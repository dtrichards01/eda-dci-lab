#!/usr/bin/env bash
# SH L3 DCI: vnet-6 / vnet-7 RouterInterconnect (155.x ↔ 156.x).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> VirtualNetworks vnet-6 / vnet-7"
kubectl apply -f "$ROOT/services/l3/vnet-6/virtualnetwork-vnet-6.yaml"
kubectl apply -f "$ROOT/services/l3/vnet-7/virtualnetwork-vnet-7.yaml"

echo "==> RouterInterconnect (stitch RT 400 ↔ 401)"
kubectl apply -f "$ROOT/services/l3/router-interconnect/router-interconnect-vnet-6.yaml"
kubectl apply -f "$ROOT/services/l3/router-interconnect/router-interconnect-vnet-7.yaml"

echo "==> Status"
kubectl get virtualnetwork vnet-6 vnet-7 -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState
kubectl get routerinterconnect router-interconnect-vnet-6 router-interconnect-vnet-7 -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState,ET:.spec.interconnectBGPInstance.exportTarget,IT:.spec.interconnectBGPInstance.importTarget
