# Co-publishing: shared topics, and why they're a separate thing

Every other doc here assumes the normal case: **one publisher owns a key prefix,
and only it writes there.** That is the fabric's default and its strongest
guarantee — the router grants each identity `put` on its own root
(`<anchor>/**`) and *nothing else*, deny-by-default, so a subscriber knows every
sample under `<anchor>/…` came from that one writer. **That single-owner root is
inviolable.** Nothing — no admin, no grant — adds a second writer to it. Keep
building on that; it's the reason provenance is free here.

This doc is about the one exception, and how it is deliberately kept *outside*
that guarantee: a **shared topic** — a distinct, clearly-marked namespace that is
*born* multi-writer, so "more than one publisher" only ever happens somewhere
that announces itself as such.

> Each claim is marked **[built]** (the mechanism is real, with the source),
> **[standard]** (general pub/sub practice), or **[future]** (a forward idea,
> *not* built). One extra marker: **[built · deploy-pending]** — the mechanism
> exists in code and CLI but is **default-off and not yet live-fired** on a
> goatnet. Read it literally: the *guidance* is usable today; the *capability* is
> opt-in and, at time of writing, off.

---

## Why one writer per root is worth protecting

**[built]** The router enforces writes per identity: one pre-cut rule grants
`put/delete` on `<anchor>/**` (plus its `volatile/` mirror), and every other
write is denied. Denial is **silent** at the publisher (the `put` returns as if
it worked; the sample simply never routes) — so if you could quietly add a
second writer to someone's root, a subscriber who reasonably assumed one author
would never know. That's exactly why the fabric refuses to let anyone do it. When
a root has a single owner, "who published this?" has one answer, and the ACL, the
storage key, and the audit trail all agree on it.

So co-publishing does **not** open an existing root. It gives you a *different*
place to put a multi-writer stream.

## What a shared topic is

**[built · deploy-pending]** A shared topic is a **deliberately-created,
registered, org-scoped object** in a reserved namespace:

```
shared/<org-pool>/<topic-id>/**
```

- The leading **`shared/`** segment is the whole point: it's structural and
  immutable, so a raw-key reader sees *immediately* "this is multi-writer, don't
  assume one author." It is never a single-owner root.
- **`<org-pool>`** is a **stable, opaque, per-org handle**. It is *not* the org's
  name — names are mutable (reorgs, renames) and a key is freeze-critical, so
  putting a name in a key is the one thing this fabric never does. The handle
  resolves to the owning org through the registry, and to a human-readable org
  name through the display/alias layer — always current, never frozen into the
  key. All of an org's shared topics cluster under its handle, so you can tell
  two shared topics belong to the same org, and *which* org, on discovery.
- **`<topic-id>`** is a stable opaque id; the human name you see is a registry
  alias.

Creating one is a **deliberate act** by the org's data-governance admin (the
`PUBSUB-ORG-ADMIN` capability), with a recorded justification — not a side effect
of a grant. Adding a publisher to it is a separate, audited step. Both are
at-most-own-org: an admin only ever creates topics for, and adds publishers
from, *its own* org.

## When to create one

**[standard]** The legitimate multi-writer patterns — all *within one org*:

- **A shared org feed** several of the org's systems contribute to (redundant
  collectors, a primary + failover publishing one logical stream).
- **A registry / aggregation service** that maintains derived state on behalf of
  the org's producers.
- **A same-org gateway** that republishes several of its own streams through one
  topic.

If that's you: create a shared topic, add the publishers, done. Subscribers
follow the one `shared/<org-pool>/<topic>` key regardless of which publisher is
live.

## When *not* to

**[standard]** Reach for a different shape first:

- **Two writers that are really two streams.** If each writer's samples are
  independently useful, give them their **own** roots and let subscribers merge.
  A shared topic is for streams that genuinely want interleaving under one key.
- **Cross-organization sharing.** Shared topics are at-most-own-org. Letting
  another org publish into your space is not this mechanism (and is refused by
  design). That's a platform decision, not an org one.
- **A one-off / short-lived need.** A co-publish grant is effective-dated and
  revocable — set an expiry rather than leaving a standing extra writer forever.

## The trade-off you're accepting: attribution is many-to-one

**[standard]** This is the cost, and the reason the guidance ships *with* the
capability. On a shared topic, by design:

- **A subscriber can't infer the writer from the key** — that was the whole
  point of the single-owner rule, and you've deliberately stepped outside it. If
  downstream logic needs the author (dedup, provenance, trust), read the sample's
  own `SourceInfo`/publisher identity, not the topic.
- **Audit reads as a set** — "who can write here?" is a list. That list stays
  short and stays *recorded*: every publisher is a durable, enumerable, justified,
  effective-dated grant row, and every create/add/revoke is an audited operator
  action. Discovery shows the shared topic *with* its declared publisher set and
  its owning org, so the many-to-one is never a surprise.

If your subscribers or your audit story can't absorb "more than one writer here,"
a shared topic is the wrong call — reshape the topology instead.

## Doing it (the CLI)

**[built · deploy-pending]**

```
# 1. create the shared topic (a deliberate, org-scoped, justified act)
goat access co-publish create-topic <your-org> \
    --name "Shared status feed" \
    --justification "primary + failover collectors publish one status stream"

# 2. add publishers from your own org (at-most-own-org, enforced server-side)
goat access co-publish grant <publisher-anchor> \
    --to <topic-id> \
    --justification "failover collector"

# 3. discover — the MULTI-PUBLISHER marker, owning org, and publisher set
goat access co-publish list-topics --org <your-org>

# materialise for the router, then deploy + restart to enforce (no live reload)
goat access co-publish export
# reverse a publisher (kept for audit history)
goat access co-publish revoke <grant-id>
```

Two fabric properties shape the workflow, stated plainly because they are
deployment behaviour, not something a publisher controls:

- **The ACL does not reload live.** A newly-added publisher takes effect when the
  router next restarts. Co-publishing is deliberate and deploy-gated, not an
  instant runtime toggle.
- **Denial stays silent.** After you add a publisher, verify by *presence* — its
  sample actually arriving at a subscriber on the shared topic — and confirm an
  un-granted writer is still blocked by its *absence*, never by expecting an
  error. And confirm your ordinary roots are untouched: a peer still cannot write
  another peer's `<anchor>/**`.

## The one-paragraph version

Default to **one writer per root** — it makes provenance free, and it's
inviolable. When a *single org* genuinely needs a multi-writer stream, don't
touch a root: **create a shared topic** — a distinct, marked (`shared/…`),
org-owned, discoverable namespace — and add your own org's publishers to it,
narrowly, with a justification, with an expiry if it's temporary, knowing that
**attribution there is a recorded set, not a name.** If your subscribers or audit
can't live with that, reshape the topology instead — usually the better answer.
