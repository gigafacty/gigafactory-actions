#!/usr/bin/env bash
# Tests for check-public-safe.sh: a clean repo passes, each kind of leak fails.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
pass=0; failn=0
run() { # name, file content, expected exit (0 clean, 1 leak)
  local t; t="$(mktemp -d)"
  git -C "$t" init -q && git -C "$t" config user.email t@t && git -C "$t" config user.name t
  printf '%s\n' "$2" > "$t/action.yaml"
  git -C "$t" add . && git -C "$t" commit -qm test
  set +e; "$here/check-public-safe.sh" "$t" >/dev/null 2>&1; local got=$?; set -e
  if [ "$got" -eq "$3" ]; then pass=$((pass+1)); echo "ok   $1"; else failn=$((failn+1)); echo "FAIL $1 (exit $got, want $3)"; fi
  rm -rf "$t"
}
run "clean action"            'runs: { using: composite, steps: [] }'                             0
run "service account email"   'sa: image-publisher@acme.iam.gserviceaccount.com'                 1
run "default compute SA"      'sa: 123456789012-compute@developer.gserviceaccount.com'           1
run "project number path"     'p: projects/311338503065/locations/global'                        1
run "WIF provider"            'w: workloadIdentityPools/pool/providers/github-actions'           1
run "image registry path"     'image: us-central1-docker.pkg.dev/acme/images/api:1'              1
run "npm registry path"       'registry: https://us-central1-npm.pkg.dev/acme/npm/'              1
run "private key"             '-----BEGIN RSA PRIVATE KEY-----'                                  1
run "service account key"     '{"type": "service_account"}'                                      1
# Built at run time, so this file holds no token for gitleaks to find.
fake_token="ghp_$(head -c 600 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-36)"
run "GitHub token (gitleaks)" "token: $fake_token"                                            1
echo "$pass passed, $failn failed"; [ "$failn" -eq 0 ]
