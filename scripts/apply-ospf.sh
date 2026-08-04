#!/usr/bin/env bash
# Apply Default OSPF instances, areas, and system interfaces (WAN underlay).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OSPF="$DIR/../clab/eda-ospf"

echo "==> DefaultOSPFInstance (ospf-instance-1 DC1, ospf-instance-2 DC2)"
kubectl apply -f "$OSPF/defaultospfinstances.yaml"

echo "==> DefaultOSPFArea (backbone-0)"
kubectl apply -f "$OSPF/defaultospfareas.yaml"

echo "==> DefaultOSPFInterface (dcgw system0 — passive)"
kubectl apply -f "$OSPF/defaultospfinterfaces.yaml"

echo "==> Status"
kubectl get defaultospfinstances,defaultospfareas,defaultospfinterfaces -n "$NS"
