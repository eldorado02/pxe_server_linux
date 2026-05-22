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
# ──────────────────────────────────────────────────────────
LIVE_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's|/dev/||;s|[0-9]*$||' || true)
DISKS=$(lsblk -dno NAME,TYPE,RM \
    | awk '$2=="disk" && $3=="0" && $1!~/^loop|^ram|^sr/' \
    | grep -v "^${LIVE_DEV}" \
    | awk '{print $1}' || true)

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté."
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
    LOGFILE="$RAPPORT_LOCAL/nwipe_${DISK}_${DATE_NOW}.log"
    echo ""
    echo ">>> Lancement de nwipe (DoD 5220.22-M — 7 passes) sur $DISK_PATH ..."

    if nwipe \
        --autonuke \
        --method=dod522022m \
        --verify=last \
        --logfile="$LOGFILE" \
        "$DISK_PATH"; then
        echo ">>> OK : $DISK_PATH effacé avec succès."
    else
        echo ">>> ERREUR : L'effacement de $DISK_PATH a échoué !"
        WIPE_ERRORS=$((WIPE_ERRORS + 1))
    fi
done

echo "----------------------------------------------------------"
if [ "$WIPE_ERRORS" -gt 0 ]; then
    echo "ATTENTION : $WIPE_ERRORS disque(s) en erreur."
fi

# ──────────────────────────────────────────────────────────
# 5. Génération du rapport PDF depuis les logfiles
# ──────────────────────────────────────────────────────────
echo "Génération du rapport PDF..."
PDF_FILE="$RAPPORT_LOCAL/rapport_${HOSTNAME_ID}.pdf"

# Concaténer tous les logs en un seul texte
ALL_LOGS=""
for LOGFILE in "$RAPPORT_LOCAL"/*.log; do
    [ -f "$LOGFILE" ] && ALL_LOGS="${ALL_LOGS}\n$(cat "$LOGFILE")"
done

# Générer le PDF avec python3 + reportlab
python3 - << PYEOF
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Preformatted
from reportlab.lib.units import cm

pdf_path = "$PDF_FILE"
mac = "$MAC_ADDR"
date = "$DATE_NOW"
errors = $WIPE_ERRORS
rapport_dir = "$RAPPORT_LOCAL"

doc = SimpleDocTemplate(pdf_path, pagesize=A4,
    rightMargin=2*cm, leftMargin=2*cm,
    topMargin=2*cm, bottomMargin=2*cm)

styles = getSampleStyleSheet()
story = []

# Titre
story.append(Paragraph("CERTIFICAT D'EFFACEMENT SECURISE", styles['Title']))
story.append(Spacer(1, 0.5*cm))
story.append(Paragraph(f"Machine : {mac}", styles['Heading2']))
story.append(Paragraph(f"Date    : {date}", styles['Heading2']))
story.append(Paragraph(f"Methode : DoD 5220.22-M (7 passes)", styles['Heading2']))
status = "SUCCES" if errors == 0 else f"ECHEC ({errors} disque(s) en erreur)"
story.append(Paragraph(f"Statut  : {status}", styles['Heading2']))
story.append(Spacer(1, 0.5*cm))

# Contenu des logs
for logfile in sorted(os.listdir(rapport_dir)):
    if logfile.endswith('.log'):
        story.append(Paragraph(f"--- {logfile} ---", styles['Heading3']))
        with open(os.path.join(rapport_dir, logfile), 'r', errors='replace') as f:
            content = f.read()
        story.append(Preformatted(content, styles['Code']))
        story.append(Spacer(1, 0.3*cm))

doc.build(story)
print(f"PDF généré : {pdf_path}")
PYEOF

# ──────────────────────────────────────────────────────────
# 6. Configuration SSH pour l'envoi
# ──────────────────────────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keyscan -T 10 -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null || {
    echo "AVERTISSEMENT : ssh-keyscan a échoué."
    echo "StrictHostKeyChecking no" >> ~/.ssh/config
}

# ──────────────────────────────────────────────────────────
# 7. Transfert des rapports vers le serveur
# ──────────────────────────────────────────────────────────
echo "Transfert vers $SERVER_IP:/opt/pxe-wipe/rapports/ ..."

if scp \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    -r "$RAPPORT_LOCAL" \
    root@"$SERVER_IP":/opt/pxe-wipe/rapports/; then
    echo "Transfert réussi."
else
    echo "AVERTISSEMENT : Échec du transfert SSH."
    echo "Rapports conservés dans : $RAPPORT_LOCAL"
    ls -lh "$RAPPORT_LOCAL" 2>/dev/null || true
fi

# ──────────────────────────────────────────────────────────
# 8. Extinction sécurisée
# ──────────────────────────────────────────────────────────
echo "----------------------------------------------------------"
echo "Machine sécurisée. Extinction dans 10 secondes..."
sleep 10
sync
poweroff -f