#!/bin/bash
clear
echo "=========================================================="
echo "    INITIALISATION DE L'EFFACEMENT MILITAIRE (NWIPE)      "
echo "=========================================================="

# 1. Détection dynamique de la passerelle / serveur NFS pour le téléversement
SERVER_IP=$(ip route show default | awk '{print $3}')
RAPPORT_LOCAL="/root/rapports_effacement"
mkdir -p "$RAPPORT_LOCAL"

# 2. Identification de la machine cible
MAC_ADDR=$(cat /sys/class/net/$(ip route show default | awk '{print $5}')/address | tr -d ':')
DATE_NOW=$(date +%Y%m%d_%H%M%S)

echo "Serveur Parent détecté : $SERVER_IP"
echo "Adresse MAC Machine    : $MAC_ADDR"
echo "----------------------------------------------------------"

# 3. Récupération de la liste des disques physiques éligibles
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk" && $1!~/^loop|^ram|^sr/ {print $1}')

if [ -z "$DISKS" ]; then
    echo "ERREUR : Aucun disque physique détecté pour l'effacement."
    sleep 10
    poweroff -f
fi

for DISK in $DISKS do
    DISK_PATH="/dev/$DISK"
    echo "Lancement de nwipe (DoD 5220.22-M - 7 passes) sur $DISK_PATH..."
    
    # Exécution de nwipe en arrière-plan sans GUI avec génération de logs/PDF
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
echo "Effacement terminé. Exportation des certificats PDF..."

# 4. Envoi des rapports via SSH/SCP sur le serveur parent de manière dynamique
# Note: Utilise les clés SSH configurées au build pour ne pas demander de mot de passe
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -H "$SERVER_IP" >> ~/.ssh/known_hosts

scp -r "$RAPPORT_LOCAL"/* root@" $SERVER_IP":/opt/pxe-wipe/rapports/ || echo "Échec de la transmission du rapport."

echo "Machine sécurisée. Extinction automatique..."
sleep 5
sync
poweroff -f
