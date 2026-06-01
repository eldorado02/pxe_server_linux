#!/bin/bash
# =============================================================
# entrypoint.sh — Serveur PXE ShredOS
# =============================================================
set -euo pipefail

log() {
    echo "[pxe] $*"
}

fatal() {
    echo "[pxe][ERREUR] $*" >&2
    exit 1
}

find_first() {
    local path="$1"
    local pattern="$2"
    find "$path" -maxdepth 1 -type f -name "$pattern" | sort | head -n 1
}

extract_from_iso() {
    local iso_path="$1"
    local extract_dir

    extract_dir=$(mktemp -d)
    7z x -y "$iso_path" "-o$extract_dir" >/dev/null

    local kernel_src=""
    local initrd_src=""
    local squashfs_src=""

    kernel_src=$(find "$extract_dir" -type f \( -name "vmlinuz" -o -name "vmlinuz*" -o -name "shredos" -o -name "bzImage" \) | head -n 1)
    initrd_src=$(find "$extract_dir" -type f \( -name "initrd*" -o -name "initramfs*" \) | head -n 1)
    squashfs_src=$(find "$extract_dir" -type f \( -name "filesystem.squashfs" -o -name "*.squashfs" -o -name "*.sfs" \) | head -n 1)

    [ -n "$kernel_src" ] || fatal "Kernel introuvable dans ISO: $iso_path"

    cp "$kernel_src" "$VMLINUX"
    if [ -n "$initrd_src" ]; then
        cp "$initrd_src" "$INITRD"
    fi
    if [ -n "$squashfs_src" ]; then
        cp "$squashfs_src" "$SQUASHFS_CACHE"
    fi

    rm -rf "$extract_dir"
}

extract_from_img() {
    local img_path="$1"
    local loop_dev
    local mount_point
    local part

    loop_dev=$(losetup -fP --show "$img_path")
    mount_point=$(mktemp -d)

    part="${loop_dev}p1"
    if [ ! -b "$part" ]; then
        part="$loop_dev"
    fi

    mount -o ro "$part" "$mount_point"

    local kernel_src=""
    local initrd_src=""
    local squashfs_src=""

    kernel_src=$(find "$mount_point" -type f \( -name "shredos" -o -name "vmlinuz*" -o -name "bzImage" \) | head -n 1)
    initrd_src=$(find "$mount_point" -type f \( -name "initrd*" -o -name "initramfs*" \) | head -n 1)
    squashfs_src=$(find "$mount_point" -type f \( -name "filesystem.squashfs" -o -name "*.squashfs" -o -name "*.sfs" \) | head -n 1)

    [ -n "$kernel_src" ] || fatal "Kernel introuvable dans IMG: $img_path"
    [ -n "$initrd_src" ] || fatal "Initrd introuvable dans IMG: $img_path"
    [ -n "$squashfs_src" ] || fatal "Squashfs introuvable dans IMG: $img_path"

    cp "$kernel_src" "$VMLINUX"
    cp "$initrd_src" "$INITRD"
    cp "$squashfs_src" "$SQUASHFS_CACHE"

    umount "$mount_point"
    rmdir "$mount_point"
    losetup -d "$loop_dev"
}

download_remote_img() {
    local release_url
    local img_url

    if [ "$SHREDOS_VERSION" = "latest" ]; then
        release_url="https://api.github.com/repos/PartialVolume/shredos.x86_64/releases/latest"
    else
        release_url="https://api.github.com/repos/PartialVolume/shredos.x86_64/releases/tags/$SHREDOS_VERSION"
    fi

    log "Téléchargement ShredOS depuis GitHub ($SHREDOS_VERSION)"

    img_url=$(curl -fsSL "$release_url" \
        | jq -r '.assets[] | select(.name | test("x86-64.*\\.img\\.tar\\.gz$")) | .browser_download_url' \
        | head -n 1)

    if [ -z "$img_url" ]; then
        img_url=$(curl -fsSL "$release_url" \
            | jq -r '.assets[] | select(.name | endswith(".img.tar.gz")) | .browser_download_url' \
            | grep -v i686 | head -n 1)
    fi

    [ -n "$img_url" ] || fatal "Aucune image .img.tar.gz trouvée dans la release distante"

    wget -q --show-progress -O "$SHREDOS_WORK_DIR/shredos.img.tar.gz" "$img_url"
    echo "$SHREDOS_WORK_DIR/shredos.img.tar.gz"
}

resolve_local_artifact() {
    if [ -f "$SHREDOS_LOCAL_PATH" ]; then
        echo "$SHREDOS_LOCAL_PATH"
        return
    fi

    [ -d "$SHREDOS_LOCAL_PATH" ] || return

    local candidate=""
    candidate=$(find_first "$SHREDOS_LOCAL_PATH" "*.img")
    if [ -n "$candidate" ]; then
        echo "$candidate"
        return
    fi

    candidate=$(find_first "$SHREDOS_LOCAL_PATH" "*.img.tar.gz")
    if [ -n "$candidate" ]; then
        echo "$candidate"
        return
    fi

    candidate=$(find_first "$SHREDOS_LOCAL_PATH" "*.iso")
    if [ -n "$candidate" ]; then
        echo "$candidate"
        return
    fi
}

prepare_artifact() {
    local artifact="$1"
    local local_copy
    local ext

    local_copy="$SHREDOS_WORK_DIR/$(basename "$artifact")"
    cp "$artifact" "$local_copy"
    ext="${local_copy##*.}"

    if [[ "$local_copy" == *.img.tar.gz ]]; then
        gunzip -f "$local_copy"
        tar -xf "${local_copy%.gz}" -C "$SHREDOS_WORK_DIR"
        rm -f "${local_copy%.gz}"
        find "$SHREDOS_WORK_DIR" -maxdepth 1 -type f -name "*.img" | head -n 1
        return
    fi

    if [[ "$local_copy" == *.img.tar ]]; then
        tar -xf "$local_copy" -C "$SHREDOS_WORK_DIR"
        rm -f "$local_copy"
        find "$SHREDOS_WORK_DIR" -maxdepth 1 -type f -name "*.img" | head -n 1
        return
    fi

    echo "$local_copy"
}

INTERFACE=$(ip route show default 2>/dev/null | awk 'NR==1 {print $5}')
SERVER_IP=$(ip -o -4 addr show dev "$INTERFACE" 2>/dev/null | awk 'NR==1 {split($4,a,"/"); print a[1]}')

[ -n "${INTERFACE:-}" ] || fatal "Interface réseau non détectée"
[ -n "${SERVER_IP:-}" ] || fatal "Adresse IP serveur non détectée"

SUBNET=$(echo "$SERVER_IP" | cut -d'.' -f1-3)

FTP_USER="${FTP_USER:-shredreports}"
FTP_PASS="${FTP_PASS:-shredos2025}"
FTP_IP="${FTP_IP:-$SERVER_IP}"

SHREDOS_SOURCE="${SHREDOS_SOURCE:-local}"
SHREDOS_LOCAL_PATH="${SHREDOS_LOCAL_PATH:-/opt/local-shredos}"
SHREDOS_VERSION="${SHREDOS_VERSION:-latest}"
SHREDOS_WORK_DIR="/opt/shredos"

NWIPE_METHOD="${NWIPE_METHOD:-zero}"
NWIPE_VERIFY="${NWIPE_VERIFY:-off}"
NWIPE_EXTRA_OPTIONS="${NWIPE_EXTRA_OPTIONS:-}"

KERNEL_ONLY_MODE=0

VMLINUX="/var/tftpboot/vmlinuz"
INITRD="/var/tftpboot/initrd.img"
SQUASHFS_CACHE="$SHREDOS_WORK_DIR/filesystem.squashfs"
SQUASHFS_NFS="/var/nfsroot/live/filesystem.squashfs"
LEASE_FILE="/opt/pxe-wipe/rapports/dnsmasq.leases"

mkdir -p "$SHREDOS_WORK_DIR" /var/tftpboot/grub /var/tftpboot/pxelinux.cfg /var/nfsroot/live /opt/pxe-wipe/rapports

log "============================================================"
log " Serveur PXE ShredOS"
log " Interface : $INTERFACE"
log " IP        : $SERVER_IP"
log " Sous-réseau : $SUBNET.0/24"
log " Source image : $SHREDOS_SOURCE"
log "============================================================"

ARTIFACT=""
if [ "$SHREDOS_SOURCE" = "local" ] || [ "$SHREDOS_SOURCE" = "auto" ]; then
    ARTIFACT=$(resolve_local_artifact || true)
fi

if [ -z "$ARTIFACT" ] && { [ "$SHREDOS_SOURCE" = "remote" ] || [ "$SHREDOS_SOURCE" = "auto" ]; }; then
    ARTIFACT=$(download_remote_img)
fi

[ -n "$ARTIFACT" ] || fatal "Aucune image ShredOS trouvée (local/remote)"
log "Artifact sélectionné : $ARTIFACT"

PREPARED_ARTIFACT=$(prepare_artifact "$ARTIFACT")
[ -f "$PREPARED_ARTIFACT" ] || fatal "Artifact préparé introuvable: $PREPARED_ARTIFACT"

log "Extraction des fichiers de boot"
case "$PREPARED_ARTIFACT" in
    *.iso)
        extract_from_iso "$PREPARED_ARTIFACT"
        ;;
    *.img)
        extract_from_img "$PREPARED_ARTIFACT"
        ;;
    *)
        fatal "Format d'image non supporté: $PREPARED_ARTIFACT"
        ;;
esac

for required in "$VMLINUX" "$INITRD" "$SQUASHFS_CACHE"; do
    if [ "$required" = "$VMLINUX" ]; then
        [ -f "$required" ] || fatal "Fichier requis absent: $required"
        continue
    fi

    if [ ! -f "$required" ]; then
        KERNEL_ONLY_MODE=1
    fi
done

if [ "$KERNEL_ONLY_MODE" -eq 1 ]; then
    log "Mode kernel-only détecté (sans initrd/squashfs)."
fi

NWIPE_OPTIONS="--autonuke --nogui --autopoweroff --method=$NWIPE_METHOD --verify=$NWIPE_VERIFY --nousb --PDFreportpath=/"
if [ -n "$NWIPE_EXTRA_OPTIONS" ]; then
    NWIPE_OPTIONS="$NWIPE_OPTIONS $NWIPE_EXTRA_OPTIONS"
fi

log "Options nwipe : $NWIPE_OPTIONS"

if [ "$KERNEL_ONLY_MODE" -eq 1 ]; then
        GRUB_KERNEL_ARGS="console=tty3 loglevel=3 nomodeset nwipe_options=\"${NWIPE_OPTIONS}\" lftp=\"open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*\""
        PXE_KERNEL_ARGS="console=tty3 loglevel=3 nomodeset nwipe_options=\"${NWIPE_OPTIONS}\" lftp=\"open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*\""
else
        GRUB_KERNEL_ARGS="boot=live netboot=nfs nfsroot=${SERVER_IP}:/var/nfsroot ip=dhcp nomodeset rw quiet loglevel=3 console=tty1 nwipe_options=\"${NWIPE_OPTIONS}\" lftp=\"open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*\""
        PXE_KERNEL_ARGS="initrd=initrd.img boot=live netboot=nfs nfsroot=${SERVER_IP}:/var/nfsroot ip=dhcp nomodeset rw quiet loglevel=3 console=tty1 nwipe_options=\"${NWIPE_OPTIONS}\" lftp=\"open ${FTP_IP}; user ${FTP_USER} ${FTP_PASS}; cd /; mput *.pdf; mput nwipe_log*\""
fi

cat > /var/tftpboot/grub/grub.cfg << EOF
rmmod tpm
set timeout=5
set default=0

menuentry "ShredOS - Autonuke PXE" {
    linux /vmlinuz ${GRUB_KERNEL_ARGS}
EOF

if [ "$KERNEL_ONLY_MODE" -eq 0 ]; then
cat >> /var/tftpboot/grub/grub.cfg << EOF
    initrd /initrd.img
EOF
fi

cat >> /var/tftpboot/grub/grub.cfg << EOF
}
EOF

cat > /var/tftpboot/pxelinux.cfg/default << EOF
DEFAULT shredos
LABEL shredos
  KERNEL vmlinuz
    APPEND ${PXE_KERNEL_ARGS}
EOF

cat > /etc/dnsmasq.conf << EOF
port=0
interface=${INTERFACE}
bind-interfaces
dhcp-authoritative
dhcp-range=${SUBNET}.100,${SUBNET}.200,12h
dhcp-leasefile=${LEASE_FILE}
dhcp-boot=tag:!efi-x86_64,pxelinux.0
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:efi-x86_64,option:client-arch,11
dhcp-boot=tag:efi-x86_64,bootx64.efi
dhcp-option=tag:efi-x86_64,210,/
enable-tftp
tftp-root=/var/tftpboot
log-dhcp
EOF

if [ "$KERNEL_ONLY_MODE" -eq 0 ]; then
    modprobe nfsd 2>/dev/null || true
    modprobe nfs 2>/dev/null || true

    if ! mountpoint -q /var/nfsroot; then
        mount -t tmpfs -o size=4G,mode=755 tmpfs /var/nfsroot
    fi
    mkdir -p /var/nfsroot/live
    cp "$SQUASHFS_CACHE" "$SQUASHFS_NFS"

    cat > /etc/exports << EOF
/var/nfsroot *(ro,fsid=0,sync,no_subtree_check,no_root_squash)
EOF

    mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null || true
    rpcbind -w
    exportfs -ra
    rpc.nfsd 8
    rpc.mountd --no-udp --port 20048
else
    log "NFS non requis en mode kernel-only."
fi

log "Serveur PXE prêt: $SERVER_IP"
log "FTP reports: ftp://$FTP_IP (user: $FTP_USER)"

exec dnsmasq -d
