#!/bin/bash
# =============================================================================
# run.sh — Lance le serveur PXE avec persistance des rapports
# =============================================================================
set -euo pipefail

IMAGE="pxe_server"
CONTAINER="pxe"
RAPPORTS_DIR="$HOME/rapports_wipe"

# Créer le dossier de rapports sur l'hôte
mkdir -p "$RAPPORTS_DIR"

# Charger les modules NFS sur l'hôte si pas déjà chargés
echo "=== Chargement des modules NFS ==="
sudo modprobe nfsd  || true
sudo modprobe nfs   || true

# Supprimer l'ancien conteneur si existant
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "=== Suppression de l'ancien conteneur ==="
    docker rm -f "$CONTAINER"
fi

echo "=== Lancement du serveur PXE ==="
docker run -d \
    --privileged \
    --network host \
    --name "$CONTAINER" \
    -v "$RAPPORTS_DIR":/opt/pxe-wipe/rapports \
    "$IMAGE"

echo "=== Serveur PXE démarré ! ==="
echo "Rapports sauvegardés dans : $RAPPORTS_DIR"
echo ""
echo "Commandes utiles :"
echo "  Voir les logs      : docker logs -f $CONTAINER"
echo "  Entrer dedans      : docker exec -it $CONTAINER bash"
echo "  Voir les rapports  : ls $RAPPORTS_DIR"
echo "  Arrêter            : docker stop $CONTAINER"