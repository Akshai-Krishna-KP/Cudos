#!/usr/bin/env bash
# verify-appliance.sh: final acceptance checks, run ON the appliance (dev image) as the
# login user. Prints one PASS/FAIL line per check and a summary; exit 0 only if all pass.
# Run from Laptop 1:  ssh -i ~/.ssh/trackc_ed25519 lazarus@<ip> 'bash -s' < measure/verify-appliance.sh
set -uo pipefail
pass=0; fail=0
check() {   # check "<name>" <command...>
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
  else printf 'FAIL  %s\n' "$name"; fail=$((fail + 1)); fi
}
has_opt() { findmnt -no OPTIONS "$1" | tr ',' '\n' | grep -qx "$2"; }
sysctl_is() { [[ $(cat "/proc/sys/${1//.//}") == "$2" ]]; }
echo "# verify-appliance  $(date -Is)  $(whoami)@$(hostname)  kernel $(uname -r)"

echo "## System"
check "kernel is our 6.12.118-trackc"                  test "$(uname -r)" = 6.12.118-trackc
check "no failed systemd units"                        test "$(systemctl --failed --no-legend | wc -l)" = 0
check "login user is lazarus"                          test "$(whoami)" = lazarus
check "password 'lazarus' accepted (sudo -S)"          bash -c 'sudo -k; echo lazarus | sudo -S -v'

echo "## Read-only root + overlays (hardening 1)"
check "root is squashfs"                               test "$(findmnt -no FSTYPE /)" = squashfs
check "root mounted ro"                                has_opt / ro
check "write to / refused"                             bash -c '! sudo touch /usr/.trackc-probe 2>/dev/null'
check "/etc and /var are overlays"                     bash -c '[[ $(findmnt -no FSTYPE /etc) == overlay && $(findmnt -no FSTYPE /var) == overlay ]]'
for m in /tmp /var/tmp /home; do for o in nodev nosuid noexec; do check "$m $o" has_opt "$m" "$o"; done; done
check "boot self-test RESULT PASS"                     bash -c 'sudo journalctl -b -u trackc-selftest --no-pager | grep -q "RESULT PASS"'

echo "## GPU auto-configuration"
check "gpu-autoconfig active"                          systemctl is-active -q gpu-autoconfig
check "NVIDIA GPU visible (nvidia-smi)"                nvidia-smi -L
check "open kernel module 620.70.06 loaded"            bash -c 'grep -q 620.70.06 /proc/driver/nvidia/version && grep -qi "open kernel module" /proc/driver/nvidia/version'
check "persistence mode on"                            bash -c 'nvidia-smi --query-gpu=persistence_mode --format=csv,noheader | grep -q Enabled'
check "Dynamic Boost (nvidia-powerd) active"           systemctl is-active -q nvidia-powerd
check "CDI spec generated"                             test -s /run/cdi/nvidia.yaml
check "boot health-check benchmark result present"     test -s /run/trackc-bench/latest.json
check "health check ran as non-root user bench"        bash -c '[[ $(systemctl show -p User --value trackc-bench) == bench ]]'

echo "## Hardening 2-5"
check "sysctl kptr_restrict=2"                         sysctl_is kernel.kptr_restrict 2
check "sysctl dmesg_restrict=1"                        sysctl_is kernel.dmesg_restrict 1
check "sysctl unprivileged_bpf_disabled=1"             sysctl_is kernel.unprivileged_bpf_disabled 1
check "sysctl yama ptrace_scope=2"                     sysctl_is kernel.yama.ptrace_scope 2
check "nftables input policy drop"                     bash -c 'sudo nft list chain inet filter input | grep -q "policy drop"'
check "SSH: no passwords, no root login"               bash -c 'sudo sshd -T | grep -qx "passwordauthentication no" && sudo sshd -T | grep -qx "permitrootlogin no"'
check "no compiler on the host system"                 bash -c '! command -v gcc && ! command -v nvcc && ! command -v cc'
check "internal NVMe disks read-only"                  bash -c 'for d in /sys/block/nvme*; do [[ -e $d ]] || continue; [[ $(cat $d/ro) == 1 ]] || exit 1; done'

echo "## Network"
check "DNS resolves (systemd-resolved)"                getent hosts developer.download.nvidia.com

echo "## Your own CUDA code (cuda-dev)"
W=$(mktemp -d -p ~/cuda .verify.XXXX)
cp /usr/share/trackc/examples/vector_add.cu "$W/"
check "cuda-dev nvcc compiles vector_add.cu"           bash -c "cd '$W' && cuda-dev nvcc -arch=sm_89 -o va vector_add.cu"
check "program runs on the GPU (PASS)"                 bash -c "cd '$W' && cuda-dev ./va | grep -q 'vector_add: PASS'"
rm -rf "$W"

echo "## lazarus package manager"
check "lazarus-list shows the NVIDIA mirror"           bash -c 'lazarus-list | tail -1 | grep -q "package versions on developer.download.nvidia"'
check "lazarus-list --local shows curated list"        bash -c 'lazarus-list --local | grep -q cudnn'
check "lazarus-mirror shows mirrors"                   bash -c 'lazarus-mirror | grep -q "^nvidia: https://developer.download.nvidia"'

echo "## Summary: $pass passed, $fail failed"
(( fail == 0 ))
