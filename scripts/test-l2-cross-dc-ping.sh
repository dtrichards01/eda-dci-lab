#!/usr/bin/env bash
# L2 DCI — same subnet 172.16.103.x stretched across DCs (pure L2, no IRB/routing).
# vnet-3 client DC1: 103.1  |  vnet-4 client DC2: 103.2
set -eu

run_ping() {
  local title="$1" container="$2" dest="$3"
  echo "--- $title: $container -> $dest ---"
  if docker exec "$container" ping -c 3 -W 2 "$dest"; then
    echo "OK"
  else
    echo "FAIL"
  fi
}

echo "========== L2 cross-DC (vnet-3 DC1 -> vnet-4 DC2, same subnet) =========="
run_ping "103.1 -> 103.2" client-vnet-3-dc1 172.16.103.2

echo "========== L2 cross-DC reverse =========="
run_ping "103.2 -> 103.1" client-vnet-4-dc2 172.16.103.1
