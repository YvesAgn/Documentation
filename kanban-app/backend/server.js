const express = require('express');
const cors = require('cors');
const path = require('path');

const cardsRouter = require('./routes/cards');
const uploadRouter = require('./routes/upload');

const app = express();
const PORT = process.env.PORT || 3001;

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors({ origin: process.env.CLIENT_URL || 'http://localhost:3000' }));
app.use(express.json());

// ── Routes ────────────────────────────────────────────────────────────────────
app.use('/api/cards', cardsRouter);
app.use('/api/upload', uploadRouter);

// Health check
app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

// ── Static frontend (production) ──────────────────────────────────────────────
const frontendBuild = path.join(__dirname, '../frontend/build');
if (require('fs').existsSync(frontendBuild)) {
  app.use(express.static(frontendBuild));
  app.get('*', (req, res) =>
    res.sendFile(path.join(frontendBuild, 'index.html'))
  );
}

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`Kanban backend running on http://localhost:${PORT}`);
});
