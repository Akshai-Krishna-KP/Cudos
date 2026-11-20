# Phase 7: reproducibility check

Two clean builds of the **release** image (`build/rootfs/build-rootfs.sh release` +
`build/image/build-image.sh release`, each starting from an empty rootfs directory) on
Laptop 1, 2026-11-20. SHA-256 of the outputs: `hashes-buildA.txt`, `hashes-buildB.txt`,
comparison: `compare.txt`.

Result: **bit-for-bit identical** squashfs root, UKI (kernel + initramfs) and package list.

How: pinned snapshot.debian.org date, pinned NVIDIA package versions, pinned builder image,
`SOURCE_DATE_EPOCH` for all timestamps (mksquashfs, UKI), and NVIDIA's module build stamp
pinned (`NV_BUILD_USER`, `NV_BUILD_HOST`, `DATE`): an earlier pair of builds differed only in
`nvidia.ko`/`nvidia-modeset.ko`, which embed `user@host` and the build date (`hashes-build1/2`
history in Git).

Limits of this check: both builds ran on the same machine using the cached .debs
(`cache/mmdebstrap-debs`, signature-checked by apt); the benchmark container archive
(`out/trackc-bench.tar`) is an input here and was not rebuilt between the two builds.

## Final image on our kernel (6.12.118-trackc)

Two clean release builds from the same kernel packages: squashfs, UKI and package list
**identical** (`compare-trackc.txt`). The kernel packages themselves were rebuilt once more
(`compare-kernel.txt`): the `.config` is identical, but the `linux-image`/`linux-headers`
.debs differ between builds (not yet investigated: likely build IDs or file metadata inside
the packages). So the image is reproducible from a given set of kernel packages; the kernel
build itself is not yet bit-for-bit reproducible.
