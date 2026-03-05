#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Kanban App – Server Setup & Update Script
#  Aufruf (1. Mal):  bash deploy.sh install
#  Aufruf (Update):  bash deploy.sh update
# ─────────────────────────────────────────────────────────────
set -e

APP_DIR="/var/www/kanban"
REPO="https://github.com/YvesAgn/kanban-app.git"
BRANCH="main"
SERVICE="kanban"
PORT=3001

case "${1:-update}" in

  # ── Erstinstallation ─────────────────────────────────────
  install)
    echo "==> Node.js installieren..."
    if ! command -v node &>/dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
      apt install -y nodejs
    else
      echo "    Node $(node -v) bereits vorhanden."
    fi

    echo "==> PM2 installieren..."
    npm install -g pm2 2>/dev/null || true

    echo "==> Repository klonen..."
    mkdir -p "$(dirname "$APP_DIR")"
    if [ -d "$APP_DIR/.git" ]; then
      echo "    Repo existiert bereits – führe update durch."
      bash "$0" update
      exit 0
    fi
    git clone "$REPO" "$APP_DIR"
    cd "$APP_DIR"

    echo "==> Abhängigkeiten installieren..."
    npm install --prefix backend
    npm install --prefix frontend

    echo "==> Frontend bauen..."
    npm run build --prefix frontend

    echo "==> PM2-Dienst starten..."
    cd "$APP_DIR/backend"
    PORT=$PORT pm2 start server.js --name "$SERVICE"
    pm2 save

    echo "==> PM2 Autostart einrichten..."
    pm2 startup | tail -1 | bash || true

    echo ""
    echo "✓ Installation abgeschlossen."
    echo "  App läuft auf http://$(hostname -I | awk '{print $1}'):$PORT"
    ;;

  # ── Update ───────────────────────────────────────────────
  update)
    echo "==> Code aktualisieren..."
    cd "$APP_DIR"
    git pull origin "$BRANCH"

    echo "==> Abhängigkeiten aktualisieren..."
    npm install --prefix backend
    npm install --prefix frontend

    echo "==> Frontend neu bauen..."
    npm run build --prefix frontend

    echo "==> App neu starten..."
    pm2 restart "$SERVICE"

    echo ""
    echo "✓ Update abgeschlossen."
    ;;

  *)
    echo "Verwendung: bash deploy.sh [install|update]"
    exit 1
    ;;
esac
