# Tines API Reference

REST API for programmatic management of Tines tenants. Use for: automating Story deployment, exporting audit logs, integrating with CI/CD, IaC management, and programmatic data access.

The Tines API is distinct from **Workflows-as-APIs** — that's how you expose your own Stories as endpoints. Both are covered here.

---

## 1. Base URL

```
https://<tenant-domain>/api/v1/<endpoint>
```

`<tenant-domain>` is the domain visible in the browser when you're logged in. For SaaS, typically `<adjective-noun-1234>.tines.com` or `.tines.io`. For self-hosted, the customer-chosen domain.

In Tines formula expressions, you can reference the tenant domain as `<<META.tenant.domain>>`.

---

## 2. Authentication

Bearer token in the `Authorization` header:

```
Authorization: Bearer <api_key>
```

### API Keys
- Created in user settings
- Scoped to a specific user — they inherit that user's permissions
- For automation, **create a service-account user** and use its API key, rather than tying automation to a real person's account
- Rotation: standard practice; document in your secrets management workflow

### Example call
```bash
curl -X GET \
  https://<tenant>/api/v1/stories \
  -H 'Authorization: Bearer <api_key>' \
  -H 'Content-Type: application/json'
```

---

## 3. Pagination

Most list endpoints paginate.

- Default page size: **20 items**
- Configurable: `?per_page=100` (max varies by endpoint)
- Navigate: `?page=2`

Example:
```bash
curl 'https://<tenant>/api/v1/events?page=2&per_page=100' \
  -H 'Authorization: Bearer <api_key>'
```

### Response metadata
List responses include a `meta` object:
```json
{
  "agents": [...],
  "meta": {
    "current_page": "https://<tenant>/api/v1/agents?page=1&per_page=20",
    "previous_page": null,
    "next_page": "https://<tenant>/api/v1/agents?page=2&per_page=20",
    "next_page_number": 2,
    "per_page": 20,
    "pages": 13,
    "count": 242
  }
}
```

Note: Tines uses the older term "agents" in some API responses to mean "actions" — historical naming.

---

## 4. Common Endpoints

### Stories

```
GET    /api/v1/stories                       List stories
GET    /api/v1/stories/{id}                  Get a single story
GET    /api/v1/stories/{id}?include_live_activity=true
POST   /api/v1/stories                       Create a story
PUT    /api/v1/stories/{id}                  Update a story
DELETE /api/v1/stories/{id}                  Delete a story
POST   /api/v1/stories/{id}/import           Import from JSON
GET    /api/v1/stories/{id}/export           Export to JSON
GET    /api/v1/stories/{id}/versions         List versions
POST   /api/v1/stories/{id}/versions/restore Restore a version
```

Story object includes: `name`, `description`, `team_id`, `mode` (LIVE/DRAFT), `tags`, `entry_agent_id`, `exit_agents`, `change_control_enabled`, `keep_events_for`, `priority`, `send_to_story_enabled`, `send_to_story_access`, etc.

### Actions

```
GET    /api/v1/actions                       List all actions across stories
GET    /api/v1/actions?include_live_activity=true
GET    /api/v1/actions/{id}                  Get a single action
POST   /api/v1/actions                       Create an action
PUT    /api/v1/actions/{id}                  Update an action
DELETE /api/v1/actions/{id}                  Delete an action
```

Action object includes: `id`, `type` (e.g., `Agents::EventTransformationAgent`, `Agents::HTTPRequestAgent`), `name`, `options` (action-specific config), `position`, `sources` (upstream actions), `receivers` (downstream actions), `story_id`, `story_mode`, `team_id`, `monitor_failures`, `monitor_all_events`, `monitor_no_events_emitted`, `time_saved_unit`, `time_saved_value`, `disabled`, `guid`.

### Events
```
GET    /api/v1/events                        List events (paginated, large)
GET    /api/v1/events/{id}                   Get a single event
GET    /api/v1/events?action_id={id}         Returns events but does NOT actually filter — see note
GET    /api/v1/events?story_id={id}          Filter by story
DELETE /api/v1/events/{id}                   Delete an event
```

**Caveat:** the `?action_id={id}` query parameter does NOT actually restrict the response to events emitted by that action — it returns a broader pool. Filter client-side by `agent_id == <id>` on each event, or group events from one story run by the shared `story_run_guid` field. The richer signal for action-level debugging is the action-logs endpoint:

```
GET /api/v1/actions/{id}/logs?per_page=N      Action-level log messages
```

Returns `{action_logs: [...]}`. Each entry has `level` (3=info, 4=error), `created_at`, and a `message` field. The `message` on an HTTP Request log includes the exact URL and body Tines sent after pill substitution — the single most useful piece of info when diagnosing why a URL hit endpoint-not-found or an API rejected your params. For AI Agent logs, errors like "AI actions cannot run in a personal team" or "Error evaluating formula: Undefined function FORMAT_DATE" surface here. Not prominent in the public docs; see [gotchas.md](gotchas.md#17-action-logs-endpoint-is-the-single-best-debug-tool).

### Credentials
```
GET    /api/v1/user_credentials              List credentials
POST   /api/v1/user_credentials              Create
PUT    /api/v1/user_credentials/{id}         Update
DELETE /api/v1/user_credentials/{id}         Delete
GET    /api/v1/user_credentials/{id}/test    Test (validate)
```

### Resources
```
GET    /api/v1/global_resources              List resources
POST   /api/v1/global_resources              Create
PUT    /api/v1/global_resources/{id}         Update
DELETE /api/v1/global_resources/{id}         Delete
```

### Teams, Users, Roles
```
GET    /api/v1/teams
GET    /api/v1/users
GET    /api/v1/admin/users                   (admin scope)
POST   /api/v1/teams                         Create team
```

### Audit logs
```
GET    /api/v1/audit_logs                    List audit log entries
GET    /api/v1/audit_logs?from={ISO8601}&to={ISO8601}
```

Forward to SIEM via scheduled Story or external pull.

### Cases
```
GET    /api/v1/cases
POST   /api/v1/cases
PUT    /api/v1/cases/{id}
DELETE /api/v1/cases/{id}
```

### Records
```
GET    /api/v1/records
POST   /api/v1/records
PUT    /api/v1/records/{id}
DELETE /api/v1/records/{id}
```

(Verify exact endpoint names and shape with Tines API docs at runtime — paths can vary slightly between API versions.)

---

## 5. Response Codes

Standard HTTP semantics:

| Code | Meaning |
|---|---|
| 200 | OK — request succeeded |
| 201 | Created — resource created (also used by Workflows-as-APIs when limit reached, see Section 7) |
| 204 | No Content — success with no body (typical on DELETE) |
| 400 | Bad Request — malformed payload |
| 401 | Unauthorized — missing or invalid API key |
| 403 | Forbidden — auth valid but lacks permission |
| 404 | Not Found |
| 422 | Unprocessable Entity — validation error |
| 429 | Rate Limited — back off and retry |
| 500 | Server Error |
| 504 | Gateway Timeout (Workflows-as-APIs) |

---

## 6. Rate Limits

Tines applies rate limits to API calls. Specific limits vary by endpoint and tier — check headers on responses for current usage. On `429`, back off with exponential delay before retry.

For high-volume integrations, prefer:
- **Workflows-as-APIs** (Webhook entry actions) for inbound — these are designed for high throughput
- **Batched updates** rather than per-resource calls

---

## 7. Workflows as APIs (Webhook Entry Pattern)

Any Story with a Webhook entry action exposes itself as an HTTP API.

### URL Structure
```
https://<tenant>/webhook/<path>/<secret>
```

Tines auto-generates the `<path>` and `<secret>`; both are configurable on the Webhook action.

### Behavior
- Webhook accepts any HTTP method (GET, POST, PUT) and any payload
- The Story executes
- **Synchronous mode**: returns the first Exit action's payload as the HTTP response, within 30 seconds
- **Async mode**: if exit doesn't fire in 30s, returns `504 Gateway Timeout` with `response_url` header pointing to where the response will be available
- Concurrency limits: when exceeded, returns `201 Created` instead of `200 OK`, and the Story continues running asynchronously

### Custom HTTP Response
By default, the Exit action's payload becomes the response body. For control over status code and headers, structure the Exit action's payload:

```json
{
  "status": 200,
  "body": "...",
  "headers": {
    "Content-Type": "application/pdf",
    "Content-Disposition": "attachment; filename=report.pdf"
  }
}
```

If `status` is a valid HTTP code, Tines uses it as the response status. `body` becomes the response body. `headers` becomes response headers.

### Headers Returned
| Header | Meaning |
|---|---|
| `X-Tines-Status` | Status of the request: `data_received` (executed and data returned), `ok` (executing but didn't return data in time), `limit_reached` (concurrent request limit hit) |
| `X-Tines-Limit-Reached` | If a limit was reached, identifies which one |
| `X-Tines-Response-Location` | URL where the response will be available in JSON when ready |

### Webhook Security
- Always require HMAC verification for inbound webhooks from third parties
- Configure IP allowlist on the Webhook action when the source IPs are known
- Rotate secrets if exposed
- Don't put sensitive data in the webhook URL path

### Pattern: Story as a Service
This is how you expose Tines workflows as APIs to other internal systems:

```
External System → POST https://<tenant>/webhook/<path>/<secret>
                  → Webhook Action
                  → Story logic
                  → Exit Action (with status + body + headers)
                  → HTTP response back to External System
```

Used for: enrichment APIs, decision APIs, automation triggers, anywhere a stable HTTP endpoint is desired without hosting your own service.

---

## 8. Send to Story (Programmatic Sub-Story Invocation)

When invoked from an external system, use the Workflows-as-APIs pattern. When invoked between Stories internally, use Send to Story action.

The Send to Story action payload format:
```json
{
  "story": "<<STORY.story_name>>",
  "payload": {
    "key": "value",
    "...": "..."
  },
  "send_payload_as_body": true,
  "send_to_draft": false,
  "loop": "field_containing_array"
}
```

- `story`: target Story by name (using the `STORY` formula) or by numeric ID
- `payload`: data to pass
- `send_payload_as_body`: if false, payload isn't nested under a `body` key (default true)
- `send_to_draft`: if true, sends to the draft of a Story with change control enabled
- `loop`: name of a field in the incoming event that contains an array — the action invokes the sub-Story once per element

Resolution order: current team first, then any Story globally enabled for Send to Story.

### Enabling a Story to receive Send to Story calls

Before any Send-to-Story action (or MCP tool wired through Send-to-Story) can invoke a target Story, that target must be explicitly enabled:

```
PUT /api/v1/stories/{id}
{
  "send_to_story_enabled": true,
  "send_to_story_access_source": "TEAM",
  "entry_agent_id": <id of entry action, usually webhook>,
  "exit_agent_ids": [<id of action whose emission is the return value>]
}
```

Acceptable `send_to_story_access_source` values: `"TEAM"`, `"ALL_TEAMS"`, `"SPECIFIC_TEAMS"`. Tines internally normalizes `"TEAM"` to `send_to_story_access_source="STS"` + `send_to_story_access="TEAM"` — idiosyncratic but harmless.

## 8a. Action wiring (links_to_sources / links_to_receivers) quirks

There is **no separate `/links` endpoint**. Linking happens inline on the action body via `links_to_sources` / `links_to_receivers` arrays. To wire action A → action B, POST or PUT action B with:

```json
{ "links_to_sources": [{"source_id": <A's id>, "type": "DEFAULT"}] }
```

⚠️ **`PUT /api/v1/actions/{id}` with `links_to_sources` APPENDS** to the existing links rather than replacing them. Same for `links_to_receivers`. Legacy `source_ids` / `receiver_ids` fields are mutually exclusive with the `links_to_*` form and don't reliably replace either.

To change wiring cleanly, **delete and recreate the action**. See [gotchas.md](gotchas.md#8-links_to_sources--links_to_receivers-on-put--adds-does-not-replace).

---

## 9. Terraform Provider

Tines has an official Terraform provider for IaC management.

### Manageable resources
- `tines_story`
- `tines_action`
- `tines_credential` (with sensitive value handling)
- `tines_resource`
- `tines_team`
- `tines_user`
- `tines_role`
- `tines_webhook` (configured via the Webhook action)

### When to use Terraform vs Story Syncing
| Need | Terraform | Story Syncing |
|---|---|---|
| Full IaC with Git history | ✓ | — |
| Move a Story between tenants quickly | — | ✓ |
| Compliance requires reviewable change history | ✓ | partial |
| Manage credentials and resources in code | ✓ | — |
| Story drafted in dev, promoted to prod via PR | ✓ | — |
| Quick iteration in Tines UI | — | ✓ |

For orgs with established infrastructure-as-code culture and change-reviewability requirements, Terraform is the natural fit. Story Syncing is a faster alternative for non-critical work where speed matters more than full IaC discipline.

### Example: Terraform-managed Story
```hcl
provider "tines" {
  email     = var.tines_email
  api_token = var.tines_api_token
  domain    = var.tines_domain
}

resource "tines_team" "eda" {
  name = "EDA"
}

resource "tines_story" "phishing_triage" {
  name              = "Phishing Triage"
  team_id           = tines_team.eda.id
  description       = "Triage phishing alerts from Proofpoint"
  tags              = ["security", "phishing", "tier-1"]
  keep_events_for   = 604800   # 7 days
  change_control_enabled = true
  priority          = true
}

resource "tines_action" "webhook_entry" {
  name     = "Receive phishing alert"
  type     = "Agents::WebhookAgent"
  story_id = tines_story.phishing_triage.id
  options  = jsonencode({
    secret = var.phishing_webhook_secret
    path   = "phishing-alert"
  })
}
```

(Exact resource names and option fields — verify against the current Terraform provider docs.)

---

## 10. Common Patterns

### Export all stories in a team for backup
```bash
# List stories in team
curl -s 'https://<tenant>/api/v1/stories?team_id=<team_id>&per_page=100' \
  -H 'Authorization: Bearer <api_key>' \
  | jq -r '.stories[].id' \
  | while read id; do
      curl -s "https://<tenant>/api/v1/stories/${id}/export" \
        -H 'Authorization: Bearer <api_key>' \
        > "story-${id}.json"
    done
```

### Forward audit logs to SIEM
Schedule a Story (cron-style Webhook entry):
```
1. Schedule trigger (every 15 min)
2. HTTP Request → GET /api/v1/audit_logs?from=<last_run>&to=<now>
3. Event Transform Explode → emit one event per audit entry
4. HTTP Request → POST to SIEM webhook
5. Record → save last_run timestamp for next iteration
```

### Programmatic Story deployment from CI
Use Terraform: PR merge triggers `terraform apply`, which creates/updates the Story in the target tenant. Story Syncing for hot-fixes when speed matters more than review.

### Bulk action update
For applying a tag, monitoring config, or option change across many actions:
```bash
curl -s 'https://<tenant>/api/v1/actions?per_page=200' \
  -H 'Authorization: Bearer <api_key>' \
  | jq -r '.agents[] | select(.story_id==<story_id>) | .id' \
  | while read id; do
      curl -X PUT "https://<tenant>/api/v1/actions/${id}" \
        -H 'Authorization: Bearer <api_key>' \
        -H 'Content-Type: application/json' \
        -d '{"agent": {"monitor_failures": true}}'
    done
```

### Programmatic credential rotation
1. Create new credential via API with same scopes
2. Update actions referencing the old credential to use the new one
3. Verify in dev/staging
4. Delete old credential

---

## 11. Action Type IDs (for API)

When creating actions via API, the `type` field uses internal class names:

| Action UI Name | API `type` Value |
|---|---|
| Webhook | `Agents::WebhookAgent` |
| MCP Server (Webhook variant) | `Agents::WebhookAgent` with `options.mode = "mcp"` |
| Receive Email (mailbox-hosted) | `Agents::ReceiveEmailAgent` |
| Receive Email (IMAP poll) | `Agents::IMAPAgent` |
| Send Email | `Agents::EmailAgent` |
| HTTP Request | `Agents::HTTPRequestAgent` |
| Condition | `Agents::TriggerAgent` |
| Event Transform | `Agents::EventTransformationAgent` |
| Send to Story | `Agents::SendToStoryAgent` |
| AI Agent | `Agents::LLMAgent` |
| Group / subroutine (used as MCP tool) | `Agents::GroupAgent` (with nested `Agents::GroupInputAgent` + `Agents::GroupOutputAgent`) |

The `Agents::` prefix is historical naming from when actions were called "agents" in older Tines versions — a different concept from the current AI Agent action.

**MCP Server is not a distinct action type.** It is a Webhook with `options.mode = "mcp"`. POSTing `type: "Agents::McpServerAgent"` fails. The MCP Server is added from the UI Templates panel, not the main action picker. Tools attached to it are nested `Agents::GroupAgent` subroutines visible only in story exports — `GET /api/v1/actions/{id}` does not return the `tools` array. See [gotchas.md](gotchas.md#2-mcp-server-is-not-a-distinct-action-type).

---

## 12. Open Questions for POC

Items to clarify with Tines SE / API documentation:

1. **Current API version** — is `/api/v1/` the latest, or is there a `/v2` worth using?
2. **Rate limit specifics** — exact requests-per-minute limits per endpoint by tier
3. **Webhook authentication options** — beyond HMAC and IP allowlist, what else is available?
4. **AI Agent API operations** — can AI Agent actions be created and configured via API/Terraform, or UI-only?
5. **Bulk operations** — any first-class bulk update endpoints, or is it always loop-and-update?
6. **OpenAPI spec** — does Tines publish a current OpenAPI spec for SDK generation?
7. **API key scope** — can keys be scoped narrower than full user permissions (read-only, specific resources)?
8. **Self-hosted API parity** — any features in SaaS API not yet in self-hosted?
9. **Terraform provider version** — current version, breaking changes, supported resource types
10. **Webhook execution tracing** — can we get per-execution timing/credit data via API for cost monitoring?

---

## 13. Documentation Pointers

- API Welcome: https://www.tines.com/api/welcome/
- Stories endpoints: https://www.tines.com/api/stories/
- Actions endpoints: https://www.tines.com/api/actions/
- Workflows as APIs: https://www.tines.com/docs/stories/apis/
- Send to Story: https://www.tines.com/docs/actions/types/send-to-story/
- Terraform docs: https://www.tines.com/docs/admin/terraform/
- Audit logs: https://www.tines.com/docs/admin/audit-logs/
