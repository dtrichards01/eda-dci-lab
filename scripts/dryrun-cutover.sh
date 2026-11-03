#!/usr/bin/env bash
# Dry-run (or --commit) an eda-txn.py ops file, then show errors and the CR / node changes for dcgw-3.
# Usage: dryrun-cutover.sh <ops.yaml> [--commit]
set -u
NS=clab-srl-dcgw-wan
TB=$(kubectl -n eda-system get pods -l eda.nokia.com/app=eda-toolbox -o jsonpath='{.items[0].metadata.name}')
edactl() { kubectl -n eda-system exec "$TB" -- edactl "$@" 2>&1; }
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

out=$(python3 "$(dirname "$0")/eda-txn.py" "$@" 2>&1); rc=$?
echo "$out"
tid=$(echo "$out" | awk '/^transaction /{print $2}')
[ -n "$tid" ] || exit $rc
echo "======== errors"
edactl transaction "$tid" -e 2>&1 | head -60
echo "======== CR changes (dcgw / pool / fabric)"
edactl transaction "$tid" cr-change 2>&1 | grep -iE 'dcgw|asn-pool|backbone|systeminterface|defaultrouter|isis|bgp' | head -60
for o in "DefaultRouter router-dcgw-3" "SystemInterface dcgw-3-system0"; do
  set -- $o
  echo "======== $1 $2"
  edactl transaction "$tid" cr-change "$1/$NS/$2" 2>&1 | head -60
done
echo "======== node change dcgw-3 (first 120 lines)"
edactl transaction "$tid" node-change dcgw-3 2>&1 | head -120
exit $rc
