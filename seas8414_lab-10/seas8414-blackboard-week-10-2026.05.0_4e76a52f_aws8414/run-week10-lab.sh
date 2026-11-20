#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/run-week-lab-common.sh"
if [ ! -f "$COMMON" ]; then
  echo "ERROR: Missing bundled script: $COMMON" >&2
  echo "Extract the complete Week 10 Blackboard ZIP before running the lab." >&2
  exit 1
fi
chmod +x "$COMMON"

PHASE=10 WEEK=10 LAB_TITLE="Active Deception and Threat Hunting" exec "$COMMON" "$@"

