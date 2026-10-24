-- POC v2: unified asset index across data and API assets.
-- Gravitino remains the source for data tags/policies; OpenAPI is the API contract source.
-- This table is an index for the gate, not a second catalog.

CREATE TABLE IF NOT EXISTS iceberg.poc.asset_catalog (
  asset_id         varchar,
  asset_type       varchar,   -- table | topic | api
  name             varchar,
  owner            varchar,
  domain           varchar,
  tags             varchar,
  contract_id      varchar,
  contract_version varchar,
  dq_status        varchar,   -- pass | warn | fail | error | unknown | stale
  last_run_at      timestamp(6) with time zone,
  lineage_ref      varchar
);

MERGE INTO iceberg.poc.asset_catalog t
USING (
  SELECT
    'iceberg.poc.events' AS asset_id, 'table' AS asset_type, 'events' AS name,
    'orders-team' AS owner, 'orders' AS domain, 'domain=orders,pii' AS tags,
    'event-contract' AS contract_id, 'event-contract-v1' AS contract_version,
    'unknown' AS dq_status,
    CAST(NULL AS timestamp(6) with time zone) AS last_run_at,
    CAST(NULL AS varchar) AS lineage_ref
  UNION ALL
  SELECT 'iceberg.poc.snapshot_order', 'table', 'snapshot_order',
    'orders-team', 'orders', 'domain=orders,dq_tier=critical',
    'snapshot-order', 'snapshot-order-v1', 'unknown', NULL, NULL
  UNION ALL
  SELECT 'iceberg.poc.events_kafka', 'table', 'events_kafka',
    'orders-team', 'orders', 'domain=orders',
    'event-contract', 'event-contract-v1', 'unknown', NULL, NULL
  UNION ALL
  SELECT 'kafka.default.domain-events', 'topic', 'domain-events',
    'orders-team', 'orders', 'domain=orders,freshness_class=streaming',
    'event-contract', 'event-contract-v1', 'unknown', NULL, NULL
  UNION ALL
  SELECT 'GET /v1/orders/{correlationId}', 'api', 'get-order-by-correlation',
    'orders-team', 'orders', 'domain=orders,api_exposure=internal',
    'orders-api', 'orders-api-v1', 'unknown', NULL, NULL
) s
ON t.asset_id = s.asset_id
WHEN MATCHED THEN UPDATE SET
  asset_type       = s.asset_type,
  name             = s.name,
  owner            = s.owner,
  domain           = s.domain,
  tags             = s.tags,
  contract_id      = s.contract_id,
  contract_version = s.contract_version
WHEN NOT MATCHED THEN INSERT
  (asset_id, asset_type, name, owner, domain, tags, contract_id, contract_version,
   dq_status, last_run_at, lineage_ref)
  VALUES
  (s.asset_id, s.asset_type, s.name, s.owner, s.domain, s.tags, s.contract_id,
   s.contract_version, s.dq_status, s.last_run_at, s.lineage_ref);
