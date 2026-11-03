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

It publishes **three distinct events** to three unique keys under one prefix,
then replays the prefix with `goat replay <prefix>/** --since` and shows **all
three** come back — selectable together by the `**` key expression and bounded
by the `--since` time window. Contrast with [Pattern A](../A-singleton-latest/),
where re-using one key left only the latest in latest-value storage.

## Run it

```bash
bin/hello-zenoh C-per-event-history
```

> The replay path reads the audit-tail and is operator-gated on a goatnet. If you're
> not an operator, the publishes still land; `goat sub <prefix>/** --follow` is
> the ungated live equivalent for watching new events arrive.
