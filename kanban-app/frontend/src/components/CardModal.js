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

  const handleChange = (e) =>
    setForm((prev) => ({ ...prev, [e.target.name]: e.target.value }));

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!form.company_name.trim()) return;
    onSave(form);
  };

  return (
    <div className="modal-overlay" onMouseDown={onClose} onKeyDown={handleKey}>
      <div className="modal" onMouseDown={(e) => e.stopPropagation()}>
        <h2 className="modal-title">
          {mode === 'create' ? 'Neue Karte erstellen' : 'Karte bearbeiten'}
        </h2>

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="company_name">Firmenname *</label>
            <input
              id="company_name"
              ref={firstRef}
              name="company_name"
              value={form.company_name}
              onChange={handleChange}
              placeholder="Muster GmbH"
              required
            />
          </div>
          <div className="form-group">
            <label htmlFor="website">Webseite</label>
            <input
              id="website"
              name="website"
              value={form.website}
              onChange={handleChange}
              placeholder="www.muster.de"
              type="text"
            />
          </div>
          <div className="form-group">
            <label htmlFor="email">E-Mail-Adresse</label>
            <input
              id="email"
              name="email"
              value={form.email}
              onChange={handleChange}
              placeholder="info@muster.de"
              type="email"
            />
          </div>
          <div className="form-group">
            <label htmlFor="phone">Telefonnummer</label>
            <input
              id="phone"
              name="phone"
              value={form.phone}
              onChange={handleChange}
              placeholder="+49 30 12345678"
            />
          </div>

          <div className="modal-actions">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Abbrechen
            </button>
            <button type="submit" className="btn btn-primary">
              {mode === 'create' ? 'Erstellen' : 'Speichern'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
