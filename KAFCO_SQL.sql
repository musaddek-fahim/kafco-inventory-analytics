-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 1: Create the core table
-- ============================================================

DROP TABLE IF EXISTS kafco_items;

CREATE TABLE kafco_items (
    item_code               VARCHAR(20)     PRIMARY KEY,
    category                VARCHAR(30)     NOT NULL,
    po_date                 DATE            NOT NULL,
    received_date           DATE            NOT NULL,
    issue_date              DATE            NOT NULL,
    quantity_received       INTEGER         NOT NULL,
    demand_rate_units_yr    NUMERIC(6,2)    NOT NULL,
    lead_time_days          INTEGER         NOT NULL,
    days_held_before_issue  INTEGER         NOT NULL
);

-- Quick sanity check after loading data (Step 1b)
-- SELECT COUNT(*) FROM kafco_items;


SELECT COUNT(*) FROM kafco_items;

-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 2: Data Integrity Checks
-- Run each block and confirm the result matches the expected value in the comment.
-- ============================================================

-- 2.1 Row count — expect 400
SELECT COUNT(*) AS total_rows FROM kafco_items;

-- 2.2 Null check on every column — expect all zeros
SELECT
    SUM(CASE WHEN item_code               IS NULL THEN 1 ELSE 0 END) AS null_item_code,
    SUM(CASE WHEN category                IS NULL THEN 1 ELSE 0 END) AS null_category,
    SUM(CASE WHEN po_date                 IS NULL THEN 1 ELSE 0 END) AS null_po_date,
    SUM(CASE WHEN received_date           IS NULL THEN 1 ELSE 0 END) AS null_received_date,
    SUM(CASE WHEN issue_date              IS NULL THEN 1 ELSE 0 END) AS null_issue_date,
    SUM(CASE WHEN quantity_received       IS NULL THEN 1 ELSE 0 END) AS null_qty,
    SUM(CASE WHEN demand_rate_units_yr    IS NULL THEN 1 ELSE 0 END) AS null_demand_rate,
    SUM(CASE WHEN lead_time_days          IS NULL THEN 1 ELSE 0 END) AS null_lead_time,
    SUM(CASE WHEN days_held_before_issue  IS NULL THEN 1 ELSE 0 END) AS null_days_held
FROM kafco_items;

-- 2.3 Duplicate item codes — expect 0 rows returned
SELECT item_code, COUNT(*)
FROM kafco_items
GROUP BY item_code
HAVING COUNT(*) > 1;

-- 2.4 Date logic: PO Date must come before Received Date — expect 0 rows returned
SELECT item_code, po_date, received_date
FROM kafco_items
WHERE received_date < po_date;

-- 2.5 Date logic: Received Date must come before or on Issue Date — expect 0 rows returned
SELECT item_code, received_date, issue_date
FROM kafco_items
WHERE issue_date < received_date;

-- 2.6 Category spelling check — expect exactly these 10 categories, no typos/variants
SELECT DISTINCT category FROM kafco_items ORDER BY category;

-- 2.7 Value sanity: quantities, demand rate, lead time must all be positive — expect 0 rows returned
SELECT item_code, quantity_received, demand_rate_units_yr, lead_time_days
FROM kafco_items
WHERE quantity_received <= 0
   OR demand_rate_units_yr <= 0
   OR lead_time_days <= 0;




-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 3: Category-Level Descriptive Stats
-- This rebuilds (and extends) your Excel Pivot_Summary sheet using SQL.
-- ============================================================

SELECT
    category,
    COUNT(*)                                   AS item_count,
    SUM(quantity_received)                     AS total_qty_received,
    ROUND(AVG(demand_rate_units_yr), 2)        AS avg_demand_rate,
    ROUND(AVG(lead_time_days), 1)              AS avg_lead_time_days,
    MIN(lead_time_days)                        AS min_lead_time_days,
    MAX(lead_time_days)                        AS max_lead_time_days,
    ROUND(STDDEV(lead_time_days), 1)           AS stddev_lead_time_days,
    ROUND(AVG(days_held_before_issue), 1)      AS avg_days_held_before_issue
FROM kafco_items
GROUP BY category
ORDER BY avg_lead_time_days DESC;


-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 4: Cycle Days View
-- Breaks each item's life into 3 measurable stages:
--   procurement_days = time from order to warehouse arrival
--   storage_days      = time sitting in the warehouse before use
--   total_cycle_days  = full PO -> Issue span
-- Saved as a VIEW so every later step can reuse it without repeating the math.
-- ============================================================

DROP VIEW IF EXISTS kafco_cycle_days;

CREATE VIEW kafco_cycle_days AS
SELECT
    item_code,
    category,
    po_date,
    received_date,
    issue_date,
    quantity_received,
    demand_rate_units_yr,
    lead_time_days,
    (received_date - po_date)      AS procurement_days,
    (issue_date - received_date)   AS storage_days,
    (issue_date - po_date)         AS total_cycle_days
FROM kafco_items;

-- Preview
SELECT * FROM kafco_cycle_days ORDER BY total_cycle_days DESC LIMIT 5;



-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 5: Consumption Velocity
--
-- Two new metrics per item:
--   days_of_supply        = how many days the received quantity would last
--                            at that item's annual demand rate
--   turnover_rate_per_year = how many times per year that order quantity
--                            gets fully consumed at the demand rate
-- Then we compare that "theoretical" pace against how long the item
-- ACTUALLY sat in the warehouse (storage_days from Step 4).
-- ============================================================

DROP VIEW IF EXISTS kafco_velocity;

CREATE VIEW kafco_velocity AS
SELECT
    item_code,
    category,
    quantity_received,
    demand_rate_units_yr,
    storage_days,
    ROUND(quantity_received / (demand_rate_units_yr / 365.0), 1)  AS days_of_supply,
    ROUND(demand_rate_units_yr / quantity_received, 3)            AS turnover_rate_per_year
FROM kafco_cycle_days;

-- Category-level velocity summary
SELECT
    category,
    ROUND(AVG(turnover_rate_per_year), 3)  AS avg_turnover_rate_per_year,
    ROUND(AVG(days_of_supply), 1)          AS avg_days_of_supply,
    ROUND(AVG(storage_days), 1)            AS avg_actual_storage_days,
    ROUND(AVG(storage_days) / AVG(days_of_supply), 2) AS velocity_gap_ratio
    -- gap ratio > 1 means items sit in the warehouse LONGER than their
    -- theoretical consumption pace would suggest (i.e. held for a future
    -- shutdown, not routine use). Close to 1 means routine, fast-cycling stock.
FROM kafco_velocity
GROUP BY category
ORDER BY velocity_gap_ratio DESC;



-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 6: Fast-Moving vs Slow-Moving Classification
--
-- We rank ALL 400 items by turnover_rate_per_year (from Step 5) and
-- split them into 3 equal-sized buckets (top third / middle third /
-- bottom third). This is a standard inventory-management technique
-- (similar in spirit to ABC analysis).
-- ============================================================

DROP VIEW IF EXISTS kafco_velocity_classified;

CREATE VIEW kafco_velocity_classified AS
WITH ranked AS (
    SELECT
        item_code,
        category,
        turnover_rate_per_year,
        NTILE(3) OVER (ORDER BY turnover_rate_per_year DESC) AS velocity_tile
    FROM kafco_velocity
)
SELECT
    item_code,
    category,
    turnover_rate_per_year,
    CASE
        WHEN velocity_tile = 1 THEN 'Fast-Moving'
        WHEN velocity_tile = 2 THEN 'Medium-Moving'
        ELSE 'Slow-Moving'
    END AS velocity_class
FROM ranked;

-- Summary: how many items per category fall into each class,
-- and what % of that category is Slow-Moving (i.e. critical, shutdown-cycle stock)
SELECT
    category,
    COUNT(*) FILTER (WHERE velocity_class = 'Fast-Moving')   AS fast_moving,
    COUNT(*) FILTER (WHERE velocity_class = 'Medium-Moving') AS medium_moving,
    COUNT(*) FILTER (WHERE velocity_class = 'Slow-Moving')   AS slow_moving,
    COUNT(*)                                                  AS total_items,
    ROUND(100.0 * COUNT(*) FILTER (WHERE velocity_class = 'Slow-Moving') / COUNT(*), 1) AS pct_slow_moving
FROM kafco_velocity_classified
GROUP BY category
ORDER BY pct_slow_moving DESC;



-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 7: Lead Time Reliability Analysis
--
-- Average lead time alone isn't enough to plan a reorder window —
-- we also need to know how UNPREDICTABLE each category's lead time is.
-- Coefficient of Variation (CoV) = stddev / average.
-- Higher CoV = less predictable supplier performance = needs a bigger
-- safety buffer in Step 8.
-- ============================================================

SELECT
    category,
    ROUND(AVG(lead_time_days), 1)                              AS avg_lead_time_days,
    MIN(lead_time_days)                                        AS min_lead_time_days,
    MAX(lead_time_days)                                        AS max_lead_time_days,
    ROUND(STDDEV(lead_time_days), 1)                           AS stddev_lead_time_days,
    ROUND(STDDEV(lead_time_days) / AVG(lead_time_days), 3)     AS coefficient_of_variation,
    RANK() OVER (ORDER BY STDDEV(lead_time_days) / AVG(lead_time_days) DESC) AS variability_rank
FROM kafco_items
GROUP BY category
ORDER BY variability_rank;


-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 8: Data-Driven Safety Buffer
--
-- Instead of guessing a flat "add 2 weeks" buffer, we calculate it from
-- each category's OWN lead time variability (stddev, from Step 7).
-- This is the standard industrial safety-stock formula:
--     Safety Buffer = Z x stddev(lead time)
-- Z = 1.65 corresponds to a 95% service level (a 95% chance the part
-- arrives on or before the buffered date) -- a common industrial default.
-- ============================================================

DROP VIEW IF EXISTS kafco_lead_time_stats;
CREATE VIEW kafco_lead_time_stats AS
SELECT
    category,
    AVG(lead_time_days)    AS avg_lead_time_days,
    STDDEV(lead_time_days) AS stddev_lead_time_days
FROM kafco_items
GROUP BY category;

DROP VIEW IF EXISTS kafco_safety_buffer;
CREATE VIEW kafco_safety_buffer AS
SELECT
    category,
    ROUND(avg_lead_time_days, 1)                    AS avg_lead_time_days,
    ROUND(stddev_lead_time_days, 1)                 AS stddev_lead_time_days,
    CEIL(1.65 * stddev_lead_time_days)::int         AS safety_buffer_days
FROM kafco_lead_time_stats
ORDER BY safety_buffer_days DESC;

SELECT * FROM kafco_safety_buffer;



-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 9: Optimal Reorder Window  (CORE DELIVERABLE)
--
-- Formula:  Reorder Date = Shutdown Date - Avg Lead Time - Safety Buffer
--
-- Target shutdown: 10-Sep-2027 (the next shutdown in KAFCO's ~3.3-3.5 year
-- cycle, per the plant's historical shutdown pattern: 2017, 2021, 2024, 2027)
-- ============================================================

DROP VIEW IF EXISTS kafco_reorder_window;
CREATE VIEW kafco_reorder_window AS
SELECT
    category,
    avg_lead_time_days,
    safety_buffer_days,
    (ROUND(avg_lead_time_days) + safety_buffer_days)::int      AS total_buffer_days,
    DATE '2027-09-10'
        - (ROUND(avg_lead_time_days)::int + safety_buffer_days) AS recommended_po_date,
    DATE '2027-09-10'                                           AS target_shutdown_date
FROM kafco_safety_buffer
ORDER BY recommended_po_date;

SELECT * FROM kafco_reorder_window;



-- ============================================================
-- KAFCO Inventory Cycle & Lifespan Analytics
-- Step 10: Final Export Views for Tableau
--
-- Two outputs, matching how Tableau dashboards are usually built:
--   1) kafco_item_detail   -> one row per item (400 rows), for drill-down
--   2) kafco_category_kpi  -> one row per category (10 rows), for headline KPIs
-- Both share the "category" column so they can be joined/blended in Tableau.
-- ============================================================

-- 1) ITEM-LEVEL DETAIL
DROP VIEW IF EXISTS kafco_item_detail;
CREATE VIEW kafco_item_detail AS
SELECT
    c.item_code,
    c.category,
    c.po_date,
    c.received_date,
    c.issue_date,
    c.quantity_received,
    c.demand_rate_units_yr,
    c.lead_time_days,
    c.procurement_days,
    c.storage_days,
    c.total_cycle_days,
    v.days_of_supply,
    v.turnover_rate_per_year,
    vc.velocity_class
FROM kafco_cycle_days c
JOIN kafco_velocity v            ON c.item_code = v.item_code
JOIN kafco_velocity_classified vc ON c.item_code = vc.item_code;

-- 2) CATEGORY-LEVEL KPI SUMMARY
DROP VIEW IF EXISTS kafco_category_kpi;
CREATE VIEW kafco_category_kpi AS
SELECT
    s.category,
    s.avg_lead_time_days,
    s.stddev_lead_time_days,
    s.safety_buffer_days,
    r.recommended_po_date,
    r.target_shutdown_date,
    cls.fast_moving,
    cls.medium_moving,
    cls.slow_moving,
    cls.total_items,
    cls.pct_slow_moving
FROM kafco_safety_buffer s
JOIN kafco_reorder_window r ON s.category = r.category
JOIN (
    SELECT
        category,
        COUNT(*) FILTER (WHERE velocity_class = 'Fast-Moving')   AS fast_moving,
        COUNT(*) FILTER (WHERE velocity_class = 'Medium-Moving') AS medium_moving,
        COUNT(*) FILTER (WHERE velocity_class = 'Slow-Moving')   AS slow_moving,
        COUNT(*)                                                  AS total_items,
        ROUND(100.0 * COUNT(*) FILTER (WHERE velocity_class = 'Slow-Moving') / COUNT(*), 1) AS pct_slow_moving
    FROM kafco_velocity_classified
    GROUP BY category
) cls ON s.category = cls.category
ORDER BY r.recommended_po_date;

-- Previews
SELECT * FROM kafco_item_detail LIMIT 5;
SELECT * FROM kafco_category_kpi;

