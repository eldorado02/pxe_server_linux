#!/bin/bash
# ==========================================================
#  CLIENT WIPE — Effacement sécurisé nwipe (DoD 5220.22-M)
#  Génère un rapport PDF et le transfère vers le serveur PXE
# ==========================================================

# PAS de set -e ici — on gère les erreurs manuellement
# pour éviter que nwipe ou une commande secondaire tue le script
set -uo pipefail

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
# 3. Détection robuste du disque live (overlay → vrai device)
# ──────────────────────────────────────────────────────────
LIVE_DEV=""

RAW_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)

if echo "$RAW_SOURCE" | grep -qE '^(overlay|tmpfs|aufs|/dev/loop)'; then
    # Live-boot : / est sur overlay/loop → chercher le vrai disque USB/CD

    # Méthode 1 : device monté dans /run/live/medium
    LIVE_DEV=$(findmnt -n -o SOURCE /run/live/medium 2>/dev/null \
        | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||' || true)

    # Méthode 2 : premier disque amovible (RM=1) = clé USB live
    if [ -z "$LIVE_DEV" ]; then
        LIVE_DEV=$(lsblk -dno NAME,RM | awk '$2=="1" {print $1}' | head -1 || true)
    fi

    # Méthode 3 : device du loop0 (squashfs)
    if [ -z "$LIVE_DEV" ]; then
        LOOP_BACKING=$(losetup -n -O BACK-FILE /dev/loop0 2>/dev/null || true)
        if [ -n "$LOOP_BACKING" ]; then
            LIVE_DEV=$(findmnt -n -o SOURCE -T "$LOOP_BACKING" 2>/dev/null \
                | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||' || true)
        fi
    fi
else
    # Boot normal : extraire le nom du disque depuis le device
    LIVE_DEV=$(echo "$RAW_SOURCE" | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||')
fi

echo "Disque live détecté (protégé) : /dev/${LIVE_DEV:-aucun}"

# ──────────────────────────────────────────────────────────
# 4. Détection des disques physiques à effacer
# ──────────────────────────────────────────────────────────
DISKS=$(lsblk -dno NAME,TYPE,RM \
    | awk '$2=="disk" && $3=="0" && $1!~/^loop|^ram|^sr/' \
    | awk '{print $1}' \
    | grep -v "^${LIVE_DEV}$" || true)

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté."
    echo "Liste complète des devices :"
    lsblk -dno NAME,TYPE,SIZE,RM,MODEL
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
# 5. Construction des exclusions pour nwipe
#    Format : --exclude=/dev/sda,/dev/sdb  (virgule, pas répété)
# ──────────────────────────────────────────────────────────
EXCLUDE_LIST=""
ALL_BLOCK=$(lsblk -dno NAME,TYPE | awk '$2=="disk" {print $1}')

for D in $ALL_BLOCK; do
    if ! echo "$DISKS" | grep -qw "$D"; then
        if [ -z "$EXCLUDE_LIST" ]; then
            EXCLUDE_LIST="/dev/$D"
        else
            EXCLUDE_LIST="$EXCLUDE_LIST,/dev/$D"
        fi
    fi
done

echo "Exclusions nwipe : ${EXCLUDE_LIST:-aucune}"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 6. Effacement via nwipe
# ──────────────────────────────────────────────────────────
LOGFILE="$RAPPORT_LOCAL/nwipe_${DATE_NOW}.log"
WIPE_ERRORS=0

echo ""
echo ">>> Lancement de nwipe (DoD 5220.22-M — 7 passes)..."

if [ -n "$EXCLUDE_LIST" ]; then
    nwipe \
        --autonuke \
        --nogui \
        --method=dod522022m \
        --verify=last \
        --logfile="$LOGFILE" \
        --exclude="$EXCLUDE_LIST" \
    && echo ">>> OK : Effacement terminé avec succès." \
    || { echo ">>> ERREUR : L'effacement a échoué !"; WIPE_ERRORS=1; }
else
    nwipe \
        --autonuke \
        --nogui \
        --method=dod522022m \
        --verify=last \
        --logfile="$LOGFILE" \
    && echo ">>> OK : Effacement terminé avec succès." \
    || { echo ">>> ERREUR : L'effacement a échoué !"; WIPE_ERRORS=1; }
fi

echo "----------------------------------------------------------"
[ "$WIPE_ERRORS" -gt 0 ] && echo "ATTENTION : Erreur(s) lors de l'effacement."

# ──────────────────────────────────────────────────────────
# 7. Génération du rapport PDF
# ──────────────────────────────────────────────────────────
echo "Génération du rapport PDF..."
PDF_FILE="$RAPPORT_LOCAL/rapport_${HOSTNAME_ID}.pdf"

python3 - << PYEOF
import os, sys
try:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Preformatted
    from reportlab.lib.units import cm
except ImportError:
    print("ERREUR : reportlab non disponible, rapport texte uniquement.")
    sys.exit(0)

pdf_path    = "$PDF_FILE"
mac         = "$MAC_ADDR"
date        = "$DATE_NOW"
errors      = $WIPE_ERRORS
rapport_dir = "$RAPPORT_LOCAL"

doc = SimpleDocTemplate(pdf_path, pagesize=A4,
    rightMargin=2*cm, leftMargin=2*cm,
    topMargin=2*cm, bottomMargin=2*cm)

styles = getSampleStyleSheet()
story  = []

story.append(Paragraph("CERTIFICAT D'EFFACEMENT SECURISE", styles['Title']))
story.append(Spacer(1, 0.5*cm))
story.append(Paragraph(f"Machine : {mac}",                    styles['Heading2']))
story.append(Paragraph(f"Date    : {date}",                   styles['Heading2']))
story.append(Paragraph(f"Methode : DoD 5220.22-M (7 passes)", styles['Heading2']))
status = "SUCCES" if errors == 0 else f"ECHEC ({errors} erreur(s))"
story.append(Paragraph(f"Statut  : {status}",                 styles['Heading2']))
story.append(Spacer(1, 0.5*cm))

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
# 8. Configuration SSH
# ──────────────────────────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keyscan -T 10 -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null \
    || echo "AVERTISSEMENT : ssh-keyscan a échoué, on continue quand même."

# ──────────────────────────────────────────────────────────
# 9. Transfert vers le serveur
# ──────────────────────────────────────────────────────────
echo "Transfert vers $SERVER_IP:/opt/pxe-wipe/rapports/ ..."

scp \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    -r "$RAPPORT_LOCAL" \
    root@"$SERVER_IP":/opt/pxe-wipe/rapports/ \
&& echo "Transfert réussi." \
|| {
    echo "AVERTISSEMENT : Échec du transfert SSH."
    echo "Rapports conservés dans : $RAPPORT_LOCAL"
    ls -lh "$RAPPORT_LOCAL" 2>/dev/null || true
}

# ──────────────────────────────────────────────────────────
# 10. Extinction sécurisée
# ──────────────────────────────────────────────────────────
echo "----------------------------------------------------------"
echo "Machine sécurisée. Extinction dans 10 secondes..."
sleep 10
sync
poweroff -f