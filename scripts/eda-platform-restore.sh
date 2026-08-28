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
# Usage:
#   cd ~/backups && ./eda-platform-restore.sh          # interactive wizard
#   ./eda-platform-restore.sh platformbackup-....tar.gz
#   ./eda-platform-restore.sh -y                       # non-interactive (env vars as overrides)
#
#   Copied from Windows? CRLF errors (set: invalid option, $'\r': command not found):
#     sed -i 's/\r$//' eda-platform-restore.sh   # or: dos2unix eda-platform-restore.sh
#
# Environment variables (optional overrides; wizard prompts when unset):
#   KUBECONFIG          Path to kubeconfig (optional; default ~/.kube/config)
#   KUBE_CONTEXT        kubectl context name
#   EDA_NAMESPACE       Namespace for eda-toolbox pod (default: eda-system)
#   TOOLBOX_POD         Explicit toolbox pod name (skips auto-discovery)
#   TOOLBOX_LABEL       Label selector for toolbox pod (default: eda.nokia.com/app=eda-toolbox)
#   BACKUP_DIR          Directory containing platformbackup*.tar.gz
#   RESTORE_TIMEOUT     edactl timeout (default: 15m)
#   SKIP_HOST_CHECK     Set to 1 to skip hostname/context safety prompts
#   EXPECTED_HOST       Warn when hostname differs (default: k0r4)
#   EXPECTED_CONTEXT    Warn when kubectl context differs (default: admin@eda-compute-cluster)
#   EDA_UI_URL          Display only — helps confirm which cluster you mean
#
# Do NOT source this script (do not run: . eda-platform-restore.sh). Execute it directly.

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "" >&2
  echo "ERROR: Run with ./eda-platform-restore.sh not . eda-platform-restore.sh" >&2
  echo "       Sourcing corrupts your shell and can cause 'pop_var_context' errors." >&2
  echo "" >&2
  return 1 2>/dev/null || exit 1
fi

set -eu

if grep -q $'\r' "${BASH_SOURCE[0]}" 2>/dev/null; then
  echo "WARNING: This script has Windows (CRLF) line endings and may misbehave in bash." >&2
  echo "         Fix with: sed -i 's/\\r$//' ${BASH_SOURCE[0]}" >&2
  echo "" >&2
fi

NON_INTERACTIVE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) NON_INTERACTIVE=true; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
BACKUP_FILE_ARG="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PWD_DIR="$(pwd)"

EDA_NAMESPACE="${EDA_NAMESPACE:-eda-system}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-15m}"
TOOLBOX_LABEL="${TOOLBOX_LABEL:-eda.nokia.com/app=eda-toolbox}"
POD_TMP="/tmp"
EXPECTED_HOST="${EXPECTED_HOST:-k0r4}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-admin@eda-compute-cluster}"

if [[ -z "${BACKUP_DIR:-}" ]]; then
  if [[ "$PWD_DIR" == "$HOME/backups" ]] || [[ "$(basename "$PWD_DIR")" == "backups" ]]; then
    BACKUP_DIR="$PWD_DIR"
  elif [[ "$SCRIPT_DIR" == "$HOME/backups" ]] || [[ "$(basename "$SCRIPT_DIR")" == "backups" ]]; then
    BACKUP_DIR="$SCRIPT_DIR"
  else
    BACKUP_DIR="/home/nokia/backups"
  fi
fi

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

is_kind_context() {
  [[ "${1:-}" == kind-* ]]
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result=""
  if [[ "$NON_INTERACTIVE" == true ]]; then
    echo "$default"
    return
  fi
  read -r -p "${prompt} [${default}]: " result
  if [[ -z "$result" ]]; then
    echo "$default"
  else
    echo "$result"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local hint ans
  if [[ "$NON_INTERACTIVE" == true ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
  read -r -p "${prompt} [${hint}]: " ans
  if [[ -z "$ans" ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  confirm_yes "$ans"
}

list_contexts() {
  kubectl config get-contexts -o name 2>/dev/null || true
}

resolve_context_input() {
  local input="$1"
  local current="$2"
  mapfile -t contexts < <(list_contexts)

  if [[ -z "$input" ]]; then
    echo "$current"
    return
  fi

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    local idx="$input"
    if [[ "$idx" -ge 1 && "$idx" -le ${#contexts[@]} ]]; then
      echo "${contexts[$((idx - 1))]}"
      return
    fi
  fi

  local c
  for c in "${contexts[@]}"; do
    if [[ "$c" == "$input" ]]; then
      echo "$input"
      return
    fi
  done

  echo "$input"
}

show_context_menu() {
  local current="$1"
  mapfile -t contexts < <(list_contexts)
  if [[ ${#contexts[@]} -eq 0 ]]; then
    echo "  (no contexts in kubeconfig)"
    return
  fi
  local i=1 c marker
  for c in "${contexts[@]}"; do
    marker=""
    [[ "$c" == "$current" ]] && marker=" *"
    printf "    %2d) %s%s\n" "$i" "$c" "$marker"
    i=$((i + 1))
  done
}

verify_cluster_reachable() {
  kubectl_cmd get nodes >/dev/null 2>&1
}

discover_toolbox_pod() {
  if [[ -n "${TOOLBOX_POD:-}" ]]; then
    local phase
    phase="$(kubectl_cmd get pod -n "$EDA_NAMESPACE" "$TOOLBOX_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ -n "$phase" ]] || die "Toolbox pod not found: ${EDA_NAMESPACE}/${TOOLBOX_POD}"
    echo "$TOOLBOX_POD"
    return
  fi

  local pod
  pod="$(kubectl_cmd get pods -n "$EDA_NAMESPACE" -l "$TOOLBOX_LABEL" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)"
  if [[ -n "$pod" ]]; then
    echo "$pod"
    return
  fi

  pod="$(kubectl_cmd get pods -n "$EDA_NAMESPACE" --no-headers 2>/dev/null | awk '/toolbox/{print $1; exit}')"
  if [[ -z "$pod" ]]; then
    echo "ERROR: No eda-toolbox pod in namespace ${EDA_NAMESPACE}." >&2
    echo "       Tried label ${TOOLBOX_LABEL} and name pattern 'toolbox'." >&2
    echo "       Check pods:" >&2
    kubectl_cmd get pods -n "$EDA_NAMESPACE" 2>&1 | sed 's/^/         /' >&2 || true
    die "eda-toolbox pod not found - install EDA or set TOOLBOX_POD / TOOLBOX_LABEL"
  fi
  echo "$pod"
}

select_backup_file() {
  if [[ -n "$BACKUP_FILE_ARG" ]]; then
    BACKUP_FILE="$BACKUP_FILE_ARG"
    return
  fi

  mapfile -t backup_files < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'platformbackup*.tar.gz' -o -name 'platformbackup*.tgz' \) -printf '%f\n' 2>/dev/null | sort
  )
  if [[ ${#backup_files[@]} -eq 0 ]]; then
    mapfile -t backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' 2>/dev/null | sort)
  fi
  [[ ${#backup_files[@]} -gt 0 ]] || die "No .tar.gz backups found in ${BACKUP_DIR}"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    BACKUP_FILE="${backup_files[-1]}"
    echo "Auto-selected latest backup: ${BACKUP_FILE}"
    return
  fi

  echo
  echo "Backups in ${BACKUP_DIR}:"
  local i=1 f size
  for f in "${backup_files[@]}"; do
    size="$(du -h "${BACKUP_DIR}/${f}" | awk '{print $1}')"
    printf "  %2d) %s  (%s)\n" "$i" "$f" "$size"
    i=$((i + 1))
  done
  echo
  read -r -p "Enter number or full backup file name: " choice
  [[ -n "$choice" ]] || die "No selection"

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx="$choice"
    if [[ "$idx" -lt 1 || "$idx" -gt ${#backup_files[@]} ]]; then
      die "Invalid number: ${choice} (pick 1-${#backup_files[@]})"
    fi
    BACKUP_FILE="${backup_files[$((idx - 1))]}"
    echo "Selected: ${BACKUP_FILE}"
  else
    BACKUP_FILE="$choice"
  fi
}

handle_host_safety() {
  if [[ "${SKIP_HOST_CHECK:-}" == "1" ]]; then
    echo "Host safety checks: skipped (SKIP_HOST_CHECK=1)"
    return
  fi

  local host ctx
  host="$(hostname)"
  ctx="$KUBE_CONTEXT"

  if is_kind_context "$ctx"; then
    echo "Host safety checks: skipped (kind-* context)"
    return
  fi

  if [[ "$host" != "$EXPECTED_HOST" && "$ctx" != "$EXPECTED_CONTEXT" ]]; then
    echo "WSL/local mode, skipping Talos host check"
    return
  fi

  local host_mismatch=false ctx_mismatch=false

  [[ -n "$EXPECTED_HOST" && "$host" != "$EXPECTED_HOST" ]] && host_mismatch=true
  [[ -n "$EXPECTED_CONTEXT" && "$ctx" != "$EXPECTED_CONTEXT" ]] && ctx_mismatch=true

  if [[ "$host_mismatch" == false && "$ctx_mismatch" == false ]]; then
    echo "Host safety checks: passed (Talos lab defaults)"
    return
  fi

  echo
  echo "Host safety check (informational):"
  echo "  Host:    ${host}"
  echo "  Context: ${ctx}"
  if [[ "$host_mismatch" == true ]]; then
    echo "  NOTE: Hostname is not ${EXPECTED_HOST} (expected for Talos lab on k0r4)"
  fi
  if [[ "$ctx_mismatch" == true ]]; then
    echo "  NOTE: Context is not ${EXPECTED_CONTEXT} (expected for Talos lab)"
  fi

  if [[ "$NON_INTERACTIVE" == true ]]; then
    echo "Non-interactive mode: continuing despite mismatch"
    return
  fi

  local skip_default="y"
  if [[ "$host_mismatch" == false && "$ctx_mismatch" == false ]]; then
    skip_default="n"
  fi

  if prompt_yes_no "Skip Talos host/context safety checks?" "$skip_default"; then
    echo "Safety checks skipped by user"
    return
  fi

  if [[ "$host_mismatch" == true ]]; then
    prompt_yes_no "Hostname is not ${EXPECTED_HOST}. Continue anyway?" "y" || die "Aborted by user"
  fi
  if [[ "$ctx_mismatch" == true ]]; then
    prompt_yes_no "Context is not ${EXPECTED_CONTEXT}. Continue anyway?" "y" || die "Aborted by user"
  fi
}

echo "=== EDA platform restore ==="
echo
if [[ -n "${KUBECONFIG:-}" ]]; then
  echo "KUBECONFIG: ${KUBECONFIG}"
fi
if [[ -n "${EDA_UI_URL:-}" ]]; then
  echo "EDA UI:     ${EDA_UI_URL} (reference only - restore uses kubectl API)"
  echo
fi

# --- Wizard: kubectl context ---
if [[ -z "${KUBE_CONTEXT:-}" ]]; then
  KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi

echo "kubectl context"
echo "  Current: ${KUBE_CONTEXT:-<none>}"
show_context_menu "${KUBE_CONTEXT:-}"

if [[ "$NON_INTERACTIVE" != true ]]; then
  read -r -p "Context [${KUBE_CONTEXT:-}]: " ctx_in
  KUBE_CONTEXT="$(resolve_context_input "$ctx_in" "${KUBE_CONTEXT:-}")"
  echo
fi

[[ -n "${KUBE_CONTEXT:-}" ]] || die "No kubectl context selected"

if ! verify_cluster_reachable; then
  echo "WARNING: Cannot reach cluster with context '${KUBE_CONTEXT}'"
  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo "Available contexts:"
    show_context_menu "${KUBE_CONTEXT}"
    read -r -p "Pick context (number or name) [${KUBE_CONTEXT}]: " ctx_retry
    if [[ -n "$ctx_retry" ]]; then
      KUBE_CONTEXT="$(resolve_context_input "$ctx_retry" "$KUBE_CONTEXT")"
    fi
    echo
  fi
  verify_cluster_reachable || die "kubectl cannot reach the cluster (check KUBECONFIG, context, VPN, and API reachability)"
fi

api="$(kubectl_cmd cluster-info 2>/dev/null | head -1 || true)"
[[ -n "$api" ]] && echo "Cluster:    $api"
echo

# Early toolbox pod check - fail fast with pod list if missing
_early_toolbox="$(discover_toolbox_pod)"
echo "Toolbox pod: ${_early_toolbox}"
echo

# --- Wizard: backup directory ---
BACKUP_DIR="$(prompt_with_default "Backup directory" "$BACKUP_DIR")"
[[ -d "$BACKUP_DIR" ]] || die "Backup directory not found: $BACKUP_DIR"
echo

# --- Wizard: EDA namespace ---
EDA_NAMESPACE="$(prompt_with_default "EDA namespace" "$EDA_NAMESPACE")"
echo

# --- Wizard: host safety ---
handle_host_safety
echo

# --- Wizard: toolbox pod ---
discovered_pod="${TOOLBOX_POD:-$_early_toolbox}"
if [[ -n "${TOOLBOX_POD:-}" ]]; then
  discovered_pod="$(discover_toolbox_pod)"
fi
if [[ "$NON_INTERACTIVE" != true ]]; then
  read -r -p "Toolbox pod [${discovered_pod}]: " pod_in
  if [[ -n "$pod_in" ]]; then
    TOOLBOX_POD="$pod_in"
    discovered_pod="$(discover_toolbox_pod)"
  fi
fi
TOOLBOX_POD="$discovered_pod"
echo

# --- Backup selection ---
select_backup_file

SRC="${BACKUP_DIR%/}/${BACKUP_FILE}"
[[ -f "$SRC" ]] || die "Backup not found: $SRC"

# --- Summary ---
echo
echo "=== Restore summary ==="
echo "  Context:    ${KUBE_CONTEXT}"
echo "  Backup dir: ${BACKUP_DIR}"
echo "  Backup:     ${BACKUP_FILE} ($(du -h "$SRC" | awk '{print $1}'))"
echo "  Namespace:  ${EDA_NAMESPACE}"
echo "  Toolbox:    ${TOOLBOX_POD}"
echo "  Command:    edactl platform restore ${POD_TMP}/${BACKUP_FILE} --exclude-security-git-repo"
echo "  Note:       CE will restart after restore completes."
echo

if ! prompt_yes_no "Proceed?" "y"; then
  die "Aborted by user"
fi

echo
echo "Copying backup into toolbox pod..."
kubectl_cmd cp "$SRC" "${EDA_NAMESPACE}/${TOOLBOX_POD}:${POD_TMP}/${BACKUP_FILE}"

echo "Running platform restore (timeout ${RESTORE_TIMEOUT})..."
kubectl_cmd exec -n "$EDA_NAMESPACE" "$TOOLBOX_POD" -- \
  edactl platform restore "${POD_TMP}/${BACKUP_FILE}" \
  --exclude-security-git-repo \
  --timeout "$RESTORE_TIMEOUT"

echo
echo "Restore command finished. CE may still be restarting - check EDA UI and:"
echo "  kubectl --context ${KUBE_CONTEXT} get pods -n ${EDA_NAMESPACE}"
echo "  kubectl --context ${KUBE_CONTEXT} get pods -A | grep -E 'eda|clab'"
\r': command not found):
#     sed -i 's/\r$//' eda-platform-restore.sh   # or: dos2unix eda-platform-restore.sh
#
# Environment variables (optional overrides; wizard prompts when unset):
#   KUBECONFIG          Path to kubeconfig (optional; default ~/.kube/config)
#   KUBE_CONTEXT        kubectl context name
#   EDA_NAMESPACE       Namespace for eda-toolbox pod (default: eda-system)
#   TOOLBOX_POD         Explicit toolbox pod name (skips auto-discovery)
#   TOOLBOX_LABEL       Label selector for toolbox pod (default: eda.nokia.com/app=eda-toolbox)
#   BACKUP_DIR          Directory containing platformbackup*.tar.gz
#   RESTORE_TIMEOUT     edactl timeout (default: 15m)
#   SKIP_HOST_CHECK     Set to 1 to skip hostname/context safety prompts
#   EXPECTED_HOST       Warn when hostname differs (default: k0r4)
#   EXPECTED_CONTEXT    Warn when kubectl context differs (default: admin@eda-compute-cluster)
#   EDA_UI_URL          Display only — helps confirm which cluster you mean
#
# Do NOT source this script (do not run: . eda-platform-restore.sh). Execute it directly.

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "" >&2
  echo "ERROR: Run with ./eda-platform-restore.sh not . eda-platform-restore.sh" >&2
  echo "       Sourcing corrupts your shell and can cause 'pop_var_context' errors." >&2
  echo "" >&2
  return 1 2>/dev/null || exit 1
fi

set -eu

if grep -q $'\r' "${BASH_SOURCE[0]}" 2>/dev/null; then
  echo "WARNING: This script has Windows (CRLF) line endings and may misbehave in bash." >&2
  echo "         Fix with: sed -i 's/\\r$//' ${BASH_SOURCE[0]}" >&2
  echo "" >&2
fi

NON_INTERACTIVE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) NON_INTERACTIVE=true; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
BACKUP_FILE_ARG="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PWD_DIR="$(pwd)"

EDA_NAMESPACE="${EDA_NAMESPACE:-eda-system}"
RESTORE_TIMEOUT="${RESTORE_TIMEOUT:-15m}"
TOOLBOX_LABEL="${TOOLBOX_LABEL:-eda.nokia.com/app=eda-toolbox}"
POD_TMP="/tmp"
EXPECTED_HOST="${EXPECTED_HOST:-k0r4}"
EXPECTED_CONTEXT="${EXPECTED_CONTEXT:-admin@eda-compute-cluster}"

if [[ -z "${BACKUP_DIR:-}" ]]; then
  if [[ "$PWD_DIR" == "$HOME/backups" ]] || [[ "$(basename "$PWD_DIR")" == "backups" ]]; then
    BACKUP_DIR="$PWD_DIR"
  elif [[ "$SCRIPT_DIR" == "$HOME/backups" ]] || [[ "$(basename "$SCRIPT_DIR")" == "backups" ]]; then
    BACKUP_DIR="$SCRIPT_DIR"
  else
    BACKUP_DIR="/home/nokia/backups"
  fi
fi

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

is_kind_context() {
  [[ "${1:-}" == kind-* ]]
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result=""
  if [[ "$NON_INTERACTIVE" == true ]]; then
    echo "$default"
    return
  fi
  read -r -p "${prompt} [${default}]: " result
  if [[ -z "$result" ]]; then
    echo "$default"
  else
    echo "$result"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-y}"
  local hint ans
  if [[ "$NON_INTERACTIVE" == true ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  if [[ "$default" == "y" ]]; then hint="Y/n"; else hint="y/N"; fi
  read -r -p "${prompt} [${hint}]: " ans
  if [[ -z "$ans" ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  confirm_yes "$ans"
}

list_contexts() {
  kubectl config get-contexts -o name 2>/dev/null || true
}

resolve_context_input() {
  local input="$1"
  local current="$2"
  mapfile -t contexts < <(list_contexts)

  if [[ -z "$input" ]]; then
    echo "$current"
    return
  fi

  if [[ "$input" =~ ^[0-9]+$ ]]; then
    local idx="$input"
    if [[ "$idx" -ge 1 && "$idx" -le ${#contexts[@]} ]]; then
      echo "${contexts[$((idx - 1))]}"
      return
    fi
  fi

  local c
  for c in "${contexts[@]}"; do
    if [[ "$c" == "$input" ]]; then
      echo "$input"
      return
    fi
  done

  echo "$input"
}

show_context_menu() {
  local current="$1"
  mapfile -t contexts < <(list_contexts)
  if [[ ${#contexts[@]} -eq 0 ]]; then
    echo "  (no contexts in kubeconfig)"
    return
  fi
  local i=1 c marker
  for c in "${contexts[@]}"; do
    marker=""
    [[ "$c" == "$current" ]] && marker=" *"
    printf "    %2d) %s%s\n" "$i" "$c" "$marker"
    i=$((i + 1))
  done
}

verify_cluster_reachable() {
  kubectl_cmd get nodes >/dev/null 2>&1
}

discover_toolbox_pod() {
  if [[ -n "${TOOLBOX_POD:-}" ]]; then
    local phase
    phase="$(kubectl_cmd get pod -n "$EDA_NAMESPACE" "$TOOLBOX_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ -n "$phase" ]] || die "Toolbox pod not found: ${EDA_NAMESPACE}/${TOOLBOX_POD}"
    echo "$TOOLBOX_POD"
    return
  fi

  local pod
  pod="$(kubectl_cmd get pods -n "$EDA_NAMESPACE" -l "$TOOLBOX_LABEL" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -1)"
  if [[ -n "$pod" ]]; then
    echo "$pod"
    return
  fi

  pod="$(kubectl_cmd get pods -n "$EDA_NAMESPACE" --no-headers 2>/dev/null | awk '/toolbox/{print $1; exit}')"
  if [[ -z "$pod" ]]; then
    echo "ERROR: No eda-toolbox pod in namespace ${EDA_NAMESPACE}." >&2
    echo "       Tried label ${TOOLBOX_LABEL} and name pattern 'toolbox'." >&2
    echo "       Check pods:" >&2
    kubectl_cmd get pods -n "$EDA_NAMESPACE" 2>&1 | sed 's/^/         /' >&2 || true
    die "eda-toolbox pod not found - install EDA or set TOOLBOX_POD / TOOLBOX_LABEL"
  fi
  echo "$pod"
}

select_backup_file() {
  if [[ -n "$BACKUP_FILE_ARG" ]]; then
    BACKUP_FILE="$BACKUP_FILE_ARG"
    return
  fi

  mapfile -t backup_files < <(
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'platformbackup*.tar.gz' -o -name 'platformbackup*.tgz' \) -printf '%f\n' 2>/dev/null | sort
  )
  if [[ ${#backup_files[@]} -eq 0 ]]; then
    mapfile -t backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' 2>/dev/null | sort)
  fi
  [[ ${#backup_files[@]} -gt 0 ]] || die "No .tar.gz backups found in ${BACKUP_DIR}"

  if [[ "$NON_INTERACTIVE" == true ]]; then
    BACKUP_FILE="${backup_files[-1]}"
    echo "Auto-selected latest backup: ${BACKUP_FILE}"
    return
  fi

  echo
  echo "Backups in ${BACKUP_DIR}:"
  local i=1 f size
  for f in "${backup_files[@]}"; do
    size="$(du -h "${BACKUP_DIR}/${f}" | awk '{print $1}')"
    printf "  %2d) %s  (%s)\n" "$i" "$f" "$size"
    i=$((i + 1))
  done
  echo
  read -r -p "Enter number or full backup file name: " choice
  [[ -n "$choice" ]] || die "No selection"

  if [[ "$choice" =~ ^[0-9]+$ ]]; then
    local idx="$choice"
    if [[ "$idx" -lt 1 || "$idx" -gt ${#backup_files[@]} ]]; then
      die "Invalid number: ${choice} (pick 1-${#backup_files[@]})"
    fi
    BACKUP_FILE="${backup_files[$((idx - 1))]}"
    echo "Selected: ${BACKUP_FILE}"
  else
    BACKUP_FILE="$choice"
  fi
}

handle_host_safety() {
  if [[ "${SKIP_HOST_CHECK:-}" == "1" ]]; then
    echo "Host safety checks: skipped (SKIP_HOST_CHECK=1)"
    return
  fi

  local host ctx
  host="$(hostname)"
  ctx="$KUBE_CONTEXT"

  if is_kind_context "$ctx"; then
    echo "Host safety checks: skipped (kind-* context)"
    return
  fi

  if [[ "$host" != "$EXPECTED_HOST" && "$ctx" != "$EXPECTED_CONTEXT" ]]; then
    echo "WSL/local mode, skipping Talos host check"
    return
  fi

  local host_mismatch=false ctx_mismatch=false

  [[ -n "$EXPECTED_HOST" && "$host" != "$EXPECTED_HOST" ]] && host_mismatch=true
  [[ -n "$EXPECTED_CONTEXT" && "$ctx" != "$EXPECTED_CONTEXT" ]] && ctx_mismatch=true

  if [[ "$host_mismatch" == false && "$ctx_mismatch" == false ]]; then
    echo "Host safety checks: passed (Talos lab defaults)"
    return
  fi

  echo
  echo "Host safety check (informational):"
  echo "  Host:    ${host}"
  echo "  Context: ${ctx}"
  if [[ "$host_mismatch" == true ]]; then
    echo "  NOTE: Hostname is not ${EXPECTED_HOST} (expected for Talos lab on k0r4)"
  fi
  if [[ "$ctx_mismatch" == true ]]; then
    echo "  NOTE: Context is not ${EXPECTED_CONTEXT} (expected for Talos lab)"
  fi

  if [[ "$NON_INTERACTIVE" == true ]]; then
    echo "Non-interactive mode: continuing despite mismatch"
    return
  fi

  local skip_default="y"
  if [[ "$host_mismatch" == false && "$ctx_mismatch" == false ]]; then
    skip_default="n"
  fi

  if prompt_yes_no "Skip Talos host/context safety checks?" "$skip_default"; then
    echo "Safety checks skipped by user"
    return
  fi

  if [[ "$host_mismatch" == true ]]; then
    prompt_yes_no "Hostname is not ${EXPECTED_HOST}. Continue anyway?" "y" || die "Aborted by user"
  fi
  if [[ "$ctx_mismatch" == true ]]; then
    prompt_yes_no "Context is not ${EXPECTED_CONTEXT}. Continue anyway?" "y" || die "Aborted by user"
  fi
}

echo "=== EDA platform restore ==="
echo
if [[ -n "${KUBECONFIG:-}" ]]; then
  echo "KUBECONFIG: ${KUBECONFIG}"
fi
if [[ -n "${EDA_UI_URL:-}" ]]; then
  echo "EDA UI:     ${EDA_UI_URL} (reference only - restore uses kubectl API)"
  echo
fi

# --- Wizard: kubectl context ---
if [[ -z "${KUBE_CONTEXT:-}" ]]; then
  KUBE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
fi

echo "kubectl context"
echo "  Current: ${KUBE_CONTEXT:-<none>}"
show_context_menu "${KUBE_CONTEXT:-}"

if [[ "$NON_INTERACTIVE" != true ]]; then
  read -r -p "Context [${KUBE_CONTEXT:-}]: " ctx_in
  KUBE_CONTEXT="$(resolve_context_input "$ctx_in" "${KUBE_CONTEXT:-}")"
  echo
fi

[[ -n "${KUBE_CONTEXT:-}" ]] || die "No kubectl context selected"

if ! verify_cluster_reachable; then
  echo "WARNING: Cannot reach cluster with context '${KUBE_CONTEXT}'"
  if [[ "$NON_INTERACTIVE" != true ]]; then
    echo "Available contexts:"
    show_context_menu "${KUBE_CONTEXT}"
    read -r -p "Pick context (number or name) [${KUBE_CONTEXT}]: " ctx_retry
    if [[ -n "$ctx_retry" ]]; then
      KUBE_CONTEXT="$(resolve_context_input "$ctx_retry" "$KUBE_CONTEXT")"
    fi
    echo
  fi
  verify_cluster_reachable || die "kubectl cannot reach the cluster (check KUBECONFIG, context, VPN, and API reachability)"
fi

api="$(kubectl_cmd cluster-info 2>/dev/null | head -1 || true)"
[[ -n "$api" ]] && echo "Cluster:    $api"
echo

# Early toolbox pod check - fail fast with pod list if missing
_early_toolbox="$(discover_toolbox_pod)"
echo "Toolbox pod: ${_early_toolbox}"
echo

# --- Wizard: backup directory ---
BACKUP_DIR="$(prompt_with_default "Backup directory" "$BACKUP_DIR")"
[[ -d "$BACKUP_DIR" ]] || die "Backup directory not found: $BACKUP_DIR"
echo

# --- Wizard: EDA namespace ---
EDA_NAMESPACE="$(prompt_with_default "EDA namespace" "$EDA_NAMESPACE")"
echo

# --- Wizard: host safety ---
handle_host_safety
echo

# --- Wizard: toolbox pod ---
discovered_pod="${TOOLBOX_POD:-$_early_toolbox}"
if [[ -n "${TOOLBOX_POD:-}" ]]; then
  discovered_pod="$(discover_toolbox_pod)"
fi
if [[ "$NON_INTERACTIVE" != true ]]; then
  read -r -p "Toolbox pod [${discovered_pod}]: " pod_in
  if [[ -n "$pod_in" ]]; then
    TOOLBOX_POD="$pod_in"
    discovered_pod="$(discover_toolbox_pod)"
  fi
fi
TOOLBOX_POD="$discovered_pod"
echo

# --- Backup selection ---
select_backup_file

SRC="${BACKUP_DIR%/}/${BACKUP_FILE}"
[[ -f "$SRC" ]] || die "Backup not found: $SRC"

# --- Summary ---
echo
echo "=== Restore summary ==="
echo "  Context:    ${KUBE_CONTEXT}"
echo "  Backup dir: ${BACKUP_DIR}"
echo "  Backup:     ${BACKUP_FILE} ($(du -h "$SRC" | awk '{print $1}'))"
echo "  Namespace:  ${EDA_NAMESPACE}"
echo "  Toolbox:    ${TOOLBOX_POD}"
echo "  Command:    edactl platform restore ${POD_TMP}/${BACKUP_FILE} --exclude-security-git-repo"
echo "  Note:       CE will restart after restore completes."
echo

if ! prompt_yes_no "Proceed?" "y"; then
  die "Aborted by user"
fi

echo
echo "Copying backup into toolbox pod..."
kubectl_cmd cp "$SRC" "${EDA_NAMESPACE}/${TOOLBOX_POD}:${POD_TMP}/${BACKUP_FILE}"

echo "Running platform restore (timeout ${RESTORE_TIMEOUT})..."
kubectl_cmd exec -n "$EDA_NAMESPACE" "$TOOLBOX_POD" -- \
  edactl platform restore "${POD_TMP}/${BACKUP_FILE}" \
  --exclude-security-git-repo \
  --timeout "$RESTORE_TIMEOUT"

echo
echo "Restore command finished. CE may still be restarting - check EDA UI and:"
echo "  kubectl --context ${KUBE_CONTEXT} get pods -n ${EDA_NAMESPACE}"
echo "  kubectl --context ${KUBE_CONTEXT} get pods -A | grep -E 'eda|clab'"
