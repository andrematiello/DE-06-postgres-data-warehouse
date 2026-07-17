/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source CSVs -> Bronze)
===============================================================================
Purpose:
    Truncates every bronze table and reloads it from the CSVs with COPY.
    Truncate-and-load makes the procedure idempotent: any number of runs
    yields the same state.

Notes:
    - COPY reads server-side paths, so the datasets folder is mounted into
      the container at /data/datasets (read-only).
    - Row counts are logged from the tables themselves after each load,
      never from the client output.

Usage:
    CALL bronze.load_bronze();            -- default path /data/datasets
    CALL bronze.load_bronze('/other');    -- custom mount
===============================================================================
*/

CREATE OR REPLACE PROCEDURE bronze.load_bronze(p_src TEXT DEFAULT '/data/datasets')
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_start TIMESTAMPTZ := clock_timestamp();
    v_start       TIMESTAMPTZ;
    v_rows        BIGINT;
    v_table       TEXT;
    v_file        TEXT;
    -- table -> relative CSV path, loaded in declaration order
    v_loads CONSTANT TEXT[][] := ARRAY[
        ['bronze.crm_cust_info',    'source_crm/cust_info.csv'],
        ['bronze.crm_prd_info',     'source_crm/prd_info.csv'],
        ['bronze.crm_sales_details','source_crm/sales_details.csv'],
        ['bronze.erp_cust_az12',    'source_erp/CUST_AZ12.csv'],
        ['bronze.erp_loc_a101',     'source_erp/LOC_A101.csv'],
        ['bronze.erp_px_cat_g1v2',  'source_erp/PX_CAT_G1V2.csv']
    ];
    i INT;
BEGIN
    RAISE NOTICE '=== Loading Bronze Layer ===';

    FOR i IN 1 .. array_length(v_loads, 1) LOOP
        v_table := v_loads[i][1];
        v_file  := p_src || '/' || v_loads[i][2];
        v_start := clock_timestamp();

        EXECUTE format('TRUNCATE TABLE %s', v_table);
        EXECUTE format('COPY %s FROM %L WITH (FORMAT csv, HEADER true)', v_table, v_file);

        EXECUTE format('SELECT count(*) FROM %s', v_table) INTO v_rows;
        RAISE NOTICE '%: % rows in % ms',
            v_table, v_rows,
            round(extract(epoch FROM clock_timestamp() - v_start) * 1000);
    END LOOP;

    RAISE NOTICE '=== Bronze completed in % s ===',
        round(extract(epoch FROM clock_timestamp() - v_batch_start)::numeric, 2);
END;
$$;
