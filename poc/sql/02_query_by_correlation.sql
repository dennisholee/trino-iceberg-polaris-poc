-- On-read aggregate: reconstruct the business transaction from raw events.
-- No materialisation required — this is mode 1 of retrieval (see seq-04).

SELECT
  aggregate_id,
  seq,
  event_type,
  occurred_at,
  payload
FROM iceberg.poc.events
WHERE correlation_id = 'txn-456'
ORDER BY aggregate_id, seq;
