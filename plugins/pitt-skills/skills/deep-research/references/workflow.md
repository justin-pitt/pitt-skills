# Deep Research Skill Workflow

## Overview

This skill enables comprehensive research on any topic using a configurable provider backend (OpenAI Deep Research, Anthropic Claude with `web_search`, or Perplexity `sonar-deep-research`). It automates the process of enhancing user prompts through interactive clarifying questions, saving the research parameters, and executing the research call.

## When to Use This Skill

Use this skill when:
- User requests in-depth research on a topic
- User asks for analysis, investigation, or comprehensive information gathering
- User wants to explore a subject with web search and structured reasoning
- User provides a brief or vague research query that needs refinement

Example triggers:
- "Research the most effective open-source RAG solutions"
- "I need to understand the current state of quantum computing"
- "Find information about emerging web frameworks"
- "Investigate best practices for distributed systems"

## Skill Workflow

### 1. Receive User Research Prompt

Accept the user's research request. This can be:
- Brief/vague: "Latest AI trends"
- Detailed: "Impact of large language models on software engineering in 2025"
- Technical: "Comparison of vector databases for semantic search"

### 2. Assess Prompt Completeness

Determine if the prompt needs enhancement:
- **Too brief** (< 15 words): Ask clarifying questions
- **Generic** (starts with "what is", "how to", etc.): Ask clarifying questions
- **Detailed/Specific**: Proceed directly to research

### 3. Enhance Prompt (if needed)

Ask user 2-3 focused clarifying questions based on research type:

**For General Research:**
- Scope/Timeframe: Latest (2024-2025), Historical, Specific period?
- Depth level: Executive summary, Technical, Implementation guide, Comparative?
- Focus areas: Performance, Cost, Ease of use, Security, Multiple?

**For Technical Research:**
- Technology scope: Open-source only, Enterprise, Language-specific?
- Key metrics: Speed, Accuracy, Scalability, Resources?
- Use cases: Production, Research, Education, Exploration?

Allow users to:
- Select from predefined options (numbered list)
- Provide custom text input

### 4. Construct Enhanced Prompt

Combine:
1. Original user prompt
2. User's answers as structured research parameters

Example:
```
Original: "Most effective opensource RAG solutions with highest benchmark performance"

Enhanced: "Most effective opensource RAG solutions with highest benchmark performance

Research parameters:
- Latest developments (2024-2025)
- Technical deep dive
- Performance/Benchmarks"
```

### 5. Save Research Prompt

Save the final research prompt to a timestamped file:
- Location: User-specified output directory or current working directory
- Format: `research_prompt_YYYYMMDD_HHMMSS.txt`
- Purpose: Reproducibility and audit trail

### 6. Resolve Provider

Selection priority:
1. `--provider <name>` CLI flag
2. `DEEP_RESEARCH_PROVIDER` env var
3. First provider whose API key is set (`OPENAI_API_KEY` → `ANTHROPIC_API_KEY` → `PERPLEXITY_API_KEY`)

If none of the above resolves to a provider with a configured key, the script exits with an error listing the options.

### 7. Execute Deep Research

Run `deep_research.py` (invoked via `run_deep_research.py`) with:
- Resolved provider and model (provider's default unless `--model` is set)
- Timeout: 1800 seconds / 30 minutes (configurable)
- Web search enabled

Outputs:
- **Deep Research Report**: Comprehensive analysis with citations
- **Web Sources**: Numbered URL list
- **Saved markdown file**: Report + sources + provider/model/date footer

### 8. Present Results

Output to user:
1. Research report (formatted markdown)
2. Referenced web sources (numbered list)
3. Path to the saved markdown report
4. Path to the saved prompt file

## File Structure

```
deep-research/
├── SKILL.md                          # Skill metadata and instructions
├── scripts/
│   └── run_deep_research.py          # Orchestration script (entry point)
├── references/
│   └── workflow.md                   # This file
└── assets/
    └── deep_research.py              # Provider-agnostic research client
```

## Provider Reference

### OpenAI (`--provider openai`)

- Default model: `o4-mini-deep-research`
- API: Responses API (`client.responses.create`) with the built-in `web_search` tool
- Sources: pulled from `web_search_call.action` items
- Env: `OPENAI_API_KEY`
- Dependency: `pip install openai`

### Anthropic (`--provider anthropic`)

- Default model: `claude-opus-4-7`
- API: Messages API with the server-side `web_search_20250305` tool
- Sources: pulled from text-block citations and `web_search_tool_result` blocks
- Env: `ANTHROPIC_API_KEY`
- Dependency: `pip install anthropic`

### Perplexity (`--provider perplexity`)

- Default model: `sonar-deep-research`
- API: `POST https://api.perplexity.ai/chat/completions`
- Sources: pulled from `search_results` (preferred) and `citations` (legacy)
- Env: `PERPLEXITY_API_KEY`
- Dependency: stdlib only (no extra package)

## Key Concepts

### Prompt Enhancement

Enhancement is **smart and optional**:
- Only triggered for brief or generic prompts
- Users can skip with `--no-enhance`
- Questions use closed-list options + custom text input
- Template-aware: Technical vs. General question sets

### Research Parameters

The enhanced prompt includes:
- Original user query with context
- Explicit scope/timeframe
- Depth level expectations
- Specific focus areas

This helps the model deliver more targeted results regardless of provider.

### Reproducibility

Each run saves:
- Complete enhanced prompt (timestamped)
- Markdown report with provider + model + date footer
- Re-runnable via `--prompt-file`

## Integration with Claude

When Claude uses this skill:

1. **Receive research request** → Accept user prompt
2. **Check prompt quality** → Determine if enhancement is needed
3. **Ask questions** → Guide user to refine scope (if needed)
4. **Execute script** → Run `run_deep_research.py` with the enhanced prompt
5. **Present results** → Show report + sources + saved-file paths
6. **Offer follow-ups** → Suggest related research directions or refinements

## Command-Line Interface

```bash
# Auto-detect provider from env keys
python3 run_deep_research.py "Your research prompt"

# Skip enhancement
python3 run_deep_research.py "Brief prompt" --no-enhance

# Force a provider
python3 run_deep_research.py "Prompt" --provider anthropic

# Override model and timeout
python3 run_deep_research.py "Prompt" --model claude-sonnet-4-6 --timeout 3600

# Save prompt to a custom directory
python3 run_deep_research.py "Prompt" --output-dir ./results
```

## Error Handling

The skill handles:
- **No provider resolved** → Lists env-key options and `--provider` choices
- **Missing API key for chosen provider** → Names the env var to set
- **Missing SDK** → Stdlib `ImportError`; user installs the relevant package
- **Missing `deep_research.py`** → Helpful path-search hint
- **Timeout exceeded** → User can increase via `--timeout`
- **Interrupted research** → Saved prompt file available for retry

## Tips for Effective Research

1. **Be specific**: More specific prompts often yield better results even without enhancement
2. **Define scope**: Clarify timeframe and domain (e.g., "2025 trends in quantum computing")
3. **Set expectations**: Indicate desired output format (comparison table, timeline, etc.)
4. **Pick the right provider**:
   - OpenAI Deep Research models are tuned for long, multi-step research; slower but most thorough
   - Claude with `web_search` is fast and produces clean citations inline
   - Perplexity `sonar-deep-research` is purpose-built for cited research synthesis
5. **Review sources**: Check URLs in results for credibility and relevance
6. **Iterate**: Use saved prompts as starting points for follow-up research
