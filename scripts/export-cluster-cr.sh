#!/usr/bin/env bash
# Export fabric, ISL, and MPLS/LDP CRs from cluster (run on Talos).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
OUT="${OUT:-/tmp/eda-cr-export}"
mkdir -p "$OUT/mpls-ldp"

clean() {
  sed -e '/^  resourceVersion:/d' \
      -e '/^  uid:/d' \
      -e '/^  creationTimestamp:/d' \
      -e '/^  generation:/d' \
      -e '/^status:/,$d'
}

export_kind() {
  kind=$1
  file=$2
  : > "$file"
  kubectl get "$kind" -n "$NS" -o name | while read -r name; do
    kubectl get -n "$NS" "$name" -o yaml | clean >> "$file"
    echo "---" >> "$file"
  done
  echo "exported $kind -> $file"
}

export_kind fabrics "$OUT/fabrics.yaml"
export_kind isls "$OUT/isls.yaml"
export_kind defaultldprouters "$OUT/mpls-ldp/defaultldprouters.yaml"
export_kind defaultldpinterfaces "$OUT/mpls-ldp/defaultldpinterfaces.yaml"
export_kind labelblocks "$OUT/mpls-ldp/labelblocks.yaml"

echo "==> Export complete: $OUT"
echo "    Copy to repo: clab/eda-fabric/ and clab/eda-mpls-ldp/"