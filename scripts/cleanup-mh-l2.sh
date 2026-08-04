#!/usr/bin/env bash
# Remove MH L2 + aggregated L3 CRs and strip stale LAG labels.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

exec bash "$ROOT/scripts/cleanup-mh-stale.sh"
