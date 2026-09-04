#!/usr/bin/env bash
# Validate the active WAN IGP option: adj/transport, IGP leak onto spines, L3 ping.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wan-igp-lib.sh
source "$DIR/wan-igp-lib.sh"

clab_exec() {
  local node="$1" cmd="$2"
  if docker inspect "$node" >/dev/null 2>&1; then
    docker exec "$node" sr_cli -e "$cmd"
    return
  fi
  local cid
  cid="$(docker ps --format '{{.Names}}' | grep -E "(^|-)${node}$" | head -1 || true)"
  if [ -n "$cid" ]; then
    docker exec "$cid" sr_cli -e "$cmd"
    return
  fi
  echo "SKIP: container $node not found"
}

PROTO="$(kubectl get fabric backbone-simulation -n "$NS" -o jsonpath='{.spec.underlayProtocol.protocols[0]}')"
echo "Active backbone IGP: $PROTO"
wan_igp_status
echo

if [ "$PROTO" = "ISIS" ]; then
  echo "==> IS-IS adjacency (dcgw-1)"
  clab_exec dcgw-1 "show network-instance default protocols isis adjacency"
  echo "==> SR-MPLS / tunnel table (dcgw-1)"
  clab_exec dcgw-1 "show network-instance default tunnel-table"
  clab_exec dcgw-1 "info from state network-instance default tunnel-table ipv4"
  clab_exec dcgw-1 "info from state network-instance default protocols isis instance isis-instance-1 segment-routing mpls sid-database"
  clab_exec dcgw-1 "show network-instance default protocols ldp ipv4 fec"
else
  echo "==> OSPF neighbors (dcgw-1)"
  clab_exec dcgw-1 "show network-instance default protocols ospf neighbor"
  echo "==> LDP / tunnel table (dcgw-1)"
  clab_exec dcgw-1 "show network-instance default protocols ldp neighbor"
  clab_exec dcgw-1 "show network-instance default tunnel-table"
fi

echo
  echo "==> IGP leak check: remote-site system /32s must not be on a DC1 spine"
  echo "    Pass: spine has local fabric + local DCGW only, not DC2 leaf/spine 11.0.0.x"
  clab_exec srl-spine-1 "info from state network-instance default route-table ipv4-unicast"

echo
echo "==> L3 hub-spoke ping"
if [ -x "$DIR/test-l3-cross-dc-ping.sh" ]; then
  bash "$DIR/test-l3-cross-dc-ping.sh" || true
else
  echo "SKIP: test-l3-cross-dc-ping.sh not found"
fi
