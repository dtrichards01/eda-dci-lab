#!/bin/bash
# Simple L2/L3 client: IP/GW on eth1 + optional aggregate route.
set -euo pipefail
IP="${1:?usage: client-config.sh <ip/mask> <gw> [extra-route]}"
GW="${2:?}"
EXTRA_ROUTE="${3:-}"

for i in $(seq 1 30); do
  ip link show eth1 >/dev/null 2>&1 && break
  sleep 1
done

ip link set eth1 up
ip addr add "$IP" dev eth1
ip route replace default via "$GW"
if [ -n "$EXTRA_ROUTE" ]; then
  ip route replace "$EXTRA_ROUTE" via "$GW"
fi

iperf3 -s -D
echo "client-config ready: $IP via $GW"
