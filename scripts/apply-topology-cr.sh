#!/usr/bin/env bash
# Apply generated TopoLink + ISL/WAN Interface CRs after CLAB re-import / integrate.
# Regenerate first if clab YAML changed: python3 clab/eda-topology/gen_clab_eda_cr.py
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
TOPO="$DIR/../clab/eda-topology"

if [[ ! -f "$TOPO/topolinks-isl.yaml" ]]; then
  echo "Missing $TOPO/topolinks-isl.yaml — run: python3 $TOPO/gen_clab_eda_cr.py"
  exit 1
fi

echo "==> ISL interfaces (leaf/spine, dcgw/spine, dcgw mesh)"
kubectl apply -f "$TOPO/interfaces-isl.yaml"

echo "==> ISL topolinks"
kubectl apply -f "$TOPO/topolinks-isl.yaml"

echo "==> WAN interfaces (dcgw <-> sros-pe)"
kubectl apply -f "$TOPO/interfaces-wan.yaml"

echo "==> WAN topolinks"
kubectl apply -f "$TOPO/topolinks-wan.yaml"

echo "==> Edge topolinks (clients -> leaves; wait for client TopoNodes after integrate)"
kubectl apply -f "$TOPO/topolinks-edge.yaml"

echo "==> TopoLink summary"
kubectl get topolinks -n "$NS" 2>/dev/null | head -20 || true
echo "..."
kubectl get topolinks -n "$NS" --no-headers 2>/dev/null | wc -l | xargs -r echo "total topolinks:"
