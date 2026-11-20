#!/usr/bin/env python3
"""render-wifi-netplan.py: print a netplan Wi-Fi config for the lab hotspot(s).

Usage: render-wifi-netplan.py SSID PASSWORD [SSID2 PASSWORD2 ...]
Every pair becomes an access point; NetworkManager-less netplan (networkd +
wpa_supplicant) joins whichever is in range. JSON strings are valid YAML
scalars, so quoting is always safe for spaces and special characters.
"""
import json
import sys

args = sys.argv[1:]
if not args or len(args) % 2:
    sys.exit("usage: render-wifi-netplan.py SSID PASSWORD [SSID2 PASSWORD2 ...]")
aps = "\n".join(
    f"        {json.dumps(s)}: {{password: {json.dumps(p)}}}"
    for s, p in zip(args[::2], args[1::2])
)
print(f"""network:
  version: 2
  wifis:
    wlan:
      match: {{name: "wl*"}}
      dhcp4: true
      optional: true
      access-points:
{aps}""")
