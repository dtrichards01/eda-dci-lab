#!/usr/bin/env bash
# L3 DCI cross-vnet tests (native per DC: vnet-1 DC1, vnet-2 DC2 hub).
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

echo "========== L3 cross-vnet DC1 -> DC2 hub =========="
run_ping client-vnet-1-dc1 172.16.201.1 "vnet-1 -> vnet-2 hub"

echo "========== L3 cross-vnet DC2 hub -> DC1 =========="
run_ping client-vnet-2-dc2 172.16.101.1 "vnet-2 hub -> vnet-1"

echo "========== L3 hub/spoke (when vnet-5 deployed) =========="
run_ping client-5-vnet-5-dc1 172.16.201.1 "vnet-5 spoke -> hub" || true
run_ping client-3-vnet-2-dc2 172.16.151.1 "hub -> vnet-5 spoke" || true
