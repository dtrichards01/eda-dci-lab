#!/usr/bin/env bash
# Read-only: after dcgw-3/4 got distinct underlay ASNs, check sessions, DCI tests and the DC2 backup path.
set -u
cli() { docker exec "$1" sr_cli -e "$2" 2>&1; }

for n in dcgw-3 dcgw-4; do
  echo "======== $n BGP"
  cli "$n" "show network-instance default protocols bgp summary" | grep -E 'Local AS|AS:' | head -2
  cli "$n" "show network-instance default protocols bgp neighbor" | grep -E '^\| default'
done
echo "======== spine-3 neighbors to dcgw-3/4"
cli srl-spine-3 "show network-instance default protocols bgp neighbor" | grep -E '192\.168\.220|11\.0\.2\.'

echo "======== backup path: DC1 L2 IMET (RD 11.0.0.7:110) on dcgw-4 and dcgw-3"
for n in dcgw-4 dcgw-3; do
  echo "-- $n"
  cli "$n" "show network-instance default protocols bgp routes evpn route-type 3 summary" | grep -E '11\.0\.0\.7:110'
done
echo "======== backup path: DC1 L3 (VPN-IPv4) is not reflected (fabric overlay is EVPN only), for reference"
cli dcgw-4 "show network-instance default protocols bgp routes ipv4 summary" | grep -c '172\.16\.' 

echo "======== DCI validation"
cd ~/eda-dci-lab && bash scripts/validate-dci-split.sh 2>&1 | grep -E 'PASS|FAIL|failed checks'
