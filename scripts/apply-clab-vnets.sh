#!/usr/bin/env bash
# Apply core VirtualNetwork CRs vnet-1 .. vnet-5 from cluster export.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
VN="$DIR/../clab/eda-vnets"
POL="$DIR/../services/dci-policies"

echo "==> VirtualNetworks vnet-1 .. vnet-5"
kubectl apply -f "$VN/vnet-1.yaml"
kubectl apply -f "$VN/vnet-2.yaml"
kubectl apply -f "$VN/vnet-3.yaml"
kubectl apply -f "$VN/vnet-4.yaml"
kubectl apply -f "$VN/vnet-5.yaml"

echo "==> IRB host-route patch (L3 vnets)"
kubectl patch virtualnetwork vnet-1 vnet-2 vnet-5 -n "$NS" --type=json \
  --patch-file="$POL/patches/vnet-irb-evpn-hostroutes-patch.json"

echo "==> Status"
kubectl get virtualnetwork vnet-1 vnet-2 vnet-3 vnet-4 vnet-5 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState
