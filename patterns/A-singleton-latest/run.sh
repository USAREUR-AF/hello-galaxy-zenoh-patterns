#!/usr/bin/env bash
# Pattern A — singleton / latest value.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Pattern A — singleton / latest value" \
          "One fixed key. The router's latest-value storage keeps the current value only."

hz_preflight || exit 1
ANCHOR="$(hz_anchor)"
KEY="$ANCHOR/hello/state"
RUN="$(hz_run_id)"

hz_step "The key — one, fixed, forever"
hz_note "$KEY"
hz_say  "We never vary this key. It represents a single value we keep current."

hz_step "Publish a FIRST value"
hz_cmd  "goat pub $KEY --payload '{\"mode\":\"standby\",\"run\":\"$RUN-1\"}'"
hz_goat pub "$KEY" --payload "{\"mode\":\"standby\",\"run\":\"$RUN-1\"}" --encoding json
hz_say  "Sent. A latest-value storage now holds this as the current value at the key."

hz_step "Publish a SECOND value to the SAME key"
hz_cmd  "goat pub $KEY --payload '{\"mode\":\"active\",\"run\":\"$RUN-2\"}' --confirm"
OUT="$(hz_goat pub "$KEY" --payload "{\"mode\":\"active\",\"run\":\"$RUN-2\"}" --encoding json --confirm 2>&1)"
RC=$?
printf '%s\n' "$OUT"
hz_say  "--confirm reads the key back from router storage after writing."

hz_step "What the storage holds now"
hz_say  "The read-back reflects the SECOND value (mode=active, run=$RUN-2)."
hz_say  "The first value is no longer the current value at this key — a"
hz_say  "latest-value storage keeps exactly one sample per key."
hz_note "Need every value over time? That's Pattern C (per-event history)."
hz_note "Need many entities at once? That's Pattern B (per-entity state)."

# --- assertions -------------------------------------------------------------
hz_step "Verify"
hz_assert_contains "the confirmed write landed in storage" "$OUT" "landed"
[ "$RC" -eq 0 ] && printf '    %s✓%s goat pub --confirm exited cleanly (write landed)\n' "$C_GREEN" "$C_RESET" \
  || { printf '    %s✗%s goat pub --confirm reported the write did not land (rc=%s)\n' "$C_RED" "$C_RESET" "$RC" >&2; HZ_FAILS=$((HZ_FAILS+1)); }
hz_done
