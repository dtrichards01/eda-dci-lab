#!/usr/bin/env bash
# Read-only: WAN namespace objects, which are Fabric-derived vs user-made, and TopoLink labels.
set -u
NS=clab-srl-dcgw-wan
TB=$(kubectl -n eda-system get pods -l eda.nokia.com/app=eda-toolbox -o jsonpath='{.items[0].metadata.name}')
edactl() { kubectl -n eda-system exec "$TB" -- edactl "$@" 2>&1; }

for k in isls defaultisisinstances defaultisisinterfaces systeminterfaces defaultinterfaces; do
  echo "======== $k (edactl = all, kubectl = user)"
  edactl -n $NS get $k
  echo "-- user:"; kubectl -n $NS get $k --no-headers -o custom-columns=N:.metadata.name 2>&1 | tr '\n' ' '; echo
done
echo "======== a Fabric-derived ISL (pe-1 to pe-2)"
for i in $(edactl -n $NS get isls | awk 'NR>1{print $1}'); do
  if ! kubectl -n $NS get isl "$i" >/dev/null 2>&1; then edactl -n $NS get isl "$i" -o yaml | sed -n '/^spec:/,/^status:/p'; break; fi
done
echo "======== TopoLinks"
kubectl -n $NS get topolinks -L eda.nokia.com/role -o custom-columns='NAME:.metadata.name,ROLE:.metadata.labels.eda\.nokia\.com/role,LOCAL:.spec.links[0].local.node,LIF:.spec.links[0].local.interface,REMOTE:.spec.links[0].remote.node,RIF:.spec.links[0].remote.interface'
echo "======== dcgw-3 ISIS / BGP running summary"
docker exec dcgw-3 sr_cli -e "show network-instance default protocols isis adjacency" 2>&1 | grep -E 'ethernet|system' 
docker exec dcgw-3 sr_cli -e "show network-instance default protocols bgp neighbor" 2>&1 | grep -E '^\| default' 
