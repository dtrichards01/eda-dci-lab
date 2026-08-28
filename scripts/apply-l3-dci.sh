#!/usr/bin/env bash
# L3 DCI: RouterInterconnect on native DCGWs (no stretched import legs).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")/../services/l3/router-interconnect" && pwd)"
POL="$(cd "$(dirname "$0")/../services/dci-policies" && pwd)"

echo "==> Patch VirtualNetworks: router BGP ASN + ipv4Unicast"
kubectl patch virtualnetwork vnet-1 -n "$NS" --type=json \
  --patch-file="$DIR/vnet-1-router-bgp-patch.json"
kubectl patch virtualnetwork vnet-1 -n "$NS" --type=json \
  --patch-file="$DIR/vnet-1-router-bgp-ipv4-patch.json"
kubectl patch virtualnetwork vnet-2 -n "$NS" --type=json \
  --patch-file="$DIR/vnet-2-router-bgp-patch.json"
kubectl patch virtualnetwork vnet-2 -n "$NS" --type=json \
  --patch-file="$DIR/vnet-2-router-bgp-ipv4-patch.json"

echo "==> Hub multi-RT import policy (spoke RTs 100 + 105)"
kubectl apply -f "$POL/communitysets/vpn-import-rts.yaml"
kubectl apply -f "$POL/policies/multi-rt-import.yaml"

echo "==> RouterInterconnect (EVPN-VXLAN -> IPVPN-MPLS on DCGW)"
kubectl apply -f "$DIR/router-interconnect-vnet-1.yaml"
kubectl apply -f "$DIR/router-interconnect-vnet-2.yaml"

echo "==> Status"
kubectl get routerinterconnects -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState,NODES:.status.nodes
