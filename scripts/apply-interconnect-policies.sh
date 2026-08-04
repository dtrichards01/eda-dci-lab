#!/usr/bin/env bash
# Apply interconnect policies to RouterInterconnect on SRL DCGW (X1B).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POL="$ROOT/services/dci-policies"
RIC="$ROOT/services/l3/router-interconnect"

echo "==> Community sets"
kubectl apply -f "$POL/communitysets/"

echo "==> Interconnect stitch policies (Policy CR)"
kubectl apply -f "$POL/policies/import-dci-hub-stitch.yaml"
kubectl apply -f "$POL/policies/import-dci-hub-spoke-stitch.yaml"
kubectl apply -f "$POL/policies/export-dci-stitch-dc1-vnet-1.yaml"
kubectl apply -f "$POL/policies/export-dci-stitch-dc2-hub.yaml"
kubectl apply -f "$POL/policies/export-dci-stitch-vnet-5.yaml"

echo "==> Wait for policy intent"
sleep 15

echo "==> RouterInterconnect with importPolicy/exportPolicy"
for f in router-interconnect-vnet-1.yaml router-interconnect-vnet-2.yaml router-interconnect-vnet-5.yaml; do
  echo "--- applying $f ---"
  kubectl apply -f "$RIC/$f"
  sleep 20
done

echo "==> Verify CR spec (must show policies, not route targets)"
kubectl get routerinterconnects -n "$NS" -o custom-columns=\
NAME:.metadata.name,\
IMPORT:.spec.interconnectBGPInstance.importPolicy,\
EXPORT:.spec.interconnectBGPInstance.exportPolicy,\
IT:.spec.interconnectBGPInstance.importTarget,\
ET:.spec.interconnectBGPInstance.exportTarget,\
STATE:.status.operationalState

echo "==> Latest transaction"
kubectl get transactionresults -n eda-system --sort-by=.metadata.creationTimestamp | tail -3
