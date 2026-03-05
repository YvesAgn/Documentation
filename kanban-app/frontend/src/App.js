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
  const [modal, setModal] = useState(null); // { mode: 'create'|'edit', card?, columnId? }
  const [toast, setToast] = useState(null);

  const showToast = useCallback((message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3500);
  }, []);

  const fetchCards = useCallback(async () => {
    try {
      const { data } = await axios.get('/api/cards');
      setColumns(data);
    } catch {
      showToast('Fehler beim Laden der Karten', 'error');
    } finally {
      setLoading(false);
    }
  }, [showToast]);

  useEffect(() => { fetchCards(); }, [fetchCards]);

  // ── Drag & Drop ─────────────────────────────────────────────────────────────
  const onDragEnd = useCallback(async (result) => {
    const { source, destination, draggableId } = result;
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

    // Persist reorder
    try {
      // Build updated state after drag (reading from setState is async, so we recompute)
      setColumns((current) => {
        axios.patch('/api/cards/reorder', {
          columns: Object.fromEntries(
            Object.entries(current).map(([colId, cards]) => [
              colId,
              cards.map((c, i) => ({ id: c.id, position: i })),
            ])
          ),
        }).catch(() => showToast('Reihenfolge konnte nicht gespeichert werden', 'error'));
        return current;
      });
    } catch {
      // silent
    }
  }, [showToast]);

  // ── Card CRUD ───────────────────────────────────────────────────────────────
  const handleSaveCard = async (data) => {
    try {
      if (modal.mode === 'create') {
        const { data: created } = await axios.post('/api/cards', {
          ...data,
          column_id: modal.columnId,
        });
        setColumns((prev) => ({
          ...prev,
          [modal.columnId]: [...prev[modal.columnId], created],
        }));
        showToast('Karte erstellt');
      } else {
        const { data: updated } = await axios.put(`/api/cards/${modal.card.id}`, data);
        setColumns((prev) => {
          const colId = modal.card.column_id;
          return {
            ...prev,
            [colId]: prev[colId].map((c) => (c.id === updated.id ? updated : c)),
          };
        });
        showToast('Karte aktualisiert');
      }
      setModal(null);
    } catch (err) {
      showToast(err.response?.data?.error || 'Fehler beim Speichern', 'error');
    }
  };

  const handleDeleteCard = async (card) => {
    if (!window.confirm(`„${card.company_name}" wirklich löschen?`)) return;
    try {
      await axios.delete(`/api/cards/${card.id}`);
      setColumns((prev) => ({
        ...prev,
        [card.column_id]: prev[card.column_id].filter((c) => c.id !== card.id),
      }));
      showToast('Karte gelöscht');
    } catch {
      showToast('Fehler beim Löschen', 'error');
    }
  };

  const handleImportDone = ({ inserted, skipped, cards: newCards }) => {
    if (newCards?.length) {
      setColumns((prev) => ({
        ...prev,
        leads: [...prev.leads, ...newCards].sort((a, b) =>
          a.company_name.localeCompare(b.company_name, 'de', { sensitivity: 'base' })
        ),
      }));
    }
    showToast(
      `Import abgeschlossen: ${inserted} neu hinzugefügt, ${skipped} übersprungen`,
      inserted > 0 ? 'success' : 'info'
    );
  };

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-inner">
          <h1 className="app-title">
            <span className="title-icon">📋</span> Lead-Kanban
          </h1>
          <FileUpload onImportDone={handleImportDone} onError={(msg) => showToast(msg, 'error')} />
        </div>
      </header>

      <main className="board-wrapper">
        {loading ? (
          <div className="loading">Lädt…</div>
        ) : (
          <DragDropContext onDragEnd={onDragEnd}>
            <Board
              columns={COLUMNS}
              cards={columns}
              onAddCard={(columnId) => setModal({ mode: 'create', columnId })}
              onEditCard={(card) => setModal({ mode: 'edit', card })}
              onDeleteCard={handleDeleteCard}
            />
          </DragDropContext>
        )}
      </main>

      {modal && (
        <CardModal
          mode={modal.mode}
          card={modal.card}
          onSave={handleSaveCard}
          onClose={() => setModal(null)}
        />
      )}

      {toast && <Toast message={toast.message} type={toast.type} />}
    </div>
  );
}
