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

hz_step "Publish current state for three distinct entities"
for id in A7 A8 A9; do
  KEY="$PREFIX/$id"
  hz_cmd "goat pub $KEY --payload '{\"id\":\"$id\",\"run\":\"$RUN\"}' --confirm"
  hz_goat pub "$KEY" --payload "{\"id\":\"$id\",\"alt\":31000,\"run\":\"$RUN\"}" --encoding json --confirm >/dev/null 2>&1 \
    && hz_note "landed: $KEY" \
    || hz_note "write not confirmed for $KEY (check write-ACL for your anchor)"
done

hz_step "Let the audit-tail ingest before reading it back"
hz_settle 10

hz_step "Select ONE entity by its exact key"
hz_cmd  "goat sub $PREFIX/A7 --since 10m"
ONE="$(hz_goat sub "$PREFIX/A7" --since 10m 2>&1 || true)"
printf '%s\n' "$ONE" | sed 's/^/    /'
hz_say  "Exactly aircraft A7 — the id is a key segment, so the network selects it."

hz_step "Select ALL entities with a key expression ( * = one segment )"
hz_cmd  "goat sub $PREFIX/* --since 10m"
ALL="$(hz_goat sub "$PREFIX/*" --since 10m 2>&1 || true)"
printf '%s\n' "$ALL" | sed 's/^/    /'
hz_say  "All three aircraft, addressed as a group — with NO per-message topic."
hz_note "Read-back here uses the audit-tail (operator-gated on a goatnet). The ungated"
hz_note "equivalent for any participant is a live: goat sub $PREFIX/* --follow"

# --- assertions -------------------------------------------------------------
hz_step "Verify"
hz_assert_contains "single-key select returned this run's A7" "$ONE" "$RUN"
hz_assert_contains "wildcard select saw aircraft A7" "$ALL" "A7"
hz_assert_contains "wildcard select saw aircraft A8" "$ALL" "A8"
hz_assert_contains "wildcard select saw aircraft A9" "$ALL" "A9"
hz_done
