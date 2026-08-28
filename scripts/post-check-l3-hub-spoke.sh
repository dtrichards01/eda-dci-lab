#!/usr/bin/env bash
# Read-only post-check: live L3 hub-spoke RTs, community set, ping matrix.
# Does not apply or patch EDA.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"

echo "==== RIC export/import (expect vnet-5 export target:1:105) ===="
kubectl get routerinterconnect -n "$NS" -o custom-columns=\
NAME:.metadata.name,\
EXP:.spec.interconnectBGPInstance.exportTarget,\
IMP:.spec.interconnectBGPInstance.importTarget,\
POL:.spec.interconnectBGPInstance.importPolicy,\
STATE:.status.operationalState

echo
echo "==== vpn-import-rts (expect 1:100 + 1:105, Any) ===="
kubectl get communityset vpn-import-rts -n "$NS" -o jsonpath='{.spec}' ; echo

echo
echo "==== L3 edge vnet labels ===="
kubectl get interface -n "$NS" -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for i in d.get("items",[]):
  labs=i["metadata"].get("labels",{})
  vn=[f"{k}={v}" for k,v in labs.items() if "vnet-" in k]
  if vn:
    print(i["metadata"]["name"], *vn)
'

echo
ROOT="$(cd "$(dirname "$0")" && pwd)"
bash "$ROOT/test-l3-cross-dc-ping.sh"
