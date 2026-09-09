# API, MCP, GitSync, and Operations

## The REST API

Base path `/api/v1`. Interactive Swagger UI at `/api/v1/docs`, raw OpenAPI 3.1
spec at `/api/v1/openapi.json`. Both are readable without signing in.

**The tenant's own spec is the authoritative reference.** The documentation
enumerates no endpoints beyond one example and states no rate limits. Anything
load-bearing about API coverage should come from the live spec.

### Keys

Bearer token in the `Authorization` header, prefix `3b_sk_`.

| Key source | Lifetime |
|---|---|
| Member key (settings, your member, Access tab) | **24 hours** |
| Service account API key | long-lived until revoked |
| Service account temporary credential | 1, 4, 8, or 16 hours |

"They act as you. A key carries your own access, no more and no less."

Member keys are unusable for unattended automation. Use a service account.

### Observed endpoint surface

Recorded from a live tenant's spec. Treat as a snapshot of a fast-moving
product, not a contract.

```
/spaces                              GET, POST
/spaces/{id}                         GET
/spaces/{id}/access                  PATCH
/links                               GET
/workflows                           GET, POST
/workflows/{id}                      GET
/workflows/{id}/files                GET
/workflows/{id}/file                 GET
/workflows/{id}/zip                  GET
/workflows/{id}/runs                 GET
/workflows/{id}/run                  POST
/workflows/{id}/runs/{runId}         GET
/workflows/{id}/chat_messages        GET, POST
/workflows/{id}/executions           GET
/executions/{id}                     GET
/executions/{id}/output              GET
/executions/{id}/logs                GET
/connectors                          GET
/connectors/search                   GET
/connectors/{id}                     GET
/connectors/{id}/access              PATCH
/connection_claims/{claimId}         GET
/users                               GET, POST
/users/{id}                          GET, DELETE
/user_groups                         GET, POST
/user_groups/{id}                    GET, POST, DELETE
/roles                               GET, POST
/roles/{id}                          GET, DELETE
/service_accounts                    GET, POST
/service_accounts/{id}/federations   GET, POST
/service_accounts/{id}/tenant_roles  GET, PATCH
/oidc_providers                      GET, POST
/oidc_providers/{id}                 POST, DELETE
/workflows/{wid}/branches/{bid}/connect_step     POST
/workflows/{wid}/branches/{bid}/disconnect_step  POST
```

Two things stand out. **Connectors are read-plus-share only**, alone among the
major resources in having no POST. And **`POST /roles` exists** despite the docs
describing custom-role creation as a UI-only flow, which is the mirror image:
undocumented but present.

`/executions/{id}/output` returns the raw HTTP envelope a step wrote. Strip to
the first blank line before parsing. It is the correct place to look when a
route returned 504 but the step succeeded.

## MCP

Endpoint is the tenant URL plus `/mcp`, over Streamable HTTP.

Credential type determines the tool set, not permissions:

| Credential | Tools |
|---|---|
| OAuth (browser sign-in) | everything, and "the only credential that can use the tools that build and publish workflows" |
| Bearer token from a service account | read, trigger runs, and ask 3B to build. Cannot call direct build and publish tools |

"Service account is the only supported way to get a token."

Three tool groups: **explore** (list spaces and workflows, read steps, inspect
runs and executions, read skills and connectors), **run and ask** (trigger a
run, create a workflow, send messages to the editor so it builds for you), and
**build and publish** (write step files, run a step, run shell commands, connect
a connector, checkpoint, push live).

Governance: "MCP adds no new privilege." Access follows the identity, publishing
still needs push-live permission, and mutating actions are audited and tagged as
coming from MCP.

## GitSync

Two-way and event-driven. Changes in the platform push to the repository; a
GitHub App webhook makes a push to the repository pull back in, "usually within
seconds. There's no polling interval."

**Source of truth is not designated.** The docs never name a winner and never
describe conflict resolution. This is a real gap for a change-control design.

Scope is per space; each space mirrors to its own repository or its own
directory in a shared one. Two spaces may share a repo only with non-overlapping
directories, and content outside the configured directory is untouched.

Hard requirements:

- The default branch must be `main`
- The repository URL must be `https://` and must not contain a username or password
- Protected branches work: if the repo only accepts pull requests, changes reach the remote with the next merged PR rather than a direct push

The App requests Contents (read/write), Metadata (read), Pull requests
(read/write), and Statuses (read/write), and subscribes to push and
pull_request. The generated setup link is single use and expires after 10
minutes. Enterprise Server requires manual App entry.

Disconnecting removes the sync configuration without deleting workflows.

## SSO and SCIM

**SSO** supports OIDC and SAML. No identity providers are named as supported or
certified. Every documented behavior concerns tenant login; whether SSO can gate
an end-user-facing page is **[undocumented]**.

Sync modes: Off, JIT users only, JIT users and groups, SCIM. Manual invites are
disabled when JIT or SCIM is configured. Deleting the SSO config cannot be
undone and reverts to standard login, so a non-SSO path exists. No MFA or
break-glass mechanism is documented beyond testing in a private window to avoid
lockout.

**SCIM** 2.0 with Users and Groups. Endpoint ends `/scim/v2`, OAuth bearer
token, prefix `3b_scim_`, shown once.

- **Tokens are valid for 90 days.** Warning turns red inside 30 days. An expired token stops sync
- Rate limit 3,000 requests per minute, returning 429 with `Retry-After`
- Supported: PATCH, filtering, discovery endpoints
- **Explicitly not supported**: bulk operations, sorting, password changes, ETags

Two traps. Accounts are not created on first login, so users cannot sign in
before provisioning. And groups not created by SCIM and not adopted during
configuration **cannot be deleted in-app** while SCIM is enabled. Clean up
groups before enabling SCIM.

Set the source of truth deliberately: "When your provider owns users or groups,
the platform locks the matching controls so your provider can't overwrite your
manual changes."

## AI provider

Bring-your-own on paid tiers: "you need at least one AI provider connected and
set as the default." Connectable providers are OpenAI, Anthropic, Azure OpenAI
(base URL plus deployment names), and Oracle Cloud Infrastructure Generative AI,
plus OpenAI-compatible endpoints by base URL.

API keys are never typed into the provider form; they come from a connector.

Explore tenants get a platform-managed provider covering Claude and OpenAI with
no setup. Paid tenants must connect their own.

Per-provider configuration: chat model, fast model (blank reuses chat model),
and default effort level for reasoning models. Users can override model and
effort per chat without admin access, applying to that chat only.

There is **no credit system**. You pay your provider directly. The only
credit-like construct is Explore's one-time AI allowance.

## Pricing and Tines units

A platform licence model covering three components: environment, infrastructure,
and runtime.

| Plan | Infrastructure | Runtime |
|---|---|---|
| Core | multi-tenant stack | 150K Tines units per month |
| Scale | dedicated stack | 300K TU per month |
| Power | premium dedicated stack | 600K TU per month |

**Explore** (free) mirrors paid editions with four stated limits:

- Live workflows limited to 3
- 5,000 Tines units per month
- A one-time AI allowance
- **No public website URLs allowed**

"Live workflows only matter in our Explore edition where they count towards your
license," so no cap is documented on paid tiers.

**One metric is billed: the Tines unit,** combining compute, storage, and
transfer. The allowance resets monthly and does not roll over. Overages are
charged at a rate per month, with a one-month grace period for new customers.

**[undocumented]** Dollar prices for any tier, per-seat pricing, the overage
rate, and any conversion between Tines units and real workload volume. You
cannot size a plan from the documentation.

AI tokens are not metered by the platform on paid tiers, since you bring your
own model.

## Monitoring

**Execution and runs.** A runs tab with a waterfall chart, per-step queue versus
run time, and a count of persistent (non-ephemeral) runs. No retention period is
stated.

**Dependencies.** Parses `package.json`, `requirements.txt`, `pyproject.toml`,
and Dockerfiles across live workflows, reporting package name, all versions in
use with highlights when several exist, workflow count, and source.

**AI cost.** Estimated spend, tokens, turns, and cache hit rate over a fixed
30-day window. Costs are **your own estimates, not billed amounts**: the
platform "does not pull figures from a provider's billing or cost API, so the
numbers you see are only as accurate as the rates you set." Rates are per model,
entered per million tokens, with separate input, output, cache-read, and
cache-write rates. Budgets exist as provider-level and space-level caps, though
whether breaching one blocks or only warns is **[undocumented]**.

**ROI.** `Value = (Minutes saved x Hourly rate) / 60`, default rate $75/hour,
window capped at 90 days, personal spaces excluded. Estimates are labeled AI
estimate, Manual, or Not set.

**Route auditing.** A radar chart of live-route workflows grouped by auth mode.
The fastest answer to "what is exposed publicly."

**Autofix and autotune.** Both gate on human accept or reject and generate their
own colored branches. Neither modifies a live workflow directly. Autofix cannot
fix infrastructure issues or bypass permissions, and works best on clear errors.

## Watchtower and audit logs

**Watchtower** gives admins a tenant-wide view of every space, any member's
personal workflows, and **any member's chats**. Two tenant permissions gate it,
one for spaces and personal workflows, one for personal chats. The docs' own
caution: "watchtower is a sensitive capability. It exposes private work across
your tenant, so grant these permissions carefully."

Admin viewing is visually marked with a badge and an indicator. Stated purposes
are audits, investigations, and offboarding checks. **[undocumented]** Retention,
export, whether the viewed member is notified, and whether Watchtower reads are
themselves audited.

**Audit logs** carry time, user, operation, source, status, and expandable
context including error messages, input parameters, IP address, and user agent.
Forwarding destinations are configurable over HTTPS with PUT or POST, optional
connector-based auth, and S3-style batching via a filename placeholder.

**Native retention is not stated anywhere.** The framing is that you forward
logs "to keep your logs for long-term storage or compliance," which implies
in-product retention is finite. Confirm before relying on it.

Confirmed captured: SCIM changes, and MCP mutations tagged as coming from MCP.
The full event catalog, who can view, filtering, and a read API are
**[undocumented]**.
