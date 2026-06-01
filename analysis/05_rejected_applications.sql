-- =============================================================================
-- 05_rejected_applications.sql
-- Analysis of declined applications and comparison with funded loans.
-- Sheds light on Lending Club's credit policy and the gap between
-- the population that applies vs the population that gets funded.
--
-- Tables: rejected_applications, accepted_loans
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Rejected application volume over time (by year)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    EXTRACT(YEAR FROM application_date)                              AS app_year,
    COUNT(*)                                                         AS rejected_applications,
    ROUND(AVG(amount_requested), 0)                                  AS avg_requested_amount,
    ROUND(SUM(amount_requested) / 1e6, 1)                           AS total_requested_millions,
    ROUND(AVG(risk_score), 0)                                        AS avg_risk_score,
    ROUND(AVG(debt_to_income_ratio), 2)                              AS avg_dti
FROM rejected_applications
WHERE application_date IS NOT NULL
  AND amount_requested IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Requested amount distribution — percentile profile
--     What amounts are rejected applicants asking for?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                                         AS total_rejected,
    ROUND(MIN(amount_requested),     0)                              AS min_requested,
    ROUND(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY amount_requested), 0) AS p10,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY amount_requested), 0) AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY amount_requested), 0) AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY amount_requested), 0) AS p75,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY amount_requested), 0) AS p90,
    ROUND(MAX(amount_requested),     0)                              AS max_requested,
    ROUND(AVG(amount_requested),     0)                              AS mean_requested
FROM rejected_applications
WHERE amount_requested IS NOT NULL
  AND amount_requested > 0;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. Rejection volume by state — top 15 states
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    state,
    COUNT(*)                                                         AS rejected_apps,
    ROUND(AVG(amount_requested), 0)                                  AS avg_requested,
    ROUND(AVG(risk_score), 0)                                        AS avg_risk_score,
    ROUND(AVG(debt_to_income_ratio), 2)                              AS avg_dti,
    RANK() OVER (ORDER BY COUNT(*) DESC)                             AS volume_rank
FROM rejected_applications
WHERE state IS NOT NULL AND state != ''
GROUP BY state
HAVING COUNT(*) >= 10000
ORDER BY rejected_apps DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Rejections by employment length
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    employment_length,
    COUNT(*)                                                         AS rejected_apps,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS share_pct,
    ROUND(AVG(amount_requested), 0)                                  AS avg_requested,
    ROUND(AVG(risk_score), 0)                                        AS avg_risk_score,
    ROUND(AVG(debt_to_income_ratio), 2)                              AS avg_dti
FROM rejected_applications
WHERE employment_length IS NOT NULL AND employment_length != ''
GROUP BY employment_length
ORDER BY rejected_apps DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. DTI distribution among rejected applicants
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN debt_to_income_ratio < 10      THEN '01  < 10%'
        WHEN debt_to_income_ratio < 20      THEN '02 10–20%'
        WHEN debt_to_income_ratio < 30      THEN '03 20–30%'
        WHEN debt_to_income_ratio < 40      THEN '04 30–40%'
        WHEN debt_to_income_ratio < 50      THEN '05 40–50%'
        WHEN debt_to_income_ratio < 75      THEN '06 50–75%'
        ELSE                                     '07  75%+ '
    END                                                              AS dti_band,
    COUNT(*)                                                         AS rejected_apps,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS share_pct,
    ROUND(AVG(risk_score), 0)                                        AS avg_risk_score,
    ROUND(AVG(amount_requested), 0)                                  AS avg_requested
FROM rejected_applications
WHERE debt_to_income_ratio IS NOT NULL
  AND debt_to_income_ratio BETWEEN 0 AND 200  -- cap extreme values
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. Risk score (FICO) distribution among rejected applicants
--     The risk_score column is the FICO credit score for rejected borrowers.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN risk_score < 580       THEN '01 < 580 (Very Poor)'
        WHEN risk_score < 620       THEN '02 580–619 (Poor)'
        WHEN risk_score < 660       THEN '03 620–659 (Fair)'
        WHEN risk_score < 700       THEN '04 660–699 (Good)'
        WHEN risk_score < 740       THEN '05 700–739 (Very Good)'
        WHEN risk_score < 780       THEN '06 740–779 (Excellent)'
        ELSE                             '07 780+ (Exceptional)'
    END                                                              AS fico_band,
    COUNT(*)                                                         AS rejected_apps,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS share_pct,
    ROUND(AVG(risk_score), 0)                                        AS avg_risk_score,
    ROUND(AVG(debt_to_income_ratio), 2)                              AS avg_dti,
    ROUND(AVG(amount_requested), 0)                                  AS avg_requested
FROM rejected_applications
WHERE risk_score IS NOT NULL
  AND risk_score BETWEEN 300 AND 850   -- valid FICO range
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. Accepted vs rejected comparison
--     Compares the credit profiles of funded vs declined populations.
--     Uses FICO score (risk_score in rejected, fico_avg in accepted).
--     Answers: who gets through the door vs who gets turned away?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT *
FROM (
    -- Rejected applications
    SELECT
        'Rejected'                                                   AS population,
        COUNT(*)                                                     AS n,
        ROUND(AVG(risk_score), 0)                                    AS avg_fico,
        ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY risk_score), 0) AS fico_p25,
        ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY risk_score), 0) AS fico_p75,
        ROUND(AVG(amount_requested), 0)                              AS avg_requested_amount,
        ROUND(AVG(debt_to_income_ratio), 2)                          AS avg_dti,
        NULL::DOUBLE                                                 AS avg_int_rate
    FROM rejected_applications
    WHERE risk_score BETWEEN 300 AND 850
      AND amount_requested > 0

    UNION ALL

    -- Accepted (funded) loans — use fico_avg and loan_amnt
    SELECT
        'Accepted' AS population,
        COUNT(*),
        ROUND(AVG(fico_avg), 0),
        ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY fico_avg), 0),
        ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY fico_avg), 0),
        ROUND(AVG(funded_amnt), 0),
        ROUND(AVG(dti), 2),
        ROUND(AVG(int_rate), 2)
    FROM accepted_loans
    WHERE fico_avg IS NOT NULL
      AND funded_amnt IS NOT NULL
) sub
ORDER BY population DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q8. Rejection trends: rolling monthly rejection volume
--     Tracks whether LC rejection volumes changed as policy evolved.
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly_rej AS (
    SELECT
        DATE_TRUNC('month', application_date)                        AS app_month,
        COUNT(*)                                                     AS rejections,
        ROUND(AVG(amount_requested), 0)                              AS avg_requested,
        ROUND(AVG(risk_score), 0)                                    AS avg_risk_score
    FROM rejected_applications
    WHERE application_date IS NOT NULL
      AND amount_requested > 0
    GROUP BY 1
)
SELECT
    app_month,
    rejections,
    avg_requested,
    avg_risk_score,
    LAG(rejections) OVER (ORDER BY app_month)                        AS prev_month_rejections,
    ROUND(
        AVG(CAST(rejections AS DOUBLE))
            OVER (ORDER BY app_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        0)                                                           AS rolling_3m_avg_rejections
FROM monthly_rej
ORDER BY app_month;
