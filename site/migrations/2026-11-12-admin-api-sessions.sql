-- Revocable app sessions for D1-backed admin/owner accounts.
-- Run from site/: npx wrangler d1 execute DB --file=./migrations/2026-11-12-admin-api-sessions.sql --remote
-- Safe to run repeatedly. Only token hashes are stored.
CREATE TABLE IF NOT EXISTS admin_api_sessions (
  token_hash TEXT PRIMARY KEY,
  username TEXT NOT NULL COLLATE NOCASE,
  stamp TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at INTEGER NOT NULL,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_admin_api_sessions_user ON admin_api_sessions(username);
CREATE INDEX IF NOT EXISTS idx_admin_api_sessions_expiry ON admin_api_sessions(expires_at);
