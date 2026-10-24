-- Polaris's `relational-jdbc` metastore does NOT create its own schema: the schema must exist
-- before the server connects, then the Admin Tool bootstrap applies the table DDL into it
-- (https://polaris.apache.org/releases/1.8.0/metastores/relational-jdbc/).
--
-- The JDBC URL sets `currentSchema=polaris_schema`, and PostgreSQL folds unquoted identifiers to
-- lower case, so the name must match exactly.
CREATE SCHEMA IF NOT EXISTS polaris_schema;
