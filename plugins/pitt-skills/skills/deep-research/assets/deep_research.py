#!/usr/bin/env python3
"""Vendor-agnostic CLI for deep-research-style queries.

Supports OpenAI (Deep Research API), Anthropic (Messages API + web_search tool),
and Perplexity (sonar-deep-research). Provider is auto-detected from env keys
unless --provider or DEEP_RESEARCH_PROVIDER is set.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, List

DEFAULT_TIMEOUT_SECONDS = 30 * 60
DEFAULT_ENV_PATH = Path(".env")

PROVIDER_ENV_KEYS: dict[str, str] = {
    "openai": "OPENAI_API_KEY",
    "anthropic": "ANTHROPIC_API_KEY",
    "perplexity": "PERPLEXITY_API_KEY",
}

DEFAULT_MODELS: dict[str, str] = {
    "openai": "o4-mini-deep-research",
    "anthropic": "claude-opus-4-7",
    "perplexity": "sonar-deep-research",
}

ANTHROPIC_WEB_SEARCH_TOOL = {"type": "web_search_20250305", "name": "web_search"}
ANTHROPIC_DEFAULT_MAX_TOKENS = 32000


@dataclass
class ResearchResult:
    report: str
    sources: List[str] = field(default_factory=list)
    provider: str = ""
    model: str = ""


def load_env(path: Path = DEFAULT_ENV_PATH) -> None:
    """Populate os.environ from a .env file. Never overwrites existing values."""
    if not path.exists():
        return
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if not key or key in os.environ:
            continue
        os.environ[key] = value.strip().strip('"').strip("'")


def select_provider(explicit: str | None) -> str:
    """Resolve provider in priority order: --provider, DEEP_RESEARCH_PROVIDER, key auto-detect."""
    if explicit:
        if explicit not in PROVIDER_ENV_KEYS:
            raise SystemExit(
                f"Unknown provider '{explicit}'. Choose one of: {', '.join(sorted(PROVIDER_ENV_KEYS))}"
            )
        return explicit

    env_choice = os.environ.get("DEEP_RESEARCH_PROVIDER")
    if env_choice:
        if env_choice not in PROVIDER_ENV_KEYS:
            raise SystemExit(
                f"DEEP_RESEARCH_PROVIDER='{env_choice}' is not a known provider. "
                f"Choose one of: {', '.join(sorted(PROVIDER_ENV_KEYS))}"
            )
        return env_choice

    for name in PROVIDER_ENV_KEYS:
        if os.environ.get(PROVIDER_ENV_KEYS[name]):
            return name

    raise SystemExit(
        "No provider configured. Set --provider, DEEP_RESEARCH_PROVIDER, or one of: "
        + ", ".join(PROVIDER_ENV_KEYS.values())
    )


def _dedupe(urls: List[str]) -> List[str]:
    seen: set[str] = set()
    out: List[str] = []
    for url in urls:
        if url and url not in seen:
            seen.add(url)
            out.append(url)
    return out


def run_openai(
    prompt: str,
    *,
    instructions: str | None,
    model: str,
    include_sources: bool,
    timeout: float,
) -> ResearchResult:
    from openai import OpenAI
    from openai._exceptions import OpenAIError

    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"], timeout=timeout)
    payload: dict = {
        "model": model,
        "input": prompt,
        "tools": [{"type": "web_search"}],
    }
    if instructions:
        payload["instructions"] = instructions
    if include_sources:
        payload["include"] = ["web_search_call.action.sources"]

    try:
        response = client.responses.create(**payload)
    except OpenAIError as exc:
        raise SystemExit(f"OpenAI Deep Research request failed: {exc}") from exc

    sources: List[str] = []
    if include_sources:
        for item in response.output:
            if getattr(item, "type", None) != "web_search_call":
                continue
            action = getattr(item, "action", None)
            if action is None:
                continue
            atype = getattr(action, "type", "")
            if atype == "search":
                for src in getattr(action, "sources", None) or []:
                    url = getattr(src, "url", None)
                    if url:
                        sources.append(url)
            elif atype in {"find", "open_page"}:
                url = getattr(action, "url", None)
                if url:
                    sources.append(url)

    return ResearchResult(
        report=(response.output_text or "").strip(),
        sources=_dedupe(sources),
        provider="openai",
        model=model,
    )


def run_anthropic(
    prompt: str,
    *,
    instructions: str | None,
    model: str,
    include_sources: bool,
    timeout: float,
) -> ResearchResult:
    import anthropic

    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"], timeout=timeout)
    request: dict = {
        "model": model,
        "max_tokens": ANTHROPIC_DEFAULT_MAX_TOKENS,
        "messages": [{"role": "user", "content": prompt}],
        "tools": [ANTHROPIC_WEB_SEARCH_TOOL],
    }
    if instructions:
        request["system"] = instructions

    try:
        response = client.messages.create(**request)
    except anthropic.AnthropicError as exc:
        raise SystemExit(f"Anthropic request failed: {exc}") from exc

    report_parts: List[str] = []
    sources: List[str] = []
    for block in response.content:
        btype = getattr(block, "type", None)
        if btype == "text":
            text = getattr(block, "text", "")
            if text:
                report_parts.append(text)
            if include_sources:
                for citation in getattr(block, "citations", None) or []:
                    url = getattr(citation, "url", None)
                    if url:
                        sources.append(url)
        elif btype == "web_search_tool_result" and include_sources:
            for item in getattr(block, "content", None) or []:
                url = getattr(item, "url", None)
                if url:
                    sources.append(url)

    return ResearchResult(
        report="\n".join(report_parts).strip(),
        sources=_dedupe(sources),
        provider="anthropic",
        model=model,
    )


def run_perplexity(
    prompt: str,
    *,
    instructions: str | None,
    model: str,
    include_sources: bool,
    timeout: float,
) -> ResearchResult:
    import json
    import urllib.error
    import urllib.request

    messages: List[dict] = []
    if instructions:
        messages.append({"role": "system", "content": instructions})
    messages.append({"role": "user", "content": prompt})

    body = json.dumps({"model": model, "messages": messages}).encode("utf-8")
    request = urllib.request.Request(
        "https://api.perplexity.ai/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {os.environ['PERPLEXITY_API_KEY']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Perplexity request failed (HTTP {exc.code}): {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Perplexity request failed: {exc}") from exc

    choices = data.get("choices") or []
    report = ""
    if choices:
        message = choices[0].get("message") or {}
        report = (message.get("content") or "").strip()

    sources: List[str] = []
    if include_sources:
        for entry in data.get("search_results") or []:
            url = entry.get("url")
            if url:
                sources.append(url)
        for url in data.get("citations") or []:
            if isinstance(url, str):
                sources.append(url)

    return ResearchResult(
        report=report,
        sources=_dedupe(sources),
        provider="perplexity",
        model=model,
    )


PROVIDERS: dict[str, Callable[..., ResearchResult]] = {
    "openai": run_openai,
    "anthropic": run_anthropic,
    "perplexity": run_perplexity,
}


def run_research(
    prompt: str,
    *,
    provider: str,
    instructions: str | None,
    model: str,
    include_sources: bool,
    timeout: float,
) -> ResearchResult:
    env_key = PROVIDER_ENV_KEYS[provider]
    if not os.environ.get(env_key):
        raise SystemExit(
            f"Missing {env_key} for provider '{provider}'. "
            "Set it in the environment or in a .env file."
        )
    return PROVIDERS[provider](
        prompt,
        instructions=instructions,
        model=model,
        include_sources=include_sources,
        timeout=timeout,
    )


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Run a deep-research query against a configurable provider"
    )
    parser.add_argument("prompt", nargs="?", help="The research question or task")
    parser.add_argument(
        "--provider",
        choices=sorted(PROVIDERS),
        help="Provider to use (default: DEEP_RESEARCH_PROVIDER, else first provider with API key set)",
    )
    parser.add_argument("--instructions", help="Optional system instructions")
    parser.add_argument(
        "--model",
        help="Model to use (default: provider's deep-research default)",
    )
    parser.add_argument(
        "--prompt-file",
        type=Path,
        help="Read the prompt text from a file",
    )
    parser.add_argument(
        "--no-sources",
        action="store_true",
        help="Skip extraction of web sources",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Request timeout in seconds (default: {DEFAULT_TIMEOUT_SECONDS})",
    )
    parser.add_argument(
        "--output-file",
        type=Path,
        help="Save report to this markdown file (default: timestamped name)",
    )
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="Don't save the report to a file",
    )

    args = parser.parse_args(argv)

    if args.prompt_file and args.prompt:
        parser.error("Specify either a positional prompt or --prompt-file, not both.")

    prompt_text = args.prompt
    if args.prompt_file:
        if not args.prompt_file.exists():
            parser.error(f"Prompt file not found: {args.prompt_file}")
        prompt_text = args.prompt_file.read_text()

    if not prompt_text:
        parser.error("Provide a prompt via positional argument or --prompt-file.")

    load_env()
    provider = select_provider(args.provider)
    model = args.model or DEFAULT_MODELS[provider]

    result = run_research(
        prompt_text,
        provider=provider,
        instructions=args.instructions,
        model=model,
        include_sources=not args.no_sources,
        timeout=args.timeout,
    )

    if not result.report:
        print("No textual report returned.")
        return

    if not args.no_save:
        output_file = args.output_file or Path(
            f"research_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
        )
        markdown = result.report
        if result.sources:
            markdown += "\n\n## Sources\n\n"
            for idx, url in enumerate(result.sources, start=1):
                markdown += f"{idx}. {url}\n"
        markdown += f"\n\n---\n\n*Research conducted on: {datetime.now().strftime('%B %d, %Y')}*  \n"
        markdown += f"*Provider: {result.provider}*  \n"
        markdown += f"*Model: {result.model}*  \n"
        output_file.write_text(markdown, encoding="utf-8")
        print(f"Research report saved to: {output_file.absolute()}\n")

    print(f"=== Deep Research Report ({result.provider}/{result.model}) ===\n")
    print(result.report)

    if not args.no_sources and result.sources:
        print("\n=== Sources ===")
        for idx, url in enumerate(result.sources, start=1):
            print(f"{idx}. {url}")


if __name__ == "__main__":
    main(sys.argv[1:])
