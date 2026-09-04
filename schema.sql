-- ZenSched Snow & Ice Local Database Schema
-- SQLite database for contracts (HOA, commercial, municipal, residential),
-- a cache of plow / salt sites, the operator roster, storms, clears,
-- mileage, contract invoices / receivables, and 1099 operator payouts.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my snow-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 snow-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- THIS IS NOT REALGREEN / BOSS LM / GPS INSIGHT, AND IT IS NOT A LAWYER.
-- It does not know municipal plow ordinances, does not generate a slip-and-fall
-- defense package, and does not assert that a surface was legally safe.
-- sla_at_risk uses the deadline the owner typed (default 07:00). GPS punches
-- and after photos are the owner's record; courts and insurers decide the rest.
--
-- PRIVACY: customer contacts and gate / access notes live ONLY in this file
-- on your computer: contracts.contact_name, sites.access_notes. Site street
-- addresses DO go to ZenSched — the geofence needs them. ZenSched titles are
-- "Clear 2026-01-14 - Maple Ave" (storm date + street, never a contact).
-- SKILL.md forbids the agent from putting any local-only column into a
-- ZenSched field.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE / RESTRICT to work. SKILL.md tells the
-- agent to run it at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, defaults, business name, form id).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Snow Service');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-06:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('state', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_operator_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_clear_minutes', '180');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_clear_start', '04:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_sla_deadline', '07:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('proof_form_id', NULL);
-- IRS standard mileage rate for business use. 0.70 is the 2025 rate ($0.70/mile);
-- the IRS announces a new rate each December. Update this once a year.
INSERT OR IGNORE INTO settings (key, value) VALUES ('irs_mileage_rate', '0.70');

-- Contracts: who hires you and who pays you. An HOA / property manager, a
-- commercial lot owner, a municipality, or a residential driveway customer.
-- payment_terms_days drives invoice due dates. per_clear_fee / salt_fee
-- snapshot onto each clear when left NULL. sla_deadline (HH:MM) is the
-- morning the lot must be punched by; site and storm can override.
CREATE TABLE IF NOT EXISTS contracts (
  contract_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_name TEXT NOT NULL,
  contract_type TEXT NOT NULL DEFAULT 'commercial'
    CHECK (contract_type IN ('hoa', 'commercial', 'municipal', 'residential', 'other')),
  contact_name TEXT,                                -- AP / site contact, LOCAL ONLY
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER NOT NULL DEFAULT 30,   -- net 30 / net 45; cash = 0
  per_clear_fee REAL,                               -- $ per completed clear (a "push")
  salt_fee REAL,                                    -- $ added when salt_applied is yes or pretreated
  seasonal_fee REAL,                                -- informational; not auto-billed
  sla_deadline TEXT                                 -- 'HH:MM'; NULL -> settings.default_sla_deadline
    CHECK (sla_deadline IS NULL OR sla_deadline GLOB '[0-2][0-9]:[0-5][0-9]'),
  notes TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Sites: a cache of plow / salt addresses -> ZenSched location ids, and the
-- stop list under a contract. Snow routes hit the SAME lots every storm;
-- normalized_address is the de-dup key: the agent builds it as
-- lowercase(address + city + state + zip) with commas, periods, and '#'
-- removed and whitespace collapsed to single spaces (SQLite cannot collapse
-- whitespace, so the agent does it). The agent looks here FIRST and only
-- calls location_create (geocode, $0.03) on a miss. Hand-tuned pins
-- (location_update) therefore survive. place_label is the ONLY name sent to
-- ZenSched for this address; street_name (no house number) feeds event
-- titles ("Clear 2026-01-14 - Maple Ave"). access_notes is LOCAL ONLY
-- (gate code, "plow from the north entrance", hydrant).
CREATE TABLE IF NOT EXISTS sites (
  site_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  normalized_address TEXT NOT NULL UNIQUE,
  address TEXT NOT NULL,
  city TEXT,
  state TEXT,
  zip TEXT,
  street_name TEXT,                                 -- 'Maple Ave' (no number); used in event titles
  place_label TEXT,                                 -- sent to ZenSched: 'Lot - Maple Ave'
  surface TEXT NOT NULL DEFAULT 'driveway'
    CHECK (surface IN ('driveway', 'lot', 'walk', 'mixed')),
  sla_deadline TEXT                                 -- NULL -> contract, then storm, then settings
    CHECK (sla_deadline IS NULL OR sla_deadline GLOB '[0-2][0-9]:[0-5][0-9]'),
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  access_notes TEXT,                                -- LOCAL ONLY: gate, entrance, hydrant
  is_active INTEGER DEFAULT 1,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(contract_id) ON DELETE RESTRICT
);

-- Operators: in solo mode this is one row (you, is_owner = 1) whose
-- zensched_worker_id came from inviting yourself. In agency mode add a row
-- per 1099 plow / salt operator with payout_type/payout_value:
--   per_clear -> $ per clear actually completed
--   percent   -> % of the clear's billable total
CREATE TABLE IF NOT EXISTS operators (
  operator_id INTEGER PRIMARY KEY AUTOINCREMENT,
  operator_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  is_owner INTEGER DEFAULT 0,                       -- 1 = the business owner (no payouts)
  payout_type TEXT
    CHECK (payout_type IS NULL OR payout_type IN ('per_clear', 'percent')),
  payout_value REAL,                                -- $ (per_clear) or % (percent)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Storms: one weather event / "push". Opening a storm generates one clear
-- per active site (the agent inserts those rows). storm_date is the SLA
-- *morning* (the calendar day 07:00 belongs to), not the evening the snow
-- started. High-volume same-day: one ZenSched event per site on storm_date.
-- storm_ref is filled by trigger as 'ST-2026-0001' when NULL.
CREATE TABLE IF NOT EXISTS storms (
  storm_id INTEGER PRIMARY KEY AUTOINCREMENT,
  storm_ref TEXT UNIQUE,                            -- 'ST-2026-0001', filled by trigger if NULL
  storm_name TEXT,                                  -- 'Jan 14 snow', optional
  storm_date TEXT NOT NULL                          -- ISO date of the SLA morning
    CHECK (storm_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  storm_type TEXT NOT NULL DEFAULT 'snow'
    CHECK (storm_type IN ('snow', 'ice', 'mix')),
  sla_deadline TEXT                                 -- 'HH:MM'; NULL -> settings.default_sla_deadline
    CHECK (sla_deadline IS NULL OR sla_deadline GLOB '[0-2][0-9]:[0-5][0-9]'),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('forecast', 'active', 'closed', 'cancelled')),
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Clears: THE driving table. One row per site per storm (one ZenSched shift).
-- Two ways a row is born:
--   planned  - generated when the storm is opened (every active site)
--   ad hoc   - "I'm at Maple Lot now": scheduled_start = now, is_adhoc = 1,
--              and the operator punches within the minute
--
-- High volume, same day: ONE ZenSched EVENT per site per calendar day
-- (start_date = end_date = the clear date). A second push is a new storm,
-- which opens a new one-day event. The unique index below enforces one
-- non-cancelled clear per site per storm.
--
-- scheduled_start is LOCAL wall-clock time as 'YYYY-MM-DDTHH:MM' or
-- 'YYYY-MM-DDTHH:MM:SS' with NO offset and no 'Z'; NULL on insert is filled
-- by trigger as storm_date + settings.default_clear_start (04:00). The views
-- append settings.timezone_offset to produce start_iso / end_iso.
--
-- status: planned -> completed (Clear Proof pulled) | cancelled | skipped
--   (skipped = the owner closed it without a visit; bills other_fee only).
-- surface / condition / salt_applied / photo_count / report_dc_id come from
-- the Clear Proof form. checked_in_at / checked_out_at / gps_verified /
-- checkin_distance_m are copied from shift_status once.
CREATE TABLE IF NOT EXISTS clears (
  clear_id INTEGER PRIMARY KEY AUTOINCREMENT,
  storm_id INTEGER NOT NULL,
  site_id INTEGER NOT NULL,
  operator_id INTEGER,                              -- NULL -> settings.default_operator_id (trigger)
  scheduled_start TEXT                              -- local 'YYYY-MM-DDTHH:MM[:SS]', no offset; NULL -> trigger
    CHECK (scheduled_start IS NULL
           OR (scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-2][0-9]:[0-5][0-9]*'
               AND scheduled_start NOT GLOB '*T*[+-]*'
               AND scheduled_start NOT GLOB '*Z')),
  duration_minutes INTEGER                          -- NULL -> settings.default_clear_minutes
    CHECK (duration_minutes IS NULL OR duration_minutes BETWEEN 5 AND 720),
  is_adhoc INTEGER DEFAULT 0,                       -- 1 = "I'm here now" window created on the spot
  status TEXT NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned', 'completed', 'cancelled', 'skipped')),
  surface TEXT,                                     -- form option key: driveway, lot, walk, all
  condition TEXT,                                   -- form option key: bare, packed, icy
  salt_applied TEXT,                                -- form option key: yes, no, pretreated
  photo_count INTEGER DEFAULT 0,                    -- after photos (images stay on ZenSched)
  fee REAL,                                         -- NULL -> contract per_clear_fee (trigger)
  salt_fee REAL,                                    -- NULL -> contract salt_fee (trigger)
  other_fee REAL,                                   -- wait, extra pass, skip charge, ...
  invoiced INTEGER DEFAULT 0,
  paid_out INTEGER DEFAULT 0,
  zensched_event_id INTEGER,                        -- one-day event for this site on this date
  zensched_shift_id INTEGER UNIQUE,
  report_dc_id INTEGER,                             -- Clear Proof submission_id
  checked_in_at TEXT,                               -- from shift_status (ISO with offset)
  checked_out_at TEXT,
  gps_verified INTEGER,                             -- 1 if the check-in punch was on site
  checkin_distance_m INTEGER,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (storm_id) REFERENCES storms(storm_id) ON DELETE CASCADE,
  FOREIGN KEY (site_id) REFERENCES sites(site_id) ON DELETE RESTRICT,
  FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE SET NULL
);

-- Mileage: one row per trip. clear_id is NULL for non-clear trips (salt
-- reload, yard run). rate and deduction are filled by trigger when left NULL
-- (rate from settings.irs_mileage_rate at the time of the trip).
CREATE TABLE IF NOT EXISTS mileage (
  trip_id INTEGER PRIMARY KEY AUTOINCREMENT,
  clear_id INTEGER,
  trip_date TEXT NOT NULL,                          -- ISO date
  miles REAL NOT NULL CHECK (miles >= 0),
  from_label TEXT,                                  -- 'Yard', 'Lot - Maple Ave'
  to_label TEXT,
  purpose TEXT,                                     -- 'ST-2026-0001 Maple Ave'
  rate REAL,                                        -- $/mile snapshot (trigger)
  deduction REAL,                                   -- miles * rate (trigger)
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (clear_id) REFERENCES clears(clear_id) ON DELETE SET NULL
);

-- Invoices: one per contract per billing run. invoice_number is filled by
-- trigger if left NULL. due_date is invoice_date + the contract's
-- payment_terms_days. line_items is a JSON array with one object per clear
-- (storm ref, street, surface, condition, salt, fee breakdown).
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  contract_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (contract_id) REFERENCES contracts(contract_id) ON DELETE CASCADE
);

-- Payouts: what you owe a 1099 operator for one clear (agency mode).
-- One row per clear. amount is filled by trigger when left NULL:
--   per_clear -> operators.payout_value
--   percent   -> clear billable_total * payout_value / 100
-- Never insert a payout for the owner row.
CREATE TABLE IF NOT EXISTS payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  operator_id INTEGER NOT NULL,
  clear_id INTEGER NOT NULL UNIQUE,
  amount REAL,                                      -- trigger fills if NULL
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (operator_id) REFERENCES operators(operator_id) ON DELETE CASCADE,
  FOREIGN KEY (clear_id) REFERENCES clears(clear_id) ON DELETE CASCADE
);

-- One non-cancelled clear per site per storm. A second push is a new storm.
-- Cancelled rows drop out so a replacement clear can be inserted.
CREATE UNIQUE INDEX IF NOT EXISTS idx_clears_one_per_site_storm
ON clears(storm_id, site_id) WHERE status != 'cancelled';

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_sites_contract ON sites(contract_id, is_active);
CREATE INDEX IF NOT EXISTS idx_sites_location ON sites(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_storms_date_status ON storms(storm_date, status);
CREATE INDEX IF NOT EXISTS idx_clears_storm_status ON clears(storm_id, status);
CREATE INDEX IF NOT EXISTS idx_clears_site ON clears(site_id, status);
CREATE INDEX IF NOT EXISTS idx_clears_start ON clears(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_clears_operator ON clears(operator_id, status);
CREATE INDEX IF NOT EXISTS idx_clears_event ON clears(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_clears_invoiced ON clears(invoiced, status);
CREATE INDEX IF NOT EXISTS idx_mileage_date ON mileage(trip_date);
CREATE INDEX IF NOT EXISTS idx_mileage_clear ON mileage(clear_id);
CREATE INDEX IF NOT EXISTS idx_invoices_contract ON invoices(contract_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid, due_date);
CREATE INDEX IF NOT EXISTS idx_payouts_operator ON payouts(operator_id, paid);

-- What a clear bills depends on what happened. This is the single place
-- that rule lives; receivables, invoicing, and payouts read billable_total
-- from here rather than re-deriving it.
--   completed  -> fee + salt_fee (if salt_applied is yes or pretreated) + other_fee
--   skipped    -> other_fee only (owner closed without a completed visit)
--   cancelled  -> other_fee only
--   planned    -> 0
CREATE VIEW IF NOT EXISTS billable_clears AS
SELECT
  c.clear_id,
  c.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  c.site_id,
  si.contract_id,
  ct.contract_name,
  ct.contract_type,
  si.address,
  si.street_name,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  c.status,
  c.surface,
  c.condition,
  c.salt_applied,
  c.is_adhoc,
  date(COALESCE(substr(c.checked_in_at, 1, 19), c.scheduled_start, st.storm_date)) AS completed_date,
  c.fee,
  CASE WHEN c.status = 'completed' AND c.salt_applied IN ('yes', 'pretreated')
       THEN COALESCE(c.salt_fee, 0) ELSE 0 END                                   AS salt_fee_billed,
  c.other_fee,
  CASE c.status
    WHEN 'completed' THEN round(COALESCE(c.fee, 0)
                                + CASE WHEN c.salt_applied IN ('yes', 'pretreated')
                                       THEN COALESCE(c.salt_fee, 0) ELSE 0 END
                                + COALESCE(c.other_fee, 0), 2)
    WHEN 'skipped' THEN round(COALESCE(c.other_fee, 0), 2)
    WHEN 'cancelled' THEN round(COALESCE(c.other_fee, 0), 2)
    ELSE 0
  END                                                                            AS billable_total,
  c.invoiced,
  c.paid_out,
  c.operator_id
FROM clears c
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN contracts ct ON ct.contract_id = si.contract_id;

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_contract_timestamp
AFTER UPDATE ON contracts
BEGIN
  UPDATE contracts SET updated_at = datetime('now') WHERE contract_id = NEW.contract_id;
END;

CREATE TRIGGER IF NOT EXISTS update_site_timestamp
AFTER UPDATE ON sites
BEGIN
  UPDATE sites SET updated_at = datetime('now') WHERE site_id = NEW.site_id;
END;

CREATE TRIGGER IF NOT EXISTS update_operator_timestamp
AFTER UPDATE ON operators
BEGIN
  UPDATE operators SET updated_at = datetime('now') WHERE operator_id = NEW.operator_id;
END;

CREATE TRIGGER IF NOT EXISTS update_storm_timestamp
AFTER UPDATE OF storm_ref, storm_name, storm_date, storm_type, sla_deadline, status, notes
ON storms
BEGIN
  UPDATE storms SET updated_at = datetime('now') WHERE storm_id = NEW.storm_id;
END;

CREATE TRIGGER IF NOT EXISTS update_clear_timestamp
AFTER UPDATE OF storm_id, site_id, operator_id, scheduled_start, duration_minutes, is_adhoc,
                status, surface, condition, salt_applied, photo_count, fee, salt_fee, other_fee,
                invoiced, paid_out, zensched_event_id, zensched_shift_id, report_dc_id,
                checked_in_at, checked_out_at, gps_verified, checkin_distance_m, notes
ON clears
BEGIN
  UPDATE clears SET updated_at = datetime('now') WHERE clear_id = NEW.clear_id;
END;

-- Auto-number storms: ST-2026-0001, ST-2026-0002, ... (year of storm_date,
-- sequence = storm_id, so numbers never collide or reset). An explicit
-- storm_ref is kept.
CREATE TRIGGER IF NOT EXISTS number_storm
AFTER INSERT ON storms
WHEN NEW.storm_ref IS NULL
BEGIN
  UPDATE storms
  SET storm_ref = 'ST-' || strftime('%Y', NEW.storm_date) || '-' || printf('%04d', NEW.storm_id)
  WHERE storm_id = NEW.storm_id;
END;

-- Fill sla_deadline the agent left NULL from settings (else 07:00).
CREATE TRIGGER IF NOT EXISTS fill_storm_defaults
AFTER INSERT ON storms
BEGIN
  UPDATE storms
  SET sla_deadline = COALESCE(NEW.sla_deadline,
                              (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
                              '07:00')
  WHERE storm_id = NEW.storm_id;
END;

-- Fill defaults the agent left NULL:
--   scheduled_start  <- storm_date + settings.default_clear_start (else 04:00)
--   duration_minutes <- settings.default_clear_minutes (else 180)
--   operator_id      <- settings.default_operator_id (solo mode: you)
--   fee / salt_fee   <- the site's contract defaults, else 0
--   other_fee        <- 0
-- Fees are snapshots: changing a contract's defaults later never rewrites history.
CREATE TRIGGER IF NOT EXISTS fill_clear_defaults
AFTER INSERT ON clears
BEGIN
  UPDATE clears
  SET scheduled_start = COALESCE(NEW.scheduled_start,
                                 (SELECT storm_date FROM storms WHERE storm_id = NEW.storm_id)
                                   || 'T'
                                   || COALESCE((SELECT value FROM settings WHERE key = 'default_clear_start'), '04:00')),
      duration_minutes = COALESCE(NEW.duration_minutes,
                                  (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_clear_minutes'),
                                  180),
      operator_id = COALESCE(NEW.operator_id,
                             (SELECT CAST(value AS INTEGER) FROM settings WHERE key = 'default_operator_id' AND value IS NOT NULL)),
      fee = COALESCE(NEW.fee,
                     (SELECT ct.per_clear_fee FROM sites si JOIN contracts ct ON ct.contract_id = si.contract_id
                      WHERE si.site_id = NEW.site_id),
                     0),
      salt_fee = COALESCE(NEW.salt_fee,
                          (SELECT ct.salt_fee FROM sites si JOIN contracts ct ON ct.contract_id = si.contract_id
                           WHERE si.site_id = NEW.site_id),
                          0),
      other_fee = COALESCE(NEW.other_fee, 0)
  WHERE clear_id = NEW.clear_id;
END;

-- Mileage: snapshot the IRS rate and compute the deduction.
CREATE TRIGGER IF NOT EXISTS fill_mileage_deduction
AFTER INSERT ON mileage
BEGIN
  UPDATE mileage
  SET rate = COALESCE(NEW.rate, (SELECT CAST(value AS REAL) FROM settings WHERE key = 'irs_mileage_rate'), 0),
      deduction = round(NEW.miles * COALESCE(NEW.rate, (SELECT CAST(value AS REAL) FROM settings WHERE key = 'irs_mileage_rate'), 0), 2)
  WHERE trip_id = NEW.trip_id;
END;

CREATE TRIGGER IF NOT EXISTS recompute_mileage_deduction
AFTER UPDATE OF miles, rate ON mileage
BEGIN
  UPDATE mileage SET deduction = round(NEW.miles * COALESCE(NEW.rate, 0), 2) WHERE trip_id = NEW.trip_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Payout amount from the operator's split when the agent leaves it NULL.
-- per_clear -> payout_value
-- percent   -> billable_total of the clear * payout_value / 100
-- If the operator has no payout_type the amount stays NULL and payouts_due
-- flags it (needs_amount = 1).
CREATE TRIGGER IF NOT EXISTS fill_payout_amount
AFTER INSERT ON payouts
WHEN NEW.amount IS NULL
BEGIN
  UPDATE payouts
  SET amount = (SELECT CASE i.payout_type
                         WHEN 'per_clear' THEN i.payout_value
                         WHEN 'percent' THEN round((SELECT b.billable_total
                                                    FROM billable_clears b
                                                    WHERE b.clear_id = NEW.clear_id) * i.payout_value / 100.0, 2)
                       END
                FROM operators i
                WHERE i.operator_id = NEW.operator_id)
  WHERE payout_id = NEW.payout_id;
END;

-- Shared SLA clock for a clear: site override, else contract, else storm,
-- else settings (07:00). deadline_at is local wall-clock on storm_date.
-- Every planned clear (any date) with everything the agent needs to put it
-- on ZenSched. start_iso / end_iso carry settings.timezone_offset and are
-- ready for shift_create. High-volume same-day: one event per site per
-- calendar day — day_event_id is a sibling clear's event on the same site
-- and date, so an "I'm here now" on a site that already has today's event
-- is one shift_create.
--   needs_location = 1 -> the site has no ZenSched location yet
--   needs_event    = 1 -> this site has no event yet for this date
--   needs_shift    = 1 -> the clear has no ZenSched shift yet
--   event_start_date / event_end_date = the clear's local date (same-day event)
CREATE VIEW IF NOT EXISTS clears_planned AS
SELECT
  c.clear_id,
  c.status,
  c.is_adhoc,
  c.scheduled_start,
  c.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', c.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(c.scheduled_start, '+' || c.duration_minutes || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS end_iso,
  st.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  st.status                                                                       AS storm_status,
  COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline,
  st.storm_date || 'T' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline_at,
  CAST((julianday(st.storm_date || ' ' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00'))
        - julianday('now', 'localtime')) * 24 * 60 AS INTEGER)                    AS minutes_to_deadline,
  si.site_id,
  si.address,
  si.city,
  si.state,
  si.zip,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  COALESCE(si.place_label, 'Site - ' || COALESCE(si.street_name, si.address))     AS zensched_location_name,
  'Clear ' || st.storm_date || ' - ' || COALESCE(si.street_name, si.address)      AS zensched_event_title,
  si.surface                                                                      AS site_surface,
  si.access_notes                                                                 AS site_access_notes,
  si.zensched_location_id,
  CASE WHEN si.zensched_location_id IS NULL THEN 1 ELSE 0 END                     AS needs_location,
  COALESCE(c.zensched_event_id,
           (SELECT c2.zensched_event_id FROM clears c2
            WHERE c2.site_id = c.site_id
              AND date(c2.scheduled_start) = date(c.scheduled_start)
              AND c2.zensched_event_id IS NOT NULL
            ORDER BY c2.clear_id LIMIT 1))                                        AS zensched_event_id,
  CASE WHEN c.zensched_event_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM clears c2
                            WHERE c2.site_id = c.site_id
                              AND date(c2.scheduled_start) = date(c.scheduled_start)
                              AND c2.zensched_event_id IS NOT NULL) THEN 1 ELSE 0 END AS needs_event,
  date(c.scheduled_start)                                                         AS event_start_date,
  date(c.scheduled_start)                                                         AS event_end_date,
  c.zensched_shift_id,
  CASE WHEN c.zensched_shift_id IS NULL THEN 1 ELSE 0 END                         AS needs_shift,
  c.operator_id,
  i.operator_name,
  i.zensched_worker_id,
  ct.contract_id,
  ct.contract_name,
  ct.contract_type,
  c.notes,
  'loc-site-' || si.site_id                                                       AS loc_idempotency_key,
  'event-site-' || si.site_id || '-' || strftime('%Y%m%d', c.scheduled_start)     AS event_idempotency_key,
  'shift-clear-' || c.clear_id                                                    AS shift_idempotency_key
FROM clears c
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN contracts ct ON ct.contract_id = si.contract_id
LEFT JOIN operators i ON i.operator_id = c.operator_id
WHERE c.status = 'planned'
ORDER BY c.scheduled_start, si.street_name;

-- Today's board: planned and completed clears whose local date is today
-- (the computer running the database). Completed rows stay so the owner can
-- see what is done vs still out. Same columns as clears_planned plus
-- surface / condition / salt / GPS stamps for completed stops.
CREATE VIEW IF NOT EXISTS clears_today AS
SELECT
  c.clear_id,
  c.status,
  c.is_adhoc,
  c.scheduled_start,
  c.duration_minutes,
  strftime('%Y-%m-%dT%H:%M:%S', c.scheduled_start)
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS start_iso,
  strftime('%Y-%m-%dT%H:%M:%S', datetime(c.scheduled_start, '+' || COALESCE(c.duration_minutes, 180) || ' minutes'))
    || (SELECT value FROM settings WHERE key = 'timezone_offset')                 AS end_iso,
  st.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  st.status                                                                       AS storm_status,
  COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline,
  st.storm_date || 'T' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline_at,
  CAST((julianday(st.storm_date || ' ' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00'))
        - julianday('now', 'localtime')) * 24 * 60 AS INTEGER)                    AS minutes_to_deadline,
  si.site_id,
  si.address,
  si.city,
  si.state,
  si.zip,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  COALESCE(si.place_label, 'Site - ' || COALESCE(si.street_name, si.address))     AS zensched_location_name,
  'Clear ' || st.storm_date || ' - ' || COALESCE(si.street_name, si.address)      AS zensched_event_title,
  si.surface                                                                      AS site_surface,
  si.access_notes                                                                 AS site_access_notes,
  si.zensched_location_id,
  CASE WHEN si.zensched_location_id IS NULL THEN 1 ELSE 0 END                     AS needs_location,
  COALESCE(c.zensched_event_id,
           (SELECT c2.zensched_event_id FROM clears c2
            WHERE c2.site_id = c.site_id
              AND date(c2.scheduled_start) = date(c.scheduled_start)
              AND c2.zensched_event_id IS NOT NULL
            ORDER BY c2.clear_id LIMIT 1))                                        AS zensched_event_id,
  CASE WHEN c.zensched_event_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM clears c2
                            WHERE c2.site_id = c.site_id
                              AND date(c2.scheduled_start) = date(c.scheduled_start)
                              AND c2.zensched_event_id IS NOT NULL) THEN 1 ELSE 0 END AS needs_event,
  date(c.scheduled_start)                                                         AS event_start_date,
  date(c.scheduled_start)                                                         AS event_end_date,
  c.zensched_shift_id,
  CASE WHEN c.zensched_shift_id IS NULL AND c.status = 'planned' THEN 1 ELSE 0 END AS needs_shift,
  c.operator_id,
  i.operator_name,
  i.zensched_worker_id,
  ct.contract_id,
  ct.contract_name,
  ct.contract_type,
  c.surface,
  c.condition,
  c.salt_applied,
  c.photo_count,
  c.gps_verified,
  c.checkin_distance_m,
  c.checked_in_at,
  c.checked_out_at,
  c.notes,
  'loc-site-' || si.site_id                                                       AS loc_idempotency_key,
  'event-site-' || si.site_id || '-' || strftime('%Y%m%d', c.scheduled_start)     AS event_idempotency_key,
  'shift-clear-' || c.clear_id                                                    AS shift_idempotency_key
FROM clears c
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN contracts ct ON ct.contract_id = si.contract_id
LEFT JOIN operators i ON i.operator_id = c.operator_id
WHERE c.status IN ('planned', 'completed')
  AND date(c.scheduled_start) = date('now', 'localtime')
ORDER BY c.scheduled_start, si.street_name;

-- Same planned columns, next 7 days (today through today + 6).
CREATE VIEW IF NOT EXISTS clears_upcoming AS
SELECT *
FROM clears_planned
WHERE date(scheduled_start) BETWEEN date('now', 'localtime') AND date('now', 'localtime', '+6 days')
ORDER BY scheduled_start;

-- Active / forecast storms: every active site that does not yet have a
-- completed clear. Includes sites the agent never generated a clear for
-- (needs_clear = 1) and planned clears still on the phone. Lead with this
-- after sla_at_risk when the owner asks "what's left".
CREATE VIEW IF NOT EXISTS sites_uncleared AS
SELECT
  st.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  st.status                                                                       AS storm_status,
  si.site_id,
  si.address,
  si.city,
  si.state,
  si.zip,
  si.street_name,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  COALESCE(si.place_label, 'Site - ' || COALESCE(si.street_name, si.address))     AS zensched_location_name,
  'Clear ' || st.storm_date || ' - ' || COALESCE(si.street_name, si.address)      AS zensched_event_title,
  si.surface                                                                      AS site_surface,
  si.access_notes                                                                 AS site_access_notes,
  si.zensched_location_id,
  CASE WHEN si.zensched_location_id IS NULL THEN 1 ELSE 0 END                     AS needs_location,
  ct.contract_id,
  ct.contract_name,
  ct.contract_type,
  COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline,
  st.storm_date || 'T' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline_at,
  c.clear_id,
  c.status                                                                        AS clear_status,
  c.scheduled_start,
  c.zensched_event_id,
  c.zensched_shift_id,
  c.operator_id,
  i.operator_name,
  i.zensched_worker_id,
  CASE WHEN c.clear_id IS NULL THEN 1 ELSE 0 END                                  AS needs_clear,
  CASE WHEN c.clear_id IS NOT NULL AND c.zensched_shift_id IS NULL THEN 1 ELSE 0 END AS needs_shift,
  'loc-site-' || si.site_id                                                       AS loc_idempotency_key,
  'event-site-' || si.site_id || '-' || REPLACE(st.storm_date, '-', '')           AS event_idempotency_key,
  CASE WHEN c.clear_id IS NOT NULL THEN 'shift-clear-' || c.clear_id END          AS shift_idempotency_key
FROM storms st
JOIN sites si ON si.is_active = 1
JOIN contracts ct ON ct.contract_id = si.contract_id AND ct.is_active = 1
LEFT JOIN clears c ON c.storm_id = st.storm_id AND c.site_id = si.site_id AND c.status != 'cancelled'
LEFT JOIN operators i ON i.operator_id = c.operator_id
WHERE st.status IN ('forecast', 'active')
  AND (c.clear_id IS NULL OR c.status = 'planned')
ORDER BY st.storm_date, sla_deadline_at, si.street_name;

-- Planned clears that have not checked in, with the deadline within 60
-- minutes or already past. "Not checked in before deadline" — this is the
-- view to lead every session with. minutes_to_deadline is negative once
-- the clock has passed. A completed clear never appears, even if the
-- punch was late (that is a logged miss, not at-risk).
CREATE VIEW IF NOT EXISTS sla_at_risk AS
SELECT
  c.clear_id,
  c.status,
  c.scheduled_start,
  c.checked_in_at,
  c.zensched_shift_id,
  CASE WHEN c.zensched_shift_id IS NULL THEN 1 ELSE 0 END                         AS needs_shift,
  st.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  st.status                                                                       AS storm_status,
  COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline,
  st.storm_date || 'T' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00')                                                               AS sla_deadline_at,
  CAST((julianday(st.storm_date || ' ' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00'))
        - julianday('now', 'localtime')) * 24 * 60 AS INTEGER)                    AS minutes_to_deadline,
  CASE WHEN julianday('now', 'localtime')
            >= julianday(st.storm_date || ' ' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00'))
       THEN 1 ELSE 0 END                                                          AS deadline_passed,
  si.site_id,
  si.address,
  si.street_name,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  si.access_notes                                                                 AS site_access_notes,
  ct.contract_id,
  ct.contract_name,
  c.operator_id,
  i.operator_name,
  i.zensched_worker_id
FROM clears c
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN contracts ct ON ct.contract_id = si.contract_id
LEFT JOIN operators i ON i.operator_id = c.operator_id
WHERE c.status = 'planned'
  AND c.checked_in_at IS NULL
  AND julianday('now', 'localtime')
        >= julianday(st.storm_date || ' ' || COALESCE(NULLIF(si.sla_deadline, ''),
           NULLIF(ct.sla_deadline, ''),
           NULLIF(st.sla_deadline, ''),
           (SELECT value FROM settings WHERE key = 'default_sla_deadline'),
           '07:00'), '-60 minutes')
ORDER BY minutes_to_deadline, si.street_name;

-- Forecast / active storms, for the session-start board.
CREATE VIEW IF NOT EXISTS storms_open AS
SELECT
  st.storm_id,
  st.storm_ref,
  st.storm_name,
  st.storm_date,
  st.storm_type,
  st.sla_deadline,
  st.status,
  (SELECT COUNT(*) FROM sites si JOIN contracts ct ON ct.contract_id = si.contract_id
    WHERE si.is_active = 1 AND ct.is_active = 1)                                  AS active_sites,
  (SELECT COUNT(*) FROM clears c WHERE c.storm_id = st.storm_id AND c.status = 'planned') AS planned_clears,
  (SELECT COUNT(*) FROM clears c WHERE c.storm_id = st.storm_id AND c.status = 'completed') AS completed_clears,
  (SELECT COUNT(*) FROM clears c WHERE c.storm_id = st.storm_id AND c.status = 'skipped') AS skipped_clears,
  (SELECT COUNT(*) FROM sites si JOIN contracts ct ON ct.contract_id = si.contract_id
    WHERE si.is_active = 1 AND ct.is_active = 1
      AND NOT EXISTS (SELECT 1 FROM clears c
                      WHERE c.storm_id = st.storm_id AND c.site_id = si.site_id
                        AND c.status IN ('planned', 'completed', 'skipped')))     AS sites_without_clear
FROM storms st
WHERE st.status IN ('forecast', 'active')
ORDER BY st.storm_date, st.storm_id;

-- Sites on an open storm or a planned clear that still need a ZenSched
-- location (location_create, $0.03). One row per site.
CREATE VIEW IF NOT EXISTS needs_location AS
SELECT
  si.site_id,
  si.address,
  si.city,
  si.state,
  si.zip,
  si.street_name,
  si.address || COALESCE(', ' || si.city, '') || COALESCE(', ' || si.state, '') || COALESCE(' ' || si.zip, '') AS street_address,
  COALESCE(si.place_label, 'Site - ' || COALESCE(si.street_name, si.address)) AS zensched_location_name,
  si.zensched_location_id,
  si.access_notes,
  si.surface,
  si.contract_id,
  1                                                AS needs_location,
  'loc-site-' || si.site_id                        AS loc_idempotency_key,
  (SELECT COUNT(*) FROM clears c WHERE c.site_id = si.site_id AND c.status = 'planned') AS planned_clears
FROM sites si
WHERE si.zensched_location_id IS NULL
  AND si.is_active = 1
  AND (
    EXISTS (SELECT 1 FROM clears c WHERE c.site_id = si.site_id AND c.status = 'planned')
    OR EXISTS (SELECT 1 FROM storms st WHERE st.status IN ('forecast', 'active'))
  )
ORDER BY si.site_id;

-- Uninvoiced billable work grouped by contract, with the billing contact and
-- terms. Completed clears bill the fee plus salt; skipped / cancelled bill
-- other_fee only (see billable_clears).
CREATE VIEW IF NOT EXISTS receivables_by_contract AS
SELECT
  ct.contract_id,
  ct.contract_name,
  ct.contract_type,
  ct.contact_name,
  ct.billing_email,
  ct.payment_terms_days,
  COUNT(b.clear_id)                                AS clear_count,
  SUM(CASE WHEN b.status = 'completed' THEN 1 ELSE 0 END) AS completed_count,
  SUM(CASE WHEN b.status = 'skipped' THEN 1 ELSE 0 END) AS skipped_count,
  SUM(b.billable_total)                            AS total_billable,
  MIN(b.storm_date)                                AS first_date,
  MAX(COALESCE(b.completed_date, b.storm_date))    AS last_date
FROM billable_clears b
JOIN contracts ct ON ct.contract_id = b.contract_id
WHERE b.invoiced = 0
  AND b.status IN ('completed', 'skipped', 'cancelled')
  AND b.billable_total > 0
GROUP BY ct.contract_id
ORDER BY total_billable DESC;

-- Unpaid invoices with aging. days_past_due is negative while not yet due.
--   current : not yet due
--   30      : 1-30 days past due
--   60      : 31-60 days past due
--   90+     : more than 60 days past due
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  ct.contract_id,
  ct.contract_name,
  ct.contract_type,
  ct.contact_name,
  ct.billing_email,
  ct.payment_terms_days,
  i.invoice_date,
  i.due_date,
  i.sent_date,
  i.total_amount,
  CAST(julianday(date('now', 'localtime')) - julianday(i.due_date) AS INTEGER) AS days_past_due,
  CASE
    WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 0  THEN 'current'
    WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 30 THEN '30'
    WHEN julianday(date('now', 'localtime')) - julianday(i.due_date) <= 60 THEN '60'
    ELSE '90+'
  END                                              AS aging_bucket,
  CASE WHEN i.due_date < date('now', 'localtime') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN contracts ct ON ct.contract_id = i.contract_id
WHERE i.paid = 0
ORDER BY i.due_date;

-- Mileage by calendar month: trips, miles, and the deduction at the snapshot rate.
CREATE VIEW IF NOT EXISTS mileage_by_month AS
SELECT
  strftime('%Y-%m', m.trip_date)                   AS month,
  COUNT(m.trip_id)                                 AS trips,
  SUM(m.miles)                                     AS miles,
  SUM(m.deduction)                                 AS deduction,
  SUM(CASE WHEN m.clear_id IS NULL THEN m.miles ELSE 0 END) AS non_clear_miles
FROM mileage m
GROUP BY strftime('%Y-%m', m.trip_date)
ORDER BY month DESC;

-- Agency mode: unpaid 1099 payouts, one row per clear, with a running total
-- per operator (operator_total_due). Owner rows never appear.
-- needs_amount = 1 means the operator has no payout_type; ask the owner.
CREATE VIEW IF NOT EXISTS payouts_due AS
SELECT
  p.payout_id,
  i.operator_id,
  i.operator_name,
  i.email,
  i.payout_type,
  i.payout_value,
  c.clear_id,
  st.storm_id,
  st.storm_ref,
  COALESCE(si.street_name, si.address)             AS site_label,
  c.status                                         AS clear_status,
  date(COALESCE(substr(c.checked_in_at, 1, 19), c.scheduled_start)) AS work_date,
  c.surface,
  c.condition,
  c.salt_applied,
  b.billable_total,
  p.amount,
  CASE WHEN p.amount IS NULL THEN 1 ELSE 0 END     AS needs_amount,
  SUM(p.amount) OVER (PARTITION BY i.operator_id)  AS operator_total_due,
  c.invoiced                                       AS contract_invoiced
FROM payouts p
JOIN operators i ON i.operator_id = p.operator_id
JOIN clears c ON c.clear_id = p.clear_id
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN billable_clears b ON b.clear_id = c.clear_id
WHERE p.paid = 0
  AND i.is_owner = 0
ORDER BY i.operator_name, work_date;

-- Agency mode: completed clears worked by a sub that have no payouts row yet.
CREATE VIEW IF NOT EXISTS payouts_missing AS
SELECT
  c.clear_id,
  st.storm_ref,
  COALESCE(si.street_name, si.address)             AS site_label,
  c.status,
  date(COALESCE(substr(c.checked_in_at, 1, 19), c.scheduled_start)) AS work_date,
  c.surface,
  c.condition,
  i.operator_id,
  i.operator_name,
  i.payout_type,
  i.payout_value,
  b.billable_total
FROM clears c
JOIN operators i ON i.operator_id = c.operator_id AND i.is_owner = 0
JOIN storms st ON st.storm_id = c.storm_id
JOIN sites si ON si.site_id = c.site_id
JOIN billable_clears b ON b.clear_id = c.clear_id
WHERE c.status = 'completed'
  AND NOT EXISTS (SELECT 1 FROM payouts p WHERE p.clear_id = c.clear_id)
ORDER BY work_date;

-- Per operator, last 30 days: clears completed, condition mix, ad hoc share,
-- and the share whose check-in was GPS-verified. Owner included so the solo
-- operator sees their own numbers.
CREATE VIEW IF NOT EXISTS operator_activity AS
SELECT
  i.operator_id,
  i.operator_name,
  i.is_owner,
  i.is_active,
  COUNT(c.clear_id)                                AS clears_30d,
  SUM(CASE WHEN c.condition = 'bare' THEN 1 ELSE 0 END)            AS bare_30d,
  SUM(CASE WHEN c.condition = 'packed' THEN 1 ELSE 0 END)          AS packed_30d,
  SUM(CASE WHEN c.condition = 'icy' THEN 1 ELSE 0 END)             AS icy_30d,
  SUM(CASE WHEN c.salt_applied IN ('yes', 'pretreated') THEN 1 ELSE 0 END) AS salted_30d,
  SUM(CASE WHEN c.is_adhoc = 1 THEN 1 ELSE 0 END)                  AS adhoc_30d,
  SUM(CASE WHEN c.gps_verified = 1 THEN 1 ELSE 0 END)              AS gps_verified_30d,
  CASE WHEN COUNT(c.clear_id) > 0
       THEN round(100.0 * SUM(CASE WHEN c.gps_verified = 1 THEN 1 ELSE 0 END) / COUNT(c.clear_id), 1) END AS gps_verified_pct,
  SUM(CASE WHEN c.photo_count > 0 THEN 1 ELSE 0 END)               AS with_photo_30d,
  MAX(COALESCE(substr(c.checked_in_at, 1, 16), c.scheduled_start)) AS last_clear_at,
  (SELECT COUNT(*) FROM clears c2 WHERE c2.operator_id = i.operator_id AND c2.status = 'planned'
     AND c2.scheduled_start >= strftime('%Y-%m-%dT%H:%M', 'now', 'localtime')) AS planned_ahead
FROM operators i
LEFT JOIN clears c ON c.operator_id = i.operator_id
  AND c.status = 'completed'
  AND date(COALESCE(substr(c.checked_in_at, 1, 19), c.scheduled_start)) >= date('now', 'localtime', '-30 days')
GROUP BY i.operator_id
ORDER BY clears_30d DESC, i.operator_name;
