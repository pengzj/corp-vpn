#!/usr/bin/env bash
# Run all unit tests — backend (Zig) + frontend (vitest)
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

echo "================================================"
echo "  ops_vpn test suite"
echo "================================================"
echo ""

# ---- Backend: Zig unit tests ----
echo "[ Backend — Zig ]"
cd "$ROOT/backend"
if zig build test; then
  echo "  ✓ All Zig tests passed"
  PASS=$((PASS + 1))
else
  echo "  ✗ Zig tests FAILED"
  FAIL=$((FAIL + 1))
fi

echo ""

# ---- Frontend: vitest ----
echo "[ Frontend — vitest ]"
cd "$ROOT/frontend"
if yarn test --reporter=verbose 2>&1; then
  echo "  ✓ All frontend tests passed"
  PASS=$((PASS + 1))
else
  echo "  ✗ Frontend tests FAILED"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "================================================"
if [ $FAIL -eq 0 ]; then
  echo "  ✓ All test suites passed ($PASS/$((PASS + FAIL)))"
  echo "================================================"
  exit 0
else
  echo "  ✗ $FAIL suite(s) failed"
  echo "================================================"
  exit 1
fi
