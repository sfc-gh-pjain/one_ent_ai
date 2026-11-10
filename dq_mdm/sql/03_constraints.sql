-- ============================================================
-- Constraints: Primary Keys, Foreign Keys, Unique
-- Healthcare Commercial Analytics Pipeline
-- ============================================================
-- Informational constraints (not enforced) — used by optimizer and BI tools

USE ROLE SYSADMIN;
USE WAREHOUSE MY_WH;
USE SCHEMA DEMO.HEALTHCARE_DEMO;

-- ============================================================
-- 1. Primary Keys on Dimension Tables
-- ============================================================

ALTER TABLE DIM_DRUG ADD CONSTRAINT PK_DIM_DRUG PRIMARY KEY (DRUG_ID);
ALTER TABLE DIM_TERRITORY ADD CONSTRAINT PK_DIM_TERRITORY PRIMARY KEY (TERRITORY_ID);
ALTER TABLE DIM_REGION ADD CONSTRAINT PK_DIM_REGION PRIMARY KEY (REGION_ID);
ALTER TABLE DIM_THERAPEUTIC_AREA ADD CONSTRAINT PK_DIM_THERAPEUTIC_AREA PRIMARY KEY (THERAPEUTIC_AREA_ID);

-- ============================================================
-- 2. Primary Keys on Source Tables
-- ============================================================

ALTER TABLE RAW_PRESCRIPTIONS ADD CONSTRAINT PK_RAW_PRESCRIPTIONS PRIMARY KEY (RX_ID);
ALTER TABLE RAW_HCP_PROFILES ADD CONSTRAINT PK_RAW_HCP_PROFILES PRIMARY KEY (HCP_ID);
ALTER TABLE RAW_HCP_ENGAGEMENTS ADD CONSTRAINT PK_RAW_HCP_ENGAGEMENTS PRIMARY KEY (ENGAGEMENT_ID);

-- ============================================================
-- 3. Primary Keys on Target Tables
-- ============================================================

ALTER TABLE HCP_TIERED_PROFILES ADD CONSTRAINT PK_HCP_TIERED_PROFILES PRIMARY KEY (HCP_ID);
ALTER TABLE ENGAGEMENT_FINAL ADD CONSTRAINT PK_ENGAGEMENT_FINAL PRIMARY KEY (ENGAGEMENT_ID);
ALTER TABLE HCP_GOLDEN_RECORD ADD CONSTRAINT PK_HCP_GOLDEN_RECORD PRIMARY KEY (HCP_ID);

-- ============================================================
-- 4. Foreign Keys (Informational)
-- ============================================================

-- Prescriptions → Dimensions
ALTER TABLE RAW_PRESCRIPTIONS ADD CONSTRAINT FK_RX_DRUG
    FOREIGN KEY (DRUG_ID) REFERENCES DIM_DRUG (DRUG_ID) NOT ENFORCED;
ALTER TABLE RAW_PRESCRIPTIONS ADD CONSTRAINT FK_RX_TERRITORY
    FOREIGN KEY (TERRITORY_ID) REFERENCES DIM_TERRITORY (TERRITORY_ID) NOT ENFORCED;

-- HCP Profiles → Dimensions
ALTER TABLE RAW_HCP_PROFILES ADD CONSTRAINT FK_HCP_TERRITORY
    FOREIGN KEY (TERRITORY_ID) REFERENCES DIM_TERRITORY (TERRITORY_ID) NOT ENFORCED;
ALTER TABLE RAW_HCP_PROFILES ADD CONSTRAINT FK_HCP_THERAPEUTIC_AREA
    FOREIGN KEY (THERAPEUTIC_AREA_ID) REFERENCES DIM_THERAPEUTIC_AREA (THERAPEUTIC_AREA_ID) NOT ENFORCED;

-- Territory → Region
ALTER TABLE DIM_TERRITORY ADD CONSTRAINT FK_TERRITORY_REGION
    FOREIGN KEY (REGION_ID) REFERENCES DIM_REGION (REGION_ID) NOT ENFORCED;

-- ============================================================
-- 5. Unique Constraints
-- ============================================================

ALTER TABLE RAW_HCP_PROFILES ADD CONSTRAINT UQ_HCP_NPI UNIQUE (NPI_NUMBER) NOT ENFORCED;
ALTER TABLE DIM_DRUG ADD CONSTRAINT UQ_DRUG_NAME UNIQUE (DRUG_NAME) NOT ENFORCED;

-- ============================================================
-- 6. Verify
-- ============================================================

SHOW PRIMARY KEYS IN SCHEMA DEMO.HEALTHCARE_DEMO;
SHOW IMPORTED KEYS IN SCHEMA DEMO.HEALTHCARE_DEMO;
