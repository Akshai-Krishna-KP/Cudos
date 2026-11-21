#!/usr/bin/env bash
# build-kernel.sh: build the Track C kernel (Phase 3). Runs INSIDE the kernel builder:
#   build/kernel/run.sh   (wrapper that builds/starts the container)
# Config = Debian 13's 6.12 config (from the pinned, cached linux-image .deb)
#        -> make localmodconfig with the modules loaded on both laptops (build/kernel/lsmod-*.txt)
#        -> build/kernel/trackc.config fragment.
# Output: out/kernel/linux-image-*-trackc_*.deb, linux-headers-*.deb, config-<ver>-trackc
set -euo pipefail
SRC=/src; source "$SRC/build/versions.env"
FLAVOR=${1:-laptop}   # laptop = the kernel on the sticks; iso = + trackc-iso.config
V=$KERNEL_VERSION; O=$SRC/out/kernel; W=/build
[[ $FLAVOR == iso ]] && O=$SRC/out/kernel-iso
rm -rf "$O"; mkdir -p "$O" "$W"
tar -xf "$SRC/cache/kernel/linux-$V.tar.xz" -C "$W"
cd "$W/linux-$V"
deb=$(ls "$SRC"/cache/mmdebstrap-debs/linux-image-6.12.*+deb13-amd64_*.deb 2>/dev/null | head -1 || true)
if [[ -z $deb ]]; then   # clean clone: fetch the pinned Debian kernel package for its config
  (cd /tmp && apt-get -qq update && apt-get -qq download "$KERNEL_BASECONFIG_PKG") >/dev/null
  deb=$(ls /tmp/linux-image-*.deb | head -1)
fi
dpkg-deb --fsys-tarfile "$deb" | tar -xO --wildcards './boot/config-*' > .config
cat "$SRC"/build/kernel/lsmod-*.txt | sort -u | awk '{print $1, 0, 0}' > /tmp/lsmod
make -s olddefconfig
(yes '' || true) | make -s LSMOD=/tmp/lsmod localmodconfig >/dev/null 2>&1
FRAGS=("$SRC/build/kernel/trackc.config"); [[ $FLAVOR == iso ]] && FRAGS+=("$SRC/build/kernel/trackc-iso.config")
scripts/kconfig/merge_config.sh -m -O . .config "${FRAGS[@]}" >/dev/null
make -s olddefconfig
echo "modules enabled: $(grep -c '=m$' .config)   built-in: $(grep -c '=y$' .config)"
export KBUILD_BUILD_TIMESTAMP="@$SOURCE_DATE_EPOCH" KBUILD_BUILD_USER=trackc KBUILD_BUILD_HOST=trackc-builder
make -j"$(nproc)" bindeb-pkg KDEB_PKGVERSION="$V-1" DPKG_FLAGS=-d >/tmp/build.log 2>&1 || { tail -40 /tmp/build.log; exit 1; }
cp .config "$O/config-$V-trackc"
mv ../linux-image-*.deb ../linux-headers-*.deb "$O/"
ls -l "$O"
