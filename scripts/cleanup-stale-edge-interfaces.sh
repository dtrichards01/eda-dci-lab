#!/usr/bin/env bash
# Remove edge Interface CRs not wired in CLAB; fix stale stretched-leg labels on e1-6.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$DIR/.."

echo "==> Standalone leaf e1-10 (MH LAG owns these members)"
for leaf in 1 2 3 4 5 6 7 8; do
  kubectl delete interface "srl-leaf-${leaf}-ethernet-1-10" -n "$NS" 2>/dev/null || true
done

echo "==> Orphan e1-5 (no CLAB client)"
kubectl delete interface srl-leaf-2-ethernet-1-5 -n "$NS" 2>/dev/null || true
kubectl delete interface srl-leaf-6-ethernet-1-5 -n "$NS" 2>/dev/null || true
kubectl delete interface srl-leaf-7-ethernet-1-5 -n "$NS" 2>/dev/null || true

echo "==> Obsolete interface names"
kubectl delete interface srl-leaf-5-ethernet-1-6-sh -n "$NS" 2>/dev/null || true

echo "==> Re-apply all wired edge labels (explicit files — corrects stale stretched-leg labels)"
bash "$DIR/apply-edge-interfaces.sh"

echo "==> Verify e1-6 edge labels"
kubectl get interface srl-leaf-2-ethernet-1-6 srl-leaf-3-ethernet-1-6 \
  srl-leaf-5-ethernet-1-6 srl-leaf-8-ethernet-1-6 -n "$NS" \
  -o custom-columns=NAME:.metadata.name,LABELS:.metadata.labels 2>/dev/null || true
echo "==> Done"
