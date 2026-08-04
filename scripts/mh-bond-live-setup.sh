#!/usr/bin/env bash
# Configure MH LACP bonds on *running* CLAB clients (no redeploy).
# Run on Talos host: bash scripts/mh-bond-live-setup.sh
set -eu

bond_and_vlans() {
  local vlans="$1"
  ip link set eth1 down 2>/dev/null || true
  ip link set eth2 down 2>/dev/null || true
  ip link del bond0 2>/dev/null || true
  for v in $vlans; do ip link del "bond0.$v" 2>/dev/null || true; done
  ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer3+4
  ip link set eth1 master bond0
  ip link set eth2 master bond0
  ip link set eth1 up
  ip link set eth2 up
  ip link set bond0 up
  for v in $vlans; do
    ip link add link bond0 name "bond0.$v" type vlan id "$v"
    ip link set "bond0.$v" up
  done
}

run_in() {
  local container="$1"
  local vlans="$2"
  echo "==> $container (VLANs: $vlans)"
  docker exec "$container" bash -c "$(declare -f bond_and_vlans); bond_and_vlans '$vlans'"
  docker exec "$container" ip link show bond0
}

run_in client-10-dc1-mh "100 200 110"
run_in client-11-dc2-mh "100 200 110"
run_in client-12-dc1-mh "100 200"
run_in client-13-dc2-mh "100 200"

echo "==> Done. Wait ~30s for LACP, then:"
echo "  kubectl get interfaces -n clab-srl-leaf-spine-dcgw | grep mh-dc"
echo "  kubectl get virtualnetwork -n clab-srl-leaf-spine-dcgw | grep mh"
