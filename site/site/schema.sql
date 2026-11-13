-- ============================================================================
-- VexoStream — Combined schema (D1 edition)
-- Databases: DB (vexostream) and STATUS
-- Non-destructive: only creates missing tables/indexes.
-- Existing saved data is preserved.
-- ============================================================================


-- ============================================================================
-- SECTION 1 — DB  (database_name = "vexostream")
-- Run with:  npx wrangler d1 execute DB --file=./schema.sql --remote
-- ============================================================================

PRAGMA foreign_keys = ON;

-- Admin settings (maintenance mode, feature flags, etc.)
CREATE TABLE IF NOT EXISTS settings (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  key         TEXT NOT NULL UNIQUE,
  value       TEXT,
  updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

-- Maintenance records
CREATE TABLE IF NOT EXISTS maintenance_records (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  title        TEXT NOT NULL,
  details      TEXT,
  status_code  TEXT,
  created_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_maintenance_records_status_code
  ON maintenance_records(status_code);

CREATE INDEX IF NOT EXISTS idx_maintenance_records_created_at
  ON maintenance_records(created_at);

-- Admin users
CREATE TABLE IF NOT EXISTS admins (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  username       TEXT NOT NULL UNIQUE,
  password_hash  TEXT NOT NULL,
  is_active      INTEGER NOT NULL DEFAULT 1,
  created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admins_username ON admins(username);


-- Native Windows app bearer sessions. Only token hashes are stored.
CREATE TABLE IF NOT EXISTS api_sessions (
  token_hash  TEXT PRIMARY KEY,
  member_id   INTEGER NOT NULL,
  stamp       TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at  INTEGER NOT NULL,
  revoked_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_api_sessions_member_id ON api_sessions(member_id);
CREATE INDEX IF NOT EXISTS idx_api_sessions_expires_at ON api_sessions(expires_at);

-- Admin accounts used by the Worker admin panel (Team & permissions).
-- The Worker also creates this table by itself on first sign-in.
-- permissions: JSON array of site | backend | providers | operations | social | users
-- (the owner always has every permission, including social)
CREATE TABLE IF NOT EXISTS admin_users (
  username       TEXT PRIMARY KEY COLLATE NOCASE,
  password_hash  TEXT NOT NULL,          -- PBKDF2-SHA256 hex
  salt           TEXT NOT NULL,
  iterations     INTEGER NOT NULL DEFAULT 100000,
  permissions    TEXT NOT NULL DEFAULT '[]',
  is_owner       INTEGER NOT NULL DEFAULT 0,
  disabled       INTEGER NOT NULL DEFAULT 0,
  stamp          TEXT NOT NULL,          -- rotates to sign out old sessions
  created_by     TEXT,
  created_at     TEXT DEFAULT CURRENT_TIMESTAMP,
  updated_at     TEXT DEFAULT CURRENT_TIMESTAMP,
  last_login     TEXT
);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,
  admin_id    INTEGER NOT NULL,
  expires_at  TEXT NOT NULL,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_admin_id ON sessions(admin_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

-- Safe default rows (only insert if missing)
INSERT OR IGNORE INTO settings (key, value) VALUES ('maintenance_mode', 'off');
INSERT OR IGNORE INTO settings (key, value) VALUES ('maintenance_message', 'We are performing scheduled maintenance.');
-- Provider locks (Admin > Providers). JSON, managed by the Worker; '{}' = everything live.
INSERT OR IGNORE INTO settings (key, value) VALUES ('provider_config', '{}');
-- Telegram owner-panel settings. The bot token value is stored encrypted by the
-- Worker; keep it blank here and enter the token from Admin > Telegram.
INSERT OR IGNORE INTO settings (key, value) VALUES ('telegram_bot_token_enc', '');
INSERT OR IGNORE INTO settings (key, value) VALUES ('telegram_webhook_origin', '');
-- Note: the Worker also creates/upgrades this table by itself (Admin > Database > Repair).

-- Live viewers counter (Admin > Live viewers, owner only). JSON, managed by the Worker.
-- '{}' = counter hidden. Real visitors are counted from live_presence heartbeats.
INSERT OR IGNORE INTO settings (key, value) VALUES ('live_config', '{}');

CREATE TABLE IF NOT EXISTS live_presence (
  sid        TEXT PRIMARY KEY,          -- random browser id, no personal data
  last_seen  INTEGER NOT NULL           -- unix seconds of the latest heartbeat
);

CREATE INDEX IF NOT EXISTS idx_live_presence_last_seen ON live_presence(last_seen);

-- Social media (Admin > Social media, permission "social"). JSON, managed by the Worker:
-- links (telegram, x, instagram, youtube, tiktok, discord, reddit, whatsapp, facebook, website),
-- showInFooter, botButtons, channel { chatId, title, inviteUrl }.
INSERT OR IGNORE INTO settings (key, value) VALUES ('social_config', '{}');

-- Telegram channel posts sent from the admin panel (the Worker also creates this table).
CREATE TABLE IF NOT EXISTS social_posts (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  network     TEXT NOT NULL DEFAULT 'telegram',
  chat_id     TEXT NOT NULL,
  message_id  INTEGER,
  text        TEXT,
  posted_by   TEXT,
  pinned      INTEGER NOT NULL DEFAULT 0,
  deleted     INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_social_posts_created_at ON social_posts(created_at);


-- ============================================================================
-- SECTION 2 — STATUS  (database_name = "STATUS")
-- Run with:  npx wrangler d1 execute STATUS --file=./schema.sql --remote
-- ============================================================================

PRAGMA foreign_keys = ON;

-- Status definitions (e.g. online, degraded, offline)
CREATE TABLE IF NOT EXISTS statuses (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT NOT NULL UNIQUE,
  label       TEXT NOT NULL,
  description TEXT,
  color       TEXT,
  is_active   INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_statuses_code ON statuses(code);
CREATE INDEX IF NOT EXISTS idx_statuses_is_active ON statuses(is_active);

-- Status history / incidents
CREATE TABLE IF NOT EXISTS status_history (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  status_id   INTEGER,
  status_code TEXT,
  note        TEXT,
  created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (status_id) REFERENCES statuses(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_status_history_status_id
  ON status_history(status_id);

CREATE INDEX IF NOT EXISTS idx_status_history_created_at
  ON status_history(created_at);

-- Safe default rows (only insert if missing)
INSERT OR IGNORE INTO statuses (code, label, description, color) VALUES
  ('online',   'Online',   'All systems operational.',          'green'),
  ('degraded', 'Degraded', 'Some systems are experiencing issues.', 'yellow'),
  ('offline',  'Offline',  'Major outage in progress.',         'red');CREATE TABLE IF NOT EXISTS members (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  username       TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash  TEXT NOT NULL,          -- PBKDF2-SHA256 hex
  salt           TEXT NOT NULL,
  iterations     INTEGER NOT NULL DEFAULT 100000,
  stamp          TEXT NOT NULL,          -- rotates to sign a member out everywhere
  disabled       INTEGER NOT NULL DEFAULT 0,
  created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at  TEXT
);
