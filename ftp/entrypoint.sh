#!/bin/bash
# =============================================================
# entrypoint.sh — Serveur FTP vsftpd
# Reçoit les rapports PDF + logs des clients ShredOS
# =============================================================
set -euo pipefail

FTP_USER="${FTP_USER:-shredreports}"
FTP_PASS="${FTP_PASS:-shredos2025}"
FTP_ROOT="/home/${FTP_USER}/ftpdata"
LEASE_FILE="${LEASE_FILE:-${FTP_ROOT}/dnsmasq.leases}"
REPORT_RENAME_SCAN_INTERVAL="${REPORT_RENAME_SCAN_INTERVAL:-10}"

echo "============================================================"
echo " Serveur FTP — réception des rapports ShredOS"
echo " Utilisateur : $FTP_USER"
echo " Dossier     : $FTP_ROOT"
echo "============================================================"

normalize_mac() {
    local input="${1:-}"
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^0-9a-f]+/_/g; s/^_+//; s/_+$//'
}

extract_disk_id() {
    local input="${1:-}"
    local without_ext
    without_ext="${input%.*}"
    without_ext=$(echo "$without_ext" | sed -E 's/^nwipe_log_//; s/^nwipe_//; s/^report_//')
    without_ext=$(echo "$without_ext" | sed -E 's/[^A-Za-z0-9]+/_/g; s/^_+//; s/_+$//')
    if [ -z "$without_ext" ]; then
        without_ext="unknownDisk"
    fi
    echo "$without_ext"
}

extract_ip_from_xferlog() {
    local filename="$1"
    [ -f /var/log/xferlog ] || return 1

    grep "${filename}" /var/log/xferlog | tail -n 1 | awk '{print $7}'
}

mac_from_ip() {
    local ip="$1"

    [ -n "$ip" ] || return 1
    [ -f "$LEASE_FILE" ] || return 1

    awk -v target_ip="$ip" '$3 == target_ip {print $2}' "$LEASE_FILE" | tail -n 1
}

build_unique_name() {
    local base="$1"
    local ext="$2"
    local idx=1
    local candidate="${base}.${ext}"

    while [ -e "${FTP_ROOT}/${candidate}" ]; do
        idx=$((idx + 1))
        candidate="${base}_${idx}.${ext}"
    done

    echo "$candidate"
}

rename_reports_loop() {
    while true; do
        find "$FTP_ROOT" -maxdepth 1 -type f \( -name "*.pdf" -o -name "*.log" -o -name "*.txt" \) | while read -r src; do
            local file_name
            local ext
            local ip
            local mac
            local mac_norm
            local disk_id
            local stamp
            local target_base
            local target_name
            local now_epoch
            local mtime_epoch

            file_name=$(basename "$src")

            # Ignore lease file and files already normalized.
            if [ "$file_name" = "$(basename "$LEASE_FILE")" ]; then
                continue
            fi
            if echo "$file_name" | grep -Eq '^[0-9a-f]{2}(_[0-9a-f]{2}){5}_.+_[0-9]{8}T[0-9]{6}Z(_[0-9]+)?\.(pdf|log|txt)$'; then
                continue
            fi

            now_epoch=$(date +%s)
            mtime_epoch=$(stat -c %Y "$src" 2>/dev/null || echo "$now_epoch")
            if [ $((now_epoch - mtime_epoch)) -lt 5 ]; then
                continue
            fi

            ext="${file_name##*.}"
            ip=$(extract_ip_from_xferlog "$file_name" || true)
            mac=$(mac_from_ip "$ip" || true)
            mac_norm=$(normalize_mac "$mac")
            if [ -z "$mac_norm" ]; then
                mac_norm="unknown_mac"
            fi

            disk_id=$(extract_disk_id "$file_name")
            stamp=$(date -u +%Y%m%dT%H%M%SZ)
            target_base="${mac_norm}_${disk_id}_${stamp}"
            target_name=$(build_unique_name "$target_base" "$ext")

            mv "$src" "${FTP_ROOT}/${target_name}"
            echo "[ftp] renommage: ${file_name} -> ${target_name}"
        done

        sleep "$REPORT_RENAME_SCAN_INTERVAL"
    done
}

# ─────────────────────────────────────────────────────────────
# Création de l'utilisateur FTP dédié (chrooted)
# ─────────────────────────────────────────────────────────────
if ! id "$FTP_USER" &>/dev/null; then
    useradd -m -s /bin/false "$FTP_USER"
fi
echo "${FTP_USER}:${FTP_PASS}" | chpasswd

# Le home doit appartenir à root pour le chroot vsftpd
chown root:root "/home/${FTP_USER}"
chmod 755 "/home/${FTP_USER}"

# Le dossier de dépôt appartient à l'utilisateur
mkdir -p "$FTP_ROOT"
chown "${FTP_USER}:${FTP_USER}" "$FTP_ROOT"
chmod 755 "$FTP_ROOT"

# ─────────────────────────────────────────────────────────────
# Configuration vsftpd
# ─────────────────────────────────────────────────────────────
cat > /etc/vsftpd.conf << EOF
# Mode standalone
listen=YES
listen_ipv6=NO
background=NO

# Pas d'accès anonyme
anonymous_enable=NO
local_enable=YES
write_enable=YES

# Chroot — les clients restent dans leur home
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=${FTP_ROOT}

# Permissions des fichiers uploadés
local_umask=022
file_open_mode=0644

# Log des transferts
xferlog_enable=YES
xferlog_std_format=YES
log_ftp_protocol=NO

# Mode passif (requis dans la plupart des réseaux)
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# Sécurité
ssl_enable=NO
tcp_wrappers=NO

# Message de bienvenue
ftpd_banner=ShredOS Report Server
EOF

# ─────────────────────────────────────────────────────────────
# Création du fichier user_list pour autoriser uniquement
# notre utilisateur dédié
# ─────────────────────────────────────────────────────────────
echo "$FTP_USER" > /etc/vsftpd.user_list
echo "userlist_enable=YES"      >> /etc/vsftpd.conf
echo "userlist_deny=NO"         >> /etc/vsftpd.conf
echo "userlist_file=/etc/vsftpd.user_list" >> /etc/vsftpd.conf

echo "=== Démarrage du post-traitement des rapports ==="
rename_reports_loop &

echo "=== Démarrage vsftpd ==="
echo "Les rapports PDF seront déposés dans : $FTP_ROOT"

exec /usr/sbin/vsftpd /etc/vsftpd.conf
