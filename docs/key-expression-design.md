# Designing key expressions

A Zenoh key is a `/`-separated path, like a filesystem path. A **key
expression** is a key with wildcards, used by subscribers and `get` to match
many keys at once. Getting the *shape* right is most of the battle.

## The two wildcards

| Wildcard | Matches | Example |
|---|---|---|
| `*` | exactly **one** segment | `acme/aircraft/v2/*` → every aircraft id, one level |
| `**` | **zero or more** segments | `acme/aircraft/**` → everything under `aircraft`, any depth |

So with keys shaped `acme/aircraft/v2/<id>`:

- `get acme/aircraft/v2/A7` → just aircraft `A7`
- `get acme/aircraft/v2/*` → all aircraft (current value of each)
- `sub acme/aircraft/**` → live feed of everything under aircraft, all versions

## Where each thing goes — and why

The ordering rule that prevents the most pain:

> **Stable, low-cardinality things go in the prefix. The high-cardinality
> discriminator you select on goes _last_.**

Concretely, for entity state:

```
<anchor> / <system> / <version> / <entity-id>
  acme   / aircraft  /   v2      /   A7
  └ who   └ what       └ schema    └ which one  ← varies most, selected on
            (stable)     (stable)
```

Why version in the prefix, entity last:

1. **`get .../v2/*` means "all current aircraft on schema v2."** That is the
   query you actually run. If version were last (`.../A7/v2`), the natural
   "all aircraft" query `.../aircraft/*/*` is clumsier and you can't cleanly say
   "all aircraft, this schema."
2. **Schema migrations are clean.** `v1` and `v2` are sibling prefixes. A
   consumer reads `.../v2/**`; nothing leaks across the boundary; you can run
   both during a cutover.
3. **Inspection surfaces "folder" on the last segment.** Tools that group keys
   for a tree view bucket by the last segment. If the last segment is the
   *constant* version (`.../A7/v1`, `.../A8/v1`, …), every entity collapses into
   a single `v1` bucket and the view is blinded — you can't see the individual
   aircraft. Put the entity last and each one shows up. (This exact inversion
   bogged down a real inspection tool — see [anti-patterns](anti-patterns.md).)

## Selecting by time, not just by key

For history (Pattern C), the key expression picks *which* events; a **selector
parameter** picks *when*. Time-series storages honour a time range:

```
get acme/orders/v1/**?_time=[2026-06-16T00:00:00Z..2026-06-16T01:00:00Z]
```

This returns every event whose key matches `acme/orders/v1/**` **and** whose
timestamp falls in the window. Two independent axes: the key expression
(structure) and the selector (time/metadata). Use both.

> In `goat`, the time axis is expressed as a duration or RFC3339 instant on the
> read commands: `goat replay <key-expr> --since 1h`, `goat sub <key-expr>
> --since 2026-06-16T00:00:00Z`. The key-expression axis is the `<key-expr>`
> argument, wildcards and all.

## A few more conventions worth keeping

- **No leading slash.** Zenoh keys don't start with `/`.
- **Keep segments opaque and URL-safe.** Lowercase, no spaces; ids as ids.
- **Don't encode data you'll want to query into a *value* — encode it into a
  *segment*.** The network can only select on the key.
- **Pick a version segment from day one.** Adding `v1` later is a migration;
  starting with it is free.
- **Mind your write anchor.** On an ACL'd fabric the first segment(s) are your
  identity-bound namespace — you can only write under your own anchor. Demos in
  this repo derive the anchor from your cert at runtime for exactly this reason.
