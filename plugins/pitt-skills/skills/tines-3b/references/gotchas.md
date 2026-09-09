# Tines 3B Gotchas

Behaviors the docs underspecify, contradict, or omit. Each entry is tagged with
its provenance:

- **[doc]** stated in the official documentation
- **[observed]** measured against a live tenant, not in the docs
- **[conflict]** the docs and a live tenant disagree
- **[undocumented]** the docs are silent, which is not the same as unsupported

Empirical evidence outranks documentation when they disagree, because docs lag.
Say which is which rather than merging them silently.

---

## Silent failures

### Fan-in drops data, it does not merge it

**[doc]** "If several steps feed into it, it gets the most recent successful
one."

Two upstream steps linking into one downstream step is a race, not a join. The
loser's output is discarded with no error. Anyone arriving from a platform with
an explicit aggregation primitive will assume a merge and lose data.

There is **[undocumented]** no documented join, barrier, or wait-for-all. If you
need one, build it: write to a volume from each upstream step and have the
downstream step read the set.

### Writing nothing to stdout halts the chain

**[doc]** "If a step writes no output at all, the steps after it don't run. This
is intentional and genuinely useful."

This is the only documented conditional. There is no condition expression, rule
array, or filter step. A step that exits 0 but prints nothing silently ends that
path, which is a useful idiom and an easy accident.

### Denied resources render as absent, not forbidden

**[doc]** Access denial makes a resource appear nonexistent rather than
returning an error.

A connector missing from a picker is a permissions symptom far more often than a
bug. Check grants before debugging.

### A connector goes unavailable based on the weakest member of a space

**[doc]** "A connector, skill, or network is only usable in a space when
everyone who has access to that space also has the right access to that
resource."

Availability is a function of the least-privileged member, not the acting user.
Adding one viewer without connector access breaks every workflow in that space.
Grant to the space itself rather than to individuals.

---

## Conflicts between docs and live behavior

### A route returns 504 while the step keeps running and succeeds

**[conflict]** Step `timeout` is documented as 1 to 300 seconds. Something in
front of the runtime is not honoring it: runs measured at 34.7s and 34.0s both
returned 504 to the caller and both recorded `success` with correct output.

**A 504 is not evidence of failure.** Read the execution output endpoint
instead. The documented workaround is the async pattern: return 202 Accepted
immediately and process in the background. Cron invocations have no caller and
are unaffected.

### The Explore live-workflow cap is not enforced

**[conflict]** Documented as "Live workflows: Limited to 3" on Explore.
Observed: pushing a fifth workflow was accepted and went live.

Do not design against the cap being absent. It is a documented limit that
happens not to be enforced today, which is the kind of thing that changes
without notice.

### `route_auth = "external_id"` may not be usable

**[conflict]** Documented as a valid mode that lets external services push
"without requiring a user to be logged in to your tenant." Observed on one
tenant: the route answered 500 complaining that an external_id was required in
config, however the value was authored, and the REST API exposes no surface to
register one.

Confirm on the target tenant before designing an inbound push around it.

---

## Authentication and keys

### Member API keys expire after 24 hours

**[doc]** "They expire after 24 hours. Treat each key as short lived, and
generate a fresh one when it lapses."

This is the single most common source of "my key mysteriously stopped working."
It is expiry by design, not rotation or revocation. **Service account API keys
are long-lived** and are the only viable identity for unattended automation.

### The git remote embeds the API key

**[observed]** Cloning a space embeds whatever key you cloned with in the remote
URL. A dead key breaks `git push` with an invalid-key error that looks nothing
like an auth expiry.

Rotating a key therefore needs two edits: wherever the key is stored for API
calls, and `git remote set-url`.

### The OpenAPI spec is served unauthenticated

**[doc]** "You don't need to sign in or supply an API key just to read the
docs." **[observed]** `/api/v1/openapi.json` returns the full schema to an
anonymous request.

Schema disclosure only, no tenant data. Worth knowing if `/api/v1/*` was assumed
to be auth-walled end to end.

### MCP tool access depends on credential type, not permissions

**[doc]** OAuth credentials can build and publish. Bearer tokens from a service
account can read, trigger runs, and ask 3B to build, but "can't call the direct
build and publish tools." A build tool called with a bearer token is refused.

"Service account is the only supported way to get a token."

---

## Connectors

### Creation is UI-only

**[doc]** All documented creation paths go through the interface: library
connector, custom API key connector, database connector, or the
"use this workflow as a connector" button.

**[observed]** The published OpenAPI spec gives connectors `GET` list, search,
and get, plus `PATCH` on access. No POST, PUT, or DELETE. Spaces, workflows,
users, groups, roles, and service accounts all have POST; connectors
deliberately do not.

**[undocumented]** The docs never state that API creation is unsupported. This
is inference from the spec, not a documented limit. No CLI, config-file, or
Terraform path for 3B connectors is documented anywhere. The Terraform provider
and Admin API that turn up in search results belong to classic Tines, a
different product.

### Attaching a connector to a step needs both the declaration and the call

**[observed]** Declaring the connector in `config.toml` alone persists a null id
and leaves the injected environment variable unset at runtime, so the step
reports the connector as not attached. The attach call alone binds on a new
branch. Both are required for `main` to resolve.

The attach response reports a fork and leaves a stray branch behind. Once a
connector has been attached to a workflow once, later steps in that workflow
resolve from the declaration alone.

### The declaration stores a name slug, not an id

**[observed]** The committed artifact never names the connector id, so renaming
a connector silently repoints the binding. The id is recoverable only on
readback from the workflow detail endpoint.

Declare by slug, assert by id.

### Editing a connector saves on blur, with no save button

**[doc]** "As you change a field and move off it, the change saves on its own."
There is no confirmation step. Credential rotation is in-place and immediate.

---

## Storage

### Draft storage is discarded, never promoted

**[doc]** "Draft storage is discarded rather than promoted to live." Each branch
gets an isolated copy of every volume.

Data written while testing in a draft never reaches the live volume, and live
data is not visible from a draft. Anyone testing stateful logic will be
surprised twice: once when the draft cannot see production state, and again when
their test data vanishes on promotion.

### Volumes are scoped to the space, not the workflow

**[doc]** "Every workflow in the space that declares the same volume name reads
and writes the same files."

The volume name is the join key across the whole space. Namespace volume names
deliberately, or two unrelated workflows will collide on a generic name like
`state` or `data`.

### Shared writers conflict rather than last-write-wins

**[doc]** "If two writers touch the same file, the release fails with a conflict
rather than silently letting the last write win."

Safe, but it means concurrent writers need either disjoint paths or
`concurrency=exclusive`. **[undocumented]** Lock timeout, fairness, queue depth,
and whether a conflict is automatically retried.

### Exclusive locks span the whole step

**[doc]** "A model call, an API request, or a download inside an exclusive step
makes every other writer wait for that slow work to finish."

Keep mutating steps tight. Do the slow work in one step, the exclusive write in
the next.

---

## Execution

### Every execution is a container build plus a run

**[doc]** Build is skipped when the image is cached. Cold steps pay build cost.
There is no instant-action model.

### Solo runs and test runs do not cascade

**[doc]** Solo run executes one step and "downstream steps don't fire." Test
runs "don't show up in the runs list and don't cascade to downstream steps."

There is no way to push a test event through the graph the way an event
propagates on some other platforms.

### Drafts fire no triggers at all

**[doc]** "Scheduled (cron) steps, inbound web requests, and email triggers fire
on the published version only."

Draft testing is manual runs plus branch-scoped route previews.
**[observed]** The branch is selected with a `?branch=<id>` query parameter; the
docs mention branch URLs without giving the syntax.

### Cron fires on exact UTC wall-clock boundaries, and stdin is a null device

**[observed]** On a cron invocation stdin is `/dev/null`, a character device. A
request parser reading it does not hang, it silently fabricates a request that
never happened. Never gate work on a parsed HTTP method in a step that also has
a cron.

**[undocumented]** Cron timezone and minimum interval.

### Exit codes carry meaning

**[doc]** 137 is a memory limit, 142 and 143 are timeouts. A step killed this way
publishes no volume changes.

---

## Terminology traps

### "Links" means two opposite things

**[doc]** The Links tab and the Links article mean **entry points**: the ways
into a workflow from outside. The `config.toml` `links` key and the dictionary
mean **step-to-step edges**: the way data flows onward.

Same word, opposite direction. Read which one is meant from context.

### `route_type` controls visibility, not behavior

**[doc]** Setting `route_type` is what surfaces a route on the Links tab.
Omitting it leaves the route fully functional but hidden, which is the right
choice for internal callbacks and helper endpoints.

---

## The config.toml field list is not exhaustive

**[doc]** The published field summary covers `color`, `route`, `route_auth`,
`route_type`, `cron`, `email_address`, `timeout`, `retry_seconds`, `links`, and
`output`.

**[observed]** `title` and `connectors` are real, in use, and absent from that
list. Treat the documented list as a starting point.

Only `color` is required. Omit a field rather than leaving it empty.

---

## Cross-step and cross-workflow blind spots

### A step cannot verify a sibling step's state

**[observed]** Reaching a sibling route needs a credential. Where policy forbids
storing credentials in the tenant, none exists, so files duplicated between step
directories have no in-platform drift guard.

The workaround is to publish a digest over raw file bytes and compare from
outside. Do **not** reach for the inbound `Host` header and replay the caller's
`Authorization` header to fetch a sibling: that is an SSRF plus credential
exfiltration bug.

### The file-listing endpoint disagrees with itself about paths

**[observed]** The listing endpoint returns paths with a leading slash; the
single-file endpoint rejects the leading slash.

---

## Arriving from Tines Stories

Twelve things that do not carry over. None of these are opinions about which
product is better; they are structural.

1. **No pills, no formulas, no actions.** A step is code in a container. Data arrives as bytes on stdin.
2. **Conditional branching is "write nothing to stdout."** No trigger action, no rules, no no-match path.
3. **Fan-in is a race, not an implode.** Most recent successful upstream wins.
4. **"Links" is overloaded.** Entry points on the tab, step edges in config.
5. **Default route auth is `space`, not public.** Public-by-unguessable-URL is an opt-in here and is flagged in the docs as needing review.
6. **Per-step hard timeout, 45s default and 300s max.** Long work must go async behind a 202.
7. **Draft branches fire nothing.** There is no draft-firing query parameter for webhooks as in Stories change control.
8. **Storage is branch-scoped and drafts are discarded.** Stateful testing behaves differently than expected.
9. **Every execution is a container build plus run.**
10. **Solo and test runs never cascade.**
11. **No credential pill.** The egress proxy injects auth on the wire; secrets never appear in step source.
12. **The space is a git remote.** Push deploys. Branch, merge, and three-way conflict resolution replace the draft and change-request model entirely.

And three things Stories has that 3B does not ship at all
(**[undocumented]**, meaning no entity exists in the docs, not that it is
forbidden):

- **No case or ticket entity.** The dictionary has no such noun. Tickets appear only as objects created in external systems through connectors.
- **No records store.** No structured lightweight database primitive.
- **No no-code form designer.** Forms are a first-class documented route pattern, but you get to them by prompting the agent to write a React step, not by dragging fields onto a canvas.
