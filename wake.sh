#!/bin/bash
# =============================================================================
# wake.sh — Réveille un ou plusieurs PC via Wake-on-LAN (magic packet UDP)
# Aucun sudo requis — fonctionne sur Linux, macOS, Windows Git Bash
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# Liste des PC à réveiller : FORMAT → "NOM  MAC_ADDRESS"
# Remplacez ces exemples par vos vraies adresses MAC
# (trouvable dans le BIOS ou sur un sticker sous le PC)
# ─────────────────────────────────────────────────────────────────────────────
MACHINES=(
    "PC-Atelier-01  AA:BB:CC:DD:EE:01"
    "PC-Atelier-02  AA:BB:CC:DD:EE:02"
    "PC-Atelier-03  AA:BB:CC:DD:EE:03"
)

# Adresse broadcast (255.255.255.255 fonctionne sur la plupart des réseaux)
BROADCAST="255.255.255.255"
PORT=9

# ─────────────────────────────────────────────────────────────────────────────
# Fonction : envoie un magic packet pour une adresse MAC
# Le magic packet = 6x 0xFF suivi de 16x l'adresse MAC (102 octets)
# Envoyé en UDP broadcast sur le port 9
# ─────────────────────────────────────────────────────────────────────────────
send_wol() {
    local NAME="$1"
    local MAC="$2"

    # Normaliser la MAC : accepte AA:BB:CC:DD:EE:FF ou AA-BB-CC-DD-EE-FF
    MAC=$(echo "$MAC" | tr '[:lower:]' '[:upper:]' | tr '-' ':')

    # Validation format MAC
    if ! echo "$MAC" | grep -qE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'; then
        echo "  [ERREUR] MAC invalide pour $NAME : $MAC"
        return 1
    fi

    # Construire le magic packet en Python (disponible partout)
    python3 - "$MAC" "$BROADCAST" "$PORT" << 'PYEOF'
import sys, socket, struct

mac    = sys.argv[1]
bcast  = sys.argv[2]
port   = int(sys.argv[3])

# Convertir MAC en bytes
mac_bytes = bytes(int(x, 16) for x in mac.split(':'))

# Magic packet : FF FF FF FF FF FF + MAC × 16
packet = b'\xff' * 6 + mac_bytes * 16

# Envoi UDP broadcast
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.sendto(packet, (bcast, port))
sock.close()
print("OK")
PYEOF

    local STATUS=$?
    if [ $STATUS -eq 0 ]; then
        echo "  [✓] Magic packet envoyé → $NAME ($MAC)"
    else
        echo "  [✗] Échec pour $NAME ($MAC)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

# Vérification Python3 disponible
if ! command -v python3 &>/dev/null; then
    echo "ERREUR : python3 requis (inclus dans Docker, ou installez Python sur votre PC)"
    exit 1
fi

echo "=========================================="
echo "  WAKE-ON-LAN — Réveil des machines"
echo "=========================================="

# Si un argument est passé → réveiller seulement cette MAC
# Exemple : bash wake.sh AA:BB:CC:DD:EE:FF
if [ $# -eq 1 ]; then
    echo "Mode manuel — MAC : $1"
    send_wol "Manuel" "$1"
    exit 0
fi

# Sinon → réveiller toutes les machines de la liste
if [ ${#MACHINES[@]} -eq 0 ]; then
    echo "ERREUR : Aucune machine configurée dans le script."
    echo "Éditez la section MACHINES en haut du fichier wake.sh"
    exit 1
fi

echo "Envoi des magic packets..."
echo "------------------------------------------"

for ENTRY in "${MACHINES[@]}"; do
    NAME=$(echo "$ENTRY" | awk '{print $1}')
    MAC=$(echo "$ENTRY"  | awk '{print $2}')
    send_wol "$NAME" "$MAC"
done

echo "------------------------------------------"
echo "Terminé. Les PCs devraient démarrer dans"
echo "quelques secondes (selon leur BIOS)."
echo ""
echo "Usage manuel : bash wake.sh AA:BB:CC:DD:EE:FF"