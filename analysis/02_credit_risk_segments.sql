-- =============================================================================
-- 02_credit_risk_segments.sql
-- Risk segmentation by borrower attributes: DTI, FICO, income, interest rate,
-- loan amount, combined high-risk scoring, and state-level analysis.
--
-- Table  : accepted_loans
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Default rate by DTI band
--     At what DTI does default risk accelerate? Informs underwriting thresholds.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN dti < 5           THEN '01  < 5%'
        WHEN dti < 10          THEN '02  5–10%'
        WHEN dti < 15          THEN '03 10–15%'
        WHEN dti < 20          THEN '04 15–20%'
        WHEN dti < 25          THEN '05 20–25%'
        WHEN dti < 30          THEN '06 25–30%'
        WHEN dti < 35          THEN '07 30–35%'
        ELSE                        '08  35%+ '
    END                                                              AS dti_band,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate),   2)                                        AS avg_int_rate,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico,
    ROUND(AVG(annual_inc), 0)                                        AS avg_income
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND dti IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Default rate by FICO band
--     Does FICO rank-order default risk monotonically?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN fico_avg < 600    THEN '01 < 600'
        WHEN fico_avg < 620    THEN '02 600–619'
        WHEN fico_avg < 640    THEN '03 620–639'
        WHEN fico_avg < 660    THEN '04 640–659'
        WHEN fico_avg < 680    THEN '05 660–679'
        WHEN fico_avg < 700    THEN '06 680–699'
        WHEN fico_avg < 720    THEN '07 700–719'
        WHEN fico_avg < 740    THEN '08 720–739'
        WHEN fico_avg < 760    THEN '09 740–759'
        WHEN fico_avg < 780    THEN '10 760–779'
        WHEN fico_avg < 800    THEN '11 780–799'
        ELSE                        '12 800+ '
    END                                                              AS fico_band,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate),  2)                                         AS avg_int_rate,
    ROUND(AVG(dti),       2)                                         AS avg_dti,
    ROUND(AVG(funded_amnt),0)                                        AS avg_loan_amt
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND fico_avg IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. Default rate by annual income band
--     Does higher income reliably reduce default risk?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN annual_inc < 30000        THEN '01 < $30k'
        WHEN annual_inc < 50000        THEN '02 $30–50k'
        WHEN annual_inc < 75000        THEN '03 $50–75k'
        WHEN annual_inc < 100000       THEN '04 $75–100k'
        WHEN annual_inc < 150000       THEN '05 $100–150k'
        WHEN annual_inc < 250000       THEN '06 $150–250k'
        ELSE                                '07 $250k+ '
    END                                                              AS income_band,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(funded_amnt), 0)                                       AS avg_loan_amt,
    ROUND(AVG(dti),         2)                                       AS avg_dti,
    ROUND(AVG(fico_avg),    0)                                       AS avg_fico
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND annual_inc IS NOT NULL
  AND annual_inc BETWEEN 1 AND 3000000   -- cap extreme outliers
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Default rate by interest rate band
--     Is interest rate priced proportionally to realised default risk?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN int_rate < 8      THEN '01 < 8%'
        WHEN int_rate < 11     THEN '02  8–11%'
        WHEN int_rate < 14     THEN '03 11–14%'
        WHEN int_rate < 17     THEN '04 14–17%'
        WHEN int_rate < 20     THEN '05 17–20%'
        WHEN int_rate < 24     THEN '06 20–24%'
        ELSE                        '07 24%+ '
    END                                                              AS rate_band,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico,
    ROUND(AVG(dti),        2)                                        AS avg_dti,
    ROUND(AVG(funded_amnt),0)                                        AS avg_loan_amt
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND int_rate IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. Default rate by loan amount band
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN funded_amnt < 5000       THEN '01 < $5k'
        WHEN funded_amnt < 10000      THEN '02 $5–10k'
        WHEN funded_amnt < 15000      THEN '03 $10–15k'
        WHEN funded_amnt < 20000      THEN '04 $15–20k'
        WHEN funded_amnt < 25000      THEN '05 $20–25k'
        WHEN funded_amnt < 30000      THEN '06 $25–30k'
        ELSE                               '07 $30k+ '
    END                                                              AS amount_band,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate),  2)                                         AS avg_int_rate,
    ROUND(AVG(fico_avg),  0)                                         AS avg_fico,
    ROUND(AVG(term_months),0)                                        AS avg_term_months
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND funded_amnt IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. High-risk segment identification (multi-criteria scoring)
--     Defines a high-risk flag based on three independent risk signals:
--     grade (E, F or G), DTI > 25%, FICO < 660.
--     Useful for understanding where portfolio risk concentrates.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN grade IN ('E','F','G') AND dti > 25 AND fico_avg < 660
        THEN 'Triple-flag: grade E-G, DTI>25, FICO<660'
        WHEN grade IN ('E','F','G') AND dti > 25
        THEN 'Dual-flag: grade E-G + DTI>25'
        WHEN grade IN ('E','F','G') AND fico_avg < 660
        THEN 'Dual-flag: grade E-G + FICO<660'
        WHEN dti > 25 AND fico_avg < 660
        THEN 'Dual-flag: DTI>25 + FICO<660'
        WHEN grade IN ('E','F','G')
        THEN 'Single-flag: grade E-G only'
        WHEN dti > 25
        THEN 'Single-flag: high DTI only'
        WHEN fico_avg < 660
        THEN 'Single-flag: low FICO only'
        ELSE 'No flags'
    END                                                              AS risk_segment,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(SUM(funded_amnt) / 1e6, 1)                                AS volume_millions
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND grade IS NOT NULL AND grade != ''
  AND dti IS NOT NULL
  AND fico_avg IS NOT NULL
GROUP BY 1
ORDER BY default_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. State-level default analysis — top 15 states by volume
--     RANK() window function to order by default rate within the result set.
-- ─────────────────────────────────────────────────────────────────────────────
WITH state_risk AS (
    SELECT
        addr_state,
        COUNT(*)                                                     AS resolved_loans,
        ROUND(SUM(funded_amnt) / 1e6, 1)                            AS volume_millions,
        ROUND(
            COUNT(*) FILTER (WHERE loan_status IN (
                'Charged Off', 'Default',
                'Does not meet the credit policy. Status:Charged Off'))
            * 100.0 / COUNT(*), 2)                                   AS default_rate_pct,
        ROUND(AVG(fico_avg),  0)                                     AS avg_fico,
        ROUND(AVG(int_rate),  2)                                     AS avg_int_rate,
        ROUND(AVG(dti),       2)                                     AS avg_dti
    FROM accepted_loans
    WHERE loan_status IN (
        'Fully Paid', 'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Fully Paid',
        'Does not meet the credit policy. Status:Charged Off')
      AND addr_state IS NOT NULL AND addr_state != ''
    GROUP BY addr_state
    HAVING COUNT(*) >= 1000
)
SELECT
    addr_state,
    resolved_loans,
    volume_millions,
    default_rate_pct,
    avg_fico,
    avg_int_rate,
    avg_dti,
    RANK() OVER (ORDER BY default_rate_pct DESC) AS risk_rank,
    RANK() OVER (ORDER BY volume_millions DESC)  AS volume_rank
FROM state_risk
ORDER BY default_rate_pct DESC
LIMIT 15;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q8. Employment length vs default rate
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    emp_length,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(annual_inc), 0)                                        AS avg_income,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND emp_length NOT IN ('', 'n/a')
GROUP BY emp_length
ORDER BY default_rate_pct DESC;
