#!/usr/bin/env bash
# End-to-end warehouse build: schemas -> bronze -> silver -> gold -> quality gates.
# Stops at the first error (ON_ERROR_STOP). Safe to re-run: every load is
# truncate-and-load and every DDL drops before creating.
set -euo pipefail
cd "$(dirname "$0")"

PSQL(){ docker compose exec -T warehouse psql -U dwh -d datawarehouse -v ON_ERROR_STOP=1 "$@"; }

echo "==> Waiting for PostgreSQL to be healthy"
docker compose up -d
until docker compose exec -T warehouse pg_isready -U dwh -d datawarehouse -q; do sleep 1; done

echo "==> 1/6 Schemas"
PSQL -f - < scripts/init_database.sql

echo "==> 2/6 Bronze"
PSQL -f - < scripts/bronze/ddl_bronze.sql
PSQL -f - < scripts/bronze/proc_load_bronze.sql
PSQL -c "CALL bronze.load_bronze();"

echo "==> 3/6 Silver"
PSQL -f - < scripts/silver/ddl_silver.sql
PSQL -f - < scripts/silver/proc_load_silver.sql
PSQL -c "CALL silver.load_silver();"

echo "==> 4/6 Gold"
PSQL -f - < scripts/gold/ddl_gold.sql

echo "==> 5/6 Quality gate: silver"
PSQL -f - < tests/quality_checks_silver.sql

echo "==> 6/6 Quality gate: gold"
PSQL -f - < tests/quality_checks_gold.sql

echo "==> DONE — warehouse built and both quality gates green."
