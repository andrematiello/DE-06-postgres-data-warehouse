/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Purpose:
    Truncates the silver tables and reloads them from bronze, applying every
    cleansing rule. Each rule is commented with the data problem it fixes —
    the *why*, not just the *what*. Truncate-and-load keeps the procedure
    idempotent.

Usage:
    CALL silver.load_silver();
===============================================================================
*/

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_start TIMESTAMPTZ := clock_timestamp();
    v_start       TIMESTAMPTZ;
    v_rows        BIGINT;
BEGIN
    RAISE NOTICE '=== Loading Silver Layer ===';

    ---------------------------------------------------------------------------
    -- silver.crm_cust_info
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_cust_info;
    INSERT INTO silver.crm_cust_info (
        cst_id, cst_key, cst_firstname, cst_lastname,
        cst_marital_status, cst_gndr, cst_create_date
    )
    SELECT
        cst_id,
        cst_key,
        TRIM(cst_firstname),                       -- source pads names with spaces
        TRIM(cst_lastname),
        CASE UPPER(TRIM(cst_marital_status))       -- decode S/M to readable values
            WHEN 'S' THEN 'Single'
            WHEN 'M' THEN 'Married'
            ELSE 'n/a'
        END,
        CASE UPPER(TRIM(cst_gndr))                 -- decode F/M to readable values
            WHEN 'F' THEN 'Female'
            WHEN 'M' THEN 'Male'
            ELSE 'n/a'
        END,
        cst_create_date
    FROM (
        -- the CRM re-inserts customers on update: keep only the most recent
        -- record per cst_id, drop rows with no id at all
        SELECT b.*,
               ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS rn
        FROM bronze.crm_cust_info b
        WHERE cst_id IS NOT NULL
    ) t
    WHERE rn = 1;

    SELECT count(*) INTO v_rows FROM silver.crm_cust_info;
    RAISE NOTICE 'silver.crm_cust_info: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    ---------------------------------------------------------------------------
    -- silver.crm_prd_info
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_prd_info;
    INSERT INTO silver.crm_prd_info (
        prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
    )
    SELECT
        prd_id,
        -- the first 5 chars of the raw key are the category id; the ERP
        -- category table uses '_' where the CRM uses '-'
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),
        -- from char 7 on it is the real product key (matches sales details)
        SUBSTRING(prd_key, 7),
        prd_nm,
        COALESCE(prd_cost, 0),                     -- missing cost means zero, not unknown
        CASE UPPER(TRIM(prd_line))                 -- decode product-line codes
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END,
        prd_start_dt,
        -- the raw prd_end_dt is unreliable (ends before it starts); derive it:
        -- a version ends one day before the next version of the same key starts
        LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1
    FROM bronze.crm_prd_info;

    SELECT count(*) INTO v_rows FROM silver.crm_prd_info;
    RAISE NOTICE 'silver.crm_prd_info: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    ---------------------------------------------------------------------------
    -- silver.crm_sales_details
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.crm_sales_details;
    INSERT INTO silver.crm_sales_details (
        sls_ord_num, sls_prd_key, sls_cust_id,
        sls_order_dt, sls_ship_dt, sls_due_dt,
        sls_sales, sls_quantity, sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        -- dates arrive as 8-digit integers (YYYYMMDD); 0 and malformed
        -- values become NULL instead of fake dates
        CASE WHEN sls_order_dt = 0 OR length(sls_order_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_order_dt::text, 'YYYYMMDD') END,
        CASE WHEN sls_ship_dt = 0 OR length(sls_ship_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_ship_dt::text, 'YYYYMMDD') END,
        CASE WHEN sls_due_dt = 0 OR length(sls_due_dt::text) <> 8 THEN NULL
             ELSE to_date(sls_due_dt::text, 'YYYYMMDD') END,
        -- business rule: sales = quantity * price. When sales is missing,
        -- non-positive or inconsistent, recompute it from the other two
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                  OR sls_sales <> sls_quantity * ABS(sls_price)
             THEN sls_quantity * ABS(sls_price)
             ELSE sls_sales END,
        sls_quantity,
        -- when price is missing or non-positive, derive it from sales/quantity
        CASE WHEN sls_price IS NULL OR sls_price <= 0
             THEN sls_sales / NULLIF(sls_quantity, 0)
             ELSE sls_price END
    FROM bronze.crm_sales_details;

    SELECT count(*) INTO v_rows FROM silver.crm_sales_details;
    RAISE NOTICE 'silver.crm_sales_details: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    ---------------------------------------------------------------------------
    -- silver.erp_cust_az12
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_cust_az12;
    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        -- some ids carry a legacy 'NAS' prefix that the CRM key does not have;
        -- strip it so the two systems join
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4) ELSE cid END,
        -- birthdates in the future are data-entry errors, not information
        CASE WHEN bdate > CURRENT_DATE THEN NULL ELSE bdate END,
        CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
             WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
             ELSE 'n/a'
        END                                        -- source mixes codes and words
    FROM bronze.erp_cust_az12;

    SELECT count(*) INTO v_rows FROM silver.erp_cust_az12;
    RAISE NOTICE 'silver.erp_cust_az12: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    ---------------------------------------------------------------------------
    -- silver.erp_loc_a101
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_loc_a101;
    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', ''),                     -- 'AW-00011000' vs CRM 'AW00011000'
        CASE WHEN TRIM(cntry) = 'DE'            THEN 'Germany'
             WHEN TRIM(cntry) IN ('US', 'USA')  THEN 'United States'
             WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
             ELSE TRIM(cntry)
        END                                        -- one label per country
    FROM bronze.erp_loc_a101;

    SELECT count(*) INTO v_rows FROM silver.erp_loc_a101;
    RAISE NOTICE 'silver.erp_loc_a101: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    ---------------------------------------------------------------------------
    -- silver.erp_px_cat_g1v2
    ---------------------------------------------------------------------------
    v_start := clock_timestamp();
    TRUNCATE TABLE silver.erp_px_cat_g1v2;
    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT id, cat, subcat, maintenance            -- already clean; copied for lineage
    FROM bronze.erp_px_cat_g1v2;

    SELECT count(*) INTO v_rows FROM silver.erp_px_cat_g1v2;
    RAISE NOTICE 'silver.erp_px_cat_g1v2: % rows in % ms', v_rows,
        round(extract(epoch FROM clock_timestamp() - v_start) * 1000);

    RAISE NOTICE '=== Silver completed in % s ===',
        round(extract(epoch FROM clock_timestamp() - v_batch_start)::numeric, 2);
END;
$$;
