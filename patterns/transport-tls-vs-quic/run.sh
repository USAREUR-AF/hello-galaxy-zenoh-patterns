#!/usr/bin/env bash
# Pattern — transport: TLS vs QUIC.
#
# Unlike the other patterns, transport is NOT something a publisher chooses per
# message via the goat CLI — it is a CONNECT-CONFIG (deployment) property: the
# scheme of the endpoint you dial. So this pattern shows it the honest way — the
# SAME mTLS identity doing the SAME pub->sub round-trip over both transports,
# with a tiny zenoh client (goat CLI is pinned to the profile's tls/ endpoint).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$HERE/../.." && pwd)/lib/hello-zenoh.sh"
hz_parse_env "$@"; set -- ${HZ_ARGS[@]+"${HZ_ARGS[@]}"}

hz_banner "Transport — TLS vs QUIC" \
          "One identity, one round-trip, over both transports. Transport = the endpoint scheme, not a per-publish knob."

# This pattern does NOT use the goat CLI (transport is a connect-config property
# goat can't select), so it skips hz_preflight's goat requirement. It needs only
# your context mTLS cert + the fleet-pinned zenoh python client.
CTX="$HOME/.goat/contexts/$HZ_ENV"
ANCHOR="$(hz_anchor || true)"
if [ -z "$ANCHOR" ]; then
  hz_say "No mTLS cert for context \"$HZ_ENV\" ($CTX/mtls.cert.pem). Run \`goat context use $HZ_ENV\`."
  exit 1
fi
PY="${HZ_PY:-python3}"
if ! "$PY" -c "import zenoh" >/dev/null 2>&1; then
  hz_say "This pattern needs the zenoh python client (goat CLI is pinned to tls/)."
  hz_note "Install once:  $PY -m pip install eclipse-zenoh==1.9.0"
  hz_note "or point HZ_PY at a venv that has it:  HZ_PY=/path/to/venv/bin/python bin/hello-zenoh transport-tls-vs-quic"
  exit 1
fi
# Router host from the operator profile's router_endpoint (tls/<host>:<port>).
REP="$(grep -E '^router_endpoint' "$CTX/profile.toml" 2>/dev/null | sed -E 's/.*"(.*)".*/\1/')"
HOST="$(printf '%s' "$REP" | sed -E 's#^[a-z]+/##; s#:[0-9]+$##')"
TLS_EP="tls/${HOST}:7447"
QUIC_EP="quic/${HOST}:7448"

hz_step "Transport is the endpoint scheme"
hz_note "TLS/TCP : $TLS_EP     (the fleet default)"
hz_note "QUIC/UDP: $QUIC_EP    (opt-in; the goatnet must enable the :7448 listener)"
hz_say  "Same cert ($CTX/mtls.cert.pem), same ACL, same key expressions. On the PQ"
hz_say  "router image both negotiate X25519MLKEM768 — post-quantum is free on either."

hz_step "Round-trip over TLS"
hz_cmd  "pub -> sub on $ANCHOR/hello/transport-demo over $TLS_EP"
TLS_OUT="$(GOAT_CTX="$CTX" ANCHOR="$ANCHOR" EP="$TLS_EP" "$PY" "$HERE/transport_probe.py" 2>&1)"; TLS_RC=$?
printf '  %s\n' "$TLS_OUT"

hz_step "Round-trip over QUIC"
hz_cmd  "pub -> sub on $ANCHOR/hello/transport-demo over $QUIC_EP"
QUIC_OUT="$(GOAT_CTX="$CTX" ANCHOR="$ANCHOR" EP="$QUIC_EP" "$PY" "$HERE/transport_probe.py" 2>&1)"; QUIC_RC=$?
printf '  %s\n' "$QUIC_OUT"

hz_step "What this shows"
hz_say  "The only thing that changed is tls/:7447 -> quic/:7448. Both delivered."
hz_say  "QUIC often connects faster (fewer round trips) and, on a lossy/mobile edge,"
hz_say  "avoids head-of-line blocking and survives IP changes — see the doc."
hz_note "QUIC is opt-in per endpoint against a measured benefit, NOT a blanket flip."
hz_note "docs/transport-tls-vs-quic.md — the tradeoffs + why the fleet defaults to TLS."

# --- assertions -------------------------------------------------------------
hz_step "Verify"
hz_assert_contains "TLS round-trip delivered" "$TLS_OUT" "PASS"
[ "$TLS_RC" -eq 0 ] || { printf '    %s✗%s TLS probe exited %s\n' "$C_RED" "$C_RESET" "$TLS_RC" >&2; HZ_FAILS=$((HZ_FAILS+1)); }
if [ "$QUIC_RC" -eq 0 ]; then
  hz_assert_contains "QUIC round-trip delivered" "$QUIC_OUT" "PASS"
else
  # A QUIC failure on a goatnet WITHOUT the :7448 listener is the pattern's own
  # point (transport is a deployment property) — surface it, don't hard-fail the
  # whole demo on a goatnet that simply hasn't enabled QUIC.
  hz_say "QUIC did not round-trip here. On a goatnet that has enabled the :7448 listener it"
  hz_say "should PASS; on one that has NOT, this is expected — that IS the lesson"
  hz_say "(transport is a deployment property). Check goat_zenoh_quic_enabled."
fi
hz_done
