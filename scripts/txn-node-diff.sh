#!/usr/bin/env bash
# Read-only: node config diffs of an EDA transaction. Usage: txn-node-diff.sh <txn-id> <node>...
set -u
TB=$(kubectl -n eda-system get pods -l eda.nokia.com/app=eda-toolbox -o jsonpath='{.items[0].metadata.name}')
tid=$1; shift
kubectl -n eda-system exec "$TB" -- edactl transaction "$tid" -e 2>&1 | sed -n '/targetsAffected/,$p'
for n in "$@"; do
  echo "======== $n"
  kubectl -n eda-system exec "$TB" -- edactl transaction "$tid" node-change "$n" 2>&1 | head -80
done
