#!/usr/bin/env bash
# Apply Default ISIS instances, system interfaces, and SR-MPLS pools (WAN option 2 CRs).
# Does not cut over the live OSPF WAN — use switch-wan-isis.sh for that.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ISIS="$DIR/../clab/eda-isis"
SR="$DIR/../clab/eda-sr-mpls"
POL="$DIR/../services/dci-policies/policies"

echo "==> SRGB + node SID pool"
kubectl apply -f "$SR/labelblocks.yaml"
kubectl apply -f "$SR/indexallocationpools.yaml"

echo "==> DefaultISISInstance (isis-instance-1 DC1, isis-instance-2 DC2, SR-MPLS)"
kubectl apply -f "$ISIS/defaultisisinstances.yaml"

echo "==> DefaultISISInterface (dcgw system0 — passive)"
kubectl apply -f "$ISIS/defaultisisinterfaces.yaml"

echo "==> Isolation policy reject-igp-to-fabric (OSPFv2 + ISIS)"
kubectl apply -f "$POL/reject-igp-to-fabric.yaml"

echo "==> Status"
kubectl get defaultisisinstances,defaultisisinterfaces,labelblocks,indexallocationpools -n "$NS" | grep -E 'isis|srgb|sr-node' || true
