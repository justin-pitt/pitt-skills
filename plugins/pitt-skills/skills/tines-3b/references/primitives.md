# Tines 3B Primitives

## The hierarchy

```
Tenant                     one organization's deployment
 |- Members, Groups, Service accounts     (principals)
 |- Connectors, Skills, Networks          (shared resources)
 `- Spaces                                git repositories
     `- Workflows                         top-level directories
         |- workflow.toml                 identity file, never edit
         |- README.md
         `- Steps                         subdirectories
             |- script.sh|py|ts / App.tsx
             |- config.toml
             |- README.md
             `- Dockerfile
```

Workflows, drafts, runs, executions, and build chats have **no access scope of
their own**. They resolve to their parent space.

## Step anatomy

A step is a directory, not a file, and routinely holds a full source tree
alongside the entry point.

| Component | File | Purpose |
|---|---|---|
| Core logic | `script.sh`, `script.py`, `script.ts`, `App.tsx` | the executable |
| Configuration | `config.toml` | behavior, routing, links, connectors |
| Documentation | `README.md` | first thing shown when the step is opened |
| Environment | `Dockerfile` | build and runtime environment |

### Templates

| Template | Entry | Dependencies | Runtime |
|---|---|---|---|
| shell | `script.sh` | none | shell |
| python | `script.py` | `requirements.txt` | Python |
| typescript | `script.ts` | `package.json` | Bun |
| react | `App.tsx` | npm | client-side, Tailwind |
| agent | n/a | n/a | model loop, chat or autonomous |

React steps require output enabled. The docs note further templates exist
without naming them.

### Dependencies

Declare in the manifest, never hand-install in the Dockerfile. The docs are
explicit: "You don't install packages by hand in the Dockerfile."

Tracked sources are npm (`package.json`), Python (`requirements.txt` or
`pyproject.toml`), and base images (`FROM` lines). The base image every step
starts from does not count as a dependency.

## config.toml

Only `color` is required. Omit a field rather than leaving it empty.

| Field | Meaning | Values |
|---|---|---|
| `color` | required, canvas color | `teal`, `lime`, `sky`, `red`, ... |
| `route` | creates an HTTP trigger at a path | `/checkout` |
| `route_auth` | access control on that route | `space` (default), `tenant`, `sso`, `external_id`, `connector`, `public` |
| `route_type` | surfaces the route on the Links tab | `webpage`, `api`, `webhook` |
| `cron` | schedule | `0 * * * *` |
| `email_address` | inbound mail starts a run, raw message as input | address |
| `timeout` | execution cap in seconds | 1 to 300, default 45 |
| `retry_seconds` | rerun unsuccessful steps | `[1, 2, 3]` |
| `links` | connect downstream steps | step names |
| `output` | return stdout as the HTTP response | bool |
| `title` | display title (observed, not in the doc list) | string |
| `connectors` | bind a connector to the step (observed, not in the doc list) | array of tables |

`retry_seconds` restarts the whole step on each attempt.

## The stdin/stdout contract

- A step "reads its input from stdin, does its work, and writes its result to stdout." Nothing platform-specific to learn.
- **One upstream:** stdin is the raw output the previous step wrote.
- **Several upstream:** it gets "the most recent successful one." This is a race, not a merge. There is no documented join or barrier.
- **Fan-out:** when a step links to several downstream steps, "they all receive the same output and run at the same time."
- **Empty stdout halts that path.** Intentional, and the only documented conditional.
- **stderr is the log,** kept separate from the data passed on.
- **A step marked as responding** has its stdout returned as the HTTP response body.

JSON is conventional, not mandated. Encoding rules, size caps, and non-JSON
behavior are undocumented.

## Links, two meanings

**Entry points** (the Links tab): "the front doors: the addresses people and
systems use to reach what you've built." Four kinds:

| Kind | Meaning |
|---|---|
| Webpage | HTML pages and forms a person opens in a browser |
| API | endpoints called programmatically, usually returning JSON |
| Webhook | endpoints receiving events from external services |
| Other | file downloads, redirects, OAuth callbacks |

A link is "a step that's been given a route, an HTTP path, and marked with the
kind of link it is." Routes without `route_type` stay functional but hidden.
The gallery is branch-aware, so a draft's entry points are visible before going
live.

**Step edges** (the `links` config key): downstream connections defining data
flow and execution order.

## Triggers

Four kinds. All of them fire on the **live, published version only**.

1. **Schedule** - cron, standard 5-field syntax with `*`, `*/n`, ranges, and lists. Timezone and minimum interval undocumented.
2. **Request** - a step with a route runs when someone reaches it. Covers webpages, APIs, and webhooks.
3. **Email** - `email_address` makes a step receive inbound mail, with the raw message handed to it as input.
4. **Workflow to workflow** - one workflow calls another.

A workflow can carry several triggers, each its own entry step.

## Runs and executions

**Execution** is the smallest unit: one run of one step's code. Carries stdin,
stdout, stderr, status (pending, success, error), and timing split into wait
duration and execution duration.

Two phases per execution: build the image from the Dockerfile, then run the
command. Build is skipped when cached.

Retries create a new linked execution. Executions are kept per the workflow's
retention settings; the numbers are undocumented.

**Run** is a single pass through a workflow, tied to the version active when it
began. Each step is a separate execution in its own container. States:

| State | Meaning |
|---|---|
| Running | at least one step still working or waiting |
| Success | every step finished without error |
| Error | at least one step failed |

**Solo run** executes one step alone. Downstream steps do not fire, and solo
runs are excluded from run history. When downstream steps exist, the run control
splits into solo and full.

**Test runs** do not appear in the runs list and do not cascade.

## Isolation

Every step, chat experiment, and connection test runs in its own single-use
container.

- **Sandbox:** gVisor, an extra layer between code and the real kernel.
- **Filesystem:** read-only except designated scratch space.
- **Lifecycle:** sandboxes are entirely destroyed after execution. A warm pool of clean checkpoints keeps startup fast.
- **Network:** code cannot reach the network directly. An egress proxy injects credentials, blocks private and internal addresses, and enforces routing policy.
- **Guardrails:** time budgets with automatic stopping, memory caps, throughput shaping. No numbers published.
- **Persistence:** working directories vanish. Only `/storage` volumes survive, living outside the container.

Steps start from a 3B base image and install their own packages, so different
steps can use incompatible toolchains.

## Branches

| Branch | Meaning |
|---|---|
| `main` | the live production version, marked with a green Live indicator. Handles all active triggers |
| Draft | safe experimental environment, own chat history and changes |
| Autofix (orange) | auto-generated on workflow error, when enabled |
| Autotune (purple) | auto-generated when performance improvements are identified |

**Each branch is its own sandbox, storage volumes included.** Draft changes,
test runs, and volume state stay invisible to `main` until merged, and draft
storage is discarded rather than promoted.

**Promotion** performs a three-way merge against the current live version,
surfacing conflicts before they go live.

**Fork as branch** starts from the specific commit being viewed, where a new
branch starts from the latest main. Forking a past version restores that state
as the starting point, which is the version-recovery path. A forked branch is
entirely independent.

`main` cannot be deleted. Root-level files in the repo are rejected. Never edit
or copy `workflow.toml`, which carries the workflow id.

## Personal workflows

Every member gets a personal space on first sign-in. Personal workflows are
always private, visible only to the owner and the tenant owner. The docs say not
to use them for team-critical work. How to move one into a shared space is
undocumented.

## Git as the authoring surface

```
git clone https://<tenant>/spaces/<space-slug>.git
```

Authenticate with an API key as the password. Three deployment paths: git push,
the 3B CLI, or the REST API with a bearer token.

Pushes are rejected when there are concurrent app-side edits.
