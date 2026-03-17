#!/usr/bin/env bash
# Python convention rules.
set -euo pipefail

VIOLATIONS=0
fail() { echo "::error::$*"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ── Rule: Type hints in function signatures ──────────────────────────────────
untyped=$(grep -rn --include="*.py" \
  -E '^def [a-z_]+\([^)]*\):\s*$' . \
  --exclude-dir=__pycache__ --exclude-dir=.venv --exclude-dir=venv 2>/dev/null || true)
if [ -n "$untyped" ]; then
  count=$(echo "$untyped" | wc -l | tr -d ' ')
  if [ "$count" -gt 10 ]; then
    fail "Many functions without type hints (${count}) — add return type annotations"
  fi
fi

# ── Rule: No psycopg2 (use psycopg v3) ──────────────────────────────────────
if grep -rq 'psycopg2' . --include="*.toml" --include="*.txt" --include="*.cfg" 2>/dev/null; then
  fail "psycopg2 found — use modern psycopg (v3) instead"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "::error::${VIOLATIONS} Python convention violation(s) found"
  exit 1
fi

echo "✅ Python conventions passed"
