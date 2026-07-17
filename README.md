# 🏛️ SQL Data Warehouse on PostgreSQL — Medallion + Star Schema

> A classic SQL data warehouse built entirely in PostgreSQL: raw CRM + ERP extracts land in a
> bronze layer, are cleaned and conformed in silver by PL/pgSQL procedures, and are served as a
> Kimball star schema in gold — with 18 fail-loud quality checks between the layers.
> **One command reproduces everything:** `./run_all.sh`.

```mermaid
flowchart LR
    subgraph Sources
        CRM[CRM extracts<br/>3 CSVs]
        ERP[ERP extracts<br/>3 CSVs]
    end
    subgraph PostgreSQL 16 — Docker
        B[(bronze<br/>raw, as-is<br/>6 tables)]
        S[(silver<br/>cleansed, typed<br/>6 tables)]
        G[(gold<br/>star schema<br/>2 dims + 1 fact)]
    end
    CRM -->|COPY| B
    ERP -->|COPY| B
    B -->|"CALL silver.load_silver()<br/>PL/pgSQL cleansing"| S
    S -->|views| G
    S -.->|13 checks| QS[silver quality gate]
    G -.->|5 checks| QG[gold quality gate]
    G --> A[SQL analyses]
```

---

## 📋 Table of Contents

- [Context](#-context)
- [Business Problem](#-business-problem)
- [Architecture](#%EF%B8%8F-architecture)
- [Data](#-data)
- [The Numbers (evidence)](#-the-numbers-evidence)
- [Methodology](#-methodology)
- [Design Decisions](#-design-decisions)
- [Tech Stack](#%EF%B8%8F-tech-stack)
- [Repository Structure](#-repository-structure)
- [How to Reproduce](#%EF%B8%8F-how-to-reproduce)
- [What the Analyses Say](#-what-the-analyses-say)
- [Next Steps](#-next-steps)
- [Acknowledgments](#-acknowledgments)

---

## 🎯 Context

Before dbt and lakehouses, most analytics ran on exactly this: a relational warehouse loaded by
SQL procedures. It is still everywhere — and warehouse fundamentals (layered loading, conformed
dimensions, surrogate keys, quality gates) transfer directly to any modern stack. This project
builds that classic warehouse end-to-end in pure SQL, on PostgreSQL, with engineering discipline:
idempotent loads, declared grain, and checks that fail when they should — and it proves each of
those claims with a reproducible run.

## ❓ Business Problem

Sales data lives in two disconnected systems — a CRM (customers, products, sales transactions)
and an ERP (customer demographics, locations, product categories). Nobody can answer *"which
product categories drive revenue, by customer segment and geography?"* without manually stitching
CSV exports. The warehouse integrates both sources into one dimensional model that answers
sales-performance, customer and product questions with plain SQL.

## 🏗️ Architecture

Medallion architecture implemented as three PostgreSQL schemas in one database:

| Layer | What happens | Objects |
| --- | --- | --- |
| **bronze** | Raw CSVs loaded as-is with `COPY` (truncate-and-load, idempotent). No transformation — a faithful, auditable copy. | 6 tables |
| **silver** | `CALL silver.load_silver()` — PL/pgSQL cleansing: trim, type, dedupe, decode coded values, fix invalid dates, enforce `sales = quantity × price`. Every rule is commented with the data problem it fixes. | 6 tables + audit column |
| **gold** | Business-ready **star schema** as views: `dim_customers`, `dim_products`, `fact_sales` (grain: one row per order line), surrogate keys, CRM↔ERP integration resolved. | 3 views |
| **quality gates** | 13 silver + 5 gold checks that `RAISE EXCEPTION` on violation — the pipeline stops, the load is not "done". | 2 scripts |

## 📦 Data

Six CSV extracts from two simulated source systems (AdventureWorks-derived, MIT-licensed — see
[Acknowledgments](#-acknowledgments)):

| Source | File | Rows | Content |
| --- | --- | --- | --- |
| CRM | `cust_info.csv` | 18,494 | customers (with duplicates and padded strings) |
| CRM | `prd_info.csv` | 397 | product versions (costs missing, coded lines, broken end dates) |
| CRM | `sales_details.csv` | 60,398 | order lines (dates as 8-digit ints, inconsistent amounts) |
| ERP | `CUST_AZ12.csv` | 18,484 | demographics (legacy `NAS` id prefix, future birthdates) |
| ERP | `LOC_A101.csv` | 18,484 | locations (dashed ids, mixed country codes) |
| ERP | `PX_CAT_G1V2.csv` | 37 | product categories |

## 🔢 The Numbers (evidence)

All numbers below come from query output on the built warehouse, not from console summaries.

**Row lineage — nothing lost by accident, everything lost by rule:**

| Stage | Rows | Why |
| --- | --- | --- |
| `bronze.crm_cust_info` | 18,494 | = CSV data rows, verified per file |
| `silver.crm_cust_info` | 18,484 | −10: duplicate/null ids deduped (keep latest per `cst_id`) |
| `gold.dim_customers` | 18,484 | 1:1 with silver customers |
| `bronze.crm_prd_info` | 397 | all product versions |
| `gold.dim_products` | 295 | current versions only (`prd_end_dt IS NULL`) |
| `bronze.crm_sales_details` | 60,398 | = CSV data rows |
| `gold.fact_sales` | 60,398 | grain preserved end-to-end (gate G04) |

**Quality gates:** 13 silver checks + 5 gold checks, all passing — including revenue
reconciliation across layers (G05: gold Σ`sales_amount` = silver Σ`sls_sales` = **29,356,250**).

**Idempotency, proven:** running `CALL bronze.load_bronze()` + `CALL silver.load_silver()` a
second time yields identical counts on all 12 tables and both gates green.

**The gates actually fail:** inserting one duplicate `cst_id` into silver makes the gate abort
with `ERROR: S01 FAIL: 1 duplicate/null cst_id` — a gate that cannot fail is not a gate.

## 🔍 Methodology

Kimball dimensional modeling over medallion layering:

1. **Declare the grain first** — `fact_sales` = one row per order line — before writing any SQL.
2. **Bronze** with `COPY`, truncate-and-load, so re-runs are idempotent by construction.
3. **Silver procedures** — every cleansing rule commented with the *why*: the CRM re-inserts
   customers on update (dedupe keeps the latest), sales dates arrive as `YYYYMMDD` integers
   (0 and malformed become `NULL`, not fake dates), `sales ≠ quantity × price` gets recomputed
   from the trustworthy pair.
4. **Gold views** — surrogate keys via `ROW_NUMBER()` with deterministic ordering; CRM is the
   master for shared attributes (gender), ERP fills the gaps.
5. **Number-to-number validation between layers** — row counts and revenue sums must reconcile
   exactly (gates G04/G05), not "look right".

## 🤔 Design Decisions

- **PostgreSQL instead of SQL Server** (the original inspiration uses T-SQL): runs natively on
  Linux/Docker, zero licensing friction — and rebuilding the logic in another dialect proves
  understanding rather than transcription (`BULK INSERT`→`COPY`, `GETDATE()`→`now()`,
  `ISNULL`→`COALESCE`, dynamic `EXECUTE format()` for the data-driven bronze loader).
- **Schemas as layers** in one database instead of separate databases: cross-layer
  reconciliation queries stay trivial; isolation is by grant, not by connection.
- **Stored procedures for ETL** — deliberately classic: the point is mastering warehouse loading
  in pure SQL. Orchestrated ETL is covered elsewhere in this portfolio (Airflow in DE-01, dbt in
  AE-01).
- **Gold as views** over silver: nothing to drift out of date; materialize only if volume demands.
- **Fail-loud quality gates** (`RAISE EXCEPTION`) instead of inspection queries: with
  `ON_ERROR_STOP`, a violation stops the pipeline — checks are enforcement, not decoration.

## 🛠️ Tech Stack

| Category | Tool |
| --- | --- |
| Database | PostgreSQL 16 (Docker Compose) |
| ETL | SQL + PL/pgSQL stored procedures |
| Loading | server-side `COPY` (CSV → bronze) |
| Client / runner | psql + `run_all.sh` (bash, `ON_ERROR_STOP`) |
| Modeling | Kimball star schema over medallion layers |

## 📁 Repository Structure

```text
├── docker-compose.yml            PostgreSQL 16 + read-only dataset mount
├── run_all.sh                    one-command build: schemas → bronze → silver → gold → gates
├── datasets/
│   ├── source_crm/               cust_info, prd_info, sales_details
│   └── source_erp/               CUST_AZ12, LOC_A101, PX_CAT_G1V2
├── scripts/
│   ├── init_database.sql         bronze/silver/gold schemas
│   ├── bronze/                   ddl_bronze.sql · proc_load_bronze.sql
│   ├── silver/                   ddl_silver.sql · proc_load_silver.sql
│   ├── gold/                     ddl_gold.sql (star-schema views)
│   └── analytics/                sales_analyses.sql (business questions on gold)
├── tests/
│   ├── quality_checks_silver.sql 13 fail-loud checks (S01–S13)
│   └── quality_checks_gold.sql   5 fail-loud checks (G01–G05)
└── docs/
    └── data_catalog.md           gold layer, column by column
```

## ⚙️ How to Reproduce

Requirements: Docker with the Compose plugin. Nothing else — no local Postgres, no Python.

```bash
git clone https://github.com/andrematiello/DE-06-postgres-data-warehouse.git
cd DE-06-postgres-data-warehouse
./run_all.sh
```

The script starts the container, waits for health, builds the three layers and runs both quality
gates, stopping at the first error. Expected final line:
`==> DONE — warehouse built and both quality gates green.` Then explore:

```bash
docker compose exec warehouse psql -U dwh -d datawarehouse \
  -f - < scripts/analytics/sales_analyses.sql
```

## 📊 What the Analyses Say

From `scripts/analytics/sales_analyses.sql`, on the built warehouse:

- **29,356,250** total revenue · **27,659** orders · **18,484** buying customers ·
  orders from **2010-12-29** to **2014-01-28**.
- **Bikes are the business**: 96.5% of revenue (28.3M) from 15,205 units; Accessories move more
  than twice the units (36,112) for just 2.4% of revenue.
- Every one of the **top 10 products by revenue is a bike** — Mountain-200 and Road-150 variants
  (the leader alone: 1,373,454).
- The **United States leads in total revenue** (9.16M) but **Australia monetizes 2× better per
  customer** (2,523 vs 1,224 revenue/customer).
- **2013 is the peak year** (16.3M — more than half of all revenue), 2014 has January only.

## 🚀 Next Steps

- Incremental silver loads (change detection) instead of full refresh.
- A date dimension and slowly changing dimensions (SCD2) for product history.
- A BI dashboard over the gold views (feeds the Data Analyst track of this portfolio).

## 🙌 Acknowledgments

Architecture and source datasets from the excellent
[SQL Data Warehouse Project](https://github.com/DataWithBaraa/sql-data-warehouse-project) by
**Baraa Khatib Salkini** (Data With Baraa), MIT-licensed. This repository is an independent
rebuild on PostgreSQL — same warehouse design goals, different engine, own code and decisions
(PL/pgSQL loader, fail-loud quality gates, reconciliation checks, one-command reproduction) —
not a fork of the original T-SQL code.
