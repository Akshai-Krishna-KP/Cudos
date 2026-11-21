#!/usr/bin/env bash
# fetch-source.sh: download the pinned kernel.org LTS tarball into cache/kernel/ and
# verify it against the pinned SHA-256 (taken from kernel.org's sha256sums.asc).
# Usage: build/kernel/fetch-source.sh      (then: build/kernel/run.sh [iso])
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/build/versions.env"
D="$REPO/cache/kernel"; mkdir -p "$D"; F="$D/linux-$KERNEL_VERSION.tar.xz"
[[ -f $F ]] || curl -fL --retry 3 -o "$F.part" "$KERNEL_URL" && { [[ -f $F ]] || mv "$F.part" "$F"; }
echo "$KERNEL_SHA256  $F" | sha256sum -c --quiet - && echo "kernel source ok: $F"
