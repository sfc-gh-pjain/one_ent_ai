/*=============================================================================
  SNOWFLAKE HORIZON CATALOG DEMO - PART 1: SETUP & SYNTHETIC DATA
  
  This script creates the demo schema, roles, and populates healthcare tables
  with synthetic data for demonstrating Horizon Catalog capabilities.
=============================================================================*/

-- Use ACCOUNTADMIN for initial setup
USE ROLE ACCOUNTADMIN;

-- Create demo database and schema
CREATE DATABASE IF NOT EXISTS HORIZON_DEMO_DB;
CREATE SCHEMA IF NOT EXISTS HORIZON_DEMO_DB.HEALTHCARE;

USE DATABASE HORIZON_DEMO_DB;
USE SCHEMA HEALTHCARE;
USE WAREHOUSE MY_WH;

-- ============================================================================
-- DEMO ROLES
-- ============================================================================

CREATE ROLE IF NOT EXISTS HORIZON_DEMO_ADMIN;
CREATE ROLE IF NOT EXISTS HORIZON_DEMO_CLINICAL;
CREATE ROLE IF NOT EXISTS HORIZON_DEMO_ANALYST;
CREATE ROLE IF NOT EXISTS HORIZON_DEMO_COMPLIANCE;

-- Grant role hierarchy
GRANT ROLE HORIZON_DEMO_ADMIN TO ROLE ACCOUNTADMIN;
GRANT ROLE HORIZON_DEMO_CLINICAL TO ROLE HORIZON_DEMO_ADMIN;
GRANT ROLE HORIZON_DEMO_ANALYST TO ROLE HORIZON_DEMO_ADMIN;
GRANT ROLE HORIZON_DEMO_COMPLIANCE TO ROLE HORIZON_DEMO_ADMIN;

-- Grant warehouse usage to all demo roles
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE HORIZON_DEMO_ADMIN;
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE HORIZON_DEMO_CLINICAL;
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE HORIZON_DEMO_ANALYST;
GRANT USAGE ON WAREHOUSE MY_WH TO ROLE HORIZON_DEMO_COMPLIANCE;

-- Grant database and schema usage
GRANT USAGE ON DATABASE HORIZON_DEMO_DB TO ROLE HORIZON_DEMO_ADMIN;
GRANT USAGE ON DATABASE HORIZON_DEMO_DB TO ROLE HORIZON_DEMO_CLINICAL;
GRANT USAGE ON DATABASE HORIZON_DEMO_DB TO ROLE HORIZON_DEMO_ANALYST;
GRANT USAGE ON DATABASE HORIZON_DEMO_DB TO ROLE HORIZON_DEMO_COMPLIANCE;

GRANT USAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ADMIN;
GRANT USAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_CLINICAL;
GRANT USAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ANALYST;
GRANT USAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_COMPLIANCE;

-- Grant table access
GRANT ALL ON ALL TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_CLINICAL;
GRANT SELECT ON ALL TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_COMPLIANCE;

-- Future grants
GRANT SELECT ON FUTURE TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_CLINICAL;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_COMPLIANCE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_CLINICAL;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE HORIZON_DEMO_COMPLIANCE;

-- ============================================================================
-- GRANTS FOR SYSADMIN (deploy scripts 02-06 run as SYSADMIN)
-- ============================================================================

GRANT USAGE ON DATABASE HORIZON_DEMO_DB TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT ALL ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE TABLE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE VIEW ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE DYNAMIC TABLE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE STAGE ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE MASKING POLICY ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE ROW ACCESS POLICY ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE AGGREGATION POLICY ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE JOIN POLICY ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE PROJECTION POLICY ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE TAG ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE DATA METRIC FUNCTION ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE AGENT ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE FUNCTION ON SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN;
GRANT CREATE SHARE ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY TAG ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY AGGREGATION POLICY ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY JOIN POLICY ON ACCOUNT TO ROLE SYSADMIN;
GRANT APPLY PROJECTION POLICY ON ACCOUNT TO ROLE SYSADMIN;

-- Grant SYSADMIN admin role for demo
GRANT ROLE HORIZON_DEMO_ADMIN TO ROLE SYSADMIN;

-- ============================================================================
-- TABLE: PATIENTS
-- ============================================================================

CREATE OR REPLACE TABLE PATIENTS (
    patient_id          INT AUTOINCREMENT,
    first_name          VARCHAR(50),
    last_name           VARCHAR(50),
    ssn                 VARCHAR(11),
    email               VARCHAR(100),
    phone               VARCHAR(15),
    date_of_birth       DATE,
    gender              VARCHAR(1),
    blood_type          VARCHAR(3),
    department          VARCHAR(50),
    insurance_provider  VARCHAR(50),
    address_line1       VARCHAR(200),
    city                VARCHAR(50),
    state               VARCHAR(2),
    zip_code            VARCHAR(10),
    emergency_contact   VARCHAR(100),
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PATIENTS (first_name, last_name, ssn, email, phone, date_of_birth, gender, blood_type, department, insurance_provider, address_line1, city, state, zip_code, emergency_contact)
SELECT
    CASE UNIFORM(1, 20, RANDOM())
        WHEN 1 THEN 'James' WHEN 2 THEN 'Mary' WHEN 3 THEN 'John' WHEN 4 THEN 'Patricia'
        WHEN 5 THEN 'Robert' WHEN 6 THEN 'Jennifer' WHEN 7 THEN 'Michael' WHEN 8 THEN 'Linda'
        WHEN 9 THEN 'David' WHEN 10 THEN 'Elizabeth' WHEN 11 THEN 'William' WHEN 12 THEN 'Barbara'
        WHEN 13 THEN 'Richard' WHEN 14 THEN 'Susan' WHEN 15 THEN 'Joseph' WHEN 16 THEN 'Jessica'
        WHEN 17 THEN 'Thomas' WHEN 18 THEN 'Sarah' WHEN 19 THEN 'Daniel' ELSE 'Karen'
    END AS first_name,
    CASE UNIFORM(1, 20, RANDOM())
        WHEN 1 THEN 'Smith' WHEN 2 THEN 'Johnson' WHEN 3 THEN 'Williams' WHEN 4 THEN 'Brown'
        WHEN 5 THEN 'Jones' WHEN 6 THEN 'Garcia' WHEN 7 THEN 'Miller' WHEN 8 THEN 'Davis'
        WHEN 9 THEN 'Rodriguez' WHEN 10 THEN 'Martinez' WHEN 11 THEN 'Anderson' WHEN 12 THEN 'Taylor'
        WHEN 13 THEN 'Thomas' WHEN 14 THEN 'Jackson' WHEN 15 THEN 'White' WHEN 16 THEN 'Harris'
        WHEN 17 THEN 'Martin' WHEN 18 THEN 'Thompson' WHEN 19 THEN 'Lee' ELSE 'Clark'
    END AS last_name,
    LPAD(UNIFORM(100, 999, RANDOM())::VARCHAR, 3, '0') || '-' ||
    LPAD(UNIFORM(10, 99, RANDOM())::VARCHAR, 2, '0') || '-' ||
    LPAD(UNIFORM(1000, 9999, RANDOM())::VARCHAR, 4, '0') AS ssn,
    LOWER(first_name) || '.' || LOWER(last_name) || UNIFORM(1, 999, RANDOM())::VARCHAR || '@' ||
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'gmail.com' WHEN 2 THEN 'yahoo.com' WHEN 3 THEN 'outlook.com'
        WHEN 4 THEN 'healthmail.org' ELSE 'email.com'
    END AS email,
    '(' || LPAD(UNIFORM(200, 999, RANDOM())::VARCHAR, 3, '0') || ') ' ||
    LPAD(UNIFORM(100, 999, RANDOM())::VARCHAR, 3, '0') || '-' ||
    LPAD(UNIFORM(1000, 9999, RANDOM())::VARCHAR, 4, '0') AS phone,
    DATEADD(DAY, -UNIFORM(6570, 32850, RANDOM()), CURRENT_DATE()) AS date_of_birth,
    CASE WHEN UNIFORM(1, 2, RANDOM()) = 1 THEN 'M' ELSE 'F' END AS gender,
    CASE UNIFORM(1, 8, RANDOM())
        WHEN 1 THEN 'A+' WHEN 2 THEN 'A-' WHEN 3 THEN 'B+' WHEN 4 THEN 'B-'
        WHEN 5 THEN 'O+' WHEN 6 THEN 'O-' WHEN 7 THEN 'AB+' ELSE 'AB-'
    END AS blood_type,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'CARDIOLOGY' WHEN 2 THEN 'ONCOLOGY'
        WHEN 3 THEN 'NEUROLOGY' ELSE 'GENERAL'
    END AS department,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'Blue Cross' WHEN 2 THEN 'Aetna' WHEN 3 THEN 'UnitedHealth'
        WHEN 4 THEN 'Cigna' ELSE 'Kaiser Permanente'
    END AS insurance_provider,
    UNIFORM(100, 9999, RANDOM())::VARCHAR || ' ' ||
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'Oak St' WHEN 2 THEN 'Maple Ave' WHEN 3 THEN 'Main Blvd'
        WHEN 4 THEN 'Cedar Ln' ELSE 'Pine Dr'
    END AS address_line1,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'New York' WHEN 2 THEN 'Los Angeles' WHEN 3 THEN 'Chicago'
        WHEN 4 THEN 'Houston' WHEN 5 THEN 'Phoenix' WHEN 6 THEN 'Philadelphia'
        WHEN 7 THEN 'San Antonio' WHEN 8 THEN 'San Diego' WHEN 9 THEN 'Dallas' ELSE 'Austin'
    END AS city,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'NY' WHEN 2 THEN 'CA' WHEN 3 THEN 'IL' WHEN 4 THEN 'TX'
        WHEN 5 THEN 'AZ' WHEN 6 THEN 'PA' WHEN 7 THEN 'FL' WHEN 8 THEN 'OH'
        WHEN 9 THEN 'GA' ELSE 'NC'
    END AS state,
    LPAD(UNIFORM(10000, 99999, RANDOM())::VARCHAR, 5, '0') AS zip_code,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'Jane Smith' WHEN 2 THEN 'Bob Johnson' WHEN 3 THEN 'Alice Williams'
        WHEN 4 THEN 'Tom Brown' WHEN 5 THEN 'Sarah Jones' WHEN 6 THEN 'Mike Garcia'
        WHEN 7 THEN 'Lisa Miller' WHEN 8 THEN 'Chris Davis' WHEN 9 THEN 'Amy Rodriguez' ELSE 'Dan Martinez'
    END AS emergency_contact
FROM TABLE(GENERATOR(ROWCOUNT => 10000));

-- ============================================================================
-- TABLE: DOCTORS
-- ============================================================================

CREATE OR REPLACE TABLE DOCTORS (
    doctor_id       INT AUTOINCREMENT,
    first_name      VARCHAR(50),
    last_name       VARCHAR(50),
    specialty       VARCHAR(50),
    department      VARCHAR(50),
    license_number  VARCHAR(20),
    email           VARCHAR(100),
    phone           VARCHAR(15),
    hire_date       DATE,
    is_active       BOOLEAN DEFAULT TRUE
);

INSERT INTO DOCTORS (first_name, last_name, specialty, department, license_number, email, phone, hire_date, is_active)
SELECT
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'Andrew' WHEN 2 THEN 'Emily' WHEN 3 THEN 'Christopher' WHEN 4 THEN 'Amanda'
        WHEN 5 THEN 'Matthew' WHEN 6 THEN 'Stephanie' WHEN 7 THEN 'Joshua' WHEN 8 THEN 'Nicole'
        WHEN 9 THEN 'Kevin' ELSE 'Rachel'
    END,
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'Patel' WHEN 2 THEN 'Chen' WHEN 3 THEN 'Kumar' WHEN 4 THEN 'Wilson'
        WHEN 5 THEN 'Kim' WHEN 6 THEN 'Nguyen' WHEN 7 THEN 'Shah' WHEN 8 THEN 'Singh'
        WHEN 9 THEN 'Park' ELSE 'Gupta'
    END,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'Cardiology' WHEN 2 THEN 'Oncology'
        WHEN 3 THEN 'Neurology' ELSE 'General Medicine'
    END,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'CARDIOLOGY' WHEN 2 THEN 'ONCOLOGY'
        WHEN 3 THEN 'NEUROLOGY' ELSE 'GENERAL'
    END,
    'MD-' || LPAD(UNIFORM(100000, 999999, RANDOM())::VARCHAR, 6, '0'),
    'dr.' || LOWER(CASE UNIFORM(1, 10, RANDOM()) WHEN 1 THEN 'andrew' WHEN 2 THEN 'emily' WHEN 3 THEN 'christopher' WHEN 4 THEN 'amanda' WHEN 5 THEN 'matthew' WHEN 6 THEN 'stephanie' WHEN 7 THEN 'joshua' WHEN 8 THEN 'nicole' WHEN 9 THEN 'kevin' ELSE 'rachel' END) || UNIFORM(1, 99, RANDOM())::VARCHAR || '@hospital.org',
    '(' || LPAD(UNIFORM(200, 999, RANDOM())::VARCHAR, 3, '0') || ') ' ||
    LPAD(UNIFORM(100, 999, RANDOM())::VARCHAR, 3, '0') || '-' ||
    LPAD(UNIFORM(1000, 9999, RANDOM())::VARCHAR, 4, '0'),
    DATEADD(DAY, -UNIFORM(365, 7300, RANDOM()), CURRENT_DATE()),
    CASE WHEN UNIFORM(1, 20, RANDOM()) > 1 THEN TRUE ELSE FALSE END
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- ============================================================================
-- TABLE: APPOINTMENTS
-- ============================================================================

CREATE OR REPLACE TABLE APPOINTMENTS (
    appointment_id  INT AUTOINCREMENT,
    patient_id      INT,
    doctor_id       INT,
    appointment_date TIMESTAMP_NTZ,
    department      VARCHAR(50),
    visit_type      VARCHAR(30),
    status          VARCHAR(20),
    diagnosis_code  VARCHAR(10),
    notes           VARCHAR(500),
    duration_min    INT,
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO APPOINTMENTS (patient_id, doctor_id, appointment_date, department, visit_type, status, diagnosis_code, notes, duration_min)
SELECT
    UNIFORM(1, 10000, RANDOM()),
    UNIFORM(1, 200, RANDOM()),
    DATEADD(MINUTE, UNIFORM(480, 1080, RANDOM()),
            DATEADD(DAY, -UNIFORM(0, 730, RANDOM()), CURRENT_DATE())),
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'CARDIOLOGY' WHEN 2 THEN 'ONCOLOGY'
        WHEN 3 THEN 'NEUROLOGY' ELSE 'GENERAL'
    END,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'INITIAL' WHEN 2 THEN 'FOLLOW_UP' WHEN 3 THEN 'EMERGENCY'
        WHEN 4 THEN 'ROUTINE' ELSE 'SPECIALIST'
    END,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'COMPLETED' WHEN 2 THEN 'SCHEDULED'
        WHEN 3 THEN 'CANCELLED' ELSE 'NO_SHOW'
    END,
    'ICD-' || LPAD(UNIFORM(1, 999, RANDOM())::VARCHAR, 3, '0'),
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'Patient reports improvement' WHEN 2 THEN 'Follow-up required in 2 weeks'
        WHEN 3 THEN 'New treatment plan initiated' WHEN 4 THEN 'Lab results reviewed'
        ELSE 'Referral to specialist recommended'
    END,
    UNIFORM(15, 120, RANDOM())
FROM TABLE(GENERATOR(ROWCOUNT => 50000));

-- ============================================================================
-- TABLE: PRESCRIPTIONS
-- ============================================================================

CREATE OR REPLACE TABLE PRESCRIPTIONS (
    prescription_id INT AUTOINCREMENT,
    patient_id      INT,
    doctor_id       INT,
    medication_name VARCHAR(100),
    dosage          VARCHAR(50),
    frequency       VARCHAR(50),
    start_date      DATE,
    end_date        DATE,
    refills_remaining INT,
    is_controlled   BOOLEAN,
    pharmacy        VARCHAR(100),
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PRESCRIPTIONS (patient_id, doctor_id, medication_name, dosage, frequency, start_date, end_date, refills_remaining, is_controlled, pharmacy)
SELECT
    UNIFORM(1, 10000, RANDOM()),
    UNIFORM(1, 200, RANDOM()),
    CASE UNIFORM(1, 10, RANDOM())
        WHEN 1 THEN 'Lisinopril' WHEN 2 THEN 'Metformin' WHEN 3 THEN 'Atorvastatin'
        WHEN 4 THEN 'Omeprazole' WHEN 5 THEN 'Amlodipine' WHEN 6 THEN 'Metoprolol'
        WHEN 7 THEN 'Albuterol' WHEN 8 THEN 'Gabapentin' WHEN 9 THEN 'Oxycodone' ELSE 'Sertraline'
    END,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN '10mg' WHEN 2 THEN '20mg' WHEN 3 THEN '50mg'
        WHEN 4 THEN '100mg' ELSE '250mg'
    END,
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'Once daily' WHEN 2 THEN 'Twice daily'
        WHEN 3 THEN 'Every 8 hours' ELSE 'As needed'
    END,
    DATEADD(DAY, -UNIFORM(0, 365, RANDOM()), CURRENT_DATE()),
    DATEADD(DAY, UNIFORM(30, 365, RANDOM()), CURRENT_DATE()),
    UNIFORM(0, 5, RANDOM()),
    CASE WHEN UNIFORM(1, 10, RANDOM()) = 9 THEN TRUE ELSE FALSE END,
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'CVS Pharmacy' WHEN 2 THEN 'Walgreens' WHEN 3 THEN 'Rite Aid'
        WHEN 4 THEN 'Hospital Pharmacy' ELSE 'Express Scripts'
    END
FROM TABLE(GENERATOR(ROWCOUNT => 30000));

-- ============================================================================
-- TABLE: BILLING
-- ============================================================================

CREATE OR REPLACE TABLE BILLING (
    billing_id      INT AUTOINCREMENT,
    patient_id      INT,
    appointment_id  INT,
    service_code    VARCHAR(10),
    service_desc    VARCHAR(200),
    amount_charged  DECIMAL(10,2),
    amount_paid     DECIMAL(10,2),
    insurance_covered DECIMAL(10,2),
    patient_balance DECIMAL(10,2),
    billing_date    DATE,
    payment_status  VARCHAR(20),
    insurance_claim_id VARCHAR(20),
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO BILLING (patient_id, appointment_id, service_code, service_desc, amount_charged, amount_paid, insurance_covered, patient_balance, billing_date, payment_status, insurance_claim_id)
SELECT
    UNIFORM(1, 10000, RANDOM()),
    UNIFORM(1, 50000, RANDOM()),
    'CPT-' || LPAD(UNIFORM(10000, 99999, RANDOM())::VARCHAR, 5, '0'),
    CASE UNIFORM(1, 8, RANDOM())
        WHEN 1 THEN 'Office Visit - New Patient' WHEN 2 THEN 'Office Visit - Established'
        WHEN 3 THEN 'Lab Work - Blood Panel' WHEN 4 THEN 'X-Ray Imaging'
        WHEN 5 THEN 'MRI Scan' WHEN 6 THEN 'Physical Therapy Session'
        WHEN 7 THEN 'Surgical Consultation' ELSE 'Emergency Room Visit'
    END,
    ROUND(UNIFORM(50, 5000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    ROUND(UNIFORM(0, 3000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    ROUND(UNIFORM(0, 4000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    ROUND(UNIFORM(0, 2000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    DATEADD(DAY, -UNIFORM(0, 730, RANDOM()), CURRENT_DATE()),
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'PAID' WHEN 2 THEN 'PENDING'
        WHEN 3 THEN 'PARTIAL' ELSE 'OVERDUE'
    END,
    'CLM-' || LPAD(UNIFORM(100000, 999999, RANDOM())::VARCHAR, 6, '0')
FROM TABLE(GENERATOR(ROWCOUNT => 40000));

-- ============================================================================
-- TABLE: INSURANCE_CLAIMS
-- ============================================================================

CREATE OR REPLACE TABLE INSURANCE_CLAIMS (
    claim_id        INT AUTOINCREMENT,
    patient_id      INT,
    provider_name   VARCHAR(50),
    claim_amount    DECIMAL(10,2),
    approved_amount DECIMAL(10,2),
    claim_status    VARCHAR(20),
    submission_date DATE,
    resolution_date DATE,
    denial_reason   VARCHAR(200),
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO INSURANCE_CLAIMS (patient_id, provider_name, claim_amount, approved_amount, claim_status, submission_date, resolution_date, denial_reason)
SELECT
    UNIFORM(1, 10000, RANDOM()),
    CASE UNIFORM(1, 5, RANDOM())
        WHEN 1 THEN 'Blue Cross' WHEN 2 THEN 'Aetna' WHEN 3 THEN 'UnitedHealth'
        WHEN 4 THEN 'Cigna' ELSE 'Kaiser Permanente'
    END,
    ROUND(UNIFORM(100, 10000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    ROUND(UNIFORM(50, 8000, RANDOM()) + UNIFORM(0, 99, RANDOM()) / 100.0, 2),
    CASE UNIFORM(1, 4, RANDOM())
        WHEN 1 THEN 'APPROVED' WHEN 2 THEN 'DENIED'
        WHEN 3 THEN 'PENDING' ELSE 'UNDER_REVIEW'
    END,
    DATEADD(DAY, -UNIFORM(0, 365, RANDOM()), CURRENT_DATE()),
    DATEADD(DAY, -UNIFORM(0, 300, RANDOM()), CURRENT_DATE()),
    CASE WHEN UNIFORM(1, 4, RANDOM()) = 2 THEN
        CASE UNIFORM(1, 4, RANDOM())
            WHEN 1 THEN 'Pre-authorization not obtained'
            WHEN 2 THEN 'Service not covered under plan'
            WHEN 3 THEN 'Duplicate claim submission'
            ELSE 'Out-of-network provider'
        END
    ELSE NULL END
FROM TABLE(GENERATOR(ROWCOUNT => 25000));

-- ============================================================================
-- VERIFY DATA LOAD
-- ============================================================================

SELECT 'PATIENTS' AS table_name, COUNT(*) AS row_count FROM PATIENTS
UNION ALL SELECT 'DOCTORS', COUNT(*) FROM DOCTORS
UNION ALL SELECT 'APPOINTMENTS', COUNT(*) FROM APPOINTMENTS
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM PRESCRIPTIONS
UNION ALL SELECT 'BILLING', COUNT(*) FROM BILLING
UNION ALL SELECT 'INSURANCE_CLAIMS', COUNT(*) FROM INSURANCE_CLAIMS;

-- ============================================================================
-- TRANSFER OWNERSHIP TO SYSADMIN (required for DMF attachment)
-- ============================================================================

GRANT OWNERSHIP ON ALL TABLES IN SCHEMA HORIZON_DEMO_DB.HEALTHCARE TO ROLE SYSADMIN COPY CURRENT GRANTS;
