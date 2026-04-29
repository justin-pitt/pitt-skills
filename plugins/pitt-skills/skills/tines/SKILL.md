---
name: tines
description: Tines is a no-code automation and orchestration platform commonly used as a SOAR replacement, IT automation engine, and workflow builder. Use this skill whenever the user mentions Tines, Tines stories, actions, AI Agent action, Story copilot, Webhook actions, HTTP Request actions, Event Transform, Send to Story, Resources, Pages, Cases, Records, credentials, Connect Flows, the Tines API, tenants, change control, self-hosted Tines, Helm charts for Tines, Tines Tunnel, Command-over-HTTP, Tines on Azure or AWS, Tines credits, the Workbench, or any automation or workflow build inside Tines. Also trigger when the user asks about migrating from XSOAR or other SOAR platforms to Tines, designing playbook or story patterns, integrating security tools through Tines, building forms with Pages, or running case management in Tines.
license: MIT
---

# Tines Skill

## What This Skill Covers

This skill helps you work effectively with Tines across its major functional areas:

1. **Platform Architecture** — Tenants, teams, users, roles, and access control
2. **Stories & Actions** — Building, testing, deploying, versioning, and operating workflows
3. **Action Types** — The eight action types, Event Transform modes, and Tools
4. **Resources, Cases, Records, Pages** — Data, case management, lightweight DB, and frontends
5. **Credentials & Connect Flows** — Auth handling, vendor-specific OAuth flows
6. **Formulas & Expressions** — The Tines formula language for data transformation
7. **AI Capabilities** — AI Agent action, Story copilot, and Prompts
8. **Self-Hosted Deployment** — Docker Compose, AWS Fargate, Helm/Kubernetes
9. **Admin & Security** — SSO, audit logs, IP/egress control, Tunnel, Terraform
10. **API & Integration** — REST API, Workflows as APIs, MCP server templates
11. **XSOAR-to-Tines Migration** — Conceptual mapping for teams migrating from XSOAR

## Quick Orientation

Tines is a no-code/low-code automation platform built around a simple primitive model: **Actions emit events to other Actions inside Stories**. Unlike XSOAR's playbook-and-script model, Tines workflows are declarative graphs where most logic happens through HTTP Request actions, Event Transform actions, and Conditions — with optional Run Script tools when arbitrary code is needed.

Key architectural concepts:

- **Tenant**: A single isolated Tines instance for one organization. SaaS or self-hosted.
- **Teams**: Logical groupings inside a tenant. Stories, Actions, Credentials, and Resources scope to a team unless explicitly shared.
- **Story**: A graph of Actions that automates a workflow. Equivalent to an XSOAR playbook, but as a pure event-driven graph rather than a task list.
- **Action**: The atomic execution unit. Emits and consumes events. Eight types (see below).
- **Event**: The data payload that flows between Actions. JSON object with arbitrary structure.
- **Resource**: Centralized data store (text, JSON, file) shared across Stories within a team. Equivalent to global variables.
- **Credential**: Authenticated connection to an external service (Text, AWS, HTTP, mTLS, JWT, OAuth 2.0, Multi Request).
- **Connect Flow**: Pre-built credential setup wizard for ~200+ vendor integrations.
- **Case**: Case management feature for incident-style work, with fields, tasks, groups, notifications.
- **Record**: Lightweight key-value/structured data store for state-tracking inside or across Story runs.
- **Page**: A frontend/form for collecting input or displaying output to humans.
- **Tunnel**: Outbound-only connector that lets Tines reach systems behind the firewall without inbound exposure.
- **Workbench**: Analyst-facing interface for human-in-the-loop interaction with Stories (also available in Slack).

**Default workflow build pattern:** Webhook (entry) → HTTP Request(s) → Event Transform / Condition (logic) → Send Email / HTTP Request (outputs) → optional Send to Story (sub-workflow).

## Reference Files

Read the relevant reference file before answering detailed questions on these topics.

| File | When to Read |
|---|---|
| `references/platform.md` | Deep questions on Tines concepts: action types in detail, stories, change control, resources, cases, records, pages, credentials, formulas, self-hosted overview, admin features, pricing, MCP server templates |
| `references/workflow-design-framework.md` | Pre-build decisions: humanled vs deterministic vs agentic taxonomy, four-question decision framework, when to automate at all, mode selection matrix, hybrid workflow patterns, builder skills |
| `references/agents.md` | AI Agent action deep-dive: configuration, tools (Public/Private Templates, Send to Story, Custom Tools, MCP), Task vs Chat mode, Think tool, models, AI credit pool, audit, common patterns and anti-patterns |
| `references/ai-production-patterns.md` | Production-tested AI deployment patterns: multi-agent orchestration (lead + specialized), question bank, context window management, cost tracking via Records, AI-on-AI QA, anti-hallucination patterns, memory architecture, validation patterns (parallel-run, detection health, rubric eval), deterministic guardrails, real-world benchmarks |
| `references/ai-governance.md` | AI governance framework: approval gates, risk-based prioritization, change control, auditability, transparency. High-performing vs add-on AI adoption. Vendor AI risk. AI bias considerations. Voice of Security 2026 industry context. CDW stakeholder mapping. |
| `references/api.md` | API authentication, REST endpoints, pagination, Workflows-as-APIs (Webhook entry pattern), Send to Story payload format, Terraform provider, action type IDs, common automation patterns |
| `references/self-hosted-azure.md` | Self-hosted deployment in Azure: AKS via Helm, prerequisites, architecture, sizing, networking, identity, observability, backup/DR, upgrade path, security hardening, migration from POC SaaS |
| `references/xsoar-to-tines.md` | Migration from Cortex XSOAR/XSIAM to Tines: mental model shift, concept mapping, action-level mapping, custom code migration, integration migration, incident-to-case migration, gotchas, recommended migration approach |

## The Eight Action Types

| # | Action Type | Purpose | Closest XSOAR Analog |
|---|---|---|---|
| 1 | **Webhook** | Receive HTTP requests as Story entry points; expose Stories as APIs | XSOAR webhook integration / fetch-incidents |
| 2 | **Receive Email** | Receive emails as events (Email mode = inbound MX, IMAP mode = poll a mailbox) | Mail Listener integration |
| 3 | **Send Email** | Send outbound emails | `send-mail` command |
| 4 | **HTTP Request** | Make outbound HTTP calls to any API. The workhorse — replaces ~80% of XSOAR integration commands | Generic HTTP integration |
| 5 | **Condition** | Branch logic based on event data | Conditional task in playbook |
| 6 | **Event Transform** | Manipulate events (8 modes: Deduplicate, Delay, Explode, Extract, Implode, Message only, Throttle, Automatic) | XSOAR scripts / context manipulation tasks |
| 7 | **Send to Story** | Invoke another Story as a sub-workflow (with optional looping over arrays) | Sub-playbook |
| 8 | **AI Agent** | Goal-directed AI action that can invoke tools, run iteratively, and produce structured output | No direct equivalent (Cortex Copilot is closest but less capable) |

**Event Transform modes:**
- **Deduplicate** — drop events seen before within a lookback window
- **Delay** — pause N seconds before emitting
- **Explode** — given an array field, emit one event per element
- **Extract** — pull specific fields out of an event using formulas
- **Implode** — collect events over time/count and emit one aggregated event (the inverse of Explode)
- **Message only** — emit a static or templated message event
- **Throttle** — rate-limit event emission
- **Automatic** — Tines picks the right mode based on context

## Tools (Drag-on, Not Action Types)

In addition to the eight Action types, four **Tools** can be dragged onto the Storyboard:

| Tool | Purpose |
|---|---|
| **Group** | Visually organize related Actions; collapsible container in Storyboard |
| **Page** | Frontend/form built into the Storyboard for human input or display |
| **Note** | Inline documentation on the Storyboard |
| **Record** | Capture data into a Records dataset from the Storyboard |

Plus the **Run Script** tool when arbitrary Python or JavaScript is required.

## Stories: Modes, Versioning, and Change Control

- **Story modes**: `LIVE` (production) or `DRAFT` (testing). Each Story has a single LIVE version and can have an active DRAFT.
- **Change Control**: When enabled, all changes go through a draft → review → publish flow. Uses Test Resource values during draft so live data isn't affected.
- **Versioning**: Story Versions back up, inspect, clone, export, and restore any version. Accessed via the clock icon on the Storyboard.
- **Send to Story**: Sub-Story pattern. Receiving Story has an entry point with declared inputs; calling Story uses Send to Story action with optional `loop` parameter to process arrays serially.
- **Workflows as APIs**: Any Story can expose itself as an HTTP API by configuring a Webhook entry action and Exit action. Webhook returns the exit action payload synchronously (within 30s) or async via response_url.

## Resources

Centralized, team-scoped data store for plaintext, JSON, or files (5MB limit per Resource). Reference in formulas with `RESOURCE.name`.

- Test Resources for draft testing (used by Change Control)
- Lockable to prevent edits to Resources used by high-priority Stories
- Shareable across all teams or specific teams
- Common patterns: lookup tables, allowlists/blocklists, configuration constants, shared API config

## Cases vs. Records

- **Cases** are for incident-style work: structured fields, multiplayer collaboration, tasks, groups, notifications, sensitive fields, and limits. Closest to XSOAR incidents but lighter.
- **Records** are a lightweight structured datastore. Live and test records, with limits. Use for state tracking, lookup data populated by Stories, or accumulating output for reporting.

Use Cases when humans need to investigate. Use Records when Stories need to read/write structured state.

## Pages

In-platform web pages built into the Storyboard. Used for:
- Collecting human input mid-workflow (form fields, file upload)
- Displaying status or results to non-Tines users
- Building lightweight internal apps and approval flows
- Page Collections group related pages into a single navigable interface
- Custom domains supported

Pages can be conditional and looping, and access-controlled by team, user, or external token.

## Credentials and Connect Flows

Seven credential types:
1. **Text** — static secrets, API keys
2. **AWS** — IAM access keys, IRSA, role assumption
3. **HTTP request** — when auth requires a token-fetch step
4. **Mutual TLS** — client cert auth
5. **JWT** — JWT-signed bearer tokens
6. **OAuth 2.0** — full OAuth flow with refresh
7. **Multi Request** — chain multiple auth requests

**Connect Flows** are pre-built credential wizards for ~200+ vendors. Confirmed flows for the EDA stack include:

CrowdStrike, Microsoft Graph / Outlook / Teams / Defender for Endpoint, Okta, Armis, Entro Security, ThreatConnect, ServiceNow, PagerDuty, Proofpoint TAP / Protection Server / Threat Response, Splunk Enterprise, Splunk SOAR, Elastic, Databricks, Snowflake, Cortex XDR (for transition data), Cribl, Recorded Future, Sentry, Datadog, Cloudflare, Hashicorp Terraform, GitHub, Slack, Jamf, Microsoft OneDrive, Wiz, Tenable, plus Anthropic Claude as a native flow.

Anything with an HTTP API can use the generic HTTP Request credential type when no Connect Flow exists.

## Formulas

Tines has 200+ built-in formula functions for data transformation. Categories:
- **Type & validation**: `IS_BLANK`, `IS_EMAIL`, `IS_IP_ADDRESS`, `IS_JSON`, `IS_PRESENT`, `IS_URL`, `TYPE`
- **Strings**: `CONCAT`, `DOWNCASE`, `UPCASE`, `STRIP`, `SPLIT`, `JOIN`, `REPLACE`, `REGEX_EXTRACT`, `REGEX_REPLACE`, `STARTS_WITH`, `ENDS_WITH`
- **Arrays**: `MAP`, `FILTER`, `WHERE`, `REJECT`, `REDUCE`, `GROUP_BY`, `UNIQ`, `SORT`, `SLICE`, `CHUNK_ARRAY`, `FLATTEN`, `LAMBDA`, `MAP_LAMBDA`
- **Objects**: `KEYS`, `VALUES`, `MERGE`, `DEEP_MERGE`, `GET`, `SET_KEY`, `REMOVE_KEY`
- **JSON / data**: `JSON_PARSE`, `TO_JSON`, `JSONPATH`, `XML_PARSE`, `YAML_PARSE`, `CSV_PARSE`, `EML_PARSE`, `MSG_PARSE`
- **Crypto / hashing**: `SHA256`, `MD5`, `HMAC_SHA256`, `JWT_SIGN`, `JWT_DECODE`, `AES_ENCRYPT`, `RSA_SIGN`, `BASE64_ENCODE`, `TINES_ENCRYPT`
- **Time**: `NOW`, `TODAY`, `DATE`, `DATE_PARSE`, `DATE_DIFF`, `UNIX_TIMESTAMP`
- **Math**: `PLUS`, `MINUS`, `TIMES`, `DIVIDED_BY`, `SUM`, `AVERAGE`, `MAX`, `MIN`, `ROUND`, `CEIL`, `FLOOR`
- **Network**: `IS_IPV4`, `IS_IPV6`, `IN_CIDR`, `PARSE_URL`
- **Control flow**: `IF`, `IF_ERROR`, `SWITCH`, `AND`, `OR`, `NOT`, `DEFAULT`
- **AI-aware**: `PROMPT`, `ESTIMATED_TOKEN_COUNT`

Reference data using double angle brackets (action_name.field syntax). Reference Resources with RESOURCE.name. Reference Story metadata with STORY.name or META.tenant.domain.

## AI Capabilities

Three distinct AI features:

1. **AI Agent action** — Goal-directed action that can invoke tools (other actions or templates), run iteratively, and produce structured output. Use for triage decisions, data summarization, content generation, and any task where the agent needs to choose actions based on input.
2. **Story copilot** — Helps humans build Stories from natural language descriptions. Generates action graphs from prompts. (Note: Story copilot was brought into the AI credit framework in April 2026 — affects how its usage is billed.)
3. **`PROMPT` formula function** — Single-shot LLM call inside a formula expression for inline transformations.

All three consume from the **AI credit pool** rather than charging separately per action. Tenants get a monthly AI credit allocation; overages are negotiated.

## Self-Hosted Deployment

Tines self-hosted runs as containers. Three supported deployment paths:

| Path | When to Use |
|---|---|
| **Docker Compose** | Small or evaluation deployments |
| **AWS Fargate** | Production on AWS without K8s |
| **Helm Charts (Kubernetes)** | Production on any K8s, including AKS for Azure |

Reference Architecture covers System Overview, Connectivity Requirements, Sizing & Scaling (with deployment tiers), and Scaling guidance. Images are pulled from a private Docker registry (vendor-provided credentials) with image verification supported.

For Azure, the path is **AKS + Helm Charts**. Tines does not document Azure-specific patterns directly in their public docs — sizing and connectivity translate from the AWS Fargate guide.

## Admin & Security Features

- **Authentication**: Email-based login, SSO (SAML / OIDC), JIT provisioning, SCIM, login recovery codes, login notice
- **User administration**: Built-in roles plus Custom Roles for fine-grained access
- **Audit logs**: Tenant-wide change tracking
- **IP access control**: Restrict tenant access by source IP
- **Action egress control**: Restrict where outbound HTTP actions can connect (allowlist/denylist)
- **Custom certificate authority**: Trust internal CAs for HTTPS connections
- **Custom domains**: Vanity domains for Pages and the tenant
- **Tunnel**: Outbound-only connector for reaching internal systems (deployable on AWS Fargate or Docker Compose)
- **Command-over-HTTP**: Alternative to Tunnel for command execution; uses HTTP polling
- **Job management**: View and manage running and queued jobs
- **Impersonation**: Admins can act as other users for support/debugging
- **Story syncing**: Sync stories between tenants (e.g., dev → prod)
- **Terraform provider**: Manage tenant resources as code
- **Tenant-wide credentials**: Credentials available across all teams in the tenant

## API

REST API at the `/api/v1/` path of any tenant domain. Auth via Bearer token (API key created in user settings). Resources include stories, actions, events, credentials, resources, teams, users, audit logs.

- Pagination: 20/page default, configurable via `?page=N&per_page=M`
- Bulk operations: list, get, create, update, delete on most resources
- Workflows as APIs: any Story with a Webhook entry can be invoked as a synchronous or async API endpoint

## MCP Server Templates

Tines actions can expose themselves as MCP (Model Context Protocol) endpoints, allowing external LLMs to invoke them as tools. This is configured via the **MCP server** template type under Action Templates. Use case: expose a Tines workflow as a callable tool for an external Claude or other agent to invoke.

## Pricing & Credit Model

- **Community Edition**: 50 credits/month (free tier for individuals/learners, SaaS only)
- **Paid Editions**: 5,000 credits/month base allocation
- Credits are consumed per Action execution; some actions cost more (AI Agent, certain integrations)
- AI Agent and Story copilot consume from a separate **AI credit pool** as of 2026
- Annual commit pricing is standard for enterprise; consumption-based models exist
- Self-hosted licensing is separate from SaaS — tier and entitlements differ

*Verify all pricing details directly with Tines sales — pricing model evolves.*

## General Guidelines for Working with Tines

1. **Default to HTTP Request actions** for any external API call. Tines is fundamentally an HTTP orchestration tool — most "integrations" are just HTTP requests with credentials.
2. **Use Connect Flows for OAuth-heavy vendors** — they handle the token refresh dance automatically. Fall back to HTTP credential type only when no Connect Flow exists.
3. **Use Resources for shared config and lookup data** — never hard-code values into Action options.
4. **Filter early** with Condition actions before expensive HTTP Request or AI Agent actions to avoid wasted credit consumption.
5. **Use Event Transform Explode mode** to fan out arrays into individual events — Tines processes one event at a time per action, so loops are explicit.
6. **Use Send to Story** for reusable workflows — anything called from 2+ places should be a sub-Story.
7. **Enable Change Control** for any Story going to production. Test Resources let you validate drafts without touching live data.
8. **Use Test events** during build — every action has a Test mode that runs against the most recent received event.
9. **Reference data with action_name.field syntax** — Tines uses Liquid-style templating with double angle brackets, not curly braces or dollar-sign syntax.
10. **For long-running waits, use Delay mode** in Event Transform rather than blocking inside an Action.
11. **For human-in-the-loop, use Pages or Workbench** — don't try to hold execution in an Action waiting for human input.
12. **Tag Stories and Actions** with consistent tag taxonomy for filtering, reporting, and access control.
13. **Track Time Saved** — Tines has built-in Time Saved fields on Actions and Stories. Configure these from day one to support ROI reporting.
14. **For self-hosted production**, choose Helm/K8s over Docker Compose. Compose is fine for eval/dev only.
15. **Plan credit consumption** — model expected actions per Story per day, multiply by Story count, project monthly credit burn before committing to a tier.

## Glossary

| Term | Definition |
|---|---|
| **Action** | Atomic execution unit in a Story; one of 8 types |
| **Action Egress Control** | Tenant-level allowlist/denylist for outbound HTTP destinations |
| **AI Agent** | Goal-directed AI action that can invoke tools and iterate |
| **AI Credit Pool** | Separate credit pool for AI features (AI Agent, Story copilot) |
| **Case** | Case management primitive for incident-style work |
| **Change Control** | Draft → review → publish flow for Stories |
| **Command-over-HTTP** | Alternative to Tunnel for outbound-only Tines→internal connectivity |
| **Connect Flow** | Pre-built credential setup wizard for a specific vendor |
| **Credit** | Unit of execution consumption; Actions cost 1+ credits each |
| **Event** | JSON payload that flows between Actions inside a Story |
| **Group** | Visual container for organizing related Actions on the Storyboard |
| **LIVE / DRAFT** | The two Story modes |
| **MCP server template** | Action template that exposes a Tines workflow as an MCP tool |
| **Page** | In-platform frontend/form built into a Storyboard |
| **Prompt** | Inline LLM call via the `PROMPT` formula function |
| **Record** | Lightweight structured datastore for state and lookup data |
| **Resource** | Team-scoped data store (text, JSON, file) for shared config and data |
| **Send to Story** | Action type for invoking sub-Stories |
| **Story** | A workflow built as a graph of Actions |
| **Storyboard** | The visual canvas where Stories are built |
| **Story Copilot** | AI feature that builds Stories from natural language |
| **Tenant** | Isolated Tines instance for one organization |
| **Tool** (drag-on) | Group, Page, Note, or Record dragged onto the Storyboard |
| **Tunnel** | Outbound-only connector deployed on customer infra |
| **Workbench** | Analyst-facing interface for human-in-the-loop interaction (also in Slack) |
| **Workflows as APIs** | Pattern of exposing a Story as an HTTP API via Webhook entry |

## Key Documentation Links

- Official Docs: https://www.tines.com/docs/quickstart/
- API Docs: https://www.tines.com/api/welcome/
- Tines Dictionary (concept glossary): https://explained.tines.com/en/articles/8095554-the-tines-dictionary
- Library (pre-built workflows): https://www.tines.com/library/
- Self-Hosted Docs: https://www.tines.com/docs/self-hosted/
- Connect Flows index: https://www.tines.com/docs/credentials/connect-flows/
- Formula functions: https://www.tines.com/docs/formulas/functions/
- University (training): https://www.tines.com/university/
- Customer Center: https://www.tines.com/customer-center/
- Slack Community: https://hq.tines.io/forms/6f8b122ccba3cb7e8e0d3531d1b70eb2
