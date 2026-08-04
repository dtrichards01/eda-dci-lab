#!/usr/bin/env bash
# DEPRECATED — cross-DC BridgeDomainDeployment breaks native vnet ownership.
# L2 DCI uses reciprocal BDI RT import only. See docs/L2-DCI-GUIDE.md
set -eu
echo "==> apply-dcgw-import-routers.sh is deprecated for vnet-3/4 L2 DCI."
echo "    Running cleanup-l2-bd-deployments.sh instead."
exec bash "$(dirname "$0")/cleanup-l2-bd-deployments.sh"
