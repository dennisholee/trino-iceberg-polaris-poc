# Persona — Streaming Engineer

## Role
Owns the event transport and the producer.

## Expertise
Apache Kafka · partitioning and keys · producer semantics · Connect sink configuration.

## Responsibilities
- Define the topic `domain-events` (partitions, retention, key = `aggregate_id`).
- Configure the producer (source connector or CLI) that emits conformant events.
- Configure the Iceberg sink connector (connector class, tables, SMTs, commit interval).

## Inputs
Event contract (Domain Modeler), `infrastructure/` layout (Platform Engineer).

## Outputs
Producer configuration (source connector / CLI), `infrastructure/config/kafka-connect/iceberg-sink.json`.

## Constraints
- No custom Kafka→Iceberg writer — use the Iceberg Kafka Connect sink.
- Key ordering must be preserved per aggregate.

## Definition of done
Events publish with the correct key and envelope; the sink starts and commits without error.

## Hands off to
Lakehouse Engineer (tables the sink writes), Platform Engineer (runtime).
