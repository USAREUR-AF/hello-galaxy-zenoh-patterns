# hello-galaxy: Zenoh patterns

**The right way to shape Zenoh keys, choose storage, and decide whether a single
topic is the answer — shown, not told, on a running goat fabric.**

This is the first repo in the **Hello Galaxy** series. Each Hello Galaxy is a
small, self-contained, runnable example of *best practice in one specific
dimension we work with* — the way "hello, world" is the smallest honest example
of a language. This one covers **Zenoh usage patterns**: when one topic is
right, when it isn't, and how to shape keys so you can actually retrieve your
data later.

Each pattern is a short, cold-readable runbook plus a single script that drives
the `goat` CLI against a **running fabric** (your goat CLI's active context by
default) and narrates what's happening. Nothing is faked; where a behaviour is a
deployment property rather than something a publisher controls, the docs say so
plainly.

---

## The question this repo answers

A common question is about **singleton topics** — whether to use one topic, and
when that's appropriate. A concrete example: a producer shapes its keys
`<anchor>/aircraft/<id>/v1` (entity in the middle, version last). It still
retrieves fine, but the inverted shape **blinds an inspection tool** whose tree
view folders on the last key segment — every aircraft collapses into a single
constant `v1` bucket.

The fix is a small set of rules, and they all come from one idea:

> **Zenoh is pub/sub — a channel, not an S3 bucket.** Retrieval is a *separate*
> operation (`get`) answered by a *storage*, and **where you put the
> discriminator in the key** plus **what storage covers that prefix** decide
> what "get it back later" can even mean.

Read [`docs/00-pubsub-is-not-a-bucket.md`](docs/00-pubsub-is-not-a-bucket.md)
first — it's the whole mental model in two minutes.

---

## The four patterns

| Pattern | One-line | Key shape | `get` gives you |
|---|---|---|---|
| **[A — singleton / latest](patterns/A-singleton-latest/)** | one value, current state | `<a>/.../state` | the latest value (only) |
| **[B — per-entity state](patterns/B-per-entity-state/)** | N things, current state each | `<a>/.../v1/<entity-id>` | one entity, or all via `*` |
| **[C — per-event history](patterns/C-per-event-history/)** | every message matters | `<a>/.../v1/<event-id>` | every event via `**` + time range |
| **[D — volatile stream](patterns/D-volatile-stream/)** | live firehose, no retrieval | `volatile/<a>/stream/**` | nothing — by design |
| **[E — shared topic *(advanced)*](patterns/E-shared-topic-co-publish/)** | *more than one* publisher, one org | `shared/<org-pool>/<topic>/**` | the interleaved feed (attribution is a set) |

Patterns A–D are the ~95% — **one publisher per key**. Pattern E is the
deliberate exception (co-publish); it never weakens the one-writer default, it
adds a *separate*, marked, multi-writer namespace. Reach for it only when a
single org genuinely needs a multi-writer stream.

**Plus a cross-cutting demo (not a lettered pattern):**
- **[Transport: TLS vs QUIC](patterns/transport-tls-vs-quic/)** — transport is a
  *connect-config* property, not a per-publish knob: the same identity + round-trip
  over `tls/:7447` and `quic/:7448`, side by side. QUIC helps a lossy/mobile edge
  (no head-of-line blocking, connection migration, faster reconnect); TLS is the
  default. **Know both** — [`docs/transport-tls-vs-quic.md`](docs/transport-tls-vs-quic.md).

**Can you use just one topic?** Yes — that's Pattern A — *when you genuinely
track one value.* The trap is one topic for *many* things with the discriminator
in the payload: you can then only ever read back the latest, and you can't select
by key. The fix is always to lift the discriminator into a key segment (B or C).

**What if the thing has no stable identity** — a track, a detection, or raw
sensor output rather than a known platform? Then the pattern follows the identity
model of the representation, not the object: raw signal → the volatile class,
detection → C, track and known entity → B (a track is keyed by its uid, with
staleness judged from the retained value's timestamp). See
[`docs/identity-spectrum.md`](docs/identity-spectrum.md), which marks each
lifecycle signal as built or future.

Pick with [`docs/decision-guide.md`](docs/decision-guide.md). Shape keys with
[`docs/key-expression-design.md`](docs/key-expression-design.md). Avoid the traps
in [`docs/anti-patterns.md`](docs/anti-patterns.md) (including the inversion
above).

Need **more than one publisher on a shared topic**? That's the advanced
[Pattern E — shared topic](patterns/E-shared-topic-co-publish/) (runnable), with
the full guidance in [`docs/co-publish.md`](docs/co-publish.md): when a
same-org second publisher is legitimate, when it isn't, and the attribution
trade-off you accept.

---

## Run it

```bash
git clone https://github.com/usareur-af/hello-galaxy-zenoh-patterns
cd hello-galaxy-zenoh-patterns

# confirm goat can see a fabric (a context named my-goatnet shown):
goat --context my-goatnet health    # should print a per-class health table

bin/hello-zenoh A-singleton-latest   # run a pattern, narrated (active context by default)
bin/hello-zenoh all                  # run every narrated pattern in order
bin/hello-zenoh list                 # list the patterns
```

Each pattern is a folder with a `README.md` (read it cold) and a `run.sh` (the
driver). `bin/hello-zenoh <pattern>` just runs the folder's `run.sh` with the env
you chose (the goat CLI's active context by default; `--env <context>` picks
another).

**What needs a goatnet.** Patterns A–E and the TLS/QUIC transport demo publish
to a running fabric, so they need a goatnet and a write-capable identity on it.
If you don't have one, the goatlite tutorial stands one up on a single box:
[`docs/tutorials/00-goatlite.md`](https://github.com/usareur-af/goatcore/blob/main/docs/tutorials/00-goatlite.md)
in goatcore. Without a goatnet you can still read every runbook and run the
offline checks:

```bash
bash -n lib/hello-zenoh.sh bin/hello-zenoh patterns/*/run.sh   # syntax
(cd patterns/control-priority && python3 test_probe.py)       # needs eclipse-zenoh==1.9.0; local only
```

The demos **publish under your own write anchor** (`<anchor>/hello/...`, derived
from your cert at runtime), so they're admitted by the slot ACL and never touch
anyone else's key space.

---

## Prerequisites

- The `goat` CLI on your `PATH`, with a configured context for the env
  (`goat context use <context>`, or `goat init`). Verify with `goat --context
  <context> health`.
- `openssl` (the drivers read your cert CN to derive your write anchor).
- A write-capable identity on the fabric (a slot/org cert). Publishes land under
  `<your-anchor>/hello/**`.

**Honesty notes.** Reads in Patterns B and C wait a few seconds before querying
the audit-tail — `put` is fire-and-forget and the history storage ingests
**asynchronously**, so an immediate read-back races ingestion and can miss the
newest events. The wait is part of the lesson: retrieval is a separate operation
against a storage that has to persist first. The history read-back itself uses
goat's audit-tail (`goat replay` / `goat sub --since`), which is
**operator-gated** on a goatnet (the portal mints presigned URLs for it). If you aren't an operator, the publishes
still land; use the ungated live equivalent `goat sub <key-expr> --follow` to
watch events arrive. Pattern D's empty replay is **not** a permission issue — the
volatile class is genuinely never retained.

---

## Contributing

Each pattern is a self-contained folder with its own `README.md` and `run.sh`;
that isolation is the teaching contract, so keep a new pattern runnable on its
own. `shellcheck -x` any script you add. There is no test framework here on
purpose — the runnable example is the verification.


## License

Apache 2.0 — see [LICENSE](LICENSE).

## Command and abort traffic

Use explicit publisher priorities for command channels:
`INTERACTIVE_HIGH` for control and `REAL_TIME` for abort/stop. Ordinary data
stays at `DATA`. The [control-priority example](patterns/control-priority/)
includes SDK calls and a repeatable measurement probe. Priority does not
reserve bandwidth or guarantee delivery.
