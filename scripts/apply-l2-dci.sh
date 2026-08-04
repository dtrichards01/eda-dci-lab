#!/usr/bin/env bash
# L2 DCI: native edge labels + BridgeDomainInterconnect on native DCGWs.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> L2 edge interface labels (native vnet-3 DC1, vnet-4 DC2)"
kubectl apply -f "$ROOT/services/l2/interface-labels/edge-l2-vnet-3-4.yaml"

echo "==> BridgeDomainInterconnect (EVPN-VXLAN fabric -> EVPN-MPLS on DCGW)"
kubectl apply -f "$ROOT/services/l2/bridge-domain-interconnect/bd-interconnect-vnet-3.yaml"
kubectl apply -f "$ROOT/services/l2/bridge-domain-interconnect/bd-interconnect-vnet-4.yaml"

echo "==> Import-side BridgeDomainDeployment on remote DCGWs"
kubectl apply -f "$ROOT/services/l2/bridge-domain-deployments/"

echo "==> Status"
kubectl get bridgedomains -n "$NS" -o custom-columns=NAME:.metadata.name,EVI:.status.evi,STATE:.status.operationalState,NODES:.status.nodes
kubectl get bridgedomaininterconnects -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState,NODES:.status.nodes
kubectl get bridgedomaindeployments -n "$NS"
kubectl get virtualnetwork vnet-3 vnet-4 -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState
