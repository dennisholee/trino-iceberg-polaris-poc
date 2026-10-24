import json
import os
import uuid
from pathlib import Path
from typing import Any

import great_expectations as gx
import pandas as pd
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

SUITES_DIR = Path(os.getenv("SUITES_DIR", "/app/suites"))


class ValidateRequest(BaseModel):
    asset_id: str
    contract_version: str
    payload: Any


def load_suites():
    suites = {}
    if SUITES_DIR.exists():
        for path in SUITES_DIR.glob("*.json"):
            suite = json.loads(path.read_text())
            suites[(suite["asset_id"], suite["contract_version"])] = suite
    return suites


SUITES = load_suites()
app = FastAPI(title="POC GE DQ service")


@app.get("/health")
def health():
    return {"status": "ok", "suite_count": len(SUITES)}


@app.post("/v1/validate")
def validate(req: ValidateRequest):
    suite = SUITES.get((req.asset_id, req.contract_version))
    if not suite:
        raise HTTPException(
            status_code=404,
            detail=f"No suite for {req.asset_id} / {req.contract_version}",
        )

    if req.payload is None:
        records = []
    elif isinstance(req.payload, list):
        records = req.payload
    else:
        records = [req.payload]

    run_id = str(uuid.uuid4())

    # An empty response cannot pass the contract. Return a deterministic failure
    # instead of letting GE raise a KeyError on an empty DataFrame.
    if not records:
        return {
            "success": False,
            "run_id": run_id,
            "asset_id": req.asset_id,
            "contract_version": req.contract_version,
            "results": [
                {
                    "success": False,
                    "expectation_config": {
                        "expectation_type": "table_row_count_min"
                    },
                    "result": {"observed_value": 0},
                }
            ],
        }

    df = pd.json_normalize(records)
    validator = gx.from_pandas(df)

    results = []
    row_min = suite.get("row_count_min")
    if row_min is not None:
        results.append(validator.expect_table_row_count_to_be_between(min_value=row_min))

    for column in suite.get("columns", []):
        name = column["name"]
        if column.get("not_null"):
            results.append(validator.expect_column_values_to_not_be_null(name))
        if column.get("unique"):
            results.append(validator.expect_column_values_to_be_unique(name))
        if "in_set" in column:
            results.append(
                validator.expect_column_values_to_be_in_set(name, column["in_set"])
            )
        if "between" in column:
            lower, upper = column["between"]
            results.append(
                validator.expect_column_values_to_be_between(
                    name, min_value=lower, max_value=upper
                )
            )

    return {
        "success": all(bool(result.success) for result in results),
        "run_id": run_id,
        "asset_id": req.asset_id,
        "contract_version": req.contract_version,
        "results": [result.to_json_dict() for result in results],
    }
