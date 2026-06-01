"""
run_analysis.py
───────────────
Connects to data/processed/lending_club.duckdb, runs every SQL file in
analysis/, and saves each query result as a CSV in outputs/.

Usage:
    python run_analysis.py                    # run all files
    python run_analysis.py --file 01          # only 01_*.sql
    python run_analysis.py --file 03 04       # files 03 and 04
    python run_analysis.py --dry-run          # print queries without executing
"""

import argparse
import pathlib
import re
import sys
import time

import duckdb
import pandas as pd

ROOT       = pathlib.Path(__file__).resolve().parent
DB_PATH    = ROOT / "data" / "processed" / "lending_club.duckdb"
SQL_DIR    = ROOT / "analysis"
OUTPUT_DIR = ROOT / "outputs"

OUTPUT_DIR.mkdir(exist_ok=True)

SEP = "─" * 72


# ── SQL parsing ───────────────────────────────────────────────────────────────
def split_statements(sql_text: str) -> list[tuple[str, str]]:
    """
    Returns a list of (label, sql) pairs.
    label is extracted from the '-- Q<n>. ...' heading comment above each statement.
    Strips comment lines before splitting by semicolons so that semicolons inside
    comments (e.g. 'HHI < 1500; threshold') do not break parsing.
    """
    # Remove single-line comments, preserving newlines
    no_comments = re.sub(r"--[^\n]*", "", sql_text)
    # Split into candidate statements
    raw_stmts = [s.strip() for s in no_comments.split(";")]

    # Re-extract labels from the original text by matching Q<n> headings
    labels = re.findall(r"--\s*(Q\d+\.[^\n]*)", sql_text)
    label_iter = iter(labels)

    results = []
    for stmt in raw_stmts:
        if not stmt:
            continue
        if not re.match(r"(?i)(SELECT|WITH)\b", stmt.lstrip()):
            continue
        try:
            label = next(label_iter).strip()
        except StopIteration:
            label = f"Q{len(results)+1}"
        results.append((label, stmt))

    return results


# ── Main ──────────────────────────────────────────────────────────────────────
def main(file_filters: list[str], dry_run: bool):
    if not DB_PATH.exists():
        print(f"Database not found: {DB_PATH}")
        print("Run scripts/load_lending_club_data.py first.")
        sys.exit(1)

    sql_files = sorted(SQL_DIR.glob("*.sql"))
    if file_filters:
        sql_files = [f for f in sql_files
                     if any(f.name.startswith(ff) for ff in file_filters)]
    if not sql_files:
        print("No matching SQL files found.")
        sys.exit(1)

    con = duckdb.connect(str(DB_PATH), read_only=True)

    total_queries   = 0
    total_rows      = 0
    total_errors    = 0
    results_summary = []

    for sql_file in sql_files:
        print(f"\n{'═'*72}")
        print(f"  {sql_file.name}")
        print(f"{'═'*72}")

        stmts = split_statements(sql_file.read_text())
        if not stmts:
            print("  No runnable statements found.")
            continue

        file_prefix = sql_file.stem.replace(" ", "_")

        for idx, (label, sql) in enumerate(stmts, start=1):
            total_queries += 1
            short_label = label[:60]
            print(f"\n{SEP}")
            print(f"  {short_label}")
            print(SEP)

            # Build output filename: e.g. 01_loan_performance_q01_default_by_grade.csv
            slug = re.sub(r"[^\w]+", "_", label.lower())[:40].strip("_")
            out_name = f"{file_prefix}_q{idx:02d}_{slug}.csv"
            out_path = OUTPUT_DIR / out_name

            if dry_run:
                print("  [dry-run] would write →", out_path)
                continue

            t0 = time.time()
            try:
                df = con.execute(sql).df()
                elapsed = time.time() - t0
                total_rows += len(df)

                # Print preview (first 10 rows)
                print(df.to_string(index=False, max_rows=10,
                                   float_format=lambda x: f"{x:.2f}"))
                print(f"\n  ({len(df)} rows, {elapsed:.2f}s)  →  {out_path.name}")

                df.to_csv(out_path, index=False)
                results_summary.append({
                    "file": sql_file.name,
                    "query": label[:50],
                    "rows": len(df),
                    "time_s": round(elapsed, 2),
                    "output": out_path.name,
                    "status": "OK"
                })

            except Exception as exc:
                total_errors += 1
                elapsed = time.time() - t0
                print(f"  ⚠  ERROR: {exc}")
                results_summary.append({
                    "file": sql_file.name,
                    "query": label[:50],
                    "rows": 0,
                    "time_s": round(elapsed, 2),
                    "output": "",
                    "status": f"ERROR: {str(exc)[:60]}"
                })

    con.close()

    # ── Print run summary ──────────────────────────────────────────────────
    print(f"\n\n{'═'*72}")
    print("  RUN SUMMARY")
    print(f"{'═'*72}")
    summary_df = pd.DataFrame(results_summary)
    if not summary_df.empty:
        print(summary_df.to_string(index=False))
    print(f"\n  Total queries : {total_queries}")
    print(f"  Total rows    : {total_rows:,}")
    print(f"  Errors        : {total_errors}")
    print(f"  Outputs saved : {OUTPUT_DIR}")
    print(f"{'═'*72}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", nargs="+",
                        help="File prefix(es) to run, e.g. 01 or 03 04")
    parser.add_argument("--dry-run", action="store_true",
                        help="Parse and list queries without executing")
    args = parser.parse_args()
    main(file_filters=args.file or [], dry_run=args.dry_run)
