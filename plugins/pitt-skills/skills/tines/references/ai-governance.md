# Tines AI Governance

Practical AI governance for security teams deploying AI Agent workflows. Covers Tines' five-component governance framework, the distinction between high-performing and add-on AI adoption, vendor AI risk, and bias considerations. This is the operational accountability layer above the technical patterns in `ai-production-patterns.md`.

This doc draws on Tines' Voice of Security 2026 report (1,800 security professionals surveyed) and Tines' co-founder Thomas Kinsella's articulation of the governance framework.

---

## 1. Why AI Governance Matters Now

The industry has crossed an adoption threshold. From Voice of Security 2026:

| Metric | Finding |
|---|---|
| Security teams using AI in some capacity | ~100% |
| Regularly use AI automation/workflow tools | 77% |
| Top 3 AI use cases | (1) Threat intel and detection, (2) Identity and access monitoring, (3) Compliance and policy writing |
| Workload has increased in the last year | 81% |
| Experienced emotional exhaustion (burnout) | 76% |
| Optimistic AI will create new opportunities | 86% |
| Have formal AI policies in place | 50% |
| Cite governance/compliance as top AI barrier | 35% |
| Top skill required this year | AI literacy and prompt engineering (was not on the radar last year) |

**The takeaways for governance work:**

- AI use is universal but governance maturity is not — half of organizations have no formal policy.
- Governance is the #1 friction point cited for AI adoption (35% — bigger than budget, talent, or technical limitations).
- Shadow AI is real. Even organizations restricting AI find it being used informally.
- The skills required to operate this environment changed dramatically in one year. Governance frameworks need to keep pace.

**The strategic framing:** Governance is not a brake on AI adoption. Governance is what makes AI adoption defensible. Without it, every incident becomes a board-level question of "why did the AI do that?" With it, every incident is a known-shaped event with a clear escalation path.

---

## 2. The Tines AI Governance Framework

Five components, each with concrete implementation expectations:

### 2.1 Approval Gates
Define who can approve AI use cases before they go to production.

- **Workflow authors** can prototype AI Agent workflows in dev/staging without approval.
- **Production deployment** requires approval from a designated AI governance owner (could be Security Architecture, Risk, or a dedicated AI lead).
- **Workflows touching sensitive data** (PII, financial data, executive accounts, OT) require additional approval — typically from Compliance/Privacy/Legal.
- **Workflows triggering destructive actions** (account disable, host isolate, IOC propagation, data deletion) require explicit risk owner sign-off.

Document the approval gates in writing. Auditability of approval decisions is part of the framework — not just auditability of the AI runs themselves.

### 2.2 Risk-Based Prioritization
Not all AI workflows carry the same risk. Classify them and apply governance proportionally.

| Risk Tier | Definition | Governance Required |
|---|---|---|
| **Low** | AI assists humans (suggestions, summaries, drafts). No autonomous action. | Author + peer review |
| **Medium** | AI takes reversible automated actions (close ticket, post comment, label). | Author + governance owner approval; audit trail |
| **High** | AI takes irreversible or partially-reversible actions (modify access, send external comms, update records). | Approval gate + change control + monitoring + 30-day parallel review |
| **Critical** | AI triggers destructive or business-impacting actions (account disable, host isolate, OT touch). | Approval gate + change control + always human-in-loop OR confirmed denylist guardrails + executive risk acceptance |

This is your governance triage. Don't apply Critical-tier process to Low-tier workflows — you'll burn cycles and create governance fatigue. Don't apply Low-tier process to Critical-tier workflows — you'll create the incident that defines your AI program for years.

### 2.3 Change Control
AI workflows in production change in three ways: prompts, models, and tool sets. Each change is potentially behavior-altering and requires governance.

- **Prompt changes** to production AI Agents go through the same change control as code changes — review, staging validation, rollback plan documented.
- **Model upgrades** (e.g., Tines provider swap, custom AI provider migration) require regression testing against the rubric (see `ai-production-patterns.md` Section 8.3).
- **Tool additions** to existing AI Agents trigger re-approval if the new tool changes risk classification.
- **Resource (config) changes** that AI Agents read at runtime are governed at the same level as code changes — not as data updates.

In Tines specifically: Change Control feature on Stories with AI Agent actions is mandatory at Medium tier and above. Test Resources let you validate prompt changes against representative inputs before promoting to production.

### 2.4 Auditability
Every AI action — read, write, comment, recommend, decide — must be traceable. This is non-negotiable.

What an audit log must capture:
- Which AI Agent ran (action ID, version, prompt hash)
- What model was used
- What tools were available and which were invoked
- What input was provided
- What reasoning the agent produced (full chain of thought, not just output)
- What output was emitted
- What downstream actions were taken as a result
- Which human (if any) approved or reviewed
- Token consumption and cost

In Tines: this is partially built in (event log, AI Agent reasoning trace) and partially the operator's responsibility (cost tracking via Records — see `ai-production-patterns.md` Section 4). Treat the audit pipeline as engineering work, not a compliance afterthought.

Retention: align with your overall security audit log retention policy (typically 12+ months; longer for regulated environments). Forward to SIEM for correlation with other security events.

### 2.5 Transparency
AI decisions must be explainable to four audiences:

- **The analyst** working downstream of the AI — needs to understand why the AI did what it did to validate or override.
- **The user/subject** affected by the AI's decision (when applicable) — needs to understand if their account was disabled or their data was inspected.
- **Auditors and regulators** — need to inspect the decision after the fact and reconstruct the reasoning.
- **Executive leadership** — needs to understand systemic AI behavior at a portfolio level, not just incident-level details.

Practical transparency requirements:
- Every AI verdict carries explicit reasoning with cited sources.
- Every AI action records the operator (which AI Agent, which workflow run, on which alert).
- Routine reporting to leadership: monthly AI performance and cost summary by Story.
- Quarterly review of AI decisions that resulted in escalations, errors, or near-misses.

---

## 3. High-Performing vs Add-On AI Adoption

A central distinction from Voice of Security 2026: organizations using AI fall into two camps with very different outcomes.

### Add-On Adoption (most organizations)
- AI is treated as a chatbot or assistant a user can talk to
- Used outside core workflows — analyst opens a separate tool, asks a question, copies result back
- No metrics, no governance, no integration with case data
- Often creates *more* work because of the context-switching tax
- Reports modest or no productivity gain
- Vulnerable to the "shadow AI" problem because adoption is informal

### High-Performing Adoption (the meaningful minority)
- AI is treated as a production system, not an add-on
- Built directly into workflows with deterministic guardrails
- Has clear, measurable outcomes (verdict accuracy, time saved, escalation rate)
- Indicators and KPIs tracked over time; regression detected
- Full controlled system: approvals, change control, audit, cost tracking
- Understands what data the AI touches and where the AI operates
- Reports significant productivity and security improvements

**The governance implication:** Don't measure AI adoption by "are we using it?" — almost everyone is. Measure adoption by which camp you're in. The governance framework above is what moves an organization from add-on to high-performing.

**Self-assessment questions:**
1. Can you name your AI workflows by ID and describe what each does?
2. Can you produce a per-workflow cost report this month?
3. Can you produce a per-workflow accuracy or quality metric this month?
4. Do prompt changes go through change control?
5. Do you have an approved list of which actions AI is permitted to trigger versus restricted from?
6. Are AI decisions audit-traceable end-to-end?

If three or more answers are "no," you're in add-on adoption regardless of how much AI you're using.

---

## 4. AI Bias Considerations

Bias is a governance issue, not just a model issue. Four categories matter:

### 4.1 Data Bias
The training data the model was trained on may not represent your environment. Examples: a model trained primarily on Windows enterprise data may underperform on Mac-heavy environments; a model trained on commercial threat intel may underperform on industry-specific threats.

### 4.2 Modeling Bias
Architectural and design choices in the model itself encode biases. Examples: models trained to be "helpful" may agree with leading prompts; models trained for length may pad reasoning unnecessarily.

### 4.3 Algorithmic Bias
The way the model is invoked introduces bias. Examples: a confidence threshold that's too low produces over-escalation; a default-to-decline behavior on uncertainty produces under-action.

### 4.4 Human Interaction Bias
The way humans frame prompts, design tools, and select training examples encodes their own assumptions. Examples: prompt that asks "is this malicious?" gets different answers than "what's your assessment of this alert?"

### Special case: overfitting on your own security data
If you train or fine-tune a model on your own historical security incidents, you risk overfitting to your past — the model will perform spectacularly on past patterns and struggle on novel attacks. Your past incidents are not representative of all possible incidents. Treat fine-tuned models with the same skepticism you treat new detection rules: validate against held-out data, monitor for drift, retrain on schedule.

### Mitigation
- Use multiple models or providers for high-stakes decisions and require agreement
- Test against diverse representative inputs (red team, synthetic, production-sampled)
- Monitor for production drift — same prompts and model behavior changing over time
- Document known biases and their mitigations as part of the AI workflow's governance record

---

## 5. Vendor AI Risk

A growing governance concern: vendors introduce AI features to existing platforms, sometimes training on your data without explicit consent or transparency.

### Patterns to watch for
- Existing security tool adds an AI feature in an upgrade
- AI feature is opt-in by default but in fine print
- AI processes your data on the vendor's infrastructure
- Vendor retains the right to use your data for model training, testing, or improvement
- Vendor's privacy posture is not transparent or changes in a contract amendment

### Governance response
- Inventory all vendors using AI on your behalf, even AI features in non-AI products
- Demand contractual clarity: what data flows to AI, what model is used, where data resides, retention period, training/improvement use
- Default to **opt out** of vendor AI features that train on your data
- Default to **opt out** of vendor AI features whose data residency you cannot control
- Re-evaluate vendor risk classifications when AI is introduced — a low-risk vendor processing logs becomes a higher-risk vendor when those logs go through an LLM

### CDW-specific considerations
- Tines (your proposed Plan B SOAR) runs AI inference on Tines infrastructure with documented data residency, no logging, and no training use. Validate this in writing during contract negotiation.
- Other vendors in your stack (CrowdStrike, Microsoft Entra, Akamai, ThreatConnect, Polarity, ServiceNow, Proofpoint) have all introduced AI features in recent product cycles. Inventory which are enabled, what data flows where.
- Some vendors will respect customer opt-out from AI training; some will not. Verify in writing.

---

## 6. Practical Governance Checklist

For each AI workflow before production deployment:

- [ ] Workflow has a documented owner
- [ ] Risk tier classified (Low / Medium / High / Critical)
- [ ] Approval obtained at appropriate level
- [ ] Allowed/denied actions documented (deterministic guardrails)
- [ ] Audit log captures all AI decisions with reasoning
- [ ] Cost tracking enabled (per-execution token + cost)
- [ ] Performance metrics defined (accuracy, escalation rate, latency)
- [ ] Change control process applies to prompts, models, tools
- [ ] Rollback plan documented
- [ ] Data sources identified, classification verified, retention aligned
- [ ] Bias mitigations documented (where applicable)
- [ ] Human review path defined for escalations and errors
- [ ] Initial monitoring period defined (30, 60, or 90 days parallel-run)
- [ ] Reporting cadence to leadership defined

---

## 7. Application to CDW

### How this aligns with Project Leap and the Active Defense Grid
The CISO's CAPABILITY > VISIBILITY directive demands automated countermeasures at machine speed. Governance is what makes that defensible. Without it, the first time an AI Agent makes a wrong call on the Active Defense Grid, the program loses credibility.

The governance framework supports the CISO directive by:
- Enabling speed where speed is safe (Low and Medium tier with appropriate guardrails)
- Constraining speed where speed is dangerous (High and Critical tier with human gates)
- Producing the audit trail that turns AI decisions from "the AI did it" into "the AI followed the documented policy and process"

### Stakeholder mapping for CDW

| Governance Component | CDW Owner |
|---|---|
| AI policy authority | CISO (Marcos) — sets tolerance and high-level guardrails |
| Workflow approval (production) | EDA Manager (Rick) — approves Tines workflows for production |
| Compliance / regulatory governance | SRM (Amna, Director) — ensures AI use aligns with CDW's compliance posture |
| Privacy and data classification | SRM team + Privacy / Legal |
| Risk acceptance for Critical-tier workflows | CISO + Director CER (Charity) |
| Audit and reporting | EDA team builds; Compliance reviews |
| Vendor AI risk | SRM (Tammy / Amna for compliance dashboards); EDA owns Tines specifically |

The governance work is not solely EDA's. Position it as a cross-functional artifact — that's how it actually gets adopted at scale.

### What to bring to Charity (Director, CER)
Charity's top pain point is M&A integration at scale. Governance directly addresses this: every acquired company brings its own AI tools, AI policies (or absence of them), and shadow AI. A documented CER-wide AI governance framework gives M&A integrations a clear "what to align to" target — reducing integration time, which is exactly her goal.

Position the governance framework as an M&A integration accelerator, not a SOC compliance overhead. That framing lands better with her stated priorities.

### What to bring to Marcos (CISO) when timing is right
The high-performing vs add-on framing maps directly to his CAPABILITY > VISIBILITY directive. The framework above is what gets CDW into the high-performing camp. Don't bring this to him before you have at least one production AI workflow demonstrating the framework in practice — bring data, not theory.

---

## Related Reference Files

- `workflow-design-framework.md` — Decide whether AI is the right approach for a given stage
- `ai-production-patterns.md` — How to deploy AI workflows well technically
- `agents.md` — The AI Agent action itself
