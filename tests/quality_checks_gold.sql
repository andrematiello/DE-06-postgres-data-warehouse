/*
===============================================================================
Quality Checks: Gold Layer
===============================================================================
Purpose:
    Gate on the star schema. Fails loudly (RAISE EXCEPTION) on violation.
    Includes number-to-number reconciliation against silver: the gold layer
    must not create or lose a single row or unit of revenue.

Checks:
    G01  dim_customers: surrogate key unique
    G02  dim_products: surrogate key unique
    G03  fact_sales: no orphan customer_key / product_key
    G04  fact_sales row count == silver.crm_sales_details row count
    G05  fact_sales revenue == silver revenue (sum reconciliation)
===============================================================================
*/

DO $$
DECLARE
    n BIGINT;
    v_fact_rows   BIGINT;
    v_silver_rows BIGINT;
    v_fact_sum    NUMERIC;
    v_silver_sum  NUMERIC;
BEGIN
    -- G01
    SELECT count(*) INTO n FROM (
        SELECT customer_key FROM gold.dim_customers
        GROUP BY customer_key HAVING count(*) > 1
    ) x;
    IF n > 0 THEN RAISE EXCEPTION 'G01 FAIL: % duplicate customer_key in gold.dim_customers', n; END IF;
    RAISE NOTICE 'G01 PASS: customer_key unique';

    -- G02
    SELECT count(*) INTO n FROM (
        SELECT product_key FROM gold.dim_products
        GROUP BY product_key HAVING count(*) > 1
    ) x;
    IF n > 0 THEN RAISE EXCEPTION 'G02 FAIL: % duplicate product_key in gold.dim_products', n; END IF;
    RAISE NOTICE 'G02 PASS: product_key unique';

    -- G03: every fact row must resolve both dimensions
    SELECT count(*) INTO n FROM gold.fact_sales
    WHERE customer_key IS NULL OR product_key IS NULL;
    IF n > 0 THEN RAISE EXCEPTION 'G03 FAIL: % fact rows with orphan dimension keys', n; END IF;
    RAISE NOTICE 'G03 PASS: referential integrity fact -> dimensions';

    -- G04: the fact must preserve the silver grain exactly
    SELECT count(*) INTO v_fact_rows   FROM gold.fact_sales;
    SELECT count(*) INTO v_silver_rows FROM silver.crm_sales_details;
    IF v_fact_rows <> v_silver_rows THEN
        RAISE EXCEPTION 'G04 FAIL: fact has % rows, silver has %', v_fact_rows, v_silver_rows;
    END IF;
    RAISE NOTICE 'G04 PASS: fact rows = silver rows (%)', v_fact_rows;

    -- G05: revenue reconciliation between layers
    SELECT sum(sales_amount) INTO v_fact_sum   FROM gold.fact_sales;
    SELECT sum(sls_sales)    INTO v_silver_sum FROM silver.crm_sales_details;
    IF v_fact_sum IS DISTINCT FROM v_silver_sum THEN
        RAISE EXCEPTION 'G05 FAIL: fact revenue % <> silver revenue %', v_fact_sum, v_silver_sum;
    END IF;
    RAISE NOTICE 'G05 PASS: revenue reconciles across layers (%)', v_fact_sum;

    RAISE NOTICE '=== GOLD QUALITY GATE: 5 checks passed ===';
END;
$$;
