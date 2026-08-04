#!/usr/bin/env bash
# Apply Fabric, ISL, and MPLS/LDP CRs from cluster export.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FABRIC="$DIR/../clab/eda-fabric"
MPLS="$DIR/../clab/eda-mpls-ldp"

echo "==> Label blocks (LDP)"
kubectl apply -f "$MPLS/labelblocks.yaml"

echo "==> Fabrics (backbone-simulation, pod-1, pod-2)"
kubectl apply -f "$FABRIC/fabrics.yaml"

echo "==> MPLS/LDP routers"
kubectl apply -f "$MPLS/defaultldprouters.yaml"

echo "==> MPLS/LDP interfaces"
kubectl apply -f "$MPLS/defaultldpinterfaces.yaml"

echo "==> Fabric ISLs (DCGW mesh + PE WAN)"
kubectl apply -f "$FABRIC/isls.yaml"

echo "==> Status"
kubectl get fabrics,isls -n "$NS"
kubectl get defaultldprouters,defaultldpinterfaces,labelblocks -n "$NS" 2>/dev/null | head -25
