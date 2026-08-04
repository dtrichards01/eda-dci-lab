#!/usr/bin/env bash
# Remove stale MH L2 + aggregated L3 CRs and delete orphan YAML that EDA re-applies.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="${ROOT:-$HOME/eda-dci-lab}"

echo "==> Cluster: delete MH L2 + aggregated L3 CRs"
kubectl delete virtualnetwork vnet-mh-l2-100 vnet-mh-l2-110 \
  vnet-mh-l3-dc1 vnet-mh-l3-dc2 -n "$NS" 2>/dev/null || true

for b in bd-interconnect-mh-l2-100-dc1 bd-interconnect-mh-l2-100-dc2 \
         bd-interconnect-mh-l2-110-dc1 bd-interconnect-mh-l2-110-dc2; do
  kubectl delete bridgedomaininterconnect "$b" -n "$NS" 2>/dev/null || true
done

for b in dcgw-1-bd-mh-100 dcgw-2-bd-mh-100 dcgw-3-bd-mh-100 dcgw-4-bd-mh-100 \
         dcgw-1-bd-mh-110 dcgw-2-bd-mh-110 dcgw-3-bd-mh-110 dcgw-4-bd-mh-110; do
  kubectl delete bridgedomaindeployment "$b" -n "$NS" 2>/dev/null || true
done

kubectl delete routerinterconnect router-interconnect-mh-l3-dc1 router-interconnect-mh-l3-dc2 \
  -n "$NS" 2>/dev/null || true

echo "==> Remove orphan YAML (SCP leftovers — EDA keeps re-applying these)"
rm -f "$ROOT/virtualnetwork-vnet-mh-l3-dc1.yaml" \
      "$ROOT/virtualnetwork-vnet-mh-l3-dc2.yaml" \
      "$ROOT/virtualnetwork-vnet-mh-l2-"*.yaml \
      "$ROOT/router-interconnect-mh-l3-dc1.yaml" \
      "$ROOT/router-interconnect-mh-l3-dc2.yaml" \
      "$ROOT/edge-mh-lags.yaml" \
      "$ROOT/bd-interconnect-mh-l2-"*.yaml \
      "$ROOT/dcgw-"*-bd-mh-*.yaml \
      "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc1.yaml" \
      "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc2.yaml" \
      "$ROOT/services/mh/virtualnetwork-vnet-mh-l2-"*.yaml \
      "$ROOT/services-tmp-sync/bd-interconnect-mh-l2-"*.yaml \
rm -f "$ROOT/services/l3/interface-labels/dcgw-"*-bd-mh-*.yaml \
      "$ROOT/services/l3/interface-labels/bd-interconnect-mh-l2-"*.yaml \
      "$ROOT/services/l3/interface-labels/virtualnetwork-vnet-mh-"*.yaml \
      "$ROOT/services/l3/interface-labels/virtualnetwork-vnet-7.yaml" \
      "$ROOT/services/l3/interface-labels/edge-l3-vnet-1-dc2.yaml" \
      "$ROOT/services/l3/interface-labels/edge-l3-vnet-2-dc1.yaml" 2>/dev/null || true

echo "==> Re-apply current per-ES MH L3 (safe)"
kubectl apply -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc1a.yaml" \
  -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc1b.yaml" \
  -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc2a.yaml" \
  -f "$ROOT/services/mh/virtualnetwork-vnet-mh-l3-dc2b.yaml" \
  -f "$ROOT/services/mh/router-interconnect-mh-l3-dc1.yaml" \
  -f "$ROOT/services/mh/router-interconnect-mh-l3-dc2.yaml" \
  -f "$ROOT/services/mh/interface-labels/edge-mh-lags.yaml"

echo "==> MH vnets on cluster"
kubectl get virtualnetwork -n "$NS" | grep mh || echo "(none)"
echo "==> Stale root YAML remaining"
ls "$ROOT"/*mh* 2>/dev/null || echo "(none — good)"
