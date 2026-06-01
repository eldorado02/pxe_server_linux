#!/bin/bash
# =============================================================
# run.sh — Lance le serveur PXE ShredOS
# Usage : ./run.sh [start|stop|logs|rapports|health]
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
    echo "Logs PXE : docker compose logs -f pxev2"
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

  health)
    echo "=== Santé des services ==="
    docker compose ps
    echo ""
    echo "=== Lease DHCP partagée ==="
    if [ -f ./rapports/dnsmasq.leases ]; then
      tail -n 5 ./rapports/dnsmasq.leases
    else
      echo "Aucun lease file pour le moment (normal sans client PXE)."
    fi
    echo ""
    echo "=== Derniers rapports ==="
    find ./rapports -maxdepth 1 -type f \( -name "*.pdf" -o -name "*.log" -o -name "*.txt" \) \
      | sort | tail -n 10
    ;;

  *)
    echo "Usage : $0 [start|stop|logs|rapports|health]"
    exit 1
    ;;

esac
