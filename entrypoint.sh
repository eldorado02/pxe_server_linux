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

# --- Modules NFS (chargés depuis le conteneur privilégié) ---
modprobe nfsd 2>/dev/null || true
modprobe nfs  2>/dev/null || true

# --- Montage tmpfs pour NFS ---
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

# UEFI
cat > /var/tftpboot/grub/grub.cfg << EOF
rmmod tpm
set timeout=5
set default=0
menuentry "Nwipe Auto (UEFI PXE)" {
  linux /vmlinuz boot=live netboot=nfs nfsroot=$SERVER_IP:/var/nfsroot ip=dhcp nomodeset rw quiet text snd_hda_intel.enable=0 snd-sof-pci.enable=0 systemd.unit=multi-user.target
  initrd /initrd.img
}
EOF

# BIOS
cat > /var/tftpboot/pxelinux.cfg/default << EOF
DEFAULT wipe
LABEL wipe
  KERNEL vmlinuz
  APPEND initrd=initrd.img boot=live netboot=nfs nfsroot=$SERVER_IP:/var/nfsroot ip=dhcp nomodeset rw quiet text snd_hda_intel.enable=0 snd-sof-pci.enable=0 systemd.unit=multi-user.target
EOF

# --- dnsmasq ---
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
dhcp-option=tag:efi-x86_64,210,/
enable-tftp
tftp-root=/var/tftpboot
log-dhcp
EOF

# --- NFS ---
cat > /etc/exports << EOF
/var/nfsroot *(ro,fsid=0,sync,no_subtree_check,no_root_squash)
EOF

mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null || true

rpcbind -w
sleep 2
if ! rpcinfo -p localhost > /dev/null 2>&1; then
    echo "ERREUR FATALE : rpcbind n'a pas démarré"
    exit 1
fi

exportfs -ra
rpc.nfsd 8
rpc.mountd --no-udp --port 20048
sleep 1

echo "=== Exports NFS actifs ==="
exportfs -v
echo "=== rpcinfo ==="
rpcinfo -p localhost | grep -E 'nfs|mount' || echo "ATTENTION: nfs non visible"

echo "=== Serveur PXE prêt ! SERVER_IP=$SERVER_IP ==="
exec dnsmasq -d