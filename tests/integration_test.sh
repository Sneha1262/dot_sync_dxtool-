#!/bin/bash
# Integration test: verifies the full sync cycle across containers.
# Runs against real Docker containers — requires .env and SSH key to be set up.
# Usage: bash tests/integration_test.sh

set -e

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== DX Sync Platform — Integration Test ==="
echo ""

# ── 1. Start containers ────────────────────────────────────────────────────
echo "[1/5] Starting dev1 and dev2..."
docker compose up -d dev1 dev2

# ── 2. Wait for healthy ───────────────────────────────────────────────────
echo "[2/5] Waiting for containers to become healthy (max 60s)..."
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    s1=$(docker inspect --format='{{.State.Health.Status}}' dev_container_1 2>/dev/null || echo "starting")
    s2=$(docker inspect --format='{{.State.Health.Status}}' dev_container_2 2>/dev/null || echo "starting")
    if [ "$s1" = "healthy" ] && [ "$s2" = "healthy" ]; then
        echo "  Both containers healthy after ${elapsed}s."
        break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

if [ $elapsed -ge $timeout ]; then
    fail "Containers did not become healthy within ${timeout}s"
    docker logs dev_container_1 --tail 20
    exit 1
fi

# ── 3. Cross-container sync (SLA: 30s) ───────────────────────────────────
echo ""
echo "[3/5] Testing sync from dev1 → dev2 (SLA: 30s)..."
TEST_VALUE="integration-test-$(date +%s)"
TEST_FILE="/root/dots/.integration_test"

docker exec dev_container_1 bash -c "echo '$TEST_VALUE' > $TEST_FILE"

deadline=30
elapsed=0
synced=false
while [ $elapsed -lt $deadline ]; do
    result=$(docker exec dev_container_2 bash -c "cat $TEST_FILE 2>/dev/null" || echo "")
    if [ "$result" = "$TEST_VALUE" ]; then
        pass "File synced to dev2 in ${elapsed}s (SLA: 30s)"
        synced=true
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ "$synced" = false ]; then
    fail "File did not appear in dev2 within ${deadline}s"
    echo "  dev1 logs (last 20 lines):"
    docker logs dev_container_1 --tail 20
fi

# ── 4. New container bootstraps with latest state ─────────────────────────
echo ""
echo "[4/5] Testing new container bootstrap (dev3)..."
docker compose up -d dev3
sleep 15  # allow clone + pull on startup

result=$(docker exec dev_container_3 bash -c "cat $TEST_FILE 2>/dev/null" || echo "")
if [ "$result" = "$TEST_VALUE" ]; then
    pass "dev3 bootstrapped with latest state on startup"
else
    fail "dev3 did not have the test file after 15s startup wait"
fi

# ── 5. Cleanup ────────────────────────────────────────────────────────────
echo ""
echo "[5/5] Cleaning up test file..."
docker exec dev_container_1 bash -c "rm -f $TEST_FILE" 2>/dev/null || true
sleep 20  # let the delete propagate
result=$(docker exec dev_container_2 bash -c "cat $TEST_FILE 2>/dev/null" || echo "gone")
if [ "$result" = "gone" ] || [ -z "$result" ]; then
    pass "Deletion propagated to dev2"
else
    fail "Test file still present in dev2 after deletion"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
