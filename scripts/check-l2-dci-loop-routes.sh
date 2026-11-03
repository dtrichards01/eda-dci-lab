#!/usr/bin/env bash
# Read-only: system0 IPs, and how the remote DC sees the L2 DCI routes (RD, next-hop, path count).
set -u
cli() { docker exec "$1" sr_cli -e "$2" 2>&1; }

for n in dcgw-1 dcgw-2 dcgw-3 dcgw-4; do
  echo "== $n system0"
  cli "$n" "show interface system0" | grep -E '/32'
done

for pair in "dcgw-4 11.0.0.7:110" "dcgw-2 11.0.2.3:111" "dcgw-2 11.0.0.7:110" "dcgw-4 11.0.2.3:111"; do
  set -- $pair
  echo "======== $1: type-3 RD $2"
  cli "$1" "show network-instance default protocols bgp routes evpn route-type 3 rd $2 detail" \
    | grep -E 'Received paths|Path [0-9]|Route source|BGP next-hop|AS Path|Originating router|advertised to|\[ '
done

echo "======== type-3 summary (all RDs) on dcgw-1 and dcgw-4"
cli dcgw-1 "show network-instance default protocols bgp routes evpn route-type 3 summary" | grep -E ':(104|105|110|111) '
cli dcgw-4 "show network-instance default protocols bgp routes evpn route-type 3 summary" | grep -E ':(104|105|110|111) '

echo "======== type-1 / type-4 counts on dcgw-1"
cli dcgw-1 "show network-instance default protocols bgp routes evpn route-type 1 summary" | tail -4
cli dcgw-1 "show network-instance default protocols bgp routes evpn route-type 4 summary" | tail -4

echo "======== BUM flood list bd-3 on dcgw-1, bd-4 on dcgw-3"
cli dcgw-1 "show tunnel-interface vxlan0 vxlan-interface 500 bridge-table multicast-destinations destination *" | tail -15
cli dcgw-1 "info from state network-instance bd-3 protocols bgp-evpn bgp-instance 2" | head -40
