#!/usr/bin/env python3
"""Split a containerlab topology-data.json into two node sets for two EDA namespaces.

Links with both ends in one set stay in that set's file. Links that cross the sets
are dropped (they become plain Interface + DefaultInterface CRs in each namespace)
and are listed on stdout.

Usage: split-topology-data.py IN OUT_A OUT_B node [node ...]
  nodes listed go to OUT_B; everything else goes to OUT_A.
"""
import copy
import json
import sys

src, out_a, out_b, *b_nodes = sys.argv[1:]
b_nodes = set(b_nodes)
data = json.load(open(src))

def subset(keep):
    d = copy.deepcopy(data)
    d["nodes"] = {n: v for n, v in data["nodes"].items() if keep(n)}
    d["links"] = [l for l in data["links"]
                  if keep(l["endpoints"]["a"]["node"]) and keep(l["endpoints"]["z"]["node"])]
    return d

a = subset(lambda n: n not in b_nodes)
b = subset(lambda n: n in b_nodes)
json.dump(a, open(out_a, "w"), indent=2)
json.dump(b, open(out_b, "w"), indent=2)
print(f"A: {len(a['nodes'])} nodes {len(a['links'])} links -> {out_a}")
print(f"B: {len(b['nodes'])} nodes {len(b['links'])} links -> {out_b}")
print("cross-namespace links:")
for l in data["links"]:
    ea, ez = l["endpoints"]["a"], l["endpoints"]["z"]
    if (ea["node"] in b_nodes) != (ez["node"] in b_nodes):
        print(f"  {ea['node']}:{ea['interface']} - {ez['node']}:{ez['interface']}")
