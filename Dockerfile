FROM debian:sid-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

# 1. Installation des outils d'infrastructure requis sur le serveur parent
RUN apt-get update && apt-get install -y \
    dnsmasq \
    nfs-kernel-server \
    syslinux-common \
    pxelinux \
    squashfs-tools \
    iproute2 \
    openssh-server \
    openssh-client \
    binutils \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 2. Configuration SSH du serveur parent pour accepter les rapports sans mot de passe
RUN mkdir -p /var/run/sshd /root/.ssh && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config && \
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa && \
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# 3. Préparation de l'arborescence PXE
RUN mkdir -p /var/tftpboot /var/nfsroot /opt/pxe-wipe/rapports

# 4. Extraction ROBUSTE du Kernel (vmlinuz) et de l'Initrd depuis les dépôts officiels
RUN mkdir -p /tmp/extract && cd /tmp && \
    apt-get update && \
    apt-get download linux-image-amd64 live-boot-initramfs-tools && \
    for deb in *.deb; do dpkg-deb -x "$deb" /tmp/extract; done && \
    find /tmp/extract/ -name "vmlinuz-*" -exec cp {} /var/tftpboot/vmlinuz \; && \
    find /tmp/extract/ -name "initrd.img-*" -exec cp {} /var/tftpboot/initrd.img \; && \
    rm -rf /tmp/extract /tmp/*.deb

# 5. Copie des chargeurs d'amorçage Syslinux standards
RUN cp /usr/lib/PXELINUX/pxelinux.0 /var/tftpboot/ && \
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/tftpboot/

# 6. Création du mini-système Linux (SquashFS) destiné au PC fils
RUN mkdir -p /tmp/sysroot

RUN apt-get update && apt-get install -y debootstrap && \
    debootstrap --variant=minbase trixie /tmp/sysroot http://deb.debian.org/debian/

# Installation des dépendances d'effacement au sein du système client
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

# Injection du script d'effacement au profil Root du système live
COPY client_wipe.sh /tmp/sysroot/root/client_wipe.sh
RUN chmod +x /tmp/sysroot/root/client_wipe.sh && \
    echo "/root/client_wipe.sh" >> /tmp/sysroot/root/.bashrc

# Injection de la clé privée pour que le fils puisse téléverser vers le parent sans mot de passe
# CORRECTION : cp direct car la clé est déjà dans ce même stage (pas de COPY --from=builder)
RUN mkdir -p /tmp/sysroot/root/.ssh/ && \
    cp /root/.ssh/id_rsa /tmp/sysroot/root/.ssh/id_rsa && \
    chmod 600 /tmp/sysroot/root/.ssh/id_rsa

# Configuration de l'autologin strict sur le TTY de la machine cible
# CORRECTION : printf utilisé pour les vrais sauts de ligne, et %% pour échapper le % dans Dockerfile
RUN mkdir -p /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/ && \
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I $TERM\n' \
    > /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/override.conf

# 7. Création de l'image SquashFS finale
RUN mkdir -p /var/nfsroot/live && \
    mksquashfs /tmp/sysroot /var/nfsroot/live/filesystem.squashfs -comp xz && \
    rm -rf /tmp/sysroot

# 8. Exposition NFS
RUN echo "/var/nfsroot *(ro,sync,no_subtree_check,no_root_squash)" >> /etc/exports

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]