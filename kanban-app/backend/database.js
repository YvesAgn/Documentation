const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'kanban.db');

let db;

function getDb() {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma('journal_mode = WAL');
    initSchema();
  }
  return db;
}

function initSchema() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS cards (
      id TEXT PRIMARY KEY,
      company_name TEXT NOT NULL,
      website TEXT DEFAULT '',
      email TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      column_id TEXT NOT NULL DEFAULT 'leads',
      position INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE INDEX IF NOT EXISTS idx_cards_column ON cards(column_id, position);
    CREATE INDEX IF NOT EXISTS idx_cards_email ON cards(email);
    CREATE INDEX IF NOT EXISTS idx_cards_company ON cards(company_name COLLATE NOCASE);
  `);
}

module.exports = { getDb };
