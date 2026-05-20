#!/bin/bash
clear
echo "=========================================================="
echo "    INITIALISATION DE L'EFFACEMENT MILITAIRE (NWIPE)      "
echo "=========================================================="

# 1. Détection dynamique de la passerelle (IP du serveur Docker parent)
SERVER_IP=$(ip route show default | awk '{print $3}')
RAPPORT_LOCAL="/root/rapports_effacement"
mkdir -p "$RAPPORT_LOCAL"

# 2. Identification unique de la machine
MAC_ADDR=$(cat /sys/class/net/$(ip route show default | awk '{print $5}')/address | tr -d ':')
DATE_NOW=$(date +%Y%m%d_%H%M%S)

echo "Serveur Parent détecté : $SERVER_IP"
echo "Adresse MAC Machine    : $MAC_ADDR"
echo "----------------------------------------------------------"

# 3. Récupération des disques durs réels (exclut la RAM, les loopback et le stockage live)
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk" && $1!~/^loop|^ram|^sr/ {print $1}')

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté pour l'effacement."
    sleep 10
    poweroff -f
fi

for DISK in $DISKS; do
    DISK_PATH="/dev/$DISK"
    echo "Lancement de nwipe (DoD 5220.22-M - 7 passes) sur $DISK_PATH..."
    
    # Exécution de nwipe en ligne de commande (génère un log et un rapport PDF)
    nwipe \
      --nogui \
      --autonuke \
      --method=dod522022m \
      --verify=last \
      --logfile="$RAPPORT_LOCAL/nwipe_${DISK}_${DATE_NOW}.log" \
      --pdf="$RAPPORT_LOCAL" \
      "$DISK_PATH"
done

echo "----------------------------------------------------------"
echo "Effacement terminé. Transfert des certificats d'audit..."

# 4. Envoi dynamique des rapports vers le dossier partagé de l'hôte via SSH
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null

# Utilisation d'une clé SSH sans mot de passe générée au build
scp -i /root/.ssh/id_rsa -r "$RAPPORT_LOCAL"/* root@"$SERVER_IP":/opt/pxe-wipe/rapports/ || echo "Alerte : Échec de l'envoi du rapport."

echo "Machine sécurisée. Extinction en cours..."
sleep 5
sync
poweroff -f