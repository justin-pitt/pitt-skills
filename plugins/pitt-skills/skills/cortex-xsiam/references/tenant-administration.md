# Tenant Administration Reference

Platform admin layer: tenant activation, BYOK, dev→prod content promotion via Remote Repository, RBAC and scoping, SAML SSO. For SOAR/playbook content concerns, see [soar-automation.md](soar-automation.md).

## Cortex Gateway

Centralized portal for managing tenants, users, roles, and user groups across **all** Cortex products tied to one Customer Support Portal account (admin doc p. 27, p. 42). Anything created in Gateway is available to every tenant under that CSP account.

- Activation entry point - every new XSIAM tenant is activated from Gateway.
- Account Admin role lives here only - it cannot be created or removed inside the tenant (admin doc p. 66). Account Admin auto-grants on first CSP Super User login.
- Roles/groups created in Gateway apply across tenants but **cannot be SAML-mapped** - only tenant-created groups support SAML group mapping. Recommended: create groups in the tenant for SSO, in Gateway only for cross-tenant admin roles (admin doc p. 68).
- Required for: tenant activation, dev tenant activation (`Activate Dev Tenant`), BYOK setup/rotation, MSSP-style multi-tenant role management.
- Not required for day-to-day analyst access - once SSO is live, analysts hit the tenant FQDN directly.

## Tenant activation + BYOK

Activation flow (admin doc p. 41-44):
1. CSP Super User logs into Gateway.
2. From `Available for Activation`, click `Activate`, set Tenant Name, Region (data residency lock - see regions list p. 44-45), Tenant Subdomain.
3. (Optional) `Advanced` → BYOK to bring your own KEK.
4. Activation runs ~1 hour, email on completion.
5. After prod activation, hover the tenant → ellipsis → `Activate Dev Tenant` (subject to license).

**BYOK** (admin doc p. 42-44) - must be selected **at initial activation**; cannot be added later. Two keys: one for BigQuery, one for other tenant services (or one key shared). 32-byte symmetric, OpenSSL-wrapped against a tenant-specific wrapping key (3-day TTL on the wrapping key). Rotation is supported via `Rotate Encryption Key` in Gateway. Disabling all keys deactivates the tenant - re-enabling requires PANW Customer Success intervention.

## Development tenant + Remote Repository

Dev tenant is the test environment for content (integrations, playbooks, scripts, layouts, classifiers, alert/indicator types and fields). It is **not** a perf/scale environment - limited endpoints, limited ingest, limited compute (admin doc p. 177).

**Push/pull cluster model** (admin doc p. 177):
- One push tenant (always a dev tenant) + one or more pull tenants (prod + additional dev).
- Push tenant manages system content (Marketplace) - pull tenants have **no Marketplace access** and only receive content via the repo.
- Push/pull supported: alert/indicator types and fields, layouts, classifiers, integrations, playbooks, scripts.
- **Not** push/pull supported: dashboards, lists, parsing rules, data modeling rules, correlation rules. These have to be developed in-place or hand-copied.

**Built-in vs Private remote repo** (admin doc p. 178):
| | Built-in | Private (Git) |
|---|---|---|
| Backend | Managed by PANW, opaque | Customer-owned: GitHub, GitLab, Bitbucket, on-prem |
| Branches | Single branch | Multiple branches supported |
| External access | None - UI-only | Direct Git access (clone, scan, CI) |
| Auth | None needed | HTTPS user/token or SSH key (RSA/ed25519) |
| Setup effort | Toggle on, done | Per-tenant URL + creds + branch |

Use built-in for simple dev/prod sync. Use private if you need branches, code review on the repo itself, or external scanners against the content. URL allow-list applies to private repos - non-allow-listed hosts require an engine.

**Push flow** (admin doc p. 183):
1. In dev (push tenant): `Settings → Configurations → Remote Repository Content → User-Defined Content`.
2. `Included for Prod` tab → select items → `Push to Prod`. Resolve dependency dialog. Add optional message. Push.
3. Prod tenant shows `Remote Repository Content Available` banner → `Install content`. Conflicts resolve per-item: `Skip` (keep prod) or `Replace` (take repo).
4. Do **not** manually export/import content - versioning breaks.

**Common conflicts** (admin doc p. 184):
- *Pointing at non-empty branch on enable* - pick "Existing content on tenant" (overwrite repo) or "Existing content on repository" (overwrite tenant). To keep tenant content with other tenants already enabled, you must disable the repo on those other tenants first.
- *Switching built-in ↔ private* - version history is lost. Choose `Existing content on your tenant` to preserve the current state into the new repo type.
- *Version mismatch dev↔prod* - don't push across versions; expect compatibility errors.

## Native Remote Repository vs custom Git pipeline

Some teams maintain a custom Git pipeline (dev tenant → manual export → GitHub commit → prod tenant via upload script) instead of, or alongside, the native Remote Repository. The two are **complementary, not competing**:

- **Native Remote Repository** - content state sync (push/pull supported types). One-click promotion, conflict resolution UI, no scripts.
- **Custom Git pipeline** - version control, code review (PRs), branch-based workflows, history beyond what XSIAM stores, change attribution, audit trail. Required for any content type the native repo doesn't push/pull (parsing rules, DMRs, correlation rules, dashboards, lists).

To combine them, configure the native repo as **Private** pointing at your existing Git remote. PRs land on the active branch, dev pulls/pushes via that branch, prod pulls. Custom upload scripts can stay for the non-push/pull content types. Built-in repo is a non-starter when audit trail matters - it bypasses code review.

## RBAC

**Predefined roles** (admin doc p. 66-67) - non-editable, save-as-new to customize:
- `Account Admin` (Gateway-only, full access all tenants), `Instance Administrator` (full per-tenant)
- Investigators: `Investigator`, `Privileged Investigator`, `Investigation Admin`
- Responders: `Responder`, `Privileged Responder`, `Privileged Security Admin`, `Security Admin`
- Endpoint/IT: `Deployment Admin`, `IT Admin`, `Privileged IT Admin`, `Scoped Endpoint Admin`
- `Viewer` (read-most, edit reports), `App Service Account` (API/integration consumers)

**App Service Account role** - assigned by default to the API key created when you spin up a Notebooks instance (admin doc p. 706). View/triage alerts/incidents/rules + public APIs for apps. **Default unrestricted dataset access** - to scope a notebook to specific datasets, duplicate the role, enable dataset access management, select datasets. Use this for any service-account-style API key (automation integrations, scheduled scripts).

**Custom roles** - create in tenant (`Settings → Configurations → Access Management → Roles`) or in Gateway. **Dataset-level access (XQL) can only be set in the tenant**, not Gateway (admin doc p. 66, p. 185). When dataset access management is enabled on a role, all datasets must be explicitly enumerated per role.

**User groups** - preferred over direct role assignment. One role per group; users can belong to multiple groups (highest-permission wins). Nested groups inherit upward (parent perms flow down). Create in the tenant for SAML mapping; Gateway groups are not SAML-mappable.

**Scope-Based Access Control (SBAC)** (admin doc p. 188-189) - limit users to a subset of entities by tag. Tag families: Endpoint Groups, Asset Groups, etc. Applies to:
- Endpoint Administration table, Policy Management, Action Center
- Dashboards/Reports (agent-related widgets only)
- Incidents and Alerts (filtered by scope)

**SBAC does not apply to most other functional areas** - a scoped user with "view incidents" sees all incidents, not just in-scope. Admin-class roles cannot be scoped at all. Users can't edit the endpoint group that defines their own scope. Alert exclusions support SBAC.

## SSO / SAML

Tenant-level SSO via SAML 2.0 (admin doc p. 70-80). Set up at `Settings → Configurations → Access Management → Authentication Settings`. Multiple IdPs supported - domain-based routing on email.

**Required IdP attributes** - case-sensitive, must match exactly: Email, Group Membership (`memberOf`), First Name, Last Name. IdP must sign **both** the SAML response and the assertion.

**Group claim format**:
- **Okta**: send group name (string). Filter to `Cortex XSIAM*` groups in the IdP to keep token small.
- **Azure AD**: send Group **Object ID (GUID)**, not name (admin doc p. 69, p. 79). Map GUIDs in user group `SAML Group Mapping` field. This is the #1 Azure AD gotcha.
- IdPs sending comma-separated DN-format groups need reconfiguration to send a single value (CN) per group - XSIAM splits on commas.

**Session + role re-evaluation** - once authenticated, role/group changes don't take effect mid-session. Permissions stick for the full configured Session Security max length even if group membership or default role updates (admin doc p. 184). Force re-login after role changes.

**Lockout protection** - keep at least one Customer Support Portal user as backup auth (admin doc p. 70). If IdP breaks, SSO-only users can't log in.

**Login URL** - SAML users must hit the tenant FQDN directly; they cannot log in via Cortex Gateway. To enable IdP-initiated SSO from the Okta dashboard or Azure AD App Catalog, set `Default RelayState` (Okta) or `Relay State` (Azure) to the tenant Audience URI.

**Common SSO failures** (admin doc p. 73-74):
- Service Provider Entity ID / Identifier mismatch IdP↔tenant.
- Attribute name case mismatch (FirstName vs firstName).
- Group membership mapped wrong (GUID vs name for Azure AD).
- IdP signing only response or only assertion - must sign both.

## Quick admin checklist

- New analyst onboarding → IdP group → tenant user group with role + SAML mapping → no manual provisioning needed.
- New service account / API key → assign `App Service Account` role (or scoped clone), record in your key inventory.
- Dev→prod content promotion → push tenant only, via Remote Repository UI or your custom Git pipeline.
- Pre-tune of correlation rule → develop in dev tenant, hand-port to prod (correlation rules are not push/pull-supported).
- Scope a junior analyst to one BU → SBAC tag family on user group; verify incident-page filtering applies (other functional areas may still expose all data).
