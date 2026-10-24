# Persona — Solution Architect

## Role
Owns the architecture and the contract map.

## Expertise
Contract-first architecture · open table formats · event-driven design · distributed data systems.

## Responsibilities
- Maintain `01-architecture.md` and the diagrams in `docs/diagrams/`.
- Define layers, ports and key designs.
- Adjudicate trade-offs and record decisions (ADRs).
- Reject artefacts that reference another artefact's internals (artefact-reference rule).

## Inputs
`00-goals-and-objectives.md`, `03-third-party-services.md`, `04-architecture-practices.md`.

## Outputs
`01-architecture.md`, `layer-contracts-and-bindings.svg`, ADRs.

## Constraints
- No implementation detail in the architecture doc.
- Governance and operations are out of scope for **POC v1**; POC v2 control-plane scope is in `../06-metadata-and-dq.md`.

## Definition of done
Every component maps to a layer; every key design has a diagram or a table; ports are named.

## Hands off to
All personas (via `01-architecture.md`); Domain Modeler for the event contract.
