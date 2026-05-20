FROM debian:sid-slim

ENV DEBIAN_FRONTEND=noninteractive

# 1. Installation des outils d'infrastructure requis sur le parent
RUN apt-get update && apt-get install -y \
    dnsmasq \
    nfs-kernel-server \
    syslinux-common \
    pxelinux \
    live-build \
    squashfs-tools \
    iproute2 \
    iptables \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# 2. Préparation des répertoires PXE et NFS
RUN mkdir -p /var/tftpboot /var/nfsroot /opt/pxe-wipe/rapports

# 3. Téléchargement et extraction des composants Live-Boot natifs pour récupérer Vmlinuz et Initrd
RUN apt-get update && apt-get install -y --download-only live-boot-initramfs-tools linux-image-amd64
RUN mkdir -p /tmp/live && \
    cd /tmp/live && \
    apt-get download linux-image-amd64 live-boot-initramfs-tools && \
    find . -name "*.deb" -exec dpkg-devdeb -x {} . \; || true

# Copie du noyau Linux natif pour le PXE
RUN cp /tmp/live/boot/vmlinuz* /var/tftpboot/vmlinuz && \
    cp /tmp/live/boot/initrd.img* /var/tftpboot/initrd.img

# 4. Copie des fichiers chargeurs d'amorçage PXE standard de Syslinux
RUN cp /usr/lib/PXELINUX/pxelinux.0 /var/tftpboot/ && \
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/tftpboot/

# 5. Création et personnalisation à la volée du mini-système d'exploitation (SquashFS) pour le PC fils
RUN mkdir -p /tmp/sysroot
WORKDIR /tmp/sysroot

# Installation de la distribution minimale brute pour le client fils
RUN apt-get update && apt-get install -y debootstrap && \
    debootstrap --variant=minbase trixie /tmp/sysroot http://deb.debian.org/debian/

# Installation des paquets requis pour l'audit et l'effacement dans le système du fils
RUN chroot /tmp/sysroot apt-get update && \
    chroot /tmp/sysroot apt-get install -y \
    live-boot \
    nwipe \
    smartmontools \
    hdparm \
    dmidecode \
    openssh-client \
    pciutils \
    systemd \
    && chroot /tmp/sysroot rm -rf /var/lib/apt/lists/*

# Injection de notre script d'effacement automatique au login de l'utilisateur Root du fils
COPY client_wipe.sh /tmp/sysroot/root/client_wipe.sh
RUN chmod +x /tmp/sysroot/root/client_wipe.sh && \
    echo "/root/client_wipe.sh" >> /tmp/sysroot/root/.bashrc

# Configuration du Login automatique sans mot de passe sur la console tty1 du fils
RUN mkdir -p /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/ && \
    echo "[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM" \
    > /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/override.conf

# 6. Compilation du système de fichiers SquashFS final
RUN mkdir -p /var/nfsroot/live && \
    mksquashfs /tmp/sysroot /var/nfsroot/live/filesystem.squashfs -comp xz && \
    rm -rf /tmp/sysroot

# 7. Configuration finale du serveur NFS dans le conteneur
RUN echo "/var/nfsroot *(ro,sync,no_subtree_check,no_root_squash)" >> /etc/exports

# Scripts de gestion d'entrée du conteneur Docker
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /
ENTRYPOINT ["/entrypoint.sh"]
