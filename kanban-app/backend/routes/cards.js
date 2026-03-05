const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../database');

const router = express.Router();

// GET all cards grouped by column
router.get('/', (req, res) => {
  try {
    const db = getDb();
    const cards = db
      .prepare(`SELECT * FROM cards ORDER BY column_id, position ASC, company_name COLLATE NOCASE ASC`)
      .all();

    const columns = {
      leads: [],
      'angebot-versendet': [],
      nachfassen: [],
    };

    for (const card of cards) {
      if (columns[card.column_id] !== undefined) {
        columns[card.column_id].push(card);
      }
    }

    res.json(columns);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST create a single card
router.post('/', (req, res) => {
  try {
    const db = getDb();
    const { company_name, website = '', email = '', phone = '', column_id = 'leads' } = req.body;

    if (!company_name || !company_name.trim()) {
      return res.status(400).json({ error: 'company_name is required' });
    }

    const maxPos = db
      .prepare(`SELECT COALESCE(MAX(position), -1) as max_pos FROM cards WHERE column_id = ?`)
      .get(column_id);

    const card = {
      id: uuidv4(),
      company_name: company_name.trim(),
      website: website.trim(),
      email: email.trim().toLowerCase(),
      phone: phone.trim(),
      column_id,
      position: maxPos.max_pos + 1,
    };

    db.prepare(
      `INSERT INTO cards (id, company_name, website, email, phone, column_id, position)
       VALUES (@id, @company_name, @website, @email, @phone, @column_id, @position)`
    ).run(card);

    res.status(201).json(card);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT update a card
router.put('/:id', (req, res) => {
  try {
    const db = getDb();
    const { id } = req.params;
    const { company_name, website, email, phone } = req.body;

    const existing = db.prepare(`SELECT * FROM cards WHERE id = ?`).get(id);
    if (!existing) return res.status(404).json({ error: 'Card not found' });

    const updated = {
      id,
      company_name: (company_name ?? existing.company_name).trim(),
      website: (website ?? existing.website).trim(),
      email: (email ?? existing.email).trim().toLowerCase(),
      phone: (phone ?? existing.phone).trim(),
    };

    db.prepare(
      `UPDATE cards SET company_name = @company_name, website = @website,
       email = @email, phone = @phone, updated_at = datetime('now')
       WHERE id = @id`
    ).run(updated);

    res.json({ ...existing, ...updated });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE a card
router.delete('/:id', (req, res) => {
  try {
    const db = getDb();
    const result = db.prepare(`DELETE FROM cards WHERE id = ?`).run(req.params.id);
    if (result.changes === 0) return res.status(404).json({ error: 'Card not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH reorder / move cards (drag-and-drop)
router.patch('/reorder', (req, res) => {
  try {
    const db = getDb();
    // columns: { [columnId]: [{ id, position }] }
    const { columns } = req.body;

    const updateStmt = db.prepare(
      `UPDATE cards SET column_id = @column_id, position = @position, updated_at = datetime('now') WHERE id = @id`
    );

    const applyAll = db.transaction(() => {
      for (const [column_id, cards] of Object.entries(columns)) {
        cards.forEach((card, index) => {
          updateStmt.run({ id: card.id, column_id, position: index });
        });
      }
    });

    applyAll();
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
