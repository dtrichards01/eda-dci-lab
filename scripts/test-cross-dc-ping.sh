#!/usr/bin/env bash
# Cross-DC connectivity: one client per vnet per DC (client-vnet-N-dcX).
set -eu

run_ping() {
  local src="$1" dst="$2" label="$3"
  echo "--- $label: $src -> $dst ---"
  if docker exec "$src" ping -c 3 -W 2 "$dst"; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

echo "========== L3 vnet-1 (172.16.101.x) DC1 <-> DC2 =========="
run_ping client-vnet-1-dc1 172.16.101.2 "vnet-1 cross-DC"
run_ping client-vnet-1-dc2 172.16.101.1 "vnet-1 reverse"

echo "========== L3 vnet-2 (172.16.201.x) DC2 <-> DC1 =========="
run_ping client-vnet-2-dc2 172.16.201.2 "vnet-2 cross-DC"
run_ping client-vnet-2-dc1 172.16.201.1 "vnet-2 reverse"

echo "========== L2 vnet-3 (172.16.103.x) DC1 <-> DC2 =========="
run_ping client-vnet-3-dc1 172.16.103.2 "vnet-3 cross-DC"
run_ping client-vnet-3-dc2 172.16.103.1 "vnet-3 reverse"

echo "========== L2 vnet-4 (172.16.105.x) DC2 <-> DC1 =========="
run_ping client-vnet-4-dc2 172.16.105.2 "vnet-4 cross-DC"
run_ping client-vnet-4-dc1 172.16.105.1 "vnet-4 reverse"
