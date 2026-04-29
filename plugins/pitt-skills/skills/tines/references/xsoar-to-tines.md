# XSOAR to Tines Migration

Practical migration patterns for teams moving from Cortex XSOAR/XSIAM to Tines. Written from the perspective of an engineer with deep XSOAR experience evaluating or executing the move.

---

## 1. The Mental Model Shift

### XSOAR: task-graph + scripts
- A playbook is an ordered set of **tasks** with branches and loops
- Tasks call **integration commands** (Python wrapped in YAML metadata)
- Data flows through the **incident context** — a JSON document mutated by each task
- **Sub-playbooks** are tasks that invoke another playbook
- Custom logic lives in **Automations** (Python scripts) or inline in playbook tasks
- The **War Room** is the audit/comm log per incident

### Tines: event-graph + formulas
- A Story is a **directed graph of Actions**, each emits an event consumed by the next
- Most "integration calls" are just **HTTP Request actions** with credentials
- Data flows as **events** (JSON payloads) from action to action — referenced by name (`<<action_name.field>>`)
- **Sub-stories** are invoked via **Send to Story** actions
- Custom logic lives in **Event Transform actions** (formulas) or **Run Script** tools
- **Cases** + **event log** replace the War Room model

The biggest shift: **there's no mutable global context**. Each Action gets the event from its predecessor, period. To "remember" something across actions, either let it flow through every event in between, or persist it to a Resource or Record.

---

## 2. Concept Mapping

| XSOAR | Tines | Notes |
|---|---|---|
| Playbook | Story | Same purpose, different mental model |
| Task (graphical step) | Action | Tines actions are typed and event-emitting |
| Integration | Connect Flow + HTTP Request | No "integration" per se — it's just authenticated HTTP |
| Integration command | HTTP Request action | The huge majority of XSOAR commands map 1:1 to a single HTTP Request |
| Automation (Python script) | Event Transform (formulas) or Run Script tool | Most automations don't actually need Python; formulas handle 80% |
| Sub-playbook task | Send to Story action | Direct equivalent, with optional looping |
| Conditional task | Condition action | Simpler in Tines — single action per branch decision |
| Loop in playbook | Event Transform Explode mode | Explicit fan-out into individual events |
| Incident | Case | Tines Cases are lighter; mirror what you actually use |
| Incident context | Event payload + Resources/Records | No global mutation — pass data forward or store explicitly |
| Incident type | Case fields + tags | Define field schema per case category |
| Layout | Page (for input) + Case fields (for display) | Pages replace UI input layouts |
| Mapper / Classifier | Event Transform Extract mode | Reshape inbound data before downstream actions |
| Pre-process script | Event Transform action(s) before main flow | First few actions in the Story |
| War Room | Event log + Case comments + Workbench | Distributed across three primitives |
| DBot reputation | Custom enrichment Story or AI Agent | No built-in reputation engine — build the pattern |
| Indicator types | Records or external TIP | Tines isn't a TIP; integrate ThreatConnect/etc. |
| Threat Intel feeds | Scheduled HTTP Request → Records or external TIP | Same |
| Marketplace pack | Library template / Custom story | Smaller community library; many integrations are just HTTP credentials + Stories |
| Engine (on-prem worker) | Tunnel | Outbound-only; cleaner firewall posture |
| Long-running container | Polling Story with Event Transform Delay | Different paradigm — Tines doesn't run persistent containers |
| Mirroring | Custom polling pattern | No first-class mirroring — design with scheduled polls or webhook callbacks |
| Job | Scheduled Story (cron-style Webhook entry) | Same |
| List | Resource (JSON) or Record dataset | Resources for static data, Records for dynamic |
| Context expression `${.alert.id}` | `<<action_name.alert.id>>` | Different syntax, same idea |

---

## 3. Action-Level Mapping

### Most XSOAR commands → 1 HTTP Request action in Tines

XSOAR `crowdstrike-falcon-search-device hostname=foo` becomes:

```
HTTP Request action:
  Method: GET
  URL: https://api.crowdstrike.com/devices/queries/devices/v1?filter=hostname:'foo'
  Credential: CrowdStrike Connect Flow
  (auth, headers, retries handled automatically)
```

Pattern: pick the API endpoint, configure the URL, attach the Connect Flow credential. No script wrapper required.

### Reputation commands → enrichment patterns

XSOAR's `!ip ip=1.2.3.4` queries multiple sources and returns aggregated reputation. Tines pattern:

```
Event Transform Explode (one event per source) →
  HTTP Request → ThreatConnect lookup
  HTTP Request → VirusTotal lookup
  HTTP Request → AbuseIPDB lookup
Event Transform Implode (aggregate results) →
Optional: AI Agent action with output schema (verdict + confidence)
```

You build it once and reuse via Send to Story.

### Pre-process scripts → first-stage Event Transform

XSOAR pre-process scripts that normalize incoming alerts become:

```
Webhook (entry) →
  Event Transform Extract mode (formulas to normalize fields) →
  ... rest of Story
```

### Filter & deduplication rules → Condition + Event Transform Deduplicate

XSOAR's classifier/filter logic in mappers becomes:

```
Webhook (entry) →
  Condition (drop noise) →
  Event Transform Deduplicate (suppress duplicates seen recently) →
  ... rest of Story
```

### Communication tasks → Send Email or HTTP Request to chat platform

XSOAR's "ask user via Slack" pattern with manual response handling becomes:

```
HTTP Request → Slack API to post interactive message →
... Story pauses or branches based on Webhook callback from Slack
```

Or, for richer interactions: use a Page with a button and let the human visit a URL.

### Sub-playbook with loop → Send to Story with `loop`

XSOAR sub-playbook with iterating input:
```
Loop over array.indicators → run subplaybook per indicator
```

Tines equivalent:
```
Send to Story:
  story: <<STORY.indicator_enrichment>>
  payload: <<event>>
  loop: array.indicators
```

The loop runs serially and aggregates results into a single output event.

---

## 4. Custom Code Migration

XSOAR Automations (Python) typically fall into a few categories:

| Automation Pattern | Tines Approach |
|---|---|
| Simple data transformation (parse JSON, reshape, filter) | Event Transform with formulas — `JSON_PARSE`, `MAP`, `FILTER`, `REGEX_EXTRACT` |
| API call with custom auth | HTTP Request with HTTP credential (token-fetch step) or Multi Request credential |
| Aggregate from multiple commands | Send to Story (sub-stories) + Event Transform Implode |
| Complex conditional logic | `SWITCH` formula or Condition chain |
| Date/time math | `DATE_PARSE`, `DATE_DIFF`, `UNIX_TIMESTAMP`, `NOW` formulas |
| String manipulation | `CONCAT`, `REGEX_REPLACE`, `REGEX_EXTRACT`, `SPLIT`, `JOIN` |
| Cryptographic ops | `SHA256`, `HMAC_SHA256`, `JWT_SIGN`, `RSA_SIGN`, `AES_ENCRYPT` |
| File parsing (CSV, EML, MSG) | `CSV_PARSE`, `EML_PARSE`, `MSG_PARSE` |
| Genuinely custom Python (e.g., proprietary library, ML inference) | Run Script tool, optionally over Tunnel for private dependencies |
| Reputation aggregation logic | Send to Story enrichment pattern + AI Agent for verdict |

**Rule of thumb**: if the Python script is <30 lines and just glues together API calls and reshapes JSON, it should become Event Transform formulas, not a Run Script tool. Run Script is for cases where formulas genuinely can't express the logic.

---

## 5. Integration Migration

XSOAR has a marketplace integration for almost every product. Tines has Connect Flows for ~200 vendors and a generic HTTP credential for the rest.

### Migration approach
1. Inventory XSOAR integrations actually in use (not all installed; just those in active playbooks)
2. For each, check the Tines Connect Flows index (https://www.tines.com/docs/credentials/connect-flows/)
3. For Tines-supported vendors: use Connect Flow
4. For unsupported vendors with a documented API: use HTTP Request credential type
5. For unsupported vendors without an API: build a Tunnel + Run Script pattern, or integrate via email/file drop
6. For deeply custom integrations (e.g., screen scraping, RPA): Run Script over Tunnel

### What you lose
- **Pre-built command catalog**: XSOAR integration commands are well-documented in the YAML; in Tines you build the API call yourself from vendor docs
- **Reputation chaining via DBot**: You build the equivalent in a Story
- **Mirroring**: Tines doesn't mirror — design polling or webhook callbacks
- **Long-running integrations**: Different paradigm; rarely a real loss

### What you gain
- **No Python container management**: integrations are just HTTP, no Docker images to maintain
- **Cleaner credential handling**: rotation and refresh are built into Connect Flows
- **Faster integration builds**: most "integrations" take 10-15 minutes to stand up
- **Generic vendor coverage**: anything with an API works without waiting for a marketplace pack

---

## 6. Incident → Case Migration

XSOAR incidents have:
- Type (controls layout, fields, default playbook)
- Severity, status, owner
- Custom fields
- Layout (UI for analyst interaction)
- War Room (chat log + audit trail)
- Attached playbook with context

Tines Cases have:
- Title, description (rich text, multiplayer)
- Status, severity (configurable)
- Assignee
- Custom fields (including sensitive)
- Tasks
- Comments
- Linked Stories and event log

### Migration pattern
1. List XSOAR incident types you actively use
2. For each, design a Case schema: title format, fields, severity values, status workflow
3. Replace XSOAR layouts with: Case fields (for display) + Pages (for analyst input forms)
4. Replace War Room with Case comments + the event log (for automated actions)
5. Replace incident-bound playbooks with: Story triggered by webhook → creates Case → updates Case as work progresses

### What's different
- **No 1:1 incident-to-playbook binding**: in Tines, the Story creates and updates the Case. Multiple Stories can interact with one Case.
- **No incident context**: data lives in Case fields and event payloads, not a mutating context blob
- **Tasks are first-class**: instead of manual playbook tasks, Cases have explicit Task primitives with their own assignment

---

## 7. Threat Intel Migration

XSOAR has integrated TIM (Threat Intel Management) with indicator types, feeds, scoring, and DBot reputation. Tines has none of this natively — it's an automation platform, not a TIP.

### CDW context
You have ThreatConnect as your TIP and Polarity as the overlay. ThreatConnect stays in place; Tines is the automation engine that:
- Pulls feeds from ThreatConnect (Stories with scheduled HTTP Request actions)
- Scores/filters indicators (Event Transform + Condition)
- Distributes IOCs to control planes (CrowdStrike, Akamai, Entra) via per-target sub-Stories
- Writes status back to ThreatConnect

This is actually cleaner than the XSIAM model where TIM was a built-in module. With Tines, the orchestration is explicit and visible in Story graphs.

---

## 8. Mirroring and Long-Running Operations

XSOAR mirroring keeps an XSOAR incident in sync with a third-party system (ServiceNow ticket, Jira issue, etc.) bidirectionally. There's no first-class equivalent in Tines.

### Patterns to replicate mirroring
- **Outbound (XSOAR → 3rd party)**: trigger a Story on Case update (use Case automation hooks if available, or a periodic Story that diffs Cases against a Records dataset)
- **Inbound (3rd party → XSOAR)**: poll the 3rd party API on a schedule, diff against Cases, update what changed; or expose a Webhook for the 3rd party to call on change
- **Bidirectional**: combine the two, with idempotency tracking via Records to prevent loops

This is more work to set up than XSOAR's "click to enable mirroring," but the trade-off is full visibility into what's being mirrored, when, and why.

### Long-running playbook tasks
XSOAR has tasks that wait for human input or external completion (status polling). Tines patterns:

| XSOAR Pattern | Tines Equivalent |
|---|---|
| Wait for analyst response (manual task) | Page with form + button → Story resumes via Webhook |
| Poll until external job completes | Loop: HTTP Request → Condition → Event Transform Delay (60s) → repeat |
| Wait for external webhook callback | Webhook entry on a separate Story; correlate via correlation ID |
| Pause for time | Event Transform Delay |

---

## 9. Common Gotchas

1. **No global mutable context.** XSOAR engineers reflexively reach for `setIncident`/`demisto.context()`. In Tines you must let data flow through events or persist to Resources/Records. Plan for it.
2. **Loops are explicit.** XSOAR's "loop in this task" becomes Event Transform Explode → downstream actions → Event Transform Implode. More verbose, more visible.
3. **Branching produces multiple events, not multiple paths in one event.** A Condition action in Tines emits an event on one branch only. Subsequent actions on the other branch don't run for that event. (Coming from XSOAR's task-graph thinking, this catches people.)
4. **Send to Story payload schema matters.** Sub-Stories with declared inputs validate the payload — mismatches throw errors. XSOAR sub-playbook inputs are looser.
5. **No `executeCommand`.** You can't generically "run integration X command Y" the way XSOAR can. Each external call is a deliberately configured HTTP Request action.
6. **Credentials are scoped tighter.** XSOAR integration instances are tenant-wide by default; Tines credentials are team-scoped unless explicitly shared. This is more secure but requires more deliberate sharing.
7. **No DBot.** Reputation aggregation is not built-in. Build it once as a sub-Story and reuse.
8. **Time Saved is a Tines-native field.** XSOAR doesn't have a built-in equivalent; you'll need to actively populate Time Saved values on actions to support ROI reporting.
9. **No demisto-sdk.** You don't develop in YAML + Python like XSOAR. Tines has Terraform for IaC and Story Syncing for tenant-to-tenant promotion, but no equivalent of `demisto-sdk validate / lint / format`.
10. **Credit consumption is the new resource accounting.** XSOAR has incident-based licensing and Compute Units (in XSIAM); Tines bills per Action execution. Forecast carefully — a chatty Story (e.g., polling every 60 seconds) burns credits fast.

---

## 10. Migration Approach (Recommended)

### Phase 1: Inventory (Week 1)
- List all production XSOAR/XSIAM playbooks (active, not legacy)
- Categorize by: trigger source, criticality, frequency, data sensitivity
- List all integrations in active use
- List all incident types in active use
- List all custom Automations (scripts) and what they do

### Phase 2: Pattern Library (Week 2)
- Build 3–5 reference Stories in Tines that exercise the most common patterns:
  - Alert ingestion + triage
  - IOC enrichment + decision
  - Bidirectional sync with one external system
  - Scheduled job (poll + process)
  - Human-in-the-loop approval flow
- These become the templates the team copies for production work

### Phase 3: Migrate by Criticality (Weeks 3–N)
- Start with high-volume, low-risk playbooks (alert triage, enrichment, ticketing)
- Validate each in parallel with XSOAR for 1–2 weeks before cutover
- Migrate critical playbooks (containment, response) only after the team is fluent in Tines
- Decommission XSOAR playbooks one by one as Tines equivalents reach parity

### Phase 4: Sunset (Last)
- Custom integrations and long-running operations migrate last
- Final XSOAR shutdown after all playbooks have Tines equivalents and a 30-day cooldown

### Don't try to migrate everything
- Some playbooks won't translate cleanly. Use the migration as an opportunity to retire ones that don't earn their keep.
- Aim for ~80% of XSOAR functionality migrated cleanly, ~20% rebuilt or retired. The 20% is where the most legacy cruft lives.

### Parallel-run validation (critical for AI-augmented workflows)
For any Tines Story replacing an XSOAR playbook with an AI Agent component, plan for **3 months of parallel-run** before full cutover:

- **Phase 1 (initial):** Tines Story runs but every AI verdict is human-reviewed before action.
- **Phase 2 (validation):** Tines Story runs and a sampled subset of verdicts is human-reviewed. Track per-decision agreement rate (AI verdict vs. human verdict). Target >95% agreement before promoting to auto-close.
- **Phase 3 (production):** Tines handles auto-close cases; humans review escalations.

Skip parallel-run and you skip the calibration data that tells you whether the AI is doing the right thing. This pattern is well-documented from production AI-augmented SOC deployments — see `ai-production-patterns.md` Section 8.1 for details.

---

## 11. CDW-Specific Considerations

### XSIAM-to-Tines transition
The XSIAM exit is the active path, not just SOAR replacement. Tines becomes the SOAR/automation layer in the new stack:
- **SIEM** (TBD: Sentinel, Splunk+ES, Elastic, Databricks) feeds alerts via Webhook into Tines
- **Tines** orchestrates triage, enrichment, response
- **Cases** in Tines (or upstream system) hold investigation state
- **CSOC analysts** work cases via Tines Workbench (or via SIEM-native case views, depending on architecture)

### Active Defense Grid alignment
Per the CISO's CAPABILITY > VISIBILITY directive, Tines Stories should:
- Receive detection alerts
- Decide on response (deterministic logic + AI Agent for nuanced decisions)
- Execute countermeasures across control planes (Identity, Endpoint, Network, Application)
- Audit every decision and action

The cross-pillar countermeasure pattern is exactly what Send to Story sub-Stories are built for — one parent Story per detection, one sub-Story per control plane.

### M&A integration
Tines Stories for new acquisitions:
- Webhook-based intake of acquired company alerts during integration window
- Tunnel deployment in acquired-company network for legacy system access
- Standardized M&A integration sub-Stories that get instantiated per acquisition

### Federal compliance
Out of scope (confirmed). EDA covers internal corporate only.

---

## 12. Open Questions for the POC

These are things to confirm during the POC (or with Tines SE) before committing the team to the migration:

1. **Performance at our event volume** — what's the realistic throughput per Tines instance for our alert load?
2. **Send to Story loop limits** — how does it scale for 10,000-element arrays (e.g., bulk IOC distribution)?
3. **Workbench vs SIEM-native cases** — do CSOC analysts want to live in Workbench, or stay in their SIEM and have Tines update there?
4. **AI Agent reliability for Tier-1 triage** — does the Active Defense Grid use case actually work, or do we need deterministic Story logic?
5. **Story syncing vs Terraform for IaC** — which fits CDW's change control posture?
6. **Tunnel scaling for our integration count** — single Tunnel per environment, or multiple?
7. **Backup/restore strategy for self-hosted** — Postgres + Redis backup integration with our existing backup tooling
8. **Migration cost modeling** — credit consumption forecast based on top 10 playbook traffic patterns
