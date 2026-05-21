# Tines gotchas — read this before you build

Non-obvious Tines behaviors that will bite you. Discovered through live tenant work; most are not documented in the public docs or are documented unclearly. **When working on anything non-trivial in Tines, skim this first.**

## The big three (each cost ~30+ min of debugging if missed)

### 1. Pill syntax is `<<slug.body.field>>` — NOT `{{ }}`

This is the single most important thing in this skill. Tines pills in text fields (URL, headers, payload, system instructions, prompt, etc.) use **double angle brackets** — not Mustache/Liquid `{{ }}` or ERB `<% %>`.

```
# Correct
"url": "https://api.example.com/users/<<receive_webhook.body.user_id>>/profile"
"prompt": "Indicator: <<receive_indicator.body.indicator>>"

# WRONG — silently stripped to empty string, no error
"url": "https://api.example.com/users/{{ receive_webhook.body.user_id }}/profile"

# WRONG — "Invalid URL" error
"url": "https://api.example.com/users/{{ .receive_webhook.body.user_id }}/profile"
```

**Not shown in any official docs.** The formulas/pills pages display pills only as rendered UI "bubbles" and expressions inside them (like `UPCASE(x)`) — never the `<<...>>` wrapper. An LLM agent reading only the public docs cannot discover this pattern. Confirmable only by inserting a pill via the UI and inspecting the stored text.

Functions and references inside pills: `<<URL_ENCODE(receive_indicator.body.url)>>`, `<<SWITCH(type, "ip", "IPv4", "domain", "domain", "default")>>`, `<<NOW()>>`, etc.

### 2. MCP Server is NOT a distinct action type

An MCP Server is `Agents::WebhookAgent` with `options.mode = "mcp"`. It's hidden from the main action picker in the storyboard — reachable only via a **Templates panel** on the left side. On Community Edition, the Templates panel may be absent entirely (or require specific exploration). No API-discoverable type string; `POST /api/v1/actions` with `type: "Agents::McpServerAgent"` fails silently with a null-validation error.

Tools attached to an MCP Server are **nested `Agents::GroupAgent` subroutines** containing `GroupInputAgent` (defines input schema) and `GroupOutputAgent` (defines return payload). The `tools` array lives on the MCP Server action but is visible **only in story exports** — `GET /api/v1/actions/{id}` does not return it.

Practical implication: building a multi-tool MCP server fully from API is impractical without reverse-engineering the nested shape from an export. One UI excursion to add each tool is the fast path.

### 3. `output_schema` on `Agents::LLMAgent` is a hint, not an enforcer

The Tines AI Agent docs describe `output_schema` as validation. In practice it is passed to the model as guidance; the model usually follows it but can return off-enum values, extra fields, missing fields, renamed fields (`reason` instead of `reasoning`, `safe` instead of `benign`). Plan downstream consumers accordingly (case-insensitive regex, tolerate extra fields, etc.).

```
schema says: verdict enum ["benign","suspicious","malicious","unknown"]
model may return: verdict="safe" or "CLEAN" or "MALICIOUS" (uppercase)
```

## Silent failures

### 4. Bad `team_id` on `POST /api/v1/stories` → personal team, no error

`POST /api/v1/stories` accepts arbitrary `team_id` values without validation. Invalid IDs silently create the story in the user's *personal* team — a hidden category that doesn't appear in `GET /api/v1/teams`. AI Agent actions in personal teams fail at run time with: **"AI actions cannot run in a personal team"**. `list_stories` shows the story with `team_id` you sent, making this even more confusing.

Always verify by cross-checking: `GET /api/v1/teams` returns the real team IDs. Your story's `team_id` should match one of those.

### 5. `list_events?action_id=X` doesn't actually filter

The `action_id` query parameter on `/api/v1/events` does not restrict the response to events emitted by that action. Returns a broader story-or-tenant pool instead. Filter client-side: `[ev for ev in events if ev["agent_id"] == <id>]`. Better pattern: use `story_run_guid` to group events from one story run (every event in the same run shares it).

### 6. Pill references to missing fields resolve to empty string — no error

If your prompt or URL references `<<foo.bar.baz>>` and `bar` doesn't exist, the pill silently substitutes empty. URLs get path-malformed, API requests get empty params, the AI Agent gets context holes. Always check action logs (`GET /api/v1/actions/{id}/logs`) to see the exact string Tines produced.

### 7. HTTP Request URL-field pill validation is placement-sensitive

A pill as a **whole path segment** often passes validation: `.../users/<<x>>/profile`. A pill surrounded by other chars in the same segment sometimes gets "Invalid URL" rejected: `.../users/a-<<x>>-b`. Tines validates the URL before substituting pills; depending on where `<<...>>` sits, the raw template may or may not look URL-ish enough to pass validation.

### 21. Pill `<<x.y.z>>` in a JSON payload value stringifies arrays and objects

When a pill is the entire value of a JSON field in an action's `payload`, Tines emits the resolved value as a JSON **string**, not as the native type. If the pill resolves to an array, you get a quoted-string-containing-a-JSON-literal like `{"composite_ids": "[\"id1\",\"id2\"]"}` — and any downstream consumer that expects an array (CrowdStrike Alerts API, etc.) will reject the body.

Use **formula syntax** (`=expr`, no angle brackets) for native-type substitution:

```jsonc
// WRONG — sends {"composite_ids": "[\"id1\"]"}, a string containing an array literal
"payload": { "composite_ids": "<<query.body.resources>>" }

// CORRECT — sends {"composite_ids": ["id1"]}, native array
"payload": { "composite_ids": "=query.body.resources" }
```

Diagnose by reading the outbound log via `GET /api/v1/agents/{id}/logs` (gotcha #17) and inspecting the literal `body` field. If the value looks like a quoted JSON literal, this bug is yours. Cost ~30 min during the CS poller build before the pattern was identified.

Pill is fine when the value is naturally a string (URL, single-string field, etc.). The trap is array/object/number/boolean passthrough.

### 22. Pill `.length` on an array doesn't resolve in TriggerAgent paths

`<<query.body.resources.length>>` in a TriggerAgent rule `path` resolves to nothing (or an unrelated internal value) — Tines doesn't honor JavaScript-style `.length` access. The Trigger silently logs `"Invalid Options"` errors and the chain stalls without an obvious cause.

Workarounds:

- Use a `regex` rule against the array literal: `type: "regex", value: "\\[.+\\]", path: "<<query.body.resources>>"`. Matches any non-empty array; `[]` fails to match.
- Use a formula path: `path: "=SIZE(query.body.resources)"` paired with a numeric comparison rule type (verify the rule type is runtime-valid; see #23).

## API surprises

### 8. `links_to_sources` / `links_to_receivers` on PUT → adds, does not replace

Updating an action's wiring via `PUT /api/v1/actions/{id}` with `links_to_sources: [...]` APPENDS to the existing links. Same for `links_to_receivers`. The legacy `source_ids`/`receiver_ids` fields don't reliably replace either. To change wiring cleanly, **delete and recreate the action**.

Note: `links_to_receivers` is also the canonical write-side for **adding** a link. The shape on PUT is `[{"receiver_id": <int>, "link_type": "DEFAULT"}]` — both fields required; `link_type: "DEFAULT"` is the common value. The MCP `tines_update_action` tool does not expose this field, so programmatic wiring requires raw `PUT /api/v1/agents/{id}`.

### 9. Some doc paths are wrong; probe the live tenant

Confirmed divergences between the public docs and the live tenant as of 2026-04:

| Operation | Docs say | Actual |
|-----------|----------|--------|
| Export story | `POST /api/v1/stories/{id}/export` | `GET /api/v1/stories/{id}/export` |
| List events by action | `GET /api/v1/stories/actions/{id}/events` | `GET /api/v1/events?action_id={id}` (flat collection, client-side filter) |
| Credentials base path | `/api/v1/credentials` | `/api/v1/user_credentials` |
| Resources base path | `/api/v1/resources` | `/api/v1/global_resources` |

**Protocol: probe-then-trust.** When the docs describe an endpoint you haven't used, hit it against a throwaway tenant resource before trusting the path/method.

### 10. Teams use PATCH, not PUT

`PATCH /api/v1/teams/{id}` for updates. PUT returns an error or silently no-ops.

### 11. Send-to-Story requires the target story to be explicitly enabled

Before a Send-to-Story action can invoke another story, that target story must have:
```
send_to_story_enabled: true
send_to_story_access_source: "TEAM"  (or "ALL_TEAMS", "SPECIFIC_TEAMS")
entry_agent_id: <id of entry action, usually webhook>
exit_agent_ids: [<id of the action whose emission is the "return value">]
```
All four via `PUT /api/v1/stories/{id}`. Tines normalizes `send_to_story_access_source="TEAM"` into `send_to_story_access_source="STS"` + `send_to_story_access="TEAM"` on its side — idiosyncratic but harmless.

**Caller side:** the SendToStoryAgent option key is `story` (singular, not `story_id`). Accepts either a numeric story ID (`109386`) or a pill like `<<STORY.cdw_target_slug>>`. The pill only resolves at runtime if the target has `send_to_story_enabled=true` — without that, the calling action errors with `"Couldn't find the target story."` even though the story exists and you can fetch it via the API. The misleading message points at the caller; the fix is on the target.

### 12. `SWITCH` formula requires an explicit default

```
# Works:
SWITCH(type, "ip", "IPv4", "domain", "domain", "unknown")

# Errors with "Invalid arguments to SWITCH, expected pairs + default":
SWITCH(type, "ip", "IPv4", "domain", "domain")
```

### 13. `FORMAT_DATE` doesn't exist as a formula function

Name is different on Tines. `NOW()` returns an ISO 8601 string directly in most pill contexts — no formatting wrapper needed. If you need a specific format, experiment with variants (`DATE_FORMAT`, `STRFTIME`, etc.) or use string manipulation on `NOW()`'s output.

### 23. Action option validators are lenient at create, strict at runtime

`POST /api/v1/actions` (and the MCP `tines_create_action`) accepts options blocks that the runtime later rejects. The action lands in the story with no creation-time error; the chain only breaks when a real event arrives.

Confirmed during the CS poller build: a TriggerAgent created with `{"rules": [{"type": "field_greater_than", "value": "0", "path": "..."}]}` returned 200 at create. Every cron tick then logged `"Invalid Options: Rule contains invalid type: 'field_greater_than'"` at runtime. The valid runtime type for that comparison turned out to be `regex` (matched against the array literal), not `field_greater_than`.

Implications:

- Don't trust a 200 from `tines_create_action` as proof the action will run.
- After creating an action programmatically, fire one event through it (or read its logs after the first real trigger) before treating it as wired.
- When stalled mid-chain with no visible event emission, fetch `GET /api/v1/agents/{id}/logs` (gotcha #17) — the runtime rejection message is there, not in the create response.

### 24. Schedules attach to HTTPRequestAgent, not WebhookAgent; shape and minimum cadence

The Tines UI does not expose an "Add schedule" affordance on `Agents::WebhookAgent`. Schedules must live on the first downstream `Agents::HTTPRequestAgent` (or another agent type that emits independently). A cron-driven poller chain is therefore `[scheduled HTTP Request] -> [Trigger] -> ...`, not `[Webhook with schedule] -> ...`.

Shape on the agent object (and on `PUT /api/v1/agents/{id}`):

```json
"schedule": [
  {"cron": "* * * * *", "timezone": "UTC"}
]
```

Field name is `timezone` (one word), not `time_zone`. Tines stores `schedule` as an **array** of schedule objects (multiple schedules per agent are allowed). The MCP `tines_update_action` tool does not expose `schedule`; use raw REST.

**Minimum cadence is 1 minute** (`* * * * *`), not 60 seconds, not 30 seconds. The Tines `whats-new` page documents this; sub-minute schedules are not accepted.

If a plan says "Every 60 seconds" or "every N seconds where N<60", interpret as "every minute" and proceed.

### 25. Action create requires the full `Agents::*` type names

`tines_create_action` and `POST /api/v1/actions` reject short type names. `"WebhookAgent"` returns 422; `"Agents::WebhookAgent"` is required. Same for every other action type: `"Agents::HTTPRequestAgent"`, `"Agents::TriggerAgent"`, `"Agents::EventTransformationAgent"`, `"Agents::SendToStoryAgent"`, `"Agents::LLMAgent"`, etc.

The `action_type` parameter description on the MCP tool implies short forms are valid (`"e.g. WebhookAgent, HTTPRequest"`). They are not. Always prefix with `Agents::`.

## Operational ceilings

### 14. MCP tool execution has a hard 30-second timeout

Any MCP `tools/call` that takes longer than 30 seconds returns `{"isError": true, "content": [{"type": "text", "text": "Tool execution timeout"}]}`. The underlying Tines action/chain keeps running and emits events normally; the caller just doesn't get the result synchronously. Send-to-Story as a tool adds invocation overhead on top of the target story's own duration — plan for the chain to complete in well under 30s, or redesign as async trigger+poll.

### 15. Community Edition has a 3-story cap

You cannot create a 4th story on CE. Building iteratively often means deleting old stories mid-eval. Plan which stories are disposable. Also: the 1-builder-seat and 50-AI-credit-monthly caps are real and immediate; `remaining_credits` in every AI Agent event is your authoritative counter.

### 16. Send-to-Story as an MCP tool auto-derives empty input schema

When you add a Send-to-Story as a tool on an MCP Server via the UI, Tines auto-derives `tool.name` from the target story's name (snake_case), **copies the target story's name to `description`** (your custom description is ignored), and leaves `inputSchema.properties` empty. Calling the tool with named arguments doesn't route them to the target story's webhook body. You have to configure input-schema fields + argument mapping explicitly in the tool's UI config.

## Debugging shortcuts

### 17. Action logs endpoint is the single best debug tool

```
GET /api/v1/actions/{action_id}/logs?per_page=N
```

Returns `{action_logs: [...]}`. Each log entry has `level` (3=info, 4=error), `created_at`, and a `message` field. The `message` on an HTTP Request log includes the exact URL and body Tines sent, which is invaluable when pill substitution is suspect. For AI Agent logs, errors like "AI actions cannot run in a personal team" or "Error evaluating formula: Undefined function FORMAT_DATE" surface here.

Not easy to find from the navigation docs; must be probed.

### 18. The storyboard Events pane is for builders, not analysts

The "Recent events" pane inside the story builder shows raw JSON payloads — good for debugging during build but wildly unsuitable as an analyst consumption surface. For human-facing output, route to Cases (Enterprise only), Pages, Send Email, Slack/Teams webhooks, or an external sink like `webhook.site`. CE without Cases has no built-in analyst view; plan for an external sink.

### 19. `PUT /api/v1/stories/{id}` silently discards `diagram_layout`

Exports include `diagram_layout` as a JSON-encoded string mapping `agent_guid → [x, y]`. Sending that field back via `PUT /api/v1/stories/{id}` returns 200 but does nothing — `diagram_layout` is a derived projection of all per-action positions, not the source of truth.

To update layout programmatically:

1. `GET /api/v1/actions?story_id={id}&per_page=100` to map each `agent.guid → action.id` (integer id, separate from guid).
2. For each agent to reposition: `PUT /api/v1/actions/{action_id}` with body `{"position": {"x": <int>, "y": <int>}}`.
3. Tines snaps `x` and `y` to a 15px grid (e.g., `±98` becomes `±105` on read-back). Functionally identical, but plan spacing as multiples of 15 if you want byte-equal round-trips.

Re-export the story after the per-action PUTs to see `diagram_layout` reflect the new positions. Reusable Python relayout script (uses topological depth + parallel-sibling row): `c:\Code\tines\scripts\relayout_stories.py`.

### 20. `/api/v2/cases*` is gated to paid tiers (401 on Community Edition)

Cases v2 endpoints (`/api/v2/cases`, `/api/v2/cases/{id}/comments`, `/api/v2/cases/{id}/activities`, etc.) require a paid tier. CE tenants get `401 "tenant does not have access"` regardless of API key permissions — this is a tenant-level entitlement gate, not an auth gate.

Practical implications:

- API smoke tests targeting `/api/v2/cases*` on a CE tenant will always fail; don't burn cycles debugging the request shape or token scope.
- For CE-compatible case-style state (incident tracking, multi-step investigations), back it with **Records** instead. The data model is similar enough for triage-style workflows.
- Pages can host the analyst-facing UI without needing Cases.

Confirmed on `lingering-waterfall-1781`. Scope case management early in any Tines build: the tier is the limiter, not the API design. See also gotcha #18 (the storyboard Events pane is not an analyst surface) — CE without Cases has no built-in analyst view, so external sinks (Pages, webhook.site, Slack) become load-bearing.

---

## What to do when you hit an un-documented thing

1. Reach for the **Action logs endpoint** first (#17). Half the time the real error is there.
2. If the pill is suspect, **look at the stored string via `GET /api/v1/actions/{id}`** — not what you sent, what Tines accepted.
3. If you're stuck on a type/shape question, **open the UI, do the action once, then read the state back via API**. Typically saves 30+ minutes vs blind probing.
4. **Probe-then-trust.** Docs lie. The live tenant is authoritative.
