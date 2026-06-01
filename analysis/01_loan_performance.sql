-- =============================================================================
-- 01_loan_performance.sql
-- Loan-level performance analysis: default rates, grade profiling,
-- risk-adjusted returns, and borrower comparisons.
--
-- Table  : accepted_loans
-- Dialect: DuckDB (PostgreSQL-compatible syntax)
--
-- Default definition used throughout:
--   IS_DEFAULT = loan_status IN (
--       'Charged Off', 'Default',
--       'Does not meet the credit policy. Status:Charged Off')
--   RESOLVED   = above + 'Fully Paid' +
--                'Does not meet the credit policy. Status:Fully Paid'
--   Default rates are always computed on RESOLVED loans only.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Total originated loan volume by year
--     How has Lending Club grown over time?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    EXTRACT(YEAR FROM issue_d)               AS issue_year,
    COUNT(*)                                 AS total_loans,
    ROUND(SUM(funded_amnt) / 1e9, 3)        AS volume_billions,
    ROUND(AVG(funded_amnt), 0)              AS avg_loan_amount,
    ROUND(AVG(int_rate), 2)                 AS avg_interest_rate,
    ROUND(AVG(fico_avg), 0)                 AS avg_fico
FROM accepted_loans
WHERE issue_d IS NOT NULL
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Loan status breakdown — snapshot of the full portfolio
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    loan_status,
    COUNT(*)                                             AS loans,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS share_pct,
    ROUND(SUM(funded_amnt) / 1e9, 3)                   AS volume_billions
FROM accepted_loans
GROUP BY loan_status
ORDER BY loans DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. Default rate by grade — resolved loans only
--     Core risk table for any credit portfolio.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    grade,
    COUNT(*)                                                         AS resolved_loans,
    COUNT(*) FILTER (WHERE loan_status IN (
        'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Charged Off'))      AS defaults,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate),   2)                                        AS avg_int_rate,
    ROUND(AVG(funded_amnt),0)                                        AS avg_loan_amt,
    ROUND(AVG(dti),        2)                                        AS avg_dti,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico,
    ROUND(AVG(annual_inc), 0)                                        AS avg_income
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND grade IS NOT NULL
  AND grade != ''
GROUP BY grade
ORDER BY grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Default rate by sub-grade — granular risk within each grade
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    sub_grade,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(int_rate), 2)                                          AS avg_int_rate,
    ROUND(AVG(fico_avg), 0)                                          AS avg_fico,
    ROUND(AVG(dti),      2)                                          AS avg_dti
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND sub_grade IS NOT NULL AND sub_grade != ''
GROUP BY sub_grade
ORDER BY sub_grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. Default rate by loan purpose
--     Are some use-cases structurally riskier than others?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    purpose,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(SUM(funded_amnt) / 1e6, 1)                                AS volume_millions,
    ROUND(AVG(funded_amnt), 0)                                       AS avg_loan_amt,
    ROUND(AVG(int_rate),    2)                                       AS avg_int_rate
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND purpose IS NOT NULL AND purpose != ''
GROUP BY purpose
HAVING COUNT(*) >= 500
ORDER BY default_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. Default rate by home ownership status
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    home_ownership,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(annual_inc), 0)                                        AS avg_income,
    ROUND(AVG(dti),        2)                                        AS avg_dti,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND home_ownership NOT IN ('', 'ANY', 'NONE')
GROUP BY home_ownership
ORDER BY default_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. Risk-adjusted return proxy by grade
--     Approximation: interest rate − expected loss (default rate × 60% LGD).
--     Shows where actual economic return is positive vs negative.
-- ─────────────────────────────────────────────────────────────────────────────
WITH grade_perf AS (
    SELECT
        grade,
        AVG(int_rate) AS avg_rate,
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 1.0 / COUNT(*) AS default_rate,
        COUNT(*) AS n
    FROM accepted_loans
    WHERE loan_status IN (
        'Fully Paid', 'Charged Off', 'Default',
        'Does not meet the credit policy. Status:Fully Paid',
        'Does not meet the credit policy. Status:Charged Off')
      AND grade IS NOT NULL AND grade != ''
    GROUP BY grade
)
SELECT
    grade,
    ROUND(avg_rate,                              2) AS avg_int_rate_pct,
    ROUND(default_rate * 100,                    2) AS default_rate_pct,
    -- Expected loss assuming 60% loss-given-default (standard unsecured LGD)
    ROUND(default_rate * 100 * 0.60,             2) AS expected_loss_pct,
    ROUND(avg_rate - (default_rate * 100 * 0.60),2) AS risk_adj_return_pct,
    n AS resolved_loans
FROM grade_perf
ORDER BY grade;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q8. Borrower profile comparison: Fully Paid vs Charged Off
--     What separates borrowers who pay back from those who default?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off')
        THEN 'Defaulted'
        ELSE 'Fully Paid'
    END                                           AS outcome,
    COUNT(*)                                      AS n_loans,
    ROUND(AVG(fico_avg),     1)                   AS avg_fico,
    ROUND(AVG(dti),          2)                   AS avg_dti,
    ROUND(AVG(annual_inc),   0)                   AS avg_annual_income,
    ROUND(AVG(funded_amnt),  0)                   AS avg_loan_amount,
    ROUND(AVG(int_rate),     2)                   AS avg_int_rate,
    ROUND(AVG(delinq_2yrs),  2)                   AS avg_delinquencies,
    ROUND(AVG(revol_util),   2)                   AS avg_revol_util_pct,
    ROUND(AVG(open_acc),     1)                   AS avg_open_accounts,
    ROUND(AVG(inq_last_6mths),2)                  AS avg_recent_enquiries
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
GROUP BY 1
ORDER BY 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q9. Verification status vs default rate
--     Counter-intuitive finding: "Verified" income often correlates with
--     higher default rates (selection bias — LC verifies riskier borrowers).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    verification_status,
    COUNT(*)                                                         AS resolved_loans,
    ROUND(
        COUNT(*) FILTER (WHERE loan_status IN (
            'Charged Off', 'Default',
            'Does not meet the credit policy. Status:Charged Off'))
        * 100.0 / COUNT(*), 2)                                       AS default_rate_pct,
    ROUND(AVG(annual_inc), 0)                                        AS avg_income,
    ROUND(AVG(fico_avg),   0)                                        AS avg_fico,
    ROUND(AVG(int_rate),   2)                                        AS avg_int_rate
FROM accepted_loans
WHERE loan_status IN (
    'Fully Paid', 'Charged Off', 'Default',
    'Does not meet the credit policy. Status:Fully Paid',
    'Does not meet the credit policy. Status:Charged Off')
  AND verification_status != ''
GROUP BY verification_status
ORDER BY default_rate_pct DESC;
