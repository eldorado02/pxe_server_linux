#!/bin/bash
# ==========================================================
#  CLIENT WIPE — Effacement nwipe + rapport PDF
# ==========================================================
set -u

clear
echo "=========================================================="
echo "    INITIALISATION DE L'EFFACEMENT (NWIPE — MODE ZERO)    "
echo "=========================================================="

# ──────────────────────────────────────────────────────────
# 1. Réseau
# ──────────────────────────────────────────────────────────
IFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')

if [ -z "$SERVER_IP" ] || [ -z "$IFACE" ]; then
    echo "ERREUR FATALE : Impossible de détecter la passerelle réseau."
    sleep 30
    poweroff -f
fi

# ──────────────────────────────────────────────────────────
# 2. Identification
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
# 3. Détection disque live — NFS aware
#    Sur NFS live-boot, findmnt / retourne "IP:/chemin"
#    → contient ":" → pas un block device local
# ──────────────────────────────────────────────────────────
LIVE_DEV=""
RAW_SOURCE=$(findmnt -n -o SOURCE / 2>/dev/null || true)

if echo "$RAW_SOURCE" | grep -q ':'; then
    echo "Boot NFS détecté — aucun disque local exclu."
    # Protéger quand même les éventuels disques amovibles (clé USB)
    LIVE_DEV=$(lsblk -dno NAME,RM 2>/dev/null | awk '$2=="1" {print $1}' | head -1 || true)
elif echo "$RAW_SOURCE" | grep -qE '^(overlay|tmpfs|aufs|/dev/loop)'; then
    LIVE_DEV=$(findmnt -n -o SOURCE /run/live/medium 2>/dev/null \
        | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||' || true)
    if [ -z "$LIVE_DEV" ]; then
        LIVE_DEV=$(lsblk -dno NAME,RM 2>/dev/null | awk '$2=="1" {print $1}' | head -1 || true)
    fi
    if [ -z "$LIVE_DEV" ]; then
        LOOP_BACKING=$(losetup -n -O BACK-FILE /dev/loop0 2>/dev/null || true)
        if [ -n "$LOOP_BACKING" ]; then
            LIVE_DEV=$(findmnt -n -o SOURCE -T "$LOOP_BACKING" 2>/dev/null \
                | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||' || true)
        fi
    fi
else
    LIVE_DEV=$(echo "$RAW_SOURCE" | sed 's|/dev/||;s|[0-9]*$||;s|p[0-9]*$||')
fi

echo "Disque live protégé : ${LIVE_DEV:-aucun (boot NFS)}"

# ──────────────────────────────────────────────────────────
# 4. Disques à effacer
# ──────────────────────────────────────────────────────────
if [ -n "$LIVE_DEV" ]; then
    DISKS=$(lsblk -dno NAME,TYPE,RM 2>/dev/null \
        | awk '$2=="disk" && $3=="0" && $1!~/^loop|^ram|^sr/' \
        | awk '{print $1}' \
        | grep -v "^${LIVE_DEV}$" || true)
else
    DISKS=$(lsblk -dno NAME,TYPE,RM 2>/dev/null \
        | awk '$2=="disk" && $3=="0" && $1!~/^loop|^ram|^sr/' \
        | awk '{print $1}' || true)
fi

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté."
    lsblk -dno NAME,TYPE,SIZE,RM,MODEL
    sleep 30
    poweroff -f
fi

echo "Disques à effacer :"
for D in $DISKS; do
    SIZE=$(lsblk -dno SIZE "/dev/$D" 2>/dev/null || echo "?")
    MODEL=$(lsblk -dno MODEL "/dev/$D" 2>/dev/null || echo "inconnu")
    SERIAL=$(lsblk -dno SERIAL "/dev/$D" 2>/dev/null || echo "")
    if [ -z "$SERIAL" ]; then
        SERIAL=$(smartctl -i "/dev/$D" 2>/dev/null | awk '/Serial Number/{print $NF}' || echo "inconnu")
    fi
    echo "  /dev/$D — $SIZE — $MODEL — S/N: $SERIAL"
done
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 5. Exclusions nwipe (virgule-séparé)
# ──────────────────────────────────────────────────────────
EXCLUDE_LIST=""
ALL_BLOCK=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}')
for D in $ALL_BLOCK; do
    if ! echo "$DISKS" | grep -qw "$D"; then
        [ -z "$EXCLUDE_LIST" ] \
            && EXCLUDE_LIST="/dev/$D" \
            || EXCLUDE_LIST="$EXCLUDE_LIST,/dev/$D"
    fi
done

echo "Exclusions nwipe : ${EXCLUDE_LIST:-aucune}"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 6. Nwipe — code retour capturé proprement
#    --PDFreportpath : PDF certifié natif généré par nwipe
# ──────────────────────────────────────────────────────────
LOGFILE="$RAPPORT_LOCAL/nwipe_${DATE_NOW}.log"
WIPE_ERRORS=0

echo ""
echo ">>> Lancement de nwipe (zero — 1 passe)..."

if [ -n "$EXCLUDE_LIST" ]; then
    nwipe --autonuke --nogui --method=zero --verify=off \
          --logfile="$LOGFILE" \
          --PDFreportpath="$RAPPORT_LOCAL" \
          --exclude="$EXCLUDE_LIST" || true
else
    nwipe --autonuke --nogui --method=zero --verify=off \
          --logfile="$LOGFILE" \
          --PDFreportpath="$RAPPORT_LOCAL" || true
fi

# Vérifier si le log contient un succès
if grep -q "Finished final round" "$LOGFILE" 2>/dev/null; then
    echo ">>> OK : Effacement confirmé dans le log."
    WIPE_ERRORS=0
else
    echo ">>> ATTENTION : 'Finished final round' absent du log."
    WIPE_ERRORS=1
fi

echo "----------------------------------------------------------"
[ "$WIPE_ERRORS" -gt 0 ] && echo "ATTENTION : Vérifier le log nwipe."

# ──────────────────────────────────────────────────────────
# 7. Récupération numéros de série pour le PDF
# ──────────────────────────────────────────────────────────
DISKS_INFO=""
for D in $DISKS; do
    SIZE=$(lsblk -dno SIZE "/dev/$D" 2>/dev/null || echo "?")
    MODEL=$(lsblk -dno MODEL "/dev/$D" 2>/dev/null || echo "inconnu")
    SERIAL=$(lsblk -dno SERIAL "/dev/$D" 2>/dev/null || echo "")
    if [ -z "$SERIAL" ]; then
        SERIAL=$(smartctl -i "/dev/$D" 2>/dev/null | awk '/Serial Number/{print $NF}' || echo "inconnu")
    fi
    DISKS_INFO="${DISKS_INFO}/dev/$D | $SIZE | $MODEL | S/N: $SERIAL\n"
done

# ──────────────────────────────────────────────────────────
# 8. Génération PDF
# ──────────────────────────────────────────────────────────
echo "Génération du rapport PDF (old)..."
PDF_FILE="$RAPPORT_LOCAL/old_rapport_${HOSTNAME_ID}.pdf"

python3 - << PYEOF
import os, sys

try:
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Preformatted, Table, TableStyle
    from reportlab.lib import colors
    from reportlab.lib.units import cm
except ImportError as e:
    print(f"ERREUR reportlab : {e}")
    sys.exit(0)

pdf_path    = "$PDF_FILE"
mac         = "$MAC_ADDR"
date        = "$DATE_NOW"
errors      = $WIPE_ERRORS
rapport_dir = "$RAPPORT_LOCAL"
disks_info  = r"$DISKS_INFO"
server_ip   = "$SERVER_IP"

doc    = SimpleDocTemplate(pdf_path, pagesize=A4,
             rightMargin=2*cm, leftMargin=2*cm,
             topMargin=2*cm, bottomMargin=2*cm)
styles = getSampleStyleSheet()
story  = []

story.append(Paragraph("CERTIFICAT D'EFFACEMENT SECURISE", styles['Title']))
story.append(Spacer(1, 0.5*cm))

# Infos machine
story.append(Paragraph("Informations Machine", styles['Heading2']))
data = [
    ["MAC Address",  mac],
    ["Date",         date],
    ["Serveur PXE",  server_ip],
    ["Methode",      "Zero (1 passe) — TEST"],
    ["Statut",       "SUCCES" if errors == 0 else "ERREUR — verifier log"],
]
t = Table(data, colWidths=[5*cm, 11*cm])
t.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (0,-1), colors.lightgrey),
    ('GRID',       (0,0), (-1,-1), 0.5, colors.grey),
    ('FONTNAME',   (0,0), (-1,-1), 'Helvetica'),
    ('FONTSIZE',   (0,0), (-1,-1), 10),
    ('PADDING',    (0,0), (-1,-1), 6),
]))
story.append(t)
story.append(Spacer(1, 0.5*cm))

# Disques
story.append(Paragraph("Disques Effaces", styles['Heading2']))
for line in disks_info.strip().split(r'\n'):
    if line.strip():
        story.append(Paragraph(line.strip(), styles['Normal']))
story.append(Spacer(1, 0.5*cm))

# Log nwipe
story.append(Paragraph("Log nwipe complet", styles['Heading2']))
for logfile in sorted(os.listdir(rapport_dir)):
    if logfile.endswith('.log'):
        story.append(Paragraph(f"--- {logfile} ---", styles['Heading3']))
        with open(os.path.join(rapport_dir, logfile), 'r', errors='replace') as f:
            content = f.read()
        story.append(Preformatted(content, styles['Code']))
        story.append(Spacer(1, 0.3*cm))

doc.build(story)
print(f"PDF genere : {pdf_path}")
PYEOF

echo "Contenu rapport :"
ls -lh "$RAPPORT_LOCAL"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 9. SSH + Transfert
# ──────────────────────────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keyscan -T 10 -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

echo "Transfert vers $SERVER_IP:/opt/pxe-wipe/rapports/ ..."

scp \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    -r "$RAPPORT_LOCAL" \
    root@"$SERVER_IP":/opt/pxe-wipe/rapports/ \
&& echo "Transfert réussi." \
|| {
    echo "AVERTISSEMENT : Échec transfert SSH."
    ls -lh "$RAPPORT_LOCAL" || true
}

# ──────────────────────────────────────────────────────────
# 10. Extinction
# ──────────────────────────────────────────────────────────
echo "----------------------------------------------------------"
echo "Machine sécurisée. Extinction dans 10 secondes..."
sleep 10
sync
# poweroff -f