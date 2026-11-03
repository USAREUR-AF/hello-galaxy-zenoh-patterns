# Which pattern should I use?

Answer two questions and the pattern falls out.

1. **Do I need to retrieve specific data later, or just stream it live?**
2. **If I retrieve it later — do I want the _current value_ of each thing, or
   _every message_ over time?**

```
                          ┌─────────────────────────────────────────┐
                          │ Do you ever need to GET data back later?  │
                          └───────────────┬──────────────┬────────────┘
                                       no  │              │ yes
                                           ▼              ▼
                         ┌───────────────────────┐   ┌──────────────────────────────┐
                         │ High-rate / loss-ok?   │   │ Current value, or full history?│
                         └────────┬──────┬────────┘   └─────────┬───────────┬──────────┘
                          yes/big │      │ no              latest│           │ every msg
                                  ▼      ▼                       ▼           ▼
                          ┌──────────┐ ┌─────────┐   ┌────────────────┐ ┌────────────────┐
                          │ Pattern D│ │ plain   │   │ one thing, or   │ │  Pattern C     │
                          │ volatile │ │ pub/sub │   │ many entities?  │ │ per-event hist │
                          └──────────┘ └─────────┘   └───┬────────┬─────┘ └────────────────┘
                                                    one  │        │ many
                                                         ▼        ▼
                                                 ┌────────────┐ ┌──────────────┐
                                                 │ Pattern A  │ │  Pattern B    │
                                                 │ singleton  │ │ per-entity    │
                                                 └────────────┘ └──────────────┘
```

## The catalog

| Pattern | Key shape | Storage | `get` returns | Use it for | Don't use it for |
|---|---|---|---|---|---|
| **[A — singleton / latest](../patterns/A-singleton-latest/)** | one fixed key `<a>/<system>/<v>/state` | latest-value | the one current value | a single global value: current mode, config, last-known-good, a heartbeat's latest beat | anything where you need yesterday's value, or per-entity values |
| **[B — per-entity state](../patterns/B-per-entity-state/)** | entity id **last**, version in the **prefix** `<a>/<system>/<v>/<entity-id>` | latest-value | current value of one entity, or all entities via `*` | tracking the **current** state of N things: tracks, aircraft, sensors, units | full history of how one entity changed over time |
| **[C — per-event history](../patterns/C-per-event-history/)** | unique segment **last** `<a>/<system>/<v>/<event-id>` | history / time-series | every event in the window via `**` + `_time=` | every message matters: audit, orders, event logs, replay, post-hoc analysis | "what is X **now**" (you'd have to scan); high-rate firehoses (storage explodes) |
| **[D — volatile stream](../patterns/D-volatile-stream/)** | `volatile/<a>/stream/**` (loss-tolerant) | **none** (routed, never retained) | nothing — by design | high-rate telemetry where only live matters: video-adjacent, raw sensor feeds | anything you must be able to pull back later |

> `<a>` = your write anchor (on goat, the slot/org anchor that the ACL keys on);
> `<v>` = a **version** segment (`v1`, `v2`) that lives in the **stable prefix**.

## Can I just use one topic?

Yes — that is **Pattern A**, and it is correct *when you genuinely track one
value*. The trap is using one topic for *many things* and putting the
discriminator (entity id, event id) **in the payload**. Then:

- `get` only ever returns the **latest** sample at that single key (1,000 puts →
  `get` returns 1). The other 999 are unrecoverable by query.
- You cannot select by key expression. To find "entity 7" you must subscribe
  live and scan every sample, or replay everything and filter client-side.

That is the [anti-pattern](anti-patterns.md). The fix is always the same: **lift
the discriminator out of the payload and into a key segment** so the network can
select it for you (Pattern B or C).

## What if the thing has no stable identity?

The catalog above keys on a clean entity id (`A7`). Upstream toward the sensor,
identity dissolves — and the pattern follows the identity model of the
representation, not the physical object:

- **raw sensor output** (returns, plots, frames) — no identity, only-live → the
  **volatile** stream class
- **detection / hit** — an event, no persistent identity → **C** (key by sensor +
  unique id; query by sensor/time, never "latest detection X")
- **track** — a system-assigned, time-limited id → **B** (key by the track uid),
  with freshness judged from the **retained value's timestamp** or an in-payload
  validity time (e.g. CoT `stale`); the latest-value store does not hide staleness
- **known entity** — real persistent id → **B**, the clean case

Full walk, including why a detection is not a tiny track, how staleness is judged
today, and which richer track-lifecycle signals are future-not-built:
[**identity-spectrum.md**](identity-spectrum.md).

## Rules of thumb

- **Version belongs in the prefix; the entity/event id belongs last.** This
  keeps `get <a>/<system>/<v>/*` meaningful and keeps inspection surfaces that
  "folder" on the last segment working. See [key-expression-design](key-expression-design.md)
  and the cautionary tale in [anti-patterns](anti-patterns.md).
- **One key per thing you want to address individually.** If you'll ask for it
  by name later, it gets its own key segment.
- **Latest vs every-message is a storage choice, not a publishing choice.** Same
  `put`; the retrievability comes from what storage covers the prefix.
- **Default to live.** If you don't need retrieval, don't provision a storage —
  Pattern D (or plain pub/sub) is lighter and faster.
