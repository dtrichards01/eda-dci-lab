#!/usr/bin/env bash
# Remove stretched-leg and interconnect-policy CRs superseded by native RIC RT / hub importPolicy.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"

echo "==> Obsolete interconnect policies"
for p in import-dci-interconnect \
         export-dci-interconnect-native-dc-1 \
         export-dci-interconnect-native-dc-2 \
         dci-interconnect-import-only-export \
         export-dci-interconnect-permissive \
         import-spoke-vnet-5-block-vnet-1; do
  kubectl delete policy "$p" -n "$NS" --ignore-not-found
done

echo "==> Obsolete stretched RouterInterconnect legs"
for r in router-interconnect-vnet-1-dc2-import \
         router-interconnect-vnet-2-dc1-import; do
  kubectl delete routerinterconnect "$r" -n "$NS" --ignore-not-found
done

echo "==> Obsolete remote RouterDeployments (native cross-vnet uses RIC only)"
for r in dcgw-1-router-2 dcgw-2-router-2 \
         dcgw-3-router-1 dcgw-4-router-1 \
         dcgw-3-router-3 dcgw-4-router-3; do
  kubectl delete routerdeployment "$r" -n "$NS" --ignore-not-found
done

echo "==> Obsolete edge Interface CRs (wrong leaf / duplicate naming)"
kubectl delete interface srl-leaf-5-ethernet-1-6-sh -n "$NS" 2>/dev/null || true
# Stretched legs removed: vnet-1 on leaf-8 e1-6, vnet-4 on leaf-5 e1-6 — labels fixed via cleanup-stale-edge-interfaces.sh

echo "==> Done"
