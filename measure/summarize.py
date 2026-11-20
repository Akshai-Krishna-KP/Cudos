#!/usr/bin/env python3
"""summarize.py: turn the raw output of measure/collect.sh into Markdown tables.

Usage: summarize.py <results-dir>   (expects <results-dir>/raw/ from run-target.sh)
       summarize.py --compare <stock-dir> <custom-dir>   (side-by-side table)
Every number printed here is parsed from raw files; nothing is typed in by hand.
"""
import glob
import json
import os
import re
import statistics
import sys


def secs(tok):
    """'2min 11.192s' / '345ms' / '4.2s' -> seconds."""
    total = 0.0
    for val, unit in re.findall(r"([\d.]+)(min|ms|s)", tok):
        total += float(val) * {"min": 60, "s": 1, "ms": 0.001}[unit]
    return total


def spread(xs, fmt="{:.2f}"):
    if not xs:
        return "n/a", "n/a", 0
    med = statistics.median(xs)
    return fmt.format(med), f"{fmt.format(min(xs))} to {fmt.format(max(xs))}", len(xs)


def load(d):
    raw = os.path.join(d, "raw")
    r = {"boot": {}, "bench": {}, "static": {}, "ram": {}}
    # Boot timing
    phases = {"firmware": [], "loader": [], "kernel": [], "initrd": [], "userspace": [], "total": [], "time_to_benchmark": []}
    for f in sorted(glob.glob(os.path.join(raw, "boot-*.txt"))):
        txt = open(f).read()
        m = re.search(r"Startup finished in (.*?) = (.*?)\s*$", txt, re.M)
        if not m:
            continue
        for part in m.group(1).split(" + "):
            pm = re.match(r"(.*) \((\w+)\)", part.strip())
            if pm and pm.group(2) in phases:
                phases[pm.group(2)].append(secs(pm.group(1)))
        phases["total"].append(secs(m.group(2)))
        tb = re.search(r"time_to_benchmark_s=(\d+)", txt)
        if tb:
            phases["time_to_benchmark"].append(float(tb.group(1)))
    r["boot"] = phases
    # Benchmark
    runs = []
    bf = os.path.join(raw, "bench.jsonl")
    if os.path.exists(bf):
        runs = [json.loads(l) for l in open(bf) if l.strip().startswith("{")]
    r["bench"]["runs"] = runs
    tf = os.path.join(raw, "bench-telemetry.csv")
    temps, power, reasons = [], [], set()
    if os.path.exists(tf):
        for line in open(tf).readlines()[1:]:
            c = [x.strip() for x in line.split(",")]
            if len(c) < 7:
                continue
            try:
                temps.append(float(c[1]))
                power.append(float(c[2].split()[0]))
            except ValueError:
                pass
            reasons.add(c[6])
    r["bench"].update(temp_max=max(temps) if temps else None,
                      power_max=max(power) if power else None,
                      reasons=sorted(reasons))
    # Static
    sf = os.path.join(raw, "static.txt")
    if os.path.exists(sf):
        s = open(sf).read()
        for k in ("packages_dpkg", "rootfs_used_bytes"):
            m = re.search(rf"^{k}=(\d+)", s, re.M)
            r["static"][k] = int(m.group(1)) if m else None
        r["static"]["groups"] = dict(
            (g, int(v)) for g, v in re.findall(r"^(\S+)\s+(\d+) KiB$", s, re.M))
        m = re.search(r'^PRETTY_NAME="(.*)"', s, re.M)
        r["static"]["os"] = m.group(1) if m else "?"
    # RAM
    rf = os.path.join(raw, "ram-idle.txt")
    if os.path.exists(rf):
        s = open(rf).read()
        m = re.search(r"^Mem:\s+(\d+)\s+(\d+)", s, re.M)
        r["ram"]["total_mib"], r["ram"]["used_mib"] = (int(m.group(1)), int(m.group(2))) if m else (None, None)
        m = re.search(r"pss_total_kib=(\d+)", s)
        r["ram"]["pss_mib"] = int(m.group(1)) / 1024 if m else None
        m = re.search(r"uptime_s=([\d.]+)", s)
        r["ram"]["uptime_s"] = float(m.group(1)) if m else None
        m = re.search(r"running --no-legend --no-pager \| wc -l\n(\d+)", s)
        r["ram"]["services"] = int(m.group(1)) if m else None
    lf = os.path.join(raw, "ram-load.txt")
    if os.path.exists(lf):
        m = re.search(r"used_mib_peak=(\d+)", open(lf).read())
        r["ram"]["peak_mib"] = int(m.group(1)) if m else None
    return r


def gib(b):
    return f"{b / 2**30:.2f} GiB" if b else "n/a"


def single(d):
    r = load(d)
    name = os.path.basename(os.path.normpath(d))
    out = [f"# Measurements: {name}", "", f"OS: {r['static'].get('os', '?')}", ""]
    st = r["static"]
    out += ["## Size and packages", "", "| Metric | Value |", "|---|---|",
            f"| Root filesystem used (du -sxb /) | {gib(st.get('rootfs_used_bytes'))} |",
            f"| dpkg packages (ii+hi) | {st.get('packages_dpkg')} |"]
    for g, kib in sorted(st.get("groups", {}).items()):
        out.append(f"| dpkg group `{g}` | {kib / 1024**2:.2f} GiB |")
    b = r["boot"]
    n = len(b["total"])
    out += ["", f"## Boot time ({n} boots, systemd-analyze)", "",
            "| Phase | Median (s) | Range (s) |", "|---|---|---|"]
    for k in ("firmware", "loader", "kernel", "initrd", "userspace", "total", "time_to_benchmark"):
        if b[k]:
            med, rng, _ = spread(b[k])
            out.append(f"| {k} | {med} | {rng} |")
    ram = r["ram"]
    out += ["", "## RAM", "", "| Metric | Value |", "|---|---|",
            f"| Idle used (free -m, after {(ram.get('uptime_s') or 0):.0f} s uptime) | {ram.get('used_mib')} MiB |",
            f"| Idle PSS total (all processes) | {(ram.get('pss_mib') or 0):.0f} MiB |",
            f"| Running services | {ram.get('services')} |",
            f"| Peak used during GPU benchmark | {ram.get('peak_mib')} MiB |"]
    runs = r["bench"]["runs"]
    out += ["", f"## GPU benchmark ({len(runs)} runs)", ""]
    if runs:
        out += [f"GPU: {runs[0]['gpu']} (sm_{runs[0]['sm']}), CUDA driver {runs[0]['cuda_driver']}, runtime {runs[0]['cuda_runtime']}", "",
                "| Metric | Median | Range |", "|---|---|---|"]
        for k, lbl in (("bandwidth_gbs", "Memory copy bandwidth (GB/s)"), ("sgemm_tflops", "cuBLAS SGEMM 4096 (TFLOP/s)"),
                       ("launch_roundtrip_us", "Launch+sync round trip (us)"), ("launch_async_us", "Async launch (us/launch)")):
            med, rng, _ = spread([x[k] for x in runs], "{:.3f}" if "tflops" in k or "async" in k else "{:.2f}")
            out.append(f"| {lbl} | {med} | {rng} |")
        bb = r["bench"]
        out += ["", f"Max GPU temperature {bb['temp_max']} C, max power {bb['power_max']} W.",
                f"Clock event reasons seen (NVML, 0x0=none, 0x1=idle): {', '.join(bb['reasons'])}"]
    return "\n".join(out) + "\n"


def compare(a, b):
    ra, rb = load(a), load(b)
    na, nb = (os.path.basename(os.path.normpath(x)) for x in (a, b))

    def red(x, y):
        return f"{(1 - y / x) * 100:.1f}%" if x and y else "n/a"

    def med(xs):
        return statistics.median(xs) if xs else None

    rows = [("Root filesystem used (GiB)", ra["static"].get("rootfs_used_bytes"), rb["static"].get("rootfs_used_bytes"), 2**30),
            ("dpkg packages", ra["static"].get("packages_dpkg"), rb["static"].get("packages_dpkg"), 1),
            ("Idle RAM used (MiB)", ra["ram"].get("used_mib"), rb["ram"].get("used_mib"), 1),
            ("Idle PSS total (MiB)", ra["ram"].get("pss_mib"), rb["ram"].get("pss_mib"), 1),
            ("Running services", ra["ram"].get("services"), rb["ram"].get("services"), 1)]
    for k in ("kernel", "userspace", "total"):
        rows.append((f"Boot {k} median (s)", med(ra["boot"][k]), med(rb["boot"][k]), 1))
    out = [f"| Metric | {na} | {nb} | Reduction |", "|---|---|---|---|"]
    for lbl, x, y, div in rows:
        fx = f"{x / div:.2f}" if x is not None else "n/a"
        fy = f"{y / div:.2f}" if y is not None else "n/a"
        out.append(f"| {lbl} | {fx} | {fy} | {red(x, y)} |")
    for k, lbl in (("bandwidth_gbs", "Bandwidth GB/s"), ("sgemm_tflops", "SGEMM TFLOP/s"), ("launch_roundtrip_us", "Launch RT us")):
        x = med([r[k] for r in ra["bench"]["runs"]])
        y = med([r[k] for r in rb["bench"]["runs"]])
        out.append(f"| {lbl} (median) | {x if x is not None else 'n/a'} | {y if y is not None else 'n/a'} | (perf, not size) |")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--compare":
        print(compare(sys.argv[2], sys.argv[3]), end="")
    elif len(sys.argv) == 2:
        print(single(sys.argv[1]), end="")
    else:
        sys.exit(__doc__)
