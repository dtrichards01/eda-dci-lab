#!/usr/bin/env bash
# Re-onboard the running srl-leaf-spine-dcgw CLAB into two EDA namespaces (see clab/split-ns/README.md).
# Run on k0r4, one phase at a time:
#   split-ns-rebuild.sh tenants-save|remove|integrate|base|labels|fabric|vars|rest|tenants-restore
# Inputs: ~/eda-rebuild/user-crs (scripts/export-user-crs.py), ~/eda-rebuild/k8s (ConfigMaps/Secret),
#         ~/eda-rebuild/topology-data-{pods,wan}.json (scripts/split-topology-data.py).
set -euo pipefail
NS_A=clab-srl-leaf-spine-dcgw
NS_B=clab-srl-dcgw-wan
EDA_URL=${EDA_URL:-https://100.124.186.55}
TD_ALL=${TD_ALL:-$HOME/3-tier-dci/clab-srl-leaf-spine-dcgw/topology-data.json}
WORK=${WORK:-$HOME/eda-rebuild}
UC=$WORK/user-crs
REPO=${REPO:-$HOME/eda-dci-lab}
SPLIT=$REPO/clab/split-ns
VARS_FILE=$WORK/split-ns.vars

conn() {
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u no_proxy -u NO_PROXY \
    "$HOME/.local/bin/clab-connector" "$@"
}
tb() {
  local pod
  pod=$(kubectl get pods -n eda-system --no-headers | awk '/toolbox/{print $1; exit}')
  kubectl exec -n eda-system "$pod" -- "$@"
}
# apply_uc <kind-file> <ns> [name ...]: re-apply exported user CRs, optionally only named items
apply_uc() {
  local file=$UC/$1.json ns=$2; shift 2
  [ -f "$file" ] || { echo "skip $1 (not exported)"; return; }
  python3 - "$file" "$ns" "$@" <<'EOF' | kubectl apply -f -
import json, sys
path, ns, *names = sys.argv[1:]
d = json.load(open(path))
d["items"] = [i for i in d["items"] if not names or i["metadata"]["name"] in names]
for i in d["items"]:
    i["metadata"]["namespace"] = ns
json.dump(d, sys.stdout)
EOF
}
render_apply() {
  local f=$1; shift
  # shellcheck disable=SC2046
  python3 "$REPO/scripts/split-ns-render.py" "$f" $( [ -f "$VARS_FILE" ] && cat "$VARS_FILE" ) "$@" | kubectl apply -f -
}
wait_fabric() {
  local ns=$1 name=$2 i
  for i in $(seq 1 60); do
    s=$(kubectl -n "$ns" get fabric "$name" -o jsonpath='{.status.operationalState}' 2>/dev/null || true)
    echo "  $ns/$name: ${s:-pending}"
    [ "$s" = Up ] && return 0
    sleep 20
  done
  return 1
}

strip_json() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for i in d["items"]:
    m = i["metadata"]
    i["metadata"] = {k: m[k] for k in ("name", "namespace", "labels", "annotations") if k in m}
    i.pop("status", None)
json.dump(d, sys.stdout, indent=1)'
}

case "${1:-}" in
tenants-save)
  # tenancy app: Tenant CRs in NS_A derive tenant-* namespaces whose VNETs block namespace removal
  mkdir -p "$WORK/tenancy"
  kubectl -n $NS_A get tenants.tenancy.dtrichards01.github.io -o json | strip_json > "$WORK/tenancy/tenants.json"
  for t in $(python3 -c 'import json,sys; [print(i["spec"]["tenantNamespace"]) for i in json.load(open(sys.argv[1]))["items"]]' "$WORK/tenancy/tenants.json"); do
    kubectl -n "$t" get virtualnetworks.services.eda.nokia.com -o json | strip_json > "$WORK/tenancy/vnets-$t.json"
  done
  ls -l "$WORK/tenancy"
  for f in "$WORK"/tenancy/vnets-*.json; do kubectl delete -f "$f" --wait=true; done
  ;;

tenants-restore)
  kubectl apply -f "$WORK/tenancy/tenants.json"
  for f in "$WORK"/tenancy/vnets-*.json; do
    t=$(basename "$f" .json); t=${t#vnets-}
    for i in $(seq 1 30); do kubectl get ns "$t" >/dev/null 2>&1 && break; sleep 5; done
    kubectl apply -f "$f"
  done
  ;;

remove)
  conn remove -t "$TD_ALL" -e "$EDA_URL" -n "$NS_A"
  ;;

integrate)
  conn integrate -t "$WORK/topology-data-pods.json" -e "$EDA_URL" -n "$NS_A"
  conn integrate -t "$WORK/topology-data-wan.json" -e "$EDA_URL" -n "$NS_B"
  ;;

base)
  for ns in $NS_A $NS_B; do
    for f in "$WORK"/k8s/cm-*.json; do
      sed "s/\"namespace\": *\"$NS_A\"/\"namespace\": \"$ns\"/" "$f" | kubectl apply -f -
    done
    for k in indexallocationpools.core ipallocationpools.core ipinsubnetallocationpools.core \
             subnetallocationpools.core communitysets.routingpolicies tagsets.routingpolicies \
             policys.routingpolicies; do
      apply_uc "$k.eda.nokia.com" "$ns"
    done
  done
  kubectl apply -f "$WORK/k8s/secret-discord-bot-token.json"
  for k in artifacts.artifacts banners.siteinfo simnodes.core notifications.discord \
           slashcommands.discord configlets.config; do
    apply_uc "$k.eda.nokia.com" "$NS_A"
  done
  render_apply "$SPLIT/pods/00-pools.yaml"
  render_apply "$SPLIT/wan/00-pools.yaml"
  ;;

labels)
  for n in 1 2 3 4; do kubectl -n $NS_A label toponode srl-leaf-$n role=leaf fabric=pod-1 site=dc1 eda.nokia.com/role=leaf --overwrite; done
  for n in 5 6 7 8; do kubectl -n $NS_A label toponode srl-leaf-$n role=leaf fabric=pod-2 site=dc2 eda.nokia.com/role=leaf --overwrite; done
  for n in 1 2; do kubectl -n $NS_A label toponode srl-spine-$n role=spine fabric=pod-1 site=dc1 eda.nokia.com/role=spine --overwrite; done
  for n in 3 4; do kubectl -n $NS_A label toponode srl-spine-$n role=spine fabric=pod-2 site=dc2 eda.nokia.com/role=spine --overwrite; done
  for n in 1 2; do kubectl -n $NS_A label toponode dcgw-$n role=dcgw fabric=pod-1 site=dc1 eda.nokia.com/role=borderleaf eda.nokia.com/dci=dc-1 --overwrite; done
  for n in 3 4; do kubectl -n $NS_B label toponode dcgw-$n role=dcgw site=dc2 eda.nokia.com/role=dcgw eda.nokia.com/dci=dc-2 --overwrite; done
  for n in 1 2; do kubectl -n $NS_B label toponode sros-pe-$n role=backbone fabric=backbone eda.nokia.com/role=backbone --overwrite; done

  # dcgw pair links are WAN IGP (user ISL), not Fabric ISLs
  for l in $(kubectl -n $NS_A get topolinks -o name | grep -E 'dcgw-1-.*dcgw-2'); do
    kubectl -n $NS_A label "$l" eda.nokia.com/role-
  done
  for l in $(kubectl -n $NS_B get topolinks -o name); do
    if [[ $l == *sros-pe-1*sros-pe-2* || $l == *sros-pe-2*sros-pe-1* ]]; then
      kubectl -n $NS_B label "$l" eda.nokia.com/role=wan-interSwitch --overwrite
    else
      kubectl -n $NS_B label "$l" eda.nokia.com/role-
    fi
  done

  # edge service labels (client ports)
  lab() { kubectl -n $NS_A label interface "$1" "$2" --overwrite; }
  lab srl-leaf-1-ethernet-1-5 eda.nokia.com/vnet-1=vlan-bd-1
  lab srl-leaf-2-ethernet-1-6 eda.nokia.com/vnet-1=vlan-bd-1
  lab srl-leaf-3-ethernet-1-5 eda.nokia.com/vnet-3=vlan-bd-3
  lab srl-leaf-4-ethernet-1-5 eda.nokia.com/vnet-5=vlan-bd-5
  lab srl-leaf-5-ethernet-1-5 eda.nokia.com/vnet-2=vlan-bd-2
  lab srl-leaf-6-ethernet-1-6 eda.nokia.com/vnet-2=vlan-bd-2
  lab srl-leaf-7-ethernet-1-5 eda.nokia.com/vnet-4=vlan-bd-4
  lab srl-leaf-8-ethernet-1-5 eda.nokia.com/vnet-4=vlan-bd-4

  # anycast-VTEP LAG owns leaf-3/4 e1-10
  kubectl -n $NS_A delete interface srl-leaf-3-ethernet-1-10 srl-leaf-4-ethernet-1-10 --ignore-not-found
  apply_uc interfaces.interfaces.eda.nokia.com $NS_A mh-l2-avtep-lag-leaf-3-4 loopback-255 \
    loopback-255-srl-leaf-4 srl-leaf-1-ethernet-1-20 srl-leaf-2-ethernet-1-20 \
    srl-leaf-1-ethernet-1-21 srl-leaf-3-ethernet-1-20 srl-leaf-4-ethernet-1-20
  ;;

fabric)
  render_apply "$SPLIT/pods/01-fabrics.yaml"
  render_apply "$SPLIT/wan/01-fabric-backbone.yaml"
  wait_fabric $NS_A pod-1
  wait_fabric $NS_A pod-2
  wait_fabric $NS_B backbone-simulation
  ;;

vars)
  as=$(tb edactl -n $NS_A get defaultrouter router-srl-spine-3 -o yaml | awk '/autonomousSystem:/{print $2; exit}')
  sys() { tb edactl -n "$1" get systeminterfaces | awk -v n="$2-system0" '$1==n{sub("/32","",$4); print $4}'; }
  pe_if() { kubectl -n $NS_B get interfaces -o name | sed 's#.*/##' | grep -E "^sros-pe-2-.*-$1-1$" | head -1; }
  pe2_c3=$(pe_if 3); pe2_c4=$(pe_if 4)
  pe1_c1=${pe2_c3/sros-pe-2/sros-pe-1}; pe1_c1=${pe1_c1%-3-1}-1-1
  pe1_c2=${pe2_c3/sros-pe-2/sros-pe-1}; pe1_c2=${pe1_c2%-3-1}-2-1
  cat > "$VARS_FILE" <<EOF
POD2_SPINE_AS=$as
SPINE3_SYS=$(sys $NS_A srl-spine-3)
SPINE4_SYS=$(sys $NS_A srl-spine-4)
DCGW1_SYS=$(sys $NS_A dcgw-1)
DCGW2_SYS=$(sys $NS_A dcgw-2)
PE2_C3=$pe2_c3
PE2_C4=$pe2_c4
PE1_C1=$pe1_c1
PE1_C1_PORT=${pe1_c1#sros-pe-1-}
PE1_C2=$pe1_c2
PE1_C2_PORT=${pe1_c2#sros-pe-1-}
EOF
  cat "$VARS_FILE"
  ;;

rest)
  [ -f "$VARS_FILE" ] || { echo "run 'vars' first"; exit 1; }
  for f in pods/02-dcgw-wan.yaml pods/03-standalone-dcgw-peering.yaml wan/02-standalone-dcgw.yaml \
           wan/03-wan-igp.yaml wan/04-wan-bgp.yaml pods/04-services.yaml wan/05-services.yaml; do
    echo "==> $f"
    render_apply "$SPLIT/$f"
  done
  ;;

*)
  sed -n '2,7p' "$0"; exit 1 ;;
esac
