/*
===============================================================================
Quality Checks: Silver Layer
===============================================================================
Purpose:
    Gate between silver and gold. Every check RAISES AN EXCEPTION when it
    finds violations — a check that only SELECTs problems but never fails
    is not a gate. Run with psql -v ON_ERROR_STOP=1 so the pipeline stops
    on the first failure.

Checks:
    S01  crm_cust_info: cst_id unique and not null
    S02  crm_cust_info: no untrimmed strings
    S03  crm_cust_info: marital status / gender in the allowed set
    S04  crm_prd_info: prd_id unique and not null
    S05  crm_prd_info: cost not null, not negative
    S06  crm_prd_info: product line in the allowed set
    S07  crm_prd_info: no version ends before it starts
    S08  crm_sales_details: no order after ship/due date
    S09  crm_sales_details: sales = quantity * price, all positive
    S10  erp_cust_az12: no birthdate in the future
    S11  erp_cust_az12: gender in the allowed set
    S12  erp_loc_a101: country never blank, raw codes all decoded
    S13  erp_px_cat_g1v2: no untrimmed strings
===============================================================================
*/

DO $$
DECLARE
    n BIGINT;
BEGIN
    -- S01: the CRM dedup must leave exactly one row per customer id
    SELECT count(*) INTO n FROM (
        SELECT cst_id FROM silver.crm_cust_info
        GROUP BY cst_id HAVING count(*) > 1 OR cst_id IS NULL
    ) x;
    IF n > 0 THEN RAISE EXCEPTION 'S01 FAIL: % duplicate/null cst_id in silver.crm_cust_info', n; END IF;
    RAISE NOTICE 'S01 PASS: cst_id unique and not null';

    -- S02: silver strings must be trimmed
    SELECT count(*) INTO n FROM silver.crm_cust_info
    WHERE cst_key <> TRIM(cst_key)
       OR cst_firstname <> TRIM(cst_firstname)
       OR cst_lastname  <> TRIM(cst_lastname);
    IF n > 0 THEN RAISE EXCEPTION 'S02 FAIL: % untrimmed strings in silver.crm_cust_info', n; END IF;
    RAISE NOTICE 'S02 PASS: customer strings trimmed';

    -- S03: coded values fully decoded
    SELECT count(*) INTO n FROM silver.crm_cust_info
    WHERE cst_marital_status NOT IN ('Single', 'Married', 'n/a')
       OR cst_gndr NOT IN ('Female', 'Male', 'n/a');
    IF n > 0 THEN RAISE EXCEPTION 'S03 FAIL: % rows outside allowed marital/gender sets', n; END IF;
    RAISE NOTICE 'S03 PASS: marital status and gender normalized';

    -- S04
    SELECT count(*) INTO n FROM (
        SELECT prd_id FROM silver.crm_prd_info
        GROUP BY prd_id HAVING count(*) > 1 OR prd_id IS NULL
    ) x;
    IF n > 0 THEN RAISE EXCEPTION 'S04 FAIL: % duplicate/null prd_id in silver.crm_prd_info', n; END IF;
    RAISE NOTICE 'S04 PASS: prd_id unique and not null';

    -- S05: COALESCE(cost, 0) must leave no null and the source no negative
    SELECT count(*) INTO n FROM silver.crm_prd_info
    WHERE prd_cost IS NULL OR prd_cost < 0;
    IF n > 0 THEN RAISE EXCEPTION 'S05 FAIL: % null/negative prd_cost', n; END IF;
    RAISE NOTICE 'S05 PASS: product cost complete and non-negative';

    -- S06
    SELECT count(*) INTO n FROM silver.crm_prd_info
    WHERE prd_line NOT IN ('Mountain', 'Road', 'Other Sales', 'Touring', 'n/a')
       OR prd_nm <> TRIM(prd_nm);
    IF n > 0 THEN RAISE EXCEPTION 'S06 FAIL: % rows with unmapped prd_line or untrimmed prd_nm', n; END IF;
    RAISE NOTICE 'S06 PASS: product line decoded, names trimmed';

    -- S07: the LEAD() derivation must never produce end < start
    SELECT count(*) INTO n FROM silver.crm_prd_info
    WHERE prd_end_dt < prd_start_dt;
    IF n > 0 THEN RAISE EXCEPTION 'S07 FAIL: % product versions end before they start', n; END IF;
    RAISE NOTICE 'S07 PASS: product validity windows consistent';

    -- S08
    SELECT count(*) INTO n FROM silver.crm_sales_details
    WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt;
    IF n > 0 THEN RAISE EXCEPTION 'S08 FAIL: % orders dated after their shipping/due date', n; END IF;
    RAISE NOTICE 'S08 PASS: order/ship/due dates in causal order';

    -- S09: the business rule the silver load enforces
    SELECT count(*) INTO n FROM silver.crm_sales_details
    WHERE sls_sales <> sls_quantity * sls_price
       OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
       OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0;
    IF n > 0 THEN RAISE EXCEPTION 'S09 FAIL: % rows violate sales = quantity * price (> 0)', n; END IF;
    RAISE NOTICE 'S09 PASS: sales = quantity * price holds on every row';

    -- S10
    SELECT count(*) INTO n FROM silver.erp_cust_az12 WHERE bdate > CURRENT_DATE;
    IF n > 0 THEN RAISE EXCEPTION 'S10 FAIL: % birthdates in the future', n; END IF;
    RAISE NOTICE 'S10 PASS: no future birthdates';
    -- informational only: very old birthdates are suspicious but not fixed by design
    SELECT count(*) INTO n FROM silver.erp_cust_az12 WHERE bdate < DATE '1924-01-01';
    IF n > 0 THEN RAISE NOTICE 'S10 note: % birthdates before 1924 kept as-is (flagged, not fixed)', n; END IF;

    -- S11
    SELECT count(*) INTO n FROM silver.erp_cust_az12
    WHERE gen NOT IN ('Female', 'Male', 'n/a');
    IF n > 0 THEN RAISE EXCEPTION 'S11 FAIL: % rows outside allowed gender set', n; END IF;
    RAISE NOTICE 'S11 PASS: ERP gender normalized';

    -- S12: country decoded — no blanks, no leftover ISO codes
    SELECT count(*) INTO n FROM silver.erp_loc_a101
    WHERE cntry IS NULL OR TRIM(cntry) = '' OR cntry IN ('DE', 'US', 'USA');
    IF n > 0 THEN RAISE EXCEPTION 'S12 FAIL: % rows with blank or undecoded country', n; END IF;
    RAISE NOTICE 'S12 PASS: countries decoded and complete';

    -- S13
    SELECT count(*) INTO n FROM silver.erp_px_cat_g1v2
    WHERE cat <> TRIM(cat) OR subcat <> TRIM(subcat) OR maintenance <> TRIM(maintenance);
    IF n > 0 THEN RAISE EXCEPTION 'S13 FAIL: % untrimmed strings in silver.erp_px_cat_g1v2', n; END IF;
    RAISE NOTICE 'S13 PASS: category strings trimmed';

    RAISE NOTICE '=== SILVER QUALITY GATE: 13 checks passed ===';
END;
$$;
