#!/usr/bin/env bash
# MH L3 DCI per ES: four vnets + RouterInterconnect 430 ↔ 431.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> MH L3 VirtualNetworks (per ES)"
kubectl apply -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc1a.yaml"
kubectl apply -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc1b.yaml"
kubectl apply -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc2a.yaml"
kubectl apply -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc2b.yaml"

echo "==> MH L3 RouterInterconnect (430 ↔ 431)"
kubectl apply -f "$ROOT/services/mh/router-interconnect-mh-l3-dc1.yaml"
kubectl apply -f "$ROOT/services/mh/router-interconnect-mh-l3-dc2.yaml"

echo "==> MH LAG edges (role=edge + one vnet label per ES)"
kubectl apply -f "$ROOT/services/mh/interface-labels/edge-mh-lags.yaml"

echo "==> Status"
kubectl get virtualnetwork -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState | grep mh-l3
kubectl get routerinterconnects -n "$NS" | grep mh-l3 || true
