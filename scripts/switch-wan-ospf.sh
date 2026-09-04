#!/usr/bin/env bash
# Restore WAN underlay to option 1: OSPFv2 + LDP (X1b PEs + SRL DCGWs).
# ISIS/SR CRs are kept but disabled so switch-wan-isis.sh can reuse them.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wan-igp-lib.sh
source "$DIR/wan-igp-lib.sh"

echo "==> Enable OSPF instances + system ifaces"
bash "$DIR/apply-ospf.sh"
set_ospf_enabled true

echo "==> Enable LDP"
kubectl apply -f "$ROOT/clab/eda-mpls-ldp/labelblocks.yaml"
kubectl apply -f "$ROOT/clab/eda-mpls-ldp/defaultldprouters.yaml"
kubectl apply -f "$ROOT/clab/eda-mpls-ldp/defaultldpinterfaces.yaml"
set_ldp_enabled true

echo "==> backbone-simulation underlay ISIS -> OSPFv2"
set_backbone_igp OSPFv2

echo "==> WAN ISLs: OSPF on, ISIS off"
kubectl apply -f "$ROOT/clab/eda-fabric/isls.yaml"

echo "==> Disable ISIS instances (CRs kept)"
set_isis_enabled false

echo "==> RIC/BDI allowedTunnelTypes -> LDP"
patch_ric_tunnels LDP

echo
wan_igp_status
echo
echo "Option 1 applied. Validate: bash $DIR/validate-wan-igp.sh"
echo "Cut to ISIS+SR-MPLS: bash $DIR/switch-wan-isis.sh"
