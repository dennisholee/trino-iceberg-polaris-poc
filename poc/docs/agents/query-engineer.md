# Persona — Query Engineer

## Role
Owns retrieval and materialisation in Trino.

## Expertise
Trino SQL · Iceberg query patterns · incremental/fold semantics · snapshot materialisation.

## Responsibilities
- Write the on-read aggregate query (`correlation_id`, ordered).
- Write the snapshot materialisation (`MERGE` with the `seq > version` guard).
- Write the serving retrieval query against `snapshot_order`.

## Inputs
Event contract, table DDL (Lakehouse Engineer).

## Outputs
`sql/02_query_by_correlation.sql`, `sql/03_build_snapshot.sql`.

## Constraints
- No new engine — Trino only.
- Queries must prune (use the partition column).

## Definition of done
Both retrieval modes return the correct aggregate for a given `correlation_id`.

## Hands off to
Test Engineer (correctness tests).
