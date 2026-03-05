#!/bin/bash
# =============================================================================
#  Kanban App – Kompletter Server-Setup (kein GitHub nötig)
#  Ausführen auf dem Server: bash server-setup.sh
# =============================================================================
set -e
APP="/var/www/kanban"

echo "==> Verzeichnisse anlegen..."
mkdir -p "$APP/backend/routes" "$APP/backend/uploads"
mkdir -p "$APP/frontend/public" "$APP/frontend/src/components"

# ── docker-compose.yml ────────────────────────────────────────────────────────
cat > "$APP/docker-compose.yml" << 'EOF'
services:
  backend:
    build: ./backend
    restart: always
    ports:
      - "44174:3001"
    environment:
      - PORT=3001
      - CLIENT_URL=http://159.195.34.237:44215
      - DB_PATH=/data/kanban.db
    volumes:
      - kanban_data:/data
      - kanban_uploads:/app/uploads
  frontend:
    build: ./frontend
    restart: always
    ports:
      - "44215:80"
    depends_on:
      - backend
volumes:
  kanban_data:
  kanban_uploads:
EOF

# ── backend/Dockerfile ────────────────────────────────────────────────────────
cat > "$APP/backend/Dockerfile" << 'EOF'
FROM node:20-alpine
RUN apk add --no-cache python3 make g++
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
RUN mkdir -p /data /app/uploads
EXPOSE 3001
CMD ["node", "server.js"]
EOF

# ── backend/package.json ──────────────────────────────────────────────────────
cat > "$APP/backend/package.json" << 'EOF'
{
  "name": "kanban-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "better-sqlite3": "^9.4.3",
    "cors": "^2.8.5",
    "exceljs": "^4.4.0",
    "express": "^4.18.3",
    "multer": "^2.1.1",
    "pdf-parse": "^1.1.1",
    "uuid": "^9.0.1"
  }
}
EOF

# ── backend/server.js ─────────────────────────────────────────────────────────
cat > "$APP/backend/server.js" << 'EOF'
const express = require('express');
const cors = require('cors');
const path = require('path');
const cardsRouter = require('./routes/cards');
const uploadRouter = require('./routes/upload');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors({ origin: process.env.CLIENT_URL || 'http://localhost:3000' }));
app.use(express.json());
app.use('/api/cards', cardsRouter);
app.use('/api/upload', uploadRouter);
app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

const frontendBuild = path.join(__dirname, '../frontend/build');
if (require('fs').existsSync(frontendBuild)) {
  app.use(express.static(frontendBuild));
  app.get('*', (req, res) => res.sendFile(path.join(frontendBuild, 'index.html')));
}

app.listen(PORT, () => console.log(`Kanban backend running on http://localhost:${PORT}`));
EOF

# ── backend/database.js ───────────────────────────────────────────────────────
cat > "$APP/backend/database.js" << 'EOF'
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
EOF

# ── backend/routes/cards.js ───────────────────────────────────────────────────
cat > "$APP/backend/routes/cards.js" << 'EOF'
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../database');
const router = express.Router();

router.get('/', (req, res) => {
  try {
    const db = getDb();
    const cards = db.prepare(`SELECT * FROM cards ORDER BY column_id, position ASC, company_name COLLATE NOCASE ASC`).all();
    const columns = { leads: [], 'angebot-versendet': [], nachfassen: [] };
    for (const card of cards) {
      if (columns[card.column_id] !== undefined) columns[card.column_id].push(card);
    }
    res.json(columns);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.post('/', (req, res) => {
  try {
    const db = getDb();
    const { company_name, website = '', email = '', phone = '', column_id = 'leads' } = req.body;
    if (!company_name || !company_name.trim()) return res.status(400).json({ error: 'company_name is required' });
    const maxPos = db.prepare(`SELECT COALESCE(MAX(position), -1) as max_pos FROM cards WHERE column_id = ?`).get(column_id);
    const card = { id: uuidv4(), company_name: company_name.trim(), website: website.trim(), email: email.trim().toLowerCase(), phone: phone.trim(), column_id, position: maxPos.max_pos + 1 };
    db.prepare(`INSERT INTO cards (id, company_name, website, email, phone, column_id, position) VALUES (@id, @company_name, @website, @email, @phone, @column_id, @position)`).run(card);
    res.status(201).json(card);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.put('/:id', (req, res) => {
  try {
    const db = getDb();
    const { id } = req.params;
    const { company_name, website, email, phone } = req.body;
    const existing = db.prepare(`SELECT * FROM cards WHERE id = ?`).get(id);
    if (!existing) return res.status(404).json({ error: 'Card not found' });
    const updated = { id, company_name: (company_name ?? existing.company_name).trim(), website: (website ?? existing.website).trim(), email: (email ?? existing.email).trim().toLowerCase(), phone: (phone ?? existing.phone).trim() };
    db.prepare(`UPDATE cards SET company_name = @company_name, website = @website, email = @email, phone = @phone, updated_at = datetime('now') WHERE id = @id`).run(updated);
    res.json({ ...existing, ...updated });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.delete('/:id', (req, res) => {
  try {
    const db = getDb();
    const result = db.prepare(`DELETE FROM cards WHERE id = ?`).run(req.params.id);
    if (result.changes === 0) return res.status(404).json({ error: 'Card not found' });
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.patch('/reorder', (req, res) => {
  try {
    const db = getDb();
    const { columns } = req.body;
    const updateStmt = db.prepare(`UPDATE cards SET column_id = @column_id, position = @position, updated_at = datetime('now') WHERE id = @id`);
    const applyAll = db.transaction(() => {
      for (const [column_id, cards] of Object.entries(columns)) {
        cards.forEach((card, index) => updateStmt.run({ id: card.id, column_id, position: index }));
      }
    });
    applyAll();
    res.json({ success: true });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

module.exports = router;
EOF

# ── backend/routes/upload.js ──────────────────────────────────────────────────
cat > "$APP/backend/routes/upload.js" << 'EOF'
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../database');

const router = express.Router();

const storage = multer.diskStorage({
  destination: path.join(__dirname, '../uploads'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});

const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (['.pdf', '.xlsx', '.xls', '.csv'].includes(ext)) cb(null, true);
    else cb(new Error('Only PDF, Excel (.xlsx/.xls) and CSV files are allowed'));
  },
});

const EMAIL_RE = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;
const PHONE_RE = /(?:\+?\d{1,3}[\s\-.]?)?\(?\d{2,4}\)?[\s\-.]?\d{3,4}[\s\-.]?\d{3,6}(?:[\s\-.]?\d{1,4})?/g;
const URL_RE = /(?:https?:\/\/)?(?:www\.)?[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}(?:\/[^\s,;)]*)?/g;

function extractFromText(text) {
  const emails = (text.match(EMAIL_RE) || []).map(e => e.toLowerCase());
  const phones = (text.match(PHONE_RE) || []).filter(p => p.replace(/\D/g, '').length >= 7);
  const urls = (text.match(URL_RE) || []).filter(u => !EMAIL_RE.test(u) && !u.match(/^\d/));
  return { emails, phones, urls };
}

function blocksToLeads(text) {
  const blocks = text.split(/\n{2,}/).map(b => b.trim()).filter(Boolean);
  const leads = [];
  for (const block of blocks) {
    const lines = block.split('\n').map(l => l.trim()).filter(Boolean);
    if (!lines.length) continue;
    const { emails, phones, urls } = extractFromText(block);
    const company_name = lines.find(l => !EMAIL_RE.test(l) && !PHONE_RE.test(l) && !URL_RE.test(l) && l.length > 1) || lines[0];
    if (!company_name) continue;
    leads.push({ company_name: company_name.replace(/[*_#]+/g, '').trim(), website: urls[0] || '', email: emails[0] || '', phone: phones[0] || '' });
  }
  return leads;
}

async function parsePdf(filePath) {
  const pdfParse = require('pdf-parse');
  const buffer = fs.readFileSync(filePath);
  const data = await pdfParse(buffer);
  return blocksToLeads(data.text);
}

async function parseExcel(filePath) {
  const ExcelJS = require('exceljs');
  const workbook = new ExcelJS.Workbook();
  const ext = path.extname(filePath).toLowerCase();
  const leads = [];
  if (ext === '.csv') await workbook.csv.readFile(filePath);
  else await workbook.xlsx.readFile(filePath);
  workbook.eachSheet(sheet => {
    const headers = [];
    sheet.eachRow((row, rowNum) => {
      if (rowNum === 1) { row.eachCell((cell, colNum) => { headers[colNum] = String(cell.value || '').toLowerCase().replace(/[\s_\-]+/g, ''); }); return; }
      const norm = {};
      row.eachCell((cell, colNum) => { if (headers[colNum]) norm[headers[colNum]] = String(cell.value ?? '').trim(); });
      const company_name = norm['firmenname'] || norm['company'] || norm['companyname'] || norm['unternehmen'] || norm['name'] || '';
      if (!company_name) return;
      leads.push({ company_name, website: norm['webseite'] || norm['website'] || norm['url'] || norm['homepage'] || '', email: (norm['email'] || norm['mail'] || norm['emailadresse'] || '').toLowerCase(), phone: norm['telefon'] || norm['phone'] || norm['telefonnummer'] || norm['tel'] || norm['mobile'] || norm['mobil'] || '' });
    });
  });
  return leads;
}

router.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  const filePath = req.file.path;
  const ext = path.extname(req.file.originalname).toLowerCase();
  try {
    let rawLeads = [];
    if (ext === '.pdf') rawLeads = await parsePdf(filePath);
    else if (['.xlsx', '.xls', '.csv'].includes(ext)) rawLeads = await parseExcel(filePath);
    else return res.status(400).json({ error: 'Unsupported file type' });

    const db = getDb();
    const existing = db.prepare(`SELECT company_name, email FROM cards`).all();
    const existingEmails = new Set(existing.map(c => c.email.toLowerCase()).filter(Boolean));
    const existingNames = new Set(existing.map(c => c.company_name.toLowerCase().trim()));
    const maxPos = db.prepare(`SELECT COALESCE(MAX(position), -1) as max_pos FROM cards WHERE column_id = 'leads'`).get();
    let nextPos = maxPos.max_pos + 1;
    const insertStmt = db.prepare(`INSERT INTO cards (id, company_name, website, email, phone, column_id, position) VALUES (@id, @company_name, @website, @email, @phone, @column_id, @position)`);
    const inserted = [], skipped = [];
    rawLeads.sort((a, b) => a.company_name.localeCompare(b.company_name, 'de', { sensitivity: 'base' }));
    const insertAll = db.transaction(() => {
      for (const lead of rawLeads) {
        const nameLower = lead.company_name.toLowerCase().trim();
        const emailLower = lead.email.toLowerCase().trim();
        if ((emailLower && existingEmails.has(emailLower)) || existingNames.has(nameLower)) { skipped.push(lead.company_name); continue; }
        const card = { id: uuidv4(), company_name: lead.company_name, website: lead.website, email: emailLower, phone: lead.phone, column_id: 'leads', position: nextPos++ };
        insertStmt.run(card);
        inserted.push(card);
        existingNames.add(nameLower);
        if (emailLower) existingEmails.add(emailLower);
      }
    });
    insertAll();
    fs.unlink(filePath, () => {});
    res.json({ inserted: inserted.length, skipped: skipped.length, skipped_names: skipped, cards: inserted });
  } catch (err) {
    fs.unlink(filePath, () => {});
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
EOF

# ── frontend/Dockerfile ───────────────────────────────────────────────────────
cat > "$APP/frontend/Dockerfile" << 'EOF'
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.25-alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
EOF

# ── frontend/nginx.conf ───────────────────────────────────────────────────────
cat > "$APP/frontend/nginx.conf" << 'EOF'
server {
    listen 80;
    client_max_body_size 25M;
    location /api/ {
        proxy_pass         http://backend:3001;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   Connection        keep-alive;
        proxy_read_timeout 60s;
    }
    location / {
        root   /usr/share/nginx/html;
        index  index.html;
        try_files $uri /index.html;
    }
}
EOF

# ── frontend/package.json ─────────────────────────────────────────────────────
cat > "$APP/frontend/package.json" << 'EOF'
{
  "name": "kanban-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@hello-pangea/dnd": "^16.6.0",
    "axios": "^1.6.8",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "proxy": "http://localhost:3001",
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version"]
  }
}
EOF

# ── frontend/public/index.html ────────────────────────────────────────────────
cat > "$APP/frontend/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="de">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#2563eb" />
    <title>Kanban – Lead Management</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
  </head>
  <body>
    <noscript>JavaScript is required to run this application.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

# ── frontend/src/index.js ─────────────────────────────────────────────────────
cat > "$APP/frontend/src/index.js" << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<React.StrictMode><App /></React.StrictMode>);
EOF

# ── frontend/src/index.css ────────────────────────────────────────────────────
cat > "$APP/frontend/src/index.css" << 'EOF'
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Inter', system-ui, sans-serif; background: #f0f4f8; color: #1e293b; min-height: 100vh; }
button { cursor: pointer; font-family: inherit; }
input, textarea { font-family: inherit; }
EOF

# ── frontend/src/App.js ───────────────────────────────────────────────────────
cat > "$APP/frontend/src/App.js" << 'EOF'
import React, { useState, useEffect, useCallback } from 'react';
import { DragDropContext } from '@hello-pangea/dnd';
import axios from 'axios';
import Board from './components/Board';
import CardModal from './components/CardModal';
import FileUpload from './components/FileUpload';
import Toast from './components/Toast';
import './App.css';

const COLUMNS = [
  { id: 'leads', label: 'Leads', color: '#dbeafe', accent: '#2563eb' },
  { id: 'angebot-versendet', label: 'Angebot versendet', color: '#dcfce7', accent: '#16a34a' },
  { id: 'nachfassen', label: 'Nachfassen', color: '#fef9c3', accent: '#ca8a04' },
];

export default function App() {
  const [columns, setColumns] = useState({ leads: [], 'angebot-versendet': [], nachfassen: [] });
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState(null);
  const [toast, setToast] = useState(null);

  const showToast = useCallback((message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3500);
  }, []);

  const fetchCards = useCallback(async () => {
    try {
      const { data } = await axios.get('/api/cards');
      setColumns(data);
    } catch { showToast('Fehler beim Laden der Karten', 'error'); }
    finally { setLoading(false); }
  }, [showToast]);

  useEffect(() => { fetchCards(); }, [fetchCards]);

  const onDragEnd = useCallback(async (result) => {
    const { source, destination } = result;
    if (!destination) return;
    if (source.droppableId === destination.droppableId && source.index === destination.index) return;
    setColumns((prev) => {
      const next = { ...prev };
      const srcCards = Array.from(next[source.droppableId]);
      const [moved] = srcCards.splice(source.index, 1);
      moved.column_id = destination.droppableId;
      if (source.droppableId === destination.droppableId) {
        srcCards.splice(destination.index, 0, moved);
        next[source.droppableId] = srcCards;
      } else {
        const dstCards = Array.from(next[destination.droppableId]);
        dstCards.splice(destination.index, 0, moved);
        next[source.droppableId] = srcCards;
        next[destination.droppableId] = dstCards;
      }
      return next;
    });
    setColumns((current) => {
      axios.patch('/api/cards/reorder', {
        columns: Object.fromEntries(Object.entries(current).map(([colId, cards]) => [colId, cards.map((c, i) => ({ id: c.id, position: i }))])),
      }).catch(() => showToast('Reihenfolge konnte nicht gespeichert werden', 'error'));
      return current;
    });
  }, [showToast]);

  const handleSaveCard = async (data) => {
    try {
      if (modal.mode === 'create') {
        const { data: created } = await axios.post('/api/cards', { ...data, column_id: modal.columnId });
        setColumns((prev) => ({ ...prev, [modal.columnId]: [...prev[modal.columnId], created] }));
        showToast('Karte erstellt');
      } else {
        const { data: updated } = await axios.put(`/api/cards/${modal.card.id}`, data);
        setColumns((prev) => { const colId = modal.card.column_id; return { ...prev, [colId]: prev[colId].map(c => c.id === updated.id ? updated : c) }; });
        showToast('Karte aktualisiert');
      }
      setModal(null);
    } catch (err) { showToast(err.response?.data?.error || 'Fehler beim Speichern', 'error'); }
  };

  const handleDeleteCard = async (card) => {
    if (!window.confirm(`„${card.company_name}" wirklich löschen?`)) return;
    try {
      await axios.delete(`/api/cards/${card.id}`);
      setColumns((prev) => ({ ...prev, [card.column_id]: prev[card.column_id].filter(c => c.id !== card.id) }));
      showToast('Karte gelöscht');
    } catch { showToast('Fehler beim Löschen', 'error'); }
  };

  const handleImportDone = ({ inserted, skipped, cards: newCards }) => {
    if (newCards?.length) {
      setColumns((prev) => ({ ...prev, leads: [...prev.leads, ...newCards].sort((a, b) => a.company_name.localeCompare(b.company_name, 'de', { sensitivity: 'base' })) }));
    }
    showToast(`Import abgeschlossen: ${inserted} neu hinzugefügt, ${skipped} übersprungen`, inserted > 0 ? 'success' : 'info');
  };

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-inner">
          <h1 className="app-title"><span className="title-icon">📋</span> Lead-Kanban</h1>
          <FileUpload onImportDone={handleImportDone} onError={(msg) => showToast(msg, 'error')} />
        </div>
      </header>
      <main className="board-wrapper">
        {loading ? <div className="loading">Lädt…</div> : (
          <DragDropContext onDragEnd={onDragEnd}>
            <Board columns={COLUMNS} cards={columns} onAddCard={(columnId) => setModal({ mode: 'create', columnId })} onEditCard={(card) => setModal({ mode: 'edit', card })} onDeleteCard={handleDeleteCard} />
          </DragDropContext>
        )}
      </main>
      {modal && <CardModal mode={modal.mode} card={modal.card} onSave={handleSaveCard} onClose={() => setModal(null)} />}
      {toast && <Toast message={toast.message} type={toast.type} />}
    </div>
  );
}
EOF

# ── frontend/src/App.css ──────────────────────────────────────────────────────
cat > "$APP/frontend/src/App.css" << 'EOF'
.app { min-height: 100vh; display: flex; flex-direction: column; }
.app-header { background: #1e293b; padding: 0 24px; height: 64px; display: flex; align-items: center; box-shadow: 0 2px 8px rgba(0,0,0,.25); position: sticky; top: 0; z-index: 100; }
.header-inner { width: 100%; max-width: 1400px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.app-title { font-size: 1.35rem; font-weight: 700; color: #f8fafc; white-space: nowrap; display: flex; align-items: center; gap: 8px; }
.title-icon { font-size: 1.4rem; }
.board-wrapper { flex: 1; padding: 28px 24px; max-width: 1400px; margin: 0 auto; width: 100%; }
.loading { text-align: center; padding: 80px 0; font-size: 1.1rem; color: #64748b; }
.board { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; align-items: start; }
@media (max-width: 900px) { .board { grid-template-columns: 1fr; } .board-wrapper { padding: 16px 12px; } }
.column { border-radius: 14px; display: flex; flex-direction: column; min-height: 200px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
.column-header { padding: 14px 16px 12px; display: flex; align-items: center; justify-content: space-between; gap: 8px; border-bottom: 2px solid rgba(0,0,0,.07); }
.column-title { font-size: .95rem; font-weight: 700; letter-spacing: .01em; }
.column-count { font-size: .8rem; font-weight: 600; background: rgba(0,0,0,.12); border-radius: 20px; padding: 2px 9px; margin-right: auto; margin-left: 6px; }
.add-btn { background: none; border: none; width: 30px; height: 30px; border-radius: 8px; font-size: 1.3rem; line-height: 1; display: flex; align-items: center; justify-content: center; color: rgba(0,0,0,.55); transition: background .15s, color .15s; }
.add-btn:hover { background: rgba(0,0,0,.1); color: rgba(0,0,0,.8); }
.column-body { padding: 10px; flex: 1; display: flex; flex-direction: column; gap: 8px; min-height: 80px; transition: background .15s; }
.column-body.is-dragging-over { background: rgba(0,0,0,.05); border-radius: 0 0 14px 14px; }
.column-empty { text-align: center; padding: 20px 0; font-size: .85rem; color: rgba(0,0,0,.35); user-select: none; }
.card { background: #fff; border-radius: 10px; padding: 12px 14px; box-shadow: 0 1px 3px rgba(0,0,0,.1); transition: box-shadow .15s, transform .15s; cursor: grab; position: relative; border-left: 4px solid transparent; }
.card:hover { box-shadow: 0 4px 12px rgba(0,0,0,.14); }
.card.is-dragging { box-shadow: 0 8px 24px rgba(0,0,0,.2); transform: rotate(1.5deg); }
.card-company { font-size: .92rem; font-weight: 700; margin-bottom: 6px; color: #0f172a; }
.card-fields { display: flex; flex-direction: column; gap: 3px; }
.card-field { font-size: .78rem; color: #475569; display: flex; align-items: center; gap: 5px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.card-field a { color: #2563eb; text-decoration: none; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.card-field a:hover { text-decoration: underline; }
.field-icon { flex-shrink: 0; font-size: .85rem; }
.card-actions { display: flex; gap: 4px; position: absolute; top: 8px; right: 8px; opacity: 0; transition: opacity .15s; }
.card:hover .card-actions { opacity: 1; }
.icon-btn { width: 26px; height: 26px; border-radius: 6px; border: none; background: rgba(0,0,0,.06); display: flex; align-items: center; justify-content: center; font-size: .75rem; transition: background .15s; }
.icon-btn:hover { background: rgba(0,0,0,.14); }
.icon-btn.danger:hover { background: #fee2e2; }
.upload-area { display: flex; align-items: center; gap: 10px; }
.upload-label { display: flex; align-items: center; gap: 7px; padding: 8px 16px; background: #2563eb; color: #fff; border-radius: 8px; font-size: .85rem; font-weight: 600; cursor: pointer; transition: background .15s; white-space: nowrap; }
.upload-label:hover { background: #1d4ed8; }
.upload-label.loading { background: #64748b; cursor: wait; }
.upload-input { display: none; }
.upload-status { font-size: .8rem; color: #94a3b8; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 180px; }
.modal-overlay { position: fixed; inset: 0; background: rgba(15,23,42,.5); display: flex; align-items: center; justify-content: center; z-index: 500; padding: 16px; backdrop-filter: blur(2px); }
.modal { background: #fff; border-radius: 16px; padding: 28px; width: 100%; max-width: 460px; box-shadow: 0 20px 60px rgba(0,0,0,.2); animation: modal-in .18s ease; }
@keyframes modal-in { from { opacity: 0; transform: scale(.96) translateY(-8px); } to { opacity: 1; transform: scale(1) translateY(0); } }
.modal-title { font-size: 1.1rem; font-weight: 700; margin-bottom: 20px; color: #0f172a; }
.form-group { margin-bottom: 14px; display: flex; flex-direction: column; gap: 5px; }
.form-group label { font-size: .82rem; font-weight: 600; color: #475569; }
.form-group input { padding: 9px 12px; border: 1.5px solid #e2e8f0; border-radius: 8px; font-size: .9rem; transition: border-color .15s, box-shadow .15s; outline: none; }
.form-group input:focus { border-color: #2563eb; box-shadow: 0 0 0 3px rgba(37,99,235,.12); }
.modal-actions { display: flex; gap: 10px; justify-content: flex-end; margin-top: 20px; }
.btn { padding: 9px 20px; border-radius: 8px; border: none; font-size: .88rem; font-weight: 600; transition: background .15s, transform .1s; }
.btn:active { transform: scale(.97); }
.btn-primary { background: #2563eb; color: #fff; }
.btn-primary:hover { background: #1d4ed8; }
.btn-secondary { background: #f1f5f9; color: #475569; }
.btn-secondary:hover { background: #e2e8f0; }
.toast { position: fixed; bottom: 28px; left: 50%; transform: translateX(-50%); padding: 12px 22px; border-radius: 10px; font-size: .88rem; font-weight: 600; box-shadow: 0 4px 20px rgba(0,0,0,.18); z-index: 1000; animation: toast-in .2s ease, toast-out .3s ease 3.2s forwards; white-space: nowrap; }
.toast.success { background: #16a34a; color: #fff; }
.toast.error { background: #dc2626; color: #fff; }
.toast.info { background: #0369a1; color: #fff; }
@keyframes toast-in { from { opacity: 0; transform: translateX(-50%) translateY(12px); } to { opacity: 1; transform: translateX(-50%) translateY(0); } }
@keyframes toast-out { from { opacity: 1; } to { opacity: 0; } }
EOF

# ── frontend/src/components/Board.js ─────────────────────────────────────────
cat > "$APP/frontend/src/components/Board.js" << 'EOF'
import React from 'react';
import Column from './Column';

export default function Board({ columns, cards, onAddCard, onEditCard, onDeleteCard }) {
  return (
    <div className="board">
      {columns.map((col) => (
        <Column key={col.id} column={col} cards={cards[col.id] || []} onAdd={() => onAddCard(col.id)} onEdit={onEditCard} onDelete={onDeleteCard} />
      ))}
    </div>
  );
}
EOF

# ── frontend/src/components/Column.js ────────────────────────────────────────
cat > "$APP/frontend/src/components/Column.js" << 'EOF'
import React from 'react';
import { Droppable } from '@hello-pangea/dnd';
import Card from './Card';

export default function Column({ column, cards, onAdd, onEdit, onDelete }) {
  return (
    <div className="column" style={{ background: column.color, borderTop: `4px solid ${column.accent}` }}>
      <div className="column-header">
        <span className="column-title" style={{ color: column.accent }}>{column.label}</span>
        <span className="column-count">{cards.length}</span>
        <button className="add-btn" onClick={onAdd} title="Karte hinzufügen">+</button>
      </div>
      <Droppable droppableId={column.id}>
        {(provided, snapshot) => (
          <div className={`column-body${snapshot.isDraggingOver ? ' is-dragging-over' : ''}`} ref={provided.innerRef} {...provided.droppableProps}>
            {cards.length === 0 && <p className="column-empty">Keine Karten</p>}
            {cards.map((card, index) => (
              <Card key={card.id} card={card} index={index} accent={column.accent} onEdit={() => onEdit(card)} onDelete={() => onDelete(card)} />
            ))}
            {provided.placeholder}
          </div>
        )}
      </Droppable>
    </div>
  );
}
EOF

# ── frontend/src/components/Card.js ──────────────────────────────────────────
cat > "$APP/frontend/src/components/Card.js" << 'EOF'
import React from 'react';
import { Draggable } from '@hello-pangea/dnd';

function normalizeUrl(url) {
  if (!url) return null;
  return url.startsWith('http') ? url : `https://${url}`;
}

export default function Card({ card, index, accent, onEdit, onDelete }) {
  return (
    <Draggable draggableId={card.id} index={index}>
      {(provided, snapshot) => (
        <div className={`card${snapshot.isDragging ? ' is-dragging' : ''}`} style={{ borderLeftColor: accent, ...provided.draggableProps.style }} ref={provided.innerRef} {...provided.draggableProps} {...provided.dragHandleProps}>
          <p className="card-company">{card.company_name}</p>
          <div className="card-fields">
            {card.website && <span className="card-field"><span className="field-icon">🌐</span><a href={normalizeUrl(card.website)} target="_blank" rel="noreferrer" onClick={e => e.stopPropagation()}>{card.website}</a></span>}
            {card.email && <span className="card-field"><span className="field-icon">✉️</span><a href={`mailto:${card.email}`} onClick={e => e.stopPropagation()}>{card.email}</a></span>}
            {card.phone && <span className="card-field"><span className="field-icon">📞</span><a href={`tel:${card.phone}`} onClick={e => e.stopPropagation()}>{card.phone}</a></span>}
          </div>
          <div className="card-actions">
            <button className="icon-btn" onClick={onEdit} title="Bearbeiten">✏️</button>
            <button className="icon-btn danger" onClick={onDelete} title="Löschen">🗑️</button>
          </div>
        </div>
      )}
    </Draggable>
  );
}
EOF

# ── frontend/src/components/CardModal.js ─────────────────────────────────────
cat > "$APP/frontend/src/components/CardModal.js" << 'EOF'
import React, { useState, useEffect, useRef } from 'react';

const EMPTY = { company_name: '', website: '', email: '', phone: '' };

export default function CardModal({ mode, card, onSave, onClose }) {
  const [form, setForm] = useState(EMPTY);
  const firstRef = useRef(null);

  useEffect(() => {
    setForm(card ? { ...EMPTY, ...card } : EMPTY);
    setTimeout(() => firstRef.current?.focus(), 60);
  }, [card]);

  const handleKey = (e) => { if (e.key === 'Escape') onClose(); };
  const handleChange = (e) => setForm(prev => ({ ...prev, [e.target.name]: e.target.value }));
  const handleSubmit = (e) => { e.preventDefault(); if (!form.company_name.trim()) return; onSave(form); };

  return (
    <div className="modal-overlay" onMouseDown={onClose} onKeyDown={handleKey}>
      <div className="modal" onMouseDown={e => e.stopPropagation()}>
        <h2 className="modal-title">{mode === 'create' ? 'Neue Karte erstellen' : 'Karte bearbeiten'}</h2>
        <form onSubmit={handleSubmit}>
          <div className="form-group"><label htmlFor="company_name">Firmenname *</label><input id="company_name" ref={firstRef} name="company_name" value={form.company_name} onChange={handleChange} placeholder="Muster GmbH" required /></div>
          <div className="form-group"><label htmlFor="website">Webseite</label><input id="website" name="website" value={form.website} onChange={handleChange} placeholder="www.muster.de" /></div>
          <div className="form-group"><label htmlFor="email">E-Mail-Adresse</label><input id="email" name="email" value={form.email} onChange={handleChange} placeholder="info@muster.de" type="email" /></div>
          <div className="form-group"><label htmlFor="phone">Telefonnummer</label><input id="phone" name="phone" value={form.phone} onChange={handleChange} placeholder="+49 30 12345678" /></div>
          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>Abbrechen</button>
            <button type="submit" className="btn btn-primary">{mode === 'create' ? 'Erstellen' : 'Speichern'}</button>
          </div>
        </form>
      </div>
    </div>
  );
}
EOF

# ── frontend/src/components/FileUpload.js ────────────────────────────────────
cat > "$APP/frontend/src/components/FileUpload.js" << 'EOF'
import React, { useState, useRef } from 'react';
import axios from 'axios';

export default function FileUpload({ onImportDone, onError }) {
  const [uploading, setUploading] = useState(false);
  const [statusMsg, setStatusMsg] = useState('');
  const inputRef = useRef(null);

  const handleFileChange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const ext = file.name.split('.').pop().toLowerCase();
    if (!['pdf', 'xlsx', 'xls', 'csv'].includes(ext)) { onError('Nur PDF, Excel (.xlsx/.xls) oder CSV-Dateien sind erlaubt'); return; }
    setUploading(true);
    setStatusMsg(`„${file.name}" wird verarbeitet…`);
    const formData = new FormData();
    formData.append('file', file);
    try {
      const { data } = await axios.post('/api/upload', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
      setStatusMsg(`${data.inserted} neu, ${data.skipped} übersprungen`);
      onImportDone(data);
    } catch (err) {
      setStatusMsg('Fehler beim Import');
      onError(err.response?.data?.error || 'Fehler beim Import');
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  };

  return (
    <div className="upload-area">
      <label className={`upload-label${uploading ? ' loading' : ''}`}>
        {uploading ? '⏳ Verarbeite…' : '⬆ Datei importieren'}
        <input ref={inputRef} className="upload-input" type="file" accept=".pdf,.xlsx,.xls,.csv" onChange={handleFileChange} disabled={uploading} />
      </label>
      {statusMsg && <span className="upload-status">{statusMsg}</span>}
    </div>
  );
}
EOF

# ── frontend/src/components/Toast.js ─────────────────────────────────────────
cat > "$APP/frontend/src/components/Toast.js" << 'EOF'
import React from 'react';
export default function Toast({ message, type = 'success' }) {
  return <div className={`toast ${type}`}>{message}</div>;
}
EOF

# ── Docker installieren & App starten ─────────────────────────────────────────
echo "==> Docker installieren..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  echo "    Docker bereits vorhanden."
fi

echo "==> Container bauen und starten (dauert 2-5 Minuten)..."
cd "$APP"
docker compose up -d --build

echo ""
echo "✓ Fertig! App läuft auf: http://159.195.34.237:44215"
