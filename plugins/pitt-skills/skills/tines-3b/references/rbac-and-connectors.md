# Access Control, Connectors, and Networks

## The grant model

Everything is one shape: **a principal, in a role, on a scope.** The access
check answers "can this principal, in this role, act on this thing?"

**Principals**, three kinds: members (humans with an email who sign in), groups,
and service accounts.

**Scopes**, six kinds plus tenant: spaces, connectors, skills, networks, groups,
service accounts. Tenant scope sits above all others.

Permission strings carry a resource prefix: `space:read`, `space:write`,
`connected_app:use`, `allow_all`. Note that a connector's internal resource name
is `connected_app`.

### Evaluation order

1. Tenant admin, which short-circuits to full access
2. A direct grant on the exact resource
3. A grant inherited through any group you belong to

No match means denied. **There is no deny rule.** Groups "only grant additional
permissions; they cannot be used to restrict or deny access." A principal's
access is the union of all grants.

**Denial is invisible.** Resources render as nonexistent rather than forbidden,
so a missing connector is usually a permissions symptom.

Every action is re-checked server-side at run time.

### What is scoped where

| Level | Owns |
|---|---|
| Tenant | members, groups, service accounts, connectors, skills, networks, SSO, audit logs, AI provider, egress rules |
| Space | workflows, volumes, git remotes, access grants |
| Workflow, draft, run, execution, chat | nothing of their own; they resolve to the parent space |

"Everything inside the space inherits that access, so a workflow doesn't have
its own separate access list."

The docs describe the model as non-hierarchical in one article and as an
explicit tenant-down tree in others. Both are reconcilable: peer resources like
connectors and spaces do not inherit from each other, but children inherit from
their space. Read the flat framing as stale.

## The weakest-member rule

The single most operationally surprising rule in the platform:

> "A connector, skill, or network is only usable in a space when everyone who
> has access to that space also has the right access to that resource."

Availability is a function of the **least-privileged member of the space**, not
the acting user. Adding one space viewer without connector access silently
breaks every workflow in that space.

Per-resource requirements:

| Resource | Who needs what |
|---|---|
| Connectors | builders and workflow-runners need `use`; viewers and admins need view |
| Skills | every space member needs at least view |
| Networks | builders and workflow-runners need `use` |

Two ways to satisfy it: add the space itself to the resource's access list, or
grant matching access to every member and group on both sides. **Grant to the
space**, not to individuals, unless you enjoy chasing phantom breakages.

Managing a connector's access requires being a sharer of it. Creators get sharer
automatically if they hold the corresponding share permission.

## Built-in roles

**Tenant**
- Tenant Admin: full access to everything, overrides every other check. Cannot be included in a custom role.

**Space**
- Space Viewer: open the space and view its workflows
- Space Editor: create, edit, and run workflows; push drafts live and restore live versions
- Space Manager: change space settings and manage access

**Connector**
- Connector Viewer: view the connector and its non-secret settings
- Connector User: use its credentials in workflows and build chats
- Connector Editor: change settings and credentials
- Connector Sharer: manage who has access

**Skill**: Skill User (view), Skill Manager (change instructions and access)

**Network**: Network Viewer, Network User (route traffic), Network Manager

**Group**: Group Member (view), Group Manager (change membership and access)

**Service account**: Viewer, User (get a short-lived credential acting as the
account), Manager (issue and revoke credentials)

**Creator roles** exist at tenant level for each resource type: Space Creator,
Connector Creator, Skill Creator, Network Creator, Group Creator, Service
Account Creator.

### Custom roles

Created in settings. Constraints:

- "The 'view' permission is always included" and cannot be disabled
- "Full tenant access is off limits." Custom roles cannot include full tenant access or manage-all-spaces
- Names must be unique
- **Immutable.** Permissions "are set when you create it and can't be edited afterward." To change one, create a new role and delete the old

Tenant capabilities go to groups, not individuals, with full admin as the
documented exception.

## Connectors

### What they are

A tenant-level credential binding. A step makes "a plain, unauthenticated
request to the app's API" and the platform "injects the right credentials as the
request leaves." Your code never touches the secret.

### Creation paths, all through the UI

1. **Library connector**: browse the library (900+ templates), pick an app, fill settings, review access, save
2. **Custom API key connector**: name, URL pattern, auth method, credential, optional test URL
3. **Database connector**: Data category, pick the type, fill host, port, database, user, password, TLS
4. **Workflow as connector**: a button in the workflow header that "automatically creates a workflow-backed connector"

Gated by the "Create connectors" permission.

No API, CLI, config-file, or Terraform creation path is documented, and the
published API spec exposes none. See `gotchas.md` for the precise standing of
that claim.

### Auth types

The custom API key form offers four: bearer token, custom headers, basic
authentication, query parameters.

The credential proxy can inject six: API keys, OAuth 2.0, bearer tokens, basic
authentication, AWS signature v4, and JWT. The extra two appear only in the
proxy documentation, and no article reconciles the lists. Treat SigV4 and JWT as
reachable through library connector types rather than the custom form.

OAuth connectors prompt for authorization after saving. MCP server connectors
take OAuth (with automatic endpoint discovery and client registration) or a
bearer token.

### The credential proxy

Three tiers of secret handling:

1. **Sealed client-side**: "sealed on your device the moment you enter them, so the plaintext value never travels to or rests on our servers"
2. **At rest**: per-tenant encryption keys, "useless in a database dump"
3. **At runtime**: "unsealed in memory only at the moment a request goes out, and it is cleared once the run finishes"

**Origin pinning** is the mechanism that prevents exfiltration: credentials
attach only when the destination URL matches the connector's URL pattern.
Additional guardrails include principal scoping, SSRF protection blocking cloud
metadata endpoints, and optional hermetic modes blocking all external traffic.

Guidance for MCP work: never set the Authorization header yourself, and never
print or store tokens.

### Failure modes

| Symptom | Cause |
|---|---|
| Connector absent when configuring an action | URL pattern mismatch (bad regex, unescaped dots), or a permissions denial rendering it invisible |
| 401 / 403 | key validity or expiry, wrong auth method, case-sensitive header names, missing provider-required headers |
| SSL verification failure | internal or self-signed certificates. Upload a PEM CA cert with the full chain |
| OAuth callback failure | redirect URI must match exactly including protocol and port |
| Token expiry | confirm a refresh token was issued; some providers require periodic manual re-auth |
| Upload rejected | file uploads cap at 1 MB, CA certs included |

Editing saves on field blur with no save button. Deleting warns with a count of
referencing workflows and branches and is permanent.

## Service accounts

The only viable identity for unattended automation, because member API keys
expire in 24 hours.

Three credential types:

| Type | Lifetime |
|---|---|
| API key | long-lived, until revoked. Shown once |
| Temporary credential | 1, 4, 8, or 16 hours. Expires on its own, nothing to revoke |
| OIDC federation | no stored secret. Register the IdP and a trusted subject matching the token `sub` claim, exact or prefix wildcard |

OIDC federation is aimed at CI systems, with build-pipeline subjects as the
cited use case.

A new service account can do nothing until granted access, and grants are made
from the resource side. Deletion revokes keys, federations, and access
immediately and cannot be undone, but an account with workflow history cannot be
deleted, only disabled.

## Networks and tunnels

**Network**: "a controlled path to systems that aren't sitting on the open
internet." Routing is automatic and step-transparent: a step makes its request
and the routing table decides the path based on destination. There is no
step-level network selection.

**It fails closed.** A space can route through a network only when the people
who run code in that space are allowed to use it. Denied means blocked, not
silently sent over the public internet.

**Enforced routes** force matching traffic through a designated network and take
precedence over standard routing. This is the guardrail against a builder
accidentally reaching an internal host over the internet.

**Tunnel**: a containerized exit node you run on a host inside your network. It
"connects outward to the tunnel gateway and holds that connection open," so no
inbound firewall holes are needed. Mutual auth with client certificates; the
platform mints a certificate and issues a one-time token at network creation.

Destinations are declared at network creation as hostname globs or CIDR ranges.

Only Docker deployment is documented. Kubernetes, systemd, and bare-binary
installs are **[undocumented]**, not stated unsupported. Note that standing up an
exit node is a container workload on a host inside your network, which may
require its own approval under local policy.

**Egress rules** are separate and tenant-wide, allowing or denying by hostname
pattern or CIDR with optional port.

**[undocumented]** Static outbound IPs for allowlisting the platform on your
side.

## Residual unknowns

- Seat model, licensing, and per-member cost. Absent from the documentation entirely
- External or guest human access as a member type. No mechanism documented either way
- Whether the space git remote carries connector definitions
- Whether the API surface differs between cloud and self-hosted
