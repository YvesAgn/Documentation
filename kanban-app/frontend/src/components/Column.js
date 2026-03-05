import React from 'react';
import { Droppable } from '@hello-pangea/dnd';
import Card from './Card';

export default function Column({ column, cards, onAdd, onEdit, onDelete }) {
  return (
    <div
      className="column"
      style={{ background: column.color, borderTop: `4px solid ${column.accent}` }}
    >
      <div className="column-header">
        <span className="column-title" style={{ color: column.accent }}>
          {column.label}
        </span>
        <span className="column-count">{cards.length}</span>
        <button className="add-btn" onClick={onAdd} title="Karte hinzufügen">
          +
        </button>
      </div>

      <Droppable droppableId={column.id}>
        {(provided, snapshot) => (
          <div
            className={`column-body${snapshot.isDraggingOver ? ' is-dragging-over' : ''}`}
            ref={provided.innerRef}
            {...provided.droppableProps}
          >
            {cards.length === 0 && (
              <p className="column-empty">Keine Karten</p>
            )}
            {cards.map((card, index) => (
              <Card
                key={card.id}
                card={card}
                index={index}
                accent={column.accent}
                onEdit={() => onEdit(card)}
                onDelete={() => onDelete(card)}
              />
            ))}
            {provided.placeholder}
          </div>
        )}
      </Droppable>
    </div>
  );
}
