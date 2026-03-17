#!/usr/bin/env bash
# Go convention rules.
set -euo pipefail

VIOLATIONS=0
fail() { echo "::error::$*"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ── Rule: Error wrapping ────────────────────────────────────────────────────
bare_returns=$(grep -rn --include="*.go" \
  -E 'return err$' . \
  --exclude-dir=vendor --exclude-dir=gen 2>/dev/null || true)
if [ -n "$bare_returns" ]; then
  count=$(echo "$bare_returns" | wc -l | tr -d ' ')
  if [ "$count" -gt 20 ]; then
    echo "::warning::${count} bare 'return err' (consider wrapping with fmt.Errorf)"
  fi
fi

# ── Rule: No fmt.Println in production code ──────────────────────────────────
print_calls=$(grep -rn --include="*.go" \
  'fmt\.Println\|fmt\.Printf' . \
  --exclude-dir=vendor --exclude-dir=gen --exclude-dir=cmd 2>/dev/null || true)
if [ -n "$print_calls" ]; then
  fail "fmt.Println/Printf in production code — use structured logging (zerolog)"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "::error::${VIOLATIONS} Go convention violation(s) found"
  exit 1
fi

echo "✅ Go conventions passed"
