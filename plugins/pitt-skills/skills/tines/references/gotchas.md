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

**Caller side:** the SendToStoryAgent option key is `story` (singular, not `story_id`). Accepts either a numeric story ID or a pill like `<<STORY.target_slug>>`. The pill only resolves at runtime if the target has `send_to_story_enabled=true` — without that, the calling action errors with `"Couldn't find the target story."` even though the story exists and you can fetch it via the API. The misleading message points at the caller; the fix is on the target.

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

Re-export the story after the per-action PUTs to see `diagram_layout` reflect the new positions. A reusable relayout script (topological depth + parallel-sibling row) can automate this.

### 20. `/api/v2/cases*` is gated to paid tiers (401 on Community Edition)

Cases v2 endpoints (`/api/v2/cases`, `/api/v2/cases/{id}/comments`, `/api/v2/cases/{id}/activities`, etc.) require a paid tier. CE tenants get `401 "tenant does not have access"` regardless of API key permissions — this is a tenant-level entitlement gate, not an auth gate.

Practical implications:

- API smoke tests targeting `/api/v2/cases*` on a CE tenant will always fail; don't burn cycles debugging the request shape or token scope.
- For CE-compatible case-style state (incident tracking, multi-step investigations), back it with **Records** instead. The data model is similar enough for triage-style workflows.
- Pages can host the analyst-facing UI without needing Cases.

Confirmed on a live tenant. Scope case management early in any Tines build: the tier is the limiter, not the API design. See also gotcha #18 (the storyboard Events pane is not an analyst surface) — CE without Cases has no built-in analyst view, so external sinks (Pages, webhook.site, Slack) become load-bearing.

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

`validate_story` does not catch the bad cases; same class as gotcha #23 (option validators lenient at create, strict at runtime). Surfaced rewriting a case-operations sub-story: every op=open call crashed the moment the chain tried to build a fallback description via `CONCAT(vendor, " ", external_id, ...)`.

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

`validate_story` does not catch it (runtime-only). Same class as gotchas #13 (`FORMAT_DATE` doesn't exist), #23 (option validators lenient at create, strict at runtime). Surfaced on a TRAP auto-close Trigger: the Trigger silently never emitted because the options dict was rejected at runtime, no event ever flowed downstream to the auto-close branch.

### 28. `HTTPRequestAgent`'s `log_error_on_status: []` masks API errors silently

An empty `log_error_on_status` array silences all non-2xx logging. The action still emits its event with the API's response body in `.body` and the status code in `.status`, but the action's log feed shows no warning/error entry — only the "Sending request" info line. The next action downstream cannot tell the request failed unless it explicitly checks `.status`.

Common false-success pattern: an HTTPRequestAgent appears to work because the log shows the request being sent, but the API actually 422'd or 404'd. The Tines UI's per-action log panel looks clean.

Diagnose by inspecting the emitted event directly (`GET /api/v1/actions/{id}/events?limit=1`) and reading the `.body` field. If `.body` is an error envelope or a Rails-style array of strings like `["Validation failed: ..."]`, the API rejected the request even though the action's logs are quiet.

Fix: configure `log_error_on_status` explicitly, e.g. `[400, 404, 409, 422, 500]`. Note that `tines_create_action` and direct API creates default to an empty array even when the UI default has values pre-populated.

Surfaced during case Update + Close debugging: the PATCH actions had been silently 422-ing for days because `sub_status_id` rendered to `""` from a broken pill (see #29) and `log_error_on_status: []` swallowed every rejection.

### 29. Pill access to nested keys on a JSON-text `RESOURCE` may resolve to empty in payload contexts

A resource stored as JSON-formatted text such as `{"in_triage": 464167, "pending_analyst": 464168}` supports dot-access pill syntax `<<RESOURCE.my_resource.in_triage>>`. In some contexts (specifically observed inside `Agents::HTTPRequestAgent` JSON-payload string slots), this resolves to empty string at evaluation time rather than the expected integer. The same resource and the same pill may work as expected in a Trigger `path` slot or an Event Transform `payload`.

The action then ships the empty string. For an integer-typed API field like Cases v2 `sub_status_id`, the API rejects with HTTP 422 — silent unless `log_error_on_status` is set (see #28).

Workarounds, in increasing order of robustness:

1. **Hardcode the literal**: `"sub_status_id": 464168` (plain JSON integer) or `"sub_status_id": "=464168"` (formula).
2. **Explicit JSON parse**: `"=JSON_PARSE(RESOURCE.my_resource).in_triage"` — typed; verify on the live tenant before relying on it.
3. **Flat resource per key**: `RESOURCE.my_in_triage_id` instead of a nested-JSON lookup.

Always **probe the rendered value via the emitted event before relying on a nested `RESOURCE` pill resolving correctly**. Sibling gotcha #29's general rule: pills resolve in some contexts and silently produce empty strings in others; the only reliable check is reading the action's emitted event.

Observed during case sub-status wiring. Whether this is a tenant-specific quirk or platform behavior is unconfirmed; the safe assumption is the latter.

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

Surfaced on a TRAP handler.

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

For the `metadata` object on a case, PATCH does not mutate it at all. See gotcha #32 for the dedicated `/cases/{id}/metadata` sub-endpoint that handles metadata mutation.

Surfaced during case-update debugging; confirmed via direct curl probes against `/api/v2/cases/{id}`.

### 32. Cases v2 case `metadata` mutates only through `/cases/{id}/metadata`, not through `PATCH /cases/{id}`

Initial discovery was that `PATCH /api/v2/cases/{id}` with a `metadata` field appeared to be "replace-not-merge." Follow-up probing corrected the picture: PATCH `/cases/{id}` ignores `metadata` **entirely**. So does PUT `/cases/{id}` with `metadata`. The mutation goes through a dedicated sub-endpoint.

Behavior (empirical, against a live tenant):

| call | body | result |
|---|---|---|
| `PATCH /cases/{id}` | `{"metadata": {...anything...}}` | 200, metadata unchanged |
| `PUT /cases/{id}` | `{"metadata": {...anything...}}` | 200, metadata unchanged |
| **`POST /cases/{id}/metadata`** | `{"metadata": {new_key: value}}` | **201, merged in (new keys only)** |
| `POST /cases/{id}/metadata` | `{"metadata": {existing_key: value}}` | **409 "Metadata key X already exists"** |
| **`PUT /cases/{id}/metadata`** | `{"metadata": {...}}` | **200, upsert: overwrites keys on collision, merges by default, never removes unmentioned keys** |
| `PUT /cases/{id}/metadata` | `{"metadata": {}}` | 400 "Invalid metadata" |
| `PATCH /cases/{id}/metadata` | (any) | 404 (endpoint does not exist) |
| `DELETE /cases/{id}/metadata` | `{"keys": [...]}` or `{"metadata": {...}}` | 400 "Invalid metadata keys" (endpoint exists; correct body shape unknown) |

Initial case creation `POST /cases` accepts an inline `metadata` object — that is the only context where the field on the parent resource lands.

Canonical Tines wiring for "update metadata after creation": a separate `Agents::HTTPRequestAgent` doing `PUT /cases/{id}/metadata` with body `{"metadata": {key: value, ...}}`. POST is strict-insert which is rarely what you want once a case is in flight; PUT is the safe default. Reference pattern: a dedicated "Write close metadata" HTTPRequestAgent doing `PUT /cases/{id}/metadata` after the case is created.

---

### 32. `\b` word boundary in regex patterns silently doesn't work

Inside a Tines formula's single-quoted string, the formula parser strips the single backslash on `\b`, leaving a literal `b` requirement that Ruby's regex engine interprets as such. `REGEX_EXTRACT(haystack, '\bhttps?://[^\s"<>]+\b')` searches for `bhttps?://...b` and matches nothing in normal text. `tines_validate_story` does NOT catch this; the action runs without error and returns `[]`.

Doubling to `'\\bhttps?://[^\s"<>]+\\b'` does NOT help — Tines collapses both passes back to the same single-backslash result and `\b` still fails to bind.

```ruby
# WRONG — silently matches nothing
'\bhttps?://[^\s"<>]+\b'
'\b(?:\d{1,3}\.){3}\d{1,3}\b'
'\b[a-fA-F0-9]{32,64}\b'

# CORRECT — character class boundaries provide sufficient delimitation
'https?://[^\s"<>]+'
'(?:\d{1,3}\.){3}\d{1,3}'
'[a-fA-F0-9]{32,64}'
```

`\s`, `\d`, `\.` and other escapes INSIDE a character class or as separators DO work with a single backslash. Only the `\b` zero-width assertion is silently dropped.

Surfaced fixing a TRAP Extract IOCs action: the URL/IP/hash extraction had been emitting `[]` since the story shipped, masked by the upstream TRAP API also returning null, so the symptom looked like an API problem rather than a regex problem. The character class boundaries (`[^\s"<>]`, `\.` between octets) bound URLs and IPs adequately for typical text; if you need strict word boundaries, use explicit lookahead/lookbehind: `(?<![a-zA-Z0-9])https?://...(?![a-zA-Z0-9])`.

---

### 33. `MAP_LAMBDA` is unreliable in `message_only` payload fields

Both shapes that the formula reference suggests are broken on a live tenant when used inside an EventTransform `message_only` payload that returns objects:

- `MAP_LAMBDA(arr, LAMBDA(x, OBJECT(...)))` → returns `[{"": null}, {"": null}, ...]` per element. No error logged. Silent data loss.
- `MAP_LAMBDA(arr, OBJECT(...))` with bare `item` iterator → errors at runtime: `Invalid argument to MAP_LAMBDA, function must be a lambda got Object` / `got Null` (depending on what the body evaluates to before iteration).

The cheatsheet's example `MAP_LAMBDA(users, DOWNCASE(STRIP(item.upn)))` works because the body returns a **scalar** (string). Returning an `OBJECT(...)` from the body breaks. `FILTER(arr, LAMBDA(x, ...))` similarly fails when the array is an array literal `[expr1, expr2, ...]` of complex `IF_ERROR(IF(...))` expressions (gotcha-pair with #29).

Working alternatives:

| Need | Use |
|---|---|
| Extract a field from each element | `MAP(arr, "dotted.path")` (dotted-path form, no LAMBDA) |
| Per-element scalar transformation | `MAP_LAMBDA(arr, DOWNCASE(item))` (body returns scalar) |
| "Any of these are true" predicate | OR-chain of `IF_ERROR(IF(...), false)` (gotcha #42) |
| Per-element object construction with a known max element count | Fixed-slot `COMPACT([IF(SIZE(arr) > 0, OBJECT(...), null), IF(SIZE(arr) > 1, ...), ...])` |

Reference pattern: replace `CONCAT(MAP_LAMBDA(...), MAP_LAMBDA(...), ...)` in a TRAP Extract IOCs action with the fixed-slot COMPACT pattern (5 URL slots, 5 IP slots, 5 hash slots, 1 domain slot). Loss of per-element filtering (URL exclusion, IP private-range) was an acceptable trade-off for the synthetic-testability fix; restore once a working per-element primitive is identified.

Surfaced across multiple extract and transform actions.

### 34. Native `Agents::CaseAgent` is Create-only; no Update / Close / Lookup / Comment action types exist

`Agents::CaseAgent` exists and supports **Create Case only**. The other case operations have no native action type — they must remain HTTPRequest against `/api/v2/cases*`.

API probe results (live tenant):

| Type name tried | Result |
|---|---|
| `Agents::CaseAgent` | 201, Create Case |
| `Agents::CaseUpdateAgent` / `Agents::UpdateCaseAgent` | 422 "Expected value to not be null" |
| `Agents::CaseLookupAgent` / `Agents::CaseSearchAgent` | 422 |
| `Agents::CaseCloseAgent` / `Agents::CloseCaseAgent` | 422 |
| `Agents::CaseCommentAgent` / `Agents::CaseAddCommentAgent` / `Agents::AddCaseCommentAgent` | 422 |
| `Agents::CaseOperationAgent` | 422 |

`Agents::CaseAgent`'s options shape has two top-level keys: `case_details` (used) and `case_fields` (advertised in the default empty action but **silently dropped on input** — any value you POST is not persisted). Use `case_details` only. Typed custom field values must still flow through Pattern B per-field `POST /cases/{id}/fields` (gotcha #20 / [reference_tines_v2_cases_api_quirks](memory)).

`case_details` is stored as an opaque JSON string and preserves arbitrary keys at write time (`metadata`, `external_id`, `sub_status_id`, `fields`, etc. all round-trip), but write-time preservation is not the same as runtime application — only the documented keys are known to be applied: `case_name`, `case_description`, `priority`, `closure_conditions`, `assignee_emails`, `tag_ids`, `record_ids`. Anything else needs separate API calls after create.

**Practical implication:** a Case Operations sub-story with 5+ ops (lookup / open / update / close / add comment + per-field upsert) can convert at most the Open branch to native CaseAgent. Eight of nine HTTPRequest actions stay HTTPRequest. Probe before committing to a refactor — usually not worth the Change Control churn on a LIVE story.

Surfaced during a native CaseAgent type-probe.

### 35. Case block element PATCH uses `element_id`, not `id`

Cases v2 lets you PATCH a block element's `content`, but the URL key is `element_id` — NOT the `id` field that also lives on every element.

```
PATCH /api/v2/cases/{case_id}/blocks/{block_id}/elements/{element_id}
body: {note_type: "text", content: "<new>"}
```

Each element exposes BOTH `id` (the result-row id) and `element_id` (the URL key for PATCH). Hitting `/elements/{id}` returns 404 "TeamCaseBlockElement not found". A direct `PATCH /blocks/{id}` only updates the block's `title` and `position` — element content is unreachable from there.

To find the right key when inspecting a block via `GET /api/v2/cases/{id}/blocks`:

```python
block["elements"][0]["element_id"]   # use this
block["elements"][0]["id"]           # NOT this
```

The 404 error message doesn't hint at which field to use; only the docs' example URL `{element_id}` distinguishes them. Surfaced during case block-element work; cost ~20 minutes of "but I'm targeting it correctly".

### 36. Cases v2 block API has three constraints worth knowing

Live tenant behaviors discovered during case block work:

- **`block_type` enum is narrow.** Only `note, file, metadata, closure_conditions, linked_cases, case_action, case_group, html`. No `markdown` or `table`. For markdown content, use `note` with element `note_type: "text"`; for raw HTML, use `html` with element `note_type: "html"`. The 422 error message ("HTML block must have note_type of html") refers to the *element*, not the block.

- **`position` on POST is server-ignored.** Caller-supplied position is discarded; the new block gets the next-available slot (max + 1) regardless. Reorder by calling `PATCH /api/v2/cases/{id}/blocks/{block_id}` body `{position: N}` after creation.

- **No element-append path.** `POST /blocks/{id}/elements` and `POST /blocks/{id}` both return 404. Multi-element blocks created in the initial `elements` array work, but to add an element to an existing block you must delete + recreate the whole block (losing the block id).

Block titles auto-derive into a `blk_<snake_case>` slug — useful for finding a block via `FIRST(FILTER(blocks, LAMBDA(b, b.slug = 'blk_my_block')))` when ids aren't known at formula time.

### 37. Case templates pre-bake blocks but only export/import is on the public API

Tines case templates (since April 2024) bundle block layouts in `options.blocks`, plus `tasks`, `closure_conditions`, `input_values`, `field_definitions`, default tags/assignees. Apply at case-creation time via the storyboard case-tile UI.

API surface is limited:
- `POST /api/v1/case_templates/export` — JSON dump by template id (per docs)
- `POST /api/v1/case_templates/import` — round-trips JSON into another team/tenant
- **No** list / get / create / update / delete REST endpoints. Live config edits stay UI-only.

Tier-or-doc-drift caveat: on a live tenant probe, all `/api/v1/case_templates*` and `/api/v2/case_templates*` paths returned 404. Either the endpoints are tier-gated, or the documented paths diverged from the live API. UI export is a safer assumption than REST until this is resolved empirically.

**Design implication for handler chains:** if a template can pre-define the block, the handler doesn't need to POST it at op=open. Action-driven block creation is only required when the *content* must be vendor-conditional or stage-derived (formulas, IFs, FILTERs that templates can't express). The hybrid pattern: template defines the skeleton, action chain PATCHes the element_id as stages complete.

### 38. `Agents::CaseAgent` does NOT resolve pills inside block content

The CaseAgent evaluates `<<pills>>` only in the case **shell** — `case_name`, `case_description`, `priority`, `status`, `metadata` values, `tag_names` — and in `case_fields`. Pills inside `blocks[].elements[].content` are **stored literally**: a `<<receive_x.body.field>>` in a block renders as the raw bracket text to the analyst. The identical pill resolves fine in `case_description`, which makes it easy to miss until someone reviews a real case.

```
case_description: "**Host:** `<<receive_cs_detection.body.device.hostname>>`"   -> WEBAUTOPRODVH7   (resolved)
blocks[0].content: "**Host:** `<<receive_cs_detection.body.device.hostname>>`"  -> raw <<...>>      (literal)
```

Structural, not a syntax issue — backticks / code-spans are irrelevant. There is no flag to turn block-content evaluation on. To populate blocks with live data, do a **post-create block-fill**: after the tile emits `<<slug.case_id>>`, `GET /api/v2/cases/{id}/blocks`, match the target block by its `blk_<snake_case>` slug (#36), then `PUT /api/v2/cases/{id}/blocks/{block_id}/elements/{element_id}` with `{"content": "<md with pills>"}` — pills resolve because they're now in a normal HTTPRequest action (element URL key is `element_id`, #35). Run the PUTs as a branch off the tile so the case stays born-complete.

To backfill cases created before such a branch existed, source the original alert from the tile action's events: `GET /api/v1/actions/{tile_id}/events` — each event payload carries the upstream `receive_*.body` (+ triage / enrichment) **and** the emitted `case_id`, so you can map case → alert without per-case archaeology. Guard overwrites on a marker (`<<`, a known placeholder, or the template's example string) so analyst-edited blocks are left alone.

Confirmed on a live tenant (CrowdStrike + Proofpoint TRAP handler fill branches). Pairs with #34 (`case_fields` also silently dropped from `case_details`) — the shell resolves, the contents don't.

### 39. Formula/action syntax traps that only error at runtime (build-from-scratch checklist)

Surfaced fixing an auto-built Promote-Case story on a live tenant; each broke a live run, none is caught by structural / `validate_story` checks. Drafts do NOT execute, so these stay invisible until a real event flows.

- **Equality is `=`, not `==`.** `IF(x == 'a', ...)` / `LAMBDA(x, x == v)` error: *"`==` is not a valid operator. You can use `=` to compare things."* Use a single `=`.
- **EventTransform emit mode is `message_only`, never `message`.** `mode: "message"` errors: *"'message' is not a valid mode."*
- **`NOW` is a function — `NOW()`.** Bare `<<NOW>>` errors: *"NOW is a function, did you mean to write NOW()?"* `=NOW()` renders ISO 8601.
- **`CONCAT` is array-only; use `JOIN`.** Scalar `CONCAT('a', x, 'b')` errors *"Invalid arguments to CONCAT, expected arrays."* Use `JOIN(['a', x, 'b'], '')`. (Also gotcha #8.)
- **`RESOURCE.x.y` nested reads render `null` inside HTTP JSON-payload slots — for the formula form `=RESOURCE...` too, not just `<<pill>>` form (extends #29/#30).** `set_case_props` sent `sub_status_id: null` and `audit_write` sent every `field_id: null`, all silently. In an `Agents::HTTPRequestAgent` payload, hardcode the literal id (or flatten the resource / read it in an upstream EventTransform and pass the scalar down). The value side (`=prep.x`, `=NOW()`, `=JOIN(...)`, `MAP(FILTER(...), "value")`) rendered fine — only the RESOURCE nested reads dropped.
- **Cases v2 update assignee field is `add_assignee_emails` (array), NOT `assignee_emails`.** `PATCH/PUT /api/v2/cases/{id}` with `assignee_emails` 422s: *"Field is not defined on TeamCaseUpdateInput."* (`assignee_emails` is only a `case_details` key on CREATE — see #34.) Also `remove_assignee_emails` to unset.

---

## What to do when you hit an un-documented thing

1. Reach for the **Action logs endpoint** first (#17). Half the time the real error is there.
2. If the pill is suspect, **look at the stored string via `GET /api/v1/actions/{id}`** — not what you sent, what Tines accepted.
3. If you're stuck on a type/shape question, **open the UI, do the action once, then read the state back via API**. Typically saves 30+ minutes vs blind probing.
4. **Probe-then-trust.** Docs lie. The live tenant is authoritative.
