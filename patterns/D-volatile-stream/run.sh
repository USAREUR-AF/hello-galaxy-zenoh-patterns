#!/usr/bin/env bash
# Pattern D — volatile stream (routed, never retained).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Pattern D — volatile stream" \
          "High-rate, loss-tolerant, NOT retained. Retrieval-after-the-fact is impossible by design."

hz_preflight || exit 1
ANCHOR="$(hz_anchor)"
PREFIX="volatile/$ANCHOR/stream"
RUN="$(hz_run_id)"

hz_step "The key shape — the top-level volatile/ class"
hz_note "$PREFIX/<...>   (DROP congestion control; never persisted)"

hz_step "Publish a few volatile samples ( --volatile-stream )"
for i in 1 2 3 4 5; do
  KEY="$PREFIX/telemetry"
  hz_cmd "goat pub $KEY --volatile-stream --payload '{\"seq\":$i,\"run\":\"$RUN\"}'"
  hz_goat pub "$KEY" --volatile-stream --payload "{\"seq\":$i,\"run\":\"$RUN\"}" --encoding json >/dev/null 2>&1 \
    && hz_note "sent (fire-and-forget, DROP): seq $i" \
    || hz_note "publish failed for seq $i (check write-ACL for volatile/$ANCHOR/**)"
done
hz_say  "Note: --volatile-stream is incompatible with --confirm — there is"
hz_say  "nothing to read back, because nothing is retained."

hz_step "Try to replay the volatile prefix — expect NOTHING"
hz_cmd  "goat replay $PREFIX/** --since 10m"
HIST="$(hz_goat replay "$PREFIX/**" --since 10m 2>&1 || true)"
if [ -z "$(printf '%s' "$HIST" | tr -d '[:space:]')" ]; then
  hz_note "(empty — as designed)"
else
  printf '%s\n' "$HIST" | sed 's/^/    /'
fi
hz_say  "Empty — the volatile class is excluded from durable + audit storage."
hz_say  "Live subscribers DID receive these samples; only after-the-fact"
hz_say  "retrieval is — intentionally — impossible."
hz_note "Need to pull it back later? It doesn't belong in volatile/ — use B or C."

# --- assertions -------------------------------------------------------------
hz_step "Verify the volatile prefix retained nothing from this run"
hz_assert_lacks "replay of the volatile prefix has no events from this run" "$HIST" "$RUN"
hz_done
