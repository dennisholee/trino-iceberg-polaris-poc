-- Gravitino entity store (POC v2).
-- Runs once on a fresh pg-data volume. For an existing volume, use
-- config/gravitino/bootstrap/00-init-db.sh instead (it is idempotent).
--
-- The official schema is copied verbatim from the Gravitino v1.3.1 release:
-- scripts/postgresql/schema-1.3.0-postgresql.sql
-- It is mounted as a .psql file so the Postgres entrypoint does not auto-run it twice.

SELECT 'CREATE DATABASE gravitino'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'gravitino')\gexec

\connect gravitino

CREATE SCHEMA IF NOT EXISTS gravitino;
SET search_path TO gravitino;

\i /docker-entrypoint-initdb.d/gravitino/schema-1.3.0-postgresql.psql
