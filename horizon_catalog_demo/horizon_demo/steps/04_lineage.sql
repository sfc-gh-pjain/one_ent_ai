USE ROLE SYSADMIN;
USE DATABASE HORIZON_DEMO_DB;
USE SCHEMA HEALTHCARE;
USE WAREHOUSE MY_WH;

-- Staging views
CREATE OR REPLACE VIEW STG_PATIENTS AS
SELECT patient_id, INITCAP(first_name) AS first_name, INITCAP(last_name) AS last_name,
  ssn, LOWER(email) AS email, phone, date_of_birth,
  DATEDIFF('year', date_of_birth, CURRENT_DATE()) AS age,
  gender, blood_type, department, insurance_provider, city, state, created_at
FROM PATIENTS;

CREATE OR REPLACE VIEW STG_BILLING AS
SELECT billing_id, patient_id, appointment_id, service_code, service_desc,
  amount_charged, amount_paid, insurance_covered,
  amount_charged - amount_paid - insurance_covered AS outstanding_balance,
  billing_date, payment_status, insurance_claim_id,
  DATEDIFF('day', billing_date, CURRENT_DATE()) AS days_since_billed
FROM BILLING;

CREATE OR REPLACE VIEW STG_APPOINTMENTS AS
SELECT appointment_id, patient_id, doctor_id, appointment_date, department,
  visit_type, status, diagnosis_code, duration_min,
  DATEDIFF('day', appointment_date, CURRENT_DATE()) AS days_since_visit
FROM APPOINTMENTS;

-- Dynamic table (aggregates all staging views)
CREATE OR REPLACE DYNAMIC TABLE PATIENT_ANALYTICS
  TARGET_LAG = '1 hour'
  WAREHOUSE = MY_WH
AS
SELECT
  p.patient_id, p.first_name, p.last_name, p.age, p.gender,
  p.department, p.insurance_provider, p.city, p.state,
  COUNT(DISTINCT a.appointment_id) AS total_appointments,
  COUNT(DISTINCT CASE WHEN a.status = 'COMPLETED' THEN a.appointment_id END) AS completed_visits,
  COUNT(DISTINCT CASE WHEN a.status = 'NO_SHOW' THEN a.appointment_id END) AS no_shows,
  MAX(a.appointment_date) AS last_visit_date,
  SUM(b.amount_charged) AS total_billed,
  SUM(b.amount_paid) AS total_paid,
  SUM(b.insurance_covered) AS total_insurance_covered,
  SUM(b.amount_charged) - SUM(b.amount_paid) - SUM(b.insurance_covered) AS total_outstanding
FROM STG_PATIENTS p
LEFT JOIN STG_APPOINTMENTS a ON p.patient_id = a.patient_id
LEFT JOIN STG_BILLING b ON p.patient_id = b.patient_id
GROUP BY p.patient_id, p.first_name, p.last_name, p.age, p.gender,
         p.department, p.insurance_provider, p.city, p.state;

-- Secure dashboard views
CREATE OR REPLACE SECURE VIEW REVENUE_DASHBOARD AS
SELECT department, insurance_provider, state,
  COUNT(*) AS patient_count,
  ROUND(AVG(total_billed), 2) AS avg_billed_per_patient,
  ROUND(AVG(total_paid), 2) AS avg_paid_per_patient,
  ROUND(SUM(total_outstanding), 2) AS total_outstanding_balance,
  ROUND(AVG(total_appointments), 1) AS avg_visits_per_patient,
  ROUND(AVG(no_shows)::FLOAT / NULLIF(AVG(total_appointments), 0) * 100, 1) AS no_show_pct
FROM PATIENT_ANALYTICS
GROUP BY department, insurance_provider, state
HAVING COUNT(*) >= 5;

CREATE OR REPLACE SECURE VIEW DEPARTMENT_METRICS AS
SELECT department, COUNT(*) AS total_patients,
  ROUND(AVG(age), 1) AS avg_age,
  SUM(total_appointments) AS total_appointments,
  SUM(completed_visits) AS total_completed,
  SUM(no_shows) AS total_no_shows,
  ROUND(SUM(no_shows)::FLOAT / NULLIF(SUM(total_appointments), 0) * 100, 1) AS no_show_rate,
  ROUND(AVG(total_billed), 2) AS avg_revenue_per_patient
FROM PATIENT_ANALYTICS
GROUP BY department;
