#!/bin/bash
# © 2025 Nokia - BSD-3-Clause
#
# DC2 all-active multi-homed client (client-11-dc2-mh).
# eth1 -> srl-leaf-5, eth2 -> srl-leaf-6 bonded (802.3ad / LACP) into bond0.
#
#   VLAN 200  = L3-DCI DC2 subnet (10.200.2.0/24, anycast GW 10.200.2.254)

set -x

for i in $(seq 1 30); do
  ip link show eth1 >/dev/null 2>&1 && ip link show eth2 >/dev/null 2>&1 && break
  sleep 1
done

ip link set eth1 down
ip link set eth2 down
ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer3+4
ip link set eth1 master bond0
ip link set eth2 master bond0
ip link set eth1 up
ip link set eth2 up
ip link set bond0 up

ip link add link bond0 name bond0.200 type vlan id 200
ip link set bond0.200 up

IDX=0
make_client() {
  ns=$1; parent=$2; mac=$3; cidr=$4; gw=$5
  IDX=$((IDX+1))
  ip netns add "$ns"
  ip link add link "$parent" name "mv$IDX" type macvlan mode bridge
  ip link set "mv$IDX" address "$mac"
  ip link set "mv$IDX" netns "$ns"
  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip link set "mv$IDX" name eth0
  ip netns exec "$ns" ip link set eth0 up
  ip netns exec "$ns" ip addr add "$cidr" dev eth0
  [ -n "$gw" ] && ip netns exec "$ns" ip route replace default via "$gw"
  ip netns exec "$ns" iperf3 -s -D
}

make_client mh2a-l3a bond0.200 00:00:00:00:02:21 10.200.2.21/24 10.200.2.254
make_client mh2a-l3b bond0.200 00:00:00:00:02:22 10.200.2.22/24 10.200.2.254

echo "mh-dc2a (all-active DC2 L3) client emulation ready"
