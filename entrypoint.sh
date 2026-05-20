#!/bin/bash
set -euo pipefail

INTERFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip -o -4 addr show dev "$INTERFACE" 2>/dev/null | awk 'NR==1 {split($4,a,"/"); print a[1]}')

if [ -z "$INTERFACE" ] || [ -z "$SERVER_IP" ]; then
    echo "ERREUR : impossible de détecter l'interface/IP"
    exit 1
fi

SUBNET=$(echo "$SERVER_IP" | cut -d'.' -f1-3)
echo "=== Configuration Dynamique du Conteneur PXE ==="
echo "Interface : $INTERFACE | IP : $SERVER_IP"

# --- SSH ---
/usr/sbin/sshd

# --- Montage tmpfs pour NFS (NFS ne peut pas servir overlayfs Docker) ---
if [ -f /var/nfsroot/live/filesystem.squashfs ]; then
    mkdir -p /tmp/nfs_backup
    mv /var/nfsroot/live/filesystem.squashfs /tmp/nfs_backup/
fi
mount -t tmpfs -o size=4G,mode=755 tmpfs /var/nfsroot
mkdir -p /var/nfsroot/live
if [ -f /tmp/nfs_backup/filesystem.squashfs ]; then
    mv /tmp/nfs_backup/filesystem.squashfs /var/nfsroot/live/
    rm -rf /tmp/nfs_backup
fi

# --- Configs TFTP ---
mkdir -p /var/tftpboot/grub
mkdir -p /var/tftpboot/pxelinux.cfg

# UEFI : GRUB cherche grub/grub.cfg depuis la racine TFTP
cat > /var/tftpboot/grub/grub.cfg << EOF
rmmod tpm
set timeout=5
set default=0

menuentry "Nwipe Auto (UEFI PXE)" {
  linux /vmlinuz boot=live netboot=nfs nfsroot=$SERVER_IP:/var/nfsroot ip=dhcp nomodeset rw quiet
  initrd /initrd.img
}
EOF

# BIOS
cat > /var/tftpboot/pxelinux.cfg/default << EOF
DEFAULT wipe
LABEL wipe
  KERNEL vmlinuz
  APPEND initrd=initrd.img boot=live netboot=nfs nfsroot=$SERVER_IP:/var/nfsroot ip=dhcp nomodeset rw quiet
EOF

# --- dnsmasq ---
# FIX UEFI : dhcp-option 210 = path prefix, indique à GRUB où chercher grub.cfg
# Sans ce prefix, GRUB construit un chemin relatif incorrect et ne trouve pas grub.cfg
cat > /etc/dnsmasq.conf << EOF
port=0
interface=$INTERFACE
bind-interfaces
dhcp-range=$SUBNET.100,$SUBNET.200,12h

# BIOS
dhcp-boot=tag:!efi-x86_64,pxelinux.0

# UEFI
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:efi-x86_64,option:client-arch,11
dhcp-boot=tag:efi-x86_64,bootx64.efi
# Indique le prefix de chemin à GRUB EFI (option 210)
dhcp-option=tag:efi-x86_64,210,/

enable-tftp
tftp-root=/var/tftpboot
log-dhcp
EOF

# --- NFS ---
# FIX Permission denied : le tmpfs monté dynamiquement n'est pas connu d'exportfs
# tant que exports + exportfs -ra ne sont pas appelés APRES le montage tmpfs
# no_root_squash obligatoire : live-boot monte en tant que root
cat > /etc/exports << EOF
/var/nfsroot *(ro,fsid=0,sync,no_subtree_check,no_root_squash)
EOF

# rpcbind doit tourner avant nfs
rpcbind || true
sleep 1

# exportfs -ra relit /etc/exports et publie le nouveau point de montage tmpfs
exportfs -ra

# Démarre NFS
/etc/init.d/nfs-kernel-server start || true

# Vérifie que l'export est bien actif
echo "=== Exports NFS actifs ==="
exportfs -v

echo "=== Serveur PXE prêt ! SERVER_IP=$SERVER_IP ==="
exec dnsmasq -d