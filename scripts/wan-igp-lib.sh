#!/usr/bin/env bash
# Shared helpers for WAN IGP option switch (OSPFv2+LDP vs ISIS+SR-MPLS).
# shellcheck disable=SC2034
NS="${NS:-clab-srl-leaf-spine-dcgw}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

patch_ric_tunnels() {
  local tunnel="$1"
  python3 - "$NS" "$tunnel" <<'PY'
import json, subprocess, sys
ns, tunnel = sys.argv[1], sys.argv[2]
changed = 0
for kind in ("routerinterconnect", "bridgedomaininterconnect"):
    r = subprocess.run(["kubectl", "get", kind, "-n", ns, "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        continue
    doc = json.loads(r.stdout)
    for item in doc.get("items") or []:
        name = item["metadata"]["name"]

        def walk(o):
            global_hits = 0
            if isinstance(o, dict):
                if "allowedTunnelTypes" in o and isinstance(o["allowedTunnelTypes"], list):
                    o["allowedTunnelTypes"] = [tunnel]
                    global_hits += 1
                for v in o.values():
                    global_hits += walk(v)
            elif isinstance(o, list):
                for v in o:
                    global_hits += walk(v)
            return global_hits

        hits = walk(item.get("spec") or {})
        if not hits:
            continue
        patch = {"spec": item["spec"]}
        p = subprocess.run(
            ["kubectl", "patch", kind, name, "-n", ns, "--type", "merge", "-p", json.dumps(patch)],
            capture_output=True, text=True,
        )
        print(p.stdout.strip() or p.stderr.strip())
        changed += 1
print(f"patched interconnects for tunnel {tunnel}: {changed}")
PY
}

set_ldp_enabled() {
  local en="$1"
  kubectl get defaultldprouter -n "$NS" -o name | while read -r r; do
    kubectl patch -n "$NS" "$r" --type merge -p "{\"spec\":{\"enabled\":${en}}}"
  done
}

set_ospf_enabled() {
  local en="$1"
  for inst in ospf-instance-1 ospf-instance-2; do
    kubectl patch defaultospfinstance "$inst" -n "$NS" --type merge -p "{\"spec\":{\"enabled\":${en}}}" || true
  done
}

set_isis_enabled() {
  local en="$1"
  for inst in isis-instance-1 isis-instance-2 isis-instance-backbone; do
    kubectl patch defaultisisinstance "$inst" -n "$NS" --type merge -p "{\"spec\":{\"enabled\":${en}}}" || true
  done
}

set_backbone_igp() {
  local proto="$1"
  kubectl patch fabric backbone-simulation -n "$NS" --type json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/underlayProtocol/protocols\",\"value\":[\"${proto}\"]}]"
}

# kubectl apply merge does not drop nested spec.ospf.ospfv2 when ospf.enabled=false.
# EDA still tries to resolve the old Fabric OSPF instance and DCGW-PE ISLs stay Degraded.
strip_isl_ospfv2() {
  python3 "$DIR/strip-isl-ospfv2.py" "$NS"
}

discover_pe_isis() {
  kubectl get defaultisisinstance -n "$NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -v '^isis-instance-' | head -1
}

wan_igp_status() {
  echo "==> Fabric backbone underlay"
  kubectl get fabric backbone-simulation -n "$NS" -o jsonpath='protocols={.spec.underlayProtocol.protocols}{"\n"}'
  echo "==> OSPF instances"
  kubectl get defaultospfinstance -n "$NS" -o custom-columns=NAME:.metadata.name,ENABLED:.spec.enabled,STATE:.status.operationalState 2>/dev/null || true
  echo "==> ISIS instances"
  kubectl get defaultisisinstance -n "$NS" -o custom-columns=NAME:.metadata.name,ENABLED:.spec.enabled,STATE:.status.operationalState 2>/dev/null || true
  echo "==> LDP routers"
  kubectl get defaultldprouter -n "$NS" -o custom-columns=NAME:.metadata.name,ENABLED:.spec.enabled,STATE:.status.operationalState 2>/dev/null || true
  echo "==> WAN ISLs"
  kubectl get isl -n "$NS" -o custom-columns=NAME:.metadata.name,OSPF:.spec.ospf.enabled,ISIS:.spec.isis.enabled,STATE:.status.operationalState
}
