# Financial Risk SQL Analytics

SQL and Python-based analysis of a large public consumer-lending dataset, focused on credit risk segmentation, portfolio performance, cohort behaviour, rejected-application trends, and risk-monitoring insights.

This project was created to demonstrate practical SQL ability for risk, fraud prevention, Trust & Safety, payments, and financial operations roles. It uses historical Lending Club data to show how structured data can be analysed to identify risk patterns, monitor portfolio changes, and produce business-ready insights.

> **Important note:** This project uses historical public lending data, not live customer, fraud, payment, or marketplace data. The findings are for analytical demonstration only and should not be used for real credit, fraud, or lending decisions.

---

## Why this project matters

Fraud prevention, credit risk, chargeback management, and Trust & Safety teams all rely on the ability to investigate structured data, detect unusual patterns, segment risk, and communicate clear findings.

This project demonstrates those transferable skills using a real financial dataset. It covers:

- SQL-based risk segmentation
- Default-rate and portfolio-performance analysis
- Cohort and vintage analysis
- Rejected-applicant comparison
- Rolling trend and concentration monitoring
- Business interpretation of risk indicators

Although the dataset is from consumer lending rather than marketplace fraud, the same analytical thinking applies to fraud prevention use cases such as account-risk segmentation, chargeback trend analysis, false-positive monitoring, rule-performance review, and suspicious-pattern detection.

---

## Dataset

This project uses the public Lending Club dataset available on Kaggle.

| File | Source | Approx. Size | Approx. Rows |
|---|---|---:|---:|
| `accepted_2007_to_2018q4.csv` | Kaggle | ~1.8 GB | ~2.26M |
| `rejected_2007_to_2018q4.csv` | Kaggle | ~0.5 GB | ~27M |

Dataset link: https://www.kaggle.com/datasets/wordsforthewise/lending-club

Raw CSV files are excluded from this repository because of their size. To run the full project, download both files and place them in:

```text
data/raw/
```

---

## Project structure

```text
financial-risk-sql-analytics/
│
├── README.md
├── requirements.txt
├── .gitignore
├── run_analysis.py
│
├── data/
│   ├── README.md
│   ├── raw/
│   └── processed/
│
├── scripts/
│   └── load_lending_club_data.py
│
├── schema/
│   └── schema.sql
│
├── analysis/
│   ├── 01_loan_performance.sql
│   ├── 02_credit_risk_segments.sql
│   ├── 03_vintage_cohort_analysis.sql
│   ├── 04_portfolio_metrics.sql
│   └── 05_rejected_applications.sql
│
└── outputs/
    ├── sample_accepted_vs_rejected_comparison.csv
    ├── sample_default_rate_by_grade.csv
    ├── sample_dti_decile_analysis.csv
    └── sample_vintage_summary.csv
```

---

## Setup

```bash
# Clone the repository
git clone https://github.com/RupanshiZ/financial-risk-analytics.git

cd financial-risk-analytics

# Install dependencies
pip install -r requirements.txt

# Place the Kaggle CSV files in data/raw/
# accepted_2007_to_2018q4.csv
# rejected_2007_to_2018q4.csv

# Load and clean the data into DuckDB
python scripts/load_lending_club_data.py

# Run all SQL analyses
python run_analysis.py

# Run a single analysis file
python run_analysis.py --file 01

# Run multiple analysis files
python run_analysis.py --file 03 04

# Preview SQL files without executing them
python run_analysis.py --dry-run
```

If the repository has not been renamed yet, replace the clone URL with the current repository URL.

---

## Business questions answered

### 1. Loan performance and default behaviour

Covered in `analysis/01_loan_performance.sql`

This section answers questions such as:

- How did originated loan volume change over time?
- What proportion of loans were fully paid, charged off, or still current?
- How does default rate vary by grade and sub-grade?
- Which loan purposes show higher realised default risk?
- Does home ownership appear to affect default probability?
- How do defaulted and fully paid borrowers differ at origination?
- What does risk-adjusted return look like across loan grades?

---

### 2. Credit risk segmentation

Covered in `analysis/02_credit_risk_segments.sql`

This section answers questions such as:

- At what DTI levels does default risk increase?
- Does FICO score rank-order realised default risk?
- Do higher-income borrowers default less frequently?
- Are interest rates proportionate to realised default rates?
- Which borrower segments are high risk across multiple indicators?
- Which states have higher or lower default rates?

---

### 3. Vintage and cohort analysis

Covered in `analysis/03_vintage_cohort_analysis.sql`

This section answers questions such as:

- How does cumulative default rate vary by origination year?
- Did credit quality change across quarterly loan cohorts?
- When do defaults usually occur within the life of a loan?
- Did the portfolio shift toward riskier grades over time?
- Are longer-term loans priced appropriately against their realised default risk?

---

### 4. Portfolio monitoring

Covered in `analysis/04_portfolio_metrics.sql`

This section answers questions such as:

- Is monthly origination volume increasing or decreasing?
- Is the rolling default rate improving or worsening?
- Does a DTI decile table rank-order default risk clearly?
- Is the portfolio concentrated across grade, state, or purpose?
- What does the HHI concentration score suggest about portfolio diversification?

---

### 5. Rejected-application analysis

Covered in `analysis/05_rejected_applications.sql`

This section answers questions such as:

- How many applications were rejected each year?
- What FICO and DTI profiles appear in rejected applications?
- How do rejected applicants compare with funded borrowers?
- Did rejected-application volumes and risk indicators change over time?
- What can rejected-applicant data suggest about underwriting policy?

---

## SQL concepts demonstrated

| SQL concept | Example use |
|---|---|
| Common Table Expressions | Used across all analysis files to structure multi-step queries |
| Conditional aggregation | Default-rate and segment-level calculations |
| `FILTER (WHERE ...)` | Clean separation of resolved, defaulted, and active loans |
| `CASE WHEN` bucketing | DTI bands, FICO bands, income bands, risk flags |
| Window functions | Cohort analysis, rolling metrics, ranking and trend analysis |
| `LAG` / `LEAD` | Month-on-month and cohort movement analysis |
| `NTILE` | Decile-based risk segmentation |
| `RANK` / `PERCENT_RANK` | Highest-risk segment and state ranking |
| Rolling windows | Portfolio monitoring over time |
| `DATE_TRUNC` / `EXTRACT` / `DATEDIFF` | Time-series and vintage analysis |
| `UNION ALL` | Accepted vs rejected applicant comparison |
| `HAVING` | Post-aggregation filtering |
| `TRY_CAST` | Safe data-type conversion during loading |
| `STRPTIME` | Date parsing for non-standard source formats |

---

## Sample findings

The project includes sample output files in the `outputs/` folder. These files show the type of business-ready results generated by the SQL analysis.

Example outputs include:

- Default rate by loan grade
- DTI decile risk analysis
- Accepted vs rejected applicant comparison
- Vintage cohort summary

### Example finding: default risk by grade

The analysis shows that default rates generally increase as lending grades move from lower-risk grades to higher-risk grades. This confirms that grade is a useful risk indicator, but the project also checks whether pricing, term, DTI, and borrower characteristics explain additional risk differences.

### Example finding: DTI risk segmentation

The DTI decile analysis helps identify whether higher debt-to-income ratios are associated with higher realised default rates. This is useful for understanding whether a risk variable rank-orders outcomes in a practical way.

### Example finding: accepted vs rejected applicants

The rejected-application analysis compares funded and declined populations to explore how credit policy separates higher-risk from lower-risk applicants.

---

## Relevance to fraud prevention and Trust & Safety roles

This project is not a fraud-detection model and does not use live fraud data. However, it demonstrates analytical methods that are directly relevant to fraud prevention and Trust & Safety work.

The project shows how SQL can be used to:

- Investigate high-risk populations
- Segment users or applicants by risk indicators
- Compare approved and declined populations
- Monitor risk trends over time
- Identify unusual shifts in portfolio behaviour
- Build clear outputs for operational and leadership review
- Support rule-performance and control-gap analysis

These skills transfer to fraud and marketplace-risk scenarios such as:

- Account takeover trend analysis
- Payment fraud monitoring
- Chargeback and dispute root-cause analysis
- False-positive review
- Detection-rule performance checks
- Vendor QA and operational-control reporting
- Marketplace abuse pattern investigation

---

## Tools used

- SQL
- DuckDB
- Python
- pandas
- CSV-based reporting
- Git and GitHub

---

## Limitations

- The dataset is historical and covers Lending Club data from 2007 to 2018.
- The data is from the US consumer-lending market, not the UK or European marketplace sector.
- The project does not use live payment, identity, device, behavioural, or chargeback data.
- Default rates are based on resolved loan outcomes. Loans still current at the end of the dataset may have unknown final outcomes.
- This is an analytical SQL project, not a machine-learning fraud model or production credit-decisioning system.
- Findings are intended to demonstrate analytical technique, not to recommend real lending or fraud-prevention decisions.

---

## Author

Rupanshi Sharma  
London, UK  

LinkedIn: https://www.linkedin.com/in/rupanshi-sharma  
GitHub: https://github.com/RupanshiZ
