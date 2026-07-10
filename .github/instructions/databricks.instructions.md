---
applyTo: "**"
description: Use when working on the databricks-mcp server or running read-only SQL against a Databricks SQL warehouse via the Statement Execution API: list tables, describe a table, or run a guarded SELECT/SHOW/DESCRIBE/WITH query. Trigger on the databricks_ MCP tool prefix, DATABRICKS_* env vars, a SQL warehouse and its default namespace (e.g. main.default), the read-only SQL guard, Databricks App deployment (name must start mcp-), or service-principal OAuth M2M vs PAT auth. This is a data-plane query server, NOT a clusters/jobs/Unity-Catalog management server.
---

# Databricks (databricks-mcp)

Read-only MCP server that runs **SQL against a Databricks SQL warehouse** via the Statement Execution API. FastMCP server name `databricks_mcp`, tool prefix `databricks_`.

**Scope correction:** this is a thin **data-plane query client**, not a management-plane server. There are no clusters, jobs, SQL-warehouse admin, Unity Catalog governance, workspace, DBFS, secrets, or repos tools. It queries whatever warehouse and namespace it is pointed at (default `hive_metastore.default`; example query `SELECT count(*) FROM main.default.events`).

## Server at a glance

- **3 read-only tools, zero writes.** No `DATABRICKS_WRITE_TOOLS_ENABLED` flag exists (by design). If a write tool is ever added, gate it behind an env flag per the template's permission-tier pattern and keep the guard.
- **Two write-prevention layers:** (1) `list_tables`/`describe_table` only interpolate a regex-validated dotted identifier (`_validate_identifier`, up to `catalog.schema.table`), never free text; (2) `assert_read_only()` in `src/databricks_client.py` guards `run_select`: strips `/*...*/` and `--` comments, rejects stacked statements, requires the first word in `{SELECT, SHOW, DESCRIBE, WITH}`, and rejects `INSERT/UPDATE/DELETE/MERGE/DROP/CREATE/ALTER/TRUNCATE/GRANT/REVOKE/COPY/REPLACE` as whole words. On violation it raises `WriteGuardError` and never touches the warehouse.
- **Transport:** stdio (engineer, default) or `streamable-http` (alias `http`, for the Databricks App). Health `/health`, metrics `/metrics`, MCP endpoint `/mcp/`.

## Auth model

Single connector code path with a per-request `AuthProvider` header callable:

- **Local / stdio:** PAT in `DATABRICKS_TOKEN` -> static `Bearer`. Token captured in a closure, never stored as an attribute (kept out of repr/logs). Local-dev only.
- **Databricks App (prod):** no PAT. The runtime injects service-principal **OAuth M2M** creds (`DATABRICKS_CLIENT_ID`/`DATABRICKS_CLIENT_SECRET`); `main._resolve_auth` builds `databricks.sdk.core.Config(host=...)` and passes `cfg.authenticate` as the provider, which returns a fresh Bearer per request and refreshes the ~hourly token. Header fetched per request, never cached on the pooled httpx client. (Fixed in commit `7a4b4c9`: the App uses OAuth M2M, not a PAT.)
- **Claude Code attach:** `scripts/mcp_app_launcher.ps1` mints a fresh U2M token each spawn via `databricks auth token --profile <your-oauth-profile>` and bridges stdio to the App `/mcp` with `npx mcp-remote`.

API surface: **only** the SQL Statement Execution API v2.0 (`POST /api/2.0/sql/statements`, `GET /api/2.0/sql/statements/{id}`). No Jobs 2.1, Unity Catalog REST, or SCIM. Host shape `https://adb-<workspace-id>.<n>.azuredatabricks.net`.

## Env vars

| Var | Default / example | Purpose |
|---|---|---|
| `DATABRICKS_HOST` | `https://adb-<workspace-id>.<n>.azuredatabricks.net` | Workspace URL (not a secret) |
| `DATABRICKS_TOKEN` | unset in prod | PAT, local-dev only. Never log/commit |
| `DATABRICKS_WAREHOUSE_ID` | `<warehouse-id>` | Target SQL warehouse |
| `DATABRICKS_CATALOG` / `DATABRICKS_SCHEMA` | `hive_metastore` / `default` | Default namespace |
| `DATABRICKS_APP_PORT` | injected by App | Bind port (takes precedence over `MCP_PORT`) |
| `DATABRICKS_CLIENT_ID` / `DATABRICKS_CLIENT_SECRET` | injected by App | Service-principal OAuth M2M (consumed by the Databricks SDK) |
| `MCP_TRANSPORT` / `MCP_PORT` / `MCP_HOST` / `MCP_SERVER_NAME` / `LOG_FORMAT` / `LOG_LEVEL` | stdio / 8080 / 0.0.0.0 / databricks_mcp / text / INFO | Fleet transport + logging |

## Tool inventory

All read-only (`readOnlyHint:True`). All take `response_format: markdown|json` (default markdown). Input models forbid extra keys and strip whitespace.

| Tool | Purpose | SQL issued | Key params |
|---|---|---|---|
| `databricks_list_tables` | List tables in a schema | `SHOW TABLES IN <schema>` | `schema_name` (default `hive_metastore.default`, validated dotted identifier) |
| `databricks_describe_table` | Describe a table's columns | `DESCRIBE TABLE <table>` | `table` (required, validated dotted identifier) |
| `databricks_run_select` | Run one arbitrary read-only statement | the statement, post read-only guard | `statement` (1-10000 chars, non-blank) |

## API specifics

- `DatabricksConnector.execute()` posts to `/api/2.0/sql/statements` with `{warehouse_id, statement, catalog, schema, wait_timeout:"25s", format:"JSON_ARRAY"}`, then polls PENDING/RUNNING (default 5 attempts x 2s, httpx timeout 60s). Any non-`SUCCEEDED` terminal state raises `DatabricksError` with the `status.error.message`.
- Result shape: columns from `manifest.schema.columns[].name`, rows from `result.data_array` (empty list if absent). Returned to tools as `{"columns": [...], "rows": [[...]]}`.
- **Poll budget is bounded** (~25s inline wait + ~10s polling). Queries that exceed it raise `DatabricksError` rather than waiting longer. This is a design limit, not a bug: for long queries, narrow the query.
- Default namespace `hive_metastore.default` is the legacy Hive metastore, not a Unity Catalog catalog. Pass a fully-qualified `catalog.schema.table` to reach elsewhere.

## Deployment

Primary prod target is a **Databricks App** (`app.yaml` runs `python src/main.py` with `MCP_TRANSPORT=streamable-http`, `LOG_FORMAT=json`; the runtime injects `DATABRICKS_APP_PORT` + OAuth M2M creds). Deploy with `databricks apps create mcp-databricks` (the App resource name MUST start with `mcp-` or the AI Playground won't list it), `databricks sync`, `databricks apps deploy`. The caller IP must be on the workspace IP access list or the App returns 403. `app.yaml` + `requirements.txt` (kept in sync with pyproject by hand) drive the App build. Also runnable as stdio (engineer mode) or a Streamable-HTTP container.

## Fleet conventions (adding a tool)

Scaffolded from `mcp-template-build`, conforms to the fleet conformance contract. Same shape as [[microsoft-graph]], [[sonarqube]], [[cribl]].

1. Subclass `BaseModule` (or extend `TablesModule`) in `src/custom_components/`; `discover_modules()` instantiates each subclass at startup. Register under `fn.__name__`, which MUST start with `databricks_`.
2. Input is a single Pydantic `BaseModel` (`ConfigDict(extra="forbid")`, `Field(...)`); set all four annotations. Validate any identifier interpolated into SQL with `_validate_identifier`; never interpolate raw user free-text into a statement.
3. respx-mocked `tests/test_<area>.py` (mock `conn.execute`); no live warehouse in unit tests.
4. Pre-push gate: `pytest -v` + `ruff check src tests` + `mypy src` (strict) + `check_pydantic_inputs.py src` + `check_no_print.py src` (stdout is the JSON-RPC channel; log to stderr) + `check_jwt_allowlist.py`.

Python `>=3.12,<4.0`, Poetry for dev (pip + `requirements.txt` for the App/Docker build). Do not run the container conformance Docker gate locally; stdio release is githooks only.
