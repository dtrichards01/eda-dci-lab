#!/usr/bin/env bash
# Read-only: L2 DCI loop-avoidance settings on dcgw-1..4 (bd-3 on DC1, bd-4 on DC2).
set -u
cli() { docker exec "$1" sr_cli -e "$2" 2>&1; }

for n in dcgw-1 dcgw-2 dcgw-3 dcgw-4; do
  echo "################ $n"
  cli "$n" "show network-instance summary" | grep -Ei 'mac-vrf'
  for ni in $(cli "$n" "show network-instance summary" | awk '/mac-vrf/ {print $2}'); do
    echo "======== $n $ni bgp-evpn / bgp-vpn"
    cli "$n" "info network-instance $ni protocols bgp-evpn"
    cli "$n" "info network-instance $ni protocols bgp-vpn"
    cli "$n" "info from state network-instance $ni protocols bgp-vpn bgp-instance * route-distinguisher"
  done
  echo "======== $n system evpn ethernet-segments"
  cli "$n" "info system network-instance protocols evpn"
  cli "$n" "show system network-instance ethernet-segments"
  echo "======== $n system0 / loopbacks"
  cli "$n" "show interface brief" | grep -Ei 'system0|lo[0-9]'
done
