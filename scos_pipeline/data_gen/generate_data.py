"""Generate synthetic healthcare/pharma data — pure Python, no external deps."""
import argparse
import csv
import os
import random
import uuid
from datetime import date, timedelta

random.seed(42)

# Domain constants
THERAPEUTIC_AREAS = [
    "Oncology", "Immunology", "Cardiology", "Neurology",
    "Infectious Disease", "Respiratory", "Endocrinology", "Dermatology"
]

SPECIALTIES = [
    "Internal Medicine", "Oncology", "Cardiology", "Neurology",
    "Pulmonology", "Endocrinology", "Dermatology", "Rheumatology",
    "Gastroenterology", "Infectious Disease", "Family Medicine",
    "Hematology", "Nephrology", "Psychiatry", "Surgery"
]

SUB_SPECIALTIES = [
    "Pediatric", "Geriatric", "Interventional", "Surgical",
    "Diagnostic", "Research", "Community Practice", "Academic"
]

CREDENTIALS = ["MD", "DO", "PharmD", "NP", "PA"]

PRACTICE_TYPES = [
    "Hospital-Based", "Group Practice", "Solo Practice",
    "Academic Medical Center", "Community Health Center"
]

DRUG_NAMES = [
    ("Cardivex", "Atorvastatin Calcium", "Cardiology", "Hyperlipidemia", "Tablet"),
    ("Immunofort", "Adalimumab", "Immunology", "Rheumatoid Arthritis", "Injection"),
    ("Oncovir", "Pembrolizumab", "Oncology", "Non-Small Cell Lung Cancer", "IV Infusion"),
    ("Neurosyn", "Levetiracetam", "Neurology", "Epilepsy", "Tablet"),
    ("Respiclear", "Fluticasone Propionate", "Respiratory", "Asthma", "Inhaler"),
    ("Glyconorm", "Metformin Extended Release", "Endocrinology", "Type 2 Diabetes", "Tablet"),
    ("Dermasolv", "Dupilumab", "Dermatology", "Atopic Dermatitis", "Injection"),
    ("Infectiguard", "Letermovir", "Infectious Disease", "CMV Prophylaxis", "Tablet"),
    ("Thrombostop", "Rivaroxaban", "Cardiology", "DVT Prevention", "Tablet"),
    ("Psorifix", "Secukinumab", "Immunology", "Psoriasis", "Injection"),
    ("Osteoguard", "Denosumab", "Endocrinology", "Osteoporosis", "Injection"),
    ("Migranex", "Erenumab", "Neurology", "Migraine Prevention", "Injection"),
    ("Hepatovir", "Sofosbuvir", "Infectious Disease", "Hepatitis C", "Tablet"),
    ("Pulmovent", "Tiotropium Bromide", "Respiratory", "COPD", "Inhaler"),
    ("Melanostop", "Nivolumab", "Oncology", "Melanoma", "IV Infusion"),
]

ENGAGEMENT_TYPES = [
    "Detail Visit", "Sample Drop", "Lunch & Learn",
    "Conference", "Peer-to-Peer Speaker", "Webinar"
]

CHANNELS = ["In-Person", "Virtual", "Hybrid", "Phone", "Email"]

PAYER_TYPES = ["Commercial", "Medicare", "Medicaid", "Cash Pay", "VA/Military"]

DISTRICTS = [f"District_{i}" for i in range(1, 26)]
TERRITORIES = [(i, f"Territory_{i}", random.choice(DISTRICTS), (i % 8) + 1) for i in range(1, 101)]
REGIONS = [
    (1, "Northeast", "US"), (2, "Southeast", "US"), (3, "Midwest", "US"),
    (4, "Southwest", "US"), (5, "West", "US"), (6, "Canada", "CA"),
    (7, "Europe-West", "EU"), (8, "Asia-Pacific", "APAC"),
]


def write_csv(filepath, headers, rows):
    with open(filepath, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(headers)
        w.writerows(rows)


def gen_drugs():
    rows = []
    for i, (brand, generic, ta, indication, form) in enumerate(DRUG_NAMES):
        did = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"drug_{i}"))
        launch = date(2015, 1, 1) + timedelta(days=random.randint(0, 3650))
        is_specialty = form in ("Injection", "IV Infusion")
        revenue = round(random.uniform(200, 8000), 1) if is_specialty else round(random.uniform(50, 2000), 1)
        rows.append((did, brand, brand, generic, ta, indication, form, launch.isoformat(), is_specialty, revenue))
    return rows


def gen_territories():
    rows = []
    for tid, name, district, region_id in TERRITORIES:
        tkey = str(uuid.uuid4())[:8]
        rows.append((tid, name, tkey, district, region_id))
    return rows


def gen_regions():
    rows = []
    for rid, name, country in REGIONS:
        rkey = str(uuid.uuid4())[:8]
        rows.append((rid, name, rkey, country))
    return rows


def gen_therapeutic_areas():
    disease_cats = [
        "Solid Tumors", "Autoimmune", "Cardiovascular", "CNS Disorders",
        "Viral Infections", "Pulmonary", "Metabolic", "Skin Conditions"
    ]
    rows = []
    for i, area in enumerate(THERAPEUTIC_AREAS):
        akey = str(uuid.uuid4())[:8]
        rows.append((i + 1, area, akey, disease_cats[i]))
    return rows


def gen_hcp_profiles(n=10000):
    rows = []
    for i in range(n):
        hid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"hcp_{i}"))
        name = f"Dr. {'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[i % 26]}. {'Smith Johnson Williams Brown Davis Miller Wilson Moore Taylor Anderson Thomas Jackson White Harris Martin Thompson Garcia Martinez Robinson Clark'.split()[i % 20]}"
        specialty = random.choice(SPECIALTIES)
        sub_spec = random.choice(SUB_SPECIALTIES)
        cred = random.choice(CREDENTIALS)
        npi = f"{random.randint(1000000000, 9999999999)}"
        territory_id = random.randint(1, 100)
        ta_id = random.randint(1, 8)
        practice = random.choice(PRACTICE_TYPES)
        years = random.randint(1, 40)
        created = "2024-01-15 08:00:00"
        etl_ts = "2026-05-26 12:00:00"
        rows.append((hid, name, specialty, sub_spec, cred, npi, territory_id, ta_id, practice, years, created, etl_ts))
    return rows


def gen_prescriptions(drugs, hcps, n=60000):
    rows = []
    ds = "2026-05-26"
    drug_ids = [d[0] for d in drugs]
    hcp_ids = [h[0] for h in hcps]
    for i in range(n):
        rxid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"rx_{i}"))
        drug_id = random.choice(drug_ids)
        hcp_id = random.choice(hcp_ids)
        territory_id = random.randint(1, 100)
        quantity = random.randint(1, 12)
        total_units = quantity * random.uniform(10, 100)
        rx_date = (date(2026, 4, 1) + timedelta(days=random.randint(0, 55))).isoformat()
        payer = random.choice(PAYER_TYPES)
        new_patient = random.choice([True, False, False, False])
        rows.append((rxid, drug_id, hcp_id, territory_id, quantity, round(total_units, 1), rx_date, payer, new_patient, ds))
    return rows


def gen_engagements(hcps, drugs, n=80000):
    rows = []
    hcp_ids = [h[0] for h in hcps]
    drug_ids = [d[0] for d in drugs]
    rep_ids = [str(uuid.uuid5(uuid.NAMESPACE_DNS, f"rep_{i}")) for i in range(200)]

    notes_templates = [
        "Discussed efficacy data from Phase III trial",
        "HCP expressed interest in new indication",
        "Provided updated dosing guidelines",
        "HCP has concerns about side effect profile",
        "Positive reception to real-world evidence data",
        "Requested additional patient education materials",
        "Discussed formulary access and prior auth process",
        "HCP switching patients from competitor product",
        "Conference presentation well received",
        "Follow-up needed on patient assistance program",
    ]

    for i in range(n):
        eid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"engagement_{i}"))
        hcp_id = random.choice(hcp_ids)
        rep_id = random.choice(rep_ids)
        drug_id = random.choice(drug_ids)
        etype = random.choice(ENGAGEMENT_TYPES)
        channel = random.choice(CHANNELS)
        edate = (date(2025, 6, 1) + timedelta(days=random.randint(0, 360))).isoformat()
        duration = random.randint(5, 90)
        samples = random.randint(0, 20) if etype in ("Detail Visit", "Sample Drop") else 0
        notes = random.choice(notes_templates)
        sentiment = round(random.uniform(-0.3, 0.9), 3)
        updated = "2026-05-26 10:30:00"
        rows.append((eid, hcp_id, rep_id, drug_id, etype, channel, edate, duration, samples, notes, sentiment, updated))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", default="data")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    print("Generating drugs (15)...")
    drugs = gen_drugs()
    write_csv(f"{args.output_dir}/dim_drug.csv",
              ["DRUG_ID", "DRUG_NAME", "BRAND_NAME", "GENERIC_NAME", "THERAPEUTIC_AREA", "INDICATION", "DOSAGE_FORM", "LAUNCH_DATE", "IS_SPECIALTY", "ANNUAL_REVENUE_MM"],
              drugs)

    print("Generating territories (100)...")
    territories = gen_territories()
    write_csv(f"{args.output_dir}/dim_territory.csv",
              ["TERRITORY_ID", "TERRITORY_NAME", "TERRITORY_KEY", "DISTRICT_NAME", "REGION_ID"],
              territories)

    print("Generating regions (8)...")
    regions = gen_regions()
    write_csv(f"{args.output_dir}/dim_region.csv",
              ["REGION_ID", "REGION_NAME", "REGION_KEY", "COUNTRY"],
              regions)

    print("Generating therapeutic areas (8)...")
    ta = gen_therapeutic_areas()
    write_csv(f"{args.output_dir}/dim_therapeutic_area.csv",
              ["THERAPEUTIC_AREA_ID", "AREA_NAME", "AREA_KEY", "DISEASE_CATEGORY"],
              ta)

    print("Generating HCP profiles (10000)...")
    hcps = gen_hcp_profiles()
    write_csv(f"{args.output_dir}/raw_hcp_profiles.csv",
              ["HCP_ID", "HCP_NAME", "SPECIALTY", "SUB_SPECIALTY", "CREDENTIAL", "NPI_NUMBER",
               "TERRITORY_ID", "THERAPEUTIC_AREA_ID", "PRACTICE_TYPE", "YEARS_EXPERIENCE",
               "CREATED_AT", "ETL_UPDATE_DATETIME_UTC"],
              hcps)

    print("Generating prescriptions (60000)...")
    rxs = gen_prescriptions(drugs, hcps)
    write_csv(f"{args.output_dir}/raw_prescriptions.csv",
              ["RX_ID", "DRUG_ID", "HCP_ID", "TERRITORY_ID", "QUANTITY", "TOTAL_UNITS",
               "RX_DATE", "PAYER_TYPE", "IS_NEW_PATIENT", "DS"],
              rxs)

    print("Generating HCP engagements (80000)...")
    engagements = gen_engagements(hcps, drugs)
    write_csv(f"{args.output_dir}/raw_hcp_engagements.csv",
              ["ENGAGEMENT_ID", "HCP_ID", "REP_ID", "DRUG_ID", "ENGAGEMENT_TYPE", "CHANNEL",
               "ENGAGEMENT_DATE", "DURATION_MINUTES", "SAMPLES_DROPPED", "NOTES",
               "SENTIMENT_SCORE", "UPDATED_AT"],
              engagements)

    print(f"Done! Files written to {args.output_dir}/")


if __name__ == "__main__":
    main()
