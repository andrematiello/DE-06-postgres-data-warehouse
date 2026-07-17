/*
===============================================================================
Analytics: Sales Analyses over the Gold Star Schema
===============================================================================
Purpose:
    Business questions answered directly on gold — the reason the warehouse
    exists. Every query touches only gold views.
===============================================================================
*/

-- A1. Business overview: how big is this dataset, really?
SELECT
    to_char(sum(sales_amount), 'FM999,999,999')      AS total_revenue,
    count(DISTINCT order_number)                     AS orders,
    count(*)                                         AS order_lines,
    count(DISTINCT customer_key)                     AS buying_customers,
    min(order_date)                                  AS first_order,
    max(order_date)                                  AS last_order
FROM gold.fact_sales;

-- A2. Which product categories drive revenue?
SELECT
    coalesce(p.category, 'n/a')                      AS category,
    to_char(sum(f.sales_amount), 'FM999,999,999')    AS revenue,
    round(100.0 * sum(f.sales_amount) / sum(sum(f.sales_amount)) OVER (), 1)
                                                     AS revenue_pct,
    sum(f.quantity)                                  AS units
FROM gold.fact_sales f
JOIN gold.dim_products p USING (product_key)
GROUP BY 1
ORDER BY sum(f.sales_amount) DESC;

-- A3. Top 10 products by revenue
SELECT
    p.product_name,
    p.category,
    to_char(sum(f.sales_amount), 'FM999,999,999')    AS revenue,
    sum(f.quantity)                                  AS units
FROM gold.fact_sales f
JOIN gold.dim_products p USING (product_key)
GROUP BY p.product_name, p.category
ORDER BY sum(f.sales_amount) DESC
LIMIT 10;

-- A4. Revenue by customer country
SELECT
    coalesce(c.country, 'n/a')                       AS country,
    to_char(sum(f.sales_amount), 'FM999,999,999')    AS revenue,
    count(DISTINCT f.customer_key)                   AS customers,
    to_char(sum(f.sales_amount) / count(DISTINCT f.customer_key), 'FM999,999')
                                                     AS revenue_per_customer
FROM gold.fact_sales f
JOIN gold.dim_customers c USING (customer_key)
GROUP BY 1
ORDER BY sum(f.sales_amount) DESC;

-- A5. Yearly trend: is the business growing?
SELECT
    extract(year FROM order_date)::int               AS year,
    to_char(sum(sales_amount), 'FM999,999,999')      AS revenue,
    count(DISTINCT order_number)                     AS orders,
    count(DISTINCT customer_key)                     AS active_customers
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- A6. Average order value by gender and marital status (segment lens)
SELECT
    c.gender,
    c.marital_status,
    to_char(sum(f.sales_amount), 'FM999,999,999')    AS revenue,
    count(DISTINCT f.order_number)                   AS orders,
    to_char(sum(f.sales_amount)::numeric / count(DISTINCT f.order_number), 'FM999,999')
                                                     AS avg_order_value
FROM gold.fact_sales f
JOIN gold.dim_customers c USING (customer_key)
GROUP BY 1, 2
ORDER BY sum(f.sales_amount) DESC;
