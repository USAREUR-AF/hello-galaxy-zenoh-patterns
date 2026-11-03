#!/usr/bin/env bash
# Pattern C — per-event history.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Pattern C — per-event history" \
          "Unique id per event on a persisted prefix. Replay a window with key-expr + time."

hz_preflight || exit 1
ANCHOR="$(hz_anchor)"
PREFIX="$ANCHOR/hello/orders/v1"
RUN="$(hz_run_id)"

hz_step "The key shape — stable prefix, UNIQUE id last"
hz_note "$PREFIX/<event-id>   (sortable id so key order = time order)"

hz_step "Publish three DISTINCT events to three unique keys"
n=0
for label in alpha bravo charlie; do
  n=$((n+1))
  # a sortable-ish event id: epoch-seconds + sequence, tagged with this run
  EID="$(date +%s)-$n-$RUN"
  KEY="$PREFIX/$EID"
  hz_cmd "goat pub $KEY --payload '{\"order\":\"$label\",\"run\":\"$RUN\"}'"
  hz_goat pub "$KEY" --payload "{\"order\":\"$label\",\"seq\":$n,\"run\":\"$RUN\"}" --encoding json --confirm >/dev/null 2>&1 \
    && hz_note "landed: $KEY" \
    || hz_note "write not confirmed for $KEY (check write-ACL for your anchor)"
  sleep 1
done

hz_step "Let the audit-tail ingest before replaying it"
hz_settle 10

hz_step "Replay the WHOLE feed with the ** key expression + a time window"
hz_cmd  "goat replay $PREFIX/** --since 10m"
HIST="$(hz_goat replay "$PREFIX/**" --since 10m 2>&1 || true)"
printf '%s\n' "$HIST" | sed 's/^/    /'
hz_say  "All three events come back. Nothing overwrote anything — each event"
hz_say  "had its own key, and a history storage (the audit-tail) retained them."
hz_note "The key expression (**) picks structure; --since picks the time window."
hz_note "Contrast Pattern A: re-using one key left only the latest in storage."

# --- assertions -------------------------------------------------------------
hz_step "Verify all three events are individually retrievable"
hz_assert_contains "replay returned the 'alpha' event"   "$HIST" "alpha"
hz_assert_contains "replay returned the 'bravo' event"   "$HIST" "bravo"
hz_assert_contains "replay returned the 'charlie' event" "$HIST" "charlie"
hz_assert_contains "all events are from this run"         "$HIST" "$RUN"
hz_done
