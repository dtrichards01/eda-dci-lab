#!/usr/bin/env bash
# Remove cross-DC BridgeDomainDeployment CRs — not used in reciprocal BDI L2 model.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"

echo "==> Delete import-side BD deployments (bd-3 on DC2 DCGW, bd-4 on DC1 DCGW)"
kubectl delete bridgedomaindeployment \
  dcgw-1-bd-4 dcgw-2-bd-4 dcgw-3-bd-3 dcgw-4-bd-3 \
  -n "$NS" --ignore-not-found --wait=true

echo "==> Status"
kubectl get bridgedomaindeployment -n "$NS" 2>/dev/null || echo "(none)"
kubectl get virtualnetwork vnet-3 vnet-4 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,NODES:.status.nodes
kubectl get bridgedomain bd-3 bd-4 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,NODES:.status.nodes
