#!/bin/bash
# Run ON Talos (k0r4) — fixes MH LACP without CLAB redeploy.
# Paste: bash scripts/mh-bond-fix.sh
# Or copy the setup_bond function below into your shell on k0r4.

setup_bond() {
  local c="$1"
  echo "==> $c"
  docker exec "$c" ip link set eth1 down
  docker exec "$c" ip link set eth2 down
  docker exec "$c" ip link del bond0 2>/dev/null || true
  docker exec "$c" ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer3+4
  docker exec "$c" ip link set eth1 master bond0
  docker exec "$c" ip link set eth2 master bond0
  docker exec "$c" ip link set eth1 up
  docker exec "$c" ip link set eth2 up
  docker exec "$c" ip link set bond0 up
  docker exec "$c" ip link del bond0.200 2>/dev/null || true
  docker exec "$c" ip link add link bond0 name bond0.200 type vlan id 200
  docker exec "$c" ip link set bond0.200 up
  docker exec "$c" ip link show bond0
  docker exec "$c" sh -c 'grep -E "MII Status|Number of ports" /proc/net/bonding/bond0' || true
}

setup_bond client-10-dc1-mh
setup_bond client-11-dc2-mh
setup_bond client-12-dc1-mh
setup_bond client-13-dc2-mh

echo "Wait 30s, then:"
echo "  kubectl get interfaces -n clab-srl-leaf-spine-dcgw | grep mh-dc"
echo "  kubectl get virtualnetwork -n clab-srl-leaf-spine-dcgw | grep mh"
