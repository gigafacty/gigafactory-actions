#!/usr/bin/env bash
# StateMesh convention rules — enforced when stack.statemesh: true.
set -euo pipefail

VIOLATIONS=0
fail() { echo "::error::$*"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ── Rule: No east-west HTTP between internal services ────────────────────────
east_west=$(grep -rn --include="*.go" \
  -E 'http\.(Post|Get|NewRequest).*localhost|httpClient\.Do' . \
  --exclude-dir=vendor --exclude-dir=gen --exclude-dir=integrations 2>/dev/null || true)
if [ -n "$east_west" ]; then
  fail "East-west HTTP detected — StateMesh services communicate via Postgres state"
fi

# ── Rule: MOCK_* env vars not allowed ────────────────────────────────────────
mock_vars=$(grep -rn --include="*.go" \
  'os\.Getenv("MOCK_' . \
  --exclude-dir=vendor --exclude-dir=gen 2>/dev/null || true)
if [ -n "$mock_vars" ]; then
  fail "MOCK_* env vars found — use core.service_config for fixture control"
fi

# ── Rule: Proto-first types ─────────────────────────────────────────────────
# Check for hand-written API request/response structs in handler code
hand_written=$(grep -rn --include="*.go" \
  -E 'type .*(Request|Response) struct' . \
  --exclude-dir=vendor --exclude-dir=gen 2>/dev/null | \
  grep -v '_test.go' | grep -v 'internal' || true)
if [ -n "$hand_written" ]; then
  echo "::warning::Hand-written Request/Response structs found — consider using proto-generated types"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "::error::${VIOLATIONS} StateMesh convention violation(s) found"
  exit 1
fi

echo "✅ StateMesh conventions passed"
