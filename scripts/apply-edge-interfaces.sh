#!/usr/bin/env bash

# Apply all edge Interface labels for CLAB client topology (13 clients + 4 MH LAGs).

set -eu

NS="${NS:-clab-srl-leaf-spine-dcgw}"

DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$DIR/.."

L3="$ROOT/services/l3/interface-labels"



echo "==> L2 edge labels (vnet-3 / vnet-4)"

kubectl apply -f "$ROOT/services/l2/interface-labels/edge-l2-vnet-3-4.yaml"



echo "==> L3 native + SH edge labels (explicit files only — no directory apply)"

kubectl apply -f "$L3/edge-l3-vnet-1-dc1.yaml" \

  -f "$L3/edge-l3-vnet-2-dc2.yaml" \

  -f "$L3/edge-l3-vnet-5-dc1.yaml" \

  -f "$L3/edge-sh-vnet-6-7.yaml"



echo "==> MH ESI LAG edges"

kubectl apply -f "$ROOT/services/mh/interface-labels/edge-mh-lags.yaml"



echo "==> Edge interface status"

kubectl get interfaces -n "$NS" 2>/dev/null | grep -E 'ethernet-1-[56]|mh-dc' || true

