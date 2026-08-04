#!/usr/bin/env bash
# Restore production WAN import/export + re-enable EVPN on WAN peers.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROD="$ROOT/services/dci-policies"

echo "==> Restore production WAN import policies"
kubectl apply -f "$PROD/policies/import-dci-services-dc-1.yaml"
kubectl apply -f "$PROD/policies/import-dci-services-dc-2.yaml"

echo "==> Restore production WAN export (repo names)"
kubectl apply -f "$PROD/policies/export-dc-1-routes-and-add-soo.yaml"
kubectl apply -f "$PROD/policies/export-dc-2-routes-and-add-soo.yaml"

echo "==> Re-enable EVPN + restore peer patches from repo"
kubectl patch defaultbgppeer dcgw-1-dcgw-3-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-1-dcgw-3-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-2-dcgw-4-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-2-dcgw-4-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-3-dcgw-1-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-3-dcgw-1-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-4-dcgw-2-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-4-dcgw-2-import-vpn-patch.json"

for peer in dcgw-1-dcgw-3-bgp-peer dcgw-2-dcgw-4-bgp-peer \
            dcgw-3-dcgw-1-bgp-peer dcgw-4-dcgw-2-bgp-peer; do
  kubectl patch defaultbgppeer "$peer" -n "$NS" --type=json \
    --patch='[{"op":"replace","path":"/spec/l2VPNEVPN/enabled","value":true}]' 2>/dev/null || true
done

echo "==> Underlay isolation draft reverted (verify export-dc-1-prefixes-and-add-soo manually if needed)."
