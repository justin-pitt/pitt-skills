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

### 26. String concat in a formula needs `JOIN`, not `CONCAT` or `+`

Despite being documented under "string functions," `CONCAT` is **array-only** at runtime:

```
CONCAT("a","b","c")            → runtime error: "Invalid arguments to CONCAT, expected arrays"
CONCAT(["a","b","c"])          → ["a","b","c"]   (returns the array, not "abc")
```

`+` is **number-only** and rejects text:

```
"a" + "b"                      → runtime error: "Could not convert object of type Text to a number.
                                  The + operator only accepts Numbers or Text that can be converted to a number."
```

The correct primitive inside a formula is `JOIN(array, separator)`:

```
JOIN(["Bearer ", credential.token], "")           → "Bearer abc123"
JOIN([vendor, external_id, "- awaiting"], " ")    → "proofpoint_trap inc-001 - awaiting"
```

Outside a formula (a top-level field value), just chain pills inline in plain text:

```
"description": "<<vendor>> <<external_id>> - awaiting enrichment"
```

`validate_story` does not catch the bad cases; same class as gotcha #23 (option validators lenient at create, strict at runtime). Surfaced during Case Operations Phase 4 rewrite on `lingering-waterfall-1781`: every op=open call crashed the moment Case Ops tried to build a fallback description via `CONCAT(vendor, " ", external_id, ...)`.

### 27. `TriggerAgent` `must_match` accepts numeric strings only — `"all"` is rejected

When wiring a `TriggerAgent` with multiple rules that all need to match (AND semantics), the natural-looking value is rejected:

```
options:
  must_match: "all"          → runtime error: "Invalid Options: 'must_match' must be a number greater than 0"
  rules: [...3 regex rules...]
```

The validator wants a numeric string equal to the rule count for AND, or `"1"` for OR. Set it to the rule count:

```
options:
  must_match: "3"            → all 3 rules must match
  must_match: "1"            → any 1 of the rules must match (OR)
```

`validate_story` does not catch it (runtime-only). Same class as gotchas #13 (`FORMAT_DATE` doesn't exist), #23 (option validators lenient at create, strict at runtime). Surfaced on the gap-1 TRAP auto-close Trigger on `lingering-waterfall-1781`: the Trigger silently never emitted because the options dict was rejected at runtime, no event ever flowed downstream to the auto-close branch.

### 28. `HTTPRequestAgent`'s `log_error_on_status: []` masks API errors silently

An empty `log_error_on_status` array silences all non-2xx logging. The action still emits its event with the API's response body in `.body` and the status code in `.status`, but the action's log feed shows no warning/error entry — only the "Sending request" info line. The next action downstream cannot tell the request failed unless it explicitly checks `.status`.

Common false-success pattern: an HTTPRequestAgent appears to work because the log shows the request being sent, but the API actually 422'd or 404'd. The Tines UI's per-action log panel looks clean.

Diagnose by inspecting the emitted event directly (`GET /api/v1/actions/{id}/events?limit=1`) and reading the `.body` field. If `.body` is an error envelope or a Rails-style array of strings like `["Validation failed: ..."]`, the API rejected the request even though the action's logs are quiet.

Fix: configure `log_error_on_status` explicitly, e.g. `[400, 404, 409, 422, 500]`. Note that `tines_create_action` and direct API creates default to an empty array even when the UI default has values pre-populated.

Surfaced on `lingering-waterfall-1781` during Case Operations Update + Close debugging (issue #24): the PATCH actions had been silently 422-ing for days because `sub_status_id` rendered to `""` from a broken pill (see #29) and `log_error_on_status: []` swallowed every rejection.

### 29. Pill access to nested keys on a JSON-text `RESOURCE` may resolve to empty in payload contexts

A resource stored as JSON-formatted text such as `{"in_triage": 464167, "pending_analyst": 464168}` supports dot-access pill syntax `<<RESOURCE.my_resource.in_triage>>`. In some contexts (specifically observed inside `Agents::HTTPRequestAgent` JSON-payload string slots), this resolves to empty string at evaluation time rather than the expected integer. The same resource and the same pill may work as expected in a Trigger `path` slot or an Event Transform `payload`.

The action then ships the empty string. For an integer-typed API field like Cases v2 `sub_status_id`, the API rejects with HTTP 422 — silent unless `log_error_on_status` is set (see #28).

Workarounds, in increasing order of robustness:

1. **Hardcode the literal**: `"sub_status_id": 464168` (plain JSON integer) or `"sub_status_id": "=464168"` (formula).
2. **Explicit JSON parse**: `"=JSON_PARSE(RESOURCE.my_resource).in_triage"` — typed; verify on the live tenant before relying on it.
3. **Flat resource per key**: `RESOURCE.my_in_triage_id` instead of a nested-JSON lookup.

Always **probe the rendered value via the emitted event before relying on a nested `RESOURCE` pill resolving correctly**. Sibling gotcha #29's general rule: pills resolve in some contexts and silently produce empty strings in others; the only reliable check is reading the action's emitted event.

Observed against `lingering-waterfall-1781` during Case Operations sub-status wiring (issue #24). Whether this is a tenant-specific quirk or platform behavior is unconfirmed; the safe assumption is the latter.

### 30. `=String(value)` is not a Tines formula function

`String()` looks like a natural JavaScript-style scalar coercion, but Tines has no such function:

```
=String(receive.body.id)         → runtime error: "Undefined function String"
```

To get the string form of a value for use inside another formula or as a string slot, use:

- **Plain pill** (auto-stringifies when placed in a JSON string context): `"<<receive.body.id>>"`
- **JOIN single-element**: `=JOIN([receive.body.id], '')` returns the value coerced to text
- **String-literal prefix concat**: `=JOIN(['', receive.body.id], '')` if you need to defeat type-preservation explicitly

`validate_story` does not catch this; runtime-only. Sibling foot-guns: no `REGEX_MATCH`, no `CONTAINS`-for-arrays, `CONCAT` is array-only, no `FORMAT_DATE`. The mental model: assume any obvious-sounding global function from a mainstream language does not exist in Tines formulas until proven by a synthetic fire.

Surfaced on `lingering-waterfall-1781` on the TRAP handler (issue #22 / PR #31).

### 31. Cases v2 PATCH: `null` is no-change, `""` is destructive

The `PATCH /api/v2/cases/{id}` endpoint draws a sharp distinction between JSON `null` and empty string for nullable fields:

| Body value | Effect |
|---|---|
| `{"sub_status_id": 464168}` | Sets sub-status to that ID |
| `{"sub_status_id": null}` | No change — current sub-status preserved |
| `{"sub_status_id": ""}` | **HTTP 422 "No object ID provided"** |
| `{"description": "new text"}` | Sets description |
| `{"description": null}` | No change — current description preserved |
| `{"description": ""}` | **Destructive** — sets description to empty string, logs a `DESCRIPTION_UPDATED` activity with empty value |

The destructive behavior is dangerous in Tines because a common pattern is `<<DEFAULT(receive.body.fields.ai_summary, '')>>` — when the caller omits `ai_summary`, the pill renders to `""` and the PATCH wipes the existing description. Same shape applies to any nullable text field on the case.

Canonical pattern: use **formula form with explicit null fallback** so JSON `null` reaches the API:

```
"description":   "=DEFAULT(receive.body.fields.ai_summary, null)"
"sub_status_id": "=IF(IS_PRESENT(receive.body.fields.ai_verdict), 464168, null)"
```

Pair with gotcha #28 (silent error logging) — without `log_error_on_status` configured, the 422s on `sub_status_id: ""` are completely silent.

Also note: the same endpoint's `metadata` object appears to be **replace-not-merge** on PATCH. Sending `{"metadata": {"new_key": "value"}}` against a case that already has `metadata: {"source": "x"}` does not merge; the new keys silently fail to land while the original is preserved. To update a single metadata key, read the case first, merge client-side, and PATCH the full merged object. Unconfirmed whether this is documented anywhere; observed empirically on `lingering-waterfall-1781`.

Surfaced during issue #24 fix; confirmed via direct curl probes against `/api/v2/cases/{id}`.

---

## What to do when you hit an un-documented thing

1. Reach for the **Action logs endpoint** first (#17). Half the time the real error is there.
2. If the pill is suspect, **look at the stored string via `GET /api/v1/actions/{id}`** — not what you sent, what Tines accepted.
3. If you're stuck on a type/shape question, **open the UI, do the action once, then read the state back via API**. Typically saves 30+ minutes vs blind probing.
4. **Probe-then-trust.** Docs lie. The live tenant is authoritative.
