# syntax=docker/dockerfile:1.4

# =============================================================================
# STAGE 1 — sysroot : Construction du système live du PC fils
# Bonne pratique : multi-stage build au lieu de debootstrap dans le build.
# On part directement de l'image Debian officielle et on installe les paquets
# nécessaires au PC fils dedans — c'est exactement ce que faisait debootstrap,
# sans les problèmes réseau et de signature GPG.
# =============================================================================
FROM debian:bookworm-slim AS sysroot

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        systemd \
        systemd-sysv \
        dbus \
        live-boot \
        linux-image-amd64 \
        nwipe \
        smartmontools \
        hdparm \
        dmidecode \
        openssh-client \
        pciutils \
        python3 \
        python3-reportlab \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# STAGE 2 — server : Serveur PXE
# =============================================================================
FROM debian:bookworm-slim AS server

ENV DEBIAN_FRONTEND=noninteractive

# --- COUCHE 1 : Dépendances du serveur ---
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        dnsmasq \
        nfs-kernel-server \
        rpcbind \
        syslinux-common \
        pxelinux \
        grub-efi-amd64-signed \
        shim-signed \
        squashfs-tools \
        iproute2 \
        openssh-server \
        openssh-client \
        python3 \
        python3-reportlab \
    && rm -rf /var/lib/apt/lists/*

# --- COUCHE 2 : Configuration SSH serveur ---
RUN mkdir -p /var/run/sshd /root/.ssh \
    && rm -f /etc/ssh/ssh_host_* \
    && ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 \
    && ssh-keygen -t rsa     -b 4096 -N "" -f /etc/ssh/ssh_host_rsa_key \
    && ssh-keygen -t ecdsa   -N "" -f /etc/ssh/ssh_host_ecdsa_key \
    && ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key \
    && cp /root/.ssh/id_ed25519.pub /root/.ssh/authorized_keys \
    && chmod 700 /root/.ssh \
    && chmod 600 /root/.ssh/authorized_keys \
    && printf 'PermitRootLogin yes\nPasswordAuthentication no\nStrictModes no\n' \
        >> /etc/ssh/sshd_config

# --- COUCHE 3 : Récupération du sysroot depuis le stage 1 ---
# CORRECTION : tar intermédiaire pour exclure /proc /sys /dev /run
# (COPY --from ne supporte pas --exclude ; ces pseudo-fs vides causent le kernel panic)
RUN mkdir -p /tmp/sysroot
COPY --from=sysroot / /tmp/sysroot/
RUN rm -rf /tmp/sysroot/proc /tmp/sysroot/sys /tmp/sysroot/dev /tmp/sysroot/run \
    && mkdir -p /tmp/sysroot/proc /tmp/sysroot/sys /tmp/sysroot/run \
    && mkdir -p /tmp/sysroot/dev \
    # Device nodes minimaux requis par init/systemd au boot live
    && mknod -m 622 /tmp/sysroot/dev/console  c 5 1 \
    && mknod -m 666 /tmp/sysroot/dev/null      c 1 3 \
    && mknod -m 666 /tmp/sysroot/dev/zero      c 1 5 \
    && mknod -m 666 /tmp/sysroot/dev/random    c 1 8 \
    && mknod -m 666 /tmp/sysroot/dev/urandom   c 1 9 \
    && mknod -m 660 /tmp/sysroot/dev/tty0      c 4 0 \
    && mknod -m 660 /tmp/sysroot/dev/tty1      c 4 1 \
    && mkdir -p /tmp/sysroot/dev/pts /tmp/sysroot/dev/shm

# --- COUCHE 4 : Préparation des fichiers TFTP ---
RUN mkdir -p /var/tftpboot/grub /var/tftpboot/pxelinux.cfg \
             /var/nfsroot/live /opt/pxe-wipe/rapports \
    && cp /usr/lib/PXELINUX/pxelinux.0               /var/tftpboot/ \
    && cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/tftpboot/ \
    && find /usr/lib/shim -name "shimx64.efi.signed"    | head -1 \
        | xargs -I{} cp {} /var/tftpboot/bootx64.efi \
    && find /usr/lib/grub -name "grubnetx64.efi.signed" | head -1 \
        | xargs -I{} cp {} /var/tftpboot/grubx64.efi \
    && find /tmp/sysroot/boot -maxdepth 1 -name "vmlinuz-*"    | sort | tail -1 \
        | xargs -I{} cp {} /var/tftpboot/vmlinuz \
    && find /tmp/sysroot/boot -maxdepth 1 -name "initrd.img-*" | sort | tail -1 \
        | xargs -I{} cp {} /var/tftpboot/initrd.img

# --- COUCHE 5 : Configuration du système live (PC fils) ---
COPY client_wipe.sh /tmp/sysroot/root/client_wipe.sh

RUN chmod +x /tmp/sysroot/root/client_wipe.sh \
    && echo "exec /root/client_wipe.sh" > /tmp/sysroot/root/.profile \
    && mkdir -p /tmp/sysroot/root/.ssh \
    && cp /root/.ssh/id_ed25519 /tmp/sysroot/root/.ssh/id_ed25519 \
    && chmod 600 /tmp/sysroot/root/.ssh/id_ed25519 \
    && printf 'StrictHostKeyChecking no\nUserKnownHostsFile /dev/null\n' \
        > /tmp/sysroot/root/.ssh/config \
    && mkdir -p /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/ \
    && printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I $TERM\n' \
        > /tmp/sysroot/etc/systemd/system/getty@tty1.service.d/override.conf

# --- COUCHE 6 : Compression SquashFS ---
RUN mksquashfs /tmp/sysroot /var/nfsroot/live/filesystem.squashfs \
        -comp xz -Xbcj x86 -b 1M -no-progress -noappend \
        -e /tmp/sysroot/proc \
        -e /tmp/sysroot/sys \
        -e /tmp/sysroot/dev \
    && rm -rf /tmp/sysroot

# --- COUCHE 7 : Entrypoint ---
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 67/udp 69/udp 111 2049
ENTRYPOINT ["/entrypoint.sh"]