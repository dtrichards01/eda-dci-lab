#!/usr/bin/env bash
# Dump every namespaced EDA CR in NS (one file per kind) and take an EDA platform backup.
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
OUT="${OUT:-$HOME/backups/ns-$NS-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

kubectl api-resources --namespaced=true --verbs=list -o name \
  | grep -E '\.eda\.nokia\.com$|\.eda\.labs$' > "$OUT/kinds.txt"

while read -r kind; do
  n=$(kubectl get "$kind" -n "$NS" --no-headers 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] || continue
  kubectl get "$kind" -n "$NS" -o yaml > "$OUT/$kind.yaml"
  echo "$n $kind" >> "$OUT/counts.txt"
done < "$OUT/kinds.txt"
sort -k2 "$OUT/counts.txt" -o "$OUT/counts.txt"
echo "CR export: $OUT ($(wc -l < "$OUT/counts.txt") kinds)"

if [ "${SKIP_PLATFORM_BACKUP:-0}" != 1 ]; then
  pod=$(kubectl get pods -n eda-system --no-headers | awk '/toolbox/{print $1; exit}')
  kubectl exec -n eda-system "$pod" -- edactl platform backup 2>&1 | tail -5
  f=$(kubectl exec -n eda-system "$pod" -- sh -c 'ls -t /eda/eda-backup-*.tar.gz 2>/dev/null | head -1' || true)
  if [ -n "$f" ]; then
    kubectl cp "eda-system/$pod:$f" "$HOME/backups/$(basename "$f")"
    echo "Platform backup: $HOME/backups/$(basename "$f")"
  else
    echo "WARN: platform backup file not found in toolbox /eda"
  fi
fi
