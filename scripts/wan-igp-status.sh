#!/usr/bin/env bash
# Show which WAN IGP option is active (OSPF+LDP vs ISIS+SR-MPLS).
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wan-igp-lib.sh
source "$DIR/wan-igp-lib.sh"
wan_igp_status
echo "==> RIC tunnel types (first RIC)"
kubectl get routerinterconnect router-interconnect-vnet-1 -n "$NS" \
  -o jsonpath='vnet-1 tunnels={.spec.interconnectBGPInstance.mpls.allowedTunnelTypes}{"\n"}' 2>/dev/null || true
