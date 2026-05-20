#!/bin/bash
set -e

# Détection de l'interface réseau et de l'adresse IP active du serveur
INTERFACE=$(ip route show default | awk '{print $5}')
SERVER_IP=$(ip -o -4 addr show dev "$INTERFACE" | awk '{split($4,a,"/"); print a[1]}')
SUBNET=$(echo "$SERVER_IP" | cut -d'.' -f1-3)

echo "=== Configuration Dynamique du Conteneur PXE ==="
echo "Interface réseau cible : $INTERFACE"
echo "IP Serveur déterminée  : $SERVER_IP"
echo "Plage DHCP dynamique   : $SUBNET.100 à $SUBNET.200"

# Démarrage du serveur SSH interne pour recevoir les rapports du fils
service ssh start

# Écriture de la configuration Dnsmasq (DHCP + TFTP)
cat <<EOF > /etc/dnsmasq.conf
interface=$INTERFACE
bind-interfaces
dhcp-range=$SUBNET.100,$SUBNET.200,12h
dhcp-boot=pxelinux.0
enable-tftp
tftp-root=/var/tftpboot
log-dhcp
EOF

# Écriture du menu d'amorcage PXE (NFSROOT pointant sur l'IP dynamique)
mkdir -p /var/tftpboot/pxelinux.cfg
cat <<EOF > /var/tftpboot/pxelinux.cfg/default
DEFAULT wipe_live
LABEL wipe_live
    KERNEL vmlinuz
    APPEND initrd=initrd.img boot=live netboot=nfs nfsroot=$SERVER_IP:/var/nfsroot ip=dhcp rw
EOF

# Démarrage du partage système NFS
service rpcbind start
exportfs -va

echo "Démarrage des services d'écoute réseau..."
exec dnsmasq -k