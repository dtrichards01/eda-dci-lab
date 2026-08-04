#!/usr/bin/env bash
# Apply WAN DefaultBGPGroup + DefaultBGPPeer CRs (DCGW1..4 inter-DC peering).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
BGP="$DIR/../clab/eda-wan-bgp"

echo "==> DefaultBGPGroup DC1 + DC2"
kubectl apply -f "$BGP/defaultbgpgroups.yaml"

echo "==> DefaultBGPPeer (dcgw-1..4 WAN mesh)"
kubectl apply -f "$BGP/defaultbgppeers.yaml"

echo "==> Status"
kubectl get defaultbgpgroups -n "$NS"
kubectl get defaultbgppeers -n "$NS" -o custom-columns=NAME:.metadata.name,PEER:.spec.peerIP,EXP:.spec.exportPolicies,IMP:.spec.importPolicies,VPN:.spec.vpnIPv4Unicast.enabled,EVPN:.spec.l2VPNEVPN.enabled,STATE:.status.operationalState
