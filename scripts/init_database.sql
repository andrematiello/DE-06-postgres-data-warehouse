/*
===============================================================================
Init: Create Warehouse Schemas
===============================================================================
Purpose:
    Creates the three medallion layers as schemas inside the 'datawarehouse'
    database (created by Docker Compose): bronze, silver, gold.

WARNING:
    Re-running this script DROPS the three schemas and everything in them.
    That is intentional: the whole warehouse rebuilds from the CSVs, so a
    from-scratch run is always possible. Do not point it at anything shared.
===============================================================================
*/

DROP SCHEMA IF EXISTS bronze CASCADE;
DROP SCHEMA IF EXISTS silver CASCADE;
DROP SCHEMA IF EXISTS gold CASCADE;

CREATE SCHEMA bronze;
CREATE SCHEMA silver;
CREATE SCHEMA gold;
