#!/bin/bash
# EDA platform restore from a platformbackup tarball.
#
# Connection model (important):
#   This script does NOT use the EDA UI URL (https://...). It uses kubectl to talk
#   to the Kubernetes API of the cluster where EDA runs, then runs edactl inside the
#   eda-toolbox pod. You need:
#     - kubectl installed on the machine you run this from
#     - kubeconfig with credentials for that cluster (KUBECONFIG or default ~/.kube/config)
#     - network reachability to the cluster API (often via SSH jump host)
#
# Typical patterns:
#   On Talos kubectl host (k0r4):  ./eda-platform-restore.sh
#   From laptop with kubeconfig:   KUBECONFIG=~/eda-talos.conf KUBE_CONTEXT=admin@eda-compute-cluster ./eda-platform-restore.sh
#   Different lab:               KUBE_CONTEXT=my-other-eda SKIP_HOST_CHECK=1 BACKUP_DIR=/path/to/backups ./eda-platform-restore.sh
#
# Environment variables:
#   KUBECONFIG          Path to kubeconfig (optional; default ~/.kube/config)
#   KUBE_CONTEXT        kubectl context name (optional; uses current context if unset)
#   EDA_NAMESPACE       Namespace for eda-toolbox pod (default: eda-system)
#   BACKUP_DIR          Directory containing platformbackup*.tar.gz (default: /home/nokia/backups)
#   RESTORE_TIMEOUT     edactl timeout (default: 15m)
#   SKIP_HOST_CHECK     Set to 1 to skip hostname/context safety prompts
#   EXPECTED_HOST       If set, warn when hostname differs (default: k0r4)
#   EXPECTED_CONTEXT    If set, warn when kubectl context differs
#   EDA_UI_URL          Display only — helps confirm which cluster you mean (not used for API calls)
#
# Usage:
#   ./eda-platform-restore.sh
#   ./eda-platform-restore.sh platformbackup-dci-all-srl-010826-0930.tar.gz
set -eu

EDA_NAMESPACE="${EDA_NAMESPACE:-eda-system}"
BACKUP_DIR="${BACKUP_DIR:-/home/nokia/backups}"
EXPECTED_HOST="${EXPECTED_HOST:-k0r4}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-admin@eda-compute-cluster}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-15m}"
SKIP_HOST_CHECK="${SKIP_HOST_CHECK:-0}"
POD_TMP="/tmp"

die() { echo "ERROR: $*" >&2; exit 1; }

kubectl_cmd() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl --context "$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

confirm_yes() {
  case "$1" in y|Y|y*|Y*) return 0 ;; *) return 1 ;; esac
}

echo "=== EDA platform restore ==="
echo "Host:       $(hostname) ($(hostname -I 2>/dev/null | awk '{print $1}'))"
echo "User:       $(whoami)"
if [[ -n "${KUBECONFIG:-}" ]]; then
  echo "KUBECONFIG: ${KUBECONFIG}"
fi
echo "Context:    $(kubectl_cmd config current-context 2>/dev/null || echo 'kubectl not configured')"
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  echo "KUBE_CONTEXT override: ${KUBE_CONTEXT}"
fi
if [[ -n "${EDA_UI_URL:-}" ]]; then
  echo "EDA UI:     ${EDA_UI_URL} (reference only — restore uses kubectl API)"
fi
api="$(kubectl_cmd cluster-info 2>/dev/null | head -1 || true)"
[[ -n "$api" ]] && echo "Cluster:    $api"
echo "Toolbox ns: ${EDA_NAMESPACE}"
if [[ "$SKIP_HOST_CHECK" != "1" ]]; then
  echo "Expected:   host=${EXPECTED_HOST}, context=${EXPECTED_CONTEXT}"
fi
echo

if [[ "$SKIP_HOST_CHECK" != "1" ]]; then
  if [[ -n "$EXPECTED_HOST" && "$(hostname)" != "$EXPECTED_HOST" ]]; then
    read -r -p "Hostname is not ${EXPECTED_HOST}. Continue anyway? [y/N] " ans
    confirm_yes "$ans" || die "Aborted — wrong host?"
  fi

  ctx="$(kubectl_cmd config current-context 2>/dev/null || true)"
  if [[ -n "$EXPECTED_CONTEXT" && "$ctx" != "$EXPECTED_CONTEXT" ]]; then
    read -r -p "kubectl context is '${ctx}', expected '${EXPECTED_CONTEXT}'. Continue? [y/N] " ans
    confirm_yes "$ans" || die "Aborted — wrong cluster context?"
  fi
fi

if ! kubectl_cmd get nodes >/dev/null 2>&1; then
  die "kubectl cannot reach the cluster (check KUBECONFIG, KUBE_CONTEXT, VPN, and API reachability)"
fi

# Optional: pick context interactively when none set and multiple exist
if [[ -z "${KUBE_CONTEXT:-}" && -z "${1:-}" ]]; then
  mapfile -t CONTEXTS < <(kubectl_cmd config get-contexts -o name 2>/dev/null)
  if [[ ${#CONTEXTS[@]} -gt 1 ]]; then
    echo "Available kubectl contexts:"
    i=1
    for c in "${CONTEXTS[@]}"; do
      printf "  %2d) %s\n" "$i" "$c"
      i=$((i + 1))
    done
    read -r -p "Use current context or enter number to switch: " ctx_choice
    if [[ "$ctx_choice" =~ ^[0-9]+$ ]]; then
      idx="$ctx_choice"
      if [[ "$idx" -ge 1 && "$idx" -le ${#CONTEXTS[@]} ]]; then
        export KUBE_CONTEXT="${CONTEXTS[$((idx - 1))]}"
        echo "Using context: ${KUBE_CONTEXT}"
      fi
    fi
  fi
fi

TOOLBOX_POD="$(kubectl_cmd get pods -n "$EDA_NAMESPACE" --no-headers 2>/dev/null | awk '/toolbox/{print $1; exit}')"
[[ -n "$TOOLBOX_POD" ]] || die "No eda-toolbox pod in namespace ${EDA_NAMESPACE}"

echo "Toolbox pod: ${TOOLBOX_POD}"

read -r -p "Backup directory [${BACKUP_DIR}]: " dir_in
[[ -n "$dir_in" ]] && BACKUP_DIR="$dir_in"
[[ -d "$BACKUP_DIR" ]] || die "Backup directory not found: $BACKUP_DIR"

if [[ -n "${1:-}" ]]; then
  BACKUP_FILE="$1"
else
  mapfile -t BACKUP_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'platformbackup*.tar.gz' -o -name 'platformbackup*.tgz' \) -printf '%f\n' 2>/dev/null | sort)
  if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
    mapfile -t BACKUP_FILES < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' 2>/dev/null | sort)
  fi
  [[ ${#BACKUP_FILES[@]} -gt 0 ]] || die "No .tar.gz backups found in ${BACKUP_DIR}"

  echo
  echo "Backups in ${BACKUP_DIR}:"
  i=1
  for f in "${BACKUP_FILES[@]}"; do
    size="$(du -h "${BACKUP_DIR}/${f}" | awk '{print $1}')"
    printf "  %2d) %s  (%s)\n" "$i" "$f" "$size"
    i=$((i + 1))
  done
  echo
  read -r -p "Enter number or full backup file name: " choice
  [[ -n "$choice" ]] || die "No selection"

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    idx="$choice"
    if [[ "$idx" -lt 1 || "$idx" -gt ${#BACKUP_FILES[@]} ]]; then
      die "Invalid number: ${choice} (pick 1-${#BACKUP_FILES[@]})"
    fi
    BACKUP_FILE="${BACKUP_FILES[$((idx - 1))]}"
    echo "Selected: ${BACKUP_FILE}"
  else
    BACKUP_FILE="$choice"
  fi
fi

SRC="${BACKUP_DIR%/}/${BACKUP_FILE}"
[[ -f "$SRC" ]] || die "Backup not found: $SRC"

echo
echo "Restore plan:"
echo "  Source:  $SRC ($(du -h "$SRC" | awk '{print $1}'))"
echo "  Pod:     ${EDA_NAMESPACE}/${TOOLBOX_POD}"
echo "  Context: $(kubectl_cmd config current-context 2>/dev/null || echo '?')"
echo "  Command: edactl platform restore ${POD_TMP}/${BACKUP_FILE} --exclude-security-git-repo"
echo "  Note:    CE will restart after restore completes."
echo
read -r -p "Proceed with restore? [y/N] " confirm
confirm_yes "$confirm" || die "Aborted by user"

echo "Copying backup into toolbox pod..."
kubectl_cmd cp "$SRC" "${EDA_NAMESPACE}/${TOOLBOX_POD}:${POD_TMP}/${BACKUP_FILE}"

echo "Running platform restore (timeout ${RESTORE_TIMEOUT})..."
kubectl_cmd exec -n "$EDA_NAMESPACE" "$TOOLBOX_POD" -- \
  edactl platform restore "${POD_TMP}/${BACKUP_FILE}" \
  --exclude-security-git-repo \
  --timeout "$RESTORE_TIMEOUT"

echo
echo "Restore command finished. CE may still be restarting — check EDA UI and:"
echo "  kubectl --context $(kubectl_cmd config current-context 2>/dev/null) get pods -n ${EDA_NAMESPACE}"
echo "  kubectl --context $(kubectl_cmd config current-context 2>/dev/null) get pods -A | grep -E 'eda|clab'"
