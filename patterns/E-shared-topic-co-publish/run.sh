#!/usr/bin/env bash
# Pattern E (advanced) — shared topic, more than one publisher (co-publish).
#
# Drives the client-visible half: an org's data-governance admin (the
# PUBSUB-ORG-ADMIN capability) CREATES a marked, discoverable shared topic and
# DISCOVERS it. The grant + enforcement half is a deploy step (the ACL is static,
# restart-required), so — like Pattern D's empty replay — this says so plainly
# instead of faking it.
#
#   Org to create the topic under (must be one you GOVERN, or run as operator):
#     HZ_CO_ORG=my-org ./run.sh
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Pattern E (advanced) — shared topic, more than one publisher" \
          "The deliberate exception: a marked, org-scoped, multi-writer topic — single-owner roots stay inviolable."

hz_preflight || exit 1

ORG="${HZ_CO_ORG:-hello-galaxy-demo}"
RUN="$(hz_run_id)"

# --- Does this goat carry the co-publish surface? ---------------------------
if ! hz_goat access co-publish --help >/dev/null 2>&1; then
  hz_step "Not available in this goat"
  hz_note "\`goat access co-publish\` is missing — update goat to the release that carries"
  hz_note "the co-publish surface (ADR 1105). The pattern + the guidance still apply:"
  hz_note "see ../../docs/co-publish.md."
  hz_done
  exit 0
fi

hz_step "1. CREATE a shared topic (the deliberate PUBSUB-ORG-ADMIN act)"
hz_cmd  "goat access co-publish create-topic $ORG --name 'Shared status feed' --justification '...'"
OUT="$(hz_goat access co-publish create-topic "$ORG" \
        --name "Shared status feed" \
        --justification "hello-galaxy pattern E demo ($RUN)" --json 2>&1)"
RC=$?
printf '%s\n' "$OUT"

CREATED=0
KEY=""
if [ "$RC" -eq 0 ]; then
  CREATED=1
  KEY="$(printf '%s' "$OUT" | sed -n 's/.*"key_base":"\([^"]*\)".*/\1/p' | head -1)"
  POOL="$(printf '%s' "$KEY" | cut -d/ -f2)"
  hz_say  "Created. The key is a DISTINCT namespace under the reserved 'shared/' class:"
  hz_note "$KEY"
  hz_say  "Note the second segment '$POOL' — a STABLE, OPAQUE per-org handle."
  hz_say  "It is NOT your org's name (names are mutable, keys are freeze-critical);"
  hz_say  "the owning org resolves OFF the key, via the registry + alias layer."
else
  hz_say  "Refused — and that is the point of the capability, not a bug:"
  if printf '%s' "$OUT" | grep -qiE "govern|not_governor|forbidden|403"; then
    hz_note "creating a shared topic needs the PUBSUB-ORG-ADMIN capability — you must"
    hz_note "GOVERN org '$ORG' (data.govern.org), or run as an operator. That gate is"
    hz_note "deliberate: multi-writer topics are an authorized, audited act."
  fi
  hz_say  "Re-run with HZ_CO_ORG set to an org you govern to see the create succeed."
fi

hz_step "2. DISCOVER it — the MULTI-PUBLISHER marker + owning org (off the key)"
hz_cmd  "goat access co-publish list-topics --org $ORG"
LIST="$(hz_goat access co-publish list-topics --org "$ORG" 2>&1)"
printf '%s\n' "$LIST"
hz_say  "Discovery carries the [MULTI-PUBLISHER] marker + the owning org — so a"
hz_say  "subscriber knows, on discovery, that this topic is intentionally multi-writer."

hz_step "3. ADD a publisher, then ENFORCE (deployment-gated)"
hz_say  "An admin adds each org publisher to the topic:"
hz_cmd  "goat access co-publish grant <publisher-anchor> --to <topic-id> --justification '...'"
hz_say  "The publisher must belong to the topic's OWN org (at-most-own-org; cross-org"
hz_say  "is refused). The grant then takes effect only when the router config is"
hz_note "re-rendered and RESTARTED — the ACL is static, it does NOT reload live."
hz_say  "So enforcement is a deliberate deploy step, not an instant runtime toggle."

hz_step "What enforcement looks like"
hz_say  "After the grant is enforced, on the router:"
hz_note "• the granted co-publisher's sample LANDS on the shared topic"
hz_note "• an UN-granted writer is silently DENIED (verify by absence, never an error)"
hz_note "• a co-publisher CANNOT write another peer's own root — INVIOLABLE"
hz_note "• each peer's own-root publishing is unaffected"
hz_say  "Attribution on the shared topic is now a recorded SET, not a name — read the"
hz_say  "sample's SourceInfo for the author. Full guidance: ../../docs/co-publish.md."

# --- assertions -------------------------------------------------------------
hz_step "Verify"
if [ "$CREATED" -eq 1 ]; then
  hz_assert_contains "the shared topic uses the reserved 'shared/' class" "$KEY" "shared/"
  if printf '%s' "$KEY" | grep -q "/$ORG/"; then
    printf '    %s✗%s the org name leaked into the key (should be an opaque handle)\n' "$C_RED" "$C_RESET" >&2
    HZ_FAILS=$((HZ_FAILS+1))
  else
    printf '    %s✓%s the org name is NOT in the key — resolved off-key (opaque handle)\n' "$C_GREEN" "$C_RESET"
  fi
  hz_assert_contains "discovery carries the multi-publisher marker" "$LIST" "multi-publisher"
else
  printf '    %s✓%s the create was refused without govern authority — the guardrail held\n' "$C_GREEN" "$C_RESET"
fi
hz_done
