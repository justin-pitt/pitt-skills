# Tines AI Production Patterns

Patterns and anti-patterns for deploying AI Agent and AI-augmented workflows in production. Synthesizes lessons from real-world Tines deployments — most notably the Robinhood RAID team's AI-augmented SOC, which has been running production for over a year. These are battle-tested techniques, not theoretical ones.

> **Decision context (read first):** This doc assumes you've already decided that a stage of your workflow should be agentic. If you're still deciding between humanled, deterministic, and agentic, start with [workflow-design-framework.md](workflow-design-framework.md).
>
> **Companion references:** [best-practices.md](best-practices.md) for tactical prompt / tool / debugging discipline, [agents.md](agents.md) for the AI Agent action surface, [gotchas.md](gotchas.md) for non-obvious platform behaviors that affect production deployments.

The principles also apply when building AI workflows on other platforms — but the Tines-specific implementations (Records for state, Send to Story for sub-agents, deterministic guardrails wrapping agent calls) are what make these patterns clean to express here.

## 0. Tines' Official Product Stance: Hybrid Is the Point

Per Tines' Head of Product (public webinar, 2025), Tines explicitly rejects the "deterministic OR agentic" framing as a false dichotomy. Their position:

- AI Agents are a form of automation, not a separate category — they live at the same layer as deterministic Stories
- The real value is in combining the two within a single workflow
- AI Agents *need* deterministic automation around them for consistency on the actions they trigger
- Tines deliberately chose to build agents into the existing diagram rather than as a separate product because they exist at the automation layer of the platform

**Tines is also deliberately agnostic about what "an agent" means.** The product team explicitly cited multiple competing industry definitions (Anthropic's "models using tools in a loop," "digital worker," "anthropomorphic agent," "anything built with LLMs") and chose to support all of them rather than be prescriptive. This means: if you have a specific definition of "agent" in mind, Tines is built to support it — they don't lock you into one paradigm.

**Practical implication for builders:** Don't ask "is this a deterministic Story or an agentic Story?" Ask "which stages of this Story benefit from each pattern?" Most production workflows mix both.

**Future capability worth tracking (Tines product roadmap, publicly hinted):** Tines has indicated they're working on the ability to convert successful agentic Story patterns into deterministic ones — capturing reasoning paths the agent discovered and locking them in as predictable workflows. This is similar to existing Workbench-to-Story conversion. If shipped, this changes the migration approach: use AI Agent during discovery and prototyping, then promote stable patterns to deterministic for cost/consistency benefits.

---

## 1. Multi-Agent Orchestration: Lead + Specialized

**The problem:** A single AI Agent given an entire investigation task with full data access tends to:
- Blow up its context window with irrelevant data
- Wander into investigation paths that aren't useful or supported
- Produce inconsistent results from run to run because the prompt is too broad

**The pattern:** Build a hierarchy.

```
Lead Agent (orchestrator)
  ├── Receives the alert + initial enrichment
  ├── Identifies investigation gaps
  ├── Calls specialized agents to fill specific gaps
  ├── Receives compacted summaries (NOT raw data) back
  ├── Reassesses; loops if more investigation needed
  └── Exits when high confidence reached or max-iteration hit

Specialized Agents (workers, one per investigation domain)
  ├── Email investigation agent
  ├── Endpoint context agent
  ├── User behavior agent
  ├── Threat intel enrichment agent
  ├── (etc.)
  Each agent:
    - Has a tightly scoped tool set
    - Investigates ONE aspect of the alert
    - Returns a compacted summary, not raw query results
```

**Why this works:**
- Each specialized agent has a small, focused context window
- Lead agent's context stays manageable because it gets summaries, not raw data
- Specialization improves quality — an "email agent" with email-specific tools and prompts performs better than a generalist
- Easier to test, swap, and version individual specialized agents

**Tines-specific implementation:**
- Lead Agent = AI Agent action (Task mode) in main Story
- Specialized Agents = separate Stories invoked via Send to Story (configured as tools on the Lead Agent)
- The "compaction" happens because each specialized Story emits its own summarized output event before returning
- Use Custom Tools (action Groups) when the specialized capability is small enough to live in the same Story

**Key configuration:**
- Lead Agent's max iterations: 5–10 (typical), high enough to allow multi-pivot investigations, low enough to bound credit cost
- Each specialized agent's tool list: tightly scoped (e.g., the email agent gets Proofpoint + email-related Graph API tools, nothing else)
- Confidence threshold gate at the lead level: exit cleanly when high confidence reached

---

## 2. Question Bank Pattern (Constrained Reasoning)

**The problem:** Give an AI Agent free reign to investigate however it sees fit, and it will:
- Try to access data sources it doesn't actually have
- Pursue investigation paths that are unreasonable for the environment
- Generate hallucinations about what data should exist

**The pattern:** Provide the agent with a predefined map of investigation questions, each tied to a specific specialized agent.

```
Lead Agent prompt:
  "You are investigating an alert. Below is a list of questions you may ask 
   to investigate. For each gap you identify, select the relevant question(s) 
   and the corresponding specialized agent will answer them.
   
   Questions:
     1. 'What's the user's recent login pattern?' → user_behavior_agent
     2. 'What other emails has this sender sent?' → email_agent
     3. 'What's the reputation of this hash?' → ti_agent
     4. 'Has this host had recent suspicious activity?' → endpoint_agent
     ...
   
   Do not invent questions outside this list."
```

**Why this works:**
- Constrains the agent to reasonable investigation paths
- Prevents "fishing expeditions" that consume credits without progress
- Makes the agent's behavior more deterministic and reviewable
- Easier to audit — every investigation pulls from a known set of questions

**Implementation tip:** Maintain the question bank as a Tines Resource (JSON). Update it as your detection coverage evolves. The Lead Agent's prompt references the Resource so updates flow without re-deploying agents.

---

## 3. Context Window Management

Three rules for keeping AI context windows clean:

### 3.1 Specialized agents compact before returning
A specialized agent might query a SIEM and get back 500 KB of log data. It must compact that into a 1–2 paragraph summary before its result returns to the Lead Agent. The compaction can be a follow-up `PROMPT` formula or a structured-output AI Agent that takes the raw data and produces a fixed-shape summary.

### 3.2 Don't pass full raw data unless necessary
Pass IDs, summaries, and decision-relevant fields. If the Lead Agent needs to dig deeper, it can request more via another specialized agent call.

### 3.3 Strip noise from inputs early
Before alert data even hits the Lead Agent, run a deterministic Event Transform Extract step that pulls out only the fields the AI needs. Drop debug fields, raw protocol details, redundant metadata, etc.

**Tines-specific:**
- Use Event Transform Extract mode aggressively before agent invocations
- Use Records to persist large data that may need to be referenced later, instead of carrying it through events
- Use the `ESTIMATED_TOKEN_COUNT` formula function to gate expensive prompts

---

## 4. Cost Tracking with Records

**The problem:** AI Agent runs consume from a credit pool. Without instrumentation, you don't know what your real cost-per-investigation is until the monthly invoice.

**The pattern:** Pipe token usage into a Records dataset throughout the workflow.

```
After each AI Agent action emits its output:
  Event Transform Extract → pull token_count from agent output
  Run Script (or formula) → calculate $ cost based on model pricing
  Record → write {timestamp, story_id, agent_name, tokens, cost} to a 
           "ai_usage" Records dataset
```

**Why this matters:**
- Real-time visibility into AI cost burn rate
- Per-Story cost attribution lets you optimize the expensive workflows first
- Per-agent cost attribution helps identify which specialized agents are driving cost
- Trendable data for forecasting before tier upgrades or AI commit increases

**Reporting:** Build a dashboard from the Records dataset, or query it with a scheduled Story that writes daily/weekly summaries to Slack or email.

---

## 5. AI-on-AI QA: Supervisor Agent

**The problem:** Even with all the above, AI Agents will occasionally produce output that's wrong, incomplete, or doesn't match expected quality. Catching this purely with humans doesn't scale.

**The pattern:** Run a separate AI Agent (or deterministic check) on every completed AI investigation, evaluating against a rubric.

```
Lead Agent completes investigation →
  Output: {verdict, reasoning, sources, confidence}
↓
Supervisor Agent (separate AI Agent, different prompt) →
  Input: the original alert + the Lead Agent's full output
  Prompt: "Evaluate this investigation against the following rubric:
    - Did the agent cite specific evidence?
    - Did the reasoning follow from the evidence?
    - Are there obvious investigation paths missed?
    - Does the verdict match the evidence weight?"
  Output: {pass/fail, gaps_identified, escalate_to_human?}
↓
If supervisor flags issues → escalate to human
If supervisor passes → proceed with Lead Agent's verdict
```

**Why this works:**
- A second pass with different framing catches errors the first pass missed
- The supervisor doesn't need to redo the investigation — just evaluate the artifact
- Lower cost than human review for high-volume workflows
- Generates training signal for prompt improvement (which cases does the supervisor flag?)

**Variant: deterministic QA agent.** Some checks don't need an LLM. A Tines Story with deterministic logic can verify: "Did the verdict include all required fields?", "Are confidence scores within bounds?", "Did the Lead Agent cite at least one external source?" Use the deterministic version where possible (cheaper, faster, more consistent).

---

## 6. Anti-Hallucination Patterns

### 6.1 "Allow your AI to be wrong"
Tell the AI it can answer "I don't know." Without explicit permission to give up, the AI will fabricate an answer to satisfy the prompt.

```
System instructions:
  "If you cannot answer with high confidence based on the data provided, 
   respond with INSUFFICIENT_DATA and describe what additional data would 
   be needed. Do not guess or fabricate."
```

When the agent returns INSUFFICIENT_DATA, escalate to a human. This becomes a quality signal: high INSUFFICIENT_DATA rates indicate gaps in your tooling, not AI failure.

### 6.2 Output schema as a strong hint
Use the AI Agent action's Output Schema feature to bias the model toward structured output. The schema is **a hint, not strict validation** — the model usually conforms but can return off-enum values, extra fields, missing fields, or renamed fields (`reason` instead of `reasoning`, `safe` instead of `benign`). Plan downstream consumers to tolerate drift: case-insensitive regex on enums, `additionalProperties: true` philosophy, default values for missing fields. See [gotchas.md](gotchas.md#3-output_schema-on-agentsllmagent-is-a-hint-not-an-enforcer).

```json
{
  "type": "object",
  "required": ["verdict", "confidence", "reasoning", "sources"],
  "properties": {
    "verdict": { "enum": ["MALICIOUS", "BENIGN", "INCONCLUSIVE", "INSUFFICIENT_DATA"] },
    "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
    "reasoning": { "type": "string", "minLength": 50 },
    "sources": { "type": "array", "items": { "type": "string" }, "minItems": 1 }
  }
}
```

The `minItems: 1` on sources forces the agent to cite at least one source — a structural defense against unsubstantiated claims.

### 6.3 "Cite your sources" prompt discipline
Every assertion in the AI's reasoning must reference a specific data point from a tool call. Treat the AI like a junior analyst who must show their work. Make this explicit in System Instructions:

```
"For every claim in your reasoning, cite the specific tool call output that 
 supports it. Format: [tool_name: result_field]. Example: [virustotal: 
 detection_count = 47]. Do not make claims you cannot cite."
```

### 6.4 Decompose long prompts
Instead of one mega-prompt, break work into sequential steps with smaller prompts. Long prompts have higher hallucination rates because content "gets lost in the middle." Multi-agent orchestration (Section 1) is one form of this.

### 6.5 Multiple agents cross-validating
For high-stakes decisions, run two independent AI Agent actions on the same input with different prompts and compare outputs. Disagreement = escalate to human.

---

## 7. Memory Architecture: Context Yes, Decisions No

**The principle:** Memory for environmental context is valuable. Memory for prior decisions is dangerous.

### Why prior-decision memory is dangerous
If the AI remembers "last week I classified this user's login pattern as benign," it will be biased toward the same classification this week — even if the user is now compromised. This is the AI version of the analyst anti-pattern: "Analyst A closed this as benign 6 months ago, so I'll close it the same way." That bad call cascades indefinitely.

### What good "memory" looks like
- **Environmental context**: "VPN range = 10.0.0.0/8", "executive accounts = [list]", "scheduled maintenance window = Tuesdays 2 AM" — these are facts about the environment, not decisions.
- **Documented runbooks and policies**: Maintained as Tines Resources, surfaced to AI Agent as context. "Per company policy, NEVER auto-rotate API keys."
- **Reference data**: Allowlists, blocklists, asset inventories. Not "what did we decide last time."

### What bad "memory" looks like
- "Verdict from prior similar alerts"
- "What this user's prior incidents looked like"
- "How analyst X handled this kind of case last month"

If you need pattern-matching on prior cases, do it as an explicit deterministic lookup (with audit trail and review), not as fuzzy AI memory.

### Implementation
- Treat each AI Agent invocation as a fresh sandbox
- Pass environmental context via Resources (read at invocation time)
- Pass alert-specific data via the event payload
- Do not pass prior verdict outcomes for similar cases as inputs to the agent

---

## 8. Validation Patterns

### 8.1 Parallel-run validation (the three-month pattern)
Before full AI cutover, run AI in tandem with humans for an extended period:

```
Phase 1 (initial): AI runs but humans review every AI verdict before action.
Phase 2 (validation, ~3 months): AI runs and a sampled subset of verdicts is human-reviewed.
Phase 3 (production): AI handles auto-close cases; humans review escalations.
```

Track per-decision agreement: of cases where AI said BENIGN and human reviewed, what % did the human agree with? <90% agreement = continue parallel-run; >95% = candidate for auto-close.

This is exactly the migration approach when going from XSIAM (or any current SOAR) to Tines AI Agent. Don't cutover blind.

### 8.2 Detection Health (chaos testing)
Inject malicious events into the environment on purpose. Watch what the AI does:
- Does the detection fire?
- Does the AI classify it correctly?
- Does it escalate when it should?
- Does it auto-close when it shouldn't?

This is repeatable, measurable, and continues to work as your AI prompts and models change. Build it as a recurring Story that runs synthetic tests on a schedule and reports drift.

### 8.3 Rubric-based eval framework
Maintain a corpus of historical alerts with known-correct outcomes. Each prompt change, model upgrade, or workflow refactor runs against the corpus before promotion.

```
Test set: 200 historical alerts, each tagged with expected verdict (malicious/benign/inconclusive)
Test framework: 
  for each alert in test_set:
    run current_workflow(alert)
    compare verdict to expected
  emit metrics: accuracy, false-positive rate, false-negative rate
```

Without this, every change is a leap of faith. Build it before the AI workflow goes to production, not after — Robinhood's RAID team's biggest "would do differently" was building the eval framework after the workflow, not before.

### 8.4 Red team validation
If you have an internal red team, point them at the AI workflows specifically. Their job: find a way to evade or fool the AI triage. Treat findings like any other security finding — track, prioritize, fix.

---

## 9. Deterministic Guardrails Around Agents

**The principle:** Don't trust the AI to never do the wrong thing. Make the wrong thing structurally impossible.

### Pattern 1: Action denylists
Wrap every agent-invokable action in deterministic logic that checks against a hard-coded denylist. Even if the agent decides to invoke "rotate-api-key", the wrapping Tines logic refuses.

```
AI Agent decides: "rotate-api-key for service X"
↓
Send to Story: rotate_api_key
↓
First step in rotate_api_key: Condition action
  IF service IN denylist: emit error, exit
  ELSE: proceed
```

### Pattern 2: Confirmation for destructive actions
Even when AI is confident, require explicit human confirmation for destructive actions (account disable, host isolate, IOC propagation). Use a Page or Slack approval flow.

### Pattern 3: Blast radius limits
Hard-cap how many entities an AI-driven workflow can affect in one run. AI says "block these 500 IPs"? The wrapping logic blocks the first 50 and escalates the rest for review.

### Pattern 4: Mode-based gating
Maintain a tenant-level Resource with operational mode: `production`, `degraded`, `incident`, `learning`. Some agent actions are only allowed in certain modes. During an incident, narrow what the AI can do unilaterally; expand it back when normal.

---

## 10. Webhook Security at Agent Entry Points

**The pattern:** Every Story that invokes an AI Agent should validate its entry point.

```
First action in the Story: Condition action
  IF source != "send_to_story": exit with error
  
This prevents external systems from invoking agent Stories directly via 
the Webhook URL — only internal Tines orchestration can route to them.
```

Why: external webhook invocation skips upstream validation, enrichment, and rate-limiting. AI agent invocation by an attacker who guessed the webhook URL is a real attack vector. This guard removes it.

For Stories that *should* be externally callable, use HMAC verification + IP allowlisting on the Webhook action, never just the secret in the URL path.

---

## 11. Documentation as Context

**The principle:** Well-written runbooks, policies, and procedures become AI context. Treat documentation as engineering artifact.

If your runbooks are detailed, accurate, and current, you can:
- Load them as Tines Resources (JSON or markdown)
- Pass them as System Instructions to AI Agents
- Cite them in AI reasoning as authoritative source

This means: investing in better documentation has compounding returns. You're documenting for both humans and AI simultaneously.

Conversely: stale, inconsistent, or ambiguous documentation poisons AI performance the same way it poisons human onboarding.

---

## 12. Iteration Discipline

### Build the eval framework first
Per Section 8.3 — without it, every change is a leap of faith. Hard to do under time pressure, but critical.

### Modular design for swappability
The AI landscape changes monthly. Today's frontier model is next year's commodity. Design so you can swap:
- Models without re-architecting
- Prompts without redeploying workflows
- Specialized agents independently
- Custom AI providers (BYO API key) without rebuilding

In Tines: every AI Agent action's model is configurable; specialized agents as separate Stories are independently deployable; prompts in Resources can be A/B tested.

### Monitor production drift
Even with no prompt changes, AI behavior drifts as models silently update. Track baseline metrics (accuracy, escalation rate, latency) over time. Alert on regression.

### Red team your own workflows
You build adversarial tests for your detections. Build them for your AI workflows too. Adversarial inputs that would fool the AI but not a human are real findings.

---

## 13. Real-World Benchmarks (Robinhood RAID Public Disclosures)

These are public metrics from one production deployment. Treat as directional, not predictive — your environment varies.

| Metric | Pre-AI | With AI (Robinhood) |
|---|---|---|
| Operating cost (SOC) | Baseline | 27x reduction |
| Critical detection build time | Hours to days | ~5 minutes from intel |
| Coverage | High/critical alerts only | All severity levels |
| Escalation rate | 100% (all human-reviewed) | ~5–10% initially, trending toward 30% |
| Validation period | n/a | 3 months parallel-run before cutover |
| Headcount | ~30 SOC analysts (prior org) | Significantly reduced, augmented with AI tooling |

**What these metrics suggest as targets:**
- Plan for 3+ months of parallel-run validation in any AI-augmented SOC migration
- Expect 5–30% escalation rate — anything outside that range warrants investigation (too low = AI being too aggressive on auto-close; too high = AI not adding value)
- Target full alert coverage (not just high-severity) as the value-add — that's what AI uniquely enables
- Cost reduction of meaningful magnitude is achievable, but is downstream of the first three (parallel-run, escalation tuning, coverage expansion)

---

## 14. Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Fix |
|---|---|---|
| One mega-agent for the whole workflow | Context blowup, inconsistent results | Multi-agent orchestration (Section 1) |
| Free-reign investigation prompt | AI invents data sources, wastes credits | Question bank (Section 2) |
| Passing raw data through the whole chain | Context blowup, slow, expensive | Compact at boundaries (Section 3) |
| No cost instrumentation | Surprise overruns at month-end | Records-based tracking (Section 4) |
| Trusting AI verdicts without QA | Errors compound | AI-on-AI QA (Section 5) |
| AI that can't say "I don't know" | Hallucinations on under-supported decisions | Explicit "INSUFFICIENT_DATA" path (Section 6.1) |
| Free-form AI output | Downstream parsing breaks | Output Schema enforcement (Section 6.2) |
| AI memory of prior decisions | Cascading bad decisions | Sandbox investigations (Section 7) |
| Cutting over without parallel-run | Production risk, no calibration data | 3-month parallel-run pattern (Section 8.1) |
| No eval framework | Every change is a leap of faith | Rubric-based eval (Section 8.3) |
| Trusting AI to not do the wrong thing | Eventually it will | Deterministic guardrails (Section 9) |
| Public webhook on agent Stories | Attack vector | Send-to-Story validation (Section 10) |
| Stale documentation | Bad AI context | Document for AI as well as humans (Section 11) |
| Rigid coupling to specific model/prompt | Can't swap as landscape changes | Modular design (Section 12) |
