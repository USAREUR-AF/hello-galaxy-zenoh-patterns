# Pub/sub is a channel, not a bucket

The single most common mistake with Zenoh is treating it like object storage.
It is not. Get this mental model right and every pattern in this repo follows
from it.

## Three operations, not one

Zenoh has three primitives, and they do different jobs:

| Operation | What it does | Analogy |
|---|---|---|
| **`put`** (publish) | sends a sample to everyone subscribed to a key, *right now* | shouting into a room |
| **`subscribe`** | receives matching samples *as they are published* | listening in that room |
| **`get`** (query) | asks "what is the value (or values) at this selector?" and gets an answer back | opening a filing cabinet |

A `put` is **fire-and-forget**. It is delivered to whoever is listening at that
instant. If nobody is subscribed, the sample is gone. Publishing does **not**,
by itself, store anything.

> In `goat`, `put` is `goat pub`, `subscribe` is `goat sub`, and the query/get
> family is `goat pub --confirm` (read one key back from storage), `goat sub
> --since` / `goat replay` (read history from the audit-tail).

## Retrieval is a *separate* operation against a *storage*

To pull a message back **later**, something must have **stored** it. In Zenoh a
**storage** is a plugin (rocksdb, S3, in-memory, time-series, …) that subscribes
to a key prefix and retains samples. A `get` is answered by a storage (or a
queryable) — not by the network itself.

This is the non-obvious footgun:

> **`get` returns nothing unless a storage is actually subscribed to that
> prefix.** Retrievability is not automatic — it is a *deployment property* of
> the key space, not a property of having published.

You can publish a million samples and still `get` back an empty result if no
storage covers the key. (On goat, publishing under a prefix nobody onboarded a
storage for is the silent-denial cousin of this — see
[zenoh-brokerless-consequences](https://github.com/usareur-af/goatcore/blob/main/docs/design/zenoh-brokerless-consequences.md)
in goatcore.)

## What kind of storage decides what you can retrieve

Two storage shapes matter for the patterns:

- **Latest-value-per-key** (e.g. a rocksdb backend). Keeps exactly one value per
  *key*. Put to the same key 1,000 times → it keeps the 1,000th. Retrieval gives
  you the **current** value per key. Storage size scales with the number of
  distinct keys, not the number of messages.
- **History / time-series.** Keeps many samples over time and supports a time
  range on the query (`_time=[start..stop]`). Retrieval can replay a window.

So **where you put the discriminator** (one segment per entity? a unique segment
per event?) and **what kind of storage covers the prefix** together decide what
"retrieve it later" actually means. That is the whole subject of this repo.

## The one-line rule

- **Live data flowing past?** → publish/subscribe. No storage needed.
- **"What is the current value of X?"** → one key per X, a latest-value storage,
  `get`.
- **"Give me every message about X over the last hour"** → a unique key per
  event on a history storage, `get` with a time range.

Next: [the decision guide](decision-guide.md) turns this into a pick-a-pattern
flow.
