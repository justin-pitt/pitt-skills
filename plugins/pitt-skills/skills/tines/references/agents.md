# Tines AI Agent Action

Deep reference for Tines' AI Agent action — the agentic AI primitive launched in 2025. This is one of the most differentiating features in Tines vs other SOAR platforms and is core to any agentic-SOC build pattern.

> **Decision context (read first):** Before going deep on AI Agent, decide whether agentic is even the right mode for your workflow stage — see `workflow-design-framework.md` for the humanled/deterministic/agentic taxonomy and four-question decision framework.
>
> **Companion reference:** For production deployment patterns (multi-agent orchestration, cost tracking, AI-on-AI QA, anti-hallucination techniques, parallel-run validation, deterministic guardrails) see `ai-production-patterns.md`. This doc covers what the AI Agent action *is*; the patterns doc covers how to deploy it well.

---

## 1. What It Is

The **AI Agent action** is an evolution of Tines' original AI action. It runs an LLM in one of two modes:

- **Task mode** — fully autonomous monologue. The agent receives a prompt, decides which tools (if any) to invoke, observes results, iterates until it reaches a goal, and emits a final event. Used for backend workflows like alert triage decisions, data extraction, content generation.
- **Chat mode** — conversational. The agent powers a Tines Page where end users interact with it in real time. The chat ends when the goal is achieved. Used for support bots, IT assistant pages, security awareness quizzes, knowledge assistants.

Both modes support tools.

---

## 2. Core Concepts

### Deterministic vs Agentic
A deterministic Story follows a fixed graph — same input produces same path and same output. An agentic Story uses AI Agent to make non-deterministic decisions about which actions to take. **Use deterministic for**: known-procedure workflows, anything compliance-bound, anything where you need repeatable outputs. **Use agentic for**: triage decisions on novel inputs, data extraction from unstructured content, classification with subjective judgment, multi-step reasoning where the next step depends on prior results.

### Models
- AI models run on Tines infrastructure with regional data residency
- Data is not logged or used for training
- Model availability varies by region
- Default with tools attached: tenant's "smart model"
- Default without tools: tenant's "fast model"
- **Custom AI providers** supported: bring your own LLM (OpenAI, Anthropic, custom) for compliance, cost, or capability reasons

### Available Models (Tines Cloud Default — verify current list with Tines)
Tines provides a current Anthropic Claude lineup (Sonnet, Haiku) plus Amazon Nova and additional models. The exact list rotates as Anthropic and other providers ship new versions; check the live list at `<tenant>/settings/ai → Providers`.

Confirmed live model string from a recent run (the `meta.model` field returned in an AI Agent task event): `us.anthropic.claude-haiku-4-5-20251001-v1:0`. This is what to expect in practice — a fully versioned, region-prefixed model identifier — rather than a marketing name like "Claude Haiku".

### Bring-Your-Own Model
Available for both cloud and self-hosted customers. Supported providers (per Tines' product team): OpenAI, Google Gemini, open source (Llama), and "essentially any model the average person would want to use." Verify your specific provider in writing during contract negotiation.

### Built-in Tools (no configuration needed)
Two tools are available to every AI Agent automatically:

- **Think** — a scratchpad based on Anthropic's research. The agent writes its plan before acting; available to both Tines-built-in and custom AI providers. Materially improves accuracy on complex multi-step tasks. Attaching Think and instructing the agent to plan first beats letting it act-without-planning on long workflows.
- **Code Analysis** — sandboxed Python for data analysis and chart generation. Useful when the agent needs to crunch numbers, parse CSVs, or produce visualizations from query output without round-tripping through an external tool.

Both are available without consuming a tool slot from the 25-tool-per-agent budget.

---

## 3. Configuration Surface

| Field | Purpose |
|---|---|
| **System instructions** | Set the agent's role, tone, domain, persona, constraints. Like a system prompt. In Chat mode, also defines when the chat ends. |
| **Prompt** | The actual task instructions. Reference upstream event data with `<<action.field>>`. |
| **Tools** | List of tools the agent can invoke. Up to 25 per agent (Custom Tools can hold more inside). |
| **Output schema** | JSON Schema. Used as a **hint** to the model, NOT strictly enforced. Model usually conforms but can return off-enum values, extra fields, missing fields, renamed fields. Plan downstream consumers to tolerate drift (case-insensitive regex on enums, accept additional properties). See [gotchas.md](gotchas.md#3-output_schema-on-agentsllmagent-is-a-hint-not-an-enforcer). |
| **Model** | The LLM to use. Override the default if needed. |
| **Additional request parameters** | (Custom providers only) key-value pairs merged into the provider request at invocation. |

### Best practices for prompts
- Be clear, grammatically correct, detailed
- Don't greet or thank the agent (wastes tokens/credits)
- Reference upstream data explicitly via `<<…>>` rather than describing it
- Use Output schema whenever you'll programmatically consume the result downstream
- Keep System instructions stable across runs; Prompt for the per-invocation payload

### Example: alert triage agent
```
System instructions:
  You are a Tier-1 SOC triage analyst. Your job is to evaluate
  security alerts and decide on a response. Use a neutral, factual
  tone. Cite tool outputs in your reasoning. Never invent indicators
  or context. If uncertain, escalate.

Prompt:
  Triage this alert: <<alert>>
  
  Use available tools to enrich indicators and check user/host context.
  Decide one of: AUTO_CLOSE, ESCALATE_TIER2, AUTO_CONTAIN.
  Format response per the output schema.

Output schema:
  {
    "type": "object",
    "required": ["decision", "confidence", "reasoning", "indicators"],
    "properties": {
      "decision": { "enum": ["AUTO_CLOSE", "ESCALATE_TIER2", "AUTO_CONTAIN"] },
      "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
      "reasoning": { "type": "string" },
      "indicators": { "type": "array", "items": { "type": "string" } }
    }
  }

Tools:
  - ThreatConnect: Search Indicator (template)
  - VirusTotal: Search Hash (template)
  - CrowdStrike: Get Host Status (Send to Story)
  - Entra ID: Get User Sign-in Logs (Send to Story)
  - Custom Tool: "Enrichment Bundle" (group of related lookups)
```

---

## 4. Tool Types

The agent can invoke five categories of tools:

### 4.1 Public Templates
Tines-provided action templates for popular products. Pre-configured shape; you attach a credential. Examples: Slack post-message, Jira create-issue, VirusTotal search-hash.

### 4.2 Private Templates
User/team-defined templates. Build once, reuse across many AI Agents.

### 4.3 Send to Story
Reference an existing Tines Story as a tool. The agent passes a payload, the sub-Story runs, the result returns to the agent.
- Lives in a separate change control scope from the Story containing the AI Agent action
- Supports a **Timeout Duration** option — agent gracefully concludes the tool use if the sub-Story doesn't finish in time
- Best for multi-step workflows the agent shouldn't have to orchestrate itself

### 4.4 Custom Tools
Action Groups built directly inside the same Story as the AI Agent. Defined and configured under one change control scope.
- Useful when the tool needs to dynamically reference upstream values from the parent Story
- Cannot be ungrouped once made (intentional — preserves the tool boundary)
- Good for "enrichment bundle" patterns: combine multiple lookups across different products into one tool the agent invokes

### 4.5 Remote MCP Server Tools
Connect to external **MCP (Model Context Protocol)** servers. Tools exposed by the remote MCP server appear alongside other tools in the agent configuration.
- Multiple MCP transports supported (verify current list with Tines)
- Use for: integrating external systems that already expose MCP, or connecting Tines agents to other AI ecosystems

### Adding tools quickly
You can copy actions from elsewhere in your storyboard and paste them directly onto the AI Agent action — they become tools with the same configuration as the source action.

---

## Output Event Shape

The shape an AI Agent action emits, verified against a live tenant. Field names diverge from what the public docs suggest in a few places — note the differences below.

### Task mode, no tools

```json
{
  "output": "final text, or parsed object when output_schema influenced the model",
  "configuration": {"temperature": 0.2, "prompt": "...resolved prompt string..."},
  "meta": {
    "provider": {"name": "AWS Bedrock", "provider": "aws_bedrock", "provisioning_type": "tines_provisioned"},
    "model": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    "input_tokens": 155,
    "output_tokens": 316,
    "credits_used": 1,
    "remaining_credits": 42,
    "duration": 2.13
  }
}
```

Field-naming notes:
- The metadata container is **`meta`**, not `metadata`.
- Credit counters are **`credits_used`** and **`remaining_credits`**.
- **`duration`** is in seconds, float.
- **`provider`** is a nested object describing which LLM provider Tines invoked.

### Task mode with tools (agentic loop)

Same shape as above plus a `steps` array:

```json
{
  "output": "...",
  "steps": [
    {"role": "assistant", "text": "I'll look up the user first."},
    {"role": "tool", "tool_name": "lookup_user", "tool_input": {"email": "..."}, "tool_output": {...}},
    {"role": "assistant", "text": "Now I'll fetch their tickets."}
  ],
  "configuration": {...},
  "meta": {...}
}
```

`steps[]` is the single most useful artifact for debugging misbehaving agents. Read it top to bottom: 90% of "the agent gave the wrong answer" turns out to be the model picking the wrong tool because the tool description was vague, or passing the wrong argument because the input schema wasn't explicit enough.

### Chat mode

Events emit only when the conversation's defined objective is met or the idle timeout fires. The final event contains the conversation's final state plus metadata. Intermediate turns are visible in the action's Events panel during the conversation but don't emit to downstream actions.

### When invoked via an MCP tool call

Tines MCP tool executions have a **hard 30-second timeout**. If the AI Agent (or the Send-to-Story that wraps it) exceeds 30s, the MCP caller receives:

```json
{"isError": true, "content": [{"type": "text", "text": "Tool execution timeout"}]}
```

The underlying chain continues running and emits events normally — the caller just doesn't get the result synchronously. Send-to-Story-as-a-tool adds invocation overhead on top of the target story's own duration. Design MCP tool chains to complete in well under 30s, or use an async trigger+poll pattern. See [gotchas.md](gotchas.md#14-mcp-tool-execution-has-a-hard-30-second-timeout).

---

## Common Failure Modes and Fixes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Agent loops on the same tool | Tool description is ambiguous or the agent can't tell when it has "enough" info | Tighten the description; add explicit "stop when X" to system instructions |
| Output is a stringified JSON object | No output schema; model returned text that happens to look like JSON | Add output schema; downstream reads it structured |
| Agent hallucinates tool args | Input schema on the tool is too loose | Tighten the tool's input schema; add an example in the description |
| High credit burn per run | Too many tools, too much context, or agent keeps retrying | Split into multiple narrower agents; trim system instructions; check `steps[]` for redundant calls |
| Chat mode never ends | Objective in system instructions is vague | Re-write the objective as a concrete, verifiable condition ("end when user confirms the ticket number") |
| Tool isn't being called | Tool description doesn't match the user's intent vocabulary | Re-word the description to match how the agent "thinks" about the task |
| "AI actions cannot run in a personal team" at run time | Story was created with an unknown `team_id` that silently routed it to a personal team | Verify `team_id` against `GET /api/v1/teams`; recreate or migrate. See [gotchas.md](gotchas.md#4-bad-team_id-on-post-apiv1stories--personal-team-no-error). |

---

## 5. Restrictions and Boundaries

- **Up to 25 tools per agent** (with Custom Tools as a workaround for more)
- **Cannot run in Personal teams** — must be in a regular team
- The agent can only access tools, stories, and credentials explicitly configured. **It will not reach for anything outside its tool list.**
- Stories using AI Agent count toward tenant flow limits (verify exact treatment)
- AI credit usage is logged and visible in the Reporting tab

---

## 6. Credit Model

AI Agent execution consumes from the **AI credit pool** — separate from regular action credits.

### Allocation
- Tenants get a monthly AI credit allowance
- Owners can allocate credits per Team via Settings → AI settings → Providers → Configure → Allocation
- Credit usage report available in tenant Reporting
- Email alerts when usage approaches limit or runs out

### Recommended buffer
Keep ~10% of monthly AI credits as buffer to prevent service interruption.

### Cost optimization
- Combine repeated tool sequences into Custom Tools or Send to Story sub-stories — fewer iterations, lower credit cost
- Use Output schema to short-circuit additional reasoning rounds
- Pre-filter inputs with Condition or Event Transform before invoking the agent — don't pay credits for "obvious" cases
- Use Tines-native models when fit-for-purpose; reserve custom providers for specific needs

---

## 7. Audit and Observability

- **Full audit log** of all tasks the agent performs
- Tenant owners view AI credit usage in Reporting
- The agent's reasoning trace is visible in the action's event history
- Failed agent runs surface like other action failures — configure Monitoring on the agent itself

**Best practice**: enable Monitoring on every AI Agent action so failures are caught promptly. The non-deterministic nature means failures are subtler than deterministic action failures.

---

## 8. Common Patterns

### Triage Decision
Inputs: alert payload + enrichment tools
Output: structured decision (close / escalate / contain) with confidence
Why agent: novel alerts vary; deterministic logic can't cover the long tail

### Data Extraction
Inputs: unstructured content (email, document, freeform text)
Output: structured fields per output schema
Why agent: extraction quality requires reading + reasoning

### Classification with Reasoning
Inputs: artifact + classification taxonomy
Output: category + reasoning + confidence
Why agent: subjective categorization with cited evidence

### Conversational Support Bot (Chat mode)
Inputs: real-time user messages
Output: conversational responses + tool invocations
Why agent: dynamic, multi-turn, goal-driven interaction

### Enrichment with Verdict
Inputs: indicator (hash, IP, domain)
Output: aggregated reputation + verdict + reasoning
Why agent: reasoning over multiple sources is more nuanced than majority vote

### Drafting Content
Inputs: structured data (release notes, support tickets, change logs)
Output: human-readable rewrite (release notes, summaries, customer comms)
Why agent: tone, structure, and audience adaptation

---

## 9. Anti-Patterns

1. **Using AI Agent for deterministic tasks** — if the input → output mapping is fixed, use formulas and HTTP Request. Agents waste credits on solved problems.
2. **No Output schema for downstream-consumed output** — without schema, downstream actions can't reliably parse the result. Always define schema when results feed into further automation.
3. **Tool sprawl** — bolting on every conceivable tool. Each tool slot in the agent's context expands the prompt; more tools = slower decisions and higher cost. Curate tightly.
4. **Holding state in the agent** — agents don't persist between runs. For state, use Records or Resources.
5. **Letting the agent retry forever** — set sensible iteration limits and timeouts on Send to Story tools.
6. **Mixing Chat and Task in one agent** — pick the mode that fits the workflow; don't try to make one agent do both.
7. **Bypassing Condition pre-filters** — filter obvious cases deterministically; only invoke the agent for cases that genuinely need reasoning.

---

## 10. Decision Framework: Agent vs Deterministic vs PROMPT

| Use Case | Approach |
|---|---|
| Fixed input → fixed output | Deterministic Story (HTTP Request + formulas) |
| Single-shot LLM transformation (extract, classify, summarize one thing) | `PROMPT` formula function (in Event Transform) |
| Multi-step LLM reasoning + tool use | AI Agent (Task mode) |
| Multi-turn user interaction | AI Agent (Chat mode) |
| Build-time generation of a Story from natural language | Story copilot (separate feature) |

---

## 11. Open Questions for POC

Things to verify during the POC, with the Tines SE:

1. **Available models per region** — what models are available in our SaaS region (or self-hosted)? Specifically: GPT-4-class, Claude Sonnet/Opus equivalents, latency characteristics.
2. **Custom AI provider configuration** — what's the operational complexity of bringing your own LLM provider key (Anthropic, OpenAI, etc.) vs using Tines' bundled access? Cost trade-off?
3. **AI credit cost per Action execution** — exact credit consumption for typical agent workloads (10 tool calls, 8K-token context). Does it vary by model?
4. **Token caps and context limits** — what's the max context size per agent invocation? Does Tines truncate or fail on overflow?
5. **Audit log retention** — how long are AI Agent reasoning traces retained? Exportable for compliance?
6. **MCP transport support** — which MCP transports are currently supported (HTTP, stdio, others)? Protocol version?
7. **Performance for parallel agent invocations** — can multiple AI Agent actions run concurrently in different Stories without queuing? Throughput limits?
8. **Failure modes** — what happens on model timeout, tool failure, malformed output? Graceful degradation vs hard failure?
9. **Output schema enforcement strictness** — does the agent retry if output doesn't match schema, or fail outright?
10. **Sandboxing posture for self-hosted** — when running self-hosted, does AI Agent traffic still leave the cluster? What's the model-call architecture?

---

## 12. Worked Example: Agentic SOC Triage with Cross-Pillar Containment

Deterministic intake, AI-driven decision, deterministic countermeasures across control planes — the canonical hybrid pattern for an agentic-SOAR build:

```
Alert ingested →
  Deterministic enrichment (Condition + HTTP Request) →
  AI Agent (Task mode):
    System: "You are a SOC triage analyst..."
    Prompt: "Decide response: AUTO_CLOSE / ESCALATE / CONTAIN"
    Tools: [host context, user context, threat intel, similar incidents]
    Output schema: { decision, confidence, reasoning }
  →
  Condition (branch on agent decision):
    AUTO_CLOSE → close alert + log
    ESCALATE → create Case + assign to Tier 2
    CONTAIN → Send to Story: cross-pillar containment
      → Identity sub-Story (disable account)
      → Endpoint sub-Story (isolate host)
      → Network sub-Story (block IP)
      → Application sub-Story (revoke session)
  →
  Audit trail to Records + external TIP
```

The agent makes the judgment call; deterministic sub-Stories execute the countermeasures. This split is what governance and audit teams want: every destructive action has structured, replayable, denylist-protected execution logic, and the AI's reasoning is captured in the event log without being on the destructive path.

**Risk to test before production rollout**: agent decision quality at real volume. If accuracy on known-correct cases drops below ~95%, add stronger deterministic pre-filters or insert a human-in-the-loop checkpoint before destructive actions. The numbers from public deployments (see [ai-production-patterns.md](ai-production-patterns.md) §13) suggest a 3-month parallel-run validation period before cutover.
