---
applyTo: "**"
description: Use when the user wants comprehensive web-search-backed research, in-depth investigation, analysis, comparison, or a topic survey. Triggers include "research X", "investigate Y", "comprehensive analysis of Z", "latest developments in", "current state of", or any prompt that requires browsing the web and synthesizing across sources.
---

# Deep Research Skill

## Purpose

Run comprehensive, web-search-backed research on any topic. Provider-agnostic: routes to OpenAI Deep Research, Anthropic Claude (web_search tool), or Perplexity sonar-deep-research based on which API key is configured. Enhances brief prompts via interactive clarifying questions, saves the enhanced prompt and the final report to timestamped files.

## When to Use This Skill

Trigger this skill when:
- User requests research on a specific topic
- User asks for analysis, investigation, or comprehensive information gathering
- User wants exploration of a subject with web search and reasoning
- User provides a brief research query that could be refined
- User wants to understand current state, trends, or comparisons in a field

Example user requests:
- "Research the most effective open-source RAG solutions with high benchmark performance"
- "What are the latest AI developments in 2025?"
- "I need a comprehensive analysis of distributed database systems"
- "Find best practices for implementing vector search"
- "Investigate how AI is impacting the software engineering industry"

## Workflow Overview

```
User Input
    ↓
Assessment: Prompt too brief?
    ↓
YES → Ask Enhancement Questions → Collect Answers
    ↓                               ↓
    └───────→ Construct Enhanced Prompt ←──┘
                    ↓
            Save to Timestamped File
                    ↓
        Resolve Provider (--provider, env, auto-detect)
                    ↓
            Execute deep_research.py
                    ↓
            Output Report + Sources
                    ↓
            Present to User
```

## How Claude Should Use This Skill

**Token efficiency:** Deep research takes 10-20 minutes. The orchestrator runs `deep_research.py` as a blocking subprocess with no intermediate polling, so wait silently for completion and present the final result once.

### Step 1: Accept Research Request

Receive the user's research prompt. This can range from brief ("Latest AI trends") to highly detailed ("Impact of language models on developer productivity with focus on 2024-2025").

### Step 2: Execute the Orchestration Script

Run the skill's main orchestration script:

```bash
python3 scripts/run_deep_research.py "Your research prompt here"
```

To force a specific provider:

```bash
python3 scripts/run_deep_research.py "Your prompt" --provider anthropic
```

### Step 3: Script Execution Flow

The script automatically:

1. **Assesses prompt completeness** (< 15 words or generic opener like "what is", "how to" → enhance)

2. **Asks clarifying questions** (if needed):
   - 2-3 focused questions; technical vs. general template based on keywords
   - Numbered options (1-4) or free-text input
   - Covers: Scope/Timeframe, Depth, Focus areas

3. **Enhances the prompt**: Combines original prompt with answers into structured research parameters

4. **Saves prompt file**: Writes enhanced prompt to `research_prompt_YYYYMMDD_HHMMSS.txt`

5. **Resolves provider** in this order:
   - `--provider <name>` CLI flag
   - `DEEP_RESEARCH_PROVIDER` env var
   - First provider with its API key set: OpenAI → Anthropic → Perplexity
   - Errors out if no provider can be resolved

6. **Executes deep research** with the resolved provider:
   - Default models: `o4-mini-deep-research` (OpenAI), `claude-opus-4-7` (Anthropic), `sonar-deep-research` (Perplexity)
   - Timeout: 1800 seconds / 30 minutes (configurable via `--timeout`)
   - Web search enabled

### Step 4: Present Results to User

The script automatically:
- Saves the report to `research_report_YYYYMMDD_HHMMSS.md`
- Prints the report to the terminal
- Lists web sources (numbered URLs)
- Footer in the saved file records provider and model used

## Providers

| Provider | Default model | Env key | SDK / dependency |
|----------|---------------|---------|------------------|
| `openai` | `o4-mini-deep-research` | `OPENAI_API_KEY` | `openai` Python SDK |
| `anthropic` | `claude-opus-4-7` | `ANTHROPIC_API_KEY` | `anthropic` Python SDK |
| `perplexity` | `sonar-deep-research` | `PERPLEXITY_API_KEY` | stdlib `urllib` (no extra dep) |

Provider-specific notes:
- **OpenAI**: Uses the Responses API with the `web_search` tool. Sources extracted from `web_search_call` actions.
- **Anthropic**: Uses Messages API with the `web_search_20250305` server-side tool. Sources extracted from `citations` blocks and `web_search_tool_result` blocks.
- **Perplexity**: Plain `chat/completions` POST. Sources from `search_results` (preferred) and `citations` (legacy fallback).

SDKs are imported lazily, so you only need to install the provider you use.

## Bundled Resources

### Scripts

#### `scripts/run_deep_research.py` (Main Entry Point)

Orchestration script: prompt assessment, enhancement Q&A, prompt saving, dispatch.

**Options:**
```
python3 run_deep_research.py <prompt> [OPTIONS]
  --no-enhance              Skip enhancement questions
  --provider <name>         openai | anthropic | perplexity (default: auto-detect)
  --model <model>           Override the provider's default model
  --timeout <seconds>       Timeout in seconds (default: 1800)
  --output-dir <path>       Where to save the prompt file
```

#### `assets/deep_research.py`

Provider-agnostic core. Resolves the provider, calls its API, normalizes the report and source list, saves a timestamped markdown file.

**Options:**
```
--provider <name>         Force provider (default: DEEP_RESEARCH_PROVIDER, else auto-detect)
--model <model>           Override the provider's default model
--instructions <text>     Optional system instructions
--prompt-file <path>      Read prompt from a file
--no-sources              Skip source extraction
--timeout <seconds>       Request timeout (default: 1800)
--output-file <path>      Custom output markdown path
--no-save                 Disable automatic markdown saving
```

### References

#### `references/workflow.md`

Detailed workflow doc: enhancement strategy, parameters, provider details, troubleshooting, tips.

## Key Behaviors

### Smart Prompt Enhancement

- Triggers enhancement for prompts with < 15 words or generic openers
- Skips enhancement for detailed prompts
- `--no-enhance` flag disables it entirely
- Template-aware: technical vs. general question sets

### Research Parameters

Enhanced prompts include:
- Original user query with full context
- Scope and timeframe preferences
- Desired depth level (summary, technical, implementation, comparative)
- Specific focus areas (performance, cost, security, etc.)

### Reproducibility

Every run saves the exact prompt to a timestamped file and writes a markdown report with a footer recording provider, model, and date.

## Examples

### Brief Prompt with Enhancement (auto-detected provider)

**User:** "Research the most effective opensource RAG solutions"

**Script:**
1. Detects 12 words + technical keywords → enhancement on
2. Asks 3 technical questions, collects answers
3. Saves enhanced prompt
4. Resolves provider: `OPENAI_API_KEY` set → `openai`
5. Runs `o4-mini-deep-research`
6. Saves report and prints to terminal

### Detailed Prompt, Forced Provider

**User:** "Analyze the impact of large language models on software developer productivity in 2024-2025, focusing on code generation tools, pair programming, and productivity metrics."

```bash
python3 scripts/run_deep_research.py "Analyze the impact of..." --provider anthropic
```

**Script:**
1. 24 words + specific scope → skip enhancement
2. Saves prompt
3. Forces `anthropic` provider, uses `claude-opus-4-7` with web_search
4. Saves report and prints to terminal

## Requirements

- Python 3.10+ (for `dict[...]` and `str | None` syntax)
- API key for at least one supported provider (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `PERPLEXITY_API_KEY`)
- The matching SDK installed for whichever providers you use:
  - `pip install openai` for OpenAI
  - `pip install anthropic` for Anthropic
  - (Perplexity uses stdlib only)
- Internet connection
- 30+ minutes for research completion (configurable timeout)

## Token-Efficient Workflow

Deep research queries take 10-20 minutes. The orchestrator runs as a blocking subprocess; Claude waits silently and presents results once. No periodic polling.

**Generated files:**
- `research_prompt_YYYYMMDD_HHMMSS.txt` — Enhanced research prompt with parameters
- `research_report_YYYYMMDD_HHMMSS.md` — Full report with sources and provider/model footer

**Customization:**
```bash
# Custom output location
python3 assets/deep_research.py --prompt-file prompt.txt --output-file my_research.md

# Disable automatic saving (terminal only)
python3 assets/deep_research.py --prompt-file prompt.txt --no-save

# Force a provider and model
python3 assets/deep_research.py --prompt-file prompt.txt --provider perplexity --model sonar-deep-research
```

## Troubleshooting

### No provider configured

**Error:** `No provider configured. Set --provider, DEEP_RESEARCH_PROVIDER, or one of: OPENAI_API_KEY, ANTHROPIC_API_KEY, PERPLEXITY_API_KEY`

**Solution:**
- Set one of the three API key env vars (or in a `.env` file in the working directory)
- Or pass `--provider <name>` and ensure that provider's key is set
- Or set `DEEP_RESEARCH_PROVIDER=<name>` to pin the choice

### Missing API key for the chosen provider

**Error:** `Missing OPENAI_API_KEY for provider 'openai'.` (or equivalent for Anthropic/Perplexity)

**Solution:**
- Set the matching env var or add it to `.env`
- Or switch providers via `--provider`

### Missing SDK

**Error:** `ModuleNotFoundError: No module named 'openai'` (or `anthropic`)

**Solution:** `pip install openai` or `pip install anthropic` for whichever providers you use. Perplexity needs no extra package.

### deep_research.py Not Found

**Error:** "Could not find deep_research.py"

**Solution:** Ensure the skill is properly installed with assets. The script searches: skill assets folder → current directory → parent directory.

### Research Timeout

**Error:** Request times out after 30 minutes

**Solution:**
- Increase timeout: `--timeout 5400` (90 minutes)
- Simplify the prompt to reduce research scope
- Try a different provider (Anthropic/Perplexity often return faster than OpenAI's deep-research models)
