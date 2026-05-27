#!/bin/bash
# =============================================================
# entrypoint.sh — Serveur PXE ShredOS
# =============================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# 1. Détection réseau
# ─────────────────────────────────────────────────────────────
INTERFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip -o -4 addr show dev "$INTERFACE" 2>/dev/null | awk 'NR==1 {split($4,a,"/"); print a[1]}')

if [ -z "$INTERFACE" ] || [ -z "$SERVER_IP" ]; then
    echo "ERREUR : impossible de détecter l'interface/IP"
    exit 1
fi

SUBNET=$(echo "$SERVER_IP" | cut -d'.' -f1-3)

echo "============================================================"
echo " Serveur PXE ShredOS"
echo "============================================================"
echo " Interface : $INTERFACE"
echo " IP        : $SERVER_IP"
echo " Sous-réseau : $SUBNET.0/24"
echo "============================================================"

# ─────────────────────────────────────────────────────────────
# 2. Téléchargement ShredOS depuis GitHub
# ─────────────────────────────────────────────────────────────
SHREDOS_IMG="/opt/shredos/shredos.img"
SHREDOS_VERSION="${SHREDOS_VERSION:-latest}"

if [ ! -f "$SHREDOS_IMG" ]; then
    echo "=== Téléchargement de ShredOS ($SHREDOS_VERSION) ==="

    if [ "$SHREDOS_VERSION" = "latest" ]; then
        RELEASE_URL="https://api.github.com/repos/PartialVolume/shredos.x86_64/releases/latest"
    else
        RELEASE_URL="https://api.github.com/repos/PartialVolume/shredos.x86_64/releases/tags/$SHREDOS_VERSION"
    fi

    # Récupérer l'URL du .img (64-bit, pas iso, pas i686)
    IMG_URL=$(curl -fsSL "$RELEASE_URL" \
        | jq -r '.assets[] | select(.name | test("x86-64.*\\.img\\.tar\\.gz$")) | .browser_download_url' \
        | head -1)

    if [ -z "$IMG_URL" ]; then
        # Fallback : prendre n'importe quel .img.tar.gz
        IMG_URL=$(curl -fsSL "$RELEASE_URL" \
            | jq -r '.assets[] | select(.name | endswith(".img.tar.gz")) | .browser_download_url' \
            | grep -v i686 | head -1)
    fi

    if [ -z "$IMG_URL" ]; then
        echo "ERREUR : Impossible de trouver l'image ShredOS dans la release."
        exit 1
    fi

    echo "URL : $IMG_URL"
    wget -q --show-progress -O /opt/shredos/shredos.img.tar.gz "$IMG_URL"

    echo "=== Extraction de l'image ==="
    cd /opt/shredos
    gunzip shredos.img.tar.gz
    tar xf shredos.img.tar 2>/dev/null || true
    # Renommer le .img quel que soit son nom daté
    find /opt/shredos -maxdepth 1 -name "shredos*.img" ! -name "shredos.img" \
        | head -1 | xargs -I{} mv {} "$SHREDOS_IMG" 2>/dev/null || true
    rm -f /opt/shredos/*.tar /opt/shredos/*.tar.gz
    echo "=== Image ShredOS disponible : $SHREDOS_IMG ==="
else
    echo "=== Image ShredOS déjà présente, skip téléchargement ==="
fi

# ─────────────────────────────────────────────────────────────
# 3. Extraction kernel + initrd + squashfs depuis le .img
#    Le .img ShredOS est une image FAT32 — on monte via loopback
# ─────────────────────────────────────────────────────────────
VMLINUZ="/var/tftpboot/vmlinuz"
INITRD="/var/tftpboot/initrd.img"
SQUASHFS="/var/nfsroot/live/filesystem.squashfs"

if [ ! -f "$VMLINUZ" ] || [ ! -f "$SQUASHFS" ]; then
    echo "=== Extraction des fichiers boot depuis ShredOS.img ==="

    LOOP_DEV=$(losetup -fP --show "$SHREDOS_IMG")
    echo "Loop device : $LOOP_DEV"

    # Trouver la partition FAT32
    PART="${LOOP_DEV}p1"
    sleep 1

    MOUNT_POINT=$(mktemp -d)
    mount -o ro "$PART" "$MOUNT_POINT"

    # Kernel — peut être /boot/shredos ou /boot/vmlinuz*
    KERNEL_SRC=$(find "$MOUNT_POINT/boot" -maxdepth 1 \
        -name "shredos" -o -name "vmlinuz*" 2>/dev/null | head -1)
    if [ -z "$KERNEL_SRC" ]; then
        KERNEL_SRC=$(find "$MOUNT_POINT" -maxdepth 3 -name "vmlinuz*" 2>/dev/null | head -1)
    fi

    # Initrd
    INITRD_SRC=$(find "$MOUNT_POINT" -maxdepth 3 \
        -name "initrd*" -o -name "initramfs*" 2>/dev/null | head -1)

    # Squashfs
    SQUASHFS_SRC=$(find "$MOUNT_POINT" -maxdepth 4 \
        -name "*.squashfs" -o -name "*.sfs" 2>/dev/null | head -1)

    echo "Kernel   : $KERNEL_SRC"
    echo "Initrd   : $INITRD_SRC"
    echo "Squashfs : $SQUASHFS_SRC"

    [ -n "$KERNEL_SRC"   ] && cp "$KERNEL_SRC"   "$VMLINUZ"
    [ -n "$INITRD_SRC"   ] && cp "$INITRD_SRC"   "$INITRD"
    [ -n "$SQUASHFS_SRC" ] && cp "$SQUASHFS_SRC" "$SQUASHFS"

    umount "$MOUNT_POINT"
    rmdir  "$MOUNT_POINT"
    losetup -d "$LOOP_DEV"

    echo "=== Extraction terminée ==="
else
    echo "=== Fichiers boot déjà extraits, skip ==="
fi

# Vérification
for F in "$VMLINUZ" "$INITRD" "$SQUASHFS"; do
    if [ ! -f "$F" ]; then
        echo "ERREUR FATALE : $F manquant après extraction !"
        exit 1
    fi
done

# ─────────────────────────────────────────────────────────────
# 4. FTP — récupérer IP et credentials depuis les vars d'env
#    (injectées par docker-compose depuis le service ftp)
# ─────────────────────────────────────────────────────────────
FTP_USER="${FTP_USER:-shredreports}"
FTP_PASS="${FTP_PASS:-shredos2025}"
# Le serveur FTP tourne sur la même machine (network_mode: host)
FTP_IP="$SERVER_IP"

# ─────────────────────────────────────────────────────────────
# 5. Configuration TFTP — GRUB (UEFI) + PXELINUX (BIOS)
#
#    Options nwipe dans grub.cfg :
#      --autonuke  : démarre sans intervention
#      --nogui     : pas d'interface graphique
#      --method=zero : effacement zéro
#      --verify=off  : pas de vérification (plus rapide)
#      --nousb       : ne pas effacer la clé USB de boot
#      --PDFreportpath=/ : PDF dans / de ShredOS
#
#    shredos_post_wipe : script téléchargé depuis le serveur HTTP
#      → envoie les PDF/logs via lftp vers le serveur FTP
#
#    lftp intégré ShredOS :
#      → mput *.pdf et nwipe_log* vers le serveur FTP
# ─────────────────────────────────────────────────────────────
echo "=== Configuration TFTP ==="

# UEFI — grub.cfg
cat > /var/tftpboot/grub/grub.cfg << EOF
rmmod tpm
set timeout=5
set default=0

menuentry "ShredOS — Autonuke PXE" {
  linux /vmlinuz \
    boot=live \
    netboot=nfs \
    nfsroot=${SERVER_IP}:/var/nfsroot \
    ip=dhcp \
    nomodeset \
    rw \
    quiet \
    loglevel=3 \
    console=tty1 \
    nwipe_options="--autonuke --nogui --method=zero --verify=off --nousb" \
    lftp="open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*"
  initrd /initrd.img
}
EOF

# BIOS — pxelinux
cat > /var/tftpboot/pxelinux.cfg/default << EOF
DEFAULT shredos
LABEL shredos
  KERNEL vmlinuz
  APPEND \
    initrd=initrd.img \
    boot=live \
    netboot=nfs \
    nfsroot=${SERVER_IP}:/var/nfsroot \
    ip=dhcp \
    nomodeset \
    rw \
    quiet \
    loglevel=3 \
    console=tty1 \
    nwipe_options="--autonuke --nogui --method=zero --verify=off --nousb" \
    lftp="open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*"
EOF

# ─────────────────────────────────────────────────────────────
# 6. dnsmasq — DHCP + TFTP
# ─────────────────────────────────────────────────────────────
echo "=== Configuration dnsmasq ==="
cat > /etc/dnsmasq.conf << EOF
port=0
interface=${INTERFACE}
bind-interfaces
dhcp-range=${SUBNET}.100,${SUBNET}.200,12h
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

# ─────────────────────────────────────────────────────────────
# 7. NFS — tmpfs + squashfs
# ─────────────────────────────────────────────────────────────
echo "=== Configuration NFS ==="
modprobe nfsd 2>/dev/null || true
modprobe nfs  2>/dev/null || true

# Tmpfs pour NFS (squashfs déjà copié dans /var/nfsroot/live/)
mount -t tmpfs -o size=4G,mode=755 tmpfs /var/nfsroot 2>/dev/null || true
mkdir -p /var/nfsroot/live
cp "$SQUASHFS" /var/nfsroot/live/filesystem.squashfs

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

echo ""
echo "============================================================"
echo " Serveur PXE ShredOS prêt !"
echo " IP serveur  : $SERVER_IP"
echo " FTP reports : ftp://$FTP_IP (user: $FTP_USER)"
echo " Les clients vont démarrer, effacer leurs disques"
echo " et envoyer leurs rapports PDF automatiquement."
echo "============================================================"

exec dnsmasq -d
