#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  Kanban App – Server Setup & Update (Docker Compose)
#
#  Erstinstallation:  bash deploy.sh install
#  Nach git pull:     bash deploy.sh update
# ─────────────────────────────────────────────────────────────────────────────
set -e

APP_DIR="/var/www/kanban"
REPO="https://github.com/YvesAgn/kanban-app.git"
BRANCH="main"

# ── Helpers ───────────────────────────────────────────────────────────────────
install_docker() {
  if command -v docker &>/dev/null; then
    echo "    Docker $(docker --version) bereits vorhanden."
    return
  fi
  echo "==> Docker installieren..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
}

compose_up() {
  docker compose up -d --build
}

# ── Commands ──────────────────────────────────────────────────────────────────
case "${1:-update}" in

  # ── Erstinstallation ───────────────────────────────────────────────────────
  install)
    install_docker

    echo "==> Repository klonen..."
    mkdir -p "$(dirname "$APP_DIR")"

    if [ -d "$APP_DIR/.git" ]; then
      echo "    Repo existiert bereits – führe Update durch."
      bash "$0" update
      exit 0
    fi

    git clone -b "$BRANCH" "$REPO" "$APP_DIR"
    cd "$APP_DIR"

    echo "==> Container bauen und starten..."
    compose_up

    echo ""
    echo "✓ Installation abgeschlossen."
    echo "  App:  http://159.195.34.237:44215"
    echo "  API:  http://159.195.34.237:44174/api/health"
    ;;

  # ── Update (nach git pull) ─────────────────────────────────────────────────
  update)
    echo "==> Code aktualisieren..."
    cd "$APP_DIR"
    git pull origin "$BRANCH"

    echo "==> Container neu bauen und starten..."
    compose_up

    echo ""
    echo "✓ Update abgeschlossen."
    echo "  App:  http://159.195.34.237:44215"
    ;;

  *)
    echo "Verwendung: bash deploy.sh [install|update]"
    exit 1
    ;;
esac
