# Tines Story Optimization Audit

A review procedure for an **existing** storyboard, especially ones using AI Agent actions. Design-time guidance lives in `workflow-design-framework.md`, `agents.md`, `ai-production-patterns.md`, and `best-practices.md` — this file is the audit-time counterpart: point it at a built story, walk the four dimensions in sequence, emit a verdict. Each check cites the principle it enforces rather than restating it.

## Pull the facts first

Drive the audit from the `tines-mcp` read tools, not from eyeballing the canvas:

- `tines_story_overview(story_id)` — one-shot story + actions + recent error logs + reachable resources. Start here for topology and the agent inventory.
- `tines_list_actions(story_id, action_type="AIAgent")` — enumerate AI Agent actions to audit.
- `tines_get_action(action_id)` — full config of one AI Agent: its tool list and prompt. This is where tool counts and orchestrator prompts are read.
- `tines_search_story_contents(query, action_type="AIAgent")` — substring-hunt orchestrator prompts across stories (e.g. search `"first"`, `"then"`, `"step 1"`).

For sub-story topology, follow Send to Story actions: `tines_get_action` exposes the target story ID; recurse with `tines_story_overview` on each.

## 1. Architecture & topology

**Sequential agent chains.** Flag agent → agent → agent with no deterministic step between. Errors compound: each agent amplifies the previous one's misread.
- *Detect:* in `tines_story_overview`, trace links where an AIAgent's receiver is another AIAgent.
- *Fix:* insert a Condition or Event Transform validation between them, or a humanled gate (Page/Workbench), or consolidate to one agent with a tighter task. See `agents.md` §9 (Anti-Patterns), `workflow-design-framework.md` §5 (Hybrid pattern — AI at the edges, deterministic spine).

**Orchestration structure.** Prefer a main story that routes + decides, with sub-stories executing. Independent agents making decisions that affect each other = fragmented topology.
- *Fix:* introduce a coordinating layer in **standard Tines logic** (Condition/Trigger routing), not another agent. See `ai-production-patterns.md` §1 (Lead + Specialized).

## 2. Tooling & capabilities

**Tool count per agent.** Treat 3–5 distinct tools as a soft ceiling, not a hard limit — Tines imposes none. Past it, tool-selection error and latency climb.
- *Detect:* count entries in each AIAgent's tool list via `tines_get_action`.
- *Fix:* split by domain into specialized sub-stories ("Jira ops" vs "Slack notify"); expose each via Send to Story. See `best-practices.md` (One agent, one job; Bundle frequently-used tool sets).

**Tool ambiguity.** Overlapping or confusingly-named tools raise wrong-tool risk.
- *Fix:* remove deprecated versions, rename for clarity, tighten the agent's tool set to only what the job needs. See `best-practices.md` (Write tool descriptions for the agent; Tighten tool input schemas).

## 3. Workflow logic

**Linear task delegation.** An agent told to "do step 1, then 2, then 3" autonomously degrades on multi-step sequential reasoning.
- *Detect:* `tines_search_story_contents` for ordinal/sequencing language in AIAgent prompts.
- *Fix:* convert the steps to deterministic Tines flow; reserve the agent for the decision point only. See `agents.md` §10 (Agent vs Deterministic vs PROMPT), `workflow-design-framework.md` §6.

**Parallelization.** A story that loops a list serially (Send to Story with `loop`, or a serial chain over 50 alerts) leaves throughput on the table — Tines runs one event at a time per action.
- *Fix:* Event Transform **Explode** fans the array into N events that flow downstream concurrently; **Implode** recombines. See SKILL.md "Event Transform modes".
- *Caveat:* every exploded item that reaches an AI Agent runs a full agent loop = N× AI credits. Gate with a Condition filter before the agent (SKILL.md guideline #4) and watch the AI credit pool (`agents.md` §6). Parallel throughput is not free.

## 4. Complexity & necessity

**Substitution test.** For each AI Agent ask: could a regex, Condition, or Event Transform do this reliably?
- *Detect:* read the agent's prompt + output schema via `tines_get_action`. Single-field extraction, fixed classification, or boolean routing rarely needs an agent.
- *Fix:* replace with standard actions where pattern-matching suffices. AI for deterministic work adds cost and latency without value. See `agents.md` §10, `workflow-design-framework.md` §3 (Four-Question framework).

**Orchestrator vs worker.** An agent should be a worker doing one job; orchestration belongs in storyboard logic.
- *Detect:* prompts containing "first do X, then decide Y, then execute Z" (search as above).
- *Fix:* extract the coordination into Tines flow; leave the agent the single decision or transformation. See `ai-production-patterns.md` §1, `best-practices.md` (Keep AI at the edges, not the core).

## Verdict

Report a per-dimension finding, then an overall classification:

1. **Architecture** — centralized vs fragmented topology
2. **Tooling** — tool counts; any ambiguity
3. **Logic** — sequential bottlenecks; parallelization opportunities
4. **Necessity** — agents that should be deterministic actions

- **Optimized** — centralized routing, specialized agents with few tools, parallel execution where items are independent, AI only at decision/transform points.
- **Refactor recommended** — long agent chains, agents with excessive or ambiguous tools, serial loops over independent items, or AI standing in for simple conditional logic.

Cite the specific action IDs and prompts behind each finding so the recommendation is actionable, not abstract.
