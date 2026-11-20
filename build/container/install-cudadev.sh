#!/usr/bin/env bash
# install-cudadev.sh: copy the CUDA dev container archive (out/trackc-cuda-dev.tar) onto
# the persist partition of a RUNNING appliance (dev image) over SSH, verify it, and
# pre-load it for user trackc so the first `cuda-dev` call is fast.
# Usage: build/container/install-cudadev.sh <host>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOST=${1:?host}; T="$REPO/out/trackc-cuda-dev.tar"; D=/run/trackc/persist/images/trackc-cuda-dev.tar
S=(ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error "trackc@$HOST")
[[ -f $T ]] || { echo "build it first: build/container/build-cudadev-image.sh" >&2; exit 1; }
[[ $("${S[@]}" 'findmnt -no FSTYPE /') == squashfs ]] || { echo "target is not running the appliance" >&2; exit 1; }
echo "copying $(( $(stat -c %s "$T") / 1048576 )) MiB to $HOST:$D ..."
"${S[@]}" "sudo install -d /run/trackc/persist/images && sudo tee $D.part >/dev/null && sudo mv $D.part $D" < "$T"
[[ $("${S[@]}" "sha256sum < $D" | awk '{print $1}') == $(sha256sum < "$T" | awk '{print $1}') ]] \
  && echo "archive verified" || { echo "archive hash MISMATCH" >&2; exit 1; }
"${S[@]}" 'cd ~/cuda && cuda-dev nvcc --version | tail -1'
