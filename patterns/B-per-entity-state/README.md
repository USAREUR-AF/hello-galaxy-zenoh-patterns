# Pattern B — per-entity state

**The idiomatic default for "track the current state of N things."** Entity id
is the **last** key segment; the version lives in the **stable prefix**. A
latest-value storage keeps the current value of each entity.

```
<anchor>/hello/aircraft/v1/<entity-id>
  e.g.  acme/hello/aircraft/v1/A7
        acme/hello/aircraft/v1/A8
```

- **Get one entity:** `get <anchor>/hello/aircraft/v1/A7`
- **Get all entities:** `get <anchor>/hello/aircraft/v1/*`
- **Subscribe to the whole fleet, live:** `sub <anchor>/hello/aircraft/v1/*`

Storage scales with the number of **entities**, not the number of messages —
each entity has one key holding its latest value, no matter how often it updates.

## When this is the right answer

This is the workhorse pattern. Use it whenever you have a set of addressable
things whose **current** state you want to read or watch:

- tracks, aircraft, vehicles, units
- sensors and their latest reading
- per-peer status, per-node health

It is almost always what people reaching for "a topic per X" actually want — and
it does **not** require one topic per message.

## Assumption: a stable, meaningful identity

This pattern assumes each thing has a persistent identity (`A7`) that exists
independently of the fabric. That holds for aircraft, vehicles, units, nodes —
and, per the fabric's own best-practices guide, for **tracks** too (key the track
by its uid). It does **not** hold further upstream: a **detection** has no
persistent identity (it's an event → Pattern C), and **raw sensor output** has
none and only-live-matters (→ the volatile stream class). For a track, "is the
latest value still current?" is judged from the **retained value's timestamp**
(or an in-payload validity time like CoT `stale`) — the latest-value store does
not hide staleness. See [**identity-spectrum.md**](../../docs/identity-spectrum.md)
for the full raw → detection → track → entity walk, including which lifecycle
signals are built today and which are future ideas.

## The two ordering rules that make it work

1. **Entity id last.** It's the high-cardinality thing you select on, and
   inspection surfaces that fold a tree on the last segment will show each
   entity as its own node.
2. **Version in the prefix.** `v1`/`v2` become clean sibling prefixes for schema
   migration, and `.../v1/*` cleanly means "all entities on schema v1."

Inverting these (`.../aircraft/<id>/v1`) still technically retrieves, but blinds
last-segment-folding inspection tools and muddles migration — see
[anti-patterns](../../docs/anti-patterns.md).

## What the demo shows

It publishes current state for **three** distinct entities to **three** keys
that share a prefix and differ only in the last segment. Then it reads back
**one** entity by its exact key (precise selection), and subscribes to the
`.../*` key expression to show the whole set is addressable as a group — without
any per-message topic.

## Run it

```bash
bin/hello-zenoh B-per-entity-state
```
