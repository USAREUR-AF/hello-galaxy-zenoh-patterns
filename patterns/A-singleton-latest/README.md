# Pattern A — singleton / latest value

**One fixed key. Storage keeps the current value. `get` returns exactly one
thing: the latest.**

```
<anchor>/hello/state            ← one key, forever
```

## When this is the right answer

Use a singleton when you genuinely track **one** value and only ever care about
its **current** state:

- the system's current operating mode
- a single configuration blob / feature flag set
- "last known good" snapshot
- the latest beat of a single heartbeat

`get <anchor>/hello/state` returns the current value. Simple, cheap, correct.

## What it does NOT do

A latest-value storage keeps **one** sample per key. Publish to this key 1,000
times and the storage holds the **1,000th**. So:

- You cannot retrieve an earlier value by querying the router storage.
- You cannot track *many* things here. If you put many entities through one key
  (id in the payload), you can only ever read back the most recent one — see
  [anti-patterns](../../docs/anti-patterns.md). If you have N things, use
  [Pattern B](../B-per-entity-state/). If you need every message, use
  [Pattern C](../C-per-event-history/).

## What the demo shows

It publishes **two** values to the **same** key, then reads the key back from
the router's latest-value storage with `goat pub --confirm`. The read-back
reflects the **second** value — the first is no longer the current value at that
key. (Separately, goat's append-only **audit-tail** *did* see both events; that
is a different storage shape and the subject of [Pattern C](../C-per-event-history/).
Pattern A is about the **latest-value** retrieval the router storage gives you.)

## Run it

```bash
bin/hello-zenoh A-singleton-latest          # active goat context by default
```
