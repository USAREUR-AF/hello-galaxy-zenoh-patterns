#!/usr/bin/env bash
# Pattern B — per-entity state.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Pattern B — per-entity state" \
          "Entity id last, version in the prefix. One key per thing, latest value each."

hz_preflight || exit 1
ANCHOR="$(hz_anchor)"
PREFIX="$ANCHOR/hello/aircraft/v1"
RUN="$(hz_run_id)"

hz_step "The key shape — version in the prefix, entity id LAST"
hz_note "$PREFIX/<entity-id>"
hz_say  "Three aircraft become three keys that differ only in the last segment."

hz_step "Subscribe live BEFORE publishing — one exact key, and the whole group"
hz_cmd  "goat sub $PREFIX/A7 --count 1 --for 45s     # ONE entity, by its exact key"
hz_cmd  "goat sub '$PREFIX/*' --count 3 --for 45s    # ALL entities ( * = one segment )"
hz_sub_start "$PREFIX/A7" 1 one
hz_sub_start "$PREFIX/*"  3 all
hz_say  "A live subscription is what any participant may open. It sees what is"
hz_say  "published while it is open, so it starts first."

hz_step "Publish current state for three distinct entities"
for id in A7 A8 A9; do
  KEY="$PREFIX/$id"
  hz_cmd "goat pub $KEY --payload '{\"id\":\"$id\",\"run\":\"$RUN\"}'"
  hz_goat pub "$KEY" --payload "{\"id\":\"$id\",\"alt\":31000,\"run\":\"$RUN\"}" --encoding json >/dev/null 2>&1 \
    && hz_note "published: $KEY" \
    || hz_note "publish refused for $KEY (check write-ACL for your anchor)"
done

hz_step "What each subscription received"
hz_sub_wait
ONE="$(hz_sub_output one)"
ALL="$(hz_sub_output all)"
hz_note "exact key $PREFIX/A7:"
printf '%s\n' "$ONE" | sed 's/^/      /'
hz_say  "Exactly aircraft A7 — the id is a key segment, so the network selects it."
hz_note "key expression $PREFIX/*:"
printf '%s\n' "$ALL" | sed 's/^/      /'
hz_say  "All three aircraft, addressed as a group — with NO per-message topic."
hz_note "Reading the same keys back after the fact (goat sub ... --since) reads the"
hz_note "audit-tail, which is operator-gated on a goatnet; Pattern C covers history."

# --- assertions -------------------------------------------------------------
hz_step "Verify"
hz_assert_contains "exact-key subscription received this run's A7" "$(hz_sub_events one)" "$RUN"
hz_assert_contains "wildcard subscription saw aircraft A7" "$(hz_sub_events all)" "A7"
hz_assert_contains "wildcard subscription saw aircraft A8" "$(hz_sub_events all)" "A8"
hz_assert_contains "wildcard subscription saw aircraft A9" "$(hz_sub_events all)" "A9"
hz_done
