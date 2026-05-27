#!/bin/bash
# =============================================================
# entrypoint.sh — Serveur FTP vsftpd
# Reçoit les rapports PDF + logs des clients ShredOS
# =============================================================
set -euo pipefail

FTP_USER="${FTP_USER:-shredreports}"
FTP_PASS="${FTP_PASS:-shredos2025}"
FTP_ROOT="/home/${FTP_USER}/ftpdata"

echo "============================================================"
echo " Serveur FTP — réception des rapports ShredOS"
echo " Utilisateur : $FTP_USER"
echo " Dossier     : $FTP_ROOT"
echo "============================================================"

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

echo "=== Démarrage vsftpd ==="
echo "Les rapports PDF seront déposés dans : $FTP_ROOT"

exec /usr/sbin/vsftpd /etc/vsftpd.conf
