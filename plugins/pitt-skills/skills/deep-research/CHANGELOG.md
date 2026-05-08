# Deep Research Skill - Changelog

## Version 3.0 - Vendor-Agnostic Provider Backend

### New Features

#### Multi-provider support
The skill is no longer locked to OpenAI. Three first-class backends:

| Provider | Default model | Env key |
|----------|---------------|---------|
| `openai` | `o4-mini-deep-research` | `OPENAI_API_KEY` |
| `anthropic` | `claude-opus-4-7` | `ANTHROPIC_API_KEY` |
| `perplexity` | `sonar-deep-research` | `PERPLEXITY_API_KEY` |

- Anthropic uses Messages API with the server-side `web_search_20250305` tool; citations are extracted from text-block `citations` and `web_search_tool_result` blocks.
- Perplexity uses the standard `chat/completions` endpoint over stdlib `urllib` (no extra dependency); sources from `search_results` (preferred) and `citations` (legacy).
- OpenAI Deep Research path is unchanged in behavior.

#### Provider auto-selection
Resolution order:
1. `--provider <name>` CLI flag
2. `DEEP_RESEARCH_PROVIDER` env var
3. First provider whose API key is set (OpenAI → Anthropic → Perplexity)

If nothing resolves, the script exits with a clear error listing the options.

#### Lazy SDK imports
`openai` and `anthropic` are imported only when their provider is chosen, so users can install just the SDK they actually use. Perplexity needs no extra package.

#### Report footer
Saved markdown reports now include `Provider: <name>` and `Model: <id>` in the metadata footer, so any saved report tells you exactly which backend produced it.

### New Command-Line Options

```bash
# scripts/run_deep_research.py
--provider <openai|anthropic|perplexity>   # Force provider; default: auto-detect

# assets/deep_research.py
--provider <openai|anthropic|perplexity>   # Force provider; default: auto-detect
# (--model now defaults to the resolved provider's deep-research model, not o4-mini-deep-research)
```

### Breaking Changes

- The implicit `--model o4-mini-deep-research` default in `run_deep_research.py` is gone. The model defaults to the resolved provider's deep-research default. If you scripted `python3 run_deep_research.py "..."` and relied on OpenAI's model, set `OPENAI_API_KEY` (or `--provider openai`) and behavior is unchanged. If multiple keys are set and you want a specific model, pass `--provider` and `--model` explicitly.
- `OPENAI_API_KEY` is no longer required at startup. The matching env key for the resolved provider is required.

### Files Modified

- `assets/deep_research.py` — provider abstraction, three backends, lazy SDK imports, footer metadata
- `scripts/run_deep_research.py` — `--provider` flag, model default deferred to assets script, plain progress messages
- `SKILL.md` — vendor-agnostic description and body, provider table, troubleshooting expanded
- `references/workflow.md` — provider reference section, selection logic, per-provider tips
- `UPSTREAM.md` — divergence from upstream documented

### Migration

| Before | After |
|--------|-------|
| `OPENAI_API_KEY` set, no flags | Same. Auto-resolves to `openai`. |
| `--model o3-deep-research` | Same. Still works for OpenAI. |
| Anthropic key set, want Claude | New: works via `--provider anthropic` or `DEEP_RESEARCH_PROVIDER=anthropic`. |
| Perplexity key set, want Sonar | New: works via `--provider perplexity`. |

---

*Released: 2026-05-08*

---

## Version 2.0 - Token-Optimized with Automatic Markdown Saving

### New Features

#### Automatic Markdown Saving
- Research reports are now automatically saved to timestamped markdown files
- Default filename: `research_report_YYYYMMDD_HHMMSS.md`
- Includes complete report, sources, and metadata footer
- No manual intervention needed

#### Token-Efficient Long-Running Task Handling
- Optimized for 10-20 minute deep research queries
- Synchronous execution (blocking subprocess, no polling)
- No intermediate status checks during wait
- **Token savings**: ~19,000 tokens per research query vs. polling approach

#### New Command-Line Options
```bash
--output-file <path>      # Custom output file path
--no-save                 # Disable automatic markdown saving
```

### Improvements

#### deep_research.py Updates
- Added automatic file saving with timestamped filenames
- Enhanced markdown formatting with metadata footer
- Added datetime import for timestamp generation
- Success confirmation message with absolute file path

#### run_deep_research.py Updates
- Better progress messages with estimated time (10-20 minutes)
- Timeout display in both seconds and minutes
- Completion confirmation message
- Improved error handling

#### SKILL.md Updates
- Added "Token-Efficient Workflow" section explaining optimization
- Documented automatic markdown saving feature
- Added token savings calculations (~20K tokens saved)
- Updated all usage examples
- Enhanced troubleshooting section

### Technical Details

**Token Optimization Strategy:**
- Traditional approach: 40 status checks × 500 tokens = 20,000 tokens
- Optimized approach: Single wait = ~1,000 tokens
- **Savings**: ~95% reduction in token usage during wait

**File Generation:**
- `research_prompt_YYYYMMDD_HHMMSS.txt` - Enhanced prompt with parameters
- `research_report_YYYYMMDD_HHMMSS.md` - Complete markdown report

### Usage Example

```bash
# Basic usage (auto-saves to research_report_20251025_150402.md)
python3 scripts/run_deep_research.py "Art as sense-making"

# Custom output location
python3 assets/deep_research.py --prompt-file prompt.txt --output-file my_research.md

# No automatic saving (terminal only)
python3 assets/deep_research.py --prompt-file prompt.txt --no-save
```

### Breaking Changes
None - all changes are backward compatible. The skill maintains full compatibility with existing workflows.

### Files Modified
- `assets/deep_research.py` - Added automatic markdown saving
- `scripts/run_deep_research.py` - Enhanced progress messages
- `SKILL.md` - Comprehensive documentation updates

---

*Released: October 25, 2025*
