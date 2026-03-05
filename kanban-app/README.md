# Lead-Kanban Board

Ein interaktives Kanban-Board für Lead-Management mit PDF/Excel-Import.

## Features

- **3 Spalten**: Leads · Angebot versendet · Nachfassen
- **Drag & Drop**: Karten innerhalb und zwischen Spalten verschieben
- **CRUD**: Karten manuell erstellen, bearbeiten und löschen
- **Datei-Import**: PDF und Excel/CSV hochladen → automatisch Kontakte extrahieren
- **Duplikat-Schutz**: Bereits vorhandene Leads werden beim Import übersprungen
- **Persistenz**: SQLite-Datenbank (kein separater Datenbankserver nötig)

## Technologie-Stack

| Schicht   | Technologie                          |
|-----------|--------------------------------------|
| Frontend  | React 18, @hello-pangea/dnd, Axios   |
| Backend   | Node.js, Express                     |
| Datenbank | SQLite (via better-sqlite3)          |
| PDF       | pdf-parse                            |
| Excel/CSV | xlsx                                 |
| Upload    | multer                               |

## Voraussetzungen

- Node.js ≥ 18
- npm ≥ 9

## Installation & Start

```bash
# 1. Abhängigkeiten installieren
npm run install:all

# 2. Backend starten (Port 3001)
npm run dev:backend

# 3. Frontend starten (in einem zweiten Terminal, Port 3000)
npm run dev:frontend
```

Die Anwendung ist dann unter **http://localhost:3000** erreichbar.

### Produktiv-Build

```bash
npm run build      # React-Build erzeugen
npm start          # Backend liefert auch das Frontend aus
```

## Excel-Spaltenbezeichnungen

Beim Excel-Import werden folgende Spaltenbezeichnungen (Groß-/Kleinschreibung egal) erkannt:

| Feld         | Erkannte Spaltenbezeichnungen                        |
|--------------|------------------------------------------------------|
| Firmenname   | Firmenname, Company, CompanyName, Unternehmen, Name  |
| Webseite     | Webseite, Website, URL, Homepage                     |
| E-Mail       | Email, Mail, E-Mail, Emailadresse                    |
| Telefon      | Telefon, Phone, Telefonnummer, Tel, Mobile, Mobil    |

## PDF-Import

Beim PDF-Import wird der gesamte Text extrahiert. Jeder durch Leerzeilen getrennte
Block wird als potenzieller Lead behandelt. Die erste Zeile ohne E-Mail/URL/Telefon
wird als Firmenname verwendet.

## API-Endpunkte

```
GET    /api/cards            – Alle Karten (nach Spalten gruppiert)
POST   /api/cards            – Neue Karte erstellen
PUT    /api/cards/:id        – Karte aktualisieren
DELETE /api/cards/:id        – Karte löschen
PATCH  /api/cards/reorder    – Reihenfolge/Spalte nach Drag & Drop speichern
POST   /api/upload           – PDF/Excel/CSV hochladen und importieren
```
