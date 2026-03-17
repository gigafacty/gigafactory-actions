#!/usr/bin/env bash
# TypeScript/JavaScript convention rules.
set -euo pipefail

VIOLATIONS=0
fail() { echo "::error::$*"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ── Rule: No untyped `any` in TypeScript ─────────────────────────────────────
any_usage=$(grep -rn --include="*.ts" --include="*.tsx" \
  -E ':\s*any\b|as\s+any\b' . \
  --exclude-dir=node_modules --exclude-dir=gen --exclude-dir=.next 2>/dev/null || true)
if [ -n "$any_usage" ]; then
  count=$(echo "$any_usage" | wc -l | tr -d ' ')
  if [ "$count" -gt 5 ]; then
    fail "Excessive use of 'any' type (${count} occurrences) — use proper types"
  fi
fi

# ── Rule: tsconfig strict mode ───────────────────────────────────────────────
if [ -f "tsconfig.json" ]; then
  if ! grep -q '"strict":\s*true' tsconfig.json 2>/dev/null; then
    echo "::warning::tsconfig.json should have \"strict\": true"
  fi
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "::error::${VIOLATIONS} TypeScript convention violation(s) found"
  exit 1
fi

echo "✅ TypeScript conventions passed"
