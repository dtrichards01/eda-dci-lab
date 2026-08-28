#!/usr/bin/env bash
# L3 hub-spoke ping matrix. Prefers live Talos short names (client-1..8).
set -eu

has() { docker inspect "$1" >/dev/null 2>&1; }

run_ping() {
  local src="$1" dst="$2" label="$3" expect="${4:-pass}"
  echo "--- $label: $src -> $dst (expect $expect) ---"
  if docker exec "$src" ping -c 2 -W 2 "$dst"; then
    if [ "$expect" = fail ]; then echo "UNEXPECTED PASS"; else echo "PASS"; fi
  else
    if [ "$expect" = fail ]; then echo "PASS (isolated)"; else echo "FAIL"; fi
  fi
}

if has client-1 && has client-5; then
  V1=client-1
  V1b=client-2
  V2=client-5
  V2b=client-6
elif has client-1-vnet-1-dc1; then
  V1=client-1-vnet-1-dc1
  V1b=client-2-vnet-1-dc1
  V2=client-3-vnet-2-dc2
  V2b=client-4-vnet-2-dc2
else
  echo "No DCI clients found in docker" >&2
  exit 1
fi

echo "========== vnet-1 -> vnet-2 =========="
run_ping "$V1" 172.16.201.254 "vnet-1 -> hub GW"
run_ping "$V1" 172.16.201.1 "vnet-1 -> hub .1"
run_ping "$V1" 172.16.201.2 "vnet-1 -> hub .2"

echo "========== vnet-2 -> vnet-1 =========="
run_ping "$V2" 172.16.101.254 "hub -> vnet-1 GW"
run_ping "$V2" 172.16.101.1 "hub -> vnet-1 .1"
run_ping "$V2b" 172.16.101.2 "hub -> vnet-1 .2"

echo "========== vnet-2 -> vnet-5 (IRB) =========="
run_ping "$V2" 172.16.151.254 "hub -> vnet-5 IRB"

echo "========== vnet-1 must NOT reach vnet-5 =========="
run_ping "$V1" 172.16.151.254 "spoke isolation" fail
