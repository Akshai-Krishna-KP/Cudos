# Pinned build environment for the Track C image.
# Base image is pinned by digest and apt points at the same snapshot as the
# target rootfs, so the toolchain is reproducible too.
ARG BUILDER_BASE_IMAGE
FROM ${BUILDER_BASE_IMAGE}
ARG DEBIAN_SNAPSHOT
ARG DEBIAN_SUITE
# Plain HTTP: the slim image has no CA bundle yet; apt still verifies every
# package against the Debian archive GPG keys, so integrity is unaffected.
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s %s main\ndeb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s %s-updates main\ndeb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s %s-security main\n' \
      "$DEBIAN_SNAPSHOT" "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$DEBIAN_SUITE" "$DEBIAN_SNAPSHOT" "$DEBIAN_SUITE" \
      > /etc/apt/sources.list && \
    apt-get -o Acquire::Retries=5 update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      # rootfs bootstrap (debootstrap-compatible, reproducible, works in containers)
      mmdebstrap ca-certificates \
      # image assembly
      squashfs-tools dosfstools mtools gdisk e2fsprogs zstd xorriso \
      # Unified Kernel Image (kernel + initrd + cmdline in one EFI binary)
      systemd-ukify systemd-boot-efi python3-pefile binutils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
