#!/bin/bash
# =============================================================================
# build.sh — Build de l'image Docker PXE
# =============================================================================
set -euo pipefail

IMAGE="pxe_server"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Build de l'image $IMAGE ==="
echo "Répertoire : $SCRIPT_DIR"

docker build \
    --no-cache \
    -t "$IMAGE" \
    "$SCRIPT_DIR"

docker system prune -f

echo ""
echo "=== Build terminé ! ==="
echo "Lancer le serveur : ./run.sh"