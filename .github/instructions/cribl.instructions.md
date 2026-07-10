---
applyTo: "**"
description: Use when working on the cribl-mcp server or querying Cribl Stream / Cribl.Cloud config via its management REST API: worker groups (fleets), pipelines, sources (inputs), destinations (outputs), routes, lookups, worker/edge nodes, and system health/metrics. Trigger on the cribl_ MCP tool prefix, CRIBL_* env vars, the leader vs worker-group path model (/master/* vs /m/<group>/*), Cribl.Cloud OAuth client_credentials, the /api/v1 base path, or a Tines platform credential (slug cribl) / global resource cribl_config. Part of an internal MCP fleet.
---

# Cribl (cribl-mcp)

Read-only MCP server over the **Cribl Stream / Cribl.Cloud management REST API** (`/api/v1`). FastMCP server name `cribl_mcp`, tool prefix `cribl_`. Part of an internal MCP fleet (Helm-deployed, registered as the `cribl` block under `servers:` in the fleet values file).

## Server at a glance

- **11 read-only tools, zero writes.** `CRIBL_WRITE_TOOLS_ENABLED` is named in CLAUDE.md as the future gate (cortex-mcp pattern) but is not referenced in code yet.
- **Auth precedence** (resolved in `main._build_fetcher`): (1) `CRIBL_CLIENT_ID` + `CRIBL_CLIENT_SECRET` -> Cribl.Cloud OAuth **client_credentials** (auto-mint/cache/refresh the ~24h token via `CRIBL_OAUTH_TOKEN_URL` / `CRIBL_OAUTH_AUDIENCE`, single-flight `asyncio.Lock`, re-mints 60s before expiry or on 401); (2) `CRIBL_API_TOKEN` -> static Bearer; (3) no auth. The JWT is never parsed (keeps `pyjwt`/`authlib` out of deps).
- **Transport:** stdio (engineer, default) or `http`. In platform/HTTP mode an auth gateway injects `X-Forwarded-User`, which the server trusts. Health `/health` + `/ready`, metrics `/metrics`.
- **Deployment cred:** at runtime the base URL + default group come from a Tines global resource (`cribl_config`), and the Bearer token from a Tines platform credential (slug `cribl`). That wiring lives in the platform layer, not the repo. Target is Cribl.Cloud (OAuth defaults `login.cribl.cloud` / `api.cribl.cloud`).

## Leader vs worker-group model

Cribl runs distributed: a **leader** manages one or more **worker groups (fleets)**.

- **Leader-scoped** endpoints sit under `/master/*` and `/system/*`: `/master/groups`, `/master/groups/<id>`, `/master/workers`, `/system/info`, `/system/metrics`.
- **Group-scoped** endpoints sit under `/m/<group>/...`: `/pipelines`, `/pipelines/<id>`, `/system/inputs`, `/system/outputs`, `/routes`, `/system/lookups`.
- Group-scoped tools default the group via `_resolve_group`: explicit arg, else `CRIBL_DEFAULT_GROUP`, else `"default"`. The server assumes leader/distributed mode.

## Env vars

| Var | Default | Purpose |
|---|---|---|
| `CRIBL_BASE_URL` | none (`https://api.example.com` fallback) | Full base incl. `/api/v1`. Cloud `https://<workspace>-<org>.cribl.cloud/api/v1`; on-prem `https://<leader>:9000/api/v1` |
| `CRIBL_CLIENT_ID` + `CRIBL_CLIENT_SECRET` | unset | client_credentials (primary path) |
| `CRIBL_OAUTH_TOKEN_URL` | `https://login.cribl.cloud/oauth/token` | Token endpoint |
| `CRIBL_OAUTH_AUDIENCE` | `https://api.cribl.cloud` | Token audience |
| `CRIBL_API_TOKEN` | unset | Static Bearer fallback (on-prem: `POST /api/v1/auth/login`) |
| `CRIBL_DEFAULT_GROUP` | `default` | Default group for group-scoped reads |
| `MCP_TRANSPORT` / `MCP_PORT` / `MCP_HOST` / `LOG_FORMAT` / `LOG_LEVEL` | stdio / 8080 / 0.0.0.0 / text / INFO | Fleet transport + logging |

Creds live in the gitignored `.env` (local dev) or a secrets store via CSI (platform). Never commit them. Note the on-disk `.env` header comments are stale (they label client_credentials "NOT WIRED YET" but `src/auth.py` fully implements it since commit `7bfe1d9`); trust CLAUDE.md / README / `.env.example` over the local `.env`.

## Tool inventory

All read-only. Group-scoped tools take `group` (nullable, path-safe, rejects `/` and `\`). List tools take `limit` (1-100, default 20) + `offset` and `response_format: markdown|json`.

| Tool | Purpose | Endpoint | Scope |
|---|---|---|---|
| `cribl_list_worker_groups` | Worker Groups / Fleets (`product`, default "stream") | `GET /master/groups` | leader |
| `cribl_get_worker_group` | One group's config version + deploy status (`id`) | `GET /master/groups/<id>` | leader |
| `cribl_list_workers` | Worker/Edge nodes with health (`group` filters client-side) | `GET /master/workers` | leader |
| `cribl_list_pipelines` | Pipelines in a group | `GET /m/<group>/pipelines` | group |
| `cribl_get_pipeline` | Full pipeline config, ordered functions (`id`) | `GET /m/<group>/pipelines/<id>` | group |
| `cribl_list_sources` | Sources (inputs) | `GET /m/<group>/system/inputs` | group |
| `cribl_list_destinations` | Destinations (outputs) | `GET /m/<group>/system/outputs` | group |
| `cribl_list_routes` | Routes in evaluation order (flattens the routing-table `routes` array) | `GET /m/<group>/routes` | group |
| `cribl_list_lookups` | Lookup tables | `GET /m/<group>/system/lookups` | group |
| `cribl_system_health` | Leader version/build/distributed mode | `GET /system/info` | leader |
| `cribl_system_metrics` | Headline gauges (throughput/CPU/mem; `metric_prefix?`) | `GET /system/metrics` | leader |

The original 6 were `list_worker_groups` / `list_pipelines` / `list_sources` / `list_destinations` / `list_routes` / `system_health`; a later change added the other 5.

## API specifics

- **Response envelope:** Cribl wraps lists in `{"items": [...], "count": N}`. `_get_items` returns the `items` array (tolerates a bare list); `_get_one` normalizes single objects.
- **Routes quirk:** `/m/<group>/routes` returns one routing-table object whose `routes` array holds the ordered rules; `cribl_list_routes` flattens across returned tables.
- **Pagination is client-side.** Config endpoints return the full set in one call, so the server slices `items[offset:offset+limit]` and reports `total`, `has_more`, `next_offset`. `cribl_list_workers` filters by `group` client-side (the leader returns all workers). `cribl_system_metrics` caps JSON output at 200 metrics.
- **Unconfirmed schemas (flagged in code, no live tenant):** `cribl_get_worker_group` deploy/version field names (`configVersion`, `deployingWorkerCount`) vary by Cribl version; `cribl_system_metrics` `/system/metrics` shape is unconfirmed, so `_normalize_metrics` tolerates three payload shapes (`{items:[{name,value}]}`, a bare list, or a flat `{gauge:scalar}` dict) and the JSON response carries a `note` field. Confirm against the in-product API Reference before relying on those fields.
- **401 handling:** `Fetcher` invalidates the provider token and retries once.
- No live tenant is available; all tests mock the Cribl API with respx.

## Fleet conventions (adding a tool)

Scaffolded from `mcp-server-template`; same shape as [[microsoft-graph]], [[sonarqube]], [[databricks]].

1. `src/custom_components/<area>.py` following `example_tool.py`: a `BaseModule` subclass; `_add_tool(fn, ...)` registers under `fn.__name__`, which MUST start with `cribl_`.
2. Input is a single Pydantic `BaseModel` (`ConfigDict(extra="forbid", str_strip_whitespace=True)`, `Field(...)`); set all four annotations. List tools take `limit`/`offset` and `response_format`.
3. respx-mocked `tests/test_<area>.py`; never call a real tenant.
4. Pre-push gate (`git config core.hooksPath .githooks`): `ruff check src tests` -> `mypy src` (strict) -> `check_pydantic_inputs.py` -> `check_no_print.py` (log to stderr; stdout is JSON-RPC) -> `check_jwt_allowlist.py` (new JWT/auth libs go in `[tool.mcp-fleet] jwt-allowlist`) -> `pytest -q`.

Python `>=3.12,<4.0`, Poetry. The platform image is built/signed/pushed by a registry build task which invokes the fleet conformance verifier: operator-run only. Do NOT run the container build or conformance gate locally. Engineer mode is stdio; the release gate for stdio is githooks only.
