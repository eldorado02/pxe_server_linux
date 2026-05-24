#!/bin/bash
# ==========================================================
#  TEST UNIQUEMENT — Pas de formatage
#  Teste : génération PDF + transfert SSH vers le serveur
# ==========================================================
set -uo pipefail

clear
echo "=========================================================="
echo "         MODE TEST — TRANSFERT + PDF UNIQUEMENT           "
echo "=========================================================="

# ──────────────────────────────────────────────────────────
# 1. Détection réseau
# ──────────────────────────────────────────────────────────
IFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip route show default 2>/dev/null | awk 'NR==1 {print $3}')

if [ -z "$SERVER_IP" ] || [ -z "$IFACE" ]; then
    echo "ERREUR FATALE : Impossible de détecter la passerelle réseau."
    sleep 30
    exit 1
fi

MAC_ADDR=$(cat /sys/class/net/"$IFACE"/address 2>/dev/null | tr -d ':' || echo "UNKNOWNMAC")
DATE_NOW=$(date +%Y%m%d_%H%M%S)
HOSTNAME_ID="${MAC_ADDR}_${DATE_NOW}"
RAPPORT_LOCAL="/root/rapports_effacement/$HOSTNAME_ID"
mkdir -p "$RAPPORT_LOCAL"

echo "Serveur détecté : $SERVER_IP"
echo "Interface       : $IFACE"
echo "MAC             : $MAC_ADDR"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 2. Simulation du log nwipe (faux log pour tester le PDF)
# ──────────────────────────────────────────────────────────
LOGFILE="$RAPPORT_LOCAL/nwipe_${DATE_NOW}.log"
WIPE_ERRORS=0

echo ">>> Simulation nwipe (pas de vrai effacement)..."
cat > "$LOGFILE" << EOF
[TEST] nwipe simulation — aucun disque effacé
Date    : $DATE_NOW
Machine : $MAC_ADDR
Methode : DoD 5220.22-M (7 passes) — SIMULATION UNIQUEMENT
Disque  : /dev/nvme0n1 (NON EFFACE — MODE TEST)
Statut  : SUCCES SIMULE
EOF
echo ">>> Log de test créé : $LOGFILE"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 3. Génération du rapport PDF
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
except ImportError as e:
    print(f"ERREUR reportlab : {e}")
    print("reportlab non disponible — rapport texte uniquement.")
    # Créer un fichier texte à la place pour quand même tester le transfert
    with open("$PDF_FILE".replace('.pdf', '.txt'), 'w') as f:
        f.write("RAPPORT TEST — reportlab manquant\n")
        f.write("MAC : $MAC_ADDR\n")
        f.write("Date : $DATE_NOW\n")
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

story.append(Paragraph("CERTIFICAT D'EFFACEMENT SECURISE — MODE TEST", styles['Title']))
story.append(Spacer(1, 0.5*cm))
story.append(Paragraph(f"Machine : {mac}",                        styles['Heading2']))
story.append(Paragraph(f"Date    : {date}",                       styles['Heading2']))
story.append(Paragraph(f"Methode : DoD 5220.22-M (7 passes)",     styles['Heading2']))
story.append(Paragraph(f"Statut  : TEST — AUCUN DISQUE EFFACE",   styles['Heading2']))
story.append(Spacer(1, 0.5*cm))

for logfile in sorted(os.listdir(rapport_dir)):
    if logfile.endswith('.log'):
        story.append(Paragraph(f"--- {logfile} ---", styles['Heading3']))
        with open(os.path.join(rapport_dir, logfile), 'r', errors='replace') as f:
            content = f.read()
        story.append(Preformatted(content, styles['Code']))
        story.append(Spacer(1, 0.3*cm))

doc.build(story)
print(f"PDF généré avec succès : {pdf_path}")
PYEOF

echo "Contenu du dossier rapport :"
ls -lh "$RAPPORT_LOCAL"
echo "----------------------------------------------------------"

# ──────────────────────────────────────────────────────────
# 4. Test SSH : ping du serveur
# ──────────────────────────────────────────────────────────
echo "Test ping vers $SERVER_IP ..."
if ping -c 2 -W 3 "$SERVER_IP" > /dev/null 2>&1; then
    echo ">>> Ping OK"
else
    echo ">>> ATTENTION : ping échoué — réseau peut-être coupé"
fi

# ──────────────────────────────────────────────────────────
# 5. Configuration SSH
# ──────────────────────────────────────────────────────────
mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo "Test ssh-keyscan vers $SERVER_IP ..."
if ssh-keyscan -T 10 -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null; then
    echo ">>> ssh-keyscan OK"
else
    echo ">>> ssh-keyscan échoué — ajout StrictHostKeyChecking=no"
    echo "StrictHostKeyChecking no" > ~/.ssh/config
fi

# ──────────────────────────────────────────────────────────
# 6. Transfert SCP
# ──────────────────────────────────────────────────────────
echo "Transfert vers $SERVER_IP:/opt/pxe-wipe/rapports/ ..."

if scp \
    -i /root/.ssh/id_ed25519 \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=30 \
    -v \
    -r "$RAPPORT_LOCAL" \
    root@"$SERVER_IP":/opt/pxe-wipe/rapports/; then
    echo "=========================================="
    echo ">>> TRANSFERT REUSSI !"
    echo "=========================================="
else
    echo "=========================================="
    echo ">>> ECHEC TRANSFERT SSH"
    echo ">>> Vérifier : clé SSH, IP serveur, dossier /opt/pxe-wipe/rapports/"
    echo "=========================================="
fi

echo "----------------------------------------------------------"
echo "TEST TERMINE. Ce PC ne s'éteint PAS (mode test)."
echo "Fichiers locaux dans : $RAPPORT_LOCAL"
ls -lh "$RAPPORT_LOCAL"