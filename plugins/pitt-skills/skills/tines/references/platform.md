# Tines Platform Reference

Deep technical reference for the Tines automation platform. Companion to `tines-SKILL.md`.

---

## 0. Platform Architecture Model

Tines describes its platform as five conceptual layers. Useful framing when explaining the architecture to non-Tines audiences (security architecture review, leadership briefings, M&A integration discussions).

```
┌─────────────────────────────────────────────────────┐
│  Human Interaction Layer                            │
│  (Pages, Workbench, Cases, Slack/Teams integration) │
├─────────────────────────────────────────────────────┤
│  Automation Layer                                   │
│  (Stories, Actions including AI Agent — both        │
│   deterministic and agentic automation live here)   │
├─────────────────────────────────────────────────────┤
│  Control Layer                                      │
│  (Credentials, audit, change control,               │
│   IP/egress controls, RBAC, governance)             │
├─────────────────────────────────────────────────────┤
│  Company Systems & Data                             │
│  (Your CrowdStrike, Entra, ServiceNow, etc.)        │
└─────────────────────────────────────────────────────┘
```

**Why the model matters:** Tines made a deliberate product decision that AI Agents live at the *automation layer* alongside deterministic automation, not as a separate product. This means everything in the control layer (auditability, credential management, change control) applies to AI Agent workflows automatically — not bolted on as an afterthought.

**Operational scale claim** (per Tines product team, public statement): the platform runs approximately 1.5 billion automations per week. Useful credibility datapoint when discussing platform maturity in leadership briefings.

---

## 1. Tenancy and Org Model

A **tenant** is an isolated Tines instance. SaaS tenants live at `<adjective-noun-1234>.tines.com` or `.tines.io`. Self-hosted tenants run on customer infrastructure with a customer-chosen domain.

Inside a tenant:
- **Teams** scope ownership of Stories, Actions, Credentials, Resources, Cases, Records, and Pages
- **Users** belong to one or more teams with role-based permissions per team
- **Roles**: built-in roles (Viewer, Editor, Team Admin) plus Custom Roles for fine-grained control
- **Tenant-wide credentials** are visible across all teams (use sparingly — most credentials should be team-scoped)

Cross-team sharing is opt-in: Resources and Stories can be shared with `All teams` or specific teams. When two teams have a Resource with the same name, the local team's Resource wins.

---

## 2. Stories

A **Story** is a directed graph of Actions. Stories have:
- A **mode**: `LIVE` or `DRAFT`
- An **entry point** (typically a Webhook or scheduled action)
- Zero or more **exit points** (used for Workflows-as-APIs and Send to Story responses)
- **Story options**: event retention period (default 7 days), priority flag, change control toggle, Send to Story enablement, monitoring config, recipients for failure notifications, tags, folder

### Story Modes
- **LIVE**: Production. Actions run against live data, real credentials, real APIs.
- **DRAFT**: Testing. When Change Control is enabled, all changes happen in a draft and use Test Resource values.

### Story Versioning
Every save creates a version. Access via the clock icon in Storyboard. You can:
- View a previous version
- Restore a previous version (overwrites current with chosen version)
- Clone a version into a new Story
- Export a version as JSON
- Compare versions

### Importing / Exporting
Stories export as JSON. Use for:
- Cross-tenant migration (dev → prod)
- Source-controlling Stories alongside other config
- Sharing with vendors or community

### Change Control
When enabled on a Story:
- Edits go into a draft, not LIVE
- Test events and Test Resource values isolate testing from production
- Promotion happens via "Publish" with optional reviewer approval
- Audit trail tracks who promoted what
- Story syncing with Terraform is the production-grade alternative for IaC workflows

### Send to Story (Sub-Stories)
- Receiving Story: enable `send_to_story_enabled`, set access (`OFF`, `TEAM`, `ALL_TEAMS`), define expected payload schema
- Calling Story: use `Send to Story` action, reference the sub-Story by name (`<<STORY.story_name>>`) or numeric ID
- **Loop processing**: pass `loop: <field name>` to invoke the sub-Story once per array element; results aggregate into a single output event
- Loop is **serial** (preserves array order) — for parallelism, design a different pattern
- Sub-Stories with confirmation enabled (`send_to_story_skill_use_requires_confirmation`) require approval for AI agent invocation

### Workflows as APIs
Pattern: Story has a Webhook entry action and one or more Exit actions.
- Calling `POST https://<tenant>/webhook/<path>/<secret>` invokes the Story
- The first Exit action's payload is returned in the HTTP response body within 30 seconds
- For more control: Exit action payload with `status` and `body` keys becomes the HTTP response (`status` = HTTP code, `body` = response body)
- Custom headers via `headers` key in exit payload (Content-Type, Content-Disposition for downloads)
- If exit doesn't fire within 30s: returns `504 Gateway Timeout` with `response_url` header pointing to where the response will be available when ready
- Limits: concurrent request caps; exceeded = `201 Created` and the Story continues in background

### Story Run
A single execution of a Story is a **Story run**, identified by a GUID. Reference inside formulas with `STORY_RUN_GUID()`. Useful for cross-action correlation, logging, and debugging.

---

## 3. Action Types — Detail

### 3.1 Webhook
Entry-point action that exposes an HTTPS endpoint.
- URL pattern: `https://<tenant>/webhook/<path>/<secret>`
- Secret is autogenerated and rotatable
- Accepts any HTTP method (GET, POST, PUT, etc.) and any payload
- Configurable: HMAC verification, IP allowlist (per webhook), event payload extraction
- Best practice: always verify HMAC or shared-secret on inbound webhooks from third parties

### 3.2 Receive Email
Two modes:
- **Email mode**: Tines exposes a unique inbound email address; mail sent to that address becomes events
- **IMAP mode**: Tines polls an existing mailbox and ingests new mail
- Event payload includes parsed headers, body (text + HTML), attachments

### 3.3 Send Email
Outbound email action.
- Configure From, To, CC, BCC, Subject, Body (text or HTML), attachments
- Tines provides a default sending domain; custom sender domains require admin config
- Reply-tracking via inbound webhook on a dedicated address

### 3.4 HTTP Request
The workhorse — most "integrations" are HTTP Request actions.
- Method, URL, headers, payload (JSON, form, multipart, raw)
- Credential reference for auth (most common pattern)
- Retry on failure (configurable count and backoff)
- Follow redirects toggle
- Timeout (default 30s)
- Response handling: emits an event with `status_code`, `headers`, `body` (auto-parsed if JSON)
- Disable monitoring for high-volume polling actions to avoid log bloat

### 3.5 Condition
Branch logic action.
- Evaluates one or more conditions against incoming event data
- Supported comparisons: equals, not equals, contains, regex, exists, is true/false, IP/CIDR membership, etc.
- Multiple conditions combined with AND/OR
- One Condition action = one branch decision; chain conditions for nested logic

### 3.6 Event Transform — All 8 Modes

| Mode | Purpose | Example Use |
|---|---|---|
| **Deduplicate** | Drop events whose path value was seen recently | Suppress duplicate phishing alerts within 24h |
| **Delay** | Wait N seconds before re-emitting | Wait 30s after disabling an account before verification |
| **Explode** | Emit one event per array element | Process 50 IOCs from one feed event individually |
| **Extract** | Pull out specific fields with formulas; reshape event | Normalize alert payloads into a common schema |
| **Implode** | Aggregate N events / events over T seconds into one | Batch 100 indicators for bulk API push |
| **Message only** | Emit a static or templated message | Build a notification payload from upstream data |
| **Throttle** | Rate-limit event emission to respect 3rd-party rate limits | Cap API calls at 10/sec |
| **Automatic** | Tines picks based on context | Default; rarely useful in production designs |

#### Deduplicate config
- `path`: pill expression for the value to deduplicate on (e.g., `<<alert.body.id>>`)
- `lookback`: window in days

#### Explode config
- `path`: array field
- Each emitted event has a `LOOP` object with iteration metadata
- Looping inside a Send to Story has its own size limits — for very large arrays, Explode first, then Send to Story per event

#### Implode config
- Trigger condition: `count >= N` or `time_elapsed >= T`
- Output payload: array of incoming events under a configurable key

### 3.7 Send to Story
See section 2 (Stories) above.

### 3.8 AI Agent
Goal-directed AI action.
- Configure: goal/prompt, available tools (other Actions or Templates the agent can invoke), output schema
- Iterates: agent decides which tool to call, observes the result, decides next action, until goal is met or max iterations reached
- Audit: full reasoning trace stored in event log
- Sandboxing: tools are limited to those explicitly granted to the agent
- Cost: consumes from AI credit pool (verify current model and pricing with Tines)

---

## 4. Tools (Drag-on)

### Group
Visual container. Collapsible. Useful for organizing complex Stories with many actions. Doesn't affect execution.

### Page
Built-in frontend (see Section 6).

### Note
Inline documentation on the Storyboard. Markdown-supported. No execution semantics.

### Record
Captures structured data into a Records dataset (see Section 8).

### Run Script
Executes Python or JavaScript inline. Use when formulas can't express the logic, or when 3rd-party libraries are needed.
- Custom runtimes: declare a runtime image with specific package versions
- **Run Script over Tunnel**: execute scripts on a self-hosted Tunnel host instead of Tines infrastructure (useful for private network access or licensed software dependencies)

---

## 5. Resources

Team-scoped centralized data store.

| Type | Use Case |
|---|---|
| **Plaintext** | Single string values: API base URLs, env identifiers, allowlist comma-separated |
| **JSON** | Structured config: maps, arrays, lookup tables |
| **File** | Static assets up to 5MB: schemas, certificates, templates |

Reference in formulas:
- `<<RESOURCE.allowed_domains>>`
- `<<RESOURCE.config.api_base_url>>` (for nested JSON)

Lockable to prevent edits. Test Resources allow draft testing without touching live values.

Sharing scopes:
- Default: team-only
- All teams (including personal teams)
- Specific teams (one or more)

When two shared Resources have the same name, the team-local Resource takes precedence.

---

## 6. Pages

Frontends built into the Storyboard. Built from Page Elements.

### Common Page Elements
- Text, Heading, Image, Divider
- Form fields: text input, textarea, select, multi-select, checkbox, radio, date, file upload
- Buttons (submit, link, action trigger)
- Conditional elements (show/hide based on state)
- Looping elements (render array as repeating element)
- Containers and Layout elements for structure

### Page Distribution
- Internal-only (Tines users)
- Anonymous link (public URL with token)
- Embedded
- Custom domain

### Page Templates
Pre-built starter templates for common patterns (form, dashboard, approval flow, etc.)

### Collections
Group related Pages into a single navigable mini-app with shared navigation.

### Common patterns
- Submission form → Webhook → Story execution → display result on next Page
- Approval flow → Page with Approve/Reject buttons → trigger downstream Story
- Dashboard → Page reading from Records to show live state

---

## 7. Cases

Case management primitive.

### Case Components
- Title and description (rich text, multiplayer collaboration)
- Status (configurable workflow)
- Severity (configurable)
- Assignee
- Custom case fields (including sensitive fields with restricted access)
- Comments and updates
- Tasks (subtasks with their own assignment/status)
- Linked actions/events (creating Story context)
- Attachments

### Case Groups
Group related cases for batch view, bulk update, parent-child relationships.

### Case Notifications
Configurable notification rules: notify assignee on new comment, notify team on status change, etc.

### Sensitive Case Fields
Fields can be marked sensitive — content is encrypted and access-restricted to specific users/roles. Use for: PII, credentials, customer data.

### Case Limits
Per-tenant limits on cases, fields, etc. (verify current limits in docs).

Use Cases when: human-in-the-loop investigation, structured incident workflow, cross-team handoffs.

---

## 8. Records

Lightweight structured datastore. Use when Stories need to persist or query structured state across runs.

- **Datasets**: schema-defined collections of records
- Records have fields with types (string, number, boolean, date, JSON)
- **Live and test records** for production vs. draft separation
- Limits on records per dataset, datasets per team, fields per dataset

Common patterns:
- Tracking accumulated state (e.g., users who've been notified, IOCs already deployed)
- Lookup tables that need to be queried by Story
- Output sink for Stories to write to, then read back later or display in Pages/Dashboards

---

## 9. Dashboards

Built-in dashboard feature for visualizing data from Records, Stories, and other tenant state. Limited to Tines-native data (not a general BI tool).

---

## 10. Workbench

Analyst-facing interface that surfaces:
- Pending human actions from Stories
- Open cases
- Record data needing review
- Custom views

**Workbench in Slack** brings the same interface into Slack channels — analysts can claim, action, and complete work without leaving Slack. Useful for SOC teams that live in Slack.

---

## 11. Credentials

### Credential Types
| Type | Use When |
|---|---|
| **Text** | Static API keys, tokens, secrets passed in headers or body |
| **AWS** | AWS API auth (access keys, IRSA, STS role assumption) |
| **HTTP request** | Auth requires fetching a token first (e.g., username+password → bearer token) |
| **Mutual TLS** | Client certificate-based auth |
| **JWT** | Generate signed JWTs for auth (with claims and signing key) |
| **OAuth 2.0** | Standard OAuth with refresh; Tines handles refresh transparently |
| **Multi Request** | Chain multiple auth requests when one isn't enough |

### Credential Configuration
- **Domain restriction**: limit which URLs the credential can be used against (security control)
- **Credential metadata**: arbitrary key-value labels (vendor, environment, owner)
- **Product**: associate credential with a product for organizational visibility
- **Access**: restrict to specific teams or users
- **Expiry**: set expiration date with notification
- **Test credential tab**: validate credential by making a sample request
- **Actions tab**: see which actions reference this credential

### Connect Flows
Pre-built credential setup wizards. Each handles vendor-specific OAuth, API key, or auth quirks. ~200+ available. The flow walks the user through:
1. Vendor selection
2. Auth type (OAuth, API key, etc.)
3. Vendor-specific config (region, instance URL, API version)
4. Validation

If a vendor isn't in Connect Flows but has an API, use HTTP Request credential type with the vendor's documented auth scheme.

---

## 12. Formulas

Tines uses pill expressions wrapped in double angle brackets `<<...>>` (similar in look to but distinct from Liquid templating). The full cheatsheet — including 95%-of-real-use functions, worked examples, and common gotchas — lives in [formulas.md](formulas.md). Quick orientation only here.

### Referencing Data
- Upstream action: `<<action_name.body.field>>` or `<<action_name.body.field.subfield>>`
- Resource: `<<RESOURCE.name>>` or `<<RESOURCE.name.nested_key>>`
- Story metadata: `<<STORY.name>>`, `<<STORY.team_id>>`
- Tenant metadata: `<<META.tenant.domain>>`
- Story run: `<<STORY_RUN_GUID()>>`

### Common Patterns

```
# Conditional value
<<IF(alert.severity == "high", "P1", "P2")>>

# Default fallback
<<DEFAULT(alert.user_email, "unknown@example.com")>>

# Array filtering
<<FILTER(events, LAMBDA(e, e.severity == "critical"))>>

# Array mapping
<<MAP(indicators, LAMBDA(i, i.value))>>

# JSON path
<<JSONPATH(payload, "$.alerts[*].id")>>

# Hash for dedup
<<SHA256(CONCAT(user, host, date))>>

# Token estimation before AI call
<<ESTIMATED_TOKEN_COUNT(prompt_text)>>
```

### Operators
Standard arithmetic (`+`, `-`, `*`, `/`), comparison (`==`, `!=`, `<`, `>`), logical (`&&`, `||`, `!`), string concatenation, array/object access (`.`, `[]`).

### Prompts
The `PROMPT` formula function makes a single-shot LLM call inline. Use for: extraction, classification, simple summarization. Don't use for multi-turn or tool-use — use AI Agent action for that.

```
<<PROMPT("Classify this alert as phishing, malware, or benign", alert.subject)>>
```

For the full function catalog (string, array, date, parsing, conditional, lambdas, crypto, object construction), pill-vs-formula-field stringification rules, slug normalization behavior, and the catalog of formula gotchas (no `FORMAT_DATE`, `SWITCH` requires default, lazy evaluation, etc.) see [formulas.md](formulas.md).

---

## 13. Story Design Patterns

### Pattern: Alert Triage
1. Webhook (entry) — receive alert from SIEM
2. Event Transform Extract — normalize fields
3. HTTP Request — enrich with threat intel
4. Condition — branch on severity
5. Send to Story — handoff to severity-specific sub-Story
6. Send Email or HTTP Request — notify or remediate

### Pattern: IOC Deployment
1. Webhook or scheduled trigger — new IOC arrives
2. Condition — verify score and type
3. Event Transform Explode — fan out per IOC
4. Send to Story — per-control-plane deployment sub-Story (CrowdStrike, Akamai, etc.)
5. Implode — collect deployment results
6. HTTP Request — write status back to TI platform

### Pattern: Human Approval
1. Webhook — request comes in
2. Page — show details, capture decision
3. Condition — branch on approval
4. HTTP Request — execute approved action
5. Send Email — notify requester

### Pattern: Scheduled Job
1. Schedule trigger (Webhook with cron) — periodic run
2. HTTP Request — pull data from system
3. Event Transform — process
4. Record (tool) — persist results
5. Send Email — daily summary

### Pattern: Bulk Processing with Throttle
1. Webhook — receive bulk job
2. Event Transform Explode — fan out
3. Event Transform Throttle — rate-limit to API tier
4. HTTP Request — process each
5. Event Transform Implode — collect results
6. HTTP Request or Record — finalize

### Pattern: Self-Healing Detection
1. Schedule — periodic health check
2. HTTP Request — query monitored system
3. Condition — degraded?
4. Run Script or HTTP Request — remediation action
5. Send to Story (if needed) — escalation if remediation fails
6. Send Email — notify owners

### Anti-Patterns
- **Holding state in Action options** — use Resources or Records instead
- **Nested Conditions instead of Switch logic** — use formula `SWITCH()` for cleaner branching
- **Synchronous waits** — use Event Transform Delay mode, never block in Action
- **Hardcoded credentials** — always use Credential references
- **Untested production deploys** — always use Change Control + Test Resources

---

## 14. Self-Hosted Deployment

### Prerequisites (all paths)
- Container runtime (Docker, K8s, or Fargate)
- Postgres database (managed or self-hosted)
- Redis (for job queue)
- Object storage (for files, logs)
- Outbound internet for image pulls and updates (or air-gapped registry mirror)
- Domain and TLS certificate

### Path 1: Docker Compose
- Single-host deployment
- Suitable for: evaluation, small teams, dev/test
- Pros: simplest setup, fast spin-up
- Cons: no HA, manual scaling, single-host failure domain

### Path 2: AWS Fargate
- Container-based on AWS without K8s
- Suitable for: AWS-centric orgs that want managed compute
- Pros: managed compute, integrated with AWS networking
- Cons: AWS-only, somewhat opinionated networking

### Path 3: Helm Charts (Kubernetes)
- For any K8s cluster: AKS, EKS, GKE, on-prem
- Suitable for: production deployments with HA, autoscaling, and IaC requirements
- Pros: portable, scales horizontally, integrates with existing K8s tooling
- Cons: requires K8s expertise, more moving parts

For Azure deployment, the path is **AKS + Helm Charts**. Tines does not publish Azure-specific guides — sizing, networking, and observability translate from the AWS Fargate Reference Architecture with AKS substitutions. (Populate `tines-self-hosted-azure.md` with specifics as the POC informs them.)

### Sizing & Scaling
Tines publishes deployment tiers (small / medium / large / enterprise) with recommended CPU, memory, DB sizing, and Redis sizing. Scaling is horizontal — add more application replicas to handle more concurrent Stories.

### Tunnel
Outbound-only connector for reaching internal systems from a Tines tenant.
- Deployed on customer infrastructure (AWS Fargate or Docker Compose)
- Establishes outbound TLS connection to Tines tenant
- Tines actions can be configured to route through Tunnel
- Use for: hitting on-prem APIs, services without public endpoints, services that need source-IP allowlisting
- Health checks and metrics endpoints available

### Command-over-HTTP
Alternative to Tunnel for outbound-only connectivity. Uses HTTP polling instead of persistent connection. Lower throughput but simpler firewall posture.

### Image Verification
Tines publishes image signatures. Production deployments should verify images before deploy as part of supply chain security.

### Offline Documentation
For air-gapped deployments, Tines provides offline-bundled docs.

---

## 15. Terraform Provider

Tines has an official Terraform provider. Manageable resources include:
- Stories (create, update, version)
- Actions
- Credentials (with sensitive value handling)
- Resources
- Teams, users, roles
- Webhooks and credentials

Use Terraform when:
- Story-as-code is required
- Multi-tenant management (dev → staging → prod)
- Compliance requires reviewable change history
- Story Syncing is too coupled and you want full Git workflow

---

## 16. API

The full REST API reference, including authentication, pagination, all endpoints (with the corrected paths for credentials at `/api/v1/user_credentials` and resources at `/api/v1/global_resources`), action wiring quirks, action-logs endpoint for debugging, response codes, rate limits, Workflows-as-APIs pattern, Send-to-Story payload format, Terraform provider, and action type IDs, lives in [api.md](api.md).

---

## 17. MCP Server Templates

Tines actions can be exposed as **MCP (Model Context Protocol) servers** via Action Templates. This means a Tines Story can act as a callable tool for an external Claude, GPT, or other LLM agent.

Use cases:
- Expose a Tines workflow (e.g., "enrich indicator", "check user status") as a tool that an external Claude session can invoke
- Build an internal AI assistant that orchestrates Tines workflows on demand
- Give engineers natural-language access to common Tines workflows from their AI tools

Configuration: under Action Templates → MCP server. Define the tool name, description, input schema, and which Story executes when invoked.

### Structural specifics that public docs underspecify

- **MCP Server is not a distinct action type.** It is `Agents::WebhookAgent` with `options.mode = "mcp"`. POSTing `type: "Agents::McpServerAgent"` fails. The action is added from the UI Templates panel, not the main action picker — on Community Edition the Templates panel may be hidden entirely.
- **Tools attached to an MCP Server are nested `Agents::GroupAgent` subroutines** containing `GroupInputAgent` (input schema) and `GroupOutputAgent` (return payload). The `tools` array on the MCP Server action is visible only in story exports — `GET /api/v1/actions/{id}` does not return it. Building a multi-tool MCP server fully via API is impractical without reverse-engineering the nested shape from an export.
- **`tools/call` has a hard 30-second execution ceiling.** Anything slower returns `{"isError": true, "content": [{"type": "text", "text": "Tool execution timeout"}]}` to the caller; the underlying Tines chain still runs and emits events normally. Send-to-Story-as-tool adds invocation overhead on top of the target story's duration. Design tool chains to complete well under 30s, or redesign as async trigger+poll.
- **Send-to-Story-as-MCP-tool auto-derives an empty input schema.** Tines uses the target story's name (snake_cased) for `tool.name`, copies the target story's name to `description` (your custom description is ignored), and leaves `inputSchema.properties` empty. Calling the tool with named arguments doesn't route them to the target story's webhook body — configure input-schema fields and argument mapping explicitly in the tool's UI config.

See [gotchas.md](gotchas.md#2-mcp-server-is-not-a-distinct-action-type) for the full backstory.

---

## 18. Pricing & Credit Model

### Editions
- **Community**: Free tier, SaaS-only, 50 credits/month, single user
- **Paid Editions**: 5,000 credits/month base, multi-user, paid features
- **Self-Hosted**: Separate licensing model from SaaS — verify with sales

### Credit Consumption
- Most Action executions cost 1 credit
- Some Actions cost more (AI Agent, certain integrations) — verify per-action cost in product
- Test events and draft executions may not consume credits (verify)
- Failed Actions still typically consume credits

### AI Credit Pool
Separate from regular credits as of 2026:
- AI Agent action execution
- Story copilot generations
- `PROMPT` formula function calls (verify)

### Commercial Models
- Annual commit (most enterprise)
- Consumption-based (overage charges)
- Self-hosted licensing (typically annual, may include support tiers)

### Licensing: Tenant Users vs End Users
Tines does not typically charge per-seat for most customers. Important distinction:
- **Tenant users** are people who log into Tines directly (your automation team, principal engineers, builders). These are sometimes counted in commercial agreements.
- **End users** are everyone consuming Tines workflows externally — Slack/Teams users interacting with bots, anonymous users hitting Pages, employees using Workbench. These typically do *not* consume seats.

This matters operationally because: distributing chat agents to your full organization, building customer-facing Pages, or routing Slack/Teams interactions through Tines does not multiply per-seat costs. Verify your specific agreement during contract negotiation.

**Verify all pricing details directly with Tines sales — model evolves.**

---

## 19. Admin Features (Detailed)

### Authentication
- Email-based login (default)
- SAML SSO with major IdPs
- OIDC SSO
- JIT user provisioning on SSO login
- SCIM for user lifecycle (provision/deprovision)
- Login recovery codes for emergency access
- Login notice (banner shown to all users)

### IP Access Control
Tenant-level IP allowlist. Restricts who can access the Tines UI/API. Useful for:
- Restricting tenant access to corporate network ranges
- Compliance requirements (e.g., access only from VPN)

### Action Egress Control
Tenant-level outbound restrictions. Limits which destinations HTTP Request actions can reach.
- Allowlist mode: only listed destinations allowed
- Denylist mode: listed destinations blocked
- Useful for preventing data exfiltration via misconfigured actions

### Custom Certificate Authority
Trust custom CAs for HTTPS connections. Required when actions need to call internal services using internal CA-signed certs.

### Custom Sender Email Addresses
Configure custom sending domains for Send Email actions. Requires DNS verification (SPF, DKIM).

### Custom Domains
Vanity domains for the tenant URL and Pages.

### Audit Logs
Tenant-wide change tracking. Captures: who created/edited/deleted what, login events, credential access, sensitive case field access. Exportable.

### Impersonation
Admin feature: act as another user for support/debugging. Logged in audit trail.

### Story Syncing
Sync Stories between tenants (e.g., dev → prod) without going through full export/import. Configurable mappings for tenant-specific values.

### Job Management
View and manage running and queued background jobs. Useful for debugging stuck Story runs and identifying performance issues.

### Event Limit Settings
Per-tenant configuration of event retention defaults, max events per Story, etc.

---

## 20. Frequently Used References

| Doc Page | URL |
|---|---|
| Quickstart | https://www.tines.com/docs/quickstart/ |
| Stories overview | https://www.tines.com/docs/stories/ |
| Actions overview | https://www.tines.com/docs/actions/ |
| Action types index | https://www.tines.com/docs/actions/types/ |
| HTTP Request action | https://www.tines.com/docs/actions/types/http-request/ |
| Event Transform | https://www.tines.com/docs/actions/types/event-transformation/ |
| Send to Story | https://www.tines.com/docs/actions/types/send-to-story/ |
| AI Agent action | https://www.tines.com/docs/actions/types/ai-agent/ |
| Resources | https://www.tines.com/docs/resources/ |
| Cases | https://www.tines.com/docs/cases/ |
| Records | https://www.tines.com/docs/records/ |
| Pages | https://www.tines.com/docs/pages/ |
| Credentials | https://www.tines.com/docs/credentials/ |
| Connect Flows | https://www.tines.com/docs/credentials/connect-flows/ |
| Formulas | https://www.tines.com/docs/formulas/ |
| Formula functions | https://www.tines.com/docs/formulas/functions/ |
| Workflows as APIs | https://www.tines.com/docs/stories/apis/ |
| Change Control | https://www.tines.com/docs/stories/change-control/ |
| Story Versioning | https://www.tines.com/docs/stories/story-versioning/ |
| Self-Hosted index | https://www.tines.com/docs/self-hosted/ |
| Reference Architecture | https://www.tines.com/docs/self-hosted/reference-architecture/ |
| Tunnel | https://www.tines.com/docs/admin/tunnel/ |
| Command-over-HTTP | https://www.tines.com/docs/admin/command-over-http/ |
| Terraform | https://www.tines.com/docs/admin/terraform/ |
| API Welcome | https://www.tines.com/api/welcome/ |
| MCP server template | https://www.tines.com/docs/actions/templates/mcp-server/ |
