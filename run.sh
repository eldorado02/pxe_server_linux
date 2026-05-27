#!/bin/bash
# =============================================================
# run.sh — Lance le serveur PXE ShredOS
# Usage : ./run.sh [start|stop|logs|rapports]
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Créer le dossier rapports si absent
mkdir -p ./rapports

case "${1:-start}" in

  start)
    echo "=== Démarrage PXE ShredOS ==="
    docker compose up -d --build
    echo ""
    echo "=== Serveur démarré ==="
    echo "Logs PXE : docker compose logs -f pxe"
    echo "Logs FTP : docker compose logs -f ftp"
    echo "Rapports : ls ./rapports"
    ;;

  stop)
    echo "=== Arrêt ==="
    docker compose down
    ;;

  logs)
    docker compose logs -f
    ;;

  rapports)
    echo "=== Rapports reçus ==="
    find ./rapports -name "*.pdf" -o -name "*.log" 2>/dev/null \
      | sort \
      | while read -r f; do
          echo "  $(ls -lh "$f" | awk '{print $5, $9}')"
        done
    ;;

  *)
    echo "Usage : $0 [start|stop|logs|rapports]"
    exit 1
    ;;

esac
