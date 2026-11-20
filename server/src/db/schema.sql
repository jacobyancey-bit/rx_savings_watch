-- rx_savings_watch Normalized SQLite Schema
-- Built for Node.js 22+ with node:sqlite

PRAGMA foreign_keys = ON;

-- 1. Drugs Table: Canonical concept registry mapped to NLM RxNorm RXCUI
CREATE TABLE IF NOT EXISTS drugs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rxcui TEXT UNIQUE NOT NULL,
    brand_name TEXT,
    generic_name TEXT NOT NULL,
    active_ingredient TEXT,
    dosage_form TEXT,
    strength TEXT,
    route TEXT,
    drug_type TEXT CHECK(drug_type IN ('small_molecule', 'biologic')) DEFAULT 'small_molecule',
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_drugs_rxcui ON drugs(rxcui);
CREATE INDEX IF NOT EXISTS idx_drugs_brand_name ON drugs(brand_name);
CREATE INDEX IF NOT EXISTS idx_drugs_generic_name ON drugs(generic_name);

-- 2. Generic Status Table: FDA Orange Book (ANDA) and Purple Book (Biosimilar/Interchangeable BLA)
CREATE TABLE IF NOT EXISTS generic_status (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_id INTEGER NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK(source IN ('orange_book', 'purple_book')),
    application_number TEXT NOT NULL,
    applicant TEXT,
    approval_date TEXT, -- Format: YYYY-MM-DD
    is_approved_generic INTEGER NOT NULL DEFAULT 0, -- 1 = approved generic/biosimilar
    te_code TEXT, -- Orange Book Therapeutic Equivalence code (AB, AP, AA, BX, etc.)
    biosimilar_status TEXT, -- Purple Book designation: 'biosimilar', 'interchangeable', or NULL
    reference_product_id TEXT, -- Reference NDA/BLA application number
    exclusivity_expiry_date TEXT,
    patent_expiry_date TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(drug_id, application_number, source)
);

CREATE INDEX IF NOT EXISTS idx_generic_status_drug ON generic_status(drug_id);
CREATE INDEX IF NOT EXISTS idx_generic_status_approval ON generic_status(approval_date);
CREATE INDEX IF NOT EXISTS idx_generic_status_app_no ON generic_status(application_number);
CREATE INDEX IF NOT EXISTS idx_generic_status_approved ON generic_status(is_approved_generic);

-- 3. Market Availability Table: OpenFDA NDC Directory, CMS NADAC pricing, and DailyMed
CREATE TABLE IF NOT EXISTS market_availability (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_id INTEGER NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK(source IN ('openfda_ndc', 'cms_nadac', 'dailymed')),
    ndc TEXT NOT NULL, -- 10 or 11 digit NDC
    labeler_name TEXT,
    marketing_category TEXT, -- 'ANDA', 'NDA', 'BLA', 'AUTHORIZED_GENERIC', etc.
    marketing_start_date TEXT, -- Format: YYYY-MM-DD
    marketing_end_date TEXT,
    is_commercialized INTEGER NOT NULL DEFAULT 0, -- 1 = observed active commercial presence
    nadac_per_unit REAL, -- CMS National Average Drug Acquisition Cost per unit ($)
    nadac_effective_date TEXT, -- Date of recorded NADAC acquisition cost
    pricing_unit TEXT, -- 'EA', 'ML', 'GM', etc.
    package_description TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(drug_id, ndc, source)
);

CREATE INDEX IF NOT EXISTS idx_market_availability_drug ON market_availability(drug_id);
CREATE INDEX IF NOT EXISTS idx_market_availability_ndc ON market_availability(ndc);
CREATE INDEX IF NOT EXISTS idx_market_availability_start ON market_availability(marketing_start_date);
CREATE INDEX IF NOT EXISTS idx_market_availability_pricing ON market_availability(nadac_effective_date);
CREATE INDEX IF NOT EXISTS idx_market_availability_comm ON market_availability(is_commercialized);

-- 4. Drug Shortages Table: FDA Drug Shortages / Market supply disruptions
CREATE TABLE IF NOT EXISTS drug_shortages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_id INTEGER REFERENCES drugs(id) ON DELETE CASCADE,
    generic_name TEXT NOT NULL,
    dosage_form TEXT,
    status TEXT NOT NULL CHECK(status IN ('Current', 'Resolved', 'Discontinued')),
    reason TEXT,
    shortage_start_date TEXT, -- Format: YYYY-MM-DD
    shortage_resolved_date TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_shortages_drug ON drug_shortages(drug_id);
CREATE INDEX IF NOT EXISTS idx_shortages_status ON drug_shortages(status);
CREATE INDEX IF NOT EXISTS idx_shortages_generic ON drug_shortages(generic_name);

-- 5. Alert Events Table: Detected commercial generic launches, price drops, and shortages
CREATE TABLE IF NOT EXISTS alert_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drug_id INTEGER NOT NULL REFERENCES drugs(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK(event_type IN (
        'commercial_generic_launch',
        'fda_generic_approved',
        'first_nadac_price',
        'price_drop',
        'shortage_started',
        'shortage_resolved'
    )),
    signal_summary TEXT NOT NULL,
    signal_details TEXT NOT NULL, -- JSON formatted details (signals, lag_days, savings_pct)
    confidence_score REAL NOT NULL CHECK(confidence_score >= 0.0 AND confidence_score <= 1.0),
    detected_at TEXT NOT NULL DEFAULT (datetime('now')),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_alert_events_drug_type ON alert_events(drug_id, event_type);
CREATE INDEX IF NOT EXISTS idx_alert_events_detected ON alert_events(detected_at);
CREATE INDEX IF NOT EXISTS idx_alert_events_drug ON alert_events(drug_id);
