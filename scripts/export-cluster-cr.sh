#!/usr/bin/env bash
# Export fabric, ISL, MPLS/LDP, WAN BGP, and core vnet CRs from cluster (run on Talos).
set -eu
NS="${NS:-clab-srl-leaf-spine-dcgw}"
OUT="${OUT:-/tmp/eda-cr-export}"
mkdir -p "$OUT/mpls-ldp" "$OUT/vnets" "$OUT/wan-bgp" "$OUT/ospf"

clean() {
  sed -e '/^  resourceVersion:/d' \
      -e '/^  uid:/d' \
      -e '/^  creationTimestamp:/d' \
      -e '/^  generation:/d' \
      -e '/^  annotations:/d' \
      -e '/^    reconcile-trigger:/d' \
      -e '/^status:/,$d'
}

export_kind() {
  kind=$1
  file=$2
  : > "$file"
  kubectl get "$kind" -n "$NS" -o name 2>/dev/null | while read -r name; do
    kubectl get -n "$NS" "$name" -o yaml | clean >> "$file"
    echo "---" >> "$file"
  done
  echo "exported $kind -> $file"
}

export_named() {
  resource=$1
  file=$2
  : > "$file"
  kubectl get -n "$NS" "$resource" -o yaml | clean >> "$file"
  echo "---" >> "$file"
  echo "exported $resource -> $file"
}

export_kind fabrics "$OUT/fabrics.yaml"
export_kind isls "$OUT/isls.yaml"
export_kind defaultldprouters "$OUT/mpls-ldp/defaultldprouters.yaml"
export_kind defaultldpinterfaces "$OUT/mpls-ldp/defaultldpinterfaces.yaml"
export_kind labelblocks "$OUT/mpls-ldp/labelblocks.yaml"

echo "==> Default OSPF (instances, areas, interfaces)"
export_kind defaultospfinstances "$OUT/ospf/defaultospfinstances.yaml"
export_kind defaultospfareas "$OUT/ospf/defaultospfareas.yaml"
export_kind defaultospfinterfaces "$OUT/ospf/defaultospfinterfaces.yaml"

echo "==> WAN BGP (DCGW peering)"
: > "$OUT/wan-bgp/defaultbgpgroups.yaml"
kubectl get -n "$NS" defaultbgpgroup/default-bgp-group-dc-1 -o yaml | clean >> "$OUT/wan-bgp/defaultbgpgroups.yaml"
echo "---" >> "$OUT/wan-bgp/defaultbgpgroups.yaml"
kubectl get -n "$NS" defaultbgpgroup/default-bgp-group-dc-2 -o yaml | clean >> "$OUT/wan-bgp/defaultbgpgroups.yaml"
echo "---" >> "$OUT/wan-bgp/defaultbgpgroups.yaml"
echo "exported defaultbgpgroups -> $OUT/wan-bgp/defaultbgpgroups.yaml"

: > "$OUT/wan-bgp/defaultbgppeers.yaml"
kubectl get defaultbgppeers -n "$NS" -o name | grep 'dcgw-[0-9]-dcgw-[0-9]-bgp-peer' | while read -r peer; do
  kubectl get -n "$NS" "$peer" -o yaml | clean >> "$OUT/wan-bgp/defaultbgppeers.yaml"
  echo "---" >> "$OUT/wan-bgp/defaultbgppeers.yaml"
done
echo "exported WAN peers -> $OUT/wan-bgp/defaultbgppeers.yaml"

echo "==> VirtualNetworks vnet-1 .. vnet-5"
for v in vnet-1 vnet-2 vnet-3 vnet-4 vnet-5; do
  export_named "virtualnetwork/$v" "$OUT/vnets/$v.yaml"
done

echo "==> Export complete: $OUT"
echo "    Copy to repo: clab/eda-fabric/, clab/eda-mpls-ldp/, clab/eda-ospf/, clab/eda-wan-bgp/, clab/eda-vnets/"
