#!/usr/bin/env bash
# Cut WAN underlay to option 2: IS-IS + SR-MPLS (RIC tunnel SR-ISIS, encap MPLS).
# Does not delete OSPF/LDP CRs — disables them so switch-wan-ospf.sh can restore.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wan-igp-lib.sh
source "$DIR/wan-igp-lib.sh"

echo "==> Apply ISIS + SR-MPLS CRs (keep OSPF CRs in place)"
bash "$DIR/apply-isis.sh"

echo "==> backbone-simulation underlay OSPFv2 -> ISIS"
set_backbone_igp ISIS

echo "==> WAN ISLs: ISIS on, OSPF off (PE side isis-instance-backbone)"
kubectl apply -f "$ROOT/clab/eda-fabric/isls-isis.yaml"
kubectl delete isl pe-1-to-pe-2-c5 pe-1-to-pe-2-c6 -n "$NS" --ignore-not-found

echo "==> Strip leftover OSPF ospfv2 blocks (kubectl apply merge keeps them)"
strip_isl_ospfv2

echo "==> Disable OSPF instances (CRs kept)"
set_ospf_enabled false

echo "==> Delete leftover OSPF system ifaces (Down CRs tank DefaultRouter / fabric health)"
kubectl delete defaultospfinterface -n "$NS" --all --ignore-not-found

echo "==> Disable LDP routers; delete leftover LDP ifaces (same health trap)"
set_ldp_enabled false
kubectl delete defaultldpinterface -n "$NS" --all --ignore-not-found

echo "==> RIC/BDI allowedTunnelTypes -> SR-ISIS (encapsulation stays MPLS)"
patch_ric_tunnels SR-ISIS

echo "==> Enable user ISIS instances"
set_isis_enabled true
kubectl patch defaultisisinstance isis-instance-backbone -n "$NS" --type merge \
  -p '{"spec":{"enabled":true}}' || true

echo
wan_igp_status
echo
echo "Option 2 applied. Validate: bash $DIR/validate-wan-igp.sh"
echo "Restore OSPF+LDP: bash $DIR/switch-wan-ospf.sh"
echo "Tech note: docs/SRL-DCI-WAN-IGP-Tech-Note.md"
