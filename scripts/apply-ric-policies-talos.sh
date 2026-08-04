#!/usr/bin/env bash
set -eu
NS=clab-srl-leaf-spine-dcgw
kubectl apply -f /tmp/ric-apply/router-interconnect-vnet-1.yaml
kubectl apply -f /tmp/ric-apply/router-interconnect-vnet-2.yaml
kubectl apply -f /tmp/ric-apply/router-interconnect-vnet-5.yaml
sleep 20
PATCH='[{"op":"remove","path":"/spec/interconnectBGPInstance/importTarget"},{"op":"remove","path":"/spec/interconnectBGPInstance/exportTarget"}]'
for r in router-interconnect-vnet-1 router-interconnect-vnet-2 router-interconnect-vnet-5; do
  kubectl patch routerinterconnect "$r" -n "$NS" --type=json -p "$PATCH" 2>/dev/null || true
done
sleep 20
kubectl get routerinterconnects -n "$NS" -o custom-columns=NAME:.metadata.name,IMPORT:.spec.interconnectBGPInstance.importPolicy,EXPORT:.spec.interconnectBGPInstance.exportPolicy,IT:.spec.interconnectBGPInstance.importTarget,ET:.spec.interconnectBGPInstance.exportTarget,STATE:.status.operationalState
