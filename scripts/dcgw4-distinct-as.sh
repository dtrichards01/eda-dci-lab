#!/usr/bin/env bash
# dcgw-4 underlay AS 64906 -> 64907 (dcgw-3 stays 64906), plus the two pod-2 spine peers to dcgw-4.
# One EDA transaction across both namespaces. Dry-run by default; pass --commit to apply.
set -eu
NEW_AS=${NEW_AS:-64907}
WAN=clab-srl-dcgw-wan
POD=clab-srl-leaf-spine-dcgw
OPS=/tmp/dcgw4-as-ops.json
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

{
  kubectl -n $WAN get defaultrouter.routing.eda.nokia.com router-dcgw-4 -o json
  kubectl -n $POD get defaultbgppeer.protocols.eda.nokia.com spine-3-dcgw-4-ebgp -o json
  kubectl -n $POD get defaultbgppeer.protocols.eda.nokia.com spine-4-dcgw-4-ebgp -o json
} | NEW_AS=$NEW_AS python3 -c '
import json, os, sys
new_as = int(os.environ["NEW_AS"])
dec, raw, i, items = json.JSONDecoder(), sys.stdin.read(), 0, []
while i < len(raw):
    if raw[i].isspace():
        i += 1; continue
    o, i = dec.raw_decode(raw, i)
    o.pop("status", None)
    for k in ("creationTimestamp", "resourceVersion", "uid", "managedFields", "generation", "annotations"):
        o["metadata"].pop(k, None)
    if o["kind"] == "DefaultRouter":
        o["spec"]["bgp"]["autonomousSystem"] = new_as
    else:
        o["spec"]["peerAS"] = {"autonomousSystem": new_as}
    items.append(o)
json.dump({"apiVersion": "v1", "kind": "List", "items": items}, open("'$OPS'", "w"), indent=1)
for o in items:
    print(o["kind"], o["metadata"]["namespace"], o["metadata"]["name"], json.dumps(o["spec"].get("bgp", {}).get("autonomousSystem") or o["spec"].get("peerAS")))
'
python3 "$(dirname "$0")/eda-txn.py" $OPS --desc "dcgw-4 underlay AS $NEW_AS (distinct from dcgw-3)" "$@"
