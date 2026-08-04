#!/usr/bin/env bash
# Deploy CLAB from eda-dci-lab/clab (bind paths relative to topology file).
set -eu
CLAB_DIR="$(cd "$(dirname "$0")/../clab" && pwd)"
TOPO="$CLAB_DIR/clab-leaf-spine-dcgw-srl-only.yaml"

if [ ! -f "$CLAB_DIR/configs/client-config.sh" ]; then
  echo "ERROR: missing $CLAB_DIR/configs/client-config.sh"
  exit 1
fi

if [ ! -d "$CLAB_DIR/configs/telemetry/gnmic" ]; then
  echo "NOTE: configs/telemetry/ missing — gnmic/prometheus/grafana binds will fail unless those nodes are removed from the YAML."
  echo "      cp -r ~/3-tier-dci/configs/telemetry $CLAB_DIR/configs/telemetry"
fi

cd "$CLAB_DIR"
echo "==> Deploy from $CLAB_DIR"
clab deploy -t "$(basename "$TOPO")"
