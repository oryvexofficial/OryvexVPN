-- v19: visitor accounts ("log in to watch")
-- Optional: the Worker creates this table by itself on first use.
CREATE TABLE IF NOT EXISTS members (
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
