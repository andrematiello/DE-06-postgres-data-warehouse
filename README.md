# 🏛️ SQL Data Warehouse on PostgreSQL — Medallion + Star Schema

> A classic SQL data warehouse built entirely in PostgreSQL: raw CRM + ERP extracts land in a
> bronze layer, are cleaned and conformed in silver via PL/pgSQL procedures, and are served as a
> Kimball star schema in gold — with SQL quality checks between every layer.

![Architecture diagram — add when built]

---

## 📋 Table of Contents

- Context
- Business Problem
- Architecture
- Data
- Methodology
- Design Decisions
- Tech Stack
- Repository Structure
- How to Reproduce
- Next Steps
- Acknowledgments
- Contact

---

## 🎯 Context

Before dbt and lakehouses, most analytics ran on exactly this: a relational warehouse loaded by
SQL procedures. It is still everywhere — and warehouse fundamentals (layered loading, conformed
dimensions, surrogate keys, quality gates) transfer directly to any modern stack. This project
builds that classic warehouse end-to-end in pure SQL, on PostgreSQL, with engineering discipline:
idempotent loads, declared grain, and checks that fail when they should.

## ❓ Business Problem

Sales data lives in two disconnected systems — a CRM (customers, products, sales transactions)
and an ERP (customer demographics, locations, product categories). Nobody can answer "which
product categories drive revenue, by customer segment and geography?" without manually stitching
CSV exports. The warehouse integrates both sources into a single dimensional model that answers
sales-performance, customer-behavior and product questions with plain SQL.

## 🏗️ Architecture

Medallion architecture implemented as three PostgreSQL schemas in one database:

- **Bronze** — raw CSV extracts loaded as-is (`COPY`), one table per source file, full-refresh
  and idempotent (truncate + load). No transformation; faithful, auditable copy.
- **Silver** — cleaned and standardized tables loaded by **PL/pgSQL stored procedures**:
  trimming, type casting, deduplication, normalization of coded values (e.g. marital status,
  gender), derived columns, invalid-date handling.
- **Gold** — business-ready **star schema** exposed as views: `dim_customers`, `dim_products`,
  `fact_sales` — surrogate keys, CRM/ERP integration resolved, one row per order line.
- **Quality checks** — SQL test scripts per layer (nulls, duplicates, referential integrity,
  ranges), run after each load; the load is not "done" until the checks pass.

## 📦 Data

Source extracts: 6 CSV files from two simulated systems (CRM: customer info, product info, sales
details; ERP: customer demographics, locations, product categories), from the original project's
MIT-licensed datasets (see Acknowledgments).

**Open decision (revisit at build time):** swap the tutorial datasets for the Olist Brazilian
e-commerce dataset (Kaggle) to connect this warehouse to the portfolio's shared data narrative.

## 🔍 Methodology

Kimball dimensional modeling over a medallion layering:

1. **Declare the grain first** — `fact_sales` = one row per order line — before writing any SQL.
2. **Bronze ingestion** with `COPY`, truncate-and-load, so re-runs are idempotent.
3. **Silver procedures** — one `proc_load_silver()` orchestrating per-table cleansing steps, each
   documented with the rule it enforces (why, not just what).
4. **Gold views** — dimensions with surrogate keys (`ROW_NUMBER()`), fact joined on business
   keys; CRM is the master for shared attributes, ERP enriches.
5. **Row-count and integrity validation between layers** — numbers published in this README will
   come from query output, never from a console summary (workspace rule D-017).

## 🤔 Design Decisions

- **PostgreSQL instead of SQL Server** (the original uses T-SQL): runs natively on Linux/Docker,
  zero licensing friction, and rebuilding the logic in another dialect proves understanding
  rather than transcription.
- **Schemas as layers** (`bronze`/`silver`/`gold` in one database) instead of separate databases:
  cross-layer validation queries stay trivial; isolation is by grant, not by connection.
- **Stored procedures for ETL** — deliberately classic: the point of this project is mastering
  warehouse loading in pure SQL; orchestration-tool ETL is covered by DE-01, dbt ELT by AE-01.
- **Gold as views** over silver: cheap to rebuild, no load step to drift; materialize only if
  volume demands it.
- **Quality checks as versioned SQL scripts** run per layer — tests that fail when they should.

## 🛠️ Tech Stack

| Category | Tool |
| --- | --- |
| Database | PostgreSQL 16 (Docker Compose) |
| ETL | SQL + PL/pgSQL stored procedures |
| Loading | `COPY` (CSV → bronze) |
| Client | psql |
| Diagrams | draw.io |

## 📁 Repository Structure

- `datasets/` — source CRM + ERP CSV extracts
- `docker-compose.yml` — PostgreSQL 16
- `scripts/init_database.sql` — database + `bronze`/`silver`/`gold` schemas
- `scripts/bronze/` — DDL + load script
- `scripts/silver/` — DDL + `proc_load_silver` procedures
- `scripts/gold/` — star-schema views
- `tests/` — quality checks per layer
- `docs/` — architecture and data-model diagrams, data catalog

## ⚙️ How to Reproduce

1. Clone the repository.
2. `docker compose up -d` — starts PostgreSQL 16.
3. Run `scripts/init_database.sql`, then bronze → silver → gold scripts in order.
4. Run the quality checks in `tests/` — all must pass.
5. Query the gold views for the sales analyses.

## 🚀 Next Steps

- Analytical SQL layer over gold (customer behavior, product performance, sales trends).
- Incremental silver loads (change detection) instead of full refresh.
- A BI dashboard over the gold views (feeds the DA track).

## 🙌 Acknowledgments

Architecture and source datasets inspired by the
[SQL Data Warehouse Project](https://github.com/DataWithBaraa/sql-data-warehouse-project) by
**Baraa Khatib Salkini** (Data With Baraa), MIT-licensed. This repository is an independent
rebuild on PostgreSQL with its own design decisions — not a fork of the original T-SQL code.

## 📬 Contact

LinkedIn | Portfolio | Email
