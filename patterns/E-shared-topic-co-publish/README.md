# Pattern E (advanced) — shared topic, more than one publisher

**The exception to the rule.** Patterns A–D each have **one** publisher owning a
key prefix — that is the default and it makes provenance free. This pattern is
the *deliberate* case where an organization wants **more than one of its own
publishers** on a single topic, without ever weakening that default.

```
shared/<org-pool>/<topic-id>/**     ← a DISTINCT, marked, multi-writer namespace
                                       (never a single-owner <anchor>/** root)
```

> This is an **advanced** pattern: it needs an org's data-governance admin to
> create the shared topic and add publishers, plus one router deploy to enforce
> it. Read [`docs/co-publish.md`](../../docs/co-publish.md) first — this pattern
> is the runnable companion to that guidance.

## When this is the right answer

Only when a **single organization** genuinely needs a multi-writer stream:

- a **shared org feed** several of the org's systems contribute to (a primary
  and a failover collector publishing one logical status stream);
- a **registry / aggregation service** maintaining derived state on behalf of
  the org's producers;
- a **same-org gateway** republishing several of its own streams through one
  topic.

Everywhere else, keep one writer per root (Patterns A–D). If two writers are
really two streams, give them their **own** roots and let subscribers merge.

## What it does NOT do — and the invariant it protects

- **It never adds a second writer to an existing single-owner root.** That
  guarantee — "everything under `<anchor>/…` came from that one identity" — is
  what makes provenance free, and nothing spends it. A shared topic is a
  *separate* namespace under the reserved `shared/` class, and it announces
  itself: a reader sees immediately that it is multi-writer.
- **It is not cross-organization.** Shared topics are at-most-own-org: an admin
  only creates topics for, and adds publishers from, *its own* org. Letting
  another org publish into your space is refused by design.
- **The org's name is never in the key.** `<org-pool>` is a stable, opaque
  per-org handle; the owning org (and a human name) resolve off-key via the
  registry + alias layer. Names are mutable, keys are freeze-critical — so the
  name never goes in.

## The trade-off you accept: attribution is many-to-one

On a shared topic, a subscriber can no longer infer the writer from the key —
that was the whole point of the single-owner rule, and you have deliberately
stepped outside it. Read the sample's own `SourceInfo` for the author, and know
that "who can write here" is now a **recorded set** (every publisher is a
justified, effective-dated, audited grant).

## Who does what (the `PUBSUB-ORG-ADMIN` capability)

Creating a shared topic and adding publishers is the **write facet of an org's
data-governance authority** — the `PUBSUB-ORG-ADMIN` capability. It is a
deliberate, audited act, not a side effect:

1. **create** the shared topic — `goat access co-publish create-topic`
2. **add** each publisher — `goat access co-publish grant … --to <topic>`
3. **enforce** — capture the grant into the router config and restart it (a
   deploy step; the ACL does not reload live)

## What the demo shows

`run.sh` drives the parts you can see from a client:

- **creates** a shared topic and prints its key — note the reserved `shared/`
  class and the **opaque** `<org-pool>` handle (never your org's name);
- **lists / discovers** it, showing the `MULTI-PUBLISHER` marker and the owning
  org resolved *off* the key;
- explains the **grant → enforce** step and the two-publisher outcome, which are
  **deployment-gated** (the ACL is static and restart-required) — so, like
  Pattern D's empty replay, the demo says so plainly rather than faking it.

Once the grant is enforced, a granted co-publisher's sample **lands** on the
shared topic, an **un-granted** writer is silently **denied**, and a co-publisher
**cannot** write another peer's single-owner root — the inviolability guarantee.
Verify each on your goatnet by presence and absence, as
[`docs/co-publish.md`](../../docs/co-publish.md) describes.

> Needs a `goat` new enough to carry `goat access co-publish`, and — to actually
> create a topic — an identity that **governs** the org (the `PUBSUB-ORG-ADMIN`
> capability). If you don't, the demo shows the guardrail refusing you, which is
> itself the point: the capability is deliberate and scoped.
