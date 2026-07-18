# 🛤️ Development Track: SQL Data Warehouse on PostgreSQL

Built 2026-07-17, end-to-end in one session. Study companion: the original T-SQL project lives in
the workspace at `references/sql-data-warehouse-project/`. Each layer was studied there first,
then rebuilt in PostgreSQL (read, close, write, not copy-and-patch).

---

## Phase 0: Study & Setup ✅

- [x] Read the original project layer by layer; noted *why* each cleansing rule exists
- [x] Concepts reviewed: medallion architecture, Kimball star schema, surrogate vs. business keys
- [x] `docker-compose.yml` with PostgreSQL 16 + named volume; `.gitignore` from commit #1
- [x] `scripts/init_database.sql`: `bronze`/`silver`/`gold` schemas (drop-and-recreate)
- [x] 6 source CSVs in `datasets/` (MIT, attributed in the README)

**Checkpoint met:** psql connects, three schemas exist, container survives restart.

## Phase 1: Bronze ✅

- [x] DDL: one table per CSV, loosely typed (sales dates stay 8-digit INTs, raw is raw)
- [x] `bronze.load_bronze(p_src)`: data-driven loop, `TRUNCATE` + dynamic `COPY` per table
- [x] Validated: bronze counts = CSV data-row counts on all 6 files
      (18,494 · 397 · 60,398 · 18,484 · 18,484 · 37)

**Checkpoint met:** second run yields identical counts, proving idempotency.

## Phase 2: Silver ✅

- [x] DDL with `dwh_create_date TIMESTAMPTZ DEFAULT now()` audit column
- [x] `silver.load_silver()`: trim, decode S/M → Single/Married etc., dedupe customers
      (keep latest per `cst_id`), split product key into `cat_id` + `prd_key`, derive
      `prd_end_dt` via `LEAD()`, convert YYYYMMDD ints to dates (invalid → NULL),
      enforce `sales = quantity × price`
- [x] Every rule commented with the data problem it fixes
- [x] Validated: 18,494 → 18,484 customers (10 dupes/nulls dropped by rule); other counts 1:1

**Checkpoint met:** `CALL silver.load_silver()` green end-to-end and re-runnable.

## Phase 3: Gold ✅

- [x] Grain declared before SQL: `fact_sales` = one row per order line
- [x] `dim_customers` (CRM master + ERP demographics/location), `dim_products` (current
      versions only, 295 of 397), with surrogate keys via deterministic `ROW_NUMBER()`
- [x] `fact_sales` joins on business keys
- [x] Validated: 60,398 fact rows = silver rows; zero orphan keys (gate G03)

**Checkpoint met:** revenue by category/segment/geography answered in one query.

## Phase 4: Quality Checks & Analyses ✅

- [x] 13 silver checks (S01–S13) + 5 gold checks (G01–G05), all `RAISE EXCEPTION` on violation
- [x] Broke it on purpose: injected a duplicate `cst_id` → gate aborted with
      `ERROR: S01 FAIL: 1 duplicate/null cst_id` → reloaded silver → green again
- [x] Reconciliation across layers: rows (G04) and revenue Σ 29,356,250 (G05)
- [x] `scripts/analytics/sales_analyses.sql`: 6 business questions answered on gold

## Phase 5: Publish ✅

- [x] Data catalog for gold (`docs/data_catalog.md`)
- [x] Architecture as mermaid in the README (renders on GitHub)
- [x] README numbers taken from query output, never console summaries (workspace rule D-017)
- [x] Clean-reproduction check: `docker compose down -v` → `./run_all.sh` → both gates green
- [x] No secrets: the only credential is the local-only Docker demo password in compose

---

## 📚 Concepts exercised

- Medallion layering: why bronze stays untouched, why silver exists apart from gold
- Kimball: grain, conformed dimensions, surrogate keys, current-version dimensions
- PL/pgSQL: procedures, dynamic SQL (`EXECUTE format()`), `RAISE NOTICE/EXCEPTION`,
  `clock_timestamp()` for in-transaction timing
- Idempotent loading: truncate-and-load; when incremental would be the next step
- Dialect translation done from the rule, not the code: `BULK INSERT`→`COPY`,
  `GETDATE()`→`now()`/`CURRENT_DATE`, `ISNULL`→`COALESCE`, `LEN`→`length`,
  `CAST(int AS varchar)`→`to_date(int::text,'YYYYMMDD')`

## ⚠️ Pitfalls hit or avoided

- `wc -l` undercounts CSV rows when the file has no trailing newline. Bronze validation
  compared against corrected counts (the DB was right, the first shell count was wrong)
- Quality checks that only SELECT problems never stop a pipeline. Every check here raises,
  and `ON_ERROR_STOP` turns a violation into a hard stop
- Surrogate keys from `ROW_NUMBER()` must order by something deterministic, or keys shift
  between rebuilds and silently break fact joins
- `NOTICE: table does not exist, skipping` on first run is expected (`DROP TABLE IF EXISTS`),
  not an error; reading logs carefully beats grepping for any "does not exist"
