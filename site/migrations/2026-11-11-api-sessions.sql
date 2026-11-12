-- VexoStream native app API: revocable 30-day bearer sessions.
-- Run with: npx wrangler d1 execute DB --file=./migrations/2026-11-11-api-sessions.sql --remote
-- Safe to run more than once. Only stores token hashes, never raw bearer tokens.
CREATE TABLE IF NOT EXISTS api_sessions (
  token_hash TEXT PRIMARY KEY,
  member_id INTEGER NOT NULL,
  stamp TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at INTEGER NOT NULL,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_api_sessions_member_id ON api_sessions(member_id);
CREATE INDEX IF NOT EXISTS idx_api_sessions_expires_at ON api_sessions(expires_at);
