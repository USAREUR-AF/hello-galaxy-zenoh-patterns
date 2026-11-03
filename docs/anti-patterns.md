# Anti-patterns

## 1. The "one key, discriminator in the payload" scan trap

```
# WRONG — one key for every aircraft, id buried in the JSON
acme/aircraft/v1   {"id":"A7","lat":...}
acme/aircraft/v1   {"id":"A8","lat":...}
acme/aircraft/v1   {"id":"A7","lat":...}   ← overwrites the first A7
```

What breaks:

- A latest-value storage keeps **one** value at `acme/aircraft/v1`. After three
  puts it holds whichever landed last. `get acme/aircraft/v1` returns **1**
  sample, not 3 — the rest are gone.
- You **cannot** ask for "aircraft A7." The id is in the payload, and the
  network can only select on the **key**. Your only option is to subscribe to
  the live stream and filter every message yourself, or replay everything and
  scan client-side.

The fix is mechanical: **move the discriminator into a key segment.**

```
# RIGHT — Pattern B: id is a key segment, selectable
acme/aircraft/v1/A7   {"lat":...}
acme/aircraft/v1/A8   {"lat":...}
# get acme/aircraft/v1/A7  → just A7
# get acme/aircraft/v1/*   → all aircraft, current value each
```

## 2. Cramming history into a latest-value key

Wanting *every* message but publishing them all to one key (or one key per
entity on a latest-value storage) silently discards all but the newest. If you
need history, each event needs its **own** key (Pattern C: a unique last
segment) **and** a storage that retains history. Latest-value storage + unique
keys also works for bounded history, but it grows without a TTL — size scales
with event count, so put a retention policy on it.

## 3. Version/entity **inversion**

This is the subtle one, because the keys *are* still retrievable — they're just
shaped wrong.

```
# the inverted shape
<anchor>/aircraft/<id>/v1      ← entity in the middle, version LAST
```

`get <anchor>/aircraft/*/v1` does work, so retrieval isn't broken. But:

- An inspection surface that builds a tree by **folding on the last segment**
  buckets *every* aircraft under a single `v1` folder, because `v1` is the
  constant last segment for all of them. The individual aircraft vanish from the
  view — the folder is **blinded**.
- "All current aircraft on this schema" is awkward to express, and schema
  migration is messier because versions aren't sibling prefixes.

The idiomatic shape puts the **version in the stable prefix and the entity
last**:

```
# RIGHT
<anchor>/aircraft/v1/<id>      ← version stable in prefix, entity selected last
```

Now `<anchor>/aircraft/v1/*` is "all aircraft, schema v1," each entity gets its
own folder node, and `v1`/`v2` are clean sibling prefixes for migration. See
[key-expression-design](key-expression-design.md) for the full ordering rule.

## 4. Assuming a `put` is retrievable

Publishing does not store. `get` returns nothing unless a **storage** is
subscribed to the prefix. Retrievability is a **deployment** decision (which
prefixes have storages, and of what kind), not a side effect of publishing.
Before you design for "we'll pull it back later," confirm a storage actually
covers that key space — and which kind (latest vs history). On goat, `goat pub
--confirm` tells you whether a write *landed in storage at all*; an empty `goat
replay` over a prefix usually means "no history storage here," not "no data was
sent."

## 5. Reaching for one topic per message

The opposite over-correction: a brand-new top-level key for every single
message (no shared prefix, no version, ids scattered). You lose the ability to
subscribe to "the feed" with one key expression, storages can't be scoped
sensibly, and discovery becomes impossible. Keep a **stable prefix** and let the
**last segment** carry the per-event uniqueness (Pattern C) — that gives you
both "the whole feed" (`prefix/**`) and "this one event" (`prefix/<id>`).

## 6. Topic sprawl — the cardinality budget (a fabric-wide cost, not just yours)

Everything above is about *your* retrievability. This one is about *everyone
else*. A key expression is not free: the router keeps **every distinct key it has
ever routed** in one in-memory table, guarded by one lock. That table is a
**shared** resource. The number of distinct keys is your **cardinality**, and it
is the single biggest lever on fabric performance.

How the cost grows as load is added one piece at a time:

- The whole service stack — publishers, subscribers, dashboards, audit — adds
  **~zero** router cost. Services are free.
- Broad crawling (dashboards walking the tree) alone burns CPU but adds **no
  latency** — with few keys, each walk is over in a blink.
- **Cardinality is what changes that.** As distinct keys grow, every broad
  `get`/crawl over the tree grows **linearly (O(N))**. And the moment new keys
  are being **declared** while something is crawling, they collide on that one
  lock and the router **seizes** — responsiveness drops from milliseconds to
  seconds. One publisher running tens of thousands of live keyexprs is enough.
- You **cannot** buy your way out with a bigger box: a single lock does not
  parallelize (adding CPU made it *worse*). The only fix is fewer keys.

**The tension with Pattern C, resolved.** "Give each event its own key" is right —
*for a bounded dimension you actually select on.* It becomes an anti-pattern when
the last segment is an **unbounded** dimension — per frame, per timestamp, per
message instance — because then "one key per event" means *thousands of live
keyexprs*, which is the sprawl that taxes the whole fabric.

The rule:

- **Bounded, selectable dimension** (the ~dozens/hundreds of entities you'll
  `get` by name — aircraft, sensors, tracks): **put it in the key.** That's
  Pattern B, and it's fine.
- **Unbounded instance/time dimension** (frame number, nanosecond timestamp, a
  fresh id per message): **do not mint a live routing key for it.** Put it in the
  **payload**, or write to a **history storage** that retains by time under a
  **stable** key. You subscribe to the *stream*; you don't `get` frame #4,183,902
  by key.

Litmus test: **if one identity is declaring more than ~100 distinct key
expressions, a dimension that belongs in the payload has leaked into the key.**

**On a goatnet this is governed, not advisory.** Topic registration is budgeted —
allocated in blocks of ten, larger requests need justification and approval, and
**>100 distinct topics from one identity requires platform-admin approval**. If
you find yourself asking for a big block, that's the signal to move a dimension
into the payload first. The budget exists because the cost is shared: your
cardinality is everyone's latency.
