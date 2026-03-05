import React from 'react';
import Column from './Column';

export default function Board({ columns, cards, onAddCard, onEditCard, onDeleteCard }) {
  return (
    <div className="board">
      {columns.map((col) => (
        <Column
          key={col.id}
          column={col}
          cards={cards[col.id] || []}
          onAdd={() => onAddCard(col.id)}
          onEdit={onEditCard}
          onDelete={onDeleteCard}
        />
      ))}
    </div>
  );
}
