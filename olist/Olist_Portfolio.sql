/*
Olist E-commerce Analysis
SQL portfolio project analyzing delivery performance,
customer reviews, and product-category trends.
*/

-- 1. Order Status Overview
SELECT
    order_status,
    COUNT(*) AS order_count,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS percentage
FROM dbo.orders_import
GROUP BY order_status
ORDER BY order_count DESC;

-- 2. Late Delivery Performance
-- Calculate late deliveries among delivered orders.

SELECT
    COUNT(*) AS delivered_orders,

    -- Count orders delivered after the estimated date
    SUM(CASE
        WHEN order_delivered_customer_date > order_estimated_delivery_date
        THEN 1
        ELSE 0
    END) AS late_deliveries,

    -- Calculate the late-delivery percentage
    CAST(
        100.0 * SUM(CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date
            THEN 1
            ELSE 0
        END) / COUNT(*)
        AS DECIMAL(5,2)
    ) AS late_delivery_rate_pct

FROM dbo.orders_import
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;


-- 3. Review Scores by Delivery Performance
-- Compare average review scores for late and on-time/early delivered orders.
-- Join orders to reviews using the shared order_id.

SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late'
        ELSE 'On-time or early'
    END AS delivery_group,
    COUNT(*) AS reviewed_orders,
    CAST(AVG(CAST(r.review_score AS DECIMAL(10,2))) AS DECIMAL(4,2))
        AS average_review_score
FROM dbo.orders_import AS o
INNER JOIN dbo.order_reviews_import AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late'
        ELSE 'On-time or early'
    END;


-- Finding: Orders delivered late had a lower average review score
-- Late: 2.57 (7,700 reviewed orders)
-- On-time or early: 4.29 (88,653 reviewed orders)
-- This is an association, not proof of causation.


-- 4. Late Delivery Rate by Product Category
-- Compare late-delivery counts and rates by product category.
-- COUNT(DISTINCT order_id) avoids counting the same order multiple
-- times within a category if it contains multiple items.

SELECT
    p.product_category_name,
    COUNT(DISTINCT o.order_id) AS delivered_orders,

    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN o.order_id
    END) AS late_orders,

    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END)
        / NULLIF(COUNT(DISTINCT o.order_id), 0)
        AS DECIMAL(5,2)
    ) AS late_delivery_rate_pct

FROM dbo.orders_import AS o
INNER JOIN dbo.order_items_import AS oi
    ON o.order_id = oi.order_id
INNER JOIN dbo.products_import AS p
    ON oi.product_id = p.product_id

WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND p.product_category_name IS NOT NULL

GROUP BY p.product_category_name
ORDER BY late_orders DESC;

-- 5. Monthly Order Trend
-- Count orders by month based on the purchase date.

SELECT
    DATEFROMPARTS(
        YEAR(order_purchase_timestamp),
        MONTH(order_purchase_timestamp),
        1
    ) AS order_month,
    COUNT(*) AS total_orders
FROM dbo.orders_import
WHERE order_purchase_timestamp IS NOT NULL
GROUP BY
    YEAR(order_purchase_timestamp),
    MONTH(order_purchase_timestamp)
ORDER BY order_month;

-- 6. Average Delivery Time
-- Calculate the average number of days from purchase to delivery.
SELECT
    AVG(CAST(
        DATEDIFF(
            DAY,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) AS DECIMAL(10,2)
    )) AS avg_delivery_days
FROM dbo.orders_import
WHERE order_status = 'delivered'
  AND order_purchase_timestamp IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL;

  -- 7. Average Days Late
  -- Calculate the average number of days late for delivered orders.
SELECT
    AVG(CAST(
        DATEDIFF(
            DAY,
            order_estimated_delivery_date,
            order_delivered_customer_date
        ) AS DECIMAL(10,2)
    )) AS avg_days_late
FROM dbo.orders_import
WHERE order_status = 'delivered'
  AND order_delivered_customer_date > order_estimated_delivery_date
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

  -- 8. Late Delivery Rate by Product Category (minimum 500 delivered orders)
  SELECT TOP 10
    p.product_category_name,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN o.order_id
    END) AS late_orders,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END) / COUNT(DISTINCT o.order_id)
        AS DECIMAL(10,2)
    ) AS late_delivery_rate
FROM dbo.orders_import o
JOIN dbo.order_items_import oi
    ON o.order_id = oi.order_id
JOIN dbo.products_import p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY p.product_category_name
HAVING COUNT(DISTINCT o.order_id) >= 500
ORDER BY late_delivery_rate DESC;

-- 9. Estimate impact of a 2-percentage-point reduction in late deliveries
WITH DeliveredOrders AS (
    SELECT
        order_id,
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date
            THEN 1 ELSE 0
        END AS is_late
    FROM dbo.orders_import
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    COUNT(*) AS delivered_orders,
    SUM(is_late) AS late_orders,
    CAST(100.0 * SUM(is_late) / COUNT(*) AS DECIMAL(5,2))
        AS current_late_rate_pct,
    CAST(COUNT(*) * 0.02 AS INT)
        AS approx_orders_avoided_by_2pp_reduction
FROM DeliveredOrders;


GROUP BY delivery_group

-- 10. Average freight cost by delivery performance
WITH OrderFreight AS (
    SELECT
        o.order_id,
        CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
                THEN 'Late'
            ELSE 'On-time or early'
        END AS delivery_group,
        SUM(oi.freight_value) AS total_freight
    FROM dbo.orders_import AS o
    INNER JOIN dbo.order_items_import AS oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY
        o.order_id,
        CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
                THEN 'Late'
            ELSE 'On-time or early'
        END
)
SELECT
    delivery_group,
    COUNT(*) AS order_count,
    CAST(AVG(total_freight) AS DECIMAL(10,2)) AS avg_freight_per_order
FROM OrderFreight
GROUP BY delivery_group;

--11.The delivery-group query
SELECT
    COUNT(DISTINCT o.order_id) AS eligible_delivered_orders,
    COUNT(DISTINCT oi.order_id) AS eligible_orders_with_items,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN o.order_id
    END) AS eligible_late_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             AND oi.order_id IS NOT NULL
        THEN o.order_id
    END) AS late_orders_with_items
FROM dbo.orders_import AS o
LEFT JOIN dbo.order_items_import AS oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;

  -- data quality check
  SELECT
    order_status,
    COUNT(*) AS order_count
FROM dbo.orders_import
GROUP BY order_status
ORDER BY order_count DESC;

-- 12. How far actual delivery dates differ from estimated dates
SELECT
    COUNT(*) AS orders_with_both_dates,
    CAST(AVG(
        CAST(
            DATEDIFF(
                DAY,
                order_estimated_delivery_date,
                order_delivered_customer_date
            ) AS DECIMAL(10,2)
        )
    ) AS DECIMAL(10,2)) AS avg_days_vs_estimate
FROM dbo.orders_import
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;


  -- 13. Distribution of delivery gap: actual date minus estimated date
WITH DeliveryGap AS (
    SELECT
        DATEDIFF(
            DAY,
            order_estimated_delivery_date,
            order_delivered_customer_date
        ) AS gap_days
    FROM dbo.orders_import
    WHERE order_status = 'delivered'
      AND order_delivered_customer_date IS NOT NULL
      AND order_estimated_delivery_date IS NOT NULL
)
SELECT
    CASE
        WHEN gap_days < -14 THEN '15+ days early'
        WHEN gap_days BETWEEN -14 AND -8 THEN '8–14 days early'
        WHEN gap_days BETWEEN -7 AND -1 THEN '1–7 days early'
        WHEN gap_days = 0 THEN 'On estimated date'
        WHEN gap_days BETWEEN 1 AND 7 THEN '1–7 days late'
        WHEN gap_days BETWEEN 8 AND 14 THEN '8–14 days late'
        ELSE '15+ days late'
    END AS delivery_gap_group,
    COUNT(*) AS order_count
FROM DeliveryGap
GROUP BY
    CASE
        WHEN gap_days < -14 THEN '15+ days early'
        WHEN gap_days BETWEEN -14 AND -8 THEN '8–14 days early'
        WHEN gap_days BETWEEN -7 AND -1 THEN '1–7 days early'
        WHEN gap_days = 0 THEN 'On estimated date'
        WHEN gap_days BETWEEN 1 AND 7 THEN '1–7 days late'
        WHEN gap_days BETWEEN 8 AND 14 THEN '8–14 days late'
        ELSE '15+ days late'
    END
ORDER BY MIN(gap_days);

-- 14. How many late-delivery orders received low reviews?
SELECT
    COUNT(DISTINCT o.order_id) AS late_orders,
    COUNT(DISTINCT CASE
        WHEN r.review_score IN (1, 2) THEN o.order_id
    END) AS late_orders_with_low_reviews,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN r.review_score IN (1, 2) THEN o.order_id
        END) / NULLIF(COUNT(DISTINCT o.order_id), 0)
        AS DECIMAL(5,2)
    ) AS late_orders_with_low_reviews_pct
FROM dbo.orders_import AS o
LEFT JOIN dbo.order_reviews_import AS r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
  AND o.order_delivered_customer_date > o.order_estimated_delivery_date;

  -- 15. Estimate low-review late orders avoided by a 2-percentage-point reduction
WITH DeliveryImpact AS (
    SELECT
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END) AS late_orders,
        COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             AND r.review_score IN (1, 2)
            THEN o.order_id
        END) AS late_orders_with_low_reviews
    FROM dbo.orders_import AS o
    LEFT JOIN dbo.order_reviews_import AS r
        ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    delivered_orders,
    late_orders,
    late_orders_with_low_reviews,
    CAST(100.0 * late_orders_with_low_reviews
        / NULLIF(late_orders, 0) AS DECIMAL(5,2)) AS low_review_rate_among_late_pct,
    CAST(delivered_orders * 0.02 AS INT) AS estimated_late_orders_avoided,
    CAST(
        delivered_orders * 0.02
        * late_orders_with_low_reviews
        / NULLIF(late_orders, 0)
        AS INT
    ) AS estimated_low_review_late_orders_avoided
FROM DeliveryImpact;


-- 16. Which customer states have the highest late-delivery rates?
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN o.order_id
    END) AS late_orders,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END) / NULLIF(COUNT(DISTINCT o.order_id), 0)
        AS DECIMAL(5,2)
    ) AS late_delivery_rate_pct
FROM dbo.orders_import AS o
INNER JOIN dbo.customers_import AS c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(DISTINCT o.order_id) >= 500
ORDER BY late_delivery_rate_pct DESC;

-- 17. Which sellers have the highest late-delivery rates?
SELECT TOP 20
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN o.order_id
    END) AS late_orders,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END) / NULLIF(COUNT(DISTINCT o.order_id), 0)
        AS DECIMAL(5,2)
    ) AS late_delivery_rate_pct
FROM dbo.orders_import AS o
INNER JOIN dbo.order_items_import AS oi
    ON o.order_id = oi.order_id
INNER JOIN dbo.sellers_import AS s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY late_delivery_rate_pct DESC, late_orders DESC;

-- 18. Rank sellers by late-delivery rate within each state
WITH SellerRates AS (
    SELECT
        s.seller_id,
        s.seller_state,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        COUNT(DISTINCT CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN o.order_id
        END) AS late_orders,
        CAST(
            100.0 * COUNT(DISTINCT CASE
                WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
                THEN o.order_id
            END) / NULLIF(COUNT(DISTINCT o.order_id), 0)
            AS DECIMAL(5,2)
        ) AS late_delivery_rate_pct
    FROM dbo.orders_import AS o
    INNER JOIN dbo.order_items_import AS oi
        ON o.order_id = oi.order_id
    INNER JOIN dbo.sellers_import AS s
        ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY s.seller_id, s.seller_state
    HAVING COUNT(DISTINCT o.order_id) >= 100
)
SELECT
    seller_state,
    seller_id,
    delivered_orders,
    late_orders,
    late_delivery_rate_pct,
    RANK() OVER (
        PARTITION BY seller_state
        ORDER BY late_delivery_rate_pct DESC
    ) AS state_rank
FROM SellerRates
ORDER BY seller_state, state_rank;

/*
Key Finding:
Electronics had the highest late-delivery rate (9.81%) among
product categories with at least 500 delivered orders.
*/