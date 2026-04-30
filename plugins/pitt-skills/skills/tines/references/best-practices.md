# Best practices — AI Agents, credit management, design

Extended version of the patterns called out in SKILL.md. Sources: the Tines [AI Agent best-practices article](https://explained.tines.com/en/articles/11644147-best-practices-for-the-ai-agent-action), the official docs, and hard-won operational lessons.

Companion references: [agents.md](agents.md) for the AI Agent action surface itself, [ai-production-patterns.md](ai-production-patterns.md) for production deployment patterns (multi-agent orchestration, cost tracking, AI-on-AI QA), [gotchas.md](gotchas.md) for non-obvious platform behaviors.

## Prompting

### Split instructions by field

- **System instructions** → persona, rules, guardrails, output expectations, domain knowledge. Written once; rarely changes per run.
- **Prompt** (task mode) → the specific job for *this* invocation, with pills referencing upstream data. Changes every run.

If you find yourself referencing pills in the system instructions, that's a smell — it means the "constant" part isn't actually constant and should move to the prompt.

### Use XML tags for structure

Long instructions parse more reliably when segmented. Common tags:

```
<instructions>...</instructions>
<rules>...</rules>
<context>...</context>
<examples>...</examples>
<data>...</data>
<output_format>...</output_format>
```

Not magical — the model has seen enough training data where XML-tagged sections are treated as structured input. Diffs are easier to review.

### Skip pleasantries

"Please help me …" / "Thank you for your assistance" / long greetings cost tokens every run. The model won't do better work because you were polite.

### Give examples, not just rules

One well-chosen example in `<examples>` beats three paragraphs of rules. The model generalizes from format + reasoning shown in the example.

### One agent, one job

Context overload, task interference, and reduced accuracy are the symptoms of an overloaded agent. If your system instructions run to 500+ words covering multiple distinct objectives, split into chained agents via **Send to Story**.

## Tools

### Write tool descriptions for the agent, not for humans

Wrong:
> "User lookup tool"

Right:
> "Use this tool to look up a single user by their email address. Returns the user's ID, full name, department, and manager. If the email is not found, returns an empty object. Only use this tool when you need user metadata beyond what's in the original alert."

The agent reads this description and uses it to decide when and how to call the tool. Vague descriptions → misrouted calls → wasted credits → wrong answers.

### Tighten tool input schemas

Descriptions on each input parameter help, but a restrictive schema (enums, minLength, required fields) prevents the agent from hallucinating arguments in the first place.

### Bundle frequently-used tool sets

If your triage agent always calls "lookup user" → "lookup asset" → "check reputation" in sequence, consider packaging them into one Send-to-Story that does all three and returns a combined object. Fewer tool-calling round-trips = fewer tokens, fewer credits, faster.

### Prefer Send to Story over Custom Tools for reusable behavior

Custom Tools are great for one-off logic scoped to a single agent. Send to Story wins when the same behavior might be used by multiple agents or by Workbench — you define it once, test it independently, and everyone benefits.

## Output schemas

### Always define one, even for "simple" extractions

Without a schema, the agent returns free-form text or a stringified JSON blob that downstream actions have to parse. With a schema:
- The model is constrained to valid output
- Tines auto-parses the output into the emitted event
- Downstream actions reference fields directly via pills
- Schema violations surface as explicit errors

The marginal effort of writing a schema is always less than the debugging effort of handling bad output.

### Use enums to eliminate invalid states

```json
"severity": { "type": "string", "enum": ["low", "medium", "high", "critical"] }
```

The model literally cannot return `"HIGH"` or `"Severe"` — the output is constrained at generation time, not validated after.

### Require reasoning fields

```json
"required": ["classification", "reasoning"],
"properties": {
  "reasoning": { "type": "string", "minLength": 20 }
}
```

Forcing the agent to articulate *why* it chose a classification both improves the classification and gives you an audit trail.

## Debugging

### Read `steps[]` top to bottom

When an agent produces a wrong answer, 90% of the time the cause is visible in the `steps` array: a wrong tool was called, a tool was called with bad args, or the model's "thought" text reveals it misunderstood the task. Fix the tool description, schema, or system instructions — not the model.

### Test with varied inputs

An agent that works on a clean, well-formed alert may fall apart on one with missing fields or unusual values. In test mode, build a set of test records that cover edge cases (empty fields, very long text, weird unicode, etc.).

### Use the **Think** built-in tool

For complex multi-step tasks, attach the Think tool. The model uses it as a scratchpad for planning before acting. Planning-then-acting consistently beats acting-without-planning on long tasks.

## Credit management

### Per-action alerts are the hard stop

Every AI Agent action should have token-usage alerts configured. Options:
- **Notify** — team gets a Slack/email when a threshold is crossed. Good for awareness.
- **Disable action** — action stops emitting until re-enabled. Use this for anything that could loop. It's the only reliable runaway-burn protection.

### Reserve ~10% of monthly credits as buffer

Don't plan to 100% of your allocation — unexpected spikes will overrun it. 10% buffer gives you time to respond without stories silently failing mid-month.

### Monitor `metadata.credits` per run

Every agent event has `metadata.credits`. Pipe this into a dashboard if AI cost is material. You'll quickly see which stories are the biggest consumers and which runs are outliers.

### Check AI credit usage reporting weekly

**Reporting → AI credit usage** shows trends. Rising usage week-over-week on a non-growing story means either the model is retrying more, tools are taking more round-trips, or someone expanded a prompt/tool set. Investigate before the next monthly reset.

### Agentic loops are the biggest risk

Task mode without tools is one-shot and bounded. Task mode *with* tools can loop: think → call → think → call → … An unbounded loop costs real money fast. The mitigations, in order:
1. System instructions explicitly state stop conditions ("Once you have X and Y, produce the final answer. Do not make additional tool calls.")
2. Tight tool descriptions so the agent doesn't retry the same tool variations
3. Per-action "Disable action" alert at a sensible threshold

## Story design

### Keep AI at the edges, not the core

A story where every action is an AI Agent burns credits and introduces variability at every step. Prefer: deterministic actions (HTTP, Event Transform, Condition) do the routine work; AI Agents handle the judgment calls (classification, summarization, natural language I/O). The story is a scaffold; the AI is the reasoning substrate plugged in at the points where reasoning is genuinely needed.

### Keep the test mode path clean

Test mode is where you iterate. If your story has actions that hit external systems in test mode (and those systems can't tolerate a duplicate call), you'll have a bad time. Strategies:
- Gate expensive actions behind a Condition that checks `is_test_mode()` (formula function)
- Use webhook URLs pointing at `httpbin.org` or an internal mock during development
- Treat test records as golden fixtures — once you've got a test event that exercises a tricky code path, keep it and re-run before every deploy

## Working discipline (hard-won from live builds)

### Probe-then-trust

Tines' public docs have multiple divergences from live behavior — see [gotchas.md](gotchas.md). Treat the docs as a starting point, not authoritative. Before trusting an endpoint, action type, or formula name you haven't personally used, **probe the live tenant**: make the call, inspect what actually works. One 10-second probe saves 30 minutes of building on a wrong premise.

Practical version:
- Unknown endpoint? `GET /api/v1/...` it and see what comes back.
- Unknown agent type string? POST with your best guess and read the error. Tines errors usually contain a readable reason.
- Unknown pill syntax? Insert a pill via the UI and inspect the stored string via API.

### UI excursion is a valid tool, not a defeat

Some things are impossible to discover via API alone — canonical pill syntax (`<<...>>`), MCP Server being a Webhook-with-mode, MCP tool nested GroupAgent shape. 60 seconds in the UI answers what 40 minutes of blind probing won't. When you've tried 3+ variations via API and none work, **open the UI, do the thing once, read the state back via API**. Budget 3 UI excursions per full story build as the norm, not the exception.

### Pre-extract fields before the AI Agent prompt

Pill-expanding a full HTTP Request body into an AI Agent prompt pulls every byte of every response — response headers, nested sub-objects, error stacks, everything. Input token counts explode (observed 53,541 → 116 after trimming a single prompt). Always reference specific fields:
```
# Expensive: dumps entire abuseipdb response
AbuseIPDB: <<abuseipdb_lookup.body>>

# Cheap: extracts the 4 fields the AI actually needs
AbuseIPDB: score=<<abuseipdb_lookup.body.data.abuseConfidenceScore>>, reports=<<abuseipdb_lookup.body.data.totalReports>>, country=<<abuseipdb_lookup.body.data.countryCode>>, status=<<abuseipdb_lookup.status>>
```
Input-token reduction is often 50–500×. Credits track proportionally.

### Action logs endpoint > UI Events panel for debugging

Build instinct: when something doesn't work, first call `GET /api/v1/actions/{id}/logs?per_page=5`. The `message` field on an HTTP Request log includes the exact URL and body Tines sent after pill substitution — the single most useful piece of info when diagnosing why a URL hit an endpoint-not-found or an API rejected your params. The UI Events panel is slower and less revealing.
