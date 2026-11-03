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

hz_step "Open a live subscription on the feed first (the participant's view)"
hz_cmd  "goat sub '$PREFIX/**' --count 3 --for 45s"
hz_sub_start "$PREFIX/**" 3 live
hz_say  "Any participant may watch new events arrive. History replay is the part"
hz_say  "that needs a history storage — and, on a goatnet, an operator key."

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

hz_step "What the live subscription received"
hz_sub_wait
LIVE="$(hz_sub_events live)"
hz_sub_output live | sed 's/^/    /'

hz_step "Let the audit-tail ingest before replaying it"
hz_settle 10

hz_step "Replay the WHOLE feed with the ** key expression + a time window"
hz_cmd  "goat replay $PREFIX/** --since 10m"
HIST="$(hz_goat replay "$PREFIX/**" --since 10m 2>&1 || true)"
printf '%s\n' "$HIST" | sed 's/^/    /'
GATED=0
if printf '%s' "$HIST" | grep -q "operator-gated"; then
  GATED=1
  hz_say  "This goatnet gates the audit-tail: replaying history needs an operator key,"
  hz_say  "and this context is a participant. The events were published and the live"
  hz_say  "subscription above received them; only the after-the-fact replay is gated."
else
  hz_say  "All three events come back. Nothing overwrote anything — each event"
  hz_say  "had its own key, and a history storage (the audit-tail) retained them."
fi
hz_note "The key expression (**) picks structure; --since picks the time window."
hz_note "Contrast Pattern A: re-using one key left only the latest in storage."

# --- assertions -------------------------------------------------------------
hz_step "Verify"
hz_assert_contains "live subscription received the 'alpha' event"   "$LIVE" "alpha"
hz_assert_contains "live subscription received the 'bravo' event"   "$LIVE" "bravo"
hz_assert_contains "live subscription received the 'charlie' event" "$LIVE" "charlie"
if [ "$GATED" -eq 1 ]; then
  WHY="history read-back needs an operator key on this goatnet"
  hz_skip "replay returned the 'alpha' event"   "$WHY"
  hz_skip "replay returned the 'bravo' event"   "$WHY"
  hz_skip "replay returned the 'charlie' event" "$WHY"
  hz_skip "replayed events are from this run"   "$WHY"
else
  hz_assert_contains "replay returned the 'alpha' event"   "$HIST" "alpha"
  hz_assert_contains "replay returned the 'bravo' event"   "$HIST" "bravo"
  hz_assert_contains "replay returned the 'charlie' event" "$HIST" "charlie"
  hz_assert_contains "replayed events are from this run"   "$HIST" "$RUN"
fi
hz_done
