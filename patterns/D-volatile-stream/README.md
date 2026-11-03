# Pattern D — volatile stream

**High-rate, loss-tolerant telemetry that is routed live and never retained.**
There is deliberately **no** storage. `get`/replay returns nothing — and that's
the correct, honest behaviour, not a bug.

```
volatile/<anchor>/stream/<...>      ← top-level `volatile/` class, DROP congestion control
```

## When this is the right answer

Use the volatile class when only the **live** value matters and you would rather
drop a sample than back-pressure the producer or fill a disk:

- raw sensor firehoses, high-rate position/telemetry
- video-adjacent streams
- anything where "the latest few are all that matter" and history is noise

`goat pub --volatile-stream` publishes with **DROP** congestion control so a fast
producer never stalls its own session, and the `volatile/` prefix is excluded
from the durable/audit storage — so it scales with flow count, not disk.

## Why it is its own top-level class

If volatile traffic lived under your normal `<anchor>/**` prefix, the per-peer
storage would try to persist the firehose and the audit-tail would record it.
Putting it under a distinct top-level `volatile/` prefix keeps the durability
sinks **out of the path** — that's exactly what lets it scale, and it's why the
class is a deliberate part of the fabric design, not just a naming convention.

## What it does NOT do

You cannot pull a volatile sample back later. There is no storage; replay over
the prefix returns nothing **by design**. If you ever need to retrieve a
specific message after the fact, it does not belong in `volatile/` — use
[Pattern B](../B-per-entity-state/) (current state) or
[Pattern C](../C-per-event-history/) (full history).

## What the demo shows

It publishes a few samples with `--volatile-stream`, then runs `goat replay` over
the volatile prefix and shows it comes back **empty** — proving the class is
routed-but-not-retained. (Live subscribers *do* receive these samples in real
time; only retrieval-after-the-fact is — intentionally — impossible.)

## Run it

```bash
bin/hello-zenoh D-volatile-stream
```
