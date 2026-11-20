#!/usr/bin/env bash
# seed-data.sh — Wait for API, register a test student user, print credentials.
#
# Usage:
#   ./seed-data.sh                     # Uses default http://localhost:8100
#   API_URL=http://host:8100 ./seed-data.sh

set -euo pipefail

API_URL="${API_URL:-http://localhost:8100}"
MAX_WAIT=120   # seconds
POLL_INTERVAL=3

STUDENT_EMAIL="student@example.com"
STUDENT_PASSWORD="breakwater-lab-2026"
STUDENT_NAME="Lab Student"

# ── Wait for API health ──────────────────────────────────────────────────────

echo "[*] Waiting for API to become healthy at ${API_URL}/health ..."

elapsed=0
while true; do
    if curl -sf "${API_URL}/health" > /dev/null 2>&1; then
        echo "[+] API is healthy."
        break
    fi
    elapsed=$((elapsed + POLL_INTERVAL))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[!] ERROR: API did not become healthy within ${MAX_WAIT}s."
        echo "    Check logs with:  docker compose logs api"
        exit 1
    fi
    printf "    ... waiting (%ds / %ds)\n" "$elapsed" "$MAX_WAIT"
    sleep "$POLL_INTERVAL"
done

# ── Register student user ────────────────────────────────────────────────────

echo "[*] Registering student user (${STUDENT_EMAIL}) ..."

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"email\": \"${STUDENT_EMAIL}\",
        \"password\": \"${STUDENT_PASSWORD}\",
        \"full_name\": \"${STUDENT_NAME}\"
    }")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "201" ]; then
    echo "[+] User registered successfully."
elif [ "$HTTP_CODE" = "409" ]; then
    echo "[*] User already exists — logging in instead."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"${STUDENT_EMAIL}\",
            \"password\": \"${STUDENT_PASSWORD}\"
        }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" != "200" ]; then
        echo "[!] ERROR: Login failed (HTTP ${HTTP_CODE})."
        echo "    Response: ${BODY}"
        exit 1
    fi
else
    echo "[!] ERROR: Registration failed (HTTP ${HTTP_CODE})."
    echo "    Response: ${BODY}"
    exit 1
fi

# ── Extract and display token ─────────────────────────────────────────────────

ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null || true)

if [ -z "$ACCESS_TOKEN" ]; then
    echo "[!] WARNING: Could not extract access token from response."
    echo "    Response: ${BODY}"
    exit 1
fi

echo ""
echo "============================================================"
echo "  Lab Environment Seeded Successfully"
echo "============================================================"
echo ""
echo "  API URL:    ${API_URL}"
echo "  Email:      ${STUDENT_EMAIL}"
echo "  Password:   ${STUDENT_PASSWORD}"
echo ""
echo "  Access Token (for API calls):"
echo "  ${ACCESS_TOKEN}"
echo ""
echo "  Example usage:"
echo "    curl -H 'Authorization: Bearer ${ACCESS_TOKEN}' ${API_URL}/health"
echo ""
echo "============================================================"
