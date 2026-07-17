# Data Catalog — Gold Layer

The gold layer is the consumption interface of the warehouse: a star schema with two dimensions
and one fact, exposed as views over silver. Query gold, not silver.

## gold.dim_customers

One row per customer (18,484 rows). Integrates CRM master data with ERP demographics and location.

| Column | Type | Description |
| --- | --- | --- |
| `customer_key` | bigint | Surrogate key (deterministic `ROW_NUMBER()` over `cst_id`). Join key for `fact_sales`. |
| `customer_id` | int | Business id from the CRM (`cst_id`). |
| `customer_number` | varchar | Alphanumeric CRM key (`AW…`), used to join the ERP sources. |
| `first_name` / `last_name` | varchar | Trimmed customer names. |
| `country` | varchar | From ERP locations; decoded (`US`/`USA` → `United States`, `DE` → `Germany`), `n/a` when unknown. |
| `marital_status` | varchar | `Single` · `Married` · `n/a`. |
| `gender` | varchar | `Female` · `Male` · `n/a`. CRM is the master; ERP fills gaps. |
| `birthdate` | date | From ERP; future birthdates removed as data-entry errors. |
| `create_date` | date | Customer record creation date in the CRM. |

## gold.dim_products

One row per **current** product version (295 rows; historical versions are filtered out).

| Column | Type | Description |
| --- | --- | --- |
| `product_key` | bigint | Surrogate key (deterministic `ROW_NUMBER()` over start date + product key). Join key for `fact_sales`. |
| `product_id` | int | Business id from the CRM (`prd_id`). |
| `product_number` | varchar | Product key as used by sales order lines. |
| `product_name` | varchar | Descriptive name. |
| `category_id` | varchar | First 5 chars of the raw key, normalized to the ERP format. |
| `category` / `subcategory` | varchar | From the ERP category table (`Bikes`, `Accessories`, `Clothing`). |
| `maintenance` | varchar | Whether the product requires maintenance (`Yes`/`No`). |
| `cost` | int | Standard cost; missing costs default to 0. |
| `product_line` | varchar | `Mountain` · `Road` · `Touring` · `Other Sales` · `n/a`. |
| `start_date` | date | Start of the current product version. |

## gold.fact_sales

**Grain: one row per order line** (60,398 rows). Reconciles 1:1 in rows and revenue with silver
(gates G04/G05).

| Column | Type | Description |
| --- | --- | --- |
| `order_number` | varchar | Sales order id (`SO…`); orders have 1..n lines. |
| `product_key` | bigint | FK → `dim_products.product_key`. |
| `customer_key` | bigint | FK → `dim_customers.customer_key`. |
| `order_date` | date | Order date; invalid source values (`0`, malformed) are `NULL`, never fake dates. |
| `shipping_date` / `due_date` | date | Fulfilment dates; always ≥ `order_date` (gate S08). |
| `sales_amount` | int | Line revenue. Enforced: `sales_amount = quantity × price` (gate S09). |
| `quantity` | int | Units in the line. |
| `price` | int | Unit price. |
