---
name: tines-3b
description: Tines 3B is a separate product from Tines (Stories), not an upgrade path. Workflows are git repositories, steps are containerized code directories that pipe stdin to stdout, and an AI agent builds them from prompts. Use this skill whenever the user mentions Tines 3B, 3B spaces, 3B workflows, steps, config.toml, route_auth, route_type, webpage routes, volumes and /storage, Tines units (TUs), connectors and the credential proxy, 3B skills, watchtower, autofix, autotune, solo runs, 3B branches or push-live, the 3B REST API or MCP endpoint, GitSync, tunnels and networks, or docs.3b.tines.com. Also trigger when comparing 3B against Tines Stories, deciding which of the two a use case belongs in, or migrating between them. For classic Tines (stories, actions, pills, formulas, Cases, Records, Pages), use the `tines` skill instead.
license: MIT
user-invocable: false
---

# Tines 3B Skill

## What This Skill Covers

Tines 3B is a **different product from Tines Stories**, sharing a vendor and a
name and almost nothing else. There is no documented migration path between
them, and the primitives do not map: 3B has no pills, no formulas, no actions,
no Cases, no Records.

1. **Primitives** - spaces, workflows, steps, runs, executions, branches
2. **The step contract** - directories of code, stdin to stdout, config.toml
3. **Routes and auth** - six auth modes, webpages, webhooks, external access
4. **Storage** - volumes, scoping, commit semantics, concurrency
5. **Access control** - the grant model, roles, and the weakest-member rule
6. **Connectors** - the credential proxy, creation paths, failure modes
7. **AI surface** - build-by-chat, agent steps, skills, autofix, autotune
8. **Ops** - the REST API, MCP, GitSync, tenant units, monitoring

## Quick Orientation

**A space is a git repository.** Each workflow is a top-level directory in it,
each step a subdirectory. `git push` deploys. That single fact explains most of
the platform: branching is the change-control model, promotion is a three-way
merge, and the source of truth is a commit.

**A step is a directory, not a file.** It holds source (`script.sh`,
`script.py`, `script.ts`, or `App.tsx`), a `config.toml`, a `README.md`, and a
`Dockerfile`. Steps routinely hold a dozen source files. Every execution builds
a container image and runs it, with image caching making repeats fast.

**Steps talk over stdin and stdout.** No platform-specific data model. A step
reads bytes on stdin, writes bytes to stdout, and its stderr becomes the log.
Writing nothing to stdout halts the chain, and that is the only documented
conditional.

**An AI agent does the building.** The documented default is that you prompt 3B
and it writes the step, including React front ends. You can hand-write
everything, and you can drive it from your own editor over git, but the product
is designed around the chat loop.

Core vocabulary:

- **Tenant**: one organization's deployment. Owns members, groups, connectors, skills, networks, service accounts.
- **Space**: a git repo holding workflows, plus its own volumes and access grants. Shared or personal.
- **Workflow**: a top-level directory in a space. Has branches; `main` is live.
- **Step**: a subdirectory. One unit of execution, one container.
- **Run**: one pass through a workflow. **Execution**: one run of one step.
- **Route**: an HTTP path on a step. **Link**: an entry point surfaced on the Links tab.
- **Volume**: a persistent directory mounted at `/storage/<name>`, scoped to space plus branch.
- **Connector**: a tenant-level credential binding. The credential proxy injects auth on the wire.
- **Skill**: a reusable instruction bundle that gives the agent new expertise.
- **Tines unit (TU)**: the single billing metric, combining compute, storage, and transfer.

**Default build pattern:** a step with a `route` and `route_type` as the entry
point, `links` to downstream steps, a `VOLUME` for anything that must persist,
and a connector for anything authenticated.

## Reference Files

> **Read `references/gotchas.md` before building anything.** It carries the
> documented-versus-observed conflicts, the traps that cost hours, and the
> twelve things that surprise anyone arriving from Tines Stories. Several are
> silent failures: fan-in drops data, denial renders resources invisible, and a
> connector goes unavailable based on the weakest member of a space.

| File | When to Read |
|---|---|
| `references/gotchas.md` | Before any build. Docs-vs-reality conflicts, silent failures, Stories-migrant traps, things the docs leave undocumented |
| `references/primitives.md` | Step anatomy, the full `config.toml` field list, stdin/stdout contract, links, triggers, cron, runs vs executions, solo runs, branches, isolation |
| `references/routes-and-auth.md` | The six `route_auth` modes, `route_type`, webpages, webhooks, reaching users without accounts, route auditing |
| `references/storage.md` | Volumes, the `VOLUME` directive, scoping, commit semantics, concurrency and locking, structured data, what to use instead |
| `references/rbac-and-connectors.md` | Grants model, the complete built-in role list, custom roles, the weakest-member availability rule, connector creation and auth types, credential proxy, networks and tunnels |
| `references/api-and-ops.md` | REST API surface and key lifetimes, MCP tool tiers, GitSync, SSO and SCIM, pricing and Tines units, monitoring, watchtower, audit logs |

## Choosing Between 3B and Stories

Neither is the successor. Pick on the shape of the work.

**3B fits** custom front ends and internal apps, anything wanting real code and
real dependencies, work that benefits from git-native change control, and
greenfield builds where an agent writing the first draft is an advantage.

**Stories fits** case management and approvals (3B ships no case or ticket
entity), anything needing a no-code form designer, teams who will maintain it
without writing code, and work that must integrate with an existing Stories
estate.

The decision usually turns on one question: does the use case need a **case
entity with statuses, assignment, and an audit trail**? Stories has that
built. In 3B you would build it, over a volume or an external database.

## Working Discipline

- **Distinguish undocumented from unsupported.** The 3B docs are new and thin in
  places. Silence is not a denial. This skill marks the difference everywhere,
  and answers should preserve it.
- **The tenant's OpenAPI spec beats the docs** for API questions. It is served
  at `/api/v1/openapi.json` and is readable without authentication.
- **Probe before promising.** The product is on its third major version and
  moves fast. Anything load-bearing should be confirmed against the live tenant.
- **Drafts fire nothing.** Cron, webhooks, and email triggers run on the live
  branch only. Test with manual runs and branch-scoped route previews.
