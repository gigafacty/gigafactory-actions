#!/usr/bin/env bash
# Universal convention rules — enforced for ALL managed projects.
set -euo pipefail

CONFIG="${1:-.gigafactory/project.yaml}"
VIOLATIONS=0

fail() { echo "::error::$*"; VIOLATIONS=$((VIOLATIONS + 1)); }

# ── Rule: Manifest validity ──────────────────────────────────────────────────
if [ ! -f "$CONFIG" ]; then
  fail "Missing .gigafactory/project.yaml manifest"
fi

if ! grep -q "^gigafactory:" "$CONFIG" 2>/dev/null; then
  fail "Manifest must start with 'gigafactory:' top-level key"
fi

if ! grep -q "version:" "$CONFIG" 2>/dev/null; then
  fail "Manifest missing 'version' field"
fi

if ! grep -q "language:" "$CONFIG" 2>/dev/null; then
  fail "Manifest missing 'stack.language' field"
fi

# ── Rule: No god files (>500 lines) ─────────────────────────────────────────
MAX_LINES=500
# Read max_file_length from manifest if set
manifest_max=$(grep 'max_file_length:' "$CONFIG" 2>/dev/null | awk '{print $2}' || true)
if [ -n "$manifest_max" ] && [ "$manifest_max" -gt 0 ] 2>/dev/null; then
  MAX_LINES=$manifest_max
fi

god_files=$(find . -name "*.go" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" | \
  grep -v node_modules | grep -v vendor | grep -v gen/ | grep -v .next/ | \
  xargs wc -l 2>/dev/null | awk -v max="$MAX_LINES" '$1 > max && !/total$/ {print}' || true)
if [ -n "$god_files" ]; then
  fail "Files exceeding ${MAX_LINES} lines (split into smaller modules):"
  echo "$god_files" | head -10
fi

# ── Rule: No secrets in code ─────────────────────────────────────────────────
secrets=$(grep -rn --include="*.go" --include="*.ts" --include="*.py" --include="*.tsx" \
  -E '(password|secret|api_key|apikey|token)\s*[:=]\s*["\x27][^\s]{8,}' . \
  --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=gen 2>/dev/null || true)
if [ -n "$secrets" ]; then
  fail "Potential hardcoded secrets found (use environment variables):"
  echo "$secrets" | head -5
fi

# ── Rule: No .env files committed ────────────────────────────────────────────
if git ls-files --cached | grep -qE '^\.env$|^\.env\.' 2>/dev/null; then
  fail ".env files should not be committed — add to .gitignore"
fi

# ── Rule: Meaningful commit messages ─────────────────────────────────────────
if [ -n "${GITHUB_EVENT_NAME:-}" ]; then
  last_msg=$(git log -1 --pretty=%s 2>/dev/null || true)
  if echo "$last_msg" | grep -qiE '^(fix|wip|test|asdf|tmp|xxx)$'; then
    fail "Commit message '${last_msg}' is not descriptive enough"
  fi
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "::error::${VIOLATIONS} universal convention violation(s) found"
  exit 1
fi

echo "✅ Universal conventions passed"
