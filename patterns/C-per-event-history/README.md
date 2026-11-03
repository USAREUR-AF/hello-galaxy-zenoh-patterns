# Pattern C — per-event history

**Every message matters. Each event gets a unique last segment on a persisted
prefix. A history storage retains them all, and you replay a window with a key
expression plus a time range.**

```
<anchor>/hello/orders/v1/<event-id>      ← event-id is unique per message
  acme/hello/orders/v1/01J...K9          (a ULID, UUID, or timestamp-id)
  acme/hello/orders/v1/01J...KA
  acme/hello/orders/v1/01J...KB
```

- **Replay the whole feed:** `get <anchor>/hello/orders/v1/**`
- **Replay a time window:** `get <anchor>/hello/orders/v1/**?_time=[start..stop]`
- **One specific event:** `get <anchor>/hello/orders/v1/01J...K9`

Because every event has its **own** key, nothing overwrites anything — the
history storage keeps them all (within its retention/TTL). Storage now scales
with **message count**, so this pattern needs a retention policy.

## When this is the right answer

Use per-event history when each message is a discrete fact you may need to pull
back later:

- orders / commands / decisions
- audit and compliance trails
- event logs, state-change records
- anything you'll want to replay or analyse after the fact

## Key shape rules (same as Pattern B, plus uniqueness)

- **Version in the prefix**, so `v1`/`v2` are sibling prefixes.
- **Unique id last.** Prefer a **sortable** id (ULID, or `<rfc3339>-<seq>`) so
  the natural key order is time order.
- **Stable shared prefix.** `prefix/**` is "the whole feed"; `prefix/<id>` is
  one event. Don't scatter events across unrelated top-level keys (that's
  [anti-pattern #5](../../docs/anti-patterns.md)).

## Latest-value vs history storage — the deployment fact

Retrieval here depends on a **history** storage covering the prefix. On goat the
append-only **audit-tail** is exactly that: it records every event across the
fabric, and `goat replay <key-expr> --since <window>` reads it back via
portal-minted presigned URLs. (A plain latest-value rocksdb storage would keep
only the newest event *per unique key* — which, since every key is unique here,
is still every event, but without a TTL it grows unbounded. History storage with
retention is the clean answer.)

## What the demo shows

It opens a live subscription on `<prefix>/**`, publishes **three distinct events**
to three unique keys under that prefix, and shows the subscription received all
three. Then it replays the prefix with `goat replay <prefix>/** --since` and shows
**all three** come back — selectable together by the `**` key expression and bounded
by the `--since` time window. Contrast with [Pattern A](../A-singleton-latest/),
where re-using one key left only the latest in latest-value storage.

**Replay needs an operator key on a goatnet.** `goat replay` reads the audit-tail,
and a goatnet gates that read to operator keys. When goat answers that the read is
operator-gated, the demo says so and marks the four replay assertions **SKIP** —
neither passed nor failed. The publishes and the live subscription still run and are
checked. The live equivalent any participant may run is
`goat sub '<prefix>/**' --count 3`, opened before the events are published.

## Run it

```bash
bin/hello-zenoh C-per-event-history
```

> As a participant you will see the live-subscription checks pass and the replay
> checks reported as SKIP. A context whose key may read the audit-tail runs the
> four replay checks as well.
