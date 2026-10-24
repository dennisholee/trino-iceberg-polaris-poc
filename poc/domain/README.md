# `domain/` — the event contract (stable core)

> **Documentation-only.** In this codeless slice the domain is a *specification* — the event contract and its invariants. No classes live here.

**Depends on nothing** (no Kafka, no Iceberg, no Trino). Every other layer references this contract.

## Contents

| Concept | Definition |
|---|---|
| `DomainEvent` | an immutable fact from Event Hub; envelope + domain payload |
| `Aggregate` | a consistency boundary identified by `aggregate_id` |
| `Snapshot` | the current state of an aggregate, folded from its events |
| `CorrelationId` | stitches events across aggregates (one business transaction) |

## The event envelope

| Field | Purpose |
|---|---|
| `event_id` | identity; idempotency/dedup key |
| `event_type` | selects the fold logic |
| `schema_version` | contract evolution |
| `aggregate_id` | the **fold key** (Kafka message key) |
| `correlation_id` | cross-aggregate stitch key |
| `seq` | monotonic per aggregate; ordering |
| `occurred_at` | valid/event time; drives `day(occurred_at)` partitioning |
| `payload` | the domain model (the part that evolves) |

## Invariants (the rules the rest of the system must preserve)

1. **Immutability** — events are never mutated, only appended.
2. **Ordering** — events for one `aggregate_id` are ordered by `seq`.
3. **Monotonic fold** — apply an event only if `seq > version`; guarantees idempotency and replay safety.
4. **Correlation** — all events sharing a `correlation_id` reconstruct one business transaction.
5. **Envelope stability** — only `payload` evolves; `schema_version` records breaking changes.

> There is **no code here** in this slice — the model is expressed as this contract and enforced by the binding/DDL choices.
