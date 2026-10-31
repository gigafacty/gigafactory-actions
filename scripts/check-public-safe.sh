#!/usr/bin/env bash
# This repo is public. It may hold only generic, reusable code: every
# credential and every coordinate of a private system comes from the caller
# (inputs and secrets). This check fails on anything that is not generic:
# keys and tokens (gitleaks, the whole history) and the identifiers of our
# private systems, which are not secrets but say where to aim.
#
# Usage: scripts/check-public-safe.sh [dir]   (default: the repo root)
set -euo pipefail
dir="${1:-$(git rev-parse --show-toplevel)}"
cd "$dir"
fail=0

# Identifiers that must never appear. Project ids alone are allowed: the org
# name is public, and knowing a path grants nothing without IAM.
patterns=(
  '[a-z0-9-]+@[a-z0-9-]+\.iam\.gserviceaccount\.com'      # a service account
  '[0-9]{12}-compute@developer\.gserviceaccount\.com'      # a default compute SA
  'projects/[0-9]{6,}/'                                    # a project number in a resource path
  'workloadIdentityPools/[A-Za-z0-9_-]+/providers/'        # a WIF provider
  '[a-z0-9-]+-docker\.pkg\.dev/'                           # an Artifact Registry image path
  '[a-z0-9-]+-npm\.pkg\.dev/'                              # an Artifact Registry npm path
  'BEGIN [A-Z ]*PRIVATE KEY'                               # a private key
  '"type": *"service_account"'                             # a service account key file
)
for p in "${patterns[@]}"; do
  if hits=$(git grep -nIE "$p" -- . ':!scripts/check-public-safe.sh' ':!scripts/test-check-public-safe.sh'); then
    echo "::error::private identifier or key material (pattern: $p)"
    echo "$hits"
    fail=1
  fi
done

if command -v gitleaks >/dev/null; then
  gitleaks git . --no-banner --redact || fail=1
else
  echo "::error::gitleaks is not installed; the history scan did not run"
  fail=1
fi

exit "$fail"
