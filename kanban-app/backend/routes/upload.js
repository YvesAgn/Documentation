const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const { getDb } = require('../database');

const router = express.Router();

// ── Multer storage ────────────────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: path.join(__dirname, '../uploads'),
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});

const upload = multer({
  storage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB
  fileFilter: (req, file, cb) => {
    const allowed = [
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-excel',
      'text/csv',
    ];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(file.mimetype) || ['.pdf', '.xlsx', '.xls', '.csv'].includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Excel (.xlsx/.xls) and CSV files are allowed'));
    }
  },
});

// ── Helpers ───────────────────────────────────────────────────────────────────

const EMAIL_RE = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;
const PHONE_RE =
  /(?:\+?\d{1,3}[\s\-.]?)?\(?\d{2,4}\)?[\s\-.]?\d{3,4}[\s\-.]?\d{3,6}(?:[\s\-.]?\d{1,4})?/g;
const URL_RE =
  /(?:https?:\/\/)?(?:www\.)?[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}(?:\/[^\s,;)]*)?/g;

function extractFromText(text) {
  const emails = (text.match(EMAIL_RE) || []).map((e) => e.toLowerCase());
  const phones = (text.match(PHONE_RE) || []).filter((p) => p.replace(/\D/g, '').length >= 7);
  const urls = (text.match(URL_RE) || []).filter(
    (u) => !EMAIL_RE.test(u) && !u.match(/^\d/)
  );

  return { emails, phones, urls };
}

/**
 * Attempt to parse blocks of text into lead records.
 * Strategy: split on double-newlines and treat each block as a potential card.
 */
function blocksToLeads(text) {
  const blocks = text.split(/\n{2,}/).map((b) => b.trim()).filter(Boolean);
  const leads = [];

  for (const block of blocks) {
    const lines = block.split('\n').map((l) => l.trim()).filter(Boolean);
    if (lines.length === 0) continue;

    const { emails, phones, urls } = extractFromText(block);

    // First non-email, non-url, non-phone line is treated as the company name
    const company_name = lines.find(
      (l) =>
        !EMAIL_RE.test(l) &&
        !PHONE_RE.test(l) &&
        !URL_RE.test(l) &&
        l.length > 1
    ) || lines[0];

    if (!company_name) continue;

    leads.push({
      company_name: company_name.replace(/[*_#]+/g, '').trim(),
      website: urls[0] || '',
      email: emails[0] || '',
      phone: phones[0] || '',
    });
  }

  return leads;
}

async function parsePdf(filePath) {
  // Lazy-require so the module is only loaded when needed
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

  if (ext === '.csv') {
    await workbook.csv.readFile(filePath);
  } else {
    await workbook.xlsx.readFile(filePath);
  }

  workbook.eachSheet((sheet) => {
    const headers = [];
    sheet.eachRow((row, rowNum) => {
      if (rowNum === 1) {
        // Collect headers from first row
        row.eachCell((cell, colNum) => {
          headers[colNum] = String(cell.value || '').toLowerCase().replace(/[\s_\-]+/g, '');
        });
        return;
      }

      const norm = {};
      row.eachCell((cell, colNum) => {
        if (headers[colNum]) {
          norm[headers[colNum]] = String(cell.value ?? '').trim();
        }
      });

      const company_name =
        norm['firmenname'] ||
        norm['company'] ||
        norm['companyname'] ||
        norm['unternehmen'] ||
        norm['name'] ||
        '';

      if (!company_name) return;

      leads.push({
        company_name,
        website: norm['webseite'] || norm['website'] || norm['url'] || norm['homepage'] || '',
        email: (norm['email'] || norm['mail'] || norm['emailadresse'] || norm['email'] || '').toLowerCase(),
        phone:
          norm['telefon'] ||
          norm['phone'] ||
          norm['telefonnummer'] ||
          norm['tel'] ||
          norm['mobile'] ||
          norm['mobil'] ||
          '',
      });
    });
  });

  return leads;
}

// ── Route ─────────────────────────────────────────────────────────────────────

router.post('/', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  const filePath = req.file.path;
  const ext = path.extname(req.file.originalname).toLowerCase();

  try {
    let rawLeads = [];

    if (ext === '.pdf') {
      rawLeads = await parsePdf(filePath);
    } else if (['.xlsx', '.xls', '.csv'].includes(ext)) {
      rawLeads = await parseExcel(filePath);
    } else {
      return res.status(400).json({ error: 'Unsupported file type' });
    }

    const db = getDb();

    // Build a set of existing fingerprints for duplicate detection
    const existing = db.prepare(`SELECT company_name, email FROM cards`).all();
    const existingEmails = new Set(existing.map((c) => c.email.toLowerCase()).filter(Boolean));
    const existingNames = new Set(
      existing.map((c) => c.company_name.toLowerCase().trim())
    );

    const maxPos = db
      .prepare(`SELECT COALESCE(MAX(position), -1) as max_pos FROM cards WHERE column_id = 'leads'`)
      .get();
    let nextPos = maxPos.max_pos + 1;

    const insertStmt = db.prepare(
      `INSERT INTO cards (id, company_name, website, email, phone, column_id, position)
       VALUES (@id, @company_name, @website, @email, @phone, @column_id, @position)`
    );

    const inserted = [];
    const skipped = [];

    // Sort leads alphabetically before inserting
    rawLeads.sort((a, b) =>
      a.company_name.localeCompare(b.company_name, 'de', { sensitivity: 'base' })
    );

    const insertAll = db.transaction(() => {
      for (const lead of rawLeads) {
        const nameLower = lead.company_name.toLowerCase().trim();
        const emailLower = lead.email.toLowerCase().trim();

        // Duplicate check: same email (non-empty) OR same company name
        if ((emailLower && existingEmails.has(emailLower)) || existingNames.has(nameLower)) {
          skipped.push(lead.company_name);
          continue;
        }

        const card = {
          id: uuidv4(),
          company_name: lead.company_name,
          website: lead.website,
          email: emailLower,
          phone: lead.phone,
          column_id: 'leads',
          position: nextPos++,
        };

        insertStmt.run(card);
        inserted.push(card);

        // Update in-memory sets to avoid intra-file duplicates
        existingNames.add(nameLower);
        if (emailLower) existingEmails.add(emailLower);
      }
    });

    insertAll();

    // Clean up temp file
    fs.unlink(filePath, () => {});

    res.json({
      inserted: inserted.length,
      skipped: skipped.length,
      skipped_names: skipped,
      cards: inserted,
    });
  } catch (err) {
    fs.unlink(filePath, () => {});
    console.error('Upload error:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
