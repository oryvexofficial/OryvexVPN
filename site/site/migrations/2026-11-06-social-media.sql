-- VexoStream: Social media section (Telegram bot + channel + social links)
-- Safe to run more than once. Only adds missing rows/tables.
-- Run with:  npx wrangler d1 execute DB --file=./migrations/2026-11-06-social-media.sql --remote

INSERT OR IGNORE INTO settings (key, value) VALUES ('social_config', '{}');

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
