#!/usr/bin/env bash
# Enable WAN EVPN for L2 BDI stitch (RT 300/301) while keeping VPNv4 for L3.
# Run after apply-l2-dci.sh (BDI Up) and apply-dci-policies.sh (base WAN policies).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")/../services/dci-policies" && pwd)"

echo "==> L2 stitch community sets"
kubectl apply -f "$DIR/communitysets/dci-service-rts.yaml"

echo "==> WAN import/export policies (L2 EVPN stitch RT 300/301)"
kubectl apply -f "$DIR/policies/import-dci-services-dc-1.yaml"
kubectl apply -f "$DIR/policies/import-dci-services-dc-2.yaml"
kubectl apply -f "$DIR/policies/export-dc-1-routes-and-add-soo.yaml"
kubectl apply -f "$DIR/policies/export-dc-2-routes-and-add-soo.yaml"
kubectl apply -f "$DIR/policies/export-dc-1-prefixes-and-add-soo.yaml"

echo "==> Enable l2VPNEVPN on DCGW WAN peers (VPNv4 stays on)"
for peer in dcgw-1-dcgw-3-bgp-peer dcgw-2-dcgw-4-bgp-peer \
            dcgw-3-dcgw-1-bgp-peer dcgw-4-dcgw-2-bgp-peer; do
  kubectl patch defaultbgppeer "$peer" -n "$NS" --type=json \
    --patch-file="$DIR/bgp-peers/wan-enable-evpn-patch.json"
done

echo "==> Status"
kubectl get defaultbgppeers -n "$NS" -o custom-columns=\
NAME:.metadata.name,EVPN:.spec.l2VPNEVPN.enabled,VPN:.spec.vpnIPv4Unicast.enabled,\
EXP:.spec.exportPolicies,IMP:.spec.importPolicies,STATE:.status.operationalState
kubectl get bridgedomaininterconnect bd-interconnect-vnet-3 bd-interconnect-vnet-4 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState,NODES:.status.nodes
