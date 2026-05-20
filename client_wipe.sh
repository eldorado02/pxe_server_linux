#!/bin/bash
# ==========================================================
#  CLIENT WIPE — Effacement sécurisé nwipe (DoD 5220.22-M)
#  Génère un rapport PDF et le transfère vers le serveur PXE
# ==========================================================
set -euo pipefail

clear
echo "=========================================================="
echo "    INITIALISATION DE L'EFFACEMENT MILITAIRE (NWIPE)      "
echo "=========================================================="

# ──────────────────────────────────────────────────────────
# 1. Détection de la passerelle (IP du serveur Docker parent)
# ──────────────────────────────────────────────────────────
IFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')

if [ -z "$SERVER_IP" ] || [ -z "$IFACE" ]; then
    echo "ERREUR FATALE : Impossible de détecter la passerelle réseau."
    echo "Vérifiez que le client a bien démarré via PXE avec une IP DHCP."
    sleep 30
    poweroff -f
fi

# ──────────────────────────────────────────────────────────
# 2. Identification unique de la machine
# ──────────────────────────────────────────────────────────
MAC_ADDR=$(cat /sys/class/net/"$IFACE"/address 2>/dev/null | tr -d ':' || echo "UNKNOWNMAC")
DATE_NOW=$(date +%Y%m%d_%H%M%S)
HOSTNAME_ID="${MAC_ADDR}_${DATE_NOW}"
RAPPORT_LOCAL="/root/rapports_effacement/$HOSTNAME_ID"
mkdir -p "$RAPPORT_LOCAL"

echo "Serveur Parent détecté : $SERVER_IP"
echo "Interface réseau       : $IFACE"
echo "Adresse MAC Machine    : $MAC_ADDR"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 3. Détection des disques physiques
#    Exclut: loopback, ram, sr (CDROM), et le disque live lui-même
# ──────────────────────────────────────────────────────────
LIVE_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's|/dev/||;s|[0-9]*$||' || true)
DISKS=$(lsblk -dno NAME,TYPE,RM \
    | awk '$2=="disk" && $3=="0" && $1!~/^loop|^ram|^sr/' \
    | grep -v "^${LIVE_DEV}" \
    | awk '{print $1}' || true)

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté pour l'effacement."
    echo "Disques présents :"
    lsblk -dno NAME,TYPE,SIZE,MODEL
    sleep 30
    poweroff -f
fi

echo "Disques à effacer :"
for D in $DISKS; do
    SIZE=$(lsblk -dno SIZE "/dev/$D" 2>/dev/null || echo "?")
    MODEL=$(lsblk -dno MODEL "/dev/$D" 2>/dev/null || echo "inconnu")
    echo "  /dev/$D — $SIZE — $MODEL"
done
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 4. Effacement de chaque disque
# ──────────────────────────────────────────────────────────
WIPE_ERRORS=0

for DISK in $DISKS; do
    DISK_PATH="/dev/$DISK"
    echo ""
    echo ">>> Lancement de nwipe (DoD 5220.22-M — 7 passes) sur $DISK_PATH ..."

    if nwipe \
        --nogui \
        --autonuke \
        --method=dod522022m \
        --verify=last \
        --logfile="$RAPPORT_LOCAL/nwipe_${DISK}_${DATE_NOW}.log" \
        --pdf="$RAPPORT_LOCAL" \
        "$DISK_PATH"; then
        echo ">>> OK : $DISK_PATH effacé avec succès."
    else
        echo ">>> ERREUR : L'effacement de $DISK_PATH a échoué ou est incomplet !"
        WIPE_ERRORS=$((WIPE_ERRORS + 1))
    fi
done

echo "----------------------------------------------------------"
if [ "$WIPE_ERRORS" -gt 0 ]; then
    echo "ATTENTION : $WIPE_ERRORS disque(s) en erreur — rapport envoyé quand même."
fi

# ──────────────────────────────────────────────────────────
# 5. Configuration SSH pour l'envoi
# ──────────────────────────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Scan de l'hôte avec timeout pour éviter un blocage
ssh-keyscan -T 10 -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null || {
    echo "AVERTISSEMENT : ssh-keyscan a échoué — tentative sans vérification d'hôte."
    echo "StrictHostKeyChecking no" >> ~/.ssh/config
}

# ──────────────────────────────────────────────────────────
# 6. Transfert des rapports PDF vers le serveur parent
# ──────────────────────────────────────────────────────────
echo "Transfert des certificats vers $SERVER_IP:/opt/pxe-wipe/rapports/ ..."

if scp \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    -r "$RAPPORT_LOCAL" \
    root@"$SERVER_IP":/opt/pxe-wipe/rapports/; then
    echo "Transfert réussi."
else
    echo "AVERTISSEMENT : Échec du transfert SSH."
    echo "Les rapports sont conservés localement dans : $RAPPORT_LOCAL"
    echo "Listage des fichiers générés :"
    ls -lh "$RAPPORT_LOCAL" 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────
# 7. Extinction sécurisée
# ──────────────────────────────────────────────────────────
echo "----------------------------------------------------------"
echo "Machine sécurisée. Extinction dans 10 secondes..."
sleep 10
sync
poweroff -f