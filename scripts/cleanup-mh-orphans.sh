#!/usr/bin/env bash
# Remove orphaned aggregated MH L3 CRs that block UI delete transactions.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "$ROOT/scripts/cleanup-mh-stale.sh"
