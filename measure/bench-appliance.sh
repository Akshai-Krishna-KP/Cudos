#!/usr/bin/env bash
# bench-appliance.sh: one benchmark run on the CUSTOM image, exactly as the boot
# service runs it (rootless Podman container as user 'bench', GPU via CDI).
# Called by collect.sh (BENCH_CMD="bash /tmp/trackc-bench-appliance.sh"), args passed through.
set -euo pipefail
install -d -o bench -g bench -m 700 /run/trackc-bench
exec runuser -u bench -- env HOME=/var/lib/trackc-bench XDG_RUNTIME_DIR=/run/trackc-bench \
  /usr/local/sbin/trackc-bench-run once "$@" 2> >(grep -v 'pause process' >&2)
