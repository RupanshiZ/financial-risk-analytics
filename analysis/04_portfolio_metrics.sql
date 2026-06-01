-- =============================================================================
-- 04_portfolio_metrics.sql
-- Portfolio-level health monitoring using advanced window functions.
-- Covers: rolling averages, MoM growth, NTILE deciles, concentration
-- metrics (including HHI), and multi-criteria portfolio rankings.
--
-- Table  : accepted_loans
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Monthly funded volume with MoM change and 3-month rolling average
--     Tracks book growth and seasonality.
--     LAG() for point-in-time comparison; ROWS BETWEEN for smoothing.
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', issue_d)                                 AS issue_month,
        COUNT(*)                                                     AS loans_originated,
        ROUND(SUM(funded_amnt) / 1e6,    3)                         AS volume_millions,
        ROUND(AVG(int_rate),             2)                         AS avg_int_rate,
        ROUND(AVG(fico_avg),             0)                         AS avg_fico,
        ROUND(AVG(dti),                  2)                         AS avg_dti
    FROM accepted_loans
    WHERE issue_d IS NOT NULL
    GROUP BY 1
)
SELECT
    issue_month,
    loans_originated,
    volume_millions,
    avg_int_rate,
    avg_fico,
    avg_dti,
    -- Month-on-month volume change
    LAG(volume_millions) OVER (ORDER BY issue_month)                 AS prev_month_volume,
    ROUND(
        (volume_millions - LAG(volume_millions) OVER (ORDER BY issue_month))
        * 100.0
        / NULLIF(LAG(volume_millions) OVER (ORDER BY issue_month), 0),
        2)                                                           AS volume_mom_pct,
    -- 3-month rolling average volume
    ROUND(
        AVG(volume_millions)
            OVER (ORDER BY issue_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        3)                                                           AS rolling_3m_avg_volume,
    -- 3-month rolling average interest rate
    ROUND(
        AVG(avg_int_rate)
            OVER (ORDER BY issue_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        3)                                                           AS rolling_3m_avg_rate,
    -- Running cumulative total book size
    ROUND(SUM(volume_millions) OVER (ORDER BY issue_month), 2)      AS cumulative_volume_millions
FROM monthly
ORDER BY issue_month;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Rolling monthly default rate
--     Tracks whether the portfolio is deteriorating over time.
--     Computed on resolved loans only.
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly_def AS (
    SELECT
        DATE_TRUNC('month', issue_d)                                 AS issue_month,
        COUNT(*)                                                     AS resolved_loans,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))  AS defaults
    FROM accepted_loans
    WHERE loan_status IN (
        'Fully Paid', 'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Fully Paid',
        'Does not meet the credit policy. Status:Charged Off')
      AND issue_d IS NOT NULL
    GROUP BY 1
)
SELECT
    issue_month,
    resolved_loans,
    defaults,
    ROUND(defaults * 100.0 / NULLIF(resolved_loans, 0), 3)          AS default_rate_pct,
    ROUND(
        AVG(defaults * 100.0 / NULLIF(resolved_loans, 0))
            OVER (ORDER BY issue_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
        3)                                                           AS rolling_3m_default_rate,
    CASE
        WHEN defaults * 100.0 / NULLIF(resolved_loans, 0) >
             AVG(defaults * 100.0 / NULLIF(resolved_loans, 0))
                 OVER (ORDER BY issue_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
        THEN 'Above 3m avg'
        ELSE 'Below 3m avg'
    END                                                              AS vs_3m_avg
FROM monthly_def
ORDER BY issue_month;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. DTI decile analysis — NTILE lift table
--     Ranks all resolved loans into 10 equal DTI buckets and shows
--     whether default rates increase monotonically with DTI.
-- ─────────────────────────────────────────────────────────────────────────────
WITH ranked AS (
    SELECT
        loan_status,
        funded_amnt,
        int_rate,
        dti,
        fico_avg,
        NTILE(10) OVER (ORDER BY dti ASC) AS dti_decile  -- decile 1 = lowest DTI
    FROM accepted_loans
    WHERE loan_status IN (
        'Fully Paid', 'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Fully Paid',
        'Does not meet the credit policy. Status:Charged Off')
      AND dti IS NOT NULL
)
SELECT
    dti_decile,
    COUNT(*)                                                         AS resolved_loans,
    COUNT(*) FILTER (WHERE loan_status IN (
        'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Charged Off'))      AS defaults,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(dti),         2)                                       AS avg_dti,
    ROUND(AVG(fico_avg),    0)                                       AS avg_fico,
    ROUND(AVG(int_rate),    2)                                       AS avg_int_rate,
    ROUND(AVG(funded_amnt), 0)                                       AS avg_loan_amt,
    -- Cumulative default rate from decile 1 up to this decile
    ROUND(
        SUM(COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off')))
                OVER (ORDER BY dti_decile)
        * 100.0
        / SUM(COUNT(*)) OVER (),
        2)                                                           AS cumulative_default_pct
FROM ranked
GROUP BY dti_decile
ORDER BY dti_decile;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Portfolio concentration by grade
--     Share of volume and loans in each grade bucket.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    grade,
    COUNT(*)                                                         AS total_loans,
    ROUND(SUM(funded_amnt) / 1e6, 1)                                AS volume_millions,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS loans_share_pct,
    ROUND(SUM(funded_amnt) * 100.0 / SUM(SUM(funded_amnt)) OVER (), 2) AS volume_share_pct,
    ROUND(AVG(int_rate), 2)                                          AS avg_int_rate,
    ROUND(AVG(fico_avg), 0)                                          AS avg_fico
FROM accepted_loans
WHERE grade IS NOT NULL AND grade != ''
GROUP BY grade
ORDER BY grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. State concentration + HHI
--     Herfindahl-Hirschman Index measures portfolio concentration.
--     HHI < 1500 = diversified, > 2500 = concentrated (by volume share).
-- ─────────────────────────────────────────────────────────────────────────────
WITH state_share AS (
    SELECT
        addr_state,
        COUNT(*)                                                     AS loans,
        SUM(funded_amnt)                                             AS volume,
        SUM(funded_amnt) * 100.0 / SUM(SUM(funded_amnt)) OVER ()    AS volume_share_pct
    FROM accepted_loans
    WHERE addr_state IS NOT NULL AND addr_state != ''
    GROUP BY addr_state
)
SELECT
    addr_state,
    loans,
    ROUND(volume / 1e6, 1)                                           AS volume_millions,
    ROUND(volume_share_pct, 2)                                       AS volume_share_pct,
    ROUND(volume_share_pct * volume_share_pct, 4)                    AS hhi_contribution,
    RANK() OVER (ORDER BY volume DESC)                               AS volume_rank
FROM state_share
UNION ALL
-- Summary row with total HHI
SELECT
    'TOTAL (HHI)' AS addr_state,
    SUM(loans),
    ROUND(SUM(volume) / 1e6, 1),
    100.00,
    ROUND(SUM(volume_share_pct * volume_share_pct), 2),
    NULL
FROM state_share
ORDER BY volume_rank NULLS LAST
LIMIT 21;  -- top 20 states + TOTAL row


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. Purpose concentration with risk ranking
--     RANK() by default rate alongside RANK() by volume.
-- ─────────────────────────────────────────────────────────────────────────────
WITH purpose_metrics AS (
    SELECT
        purpose,
        COUNT(*)                                                     AS total_loans,
        ROUND(SUM(funded_amnt) / 1e6, 1)                            AS volume_millions,
        ROUND(
            COUNT(*) FILTER (WHERE loan_status IN (
                'Charged Off', 'Default',
                'Does not meet the credit policy. Status:Charged Off'))
            * 100.0 / NULLIF(COUNT(*) FILTER (WHERE loan_status IN (
                'Fully Paid', 'Charged Off', 'Default',
                'Does not meet the credit policy. Status:Fully Paid',
                'Does not meet the credit policy. Status:Charged Off')), 0),
            2)                                                       AS default_rate_pct
    FROM accepted_loans
    WHERE purpose IS NOT NULL AND purpose != ''
    GROUP BY purpose
)
SELECT
    purpose,
    total_loans,
    volume_millions,
    default_rate_pct,
    ROUND(total_loans * 100.0 / SUM(total_loans) OVER (), 2)        AS loans_share_pct,
    RANK() OVER (ORDER BY default_rate_pct DESC)                    AS risk_rank,
    RANK() OVER (ORDER BY volume_millions DESC)                     AS volume_rank
FROM purpose_metrics
ORDER BY volume_rank;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. Grade × term matrix — volume and default rate
--     Shows whether pricing accounts for the term risk interaction.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    grade,
    term_months,
    COUNT(*)                                                         AS total_loans,
    ROUND(SUM(funded_amnt) / 1e6, 1)                                AS volume_millions,
    ROUND(AVG(int_rate), 2)                                          AS avg_int_rate,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / NULLIF(COUNT(*) FILTER (WHERE loan_status IN (
            'Fully Paid', 'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Fully Paid',
            'Does not meet the credit policy. Status:Charged Off')), 0),
        2)                                                           AS default_rate_pct
FROM accepted_loans
WHERE grade IS NOT NULL AND grade != ''
  AND term_months IS NOT NULL
GROUP BY grade, term_months
ORDER BY grade, term_months;
