"""
CRM Data Generator — Salesforce One-Hop Reduction Demo
Generates synthetic Salesforce CRM data: Accounts, Opportunities, Cases.
"""
import argparse
import csv
import random
import uuid
from datetime import date, timedelta

INDUSTRIES = ["Technology", "Healthcare", "Financial Services", "Manufacturing", "Retail"]
REGIONS = ["West", "East", "Central", "EMEA", "APAC"]
OPP_STAGES = ["Prospecting", "Qualification", "Proposal", "Negotiation", "Closed Won", "Closed Lost"]
CASE_PRIORITIES = ["Low", "Medium", "High", "Critical"]
CASE_STATUSES = ["New", "In Progress", "Escalated", "Closed"]
CASE_SUBJECTS = [
    "Login issue", "Billing discrepancy", "Feature request", "Integration error",
    "Performance degradation", "Data sync failure", "API timeout", "License renewal",
    "Onboarding assistance", "Security concern", "Report not loading", "User access request",
]

COMPANY_PREFIXES = [
    "Apex", "Nexus", "Vertex", "Quantum", "Pinnacle", "Catalyst", "Horizon",
    "Synergy", "Velocity", "Zenith", "Meridian", "Stellar", "Vanguard", "Atlas",
    "Titan", "Nova", "Prism", "Forge", "Summit", "Beacon", "Aegis", "Stratos",
    "Lumina", "Orbit", "Helix", "Cipher", "Pulse", "Sigma", "Crest", "Flux",
    "Nebula", "Ikon", "Onyx", "Cobalt", "Zephyr", "Quasar", "Radiant", "Ember",
    "Falcon", "Matrix", "Keystone", "Optima", "Brevity", "Lexicon", "Axiom",
    "Dynamo", "Paragon", "Catalyst", "Torque", "Nimbus",
]
COMPANY_SUFFIXES = ["Corp", "Inc", "Systems", "Solutions", "Global", "Labs", "Technologies", "Group"]


def write_csv(filepath, headers, rows):
    with open(filepath, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(headers)
        w.writerows(rows)


def gen_accounts(n=50):
    rows = []
    used_names = set()
    for i in range(n):
        aid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"account_{i}"))
        while True:
            name = f"{random.choice(COMPANY_PREFIXES)} {random.choice(COMPANY_SUFFIXES)}"
            if name not in used_names:
                used_names.add(name)
                break
        industry = random.choice(INDUSTRIES)
        region = random.choice(REGIONS)
        employees = random.choice([50, 100, 250, 500, 1000, 2500, 5000, 10000])
        revenue = round(random.uniform(1, 500), 1)
        created = date(2020, 1, 1) + timedelta(days=random.randint(0, 1500))
        rows.append((aid, name, industry, region, employees, revenue, created.isoformat()))
    return rows


def gen_opportunities(accounts, n=200):
    rows = []
    account_ids = [a[0] for a in accounts]
    account_names = {a[0]: a[1] for a in accounts}
    for i in range(n):
        oid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"opp_{i}"))
        account_id = random.choice(account_ids)
        stage = random.choices(
            OPP_STAGES, weights=[15, 20, 25, 20, 15, 5], k=1
        )[0]
        amount = round(random.uniform(10000, 2000000), 2)
        created = date(2024, 1, 1) + timedelta(days=random.randint(0, 500))
        close_date = created + timedelta(days=random.randint(30, 180))
        is_closed = stage in ("Closed Won", "Closed Lost")
        is_won = stage == "Closed Won"
        opp_name = f"{account_names[account_id]} - {stage[:4]} Deal {i}"
        rows.append((oid, account_id, opp_name, stage, amount,
                     close_date.isoformat(), created.isoformat(), is_closed, is_won))
    return rows


def gen_cases(accounts, n=150):
    rows = []
    account_ids = [a[0] for a in accounts]
    for i in range(n):
        cid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"case_{i}"))
        account_id = random.choice(account_ids)
        priority = random.choices(CASE_PRIORITIES, weights=[30, 40, 20, 10], k=1)[0]
        status = random.choices(CASE_STATUSES, weights=[15, 30, 10, 45], k=1)[0]
        subject = random.choice(CASE_SUBJECTS)
        created = date(2024, 6, 1) + timedelta(days=random.randint(0, 400))
        if status == "Closed":
            resolution = random.randint(1, 30)
            closed_date = created + timedelta(days=resolution)
        else:
            resolution = ""
            closed_date = ""
        rows.append((cid, account_id, priority, status, subject,
                     created.isoformat(), closed_date if closed_date else "",
                     resolution))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="crm_demo/data")
    args = parser.parse_args()

    random.seed(42)

    print("Generating accounts (50)...")
    accounts = gen_accounts(50)
    write_csv(f"{args.output_dir}/raw_accounts.csv",
              ["ACCOUNT_ID", "ACCOUNT_NAME", "INDUSTRY", "REGION", "EMPLOYEE_COUNT", "ANNUAL_REVENUE", "CREATED_DATE"],
              accounts)

    print("Generating opportunities (200)...")
    opps = gen_opportunities(accounts, 200)
    write_csv(f"{args.output_dir}/raw_opportunities.csv",
              ["OPP_ID", "ACCOUNT_ID", "OPP_NAME", "STAGE", "AMOUNT", "CLOSE_DATE", "CREATED_DATE", "IS_CLOSED", "IS_WON"],
              opps)

    print("Generating cases (150)...")
    cases = gen_cases(accounts, 150)
    write_csv(f"{args.output_dir}/raw_cases.csv",
              ["CASE_ID", "ACCOUNT_ID", "PRIORITY", "STATUS", "SUBJECT", "CREATED_DATE", "CLOSED_DATE", "RESOLUTION_DAYS"],
              cases)

    print(f"Done! Files written to {args.output_dir}/")


if __name__ == "__main__":
    main()
