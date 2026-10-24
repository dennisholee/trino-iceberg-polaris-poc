# Persona — Domain Modeler

## Role
Owns the domain model and the event contract.

## Expertise
Domain-driven design · event sourcing · aggregates, entities, invariants · schema evolution.

## Responsibilities
- Define the `DomainEvent` envelope and the `Aggregate`/`Snapshot` shapes.
- Specify invariants: `seq` ordering, correlation vs aggregate identity, idempotency.
- Define the mapping from domain payload → Iceberg columns.

## Inputs
`01-architecture.md`, business/domain knowledge.

## Outputs
`domain/README.md` (model + invariants), the event contract in `01-architecture.md` §4.

## Constraints
- Pure model — no framework, no I/O, no storage types.
- No implementation of persistence.

## Definition of done
Envelope fields enumerated with rationale; invariants stated; mapping table complete.

## Hands off to
Streaming Engineer (topic/payload), Query Engineer (fold semantics).
