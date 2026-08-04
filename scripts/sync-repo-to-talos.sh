#!/usr/bin/env bash
# Sync eda-dci-lab repo from Windows/WSL to Talos ~/eda-dci-lab (LF scripts, no root YAML junk).
set -eu
HOST="${TALOS_HOST:-nokia@100.124.186.51}"
PASS="${TALOS_PASS:-}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SSH_OPTS="-o StrictHostKeyChecking=no"
REMOTE=~/eda-dci-lab

if [ -n "$PASS" ] && command -v sshpass >/dev/null 2>&1; then
  run_ssh() { sshpass -p "$PASS" ssh $SSH_OPTS "$HOST" "$@"; }
  run_scp() { sshpass -p "$PASS" scp $SSH_OPTS -r "$@"; }
elif [ -n "$PASS" ]; then
  echo "WARN: TALOS_PASS set but sshpass not installed — using SSH keys (unset TALOS_PASS or apt install sshpass)"
  run_ssh() { ssh $SSH_OPTS "$HOST" "$@"; }
  run_scp() { scp $SSH_OPTS -r "$@"; }
else
  run_ssh() { ssh $SSH_OPTS "$HOST" "$@"; }
  run_scp() { scp $SSH_OPTS -r "$@"; }
fi

echo "==> Sync to $HOST:$REMOTE"
run_ssh "mkdir -p $REMOTE/services $REMOTE/scripts $REMOTE/docs $REMOTE/clab/configs/base-configs $REMOTE/clab/eda-topology $REMOTE/clab/eda-fabric $REMOTE/clab/eda-mpls-ldp $REMOTE/clab/eda-ospf $REMOTE/clab/eda-wan-bgp $REMOTE/clab/eda-vnets"

run_scp "$SRC/scripts/" "$HOST:$REMOTE/scripts/"
run_scp "$SRC/services/" "$HOST:$REMOTE/services/"
run_scp "$SRC/docs/" "$HOST:$REMOTE/docs/"
run_scp "$SRC/clab/clab-leaf-spine-dcgw-srl-only.yaml" "$HOST:$REMOTE/clab/"
run_scp "$SRC/clab/configs/client-config.sh" "$HOST:$REMOTE/clab/configs/"
run_scp "$SRC/clab/configs/base-configs/mh-"*.sh "$HOST:$REMOTE/clab/configs/base-configs/"
run_scp "$SRC/clab/eda-topology/" "$HOST:$REMOTE/clab/eda-topology/"
run_scp "$SRC/clab/eda-fabric/" "$HOST:$REMOTE/clab/eda-fabric/"
run_scp "$SRC/clab/eda-mpls-ldp/" "$HOST:$REMOTE/clab/eda-mpls-ldp/"
run_scp "$SRC/clab/eda-ospf/" "$HOST:$REMOTE/clab/eda-ospf/"
run_scp "$SRC/clab/eda-wan-bgp/" "$HOST:$REMOTE/clab/eda-wan-bgp/"
run_scp "$SRC/clab/eda-vnets/" "$HOST:$REMOTE/clab/eda-vnets/"

echo "==> Fix script line endings + permissions"
run_ssh "find $REMOTE/scripts -name '*.sh' -exec perl -pi -e 's/\r//g' {} +; chmod +x $REMOTE/scripts/*.sh"

echo "==> Remove SCP orphan YAML (EDA re-applies if left in tree)"
run_ssh "rm -f $REMOTE/*.yaml $REMOTE/services-tmp-sync/*.yaml \
  $REMOTE/services/l3/interface-labels/dcgw-*-bd-mh-*.yaml \
  $REMOTE/services/l3/interface-labels/edge-l3-vnet-1-dc2.yaml \
  $REMOTE/services/l3/interface-labels/edge-l3-vnet-2-dc1.yaml \
  $REMOTE/services/l3/interface-labels/virtualnetwork-vnet-*.yaml 2>/dev/null; \
  rm -rf $REMOTE/services/l3/interface-labels/dci-policies \
         $REMOTE/services/l3/interface-labels/router-interconnect \
         $REMOTE/services/l3/interface-labels/scripts 2>/dev/null; \
  ls $REMOTE/*.yaml 2>/dev/null || echo '  (no root yaml — good)'"

echo "==> Repo tree on Talos"
run_ssh "ls $REMOTE/services/mh/; ls $REMOTE/scripts/cleanup-mh*.sh $REMOTE/scripts/apply-mh*.sh $REMOTE/scripts/mh-bond*.sh 2>/dev/null"

echo "==> Done. On Talos: bash $REMOTE/scripts/apply-all.sh"
