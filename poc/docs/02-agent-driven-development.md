# Agent-Driven Development — DeepSeek Agent + Multi-Agent Personas

**How this POC is built: an agentic coding assistant (DeepSeek model) drives development through specialised expert personas, against this document set as the source of truth.**

---

## 1. Objective

Use an AI agent to produce a correct, architecture-conformant POC quickly, while keeping the
human in control of decisions. The agent is **driven by the documents** in `docs/` — the documents,
not the chat history, are the contract.

## 2. Operating model

```
   ┌─────────────┐   plan    ┌──────────────┐   act    ┌────────────┐   verify   ┌───────────┐
   │ Orchestrator│ ────────▶ │ Persona      │ ───────▶ │ Artifacts  │ ─────────▶ │ Reviewer  │
   │ (DeepSeek)  │ ◀──────── │ (specialist) │ ◀─────── │ (files)    │ ◀───────── │ (critic)  │
   └─────────────┘  revise   └──────────────┘  output  └────────────┘  findings  └───────────┘
```

The loop is **plan → act → verify → revise**, and every phase reads from `docs/`.

## 3. Context provisioning (what the agent always reads first)

1. `00-goals-and-objectives.md` — what success means.
2. `01-architecture.md` — the designs and the artefact-reference rule.
3. `03-third-party-services.md` — **what not to build**.
4. The relevant persona file in `docs/agents/`.

## 4. Personas (multi-agent)

| Persona | Owns | Primary output |
|---|---|---|
| **Architect** | `01-architecture.md`, ADRs | contract map, capabilities, key designs |
| **Domain Modeler** | `domain/` | event envelope, aggregate snapshot, invariants |
| **Streaming Engineer** | topic + producer | `domain-events`, JSON producer |
| **Lakehouse Engineer** | tables + catalog | DDL, partition spec, Polaris wiring |
| **Query Engineer** | SQL | on-read + materialised retrieval |
| **Platform Engineer** | `infrastructure/` | compose, images, configs |
| **Test Engineer** | `tests/` | tests T1–T4 from the objectives |
| **Reviewer** | findings | conformance + risk report |

Each persona file defines expertise, inputs, outputs and **definition of done**. The Orchestrator
selects personas; the Reviewer never authors the artifact it reviews.

## 5. Guardrails (non-negotiable for the agent)

1. **Never hand-write Iceberg metadata** — commits happen through the catalog/connector.
2. **Reuse, don't rebuild** — if a third-party component exists (see `03-third-party-services.md`), use it.
3. **Respect the artefact-reference rule** — an artefact may reference a contract, never another artefact's internals.
4. **Document-driven** — if a design decision isn't in `docs/`, raise it before coding.
5. **Smallest correct artifact** — no speculative abstraction in a POC.

## 6. Prompt pattern (per persona)

```
ROLE:   <persona>
CONTEXT:<docs read>
TASK:   <one objective>
CONSTRAINTS: artefact-reference rule · reuse third-party · no hand-written metadata
OUTPUT: <artifact path(s)> + <verification step>
```

## 7. Handoffs

| From → To | Handoff artifact |
|---|---|
| Architect → all | `01-architecture.md` + diagrams |
| Domain Modeler → Streaming/Query | event contract |
| Streaming → Lakehouse | topic + payload schema |
| Lakehouse → Platform | table DDL + catalog config |
| Any → Reviewer | artifact + the objective it satisfies |

## 8. Definition of done

Artefact exists · conforms to the artefact-reference rule · reuses third-party components · maps to an
objective in `00-goals-and-objectives.md` · passes its verification step.
