#!/usr/bin/env bash
# DCI service checks for the srl-leaf-spine-dcgw lab (single or split namespace).
# Exit code = number of failed checks.
set -u
fail=0

ip_of() { docker exec "$1" ip -4 -o addr show 2>/dev/null | awk '$2 ~ /^(eth1|bond0)/ {split($4,a,"/"); print a[1]; exit}'; }

check() {  # check <want ok|fail> <desc> <src> <dst>
  local want=$1 desc=$2 src=$3 dst=$4 got
  if docker exec "$src" ping -c 3 -W 1 -q "$dst" >/dev/null 2>&1; then got=ok; else got=fail; fi
  if [ "$got" = "$want" ]; then r=PASS; else r=FAIL; fail=$((fail+1)); fi
  printf '%-4s %-44s %-9s -> %-15s (want %s, got %s)\n' "$r" "$desc" "$src" "$dst" "$want" "$got"
}

c3=$(ip_of client-3); c7=$(ip_of client-7); c8=$(ip_of client-8)
echo "client-3=$c3 client-7=$c7 client-8=$c8"

check ok   "L3 vnet-1 local (leaf-1 -> leaf-2)"        client-1 172.16.101.2
check ok   "L3 DCI vnet-1 -> hub vnet-2"               client-1 172.16.201.1
check ok   "L3 DCI vnet-1 -> hub vnet-2 (leaf-6)"      client-2 172.16.201.2
check ok   "L3 DCI hub vnet-2 -> vnet-1"               client-5 172.16.101.1
check ok   "L3 DCI hub vnet-2 -> spoke vnet-5 host"    client-5 172.16.151.1
check ok   "L3 DCI spoke vnet-5 -> hub vnet-2"         client-4 172.16.201.1
check fail "L3 spoke isolation vnet-1 -> vnet-5"       client-1 172.16.151.1
[ -n "$c3" ] && [ -n "$c7" ] && check ok "L2 DCI vnet-3 <-> vnet-4 (BDI)" client-3 "$c7"
[ -n "$c7" ] && [ -n "$c8" ] && check ok "L2 vnet-4 local (leaf-7 -> leaf-8)" client-7 "$c8"

echo "== WAN BGP / IGP"
for n in dcgw-1 dcgw-3; do
  docker exec "$n" sr_cli -e "show network-instance default protocols bgp neighbor" \
    | awk -F'|' 'NF>6 && $3 ~ /[0-9]/ {gsub(/ /,"",$3); gsub(/ /,"",$4); gsub(/ /,"",$7); print "'"$n"'", $3, $4, $7}'
  docker exec "$n" sr_cli -e "show network-instance default tunnel-table all" 2>/dev/null | grep -cE 'sr-isis' | sed "s/^/$n sr-isis tunnels: /"
done
echo "failed checks: $fail"
exit "$fail"
