# Metadata & Data-Quality Control Plane — Options and Hybrids

**Companion to `decisions.md` (D16–D27) and `poc/docs/06-metadata-and-dq.md`.** This document compares the realistic options for metadata, data quality and API-boundary enforcement across **Trino/Iceberg** and **operational APIs**.

**Legend:** ✅ native/full · 🟡 partial/custom/integration · ❌ not supported · ➖ not applicable.

---

## 1. Problem decomposition

| ID | Capability | What “solved” means |
|---|---|---|
| **P1** | Data metadata | Tables, views, columns, owners, tags, statistics for Trino/Iceberg/Kafka |
| **P2** | API metadata | API endpoints, methods, request/response schemas, owners, SLA |
| **P3** | Trino DQ | Execute SQL checks against Iceberg/Trino; results history |
| **P4** | API DQ | Execute HTTP/OpenAPI checks against live API responses |
| **P5** | Contracts/policies | One contract model; tests linked; tags/policies; versioned |
| **P6** | Enforcement | API gate allows/degrades/blocks; audit; fail-open/closed |
| **P7** | Lineage/impact | API → service → table → topic; column-level; incident scoping |
| **P8** | POC fit | Lightweight, open, reproducible, minimal code and footprint |

**The hard truth:** no single product covers P1–P8. Gravitino excels at P1 but has no API endpoint, DQ engine or enforcement; OpenMetadata covers P1–P5 and P7 but not P6 and is heavy; DataHub covers P1/P2/P7 but native DQ/contracts are Cloud; GE covers P3/P4 but has no catalog or gate. **P6 is always an API gate/service.**

---

## 2. Master comparison

| Option | P1 Data metadata | P2 API metadata | P3 Trino DQ | P4 API DQ | P5 Contracts/policies | P6 Enforcement | P7 Lineage | P8 POC fit | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **Gravitino** | ✅ live federation; Kafka topics, no schemas | ❌ no API endpoint entity | ❌ no DQ engine | ❌ | 🟡 semantic models + custom policies, not enforced | ❌ | 🟡 OpenLineage/Spark | ✅ light | Best metadata control plane, not DQ |
| **OpenMetadata** | ✅ ingestion; Kafka schemas via Schema Registry | ✅ OpenAPI/REST connector | ✅ native tests via Trino | 🟡 DataFrame/custom HTTP | ✅ tables/topics/APIs* | 🟡 TestRunner callable, no built-in PEP | ✅ | ⚠️ heavy | Best one-stop, still needs API gate |
| **DataHub Core** | ✅ ingestion; Kafka schemas | ✅ OpenAPI source | 🟡 via ingested GE results | ❌ | 🟡 tags/policies; contracts Cloud | ❌ | ✅ strongest | ❌ very heavy | Lineage-first |
| **DataHub Cloud** | ✅ | ✅ | ✅ Assertions | 🟡 dataset assertions, not HTTP-native | ✅ Data Contracts | ❌ | ✅ | ❌ commercial | Strong if commercial OK |
| **Apache Atlas** | ✅ hooks | ❌ | ❌ | ❌ | 🟡 classification/Ranger | ❌ | ✅ | ❌ legacy/heavy | Not recommended |
| **Unity Catalog OSS** | ✅ Delta/Iceberg | ❌ | ❌ | ❌ | 🟡 grants/tags | ❌ | 🟡 limited | ❌ | Not a fit |
| **Nessie** | 🟡 Iceberg catalog only | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ➖ | Catalog versioning only |
| **Great Expectations** | ❌ | ❌ | ✅ SQL via SQLAlchemy | ✅ pandas/HTTP | ❌ | 🟡 via code | ❌ | 🟡 | DQ engine only |
| **Soda Core** | ❌ | ❌ | ✅ Trino | ❌ custom | ❌ | 🟡 via code | ❌ | 🟡 | DQ engine only |
| **Trino SQL checks** | ✅ via Trino | ❌ | ✅ | ❌ | ❌ | ❌ | 🟡 Trino lineage | ✅ simplest | DQ only |
| **Hybrid A** | ✅ Gravitino + index | 🟡 OpenAPI registry + asset catalog | ✅ Trino SQL/GE | ✅ GE/HTTP | 🟡 custom contracts/policies | ✅ API gate | 🟡 optional OpenLineage | ✅ | **Recommended POC** |
| **Hybrid B** | ✅ OpenMetadata | ✅ OpenMetadata | ✅ OpenMetadata/Trino | ✅ GE/DataFrame | ✅ OpenMetadata contracts | ✅ API gate | ✅ | ⚠️ heavy | **Recommended production** |
| **Hybrid C** | ✅ DataHub | ✅ DataHub | ✅ GE | ✅ GE | 🟡 DataHub Cloud/custom | ✅ API gate | ✅ best | ❌ very heavy | Lineage-first production |
| **Hybrid D** | ✅ Gravitino + OpenMetadata | ✅ OpenMetadata | ✅ OpenMetadata/Trino or GE | ✅ GE/DataFrame | ✅ OpenMetadata + Gravitino | ✅ API gate | ✅ | ❌ heaviest | Best-of-both, complex |
| **Managed cloud** | ✅ within cloud | 🟡 varies | ✅ | 🟡 varies | 🟡 varies | ❌ | 🟡 | ❌ lock-in | Only if managed is acceptable |

\* OpenMetadata contract quality tests are currently checked for **tables only**; API endpoint quality still needs a synthetic/API runner.

---

## 3. Metadata and contract coverage

| Option | Tables/views | Kafka topics | Kafka schemas | Iceberg/Polaris | Trino metadata | API endpoints | Contracts | Tags/glossary | Lineage | Live vs copy | Metadata audit |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Gravitino** | ✅ | ✅ | ❌ | ✅ REST proxy | ✅ | ❌ | 🟡 semantic models/custom policies | ✅ | 🟡 OpenLineage/Spark | **Live federation** | ✅ |
| **OpenMetadata** | ✅ | ✅ | ✅ Schema Registry | ✅ via Trino | ✅ | ✅ OpenAPI/REST | ✅ tables/topics/APIs | ✅ | ✅ | Copy | ✅ |
| **DataHub Core** | ✅ | ✅ | ✅ Schema Registry + inference | ✅ | ✅ | ✅ OpenAPI | 🟡 Cloud only | ✅ | ✅ | Copy | ✅ |
| **Atlas** | ✅ | ✅ hook | 🟡 hook-dependent | 🟡 hook | 🟡 | ❌ | ❌ | ✅ | ✅ | Copy | ✅ |
| **Hybrid A** | ✅ Gravitino | ✅ | ❌ | ✅ | ✅ | 🟡 OpenAPI registry + index | 🟡 custom | ✅ | 🟡 optional | Live + index | ✅ |
| **Hybrid B** | ✅ OpenMetadata | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Copy | ✅ |
| **Hybrid C** | ✅ DataHub | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 Cloud | ✅ | ✅ | Copy | ✅ |

**Key difference:** Gravitino **does not copy metadata**; OpenMetadata/DataHub ingest and store it. OpenMetadata/DataHub have first-class API endpoint models; Gravitino does not, so Hybrid A needs an OpenAPI registry and `asset_catalog`.

---

## 4. Data-quality coverage

| Option | SQL DQ (Trino) | API DQ | Built-in tests | Custom checks | Scheduling | Results history | Alerts | Incidents | DQ as code | Result API/gating | Profiling | Anomaly detection |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Gravitino** | ❌ | ❌ | ❌ | 🟡 jobs/statistics | 🟡 jobs | ❌ latest stats only | ❌ | ❌ | ❌ | 🟡 policy/stats lookup | ❌ | ❌ |
| **OpenMetadata** | ✅ | 🟡 DataFrame/custom HTTP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ TestRunner | ✅ TestRunner | ✅ | 🟡 |
| **DataHub Core** | 🟡 via GE results | ❌ | ❌ | 🟡 via GE | 🟡 external | 🟡 ingested | 🟡 Actions | ❌ | 🟡 | ❌ | ✅ | ❌ |
| **DataHub Cloud** | ✅ | 🟡 dataset assertions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | ✅ |
| **Great Expectations** | ✅ SQLAlchemy | ✅ pandas/HTTP | ✅ | ✅ | 🟡 external | ✅ Data Docs | ✅ Actions | ❌ | ✅ Python | ✅ Python API | ✅ | ❌ |
| **Soda Core** | ✅ Trino | ❌ custom | ✅ SodaCL | ✅ | 🟡 external | ✅ | ✅ Soda Cloud | 🟡 Soda Cloud | ✅ | 🟡 | ✅ | 🟡 Soda Cloud |
| **Trino SQL** | ✅ | ❌ | ❌ | ✅ SQL | 🟡 external | ✅ Iceberg | ❌ | ❌ | ✅ SQL files | 🟡 query | 🟡 | ❌ |
| **Hybrid A** | ✅ | ✅ | 🟡 GE/SQL | ✅ | 🟡 | ✅ Iceberg | 🟡 | ❌ | ✅ | ✅ | 🟡 | ❌ |
| **Hybrid B** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 |
| **Hybrid C** | ✅ | ✅ | 🟡 GE | ✅ | 🟡 | ✅ | 🟡 | 🟡 | ✅ | ✅ | ✅ | 🟡 |

**Key difference:** OpenMetadata is the only single product with native table DQ + contracts + alerts/incidents. GE is the most natural single engine for both Trino SQL and API DataFrames. Gravitino has no DQ execution layer.

---

## 5. Enforcement and operations

| Option | Native API enforcement | Policy decision API | API gateway integration | Fail-open/closed | Trino enforcement | Audit | Open source | Components | Footprint | POC fit | Production fit | Time to value |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Gravitino** | ❌ | 🟡 | 🟡 custom | ❌ | ❌ | ✅ metadata | ✅ | 1 JVM + DB | Light | ✅ | 🟡 | Fast |
| **OpenMetadata** | ❌ | 🟡 TestRunner | 🟡 custom | ❌ | ❌ | ✅ metadata | ✅ | server + DB + search | Heavy | ⚠️ | ✅ | Medium |
| **DataHub Core** | ❌ | ❌ | 🟡 custom | ❌ | ❌ | ✅ metadata | ✅ | GMS + Kafka + search + DB | Very heavy | ❌ | ✅ lineage | Slow |
| **GE/Soda** | ❌ | 🟡 Python API | 🟡 custom | ❌ | ❌ | ❌ | ✅ | Python + DB | Medium | 🟡 | 🟡 | Fast |
| **Hybrid A** | ✅ gate | ✅ custom | ✅ | ✅ | 🟡 API path | ✅ | ✅ | Gravitino + runner + gate | Light-medium | ✅ | 🟡 | Medium |
| **Hybrid B** | ✅ gate | ✅ | ✅ | ✅ | 🟡 API path | ✅ | ✅ | OM + Trino + GE + gate + search | Heavy | ❌/⚠️ | ✅ | Slower |
| **Hybrid C** | ✅ gate | ✅ | ✅ | ✅ | 🟡 API path | ✅ | ✅ | DataHub + GE + gate + search | Very heavy | ❌ | ✅ lineage | Slow |
| **Hybrid D** | ✅ gate | ✅ | ✅ | ✅ | 🟡 API path | ✅ | ✅ | Gravitino + OM + GE + gate + DB + search | Heaviest | ❌ | ✅ complex | Slow |
| **Managed cloud** | ❌ | 🟡 | 🟡 | ❌ | 🟡 IAM | ✅ | ❌ | Managed | Low ops | ❌ | ✅ lock-in | Medium |

**Key difference:** **no single product is a policy enforcement point for APIs.** Every viable solution needs an API gate/service. The metadata and DQ planes produce evidence; the gate enforces.

---

## 6. Hybrid options

| Hybrid | P1 Data metadata | P2 API metadata | P3 Trino DQ | P4 API DQ | P5 Contracts/policies | P6 Enforcement | P7 Lineage | P8 POC fit |
|---|---|---|---|---|---|---|---|---|
| **A** | Gravitino | OpenAPI registry + `asset_catalog` | Trino SQL/GE | GE/HTTP | Custom contracts/policies | API gate | Optional OpenLineage | ✅ |
| **B** | OpenMetadata | OpenMetadata | OpenMetadata/Trino | GE/DataFrame | OpenMetadata contracts | API gate | OpenMetadata | ⚠️ |
| **C** | DataHub | DataHub | GE | GE | DataHub Cloud/custom | API gate | DataHub | ❌ |
| **D** | Gravitino + OpenMetadata | OpenMetadata | OpenMetadata/Trino or GE | GE/DataFrame | OpenMetadata + Gravitino | API gate | OpenMetadata/DataHub | ❌ |

| Hybrid | How it solves the problem | Pros | Cons | Best for |
|---|---|---|---|---|
| **A** | Gravitino for data metadata; OpenAPI registry for APIs; GE/Trino for DQ; Iceberg results; API gate enforces | Light, open, preserves Polaris, fits 8–16 GB | Custom glue; API metadata not first-class; no incident UI | **POC / minimal footprint** |
| **B** | OpenMetadata unifies tables/topics/APIs/contracts; Trino/GE run DQ; gate enforces | One metadata/contract plane; native table DQ; incidents; API endpoints | Heavy; API DQ still custom; needs larger host | **Production / unified governance** |
| **C** | DataHub for metadata/lineage; GE for DQ; gate enforces | Best lineage/discovery; GE results visible | Very heavy; native assertions/contracts Cloud | **Lineage-first production** |
| **D** | Gravitino live data catalog + OpenMetadata governance/DQ/API | Best-of-both; live federation + rich governance | Two catalogs; sync/identity mapping; heaviest | **Complex enterprise** |

---

## 7. Recommendation

| If the priority is… | Choose… | Why |
|---|---|---|
| **Minimal change, POC, limited RAM** | **Hybrid A** | Only thin runner/gate code; keeps Polaris; fastest to prove |
| **Unified metadata/contracts + native DQ/incidents** | **Hybrid B** | OpenMetadata covers tables/topics/APIs; native table DQ; incidents |
| **Lineage/discovery at scale** | **Hybrid C** | DataHub strongest lineage; GE for DQ; Cloud for assertions/contracts |
| **Live federation + rich governance** | **Hybrid D** | Gravitino + OpenMetadata; accept two catalogs and sync |
| **Zero custom code** | **None** | No product enforces API DQ without a gate; use alerts/contracts and accept no runtime blocking |
| **Managed/cloud-first** | **Managed cloud** | Glue DQ/Dataplex/Purview; accept lock-in |

**POC decision:** **Hybrid A** (**D17**). **Production evaluation:** **Hybrid B** (**D25**). **P6 is always the API gate** (**D19**).

---

## 8. Decision criteria

1. **Does it cover both data and API metadata?** Gravitino: data only; OpenMetadata/DataHub: both.
2. **Does it execute DQ natively?** OpenMetadata/GE/Soda: yes; Gravitino: no.
3. **Does it enforce at the API boundary?** None; the gate does.
4. **Does it fit the POC footprint?** Gravitino/Hybrid A; OpenMetadata/DataHub are heavy.
5. **Does it preserve portability?** All are open source; managed cloud trades portability.
6. **What is the exit cost?** Gravitino/OpenAPI/Iceberg are the lowest; OpenMetadata/DataHub add a platform dependency.

---

## 9. Related

- [`decisions.md`](decisions.md) — D16–D27, O8–O15.
- [`../poc/docs/06-metadata-and-dq.md`](../poc/docs/06-metadata-and-dq.md) — POC v2 design.
- [`alternative-architectures.md`](alternative-architectures.md) — broader build-vs-buy context.
- [`consolidated-architecture.md`](consolidated-architecture.md) — data-plane baseline.