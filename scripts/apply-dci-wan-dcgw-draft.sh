#!/usr/bin/env bash
# Apply DRAFT WAN policies: vnet-1 / vnet-2 L3 only, DCGW next-hop.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRAFT="$ROOT/services/dci-policies/draft"

echo "==> [DRAFT] WAN export + import (vnet-1 / vnet-2 only, default Reject)"
kubectl apply -f "$DRAFT/policies/export-dc-1-routes-wan-dcgw.yaml"
kubectl apply -f "$DRAFT/policies/export-dc-2-routes-wan-dcgw.yaml"
kubectl apply -f "$DRAFT/policies/import-dci-services-dc-1-vnet-only.yaml"
kubectl apply -f "$DRAFT/policies/import-dci-services-dc-2-vnet-only.yaml"
# Optional: in-place replace if peer references export-dc-1-prefixes-and-add-soo
kubectl apply -f "$DRAFT/policies/export-dc-1-prefixes-wan-dcgw.yaml" 2>/dev/null || true

echo "==> [DRAFT] Hub import vnet-1 only + spoke hub import prefix-only"
kubectl apply -f "$DRAFT/policies/import-dci-hub-vnet-1-stitch.yaml"
kubectl apply -f "$DRAFT/policies/import-dci-hub-stitch-prefix.yaml"

echo "==> [DRAFT] RIC stitch export (type-5 + VPNv4 only)"
kubectl apply -f "$DRAFT/policies/export-dci-stitch-dc1-vnet-1-l3.yaml"
kubectl apply -f "$DRAFT/policies/export-dci-stitch-dc2-hub-l3.yaml"

echo "==> Wait for policy intent"
sleep 15

echo "==> [DRAFT] RouterInterconnect vnet-1 + vnet-2"
kubectl apply -f "$DRAFT/router-interconnect/router-interconnect-vnet-1-draft.yaml"
kubectl apply -f "$DRAFT/router-interconnect/router-interconnect-vnet-2-draft.yaml"
sleep 20

echo "==> [DRAFT] WAN BGP — export policy only (nextHopSelf often already true on peers)"
echo "    If your peer uses export-dc-1-prefixes-and-add-soo, patch exportPolicies manually"
echo "    or apply draft/policies/export-dc-1-prefixes-wan-dcgw.yaml (same name, new rules)."

echo "==> [DRAFT] Secondary WAN links → wan-dcgw export policies (repo naming)"
kubectl patch defaultbgppeer dcgw-2-dcgw-4-bgp-peer -n "$NS" --type=json \
  --patch-file="$DRAFT/bgp-peers/dcgw-2-dcgw-4-export-wan-dcgw-draft.json"
kubectl patch defaultbgppeer dcgw-4-dcgw-2-bgp-peer -n "$NS" --type=json \
  --patch-file="$DRAFT/bgp-peers/dcgw-4-dcgw-2-export-wan-dcgw-draft.json"

echo "==> Verify"
kubectl get defaultbgppeers -n "$NS" -o custom-columns=\
NAME:.metadata.name,EXPORT:.spec.exportPolicies,NHS:.spec.nextHopSelf
kubectl get routerinterconnects -n "$NS" -o custom-columns=\
NAME:.metadata.name,IMPORT:.spec.interconnectBGPInstance.importPolicy,\
EXPORT:.spec.interconnectBGPInstance.exportPolicy

echo ""
echo "See services/dci-policies/draft/README-DCGW-WAN-DRAFT.md"
echo "Revert: bash $ROOT/scripts/revert-dci-wan-dcgw-draft.sh"
