#!/usr/bin/env bash
# scripts/build.sh — invokes scripts/build.ps1 via pwsh for CI/non-Windows users
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec pwsh "$SCRIPT_DIR/build.ps1" "$@"
