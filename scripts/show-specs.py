#!/usr/bin/env python3
"""Print compact name + spec for each CR of the given kinds, read live via kubectl.

Usage: show-specs.py [-n NS] kind [kind ...]
"""
import json
import subprocess
import sys

args = sys.argv[1:]
ns = "clab-srl-leaf-spine-dcgw"
if args[:1] == ["-n"]:
    ns, args = args[1], args[2:]

for kind in args:
    out = subprocess.run(["kubectl", "get", kind, "-n", ns, "-o", "json"],
                         capture_output=True, text=True, check=True).stdout
    for item in json.loads(out)["items"]:
        meta = item["metadata"]
        src = (meta.get("labels") or {}).get("eda.nokia.com/source", "")
        print(f"## {item['kind']} {meta['name']} {src}")
        print(json.dumps(item.get("spec"), separators=(",", ":")))
