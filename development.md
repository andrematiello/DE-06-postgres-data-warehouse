# 🛤️ Development Track — SQL Data Warehouse on PostgreSQL

Step-by-step guide. Estimated time: 2-3 weeks. Study companion: the original T-SQL project lives
in the workspace at `references/sql-data-warehouse-project/` — study each layer there first, then
rebuild it in PostgreSQL **without copying**: read, close, write.

---

## Phase 0 — Study & Setup (2-3 days)

- [ ] Watch/read the original project layer by layer; take notes on *why* each cleansing rule exists
- [ ] Review the concepts: medallion architecture, Kimball star schema, surrogate vs. business keys
- [ ] `docker-compose.yml` with PostgreSQL 16 + volume; `.gitignore` from commit #1
- [ ] `scripts/init_database.sql`: database + `bronze`/`silver`/`gold` schemas
- [ ] Copy the 6 source CSVs into `datasets/` (MIT — attribution already in the README)

**Checkpoint:** `psql` connects, three empty schemas exist, container survives a restart.

## Phase 1 — Bronze (2-3 days)

- [ ] DDL: one table per CSV, columns typed as loosely as the raw data demands
- [ ] Load script with `COPY`; truncate-and-load so re-runs are idempotent
- [ ] Validate: row count per table = line count of each CSV (minus header)

**Checkpoint:** running the load twice yields identical counts — idempotency proven.

## Phase 2 — Silver (4-5 days)

- [ ] DDL for cleansed tables (+ `dwh_load_date` audit column)
- [ ] `proc_load_silver()` in PL/pgSQL: trim strings, cast types, dedupe by business key
      (keep latest), normalize coded values, handle invalid/zero dates, derive columns
- [ ] Each cleansing rule commented with the *why* (data problem it fixes)
- [ ] Validate: bronze → silver row counts reconcile; no unexpected drops

**Checkpoint:** `CALL proc_load_silver()` runs green end-to-end and is re-runnable.

## Phase 3 — Gold (3-4 days)

- [ ] Declare the grain of `fact_sales` (one row per order line) **before** writing SQL
- [ ] `dim_customers` (CRM master + ERP demographics/location), `dim_products` (current products
      + ERP categories) — surrogate keys via `ROW_NUMBER()`
- [ ] `fact_sales` joining dimensions on business keys
- [ ] Validate: fact row count vs. silver sales; no orphan keys (anti-joins return zero)

**Checkpoint:** revenue by category/segment/geography answered in one query on the star schema.

## Phase 4 — Quality Checks & Analyses (2-3 days)

- [ ] `tests/quality_checks_silver.sql` + `tests/quality_checks_gold.sql`: nulls, duplicates,
      referential integrity, value ranges — scripts that **fail loudly** (raise) when violated
- [ ] Break something on purpose and show the check catching it — evidence the gate works
- [ ] Analytical queries: customer behavior, product performance, sales trends

## Phase 5 — Publish (1-2 days)

- [ ] Architecture + data-model diagrams (draw.io) into `docs/`
- [ ] Data catalog for gold (tables, columns, meaning)
- [ ] README with real numbers **from query output** (never console summaries — D-017), screenshots
- [ ] Verify no placeholder text remains; then decide with the user about making the repo public
      and adding the site page

---

## 📚 Concepts to master

- Medallion layering: why bronze is untouched, why silver exists apart from gold
- Kimball: grain, conformed dimensions, surrogate keys, star vs. snowflake
- PL/pgSQL: procedures, exception handling, `RAISE`, transaction behavior in `CALL`
- Idempotent loading: truncate-and-load vs. incremental, and when each is right
- Dialect translation: T-SQL → PostgreSQL (`GETDATE()`→`now()`, `ISNULL`→`COALESCE`,
  `TOP`→`LIMIT`, identity vs. sequences, `BULK INSERT`→`COPY`)

## ⚠️ Common pitfalls

- Copying T-SQL and patching syntax until it runs — rebuild from the rule, not from the code
- Cleaning data in gold because silver "almost" did it — every rule belongs in silver
- Surrogate keys that shift between runs and silently break the fact joins — order deterministically
- Publishing counts read from the terminal instead of query output (the "23/23" lesson, D-017)
- Quality checks that only SELECT problems but never fail — a gate that cannot fail is not a gate
