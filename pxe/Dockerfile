FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        # Réseau / PXE
        dnsmasq \
        iproute2 \
        # NFS
        nfs-kernel-server \
        rpcbind \
        # TFTP bootloaders
        syslinux-common \
        pxelinux \
        grub-efi-amd64-signed \
        shim-signed \
        # Extraction image ShredOS
        p7zip-full \
        squashfs-tools \
        wget \
        curl \
        ca-certificates \
        # Outils divers
        jq \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# Dossiers de travail
RUN mkdir -p \
        /var/tftpboot/grub \
        /var/tftpboot/pxelinux.cfg \
        /var/nfsroot/live \
        /opt/pxe-wipe/rapports \
        /opt/shredos

# Bootloaders BIOS
RUN cp /usr/lib/PXELINUX/pxelinux.0                /var/tftpboot/ && \
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32 /var/tftpboot/

# Bootloaders UEFI
RUN find /usr/lib/shim -name "shimx64.efi.signed"    | head -1 | xargs -I{} cp {} /var/tftpboot/bootx64.efi && \
    find /usr/lib/grub -name "grubnetx64.efi.signed" | head -1 | xargs -I{} cp {} /var/tftpboot/grubx64.efi

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 67/udp 69/udp 111 2049 111/udp 2049/udp

ENTRYPOINT ["/entrypoint.sh"]
