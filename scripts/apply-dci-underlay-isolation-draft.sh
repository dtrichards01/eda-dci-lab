#!/usr/bin/env bash
# Phase 1 underlay: WAN VPNv4 only, no EVPN fabric leak across DCGW peering.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
U="$ROOT/services/dci-policies/draft/underlay"

echo "==> [UNDERLAY] Strict WAN import (VPNv4 only, default Reject)"
kubectl apply -f "$U/import-dci-services-dc-1-underlay.yaml"
kubectl apply -f "$U/import-dci-services-dc-2-underlay.yaml"

echo "==> [UNDERLAY] Strict WAN export (VPNv4 vnet-1/2 only, default Reject)"
kubectl apply -f "$U/export-dc-1-prefixes-underlay.yaml"
kubectl apply -f "$U/export-dc-2-prefixes-underlay.yaml"

echo "==> Wait for policy intent"
sleep 15

echo "==> [UNDERLAY] Disable EVPN AF on all four WAN DefaultBGPPeers"
for peer in dcgw-1-dcgw-3-bgp-peer dcgw-2-dcgw-4-bgp-peer \
            dcgw-3-dcgw-1-bgp-peer dcgw-4-dcgw-2-bgp-peer; do
  kubectl patch defaultbgppeer "$peer" -n "$NS" --type=json \
    --patch-file="$U/wan-disable-evpn-patch.json" 2>/dev/null || \
    echo "WARN: patch failed for $peer (check name)"
done

echo "==> Verify peers"
kubectl get defaultbgppeers -n "$NS" -o custom-columns=\
NAME:.metadata.name,IMPORT:.spec.importPolicies,EXPORT:.spec.exportPolicies,\
EVPN:.spec.l2VPNEVPN.enabled,VPN:.spec.vpnIPv4Unicast.enabled,NHS:.spec.nextHopSelf

echo ""
echo "On dcgw-1: check default NI — remote 11.0.0.x should be dcgw-3/4 only."
echo "See $U/README-UNDERLAY-ISOLATION.md"
echo "Revert: bash $ROOT/scripts/revert-dci-underlay-isolation-draft.sh"
