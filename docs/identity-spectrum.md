# When there's no stable entity (raw sensor → detection → track → entity)

Pattern B uses **aircraft** — a thing with a stable, persistent identity (`A7`)
that exists whether or not the fabric ever hears about it. That's the easy case.
Upstream toward the sensor, identity is *manufactured* as data flows through
processing stages, and the pattern you pick follows **the identity model of the
representation in front of you — not the physical object behind it.** The same
object is several different things along the chain, and each wants a different
pattern.

> Each claim below is marked **[built]** (real and in use today, with the source),
> **[standard]** (general domain practice, not specific to this fabric), or
> **[future]** (a forward idea, *not* built — don't design against it). Leading
> with that line is the point of this doc: others build from these examples, so a
> not-yet-real mechanism must never read as current best practice.

## One object, several representations

```
   raw returns/frames        detection / hit          track                known entity
   (no identity)        ->   (event identity)    ->   (assigned identity) -> (real identity)
        │                          │                       │                      │
   volatile stream            per-event history       per-entity state       per-entity state
   (volatile/ class)          (Pattern C)             (Pattern B)            (Pattern B)
```

| Representation | Identity model | Rate / retention | Pattern | Example key |
|---|---|---|---|---|
| **Raw sensor output** (radar returns/dwells, acoustic frames, plots) | none — it's a signal | very high, loss-tolerant, only-live-matters | **volatile** stream class | `volatile/<sensor>/stream/returns` |
| **Detection / hit** | *this observation*, not *that object* — an event | high, each one a discrete fact | **C** per-event history | `<sensor>/detections/v1/<detection-id>` |
| **Track** | system-*assigned*, time-limited | moderate, latest-solution-matters | **B** per-entity state | `<tracker>/tracks/v1/<track-id>` |
| **Known entity / platform** | real, persistent (tail number, unit) | low, current-state-matters | **B** per-entity state | `<source>/aircraft/v1/<entity-id>` |

Rule of thumb: **as identity becomes more stable and persistent (raw → detection
→ track → entity), you move volatile → C → B.** As the need to replay rises, you
move volatile → C.

> Full-motion **video** does not ride this fabric — it has its own transport.
> "Raw sensor output" here means signals structured and rate-limited enough to
> belong on the bus (radar plots, acoustic frames, telemetry), not video.

## Why a detection is not a tiny track

The tempting mistake is to give detections per-entity keys (Pattern B) as if each
were a little track. Don't:

- A detection has **no persistent identity**, so "the latest detection for X" is
  meaningless — there is no X. Keying detections per-"entity" just overwrites the
  last hit at some reused key — the [scan-trap anti-pattern](anti-patterns.md).
- A detection is a **discrete fact at an instant** — the textbook shape for
  **Pattern C**: a unique id last (`<sensor>/detections/v1/<ulid>`), on a history
  storage, queried by **sensor + time + region** (`get <sensor>/detections/v1/**?_time=[...]`),
  never by a per-object name.

Detections become tracks *downstream*, when a tracker correlates many detections
into one assigned identity. That correlation is a **separate stage with its own
namespace** (see [Linking the stages](#linking-the-stages) below) — not the same
key reshaped.

## Tracks: a stable id for a changing thing — and how staleness works today

A track ID is stable for the track's life, so per-track current state is **Pattern
B** — exactly what the house best-practices guidance says: key the track by its
uid, `<tracker>/tracks/v1/<track-id>`, and a consumer gets "track 42's latest
solution." **[built / standard — see goatcore's
[`pubsub-best-practices`](https://github.com/usareur-af/goatcore/blob/main/docs/design/pubsub-best-practices.md) guide,
which maps vehicle tracks and CoT to Pattern B keyed by the track/CoT uid.]**

The real question a track raises is: *is track 42's latest value still current, or
did the track go quiet / drop?* Here is how that is answered **today** — and it
does **not** require a new mechanism:

- **Staleness by retained-value age (consumer-side). [built]** The latest value in
  storage carries its publish timestamp. A consumer reads it and judges freshness
  by age — old ⇒ stale. goat's inspection surface does exactly this: it reads
  the last retained value and renders it `stale=true` with its original
  timestamp, so a **tracks** topic that has gone quiet shows as stale.
  *(So the latest-value store does **not** hide staleness — the retained sample's
  own timestamp is the signal.)*
- **In-payload validity time. [standard]** Many track formats carry their own
  expiry in the payload — e.g. CoT's `stale` attribute on the `<event>` element.
  Consumers honour it directly. *(CoT schema is general TAK practice, not specific
  to this fabric.)*

So: **Pattern B + judge freshness from the retained timestamp (and/or an in-payload
validity time).** That is the supported answer.

> **What liveliness/presence is — today. [built]** The fabric *does* have native
> liveliness presence, but it is **peer/session-level**: a token per peer under
> `ops/<domain>/presence/<peer>`, surfaced by `goat presence` as the live *peer*
> set. It answers "is this **producer** up?", not "is this **track** still being
> updated?" A plain publish (`goat pub`) declares **no** liveliness token at all.
> Do not reach for `goat presence` as a per-track drop signal — it isn't one.

## Future directions (designed, not built — don't build against these yet)

These are forward ideas for richer track-lifecycle signaling. They are **not** how
the fabric works today and are **not** current best practice; they're recorded so
the gap is visible, not to be copied. **[future]**

- **Per-track liveliness tokens.** A tracker *could* declare a liveliness token per
  live track (Zenoh liveliness tokens can name any key), making a drop a push event
  instead of an age inference. Not built: today's presence is peer-level and
  `goat pub` declares no token. Would need a producer that declares/retracts a
  token per track.
- **Explicit drop-state / tombstone.** A tracker *could* publish a final
  `state: dropped` value at the track's key so the death persists in latest-value
  storage (presence edges are live-only). Cheap and producer-cooperative — a fit
  for the brokerless "no broker to expire keys" reality — but a convention to be
  designed, not a built feature.
- **Merge/split association topics.** When tracks fuse or split, publish the id
  remap on a separate association topic rather than overloading the track key.

Treat all three as engineering backlog. Until they exist, the supported answer is
the one above: Pattern B + staleness-by-timestamp (+ payload validity time).

## Linking the stages

The same object under raw / detection / track / entity gets **different keys in
different namespaces**, one per processing stage. You don't reshape a single key as
it's promoted. Instead, carry **correlation ids in the payload** (a track
references the detection ids that fed it; a recognized entity references its track
id), or publish explicit association topics. That keeps each stage's key space
clean for its own pattern and lets you join across stages by id when you need to —
the [discriminator-in-a-segment](key-expression-design.md) discipline applied
across the chain instead of within one stage.

## The short version

- Pick by **how stable and meaningful the identity is** at the stage in front of
  you, not by the physical object. Raw signal → **volatile**. Detection → **C**.
  Track and known entity → **B**.
- A track is **Pattern B keyed by its uid**; judge staleness from the **retained
  value's timestamp** (built) or an **in-payload validity time** like CoT `stale`
  (standard). The latest-value store does not hide staleness.
- Liveliness/presence today is **peer-level** ("is the producer up?"), not a
  per-track signal. Per-track liveliness and explicit tombstones are **future**
  ideas — don't build against them yet.
- One object, many keys, many stages — link by correlation id, never by mutating a
  key.
