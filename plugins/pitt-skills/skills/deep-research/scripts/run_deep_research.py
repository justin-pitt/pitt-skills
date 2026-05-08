#!/usr/bin/env python3
"""Deep Research skill orchestrator.

Enhances brief or generic research prompts through interactive clarifying
questions, saves the enhanced prompt, and dispatches deep_research.py against
the configured provider (OpenAI, Anthropic, or Perplexity).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


ENHANCEMENT_TEMPLATES = {
    "general": {
        "scope": {
            "question": "What is the scope/timeframe for this research?",
            "options": [
                "Latest developments (2024-2025)",
                "Historical overview (all time)",
                "Specific time period (please specify)",
                "No preference",
            ],
        },
        "depth": {
            "question": "What level of detail do you need?",
            "options": [
                "Executive summary",
                "Technical deep dive",
                "Implementation guide",
                "Comparative analysis",
            ],
        },
        "focus": {
            "question": "Any specific aspects or domains to focus on?",
            "options": [
                "Performance/Benchmarks",
                "Cost/Efficiency",
                "Ease of use/Adoption",
                "Security/Privacy",
                "Multiple aspects",
            ],
        },
    },
    "technical": {
        "scope": {
            "question": "Technology scope?",
            "options": [
                "Open-source only",
                "Open-source + enterprise",
                "Language/framework specific",
                "No restriction",
            ],
        },
        "metrics": {
            "question": "What performance metrics matter most?",
            "options": [
                "Speed/Latency",
                "Accuracy/Correctness",
                "Scalability",
                "Resource usage",
                "Multiple metrics",
            ],
        },
        "use_case": {
            "question": "Any specific use cases or applications?",
            "options": [
                "Production deployment",
                "Research/Evaluation",
                "Learning/Education",
                "General exploration",
            ],
        },
    },
}


def is_prompt_too_brief(prompt: str) -> bool:
    """Return True if the prompt is short or starts with a generic opener."""
    word_count = len(prompt.split())
    generic_patterns = ["what is", "how to", "tell me about"]
    is_generic = any(prompt.lower().startswith(p) for p in generic_patterns)
    return word_count < 15 or is_generic


def ask_enhancement_questions(prompt: str) -> str:
    """Ask the user clarifying questions and append answers as research parameters."""
    technical_keywords = [
        "algorithm",
        "framework",
        "benchmark",
        "api",
        "architecture",
        "library",
        "tool",
        "system",
    ]
    is_technical = any(kw in prompt.lower() for kw in technical_keywords)
    template = ENHANCEMENT_TEMPLATES["technical" if is_technical else "general"]

    print("\nLet's refine your research prompt...")
    print(f"Original prompt: {prompt}\n")

    enhanced_parts = []
    for question_data in template.values():
        print(f"\n{question_data['question']}")
        for i, option in enumerate(question_data["options"], 1):
            print(f"  {i}. {option}")

        while True:
            response = input("Your choice (number or custom text): ").strip()
            if response.isdigit() and 1 <= int(response) <= len(question_data["options"]):
                selected = question_data["options"][int(response) - 1]
                if "specify" in selected.lower() or "custom" in selected.lower():
                    custom = input("Please specify: ").strip()
                    enhanced_parts.append(custom if custom else selected)
                else:
                    enhanced_parts.append(selected)
                break
            elif response:
                enhanced_parts.append(response)
                break
            else:
                print("Invalid input. Please try again.")

    enhanced_prompt = f"{prompt}\n\nResearch parameters:\n"
    enhanced_prompt += "\n".join(f"- {part}" for part in enhanced_parts)
    return enhanced_prompt


def save_research_prompt(prompt: str, output_dir: Optional[Path] = None) -> Path:
    """Persist the enhanced prompt to a timestamped file for reproducibility."""
    if output_dir is None:
        output_dir = Path.cwd()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    prompt_file = output_dir / f"research_prompt_{timestamp}.txt"
    prompt_file.write_text(prompt, encoding="utf-8")
    print(f"\nResearch prompt saved to: {prompt_file}")
    return prompt_file


def get_deep_research_path() -> Path:
    """Locate deep_research.py inside the skill or in nearby directories."""
    script_dir = Path(__file__).parent
    skill_assets = script_dir.parent / "assets" / "deep_research.py"
    if skill_assets.exists():
        return skill_assets

    cwd = Path.cwd()
    if (cwd / "deep_research.py").exists():
        return cwd / "deep_research.py"
    if (cwd.parent / "deep_research.py").exists():
        return cwd.parent / "deep_research.py"

    raise FileNotFoundError(
        "Could not find deep_research.py. Ensure it lives in the skill assets folder or current directory."
    )


def run_deep_research(
    prompt_file: Path,
    *,
    provider: Optional[str],
    model: Optional[str],
    timeout: int,
) -> None:
    """Invoke deep_research.py as a subprocess and stream its output."""
    deep_research_py = get_deep_research_path()

    print("\nRunning Deep Research")
    print(f"   Provider: {provider or 'auto-detect'}")
    print(f"   Model: {model or 'provider default'}")
    print(f"   Timeout: {timeout} seconds ({timeout // 60} minutes)")
    print("   Estimated time: 10-20 minutes")
    print("\nResearch in progress... (this may take a while)\n")

    cmd = [
        sys.executable,
        str(deep_research_py),
        "--prompt-file",
        str(prompt_file),
        "--timeout",
        str(timeout),
    ]
    if provider:
        cmd.extend(["--provider", provider])
    if model:
        cmd.extend(["--model", model])

    try:
        subprocess.run(cmd, check=True)
        print("\nDeep Research completed successfully.")
    except subprocess.CalledProcessError as exc:
        print(f"\nDeep Research execution failed with exit code {exc.returncode}")
        raise SystemExit("Research execution failed") from exc
    except FileNotFoundError as exc:
        print(f"\nCould not execute deep_research.py: {exc}")
        raise SystemExit("Missing deep_research.py executable") from exc


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Enhance a research prompt and run a Deep Research query"
    )
    parser.add_argument(
        "prompt",
        nargs="?",
        help="The research question or task (can be brief, will be enhanced)",
    )
    parser.add_argument(
        "--no-enhance",
        action="store_true",
        help="Skip prompt enhancement questions",
    )
    parser.add_argument(
        "--provider",
        choices=["openai", "anthropic", "perplexity"],
        help="Provider to use (default: auto-detect from env keys)",
    )
    parser.add_argument(
        "--model",
        help="Model override (default: provider's deep-research default)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=1800,
        help="Request timeout in seconds (default: 1800)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Directory to save the research prompt file",
    )

    args = parser.parse_args(argv)
    if not args.prompt:
        parser.error("Provide a research prompt as a positional argument.")

    prompt = args.prompt
    if not args.no_enhance and is_prompt_too_brief(prompt):
        prompt = ask_enhancement_questions(prompt)
    elif not args.no_enhance:
        print("\nPrompt looks detailed enough; skipping enhancement questions.")

    prompt_file = save_research_prompt(prompt, args.output_dir)
    run_deep_research(
        prompt_file,
        provider=args.provider,
        model=args.model,
        timeout=args.timeout,
    )


if __name__ == "__main__":
    main(sys.argv[1:])
