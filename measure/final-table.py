#!/usr/bin/env python3
"""final-table.py: the stock-vs-custom comparison tables for the report and slides.

Usage: final-table.py <stock-results-dir> <custom-results-dir> [size-release.txt] [size-dev.txt]
Reads only files written by measure/ scripts (run-target.sh raw output, image-size.sh).
Image size for the custom image comes from the build (image-size.sh): on the running
appliance `du -x /` cannot see the squashfs content under the /etc and /var overlays.
"""
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from summarize import load  # noqa: E402


def kv(path):
    d = {}
    if path and os.path.exists(path):
        for line in open(path):
            m = re.match(r"^(\w+)=([\d.]+)", line)
            if m:
                d[m.group(1)] = float(m.group(2))
    return d


def med(xs):
    return statistics.median(xs) if xs else None


def red(a, b):
    if not a or b is None:
        return "n/a"
    r = (1 - b / a) * 100
    return "same (within 1%)" if abs(r) < 1 else (f"{r:.0f}% less" if r > 0 else f"{-r:.0f}% more")


def f(x, nd=1):
    return "n/a" if x is None else f"{x:,.{nd}f}"


stock, custom = load(sys.argv[1]), load(sys.argv[2])
rel = kv(sys.argv[3] if len(sys.argv) > 3 else None)
dev = kv(sys.argv[4] if len(sys.argv) > 4 else None)
s_root_mib = stock["static"]["rootfs_used_bytes"] / 2**20

out = ["## Size", "",
       "| Metric | Stock Ubuntu + NVIDIA stack | Custom release | Custom dev (lab access) | Reduction (release) |",
       "|---|---|---|---|---|",
       f"| Root filesystem, uncompressed (MiB) | {f(s_root_mib, 0)} | {f(rel.get('rootfs_uncompressed_MiB'), 0)} | {f(dev.get('rootfs_uncompressed_MiB'), 0)} | {red(s_root_mib, rel.get('rootfs_uncompressed_MiB'))} |",
       f"| On the medium (MiB) (stock: ext4 used; custom: squashfs + UKI) | {f(s_root_mib, 0)} | {f(rel.get('medium_total_MiB'), 0)} | {f(dev.get('medium_total_MiB'), 0)} | {red(s_root_mib, rel.get('medium_total_MiB'))} |",
       f"| Compressed squashfs (MiB) | n/a | {f(rel.get('squashfs_MiB'), 0)} | {f(dev.get('squashfs_MiB'), 0)} | |",
       f"| of which: CUDA benchmark container archive (MiB) | n/a | {f(rel.get('bench_container_archive_MiB'), 0)} | {f(dev.get('bench_container_archive_MiB'), 0)} | |",
       f"| dpkg packages | {stock['static']['packages_dpkg']} | {f(rel.get('dpkg_packages'), 0)} | {f(dev.get('dpkg_packages'), 0)} | {red(stock['static']['packages_dpkg'], rel.get('dpkg_packages'))} |",
       "", "## Boot time on the same USB stick and laptop (median of 5 boots, seconds)", "",
       "| Phase | Stock | Custom dev | Reduction |", "|---|---|---|---|"]
for k in ("firmware", "loader", "kernel", "userspace", "total"):
    a, b = med(stock["boot"][k]), med(custom["boot"][k])
    out.append(f"| {k} | {f(a, 2)} | {f(b, 2)} | {red(a, b)} |")
ttb = med(custom["boot"]["time_to_benchmark"])
out.append(f"| kernel start to benchmark running | n/a (no auto-start) | {f(ttb, 0)} | |")
sr, cr = stock["ram"], custom["ram"]
out += ["", "## RAM (idle after at least 5 min; peak during the GPU benchmark)", "",
        "| Metric | Stock | Custom dev | Reduction |", "|---|---|---|---|",
        f"| Idle used, `free -m` (MiB) | {sr['used_mib']} | {cr['used_mib']} | {red(sr['used_mib'], cr['used_mib'])} |",
        f"| Idle PSS, all processes (MiB) | {f(sr['pss_mib'], 0)} | {f(cr['pss_mib'], 0)} | {red(sr['pss_mib'], cr['pss_mib'])} |",
        f"| Running services | {sr['services']} | {cr['services']} | {red(sr['services'], cr['services'])} |",
        f"| Peak used during benchmark (MiB) | {sr['peak_mib']} | {cr['peak_mib']} | {red(sr['peak_mib'], cr['peak_mib'])} |",
        "", "## GPU benchmark (median of 7 runs; stock = native binary, custom = rootless container)", "",
        "| Metric | Stock | Custom | Difference |", "|---|---|---|---|"]
for k, lbl, better in (("bandwidth_gbs", "Memory copy bandwidth (GB/s)", 1), ("sgemm_tflops", "cuBLAS SGEMM N=4096 (TFLOP/s)", 1),
                       ("launch_roundtrip_us", "Kernel launch + sync (µs)", -1), ("launch_async_us", "Async launch (µs/launch)", -1)):
    a = med([r[k] for r in stock["bench"]["runs"]])
    b = med([r[k] for r in custom["bench"]["runs"]])
    d = f"{(b / a - 1) * 100:+.1f}%" if a and b else "n/a"
    out.append(f"| {lbl} | {f(a, 2)} | {f(b, 2)} | {d} |")
out.append(f"\nMax GPU temperature: stock {stock['bench']['temp_max']} °C, custom {custom['bench']['temp_max']} °C.")
print("\n".join(out))
