# syntax=docker/dockerfile:1.4
# =============================================================================
# STAGE 0 — nwipe-builder : Compilation/récupération de nwipe + python3
# =============================================================================
FROM debian:trixie-slim AS nwipe-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nwipe \
        python3 \
        python3-reportlab \
    && rm -rf /var/lib/apt/lists/*
# Vérification des dépendances nwipe (visible dans les logs du build)
RUN echo "=== Dépendances nwipe ===" && ldd /usr/sbin/nwipe

# =============================================================================
# STAGE 1 — iso-modifier : Désossage et dégraissage RADICAL de l'ISO
# =============================================================================
FROM debian:trixie-slim AS iso-modifier
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=3 update && \
    apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends \
        p7zip-full \
        squashfs-tools \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*
# Génération des clés SSH
RUN mkdir -p /root/.ssh \
    && ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 \
    && cp /root/.ssh/id_ed25519.pub /root/.ssh/authorized_keys
# Importation de ton ISO GNOME locale
COPY debian-live-13.5.0-amd64-gnome.iso /tmp/debian-live.iso
# Extraction
RUN mkdir -p /tmp/iso-ext \
    && 7z x /tmp/debian-live.iso live/ -o/tmp/iso-ext
RUN osquashfs="`find /tmp/iso-ext/live/ -name 'filesystem.squashfs'`" \
    && unsquashfs -d /tmp/sysroot "$osquashfs"
# ─────────────────────────────────────────────────────────────────────────────
# Nettoyage graphique
# ─────────────────────────────────────────────────────────────────────────────
RUN rm -f /tmp/sysroot/etc/systemd/system/display-manager.service \
    && rm -f /tmp/sysroot/etc/systemd/system/graphical.target \
    && rm -rf /tmp/sysroot/usr/share/icons/* \
    && rm -rf /tmp/sysroot/usr/share/fonts/* \
    && rm -rf /tmp/sysroot/usr/share/doc/* \
    && rm -rf /tmp/sysroot/usr/share/backgrounds/* \
    && rm -rf /tmp/sysroot/usr/share/sounds/* \
    && rm -rf /tmp/sysroot/usr/lib/firefox-esr \
    && rm -rf /tmp/sysroot/usr/lib/thunderbird \
    && rm -rf /tmp/sysroot/usr/bin/gnome-* \
    && rm -rf /tmp/sysroot/usr/bin/Xorg \
    && rm -rf /tmp/sysroot/var/lib/apt/lists/* \
    && rm -rf /tmp/sysroot/usr/lib/xorg \
    && rm -rf /tmp/sysroot/usr/share/X11 \
    && rm -f /tmp/sysroot/etc/systemd/system/multi-user.target.wants/display-manager.service
# Forcer le target systemd en mode texte pur
RUN ln -sf /lib/systemd/system/multi-user.target \
        /tmp/sysroot/etc/systemd/system/default.target
# Désactiver le module audio SOF
RUN mkdir -p /tmp/sysroot/etc/modprobe.d \
    && printf 'blacklist snd_sof_pci\nblacklist snd_sof_pci_intel_tgl\nblacklist snd_hda_intel\nblacklist snd_hda_codec_hdmi\n' \
        > /tmp/sysroot/etc/modprobe.d/blacklist-audio.conf
# Injection de nwipe + toutes ses dépendances depuis le stage builder
COPY --from=nwipe-builder /usr/sbin/nwipe                                    /tmp/sysroot/usr/sbin/nwipe
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libncurses*              /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libtinfo*                /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libpthread*              /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libconfig*               /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libparted*               /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libdmmp*                 /tmp/sysroot/usr/lib/x86_64-linux-gnu/
RUN chmod +x /tmp/sysroot/usr/sbin/nwipe
# ─────────────────────────────────────────────────────────────────────────────
# Injection python3 + reportlab dans le sysroot client
# (nécessaire pour générer le PDF depuis client_wipe.sh)
# ─────────────────────────────────────────────────────────────────────────────
COPY --from=nwipe-builder /usr/bin/python3                                    /tmp/sysroot/usr/bin/python3
COPY --from=nwipe-builder /usr/lib/python3                                    /tmp/sysroot/usr/lib/python3
COPY --from=nwipe-builder /usr/lib/python3.13                                 /tmp/sysroot/usr/lib/python3.13
COPY --from=nwipe-builder /usr/lib/x86_64-linux-gnu/libpython3*               /tmp/sysroot/usr/lib/x86_64-linux-gnu/
COPY --from=nwipe-builder /usr/lib/python3/dist-packages/reportlab            /tmp/sysroot/usr/lib/python3/dist-packages/reportlab
# Injection script wipe + SSH
COPY client_wipe.sh /tmp/sysroot/root/client_wipe.sh
RUN mkdir -p /tmp/sysroot/root/.ssh \
    && cp /root/.ssh/id_ed25519 /tmp/sysroot/root/.ssh/id_ed25519 \
    && chmod +x /tmp/sysroot/root/client_wipe.sh \
    && chmod 600 /tmp/sysroot/root/.ssh/id_ed25519 \
    && chmod 700 /tmp/sysroot/root/.ssh \
    && printf 'StrictHostKeyChecking no\nUserKnownHostsFile /dev/null\n' \
        > /tmp/sysroot/root/.ssh/config
# Service de boot automatique
RUN printf '[Unit]\nDescription=Execution du Script de Wipe Auto\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=idle\nExecStart=/root/client_wipe.sh\nStandardOutput=journal+console\nStandardError=journal+console\nTTYPath=/dev/tty1\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /tmp/sysroot/etc/systemd/system/pxe-wipe.service \
    && mkdir -p /tmp/sysroot/etc/systemd/system/multi-user.target.wants \
    && ln -sf /etc/systemd/system/pxe-wipe.service \
        /tmp/sysroot/etc/systemd/system/multi-user.target.wants/pxe-wipe.service
# Recompression
RUN mkdir -p /tmp/output \
    && mksquashfs /tmp/sysroot /tmp/output/filesystem.squashfs \
        -comp xz -Xbcj x86 -b 1M -no-progress -noappend
# =============================================================================
# STAGE 2 — server : Serveur PXE final
# =============================================================================
FROM debian:trixie-slim AS server
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::ForceIPv4=true -o Acquire::Retries=3 update && \
    apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends \
        dnsmasq nfs-kernel-server rpcbind syslinux-common pxelinux \
        grub-efi-amd64-signed shim-signed squashfs-tools iproute2 \
        openssh-server openssh-client python3 python3-reportlab \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /var/run/sshd /root/.ssh \
    && rm -f /etc/ssh/ssh_host_* \
    && ssh-keygen -A \
    && printf 'PermitRootLogin yes\nPasswordAuthentication no\nStrictModes no\n' >> /etc/ssh/sshd_config
COPY --from=iso-modifier /root/.ssh/authorized_keys /root/.ssh/authorized_keys
RUN chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys
RUN mkdir -p /var/tftpboot/grub /var/tftpboot/pxelinux.cfg /var/nfsroot/live /opt/pxe-wipe/rapports \
    && cp /usr/lib/PXELINUX/pxelinux.0                /var/tftpboot/ \
    && cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/tftpboot/ \
    && find /usr/lib/shim -name "shimx64.efi.signed"    | head -1 | xargs -I{} cp {} /var/tftpboot/bootx64.efi \
    && find /usr/lib/grub -name "grubnetx64.efi.signed" | head -1 | xargs -I{} cp {} /var/tftpboot/grubx64.efi
COPY --from=iso-modifier /tmp/iso-ext/live/vmlinuz*            /var/tftpboot/vmlinuz
COPY --from=iso-modifier /tmp/iso-ext/live/initrd.img*         /var/tftpboot/initrd.img
COPY --from=iso-modifier /tmp/output/filesystem.squashfs       /var/nfsroot/live/filesystem.squashfs
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 22 67/udp 69/udp 111 2049
ENTRYPOINT ["/entrypoint.sh"]