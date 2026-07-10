---
name: sonarqube
description: Use when working on the sonarqube-mcp server or querying SonarQube Server code-quality and security data: projects, issues (bugs/vulns/code smells), quality gates and profiles, measures and metrics, security hotspots, coding rules, compute-engine analysis tasks, analysis history, or project branches and pull requests. Trigger on the sonarqube_ MCP tool prefix, SONARQUBE_* env vars, squ_ user tokens, the SonarQube Web API (/api/issues/search, /api/qualitygates/project_status, etc.), or branch/pullRequest edition gating. Also trigger when giving software engineers security/quality data for their repos and pipelines.
license: MIT
user-invocable: false
---

# SonarQube (sonarqube-mcp)

Read-only MCP server over the **SonarQube Server Web API**. FastMCP server name `sonarqube`, tool prefix `sonarqube_`. Purpose: give software engineers security and code-quality data for their repos and CI pipelines. Targets SonarQube **Server** (not Cloud), so there is intentionally no `organization` param.

## Server at a glance

- **21 read-only tools, zero writes.** The `SONARQUBE_WRITE_TOOLS_ENABLED` gate and `is_write_tools_enabled()` seam exist but no write tool is implemented.
- **Auth:** Bearer user token (`squ_...`) by default (`Authorization: Bearer <token>`, works on Server 10.x+). Set `SONARQUBE_BASIC_AUTH=true` to fall back to HTTP Basic (token as username, empty password) for pre-10.x servers.
- **CA trust:** `_build_verify()` precedence is (1) `SONARQUBE_CA_BUNDLE` PEM, (2) OS trust store via the `truststore` package (so corporate-managed hosts trust their internal root with zero config), (3) certifi. Verification is always on; the code never sets `verify=False`.
- **Transport:** stdio (engineer, default) or `http`. Health `/health`, metrics `/metrics`.
- **URL handling:** `SONARQUBE_URL` is the base with the context path but no `/api` (e.g. `https://sonarqube.example.com/sonar`). The connector does `base_url.rstrip("/")` then appends `/api/...`, so the context path is preserved.

## Example instance notes

- URL `https://sonarqube.example.com/sonar` (context path `/sonar`), version **2026.3.1.123439**, status UP.
- **Developer Edition or higher** (confirmed because `api/project_branches/list` and `api/project_pull_requests/list` are present in `/api/webservices/list`), so the branch/PR tools ship. `SONARQUBE_BRANCH_TOOLS` (default true) is the portability valve to turn them off on Community.
- Token lives in the gitignored repo `.env` (My Account > Security). Never commit it. Validate a live change with a read-only smoke test against the target instance; do not trust self-reports of "N tests passed" (see [[verification-before-completion]]).

## Env vars

| Var | Default | Purpose |
|---|---|---|
| `SONARQUBE_URL` | required | Base URL incl. context path, no trailing `/api` |
| `SONARQUBE_TOKEN` | required | User token (Bearer) |
| `SONARQUBE_BASIC_AUTH` | false | Use HTTP Basic (pre-10.x) |
| `SONARQUBE_CA_BUNDLE` | unset | PEM CA bundle path; overrides OS trust store (never disables verify) |
| `SONARQUBE_BRANCH_TOOLS` | **true** | Register the 2 branch/PR listing tools; set false on Community |
| `SONARQUBE_WRITE_TOOLS_ENABLED` | false | Write gate (seam only; no write tools yet) |
| `MCP_TRANSPORT` / `MCP_PORT` / `MCP_HOST` / `LOG_FORMAT` / `LOG_LEVEL` | stdio / 8080 / 0.0.0.0 / text / INFO | Fleet transport + logging |

## Tool inventory

All read-only. Every call is `GET /api/*` via `connector.get()` (None-valued params dropped). List tools take `limit`/`offset` and return `items`, `total_count`, `has_more`, `next_offset`; list+get tools take `response_format: markdown|json` (default markdown).

| Tool | Purpose | Endpoint | B/PR |
|---|---|---|---|
| `sonarqube_list_projects` | List analyzed projects (`query?`) | `components/search?qualifiers=TRK` (browse perm, not admin) | |
| `sonarqube_search_issues` | Bugs/vulns/code smells (`component_keys[]`, `severities[]`, `types[]`, `statuses[]`, `resolved`) | `issues/search` | yes |
| `sonarqube_get_issue_changelog` | Change history of one issue (`issue`) | `issues/changelog` | |
| `sonarqube_get_quality_gate` | Project gate status + conditions (`project_key`) | `qualitygates/project_status` | yes |
| `sonarqube_list_quality_gates` | Gates defined on the server | `qualitygates/list` | |
| `sonarqube_get_quality_gate_definition` | One gate's conditions (`name` xor `id`) | `qualitygates/show` | |
| `sonarqube_list_quality_profiles` | Profiles (`language?`, `project?`, `defaults?`) | `qualityprofiles/search` | |
| `sonarqube_get_measures` | Measures for one component (`component`, `metric_keys[]`) | `measures/component` | yes |
| `sonarqube_get_component_tree` | Per-child measures (`component`, `metric_keys[]`) | `measures/component_tree` | yes |
| `sonarqube_list_hotspots` | Security hotspots (`project_key`, `status?`) | `hotspots/search` | yes |
| `sonarqube_get_hotspot` | One hotspot's detail (`hotspot`) | `hotspots/show` | |
| `sonarqube_search_rules` | Coding rules (`languages[]`, `types[]`, `severities[]`, `tags[]`, `query?`) | `rules/search` | |
| `sonarqube_get_rule` | One rule detail/remediation (`key`, e.g. `python:S1481`) | `rules/show` | |
| `sonarqube_get_analysis_status` | Current/queued CE task for a component (`component`) | `ce/component` | no |
| `sonarqube_list_analysis_tasks` | CE task activity (`component?`, `status?`, `type?`) | `ce/activity` | |
| `sonarqube_list_project_analyses` | Analysis history + events (`project`, `category?`, `from_date?`/`to_date?`) | `project_analyses/search` | no |
| `sonarqube_get_measures_history` | Metric trend (`component`, `metrics[]`, `from_date?`/`to_date?`) | `measures/search_history` | yes |
| `sonarqube_list_metrics` | Metric catalog | `metrics/search` | |
| `sonarqube_list_project_branches` | Branches (`project`) | `project_branches/list` | Dev+ |
| `sonarqube_list_pull_requests` | PRs (`project`) | `project_pull_requests/list` | Dev+ |
| `sonarqube_system_status` | Instance status + version | `system/status` | |

**B/PR = accepts `branch` / `pull_request`** (mutually exclusive, enforced by `validate_branch_pr`). Only 6 tools support them: `search_issues`, `get_quality_gate`, `get_measures`, `get_component_tree`, `get_measures_history`, `list_hotspots`. Empirically `ce/component` and `project_analyses/search` do NOT accept them (validated against the live catalog; the plan was corrected on this point, docs-over-empirical loses).

## API specifics

- **Pagination:** `limit`/`offset` convert to SonarQube's 1-based `p` (`offset//limit + 1`) and `ps` (`=limit`). Non-paged endpoints (`qualitygates/list`, `qualityprofiles/search`, `qualitygates/show`, `project_branches/list`, `project_pull_requests/list`, `system/status`, `ce/component`, `measures/component`) return everything with an offset-0 envelope.
- **Param encoding:** list params are CSV-joined (`componentKeys`, `severities`, `metricKeys`, etc.); booleans lowercased strings; `from_date`/`to_date` map to the reserved `from`/`to`.
- **Projects use `components/search?qualifiers=TRK`** deliberately (browse permission), avoiding the admin-only `projects/search`.
- **Edition gating:** the branch/PR list tools require Developer Edition+; absent on Community, hence the `SONARQUBE_BRANCH_TOOLS` valve.
- When validating live capability, query `GET /api/webservices/list` (source of truth for which endpoints and params exist on the target version) rather than trusting docs.

## Fleet conventions (adding a tool)

Scaffolded from `mcp-template-build`; same shape as [[cribl]], [[microsoft-graph]], [[databricks]].

1. `src/custom_components/<area>.py` following `example_tool.py`: a `BaseModule` subclass; `_add_tool(fn, ...)` registers under `fn.__name__`, which MUST start with `sonarqube_`.
2. Input is a single Pydantic `BaseModel` (`ConfigDict(extra="forbid")`, `Field(...)`); set all four annotations. List tools add `limit`/`offset` and return the `items`/`total_count`/`has_more`/`next_offset` envelope (helpers `page_index_from_offset`, `paging_envelope` in `pkg/util.py`).
3. List+get tools accept `response_format: Literal["markdown","json"]`.
4. respx-mocked `tests/test_<area>.py`; mock the connector singleton, no live HTTP in unit tests.
5. Pre-push gate: `ruff check src tests` -> `mypy src` (strict) -> `check_pydantic_inputs.py` -> `check_no_print.py` (log to stderr, stdout is JSON-RPC) -> `check_jwt_allowlist.py` -> `pytest -q`.

Python `>=3.12,<4.0`, Poetry. Docker base image `ARG PY` must be bumped by hand (Dependabot cannot parse `FROM image:${ARG}`). Do not run the container conformance Docker gate locally; stdio release is githooks only.
