-- =============================================================================
-- 03_vintage_cohort_analysis.sql
-- Vintage analysis: how do cohorts of loans issued in the same period
-- perform as they age?  Tracks whether credit quality improved or
-- deteriorated over the 2007–2018 LC lending cycle.
--
-- Table  : accepted_loans
-- Key concept: "vintage" = all loans issued in the same month or quarter.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Issue-year vintage summary
--     Cumulative default rate for each year's cohort of loans.
--     Older vintages have fully resolved; recent vintages are still maturing.
-- ─────────────────────────────────────────────────────────────────────────────
WITH yearly AS (
    SELECT
        EXTRACT(YEAR FROM issue_d)                                   AS issue_year,
        COUNT(*)                                                     AS total_loans,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Fully Paid', 'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Fully Paid',
            'Does not meet the credit policy. Status:Charged Off'))  AS resolved_loans,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))  AS defaults,
        ROUND(SUM(funded_amnt) / 1e9, 3)                            AS volume_billions,
        ROUND(AVG(int_rate),   2)                                    AS avg_int_rate,
        ROUND(AVG(fico_avg),   0)                                    AS avg_fico,
        ROUND(AVG(dti),        2)                                    AS avg_dti
    FROM accepted_loans
    WHERE issue_d IS NOT NULL
    GROUP BY 1
)
SELECT
    issue_year,
    total_loans,
    resolved_loans,
    defaults,
    ROUND(defaults * 100.0 / NULLIF(resolved_loans, 0), 2)          AS default_rate_pct,
    volume_billions,
    avg_int_rate,
    avg_fico,
    avg_dti,
    -- YoY volume growth using LAG
    LAG(volume_billions) OVER (ORDER BY issue_year)                  AS prev_year_volume,
    ROUND(
        (volume_billions - LAG(volume_billions) OVER (ORDER BY issue_year))
        * 100.0
        / NULLIF(LAG(volume_billions) OVER (ORDER BY issue_year), 0),
        2)                                                           AS volume_yoy_pct
FROM yearly
ORDER BY issue_year;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Issue-quarter cohort performance
--     Finer vintage granularity; QoQ volume change via LAG.
-- ─────────────────────────────────────────────────────────────────────────────
WITH quarterly AS (
    SELECT
        DATE_TRUNC('quarter', issue_d)                               AS issue_quarter,
        COUNT(*)                                                     AS total_loans,
        ROUND(SUM(funded_amnt) / 1e6, 2)                            AS volume_millions,
        ROUND(AVG(int_rate), 2)                                      AS avg_int_rate,
        ROUND(AVG(fico_avg), 0)                                      AS avg_fico,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))  AS defaults,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Fully Paid', 'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Fully Paid',
            'Does not meet the credit policy. Status:Charged Off'))  AS resolved_loans
    FROM accepted_loans
    WHERE issue_d IS NOT NULL
    GROUP BY 1
)
SELECT
    issue_quarter,
    total_loans,
    volume_millions,
    avg_int_rate,
    avg_fico,
    ROUND(defaults * 100.0 / NULLIF(resolved_loans, 0), 2)          AS default_rate_pct,
    LAG(volume_millions) OVER (ORDER BY issue_quarter)               AS prev_qtr_volume,
    ROUND(
        (volume_millions - LAG(volume_millions) OVER (ORDER BY issue_quarter))
        * 100.0
        / NULLIF(LAG(volume_millions) OVER (ORDER BY issue_quarter), 0),
        2)                                                           AS volume_qoq_pct,
    ROUND(SUM(volume_millions) OVER (ORDER BY issue_quarter), 2)    AS cumulative_volume_millions
FROM quarterly
ORDER BY issue_quarter;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. Approximate age-at-default analysis
--     Computes approximate loan age (years) using issue_d and last_pymnt_d.
--     Shows whether defaults cluster early or late in loan life.
-- ─────────────────────────────────────────────────────────────────────────────
WITH aged AS (
    SELECT
        ROUND(DATEDIFF('month', issue_d, COALESCE(last_pymnt_d, DATE '2019-01-01')) / 12.0, 1)
                                                                     AS years_to_event,
        loan_status,
        grade,
        funded_amnt
    FROM accepted_loans
    WHERE loan_status IN ('Charged Off', 'Default',
                          'Does not meet the credit policy. Status:Charged Off')
      AND issue_d IS NOT NULL
      AND years_to_event BETWEEN 0 AND 7
)
SELECT
    years_to_event,
    COUNT(*)                                                         AS defaults,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS share_of_all_defaults_pct,
    ROUND(SUM(COUNT(*)) OVER (ORDER BY years_to_event) * 100.0
          / SUM(COUNT(*)) OVER (), 2)                               AS cumulative_pct,
    ROUND(AVG(funded_amnt), 0)                                      AS avg_loan_amt
FROM aged
GROUP BY years_to_event
ORDER BY years_to_event;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Grade mix by issue year
--     Did LC lend more or less conservatively over time?
--     Rising share of E/F/G loans = loosening standards.
--     Window SUM(COUNT(*)) OVER (PARTITION BY year) gives each year's total.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    EXTRACT(YEAR FROM issue_d)                                       AS issue_year,
    grade,
    COUNT(*)                                                         AS loans,
    ROUND(SUM(funded_amnt) / 1e6, 1)                                AS volume_millions,
    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (PARTITION BY EXTRACT(YEAR FROM issue_d)),
        2)                                                           AS grade_share_pct,
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
WHERE issue_d IS NOT NULL
  AND grade IS NOT NULL AND grade != ''
GROUP BY 1, 2
ORDER BY 1, 2;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. Loan purpose mix by issue year
--     How did the distribution of loan use-cases shift over time?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    EXTRACT(YEAR FROM issue_d)                                       AS issue_year,
    purpose,
    COUNT(*)                                                         AS loans,
    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (PARTITION BY EXTRACT(YEAR FROM issue_d)),
        2)                                                           AS purpose_share_pct
FROM accepted_loans
WHERE issue_d IS NOT NULL
  AND purpose IS NOT NULL AND purpose != ''
GROUP BY 1, 2
ORDER BY 1, purpose_share_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. Year-over-year change in default rate by grade
--     LAG() detects whether default rates are rising or falling within grades.
-- ─────────────────────────────────────────────────────────────────────────────
WITH annual_grade AS (
    SELECT
        EXTRACT(YEAR FROM issue_d) AS issue_year,
        grade,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0
        / NULLIF(COUNT(*) FILTER (WHERE loan_status IN (
            'Fully Paid', 'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Fully Paid',
            'Does not meet the credit policy. Status:Charged Off')), 0) AS default_rate_pct,
        COUNT(*) AS total_loans
    FROM accepted_loans
    WHERE issue_d IS NOT NULL AND grade IS NOT NULL AND grade != ''
    GROUP BY 1, 2
)
SELECT
    issue_year,
    grade,
    ROUND(default_rate_pct, 2)                                       AS default_rate_pct,
    total_loans,
    ROUND(LAG(default_rate_pct) OVER (PARTITION BY grade ORDER BY issue_year), 2)
                                                                     AS prev_year_default_rate,
    ROUND(
        default_rate_pct
        - LAG(default_rate_pct) OVER (PARTITION BY grade ORDER BY issue_year),
        2)                                                           AS yoy_change_pp
FROM annual_grade
ORDER BY grade, issue_year;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. 36- vs 60-month loans: default rate within grade
--     Is term risk correctly priced? 60-month loans carry more time-risk.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    grade,
    term_months,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate),  2)                                         AS avg_int_rate,
    ROUND(AVG(fico_avg),  0)                                         AS avg_fico,
    ROUND(AVG(dti),       2)                                         AS avg_dti
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND grade IS NOT NULL AND grade != ''
  AND term_months IS NOT NULL
GROUP BY grade, term_months
ORDER BY grade, term_months;
