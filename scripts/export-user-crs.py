#!/usr/bin/env python3
"""Export user-owned (non-derived) EDA CRs from a namespace as clean, re-appliable JSON.

One file per kind under OUT. Server-managed metadata and status are stripped so
`kubectl apply -f` works against a new namespace (namespace rewritten with --to-ns).

Usage: export-user-crs.py [-n NS] [--to-ns NS2] OUT
"""
import argparse
import json
import os
import subprocess

DROP_META = ("resourceVersion", "uid", "creationTimestamp", "generation",
             "managedFields", "ownerReferences", "finalizers", "selfLink")

p = argparse.ArgumentParser()
p.add_argument("-n", default="clab-srl-leaf-spine-dcgw")
p.add_argument("--to-ns")
p.add_argument("out")
a = p.parse_args()
os.makedirs(a.out, exist_ok=True)

kinds = subprocess.run(
    ["kubectl", "api-resources", "--namespaced=true", "--verbs=list", "-o", "name"],
    capture_output=True, text=True, check=True).stdout.split()
kinds = [k for k in kinds if k.endswith(".eda.nokia.com") or k.endswith(".eda.labs")]

for kind in kinds:
    r = subprocess.run(["kubectl", "get", kind, "-n", a.n, "-o", "json"],
                       capture_output=True, text=True)
    if r.returncode:
        continue
    items = []
    for it in json.loads(r.stdout)["items"]:
        meta = it["metadata"]
        if (meta.get("labels") or {}).get("eda.nokia.com/source") == "derived":
            continue
        for k in DROP_META:
            meta.pop(k, None)
        ann = meta.get("annotations") or {}
        ann.pop("kubectl.kubernetes.io/last-applied-configuration", None)
        if not ann:
            meta.pop("annotations", None)
        if a.to_ns:
            meta["namespace"] = a.to_ns
        it.pop("status", None)
        items.append(it)
    if items:
        with open(os.path.join(a.out, kind + ".json"), "w") as f:
            json.dump({"apiVersion": "v1", "kind": "List", "items": items}, f, indent=1)
        print(f"{len(items):4d} {kind}")
