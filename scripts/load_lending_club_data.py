"""
load_lending_club_data.py
─────────────────────────
Loads the raw Lending Club CSV files into a local DuckDB database, applying
type cleaning and column standardisation.

Expected inputs:
    data/raw/accepted_2007_to_2018q4.csv
    data/raw/rejected_2007_to_2018q4.csv

Output:
    data/processed/lending_club.duckdb
        Tables: accepted_loans, rejected_applications

Usage:
    python scripts/load_lending_club_data.py
    python scripts/load_lending_club_data.py --force   # overwrite existing DB
"""

import argparse
import pathlib
import sys
import time

import duckdb

# ── Paths ──────────────────────────────────────────────────────────────────────
ROOT          = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR       = ROOT / "data" / "raw"
PROCESSED_DIR = ROOT / "data" / "processed"
DB_PATH       = PROCESSED_DIR / "lending_club.duckdb"

ACCEPTED_CSV = RAW_DIR / "accepted_2007_to_2018q4.csv"
REJECTED_CSV = RAW_DIR / "rejected_2007_to_2018q4.csv"


# ── SQL: accepted_loans ────────────────────────────────────────────────────────
# All % symbols are stripped, dates parsed from 'Mon-YYYY' format,
# term converted from '36 months' to integer, columns standardised to
# snake_case.  Garbage/footer rows are excluded via the WHERE clause.

ACCEPTED_SQL = """
CREATE OR REPLACE TABLE accepted_loans AS
SELECT
    -- Identifiers
    id,
    member_id,

    -- Core loan amounts
    TRY_CAST(loan_amnt    AS DOUBLE) AS loan_amnt,
    TRY_CAST(funded_amnt  AS DOUBLE) AS funded_amnt,
    TRY_CAST(funded_amnt_inv AS DOUBLE) AS funded_amnt_inv,

    -- Term: '36 months' → 36
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE(term, '')), ''), ' months', '')
    AS INTEGER) AS term_months,

    -- Interest rate: '7.89%' → 7.89
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE(int_rate, '')), ''), '%', '')
    AS DOUBLE) AS int_rate,

    TRY_CAST(installment AS DOUBLE) AS installment,

    -- Grade / sub-grade
    TRIM(grade)     AS grade,
    TRIM(sub_grade) AS sub_grade,

    -- Employment
    TRIM(COALESCE(emp_title,  ''))  AS emp_title,
    TRIM(COALESCE(emp_length, ''))  AS emp_length,

    -- Housing
    UPPER(TRIM(COALESCE(home_ownership, ''))) AS home_ownership,

    -- Income and DTI
    TRY_CAST(annual_inc AS DOUBLE) AS annual_inc,
    TRIM(COALESCE(verification_status, '')) AS verification_status,

    -- DTI: occasionally has '%' suffix in older vintages
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE(dti, '')), ''), '%', '')
    AS DOUBLE) AS dti,

    -- Dates: 'Dec-2015' → DATE
    CASE WHEN NULLIF(TRIM(COALESCE(issue_d,          '')), '') IS NOT NULL
         THEN STRPTIME(TRIM(issue_d),          '%b-%Y')::DATE END AS issue_d,
    CASE WHEN NULLIF(TRIM(COALESCE(earliest_cr_line, '')), '') IS NOT NULL
         THEN STRPTIME(TRIM(earliest_cr_line), '%b-%Y')::DATE END AS earliest_cr_line,
    CASE WHEN NULLIF(TRIM(COALESCE(last_pymnt_d,     '')), '') IS NOT NULL
         THEN STRPTIME(TRIM(last_pymnt_d),     '%b-%Y')::DATE END AS last_pymnt_d,
    CASE WHEN NULLIF(TRIM(COALESCE(last_credit_pull_d,'')),'') IS NOT NULL
         THEN STRPTIME(TRIM(last_credit_pull_d),'%b-%Y')::DATE END AS last_credit_pull_d,
    CASE WHEN NULLIF(TRIM(COALESCE(next_pymnt_d,     '')), '') IS NOT NULL
         THEN STRPTIME(TRIM(next_pymnt_d),     '%b-%Y')::DATE END AS next_pymnt_d,

    -- Loan categorisation
    TRIM(COALESCE(loan_status, ''))          AS loan_status,
    TRIM(COALESCE(purpose,     ''))          AS purpose,
    TRIM(COALESCE(title,       ''))          AS title,
    TRIM(COALESCE(zip_code,    ''))          AS zip_code,
    UPPER(TRIM(COALESCE(addr_state, '')))    AS addr_state,

    -- Credit profile
    TRY_CAST(delinq_2yrs   AS DOUBLE) AS delinq_2yrs,
    TRY_CAST(fico_range_low  AS DOUBLE) AS fico_range_low,
    TRY_CAST(fico_range_high AS DOUBLE) AS fico_range_high,
    -- Midpoint FICO for single-value comparisons
    (TRY_CAST(fico_range_low AS DOUBLE) + TRY_CAST(fico_range_high AS DOUBLE)) / 2
                                          AS fico_avg,
    TRY_CAST(inq_last_6mths AS DOUBLE)   AS inq_last_6mths,
    TRY_CAST(open_acc       AS DOUBLE)   AS open_acc,
    TRY_CAST(pub_rec        AS DOUBLE)   AS pub_rec,
    TRY_CAST(revol_bal      AS DOUBLE)   AS revol_bal,
    -- Revolving utilisation: '45.6%' → 45.6
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE(revol_util, '')), ''), '%', '')
    AS DOUBLE) AS revol_util,
    TRY_CAST(total_acc      AS DOUBLE)   AS total_acc,
    TRY_CAST(mths_since_last_delinq AS DOUBLE) AS mths_since_last_delinq,
    TRY_CAST(collections_12_mths_ex_med AS DOUBLE) AS collections_12_mths_ex_med,
    TRY_CAST(pub_rec_bankruptcies AS DOUBLE) AS pub_rec_bankruptcies,

    -- Payment outcomes
    TRY_CAST(total_pymnt         AS DOUBLE) AS total_pymnt,
    TRY_CAST(total_pymnt_inv     AS DOUBLE) AS total_pymnt_inv,
    TRY_CAST(total_rec_prncp     AS DOUBLE) AS total_rec_prncp,
    TRY_CAST(total_rec_int       AS DOUBLE) AS total_rec_int,
    TRY_CAST(total_rec_late_fee  AS DOUBLE) AS total_rec_late_fee,
    TRY_CAST(recoveries          AS DOUBLE) AS recoveries,
    TRY_CAST(collection_recovery_fee AS DOUBLE) AS collection_recovery_fee,
    TRY_CAST(last_pymnt_amnt     AS DOUBLE) AS last_pymnt_amnt,
    TRY_CAST(out_prncp           AS DOUBLE) AS out_prncp,
    TRY_CAST(out_prncp_inv       AS DOUBLE) AS out_prncp_inv,

    -- Application metadata
    TRIM(COALESCE(application_type, ''))  AS application_type,
    TRY_CAST(annual_inc_joint AS DOUBLE)  AS annual_inc_joint,
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE(dti_joint, '')), ''), '%', '')
    AS DOUBLE) AS dti_joint,
    TRIM(COALESCE(debt_settlement_flag, '')) AS debt_settlement_flag,
    TRY_CAST(policy_code AS DOUBLE) AS policy_code,
    TRIM(COALESCE(pymnt_plan, ''))          AS pymnt_plan,
    TRIM(COALESCE(initial_list_status, '')) AS initial_list_status

FROM read_csv(
    '{path}',
    header       = True,
    all_varchar  = True,
    ignore_errors = True
)
WHERE TRY_CAST(loan_amnt AS DOUBLE) IS NOT NULL
  AND NULLIF(TRIM(COALESCE(id, '')), '') IS NOT NULL
"""

# ── SQL: rejected_applications ────────────────────────────────────────────────
# The rejected CSV uses display names with spaces and special characters.
# Column mapping:
#   "Amount Requested"    → amount_requested
#   "Application Date"    → application_date
#   "Loan Title"          → loan_title
#   "Risk_Score"          → risk_score          (credit/FICO proxy)
#   "Debt-To-Income Ratio"→ debt_to_income_ratio
#   "Zip Code"            → zip_code
#   "State"               → state
#   "Employment Length"   → employment_length
#   "Policy Code"         → policy_code

REJECTED_SQL = """
CREATE OR REPLACE TABLE rejected_applications AS
SELECT
    TRY_CAST("Amount Requested"   AS DOUBLE)  AS amount_requested,
    TRY_CAST("Application Date"   AS DATE)    AS application_date,
    TRIM(COALESCE("Loan Title",   ''))        AS loan_title,
    -- Risk_Score is the FICO score for rejected applicants
    TRY_CAST("Risk_Score"         AS DOUBLE)  AS risk_score,
    -- DTI may appear as '15.00%' or '15.00'
    TRY_CAST(
        REPLACE(NULLIF(TRIM(COALESCE("Debt-To-Income Ratio", '')), ''), '%', '')
    AS DOUBLE) AS debt_to_income_ratio,
    TRIM(COALESCE("Zip Code",         ''))    AS zip_code,
    UPPER(TRIM(COALESCE("State",      '')))   AS state,
    TRIM(COALESCE("Employment Length",''))    AS employment_length,
    TRIM(COALESCE("Policy Code",      ''))    AS policy_code

FROM read_csv(
    '{path}',
    header        = True,
    all_varchar   = True,
    ignore_errors = True
)
WHERE TRY_CAST("Amount Requested" AS DOUBLE) IS NOT NULL
"""


# ── Main ───────────────────────────────────────────────────────────────────────
def main(force: bool = False):
    # Validation
    errors = []
    if not ACCEPTED_CSV.exists():
        errors.append(f"  Missing: {ACCEPTED_CSV}")
    if not REJECTED_CSV.exists():
        errors.append(f"  Missing: {REJECTED_CSV}")
    if errors:
        print("ERROR — raw data files not found:\n" + "\n".join(errors))
        print("\nDownload them from Kaggle and place in data/raw/")
        print("See data/README.md for instructions.")
        sys.exit(1)

    if DB_PATH.exists() and not force:
        print(f"Database already exists: {DB_PATH}")
        print("Run with --force to overwrite.")
        sys.exit(0)

    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    if DB_PATH.exists():
        DB_PATH.unlink()

    print(f"Connecting to {DB_PATH}")
    con = duckdb.connect(str(DB_PATH))

    # ── Accepted loans ──────────────────────────────────────────────────────
    print(f"\n[1/2] Loading accepted loans from {ACCEPTED_CSV.name} ...")
    print("      (this file is ~1.8 GB — expect 2–5 minutes)")
    t0 = time.time()

    sql = ACCEPTED_SQL.format(path=str(ACCEPTED_CSV).replace("\\", "/"))
    con.execute(sql)
    n_accepted = con.execute("SELECT COUNT(*) FROM accepted_loans").fetchone()[0]
    elapsed = time.time() - t0
    print(f"      Loaded {n_accepted:,} rows in {elapsed:.1f}s")

    # Quick sanity check
    sample = con.execute("""
        SELECT
            COUNT(*) FILTER (WHERE issue_d IS NULL)  AS null_dates,
            COUNT(*) FILTER (WHERE int_rate IS NULL) AS null_rates,
            COUNT(DISTINCT grade)                    AS n_grades,
            MIN(issue_d)                             AS earliest,
            MAX(issue_d)                             AS latest
        FROM accepted_loans
    """).df()
    print(f"      Date range : {sample['earliest'][0]} → {sample['latest'][0]}")
    print(f"      Null dates : {sample['null_dates'][0]:,}   "
          f"Null rates : {sample['null_rates'][0]:,}   "
          f"Grades : {sample['n_grades'][0]}")

    # ── Rejected applications ───────────────────────────────────────────────
    print(f"\n[2/2] Loading rejected applications from {REJECTED_CSV.name} ...")
    print("      (this file is ~500 MB — expect 1–3 minutes)")
    t1 = time.time()

    # Peek at actual column names to guard against schema variations
    peek = duckdb.execute(
        f"SELECT * FROM read_csv('{str(REJECTED_CSV).replace(chr(92),'/')}', "
        f"header=True, all_varchar=True) LIMIT 0"
    ).description
    actual_cols = [d[0] for d in peek]
    print(f"      Detected columns: {actual_cols}")

    # Verify expected columns exist
    expected = {"Amount Requested", "Application Date", "Risk_Score",
                "Debt-To-Income Ratio", "State"}
    missing = expected - set(actual_cols)
    if missing:
        print(f"      WARNING: expected columns not found: {missing}")
        print("      Check the CSV header and update REJECTED_SQL if needed.")

    sql = REJECTED_SQL.format(path=str(REJECTED_CSV).replace("\\", "/"))
    con.execute(sql)
    n_rejected = con.execute("SELECT COUNT(*) FROM rejected_applications").fetchone()[0]
    elapsed = time.time() - t1
    print(f"      Loaded {n_rejected:,} rows in {elapsed:.1f}s")

    # ── Summary ─────────────────────────────────────────────────────────────
    db_size_mb = DB_PATH.stat().st_size / 1024 / 1024
    print(f"\n{'─'*60}")
    print(f"  Database   : {DB_PATH}")
    print(f"  Size       : {db_size_mb:.1f} MB")
    print(f"  accepted_loans         : {n_accepted:>10,} rows")
    print(f"  rejected_applications  : {n_rejected:>10,} rows")
    print(f"{'─'*60}")
    print("\nDone. Run analysis with: python run_analysis.py")

    con.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing database")
    args = parser.parse_args()
    main(force=args.force)
