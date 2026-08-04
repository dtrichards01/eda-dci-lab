#!/usr/bin/env bash
# Apply full aligned DCI lab (native L3/L2, SH, MH L3 per-ES, edges, policies).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
NS="${NS:-clab-srl-leaf-spine-dcgw}"

echo "==> Cleanup stale edges + MH orphans"
bash "$DIR/cleanup-stale-edge-interfaces.sh"
bash "$DIR/cleanup-mh-stale.sh"
bash "$DIR/cleanup-obsolete-dci.sh"

echo "==> Topology CRs (ISL + edge TopoLinks) — skip if already Up"
if [ -f "$DIR/../clab/eda-topology/interfaces-isl.yaml" ]; then
  bash "$DIR/apply-topology-cr.sh" || true
fi

bash "$DIR/apply-fabric-mpls.sh"
bash "$DIR/apply-clab-vnets.sh"
bash "$DIR/apply-wan-bgp.sh"

bash "$DIR/apply-l3-dci.sh"
bash "$DIR/apply-l2-dci.sh"
bash "$DIR/apply-sh-dci.sh"
bash "$DIR/apply-mh-dci.sh"
bash "$DIR/apply-vnet-5-hub-spoke.sh"
bash "$DIR/apply-dcgw-import-routers.sh"
bash "$DIR/apply-edge-interfaces.sh"
bash "$DIR/apply-dci-policies.sh"

echo "==> Summary"
kubectl get virtualnetwork -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState
kubectl get interfaces -n "$NS" -o custom-columns=NAME:.metadata.name,STATE:.status.operationalState | grep -E 'mh-dc|ethernet-1-[56]' || true
