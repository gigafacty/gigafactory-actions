#!/usr/bin/env bash
# ==============================================================================
# gcloud-ssh-retry.sh — retry a `gcloud compute ssh`/`scp` command through the
# transient OS-Login handshake race that intermittently aborts VM deploys.
#
# Why this exists
# ---------------
# A VM deploy fires a burst of `gcloud compute ssh`/`scp` calls over the IAP
# tunnel. GCP's guest agent (OS Login) periodically rewrites the instance's
# `oslogin_trustedca.pub` / authorized keys. When that rewrite lands *mid-burst*,
# an in-flight ssh/scp handshake is rejected with `Permission denied (publickey)`
# and gcloud exits 255 — even though an earlier call in the same job succeeded a
# few seconds before. It is an eventual-consistency propagation race, not a
# credential or config error, so the correct fix is a bounded retry: re-attempt
# the handshake until the guest agent settles. See gigafacty/gigafactory-actions#4.
#
# Scope of the retry is deliberately narrow. We retry ONLY when the captured
# output matches a known transient SSH-handshake signature (see TRANSIENT_RE).
# Any other non-zero exit — a failed remote command, a docker-compose that comes
# up unhealthy, a bad SQL migration — does NOT match and fails fast with its
# original exit code, so real errors are never masked or needlessly re-run.
#
# Usage
# -----
#   bash gcloud-ssh-retry.sh gcloud compute scp <args...>
#   bash gcloud-ssh-retry.sh gcloud compute ssh "$VM" ... --command="..."
#   bash gcloud-ssh-retry.sh gcloud compute ssh "$VM" ... --command="sudo bash -s" <<'SCRIPT'
#   ...remote heredoc...
#   SCRIPT
#
# Heredoc/stdin-fed commands are supported: stdin is slurped once up front and
# replayed from a temp file on every attempt (a raw heredoc fd is at EOF after
# the first read, which would send an empty script on retry). The same applies
# to a piped tar stream.
#
# Stalls
# ------
# An IAP-tunnelled transfer can also stall: no bytes move for minutes and
# nothing is printed, so there is no output for TRANSIENT_RE to match and the
# attempt never ends on its own — it runs until the job's step timeout. Set
# GCLOUD_SSH_ATTEMPT_TIMEOUT on calls that are safe to kill and re-run (file
# syncs, mkdir/chown) to bound each attempt; an attempt that hits the limit is
# retried like a handshake race. Leave it unset for long or non-idempotent
# remote commands (compose pull/up): killing those mid-way is not a retry.
#
# Tunables (env):
#   GCLOUD_SSH_RETRIES          max attempts         (default 5)
#   GCLOUD_SSH_BACKOFF          base backoff seconds (default 5; linear: base*attempt)
#   GCLOUD_SSH_ATTEMPT_TIMEOUT  seconds per attempt  (default 0 = no limit)
# ==============================================================================
set -uo pipefail

MAX_ATTEMPTS="${GCLOUD_SSH_RETRIES:-5}"
BASE_BACKOFF="${GCLOUD_SSH_BACKOFF:-5}"
ATTEMPT_TIMEOUT="${GCLOUD_SSH_ATTEMPT_TIMEOUT:-0}"

# GNU timeout runs the command in its own process group and signals the whole
# group, so gcloud's ssh/scp child and its IAP tunnel helper die with it. It
# exits 124 when the limit hit, or 137 when the command ignored TERM and had to
# be KILLed after the grace period.
RUN=("$@")
if [ "$ATTEMPT_TIMEOUT" -gt 0 ]; then
  if command -v timeout >/dev/null 2>&1; then
    RUN=(timeout --kill-after=10 "$ATTEMPT_TIMEOUT" "$@")
  else
    echo "::warning::GCLOUD_SSH_ATTEMPT_TIMEOUT=${ATTEMPT_TIMEOUT} ignored: timeout(1) is not installed"
    ATTEMPT_TIMEOUT=0
  fi
fi

# Transient SSH-*handshake* signatures worth retrying. Case-insensitive. These
# are all pre-auth / connection-establishment failures the remote command never
# started for, so re-attempting is safe and idempotent. We deliberately do NOT
# match gcloud's generic "exited with return code [255]" wrapper: a real
# transport race always prints one of these specific reasons first, while a
# remote command in the `ssh ... "sudo bash -s"` heredoc deploys can exit 255 on
# its own — matching the bare 255 would wrongly retry a real deploy failure.
TRANSIENT_RE='Permission denied \(publickey|Connection closed|Connection reset by peer|kex_exchange_identification|banner exchange|Connection timed out|Operation timed out|port 22|Broken pipe'

# Slurp stdin once so heredoc-fed commands can be replayed on each attempt.
# In a GitHub Actions `run:` step stdin is /dev/null, so for the short ssh/scp
# calls this reads nothing and the temp file stays empty. An empty file redirected
# as stdin is identical to closed stdin for these non-interactive commands, so we
# always redirect it and avoid branching on whether a heredoc was supplied.
STDIN_FILE="$(mktemp)"
cat > "$STDIN_FILE" 2>/dev/null || true

LOG_FILE="$(mktemp)"
cleanup() { rm -f "$STDIN_FILE" "$LOG_FILE"; }
trap cleanup EXIT

attempt=1
while :; do
  # Stream combined output live (tee) while capturing it for transient
  # detection. PIPESTATUS[0] is the command's exit code, not tee's.
  "${RUN[@]}" < "$STDIN_FILE" 2>&1 | tee "$LOG_FILE"
  rc="${PIPESTATUS[0]}"

  if [ "$rc" -eq 0 ]; then
    exit 0
  fi

  if [ "$ATTEMPT_TIMEOUT" -gt 0 ] && { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; }; then
    reason="stalled past ${ATTEMPT_TIMEOUT}s"
  elif grep -qiE "$TRANSIENT_RE" "$LOG_FILE"; then
    reason="OS-Login handshake race"
  else
    # Not transient — fail fast with the real exit code.
    exit "$rc"
  fi

  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "::error::gcloud ssh/scp failed on all ${MAX_ATTEMPTS} attempts (last: ${reason}, rc=${rc})"
    exit "$rc"
  fi

  wait_s=$(( BASE_BACKOFF * attempt ))
  echo "::warning::gcloud ssh/scp transient failure (attempt ${attempt}/${MAX_ATTEMPTS}, rc=${rc}) — ${reason}, retrying in ${wait_s}s"
  sleep "$wait_s"
  attempt=$(( attempt + 1 ))
done
