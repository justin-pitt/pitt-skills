# Tines Workflow Design Framework

**Pre-build decisions:** how to choose between humanled, deterministic, and agentic patterns for a given workflow — and how to know whether the workflow is even worth automating in the first place.

This is Tines' canonical "intelligent workflow platform" framing as articulated by Thomas Kinsella (co-founder, CCO). It's upstream of the production patterns in `ai-production-patterns.md`. That doc covers *how to do AI right*; this one covers *whether AI is the right tool for this stage at all*.

---

## 1. The Three Workflow Modes

Every workflow stage falls into one of three modes. The biggest mistake teams make is picking one mode and applying it everywhere.

### Humanled
A human follows a procedure manually, applying judgment and context.

| Strengths | Weaknesses |
|---|---|
| Judgment in context | Slow |
| Nuanced understanding | Inconsistent |
| Strategic decisions | Doesn't scale |
| Ambiguous situations | Subject to human error and fatigue |

**Best for:** Strategy, risk assessment, root cause analysis, deep investigation, escalation handling, novel/unprecedented situations, low-volume high-stakes decisions.

### Deterministic
A coded workflow that runs the same way every time. In Tines: a Story built with HTTP Request, Condition, Event Transform, Send to Story, etc.

| Strengths | Weaknesses |
|---|---|
| Reliable | No creativity |
| Predictable | No judgment |
| Scalable to high volume | Brittle when reality varies |
| Auditable | Can't handle novelty |
| Mission-critical fit | Can't adapt context |

**Best for:** Provisioning/deprovisioning, alert routing, deduplication, IOC enrichment with stable APIs, bulk processing, employee lifecycle management, scheduled jobs, anything where "happens the same way every time" is the requirement.

### Agentic
An AI Agent given a goal and tools, operating autonomously within constraints. In Tines: AI Agent action with attached tools.

| Strengths | Weaknesses |
|---|---|
| Easy to deploy | Hallucinates occasionally |
| Adapts to varied input | Output not perfectly consistent |
| Handles long-tail variation | Higher per-execution cost |
| Good at synthesis and research | Harder to fully audit reasoning |
| Powerful for novel decisions | Needs guardrails |

**Best for:** Long-tail alert triage, decisions over varied inputs, content generation, summarization, research/synthesis across many sources, threat containment decisions where context matters, contextual recommendation, gap-filling investigation.

---

## 2. Should You Automate This At All?

Before picking a mode, decide if automation is even appropriate. Five filters:

### Filter 1: Frequency (the XKCD test)
Worth automating if you do it several times a day OR spend a huge amount of time on it occasionally. One-off tasks aren't automation candidates — script them ad-hoc instead.

### Filter 2: Accuracy requirement
If the process must be 100% accurate AND AI is the candidate mode, AI is probably wrong for it. AI hallucinates; deterministic doesn't. Pick deterministic or humanled for must-be-perfect work.

### Filter 3: Feasibility
- Does the platform support the integrations you need?
- Are APIs available (and stable) for the systems involved?
- Is there an MCP server or Connect Flow for the tool?
- Is the data accessible to the workflow at all?

If three of these are "no," the workflow isn't ready for automation regardless of mode.

### Filter 4: Team readiness
You can't automate processes that the owning team isn't ready to give up. Legal, compliance, and HR teams especially need buy-in — automating their work without bringing them along creates more friction than the time it saves.

### Filter 5: Business benefit
Not just "time saved" — also cost, speed, efficiency, and improved security posture. If the only benefit is "this annoying thing goes away," that's fine for low-effort automation; it's not enough to justify a complex hybrid workflow.

---

## 3. The Four-Question Decision Framework

Once you've decided to automate, choose the mode for each stage by asking:

1. **How predictable is the task?** — Predictable steps go deterministic. Variable but bounded steps go agentic. Unpredictable goes human.
2. **What's the tolerance for risk or error?** — Low tolerance = humanled or deterministic. Tolerant with guardrails = agentic.
3. **How much context or creativity is required?** — None = deterministic. Some = agentic. Lots = humanled.
4. **What speed and scale is needed?** — High volume = deterministic. Medium scale with stakes = agentic. Low volume high stakes = humanled.

---

## 4. Mode Selection Matrix

| Criterion | Humanled | Deterministic | Agentic |
|---|---|---|---|
| Predictability | Low | High | Medium |
| Risk tolerance | Low | Low | Medium (with guardrails) |
| Creativity required | High | None | Some |
| Speed/scale | Low volume, high stakes | High volume, low stakes | Medium volume, medium stakes |
| Variability of input | High | Low | Medium |
| Reasoning needed | Strategic | Rule-based | Contextual |

Most stages don't fit one mode cleanly. That's a signal to combine modes, not to force one.

---

## 5. The Hybrid Pattern (Most Real Workflows)

Real workflows interleave all three modes. Each stage of the workflow gets the mode best suited to it.

### Worked Example: EDR Alert Investigation

| Stage | Mode | Why |
|---|---|---|
| Fetch alerts from EDR | Deterministic | Same API call every time |
| Deduplicate against recent history | Deterministic | Memory belongs in a database, not an agent |
| Extract indicators (IPs, hashes, devices) | Deterministic | Field extraction is structured |
| Enrich indicators with TI | Deterministic | API call, structured output |
| Create case + structured fields | Deterministic | Field values are mapped |
| Generate plain-English case summary | Agentic | LLM excels at narrative summarization |
| Run additional contextual investigation | Agentic | Variable inputs, contextual reasoning, gap-filling |
| Update case with findings | Hybrid | Structured fields deterministic, narrative agentic |
| Notify user / collect input | Hybrid | Page/Workbench drives interaction; agent can converse |
| Deep forensic deep-dive | Humanled + co-pilot | Human judgment with AI assistance for tooling |
| Isolate host / lock account | Deterministic, human-triggered | Action is structured; trigger is human (not AI) |
| Discuss with affected user | Humanled | Strategic, contextual, interpersonal |
| Escalate to P1 incident | Humanled | Strategic decision |
| Run RCA / postmortem | Humanled (LLM-assisted) | Complex synthesis, requires judgment |

**Pattern observation:** the early stages (data movement, enrichment) are deterministic; the middle (investigation, synthesis) is agentic; the late stages (decisions, response, postmortem) are human-led with deterministic execution of approved actions.

This pattern generalizes. Most security workflows look like:

```
[Deterministic intake] → [Agentic investigation] → [Human decision] → [Deterministic action] → [Human postmortem]
```

---

## 6. "Just Because You Can With AI Doesn't Mean You Should"

A few specific anti-patterns to avoid:

- **Don't use an agent to hold workflow state.** Use a Records dataset or external database. Agents shouldn't remember things across runs.
- **Don't let an LLM trigger destructive actions unilaterally.** The decision can be agentic; the trigger should be deterministic and human-approved (or at least audited and reversible). Block IPs, isolate hosts, and disable accounts deterministically — the AI's role is to recommend, not to pull the trigger.
- **Don't agentify dedup, enrichment, or routing logic.** These are stable, structured, and don't benefit from reasoning. Deterministic is faster, cheaper, and more reliable.
- **Don't automate things that aren't worth automating.** Frequency filter exists for a reason.
- **Don't lead with "I want to deploy AI."** Lead with the business problem, then pick the right modes for each stage. Teams that lead with "deploy AI" build worse workflows.

---

## 7. Critical Skills for Workflow Builders

Building good workflows isn't about being a great coder. The skills that matter:

### Domain awareness, not deep expertise
You need enough domain knowledge to know what the task actually involves — not the full depth of an SME. The "phishing email" example: the human brain wants to simplify it to "just look at it and the URLs," but real phishing analysis involves DMARC, DKIM, SPF, sentiment, attachments, sender spoofing, impersonation. A workflow builder needs awareness of all those dimensions, not mastery of any.

### Ability to articulate the task
Tines is no-code, but the builder still has to break the task into discrete steps. If you can describe the task in clear sequential prose, you can build it in Tines. If you can't, the task isn't ready for automation regardless of platform.

### Influencing skills (change management)
You will impact other teams. Building a workflow that fires 1,000 alerts at IT or Legal without warning produces friction, not value. Bring stakeholders along: socialize the workflow before building, get buy-in on the process, and educate downstream owners about what to expect.

### Comfort with iteration
Few workflows ship right the first time. Build, deploy, observe, refine. SOPs evolve, alerts evolve, your workflow evolves. Treat the first version as a starting point, not a destination.

### Light technical literacy
Helps to know what an API is, what JSON looks like, how a webhook works, basic regex. None of these are required, but they speed up the build.

---

## 8. Applying the Framework to Common SOC Workflow Categories

### Phishing triage — classic hybrid

- Deterministic intake + IOC extraction + threat-intel enrichment
- Agentic decision (auto-close vs escalate)
- Deterministic execution of containment if escalated
- Humanled review of escalations

This is the workflow shape most likely to demonstrate the "intelligent workflow platform" claim. If a SOAR platform can't cleanly support all three modes in a single workflow, that's a meaningful evaluation finding.

### Brute-force / sign-in anomaly response — mostly deterministic with humanled gate

- Deterministic detection + sign-in confirmation
- Humanled gate for account disable in sensitive cases (e.g., executive accounts)
- Deterministic re-enable after verification

Less AI-heavy. Demonstrates the platform as a deterministic SOAR. AI Agent isn't the differentiator here.

### Threat-intel IOC deployment — fully deterministic

- Validate score → deploy across control planes → confirm
- No AI required; AI would be wrong for this (must be 100% accurate)
- Demonstrates cross-control-plane deterministic orchestration

### Applying the framework to migration planning

The "should we automate this at all?" filters apply to every legacy SOAR playbook you consider migrating:
- Frequency: is it actually used?
- Accuracy: does it require deterministic precision?
- Feasibility: do all the integrations exist in the new platform?
- Team readiness: who owns it; are they aligned?
- Business benefit: what changes if it doesn't get migrated?

Some legacy playbooks won't pass these filters. **Use migration as an opportunity to retire workflows that don't earn their keep.** Don't lift-and-shift everything.

### Applying the framework to a "capability-first" automated-response strategy

A "capability over visibility" mandate doesn't mean everything is agentic. The right framing:
- Detection logic: deterministic (correlation rules, BIOC, etc.)
- Triage decision: agentic (where AI Agent shines)
- Cross-control-plane countermeasure execution: deterministic (predictable actions on triggered conditions)
- Escalation review: humanled
- Strategy and tuning: humanled with AI assistance

Automated response is a hybrid system, not an "AI does everything" system.

---

## 9. Quick Reference Card

When designing a new workflow, walk through these questions in order:

1. **Should this be automated at all?** (frequency × accuracy × feasibility × team-readiness × business benefit)
2. **What stages does the workflow have?** (Decompose into discrete steps)
3. **For each stage:** apply the four-question framework (predictability, risk tolerance, creativity, speed/scale)
4. **Map each stage to a mode:** humanled, deterministic, or agentic
5. **Identify boundaries:** where does one mode hand off to another? Plan the interface (event payload, Page, Case update, etc.)
6. **Build, observe, iterate:** version one is a starting point

If three or more stages of a workflow end up as humanled, the workflow may not be ready to automate. If every stage is deterministic, you don't need AI. If every stage is agentic, you're probably over-using AI and should pull back to deterministic for the predictable parts.

---

## Related Reference Files

- `ai-production-patterns.md` — Once you've decided a stage is agentic, how to deploy it well (multi-agent orchestration, cost tracking, anti-hallucination, validation)
- `agents.md` — The AI Agent action itself (configuration, tool types, modes)
- `platform.md` — Tines core concepts (Stories, Actions, Resources, Cases, Pages, etc.)
- `xsoar-to-tines.md` — Migration patterns including the parallel-run validation period
