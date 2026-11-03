# Transport: TLS vs QUIC

**Transport is a deployment property, not a publisher's choice.** You don't pick
TLS or QUIC per message — you pick it in the **endpoint you dial**, and Zenoh
selects the transport from the scheme:

```
tls/<router>:7447    →  TLS over TCP   (the fleet default today)
quic/<router>:7448   →  QUIC over UDP  (opt-in per goatnet)
```

Everything else is identical: the same mTLS cert, the same offline-CA root, the
same URI-SAN / slot ACL, the same key expressions, the same code. On the PQ /
PQ-FIPS router image both negotiate **X25519MLKEM768** from the same crypto
provider — so **post-quantum is free on either transport**, and is *not* a reason
to choose one.

Because it's a connect-config property (and the `goat` CLI is pinned to the
profile's `tls/` endpoint), the runnable pattern
[`patterns/transport-tls-vs-quic/`](../patterns/transport-tls-vs-quic/) uses a
tiny zenoh client directly: your own context cert, the same pub→sub round-trip,
once over each transport, and prints each leg's connect time so you can compare
them on your own goatnet.

```
bin/hello-zenoh transport-tls-vs-quic          # needs eclipse-zenoh==1.9.0
```

## Why you might reach for QUIC

Its properties map to a **lossy / mobile / denied edge**:

- **No head-of-line blocking under loss.** TCP is one ordered byte stream — a
  single dropped segment stalls everything behind it. QUIC's streams are
  independent, so one lost packet doesn't hold up unrelated data. On a
  bursty-loss uplink that's the difference that matters.
- **Connection migration.** A QUIC connection survives the client's IP changing
  (Starlink/CGNAT re-addressing, path failover) without a full reconnect — it's
  keyed on a connection ID, not the 4-tuple.
- **Faster (re)connect.** Fewer round trips to establish, so recovery after a
  drop is quicker — the demo above prints the connect time of each leg.

## Why the fleet still defaults to TLS

- **It works and nothing forces a move.** No transport-level problem has been
  seen that QUIC would fix; TLS is the older, more widely battle-tested path.
- **UDP reachability.** QUIC is UDP. Inside the mesh it rides the same
  NetBird/WireGuard tunnel as everything else (so it reaches the router fine),
  but any environment that throttles/blocks UDP favours TCP.
- **Complexity budget.** A blanket flip is churn for no measured benefit.

## The takeaway: know both, choose per endpoint

Neither is "the answer." **Familiarise yourself with both** — run the pattern
and see them side by side. Start on TLS (the default); move a specific endpoint
to QUIC when its link characteristics (bursty loss, changing IPs, frequent
reconnects) predict a real win, and **measure it** — compare the router's TLS
and QUIC traffic before and after you flip an endpoint.

## What has to be true on the router

The goatnet must have the QUIC listener enabled (`goat_zenoh_quic_enabled:
true`, UDP `:7448` published). On a goatnet that hasn't enabled it, the QUIC leg simply won't connect and you stay on
TLS — which is exactly the "transport is a deployment property" lesson, and the
pattern surfaces that case instead of pretending. Enabling QUIC is a
transport-listen decision covered by the PQC adoption pattern
([ADR 1086](https://github.com/usareur-af/goatcore/blob/main/docs/adr/1086-pqc-adoption-pattern.md)); the
ACL, mTLS, and slot model are unchanged.
