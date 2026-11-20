#!/usr/bin/env bash
# reset-lab.sh — Full lab environment reset: stop, clean, rebuild, seed.
#
# Usage:
#   ./reset-lab.sh              # Reset and restart everything
#   ./reset-lab.sh --no-seed    # Reset without seeding a student user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SKIP_SEED=false
for arg in "$@"; do
    case "$arg" in
        --no-seed) SKIP_SEED=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ── Step 1: Stop all containers ──────────────────────────────────────────────

echo "[*] Stopping all lab containers ..."
docker compose down --remove-orphans 2>/dev/null || true

# ── Step 2: Remove volumes ───────────────────────────────────────────────────

echo "[*] Removing volumes (database, caches) ..."
docker compose down -v 2>/dev/null || true

# ── Step 3: Rebuild and start fresh ──────────────────────────────────────────

echo "[*] Starting fresh lab environment ..."
docker compose up -d --build

# ── Step 4: Wait for infrastructure to be healthy ────────────────────────────

echo "[*] Waiting for services to become healthy ..."

MAX_WAIT=120
POLL_INTERVAL=5
elapsed=0

while true; do
    # Check if api is healthy via docker health status
    API_HEALTH=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    svc = json.loads(line)
    if svc.get('Service') == 'api':
        print(svc.get('Health', 'unknown'))
        break
" 2>/dev/null || echo "unknown")

    if [ "$API_HEALTH" = "healthy" ]; then
        echo "[+] All services are healthy."
        break
    fi

    elapsed=$((elapsed + POLL_INTERVAL))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[!] WARNING: Services did not become healthy within ${MAX_WAIT}s."
        echo "    Continuing anyway. Check logs with:  docker compose logs"
        break
    fi

    printf "    ... waiting for API health (%ds / %ds) [status: %s]\n" \
        "$elapsed" "$MAX_WAIT" "$API_HEALTH"
    sleep "$POLL_INTERVAL"
done

# ── Step 5: Seed data ────────────────────────────────────────────────────────

if [ "$SKIP_SEED" = false ]; then
    echo ""
    bash "$SCRIPT_DIR/seed-data.sh"
else
    echo ""
    echo "[*] Skipping seed data (--no-seed flag)."
fi

echo ""
echo "============================================================"
echo "  Lab environment ready"
echo "============================================================"
echo ""
echo "  API:         http://localhost:8100"
echo "  Health:      http://localhost:8100/health"
echo "  API docs:    http://localhost:8100/docs"
echo "  Network:     172.30.0.0/24 (iotsim-net)"
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f api         # Watch API logs"
echo "    docker compose ps                  # Service status"
echo "    docker compose down -v             # Full cleanup"
echo ""
echo "============================================================"
