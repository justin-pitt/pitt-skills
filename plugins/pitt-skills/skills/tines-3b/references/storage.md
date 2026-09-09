# Storage

## There is one storage primitive

The volume. No second mechanism appears anywhere in the storage documentation.

"A volume is a named, persistent folder that a step can mount into its sandbox."
Once mounted "it appears at `/storage/<name>`" and acts as "a durable filesystem
directory mounted within the step's container."

Everything else vanishes: working directories are destroyed with the sandbox
after every execution.

## Two ownership flavors

| Flavor | Scope |
|---|---|
| Space volume | "shared across all workflows within a specific space... scoped by the space ID and branch ID" |
| Personal volume | scoped to one user. Files from personal chats and personal workflows, "separate from anyone else's" |

**The volume name is the join key across the whole space.** Every workflow in
the space declaring the same name reads and writes the same files. Namespace
names deliberately, or unrelated workflows collide on something generic like
`state`.

## The VOLUME directive

Three orthogonal dimensions.

| Dimension | Options | Syntax |
|---|---|---|
| Lifetime | durable (default), run-scoped | `VOLUME ["state"]` / `VOLUME ["work:scope=run"]` |
| Access | writable (default), read-only | `VOLUME ["state"]` / `VOLUME ["state:ro"]` |
| Concurrency | shared (default), exclusive | `VOLUME ["incoming"]` / `VOLUME ["state:concurrency=exclusive"]` |

Defaults when nothing is specified: "writable, shared, and tied to its branch,
which is the common case."

Durable means "files survive and stay visible to later Live workflow runs in the
same space." Run-scoped means "files exist only for the single workflow run that
created them, then they're gone," and is only available in workflow steps.

Lifetime and concurrency compose independently. A durable volume can be shared
when writers create disjoint paths; a run-scoped volume can still need exclusive
mode when parallel steps update the same file group.

## Commit semantics are transactional, not POSIX

This is the most precisely specified part of the platform and the most useful.

- "A step writes into its own private view while it runs. Other steps always see the last committed version, never half-written files."
- "When a step succeeds, its changed files publish. If it fails, nothing publishes."
- "Data stored in a volume survives workflow runs and redeploys."

Writes are **step-atomic**. The commit boundary is step success. A crashed,
timed-out, or OOM-killed step publishes nothing, so partial-write handling comes
free.

Failure modes that discard writes: exit 137 (memory limit), exit 142 or 143
(timeout).

**[undocumented]** What happens if the platform crashes after step exit but
before the publish completes, whether publish is atomic across a multi-file
change set, and the durability or replication of the underlying store.

## Concurrency

**Shared mode** uses optimistic concurrency with conflict detection: "If two
writers touch the same file, the release fails with a conflict rather than
silently letting the last write win."

**Exclusive mode** locks for the whole step. Best for "counters, cursors,
ledgers, sessions, a single append-only file, a package cache, or one database
or JSON file that many runs update."

The cost is stated plainly: "A model call, an API request, or a download inside
an exclusive step makes every other writer wait." Keep mutating steps tight and
push slow I/O into a separate step.

**[undocumented]** Lock timeout, queue depth, fairness, what a waiting writer
observes, and whether conflicts retry automatically.

## Structured data

There is no managed database, key-value store, or table service. Volumes are
file-like only. The docs give two paths:

**SQLite on a volume.** "SQLite works well on a durable or run-scoped volume for
structured data local to a workflow." Storage-inspection docs treat SQLite files
as normal volume contents.

**An external database through a connector.** "When you need to read from or
write to an existing external database, connect to it directly with a database
connector (Postgres, MySQL, Microsoft SQL Server, or MongoDB) rather than
storing that data in a volume."

Database connectors are a first-class creation category in the UI: pick the Data
category, choose the type, supply host, port, database, user, password, and TLS
settings.

## Sharing across boundaries

| Boundary | Shared? |
|---|---|
| Workflows in the same space | Yes, by volume name |
| Between branches | No. "each workflow branch works with its own isolated copy" |
| Draft to live on promotion | **No. "Draft storage is discarded rather than promoted to live."** |
| Between spaces | **[undocumented]**. Scoping is stated as space plus branch, which implies no, but the docs never say so |
| Personal vs space | Separate |

The draft-discard rule is the sharpest trap. Data written while testing never
reaches live, and live data is invisible from a draft.

## Limits

**No numeric size limit, quota, or retention period is stated anywhere.**

What exists is measurement, not enforcement: a storage-by-space treemap of
logical bytes, limited to team spaces with personal spaces excluded. A space
must use at least 6 percent of total storage to get its own tile, and the view
caps at 12 tiles. Those are display thresholds, not storage limits.

Resource limits that do exist apply to the sandbox rather than the volume:
CPU and memory caps surfacing as exit 137, and time budgets as 142 or 143.

**[undocumented]** Per-volume cap, per-space quota, tenant quota, file-count
limits, retention or expiry of durable files, and whether storage is billed
separately (it feeds the Tines unit metric, which combines compute, storage, and
transfer).

## Inspecting data

**Per workflow:** the workflow actions menu, Browse storage. Pick the branch,
choosing the main entry for live storage or a draft branch for that branch's
isolated files. Click through folders, preview inline, or download. "It's a
read-only view, so looking never changes your data."

**Per space:** monitoring, storage-by-space view, select a space to browse.

**[undocumented]** Any API or CLI for reading or writing volume contents from
outside a step, and whether the browser can delete files.

## Using a volume as an application record store

Workable with care, and the docs name the pattern almost exactly. A SQLite file
on a durable space volume, mounted `concurrency=exclusive` by every mutating
step, matches the documented use case of "one database or JSON file that many
runs update."

What supports it: space scoping shares one dataset across workflows, step-atomic
commit means a failed update leaves no partial write, exclusive mode serializes
read-modify-write, and shared mode surfaces conflicts instead of losing writes.

What to plan around:

- **Serialization cost.** Exclusive locks span the whole step, so no model calls or external API calls inside a mutating step.
- **Drafts see a different dataset,** and draft data is discarded on promotion.
- **No query surface outside a step.** Reading means running a step or using the read-only browser.
- **No stated quota or retention,** so growth is unbounded per the docs and unguaranteed in practice.
- **Concurrency is documented at the step level, not the row level.** No transaction isolation, row locking, or optimistic-concurrency token is described for records inside a file.

If the application needs real multi-user OLTP semantics, the documentation's own
recommendation points off-platform to a database connector.
