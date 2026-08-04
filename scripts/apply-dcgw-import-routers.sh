#!/usr/bin/env bash
# L2 import-side bridge domains on remote DCGWs (post-restore).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> BridgeDomainDeployment: bd-3 on DC2, bd-4 on DC1 DCGWs"
kubectl apply -f "$ROOT/services/l2/bridge-domain-deployments/"

echo "==> Status"
kubectl get bridgedomaindeployments -n "$NS"
