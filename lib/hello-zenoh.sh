# shellcheck shell=bash
# hello-zenoh.sh — shared library for the "Hello Galaxy: Zenoh patterns" series.
#
# Sourced by every pattern driver. Provides: environment resolution (which goat
# context / fabric a demo runs against), the `goat` invocation wrapper, the
# producer-anchor derivation, a per-run unique suffix (so reruns don't collide),
# pretty narration, and lightweight assertions.
#
# Execution model — against a running fabric (your active goat context):
#   Every demo talks to a running Zenoh fabric using your real goat
#   profile. Publishes land under YOUR OWN write namespace (<anchor>/hello/...),
#   so they are admitted by the slot ACL and isolated from everyone else's keys.
#   Nothing here injects load on anyone else's prefix and nothing is faked.
#
# Nothing environment-specific is hardcoded: the router endpoint and the
# producer anchor are read from the active goat profile at runtime.

set -o pipefail

# --- resolve repo root regardless of caller cwd -----------------------------
HZ_LIB="${BASH_SOURCE[0]}"
HZ_ROOT="$(cd "$(dirname "$HZ_LIB")/.." && pwd)"
export HZ_ROOT

# --- environment selection --------------------------------------------------
# HZ_ENV names a goat context (e.g. "my-goatnet"). Default: the
# profile's active context, resolved the way goat itself does ($GOAT_CONTEXT,
# then current_context in config.toml, then "default") — so a bare run works
# on any machine without naming a context.
hz_active_context() {
  if [ -n "${GOAT_CONTEXT:-}" ]; then echo "$GOAT_CONTEXT"; return; fi
  local cfg="${GOAT_PROFILE_DIR:-$HOME/.goat}/config.toml" cur=""
  [ -f "$cfg" ] && cur="$(sed -n 's/^current_context *= *"\(.*\)"/\1/p' "$cfg" | head -n1)"
  echo "${cur:-default}"
}
HZ_ENV="${HZ_ENV:-$(hz_active_context)}"

# Parse a leading `--env <name>` out of a driver's args. Call as:
#   hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}
hz_parse_env() {
  HZ_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --env) HZ_ENV="$2"; shift 2 ;;
      --env=*) HZ_ENV="${1#--env=}"; shift ;;
      *) HZ_ARGS+=("$1"); shift ;;
    esac
  done
  export HZ_ENV
}

# --- goat invocation --------------------------------------------------------
# `goat --context <env>` against the operator's ~/.goat profile for that env.
hz_goat() { goat --context "$HZ_ENV" "$@"; }

# --- producer anchor (the writable namespace prefix the ACL keys on) --------
# The anchor is the mTLS cert CN. On a slot-cert fabric it is the 32-hex slot
# id; the write ACL admits writes whose key's FIRST segment is that anchor.
# Derive it from the active profile's cert so no identifier is baked into the
# repo and the demos work for any operator on any goatnet.
hz_cert_path() { echo "${GOAT_PROFILE_DIR:-$HOME/.goat}/contexts/$HZ_ENV/mtls.cert.pem"; }

hz_anchor() {
  local cert cn
  cert="$(hz_cert_path)"
  if [ ! -f "$cert" ]; then return 1; fi
  cn="$(openssl x509 -in "$cert" -noout -subject 2>/dev/null \
        | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p' | tr -d '[:space:]')"
  echo "$cn"
}

# A short, per-run token so repeated runs publish to fresh keys instead of
# silently overwriting the last run's (which would hide the pattern's point).
hz_run_id() { echo "r$(date +%s)$$"; }

# Reading from the audit-tail right after publishing can miss the newest events:
# `put` is fire-and-forget, and the history storage subscribes + persists
# asynchronously. Give it a moment before a read-back so the demo isn't racing
# ingestion. (This wait is itself the lesson — retrieval is a separate operation
# against a storage that has to ingest first.)
hz_settle() {
  local secs="${1:-10}"
  hz_say "Letting the audit-tail ingest (~${secs}s) — publish is async, the"
  hz_say "history storage persists the events before a query can return them."
  sleep "$secs"
}

# --- presentation -----------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_CYAN=""; C_BLUE=""
fi

HZ_STEP=0
hz_banner() {
  printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"
  [ -n "${2:-}" ] && printf '%s%s%s\n' "$C_DIM" "$2" "$C_RESET"
  printf '%senv: %s · anchor: %s%s\n' "$C_DIM" "$HZ_ENV" "$(hz_anchor || echo '<no cert>')" "$C_RESET"
}
hz_step() { HZ_STEP=$((HZ_STEP + 1)); printf '\n%s%s[%d] %s%s\n' "$C_BOLD" "$C_CYAN" "$HZ_STEP" "$1" "$C_RESET"; }
hz_say()  { printf '    %s\n' "$1"; }
hz_note() { printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
hz_cmd()  { printf '    %s$ %s%s\n' "$C_GREEN" "$1" "$C_RESET"; }

# --- preflight --------------------------------------------------------------
hz_preflight() {
  if ! command -v goat >/dev/null 2>&1; then
    printf '%sgoat is not on your PATH.%s See the repo README → Prerequisites.\n' "$C_RED" "$C_RESET" >&2
    return 1
  fi
  local anchor; anchor="$(hz_anchor || true)"
  if [ -z "$anchor" ]; then
    printf '%sNo mTLS cert for context "%s".%s Run `goat init` or `goat context use %s`.\n' \
      "$C_RED" "$HZ_ENV" "$C_RESET" "$HZ_ENV" >&2
    return 1
  fi
  return 0
}

# --- assertions -------------------------------------------------------------
HZ_FAILS=0
hz_assert_contains() {
  local what="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$what"
  else
    printf '    %s✗%s %s (expected to find: %s)\n' "$C_RED" "$C_RESET" "$what" "$needle" >&2
    HZ_FAILS=$((HZ_FAILS + 1))
  fi
}
hz_assert_lacks() {
  local what="$1" hay="$2" needle="$3"
  if printf '%s' "$hay" | grep -qF -- "$needle"; then
    printf '    %s✗%s %s (did NOT expect: %s)\n' "$C_RED" "$C_RESET" "$what" "$needle" >&2
    HZ_FAILS=$((HZ_FAILS + 1))
  else
    printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$what"
  fi
}
hz_done() {
  if [ "$HZ_FAILS" -eq 0 ]; then
    printf '\n%s%s✓ pattern complete — every assertion held.%s\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    return 0
  fi
  printf '\n%s%s✗ %d assertion(s) failed.%s\n' "$C_BOLD" "$C_RED" "$HZ_FAILS" "$C_RESET" >&2
  return 1
}
