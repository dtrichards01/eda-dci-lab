#!/usr/bin/env bash
# Record DCI baseline: system IPs, BD/VRF identifiers, WAN BGP, client pings.
set -u
OUT="${OUT:-$HOME/backups/dci-baseline-$(date +%Y%m%d-%H%M%S).txt}"
exec > >(tee "$OUT") 2>&1

for n in dcgw-1 dcgw-2 dcgw-3 dcgw-4 srl-spine-1 srl-spine-3 srl-leaf-1 srl-leaf-5; do
  echo "== $n system0 / AS"
  docker exec "$n" sr_cli -e "show interface system0.0" | grep -E 'IPv4|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/32'
  docker exec "$n" sr_cli -e "info flat network-instance default protocols bgp autonomous-system" 2>/dev/null
done

echo "== dcgw-1 BGP summary"
docker exec dcgw-1 sr_cli -e "show network-instance default protocols bgp neighbor"
echo "== dcgw-3 BGP summary"
docker exec dcgw-3 sr_cli -e "show network-instance default protocols bgp neighbor"

echo "== dcgw-1 / dcgw-3 network-instances"
docker exec dcgw-1 sr_cli -e "show network-instance summary"
docker exec dcgw-3 sr_cli -e "show network-instance summary"

echo "== BD / VRF ids (EDA status)"
kubectl -n clab-srl-leaf-spine-dcgw get bridgedomains.services.eda.nokia.com \
  -o custom-columns=NAME:.metadata.name,VNI:.status.vni,EVI:.status.evi,EXP:.status.exportTarget,IMP:.status.importTarget

ping_c() { echo "-- $1 -> $2"; docker exec "$1" ping -c 3 -W 1 "$2" | tail -2; }
echo "== client pings"
for c in $(docker ps --format '{{.Names}}' | grep -E '^client-[0-9]+$'); do
  docker exec "$c" ip -4 -br addr show eth1 2>/dev/null | sed "s/^/$c /"
done
echo "Baseline: $OUT"
