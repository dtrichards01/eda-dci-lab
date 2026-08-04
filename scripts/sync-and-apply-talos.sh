#!/usr/bin/env bash
# Full sync from Windows repo + apply aligned DCI/MH services on Talos.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/sync-repo-to-talos.sh"
HOST="${TALOS_HOST:-nokia@100.124.186.51}"
PASS="${TALOS_PASS:-}"
if [ -n "$PASS" ]; then
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$HOST" "bash ~/eda-dci-lab/scripts/apply-all.sh"
else
  ssh -o StrictHostKeyChecking=no "$HOST" "bash ~/eda-dci-lab/scripts/apply-all.sh"
fi
