---
name: microsoft-graph
description: Use when working on the graph-mcp server or querying the Microsoft Graph / Entra ID identity plane: users, groups, sign-in and audit logs, risky users and risk detections (Identity Protection), app registrations, service principals, directory roles, PIM, conditional access, or devices. Trigger on the graph_ MCP tool prefix, GRAPH_* / AZURE_* env vars, DefaultAzureCredential, Graph app-only permissions (User.Read.All, RoleManagement.Read.Directory, etc.), OData $filter/$select/$skiptoken paging, or adding a tool to the graph-mcp fleet server. Also trigger for a Tines-hosted read mirror of the Graph API.
license: MIT
user-invocable: false
---

# Microsoft Graph (graph-mcp)

Read-heavy MCP server wrapping **Microsoft Graph v1.0** for the Entra ID identity plane. FastMCP server name `graph_mcp`, tool prefix `graph_`. Graph identity plane only. Azure resource RBAC (ARM `management.azure.com`) is explicitly out of scope.

## Server at a glance

- **41 tools across 10 modules.** 31 read, 10 write. Writes register only when `GRAPH_WRITE_TOOLS_ENABLED=true`.
- **Auth:** `azure.identity.aio.DefaultAzureCredential`, app-only (application permissions), client-credentials flow, scope `https://graph.microsoft.com/.default`. In stdio it resolves the client secret from `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`; on the platform it auto-resolves Workload Identity Federation (leave the secret unset). Token cached in `GraphFetcher`, refreshed within 300s of expiry.
- **Transport:** stdio (engineer mode, default) or `http` (platform, Helm-deployed). Health `/health`, metrics `/metrics`.
- **Base URL:** `GRAPH_BASE_URL` default `https://graph.microsoft.com/v1.0`. Every tool uses **v1.0** (including PIM and Identity Protection; the design doc's `/beta` note is stale).
- **Tines mirror:** a Tines-hosted read-only v1 native-REST wrapper of the Graph API exists, backed by a platform credential (slug `microsoft_graph`). It is hand-built and independent of this repo; adding a Graph read tool here does not add it to the mirror. See [[tines]] for the in-story MCP build method.

## Env vars

| Var | Default | Purpose |
|---|---|---|
| `GRAPH_BASE_URL` | `https://graph.microsoft.com/v1.0` | Graph endpoint; override for sovereign clouds (`graph.microsoft.us/v1.0`) |
| `GRAPH_SCOPES` | `https://graph.microsoft.com/.default` | Passed as a single scope to `get_token` (not split on commas) |
| `GRAPH_WRITE_TOOLS_ENABLED` | unset (false) | Write gate. Must equal `true` (case-insensitive) to register write tools |
| `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` | required in stdio | azure-identity standard app-registration creds |
| `AZURE_CLIENT_SECRET` | optional | Leave unset on the platform (prefer Workload Identity Federation) |
| `MCP_TRANSPORT` / `MCP_PORT` / `MCP_HOST` / `LOG_FORMAT` / `LOG_LEVEL` | stdio / 8080 / 0.0.0.0 / text / INFO | Fleet transport + logging |

Creds live in the gitignored `.env` (stdio) or a secrets store / federated identity (platform). Never commit or log a secret.

## Tool inventory

Reads are always on. Writes (marked **W**) need `GRAPH_WRITE_TOOLS_ENABLED=true`. All list tools return the envelope `{count, offset, items, has_more, next_offset, cap_hit}`; every response is wrapped by `create_response` as a JSON string (`{"data": ...}` or `{"error": "..."}`).

**Users** (`users.py`)
- `graph_user_get` (`identifier`, `select[]`) look up one user by id / UPN / onPremisesSamAccountName (Sam falls back to `$filter`).
- `graph_user_search` (≥1 of `display_name`/`upn`/`mail` startswith, `job_title`/`department` eq; AND'd) search users.
- `graph_user_signins` (`user_id_or_upn`, `start_time`/`end_time` ISO-8601, `status`) sign-in logs. Needs Entra ID **P1+**.
- `graph_user_groups` (`user_id_or_upn`, `transitive`, `security_only`) memberships (`security_only` is a post-slice client filter).
- `graph_user_disable` **W** set `accountEnabled=false` (containment).
- `graph_user_revoke_sessions` **W** `revokeSignInSessions` (invalidate refresh tokens).
- `graph_user_reset_password` **W** (`password` min 12, `force_change_on_next_signin`) caller supplies the password; not echoed.

**Groups** (`groups.py`)
- `graph_group_members` (`group_id`, `transitive`).
- `graph_group_add_member` **W** via `members/$ref`; idempotent (dup returns `already_member:true`).
- `graph_group_remove_member` **W**.

**Audit** (`audit.py`)
- `graph_audit_logs_search` (`actor_upn`/`target_upn`/`activity`/`category`/`result`, `start_time`/`end_time`; ≥1 filter beyond the window) `/auditLogs/directoryAudits`.

**Identity Protection** (`identity_protection.py`) all need Entra ID **P2**
- `graph_risky_users_list` (`risk_state`/`risk_level`/`user_principal_name`).
- `graph_risky_user_history` (`user_id`).
- `graph_risk_detections_list` (`user_id_or_upn`, `risk_event_type`/`risk_level`/`risk_state`, window; ≥1 filter beyond window; time field `detectedDateTime`).

**Applications** (`applications.py`)
- `graph_app_list` (`display_name` startswith, `app_id` eq).
- `graph_app_get` (`identifier`, `by_app_id`).
- `graph_app_credentials` (`app_id` object id) password+key credentials with computed `expired` flag.
- `graph_app_owners` (`app_id`).
- `graph_app_revoke_credential` **W** (`app_id`, `key_id`, `reason`) `removePassword` (certs out of scope).

**Service Principals** (`service_principals.py`)
- `graph_sp_list` / `graph_sp_get` (`sp_id` xor `app_id`).
- `graph_sp_app_role_assignments` (`sp_id`) `appRoleAssignedTo` (roles granted TO this SP, inbound).
- `graph_sp_oauth2_grants` (`sp_id`) delegated grants.
- `graph_sp_owners` (`sp_id`).
- `graph_sp_credentials` (`sp_id`) with `expired` flag.
- `graph_sp_remove_app_role_assignment` **W** (`sp_id`, `assignment_id`, `reason`).
- `graph_sp_revoke_credential` **W** (`sp_id`, `key_id`, `reason`).

**Directory Roles** (`directory_roles.py`) no write tier
- `graph_directory_role_list` (`definitions`) activated roles or all definitions.
- `graph_directory_role_members` (`role_id` = activated-role object id; unactivated returns 404).
- `graph_directory_role_assignments` (`role_definition_id`/`principal_id`; ≥1 filter) `/roleManagement/directory/roleAssignments`.

**PIM** (`pim.py`)
- `graph_pim_eligible_roles` / `graph_pim_active_roles` / `graph_pim_activation_history` (`principal_id`, `role_definition_id`).
- `graph_pim_activate` **W** (`principal_id`, `role_definition_id`, `justification`, `duration_hours` 1-24, `start_time`) `selfActivate`, `idempotentHint:false`.
- `graph_pim_deactivate` **W** (`principal_id`, `role_definition_id`, `reason`) `selfDeactivate`.

**Conditional Access** (`conditional_access.py`) read-only v1
- `graph_ca_policies` (`state` post-slice client filter).
- `graph_ca_named_locations`.

**Devices** (`devices.py`) read-only v1
- `graph_device_list` (`display_name` startswith, `compliant` post-slice client filter).
- `graph_device_get` (`device_id`).
- `graph_device_owners` / `graph_device_registered_users` (`device_id`).

## Graph permissions (application, admin-consented)

| Module | Read app roles | Extra for writes |
|---|---|---|
| Users | `User.Read.All` | `User.ReadWrite.All`; reset-password needs **Privileged Authentication Administrator** (admin targets) / **User Administrator** (non-admin) directory role |
| Groups | `Group.Read.All` | `Group.ReadWrite.All` |
| Audit | `AuditLog.Read.All` | - |
| Identity Protection (P2) | `IdentityRiskyUser.Read.All`, `IdentityRiskEvent.Read.All` | - |
| Applications | `Application.Read.All` | `Application.ReadWrite.All` |
| Service Principals | `Application.Read.All` | `RoleManagement.ReadWrite.Directory` (app-role remove) |
| Directory Roles | `Directory.Read.All`, `RoleManagement.Read.Directory` | - |
| PIM | `RoleManagement.Read.All` | `RoleManagement.ReadWrite.Directory` |
| Conditional Access | `Policy.Read.All` | - |
| Devices | `Device.Read.All` | - |

Licensing: **P2** for the three Identity Protection tools, **P1+** for `graph_user_signins`, any licensed tenant otherwise. A `403` with `Authentication_RequestFromNonPremiumTenant` means the license/app-role is missing, not a code bug.

## Pagination and gotchas

- **Pagination** (`_common.walk_and_slice`): adapts Graph `@odata.nextLink` to int `limit`/`offset`. Injects `$top=100` when omitted, walks nextLink until `offset+limit+1` (the +1 detects `has_more`), then slices. `hard_cap=5000`: reaching it before covering `offset` raises a `ToolError` ("refine filters"); after covering it sets `cap_hit=true` (truncated, `has_more` unreliable). Page with `next_offset`.
- **Client-side filters after slicing** underreport `count`/`has_more`: `graph_user_groups.security_only`, `graph_ca_policies.state`, `graph_device_list.compliant`.
- **OData injection defense:** identifiers are percent-encoded; `$filter` string inputs reject or double single quotes. OData operator injection (parens, `eq`/`or`/`and`) is deliberately NOT blocked (trust boundary assumes an authenticated caller).
- No advanced-query header (`ConsistencyLevel: eventual` / `$count`) is sent, so filters rely on non-advanced OData.
- Absolute nextLink URLs bypass the base-URL join (`_resolve_url`).
- `aiohttp` is a hard dependency: azure-identity's async transport needs it or `DefaultAzureCredential()` fails to construct at startup.

## Fleet conventions (adding a tool)

Same template as the rest of the fleet ([[cribl]], [[sonarqube]], [[databricks]]).

1. Add `src/custom_components/<area>.py` following `example_tool.py`: a `BaseModule` subclass whose `register_tools()` calls `self._add_tool(fn, annotations=...)`. `discover_modules()` instantiates every subclass at startup; the registered tool name is exactly `fn.__name__`, so it MUST start with `graph_`.
2. Tool input is a single Pydantic `BaseModel` with `Field(...)` constraints (no bare positional args), and all four annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`).
3. Gate writes behind `writes_enabled()` (registered only when `GRAPH_WRITE_TOOLS_ENABLED=true`).
4. Add a respx-mocked `tests/test_<area>.py`; never hit live Graph in unit tests.
5. Pre-push gate (`git config core.hooksPath .githooks`): `ruff check src tests` -> `mypy src` (strict) -> `check_pydantic_inputs.py` -> `check_no_print.py` (no `print()`; stdout is the JSON-RPC wire, log to stderr) -> `check_jwt_allowlist.py` (no `python-jose`/`pyjwt`/`authlib` unless allowlisted in `[tool.mcp-fleet]`) -> `pytest -q`.

Python `>=3.12,<4.0`, Poetry, `poetry run pytest -v`. The fleet contract lives in the platform repo's `mcp-fleet/CONTRACT.md`. Do not run the container conformance Docker gate locally (operator-approval-gated); stdio engineer-mode release is githooks only.
