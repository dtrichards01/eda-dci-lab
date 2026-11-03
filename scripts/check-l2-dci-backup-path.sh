#!/usr/bin/env bash
# Read-only: how the leaked WAN L2 routes act as a backup path, and what the fabric does with them.
set -u
cli() { docker exec "$1" sr_cli -e "$2" 2>&1; }

echo "======== dcgw-2: tunnel to dcgw-3 (11.0.2.3) and dcgw-4 (11.0.2.4)"
cli dcgw-2 "show network-instance default tunnel-table ipv4" | grep -E '11\.0\.2\.(3|4)/32'

echo "======== dcgw-2: type-2 paths for DC2 (RD 11.0.2.3:111), best vs backup"
cli dcgw-2 "show network-instance default protocols bgp routes evpn route-type 2 summary" | grep -E '11\.0\.2\.3:111' | head -12
echo "count via spines: $(cli dcgw-2 "show network-instance default protocols bgp routes evpn route-type 2 summary" | grep -E '11\.0\.2\.3:111' | grep -cE '11\.0\.0\.(5|6) ')"
echo "count via dcgw-4: $(cli dcgw-2 "show network-instance default protocols bgp routes evpn route-type 2 summary" | grep -E '11\.0\.2\.3:111' | grep -c '11\.0\.2\.4 ')"

echo "======== spine-1: WAN L2 routes held by the RR"
echo "type-2 RD 11.0.2.3:111: $(cli srl-spine-1 "show network-instance default protocols bgp routes evpn route-type 2 summary" | grep -c '11\.0\.2\.3:111')"
echo "type-3 RD 11.0.2.3:111: $(cli srl-spine-1 "show network-instance default protocols bgp routes evpn route-type 3 summary" | grep -c '11\.0\.2\.3:111')"

echo "======== srl-leaf-1: does the leaf keep or install them"
echo "type-2 RD 11.0.2.3:111 in RIB-in: $(cli srl-leaf-1 "show network-instance default protocols bgp routes evpn route-type 2 summary" | grep -c '11\.0\.2\.3:111')"
echo "type-3 RD 11.0.2.3:111 in RIB-in: $(cli srl-leaf-1 "show network-instance default protocols bgp routes evpn route-type 3 summary" | grep -c '11\.0\.2\.3:111')"
cli srl-leaf-1 "info network-instance default protocols bgp afi-safi evpn" | grep -Ei 'route-target|rt-constraint|keep-all' || echo "(no rt-constraint / keep-all-routes under default bgp evpn)"

echo "======== any fabric VNET importing the WAN L2 RTs (1:300 / 1:301)"
for n in srl-leaf-1 srl-leaf-5 dcgw-1 dcgw-3; do
  echo "$n: $(cli "$n" "info network-instance * protocols bgp-vpn" | grep -E 'target:1:30[01]' | tr -s ' ' | tr '\n' ' ')"
done
