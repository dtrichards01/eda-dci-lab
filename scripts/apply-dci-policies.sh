#!/usr/bin/env bash
# DCI import/export policies + VPN-IPv4 on DCGW inter-DC BGP peers.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")/../services/dci-policies" && pwd)"

echo "==> Community sets (service RTs)"
kubectl apply -f "$DIR/communitysets/"

echo "==> Hub multi-RT import (vnet-1 + vnet-5 spokes)"
kubectl apply -f "$DIR/policies/multi-rt-import.yaml"
kubectl apply -f "$DIR/policies/import-dci-services-dc-1.yaml"
kubectl apply -f "$DIR/policies/import-dci-services-dc-2.yaml"
kubectl apply -f "$DIR/policies/import-dci-hub-stitch.yaml"
kubectl apply -f "$DIR/policies/import-dci-hub-spoke-stitch.yaml"
kubectl apply -f "$DIR/policies/export-dci-stitch-dc1-vnet-1.yaml"
kubectl apply -f "$DIR/policies/export-dci-stitch-dc2-hub.yaml"
kubectl apply -f "$DIR/policies/export-dci-stitch-vnet-5.yaml"
kubectl apply -f "$DIR/policies/export-wan-routes-only-dc-1.yaml"
kubectl apply -f "$DIR/policies/export-wan-routes-only-dc-2.yaml"
kubectl apply -f "$DIR/policies/export-dc-1-routes-and-add-soo.yaml"
kubectl apply -f "$DIR/policies/export-dc-2-routes-and-add-soo.yaml"

echo "==> Remove obsolete interconnect / stretched-leg CRs"
bash "$(dirname "$0")/cleanup-obsolete-dci.sh"

echo "==> Enable VPN-IPv4 on DCI BGP groups"
kubectl patch defaultbgpgroup default-bgp-group-dc-1 -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/default-bgp-group-dc-1-vpn-patch.json"
kubectl patch defaultbgpgroup default-bgp-group-dc-2 -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/default-bgp-group-dc-2-vpn-patch.json"

echo "==> Patch DCGW<->DCGW BGP peers (import policy + VPN-IPv4)"
kubectl patch defaultbgppeer dcgw-1-dcgw-3-bgp-peer -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/dcgw-1-dcgw-3-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-2-dcgw-4-bgp-peer -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/dcgw-2-dcgw-4-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-3-dcgw-1-bgp-peer -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/dcgw-3-dcgw-1-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-4-dcgw-2-bgp-peer -n "$NS" --type=json \
  --patch-file="$DIR/bgp-peers/dcgw-4-dcgw-2-import-vpn-patch.json"

echo "==> Status"
kubectl get communitysets -n "$NS" | grep dci-rt || true
kubectl get policys -n "$NS" | grep -E 'import-dci|export-dc|export-wan' || true
kubectl get defaultbgppeers -n "$NS" -o custom-columns=NAME:.metadata.name,IMPORT:.spec.importPolicies,EXPORT:.spec.exportPolicies,EVPN:.spec.l2VPNEVPN.enabled,VPNV4:.spec.vpnIPv4Unicast.enabled
