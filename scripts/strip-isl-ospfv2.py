#!/usr/bin/env python3
"""Remove leftover spec.ospf.ospfv2 from WAN ISLs (kubectl apply merge keeps it)."""
import json
import subprocess
import sys

ns = sys.argv[1] if len(sys.argv) > 1 else "clab-srl-leaf-spine-dcgw"
r = subprocess.run(
    ["kubectl", "get", "isl", "-n", ns, "-o", "json"],
    capture_output=True,
    text=True,
    check=True,
)
doc = json.loads(r.stdout)
for item in doc.get("items") or []:
    name = item["metadata"]["name"]
    ospf = (item.get("spec") or {}).get("ospf") or {}
    if "ospfv2" not in ospf:
        print(f"{name}: no ospfv2")
        continue
    p = subprocess.run(
        [
            "kubectl",
            "patch",
            "isl",
            name,
            "-n",
            ns,
            "--type",
            "json",
            "-p",
            '[{"op":"remove","path":"/spec/ospf/ospfv2"}]',
        ],
        capture_output=True,
        text=True,
    )
    msg = (p.stdout or p.stderr).strip()
    print(f"{name}: {msg or ('ok' if p.returncode == 0 else 'failed rc=' + str(p.returncode))}")
