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
    if (!['pdf', 'xlsx', 'xls', 'csv'].includes(ext)) {
      onError('Nur PDF, Excel (.xlsx/.xls) oder CSV-Dateien sind erlaubt');
      return;
    }

    setUploading(true);
    setStatusMsg(`„${file.name}" wird verarbeitet…`);

    const formData = new FormData();
    formData.append('file', file);

    try {
      const { data } = await axios.post('/api/upload', formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      setStatusMsg(`${data.inserted} neu, ${data.skipped} übersprungen`);
      onImportDone(data);
    } catch (err) {
      const msg = err.response?.data?.error || 'Fehler beim Import';
      setStatusMsg('Fehler beim Import');
      onError(msg);
    } finally {
      setUploading(false);
      // Reset so the same file can be re-uploaded if desired
      if (inputRef.current) inputRef.current.value = '';
    }
  };

  return (
    <div className="upload-area">
      <label className={`upload-label${uploading ? ' loading' : ''}`}>
        {uploading ? '⏳ Verarbeite…' : '⬆ Datei importieren'}
        <input
          ref={inputRef}
          className="upload-input"
          type="file"
          accept=".pdf,.xlsx,.xls,.csv"
          onChange={handleFileChange}
          disabled={uploading}
        />
      </label>
      {statusMsg && <span className="upload-status">{statusMsg}</span>}
    </div>
  );
}
