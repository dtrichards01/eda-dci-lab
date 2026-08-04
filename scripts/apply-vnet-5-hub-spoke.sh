#!/usr/bin/env bash
# Deploy vnet-5 spoke + hub multi-RT import for vnet-1 + vnet-5 hub-spoke.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POL="$(cd "$ROOT/services/dci-policies" && pwd)"
RIC="$(cd "$ROOT/services/l3/router-interconnect" && pwd)"

echo "==> Community sets + hub import policy"
kubectl apply -f "$POL/communitysets/vpn-import-rts.yaml"
kubectl apply -f "$POL/policies/multi-rt-import.yaml"

echo "==> WAN policies (vnet-5 RT 102 on DC1 export / DC2 import)"
kubectl apply -f "$POL/policies/export-dc-1-routes-and-add-soo.yaml"
kubectl apply -f "$POL/policies/import-dci-services-dc-2.yaml"

echo "==> VirtualNetwork vnet-5 (spoke)"
kubectl apply -f "$ROOT/clab/eda-vnets/vnet-5.yaml"
kubectl patch virtualnetwork vnet-5 -n "$NS" --type=json \
  --patch-file="$POL/patches/vnet-irb-evpn-hostroutes-patch.json"

echo "==> Edge interface"
kubectl apply -f "$ROOT/services/l3/interface-labels/edge-l3-vnet-5-dc1.yaml"

echo "==> RouterInterconnect hub (multi-rt-import) + spoke (RT 102)"
kubectl apply -f "$RIC/router-interconnect-vnet-2.yaml"
kubectl apply -f "$RIC/router-interconnect-vnet-5.yaml"

echo "==> Status"
kubectl get virtualnetwork vnet-5 -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState,NODES:.status.nodes
kubectl get routerinterconnect router-interconnect-vnet-2 router-interconnect-vnet-5 -n "$NS" -o custom-columns=NAME:.metadata.name,EXP-T:.spec.interconnectBGPInstance.exportTarget,IMP-P:.spec.interconnectBGPInstance.importPolicy,STATE:.status.operationalState
