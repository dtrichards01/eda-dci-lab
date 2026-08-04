#!/usr/bin/env bash
# Revert vnet-1 / vnet-2 DRAFT WAN policies to production.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROD="$ROOT/services/dci-policies"
RIC="$ROOT/services/l3/router-interconnect"

echo "==> Restore production WAN import policies"
kubectl apply -f "$PROD/policies/import-dci-services-dc-1.yaml"
kubectl apply -f "$PROD/policies/import-dci-services-dc-2.yaml"
kubectl apply -f "$PROD/policies/export-dci-stitch-dc1-vnet-1.yaml"
kubectl apply -f "$PROD/policies/export-dci-stitch-dc2-hub.yaml"

echo "==> Restore production WAN secondary peers"
kubectl patch defaultbgppeer dcgw-2-dcgw-4-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-2-dcgw-4-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-4-dcgw-2-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-4-dcgw-2-import-vpn-patch.json"

echo "==> Restore primary WAN peers"
kubectl patch defaultbgppeer dcgw-1-dcgw-3-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-1-dcgw-3-import-vpn-patch.json"
kubectl patch defaultbgppeer dcgw-3-dcgw-1-bgp-peer -n "$NS" --type=json \
  --patch-file="$PROD/bgp-peers/dcgw-3-dcgw-1-import-vpn-patch.json"

echo "==> Restore production RouterInterconnect vnet-1 + vnet-2"
kubectl apply -f "$RIC/router-interconnect-vnet-1.yaml"
kubectl apply -f "$RIC/router-interconnect-vnet-2.yaml"
sleep 20

echo "==> Delete draft-only Policy CRs"
kubectl delete policy import-dci-hub-stitch-prefix -n "$NS" --ignore-not-found
kubectl delete policy import-dci-hub-vnet-1-stitch -n "$NS" --ignore-not-found
kubectl delete policy export-dc-1-routes-wan-dcgw -n "$NS" --ignore-not-found
kubectl delete policy export-dc-2-routes-wan-dcgw -n "$NS" --ignore-not-found

echo "==> Production vnet-1 / vnet-2 DCI restored."
