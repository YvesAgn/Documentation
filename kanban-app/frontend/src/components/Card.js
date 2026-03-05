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
        <div
          className={`card${snapshot.isDragging ? ' is-dragging' : ''}`}
          style={{ borderLeftColor: accent, ...provided.draggableProps.style }}
          ref={provided.innerRef}
          {...provided.draggableProps}
          {...provided.dragHandleProps}
        >
          <p className="card-company">{card.company_name}</p>

          <div className="card-fields">
            {card.website && (
              <span className="card-field">
                <span className="field-icon">🌐</span>
                <a
                  href={normalizeUrl(card.website)}
                  target="_blank"
                  rel="noreferrer"
                  onClick={(e) => e.stopPropagation()}
                >
                  {card.website}
                </a>
              </span>
            )}
            {card.email && (
              <span className="card-field">
                <span className="field-icon">✉️</span>
                <a
                  href={`mailto:${card.email}`}
                  onClick={(e) => e.stopPropagation()}
                >
                  {card.email}
                </a>
              </span>
            )}
            {card.phone && (
              <span className="card-field">
                <span className="field-icon">📞</span>
                <a
                  href={`tel:${card.phone}`}
                  onClick={(e) => e.stopPropagation()}
                >
                  {card.phone}
                </a>
              </span>
            )}
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
