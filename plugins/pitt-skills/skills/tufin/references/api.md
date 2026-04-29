# Tufin TOS REST and GraphQL API Reference

Reference for TOS Aurora R25-1 APIs. Base assumption: HTTPS only, HTTP Basic Auth, JSON via explicit `Accept` header.

## Authentication

HTTP Basic Auth on every request. There is no token, no OAuth, no API key. The user account's permissions in TOS dictate what the API call can do.

```
Authorization: Basic base64(user:password)
```

Recommendations for service accounts:
- One service account per integration (XSIAM, Tines, Torq, ServiceNow, etc.). Do not share.
- For SecureTrack/SecureChange/SecureApp interop, the SecureChange-to-SecureTrack service account needs **Super Admin**. For your own automation, scope tighter.
- SecureTrack accepts local users, RADIUS, LDAP, and TACACS for API auth. SecureChange and SecureApp accept whatever the user has permissions for.
- Session duration is enforced. Long-running jobs should expect 401s and re-auth, not assume sticky sessions.

## Base URLs

```
SecureTrack:        https://<TOS>/securetrack/api/
SecureChange:       https://<TOS>/securechangeworkflow/api/securechange/
SecureApp:          https://<TOS>/securechangeworkflow/api/secureapp/
GraphQL (sync):     https://<TOS>/v2/api/sync/graphiql
GraphQL (SNMP):     https://<TOS>/v2/monitor-tower/graphiql
Swagger SecureTrack: https://<TOS>/securetrack/apidoc/
Swagger SecureChange: https://<TOS>/securechangeworkflow/apidoc/
```

`<TOS>` is the SecureTrack server. SecureTrack and SecureChange can be on different hosts in distributed deployments. Ask the platform owner before hardcoding.

## Content Types

Default response is XML. To get JSON, set `Accept: application/json`. For POST/PUT/PATCH, set `Content-Type` to match the body. For most automation work, use JSON. XML is needed when interacting with custom workflow scripts (the mediator pattern passes XML on stdin).

```
Accept: application/json
Content-Type: application/json
```

The OPTION HTTP method is not supported (security policy). Supported: GET, POST, PUT, PATCH, DELETE.

## Pagination

REST endpoints that return lists support `start` and `count` query parameters. The response DTO includes a `total` field; use it to drive your loop.

```
GET /securetrack/api/devices/254/rules?start=0&count=100
GET /securetrack/api/devices/254/rules?start=100&count=100
```

GraphQL uses `first` (max 500, default 100) and `offset`.

```graphql
{ rules(first: 200, offset: 0, filter: "name exists") { count, values { id, name } } }
```

## Common SecureTrack REST Endpoints

### Devices

```
GET    /securetrack/api/devices                       # list all devices
GET    /securetrack/api/devices/{id}                   # one device
POST   /securetrack/api/devices                        # add offline device
PUT    /securetrack/api/devices/{id}                   # update offline device
DELETE /securetrack/api/devices/{id}
GET    /securetrack/api/devices/{id}/revisions         # revision history
GET    /securetrack/api/devices/topology_interfaces?mgmtId={id}
```

### Security Rules

```
GET /securetrack/api/devices/{device_id}/rules                  # all rules on device
GET /securetrack/api/devices/{device_id}/rules/{rule_id}        # specific rule
GET /securetrack/api/devices/{device_id}/rules/{rule_id}/documentation
GET /securetrack/api/rule_search?devices={ids}&...              # find rules across devices
```

Rule responses include source, destination, service, action, comments, hit info, permissiveness, shadowing flags.

### Network Objects, Services, NAT

```
GET /securetrack/api/devices/{device_id}/network_objects
GET /securetrack/api/devices/{device_id}/services
GET /securetrack/api/devices/{device_id}/nat_rules
```

### Zones (Network Zones, Subnets, Security Groups, Patterns)

```
GET    /securetrack/api/zones                                  # all zones
GET    /securetrack/api/zones/{zone_id}
POST   /securetrack/api/zones                                  # create
DELETE /securetrack/api/zones/{zone_id}
GET    /securetrack/api/zones/{zone_id}/entries                # subnets in zone
POST   /securetrack/api/zones/{zone_id}/entries
DELETE /securetrack/api/zones/{zone_id}/entries/{entry_id}
```

For zone security groups (cloud SG mirroring) and zone patterns (auto-association by name match), separate sub-resources exist. Patterns are how you tell SecureTrack "any cloud SG whose name contains `prod-` belongs in zone `Production`."

### Topology and Path Analysis

```
GET /securetrack/api/topology/path?src={ip}&dst={ip}&service={proto:port}
GET /securetrack/api/topology/path_image?...                   # SVG/PNG of the path
GET /securetrack/api/topology_clouds                           # cloud objects in topology
```

NAT simulation, broken paths, and blocked-status flags are query parameters. See `topology.md` for the full set.

### Policy Analysis (rule-level, not topology-level)

```
GET /securetrack/api/devices/{device_id}/policy_analysis?
       sources=Any&destinations=Any&services=Any&action=&exclude=
```

Returns the rules that match the supplied flow on the specified device(s). Different from path analysis: this asks "which rules match," not "what is the path."

### Cleanup

```
GET /securetrack/api/cleanups                                  # supported cleanup types
GET /securetrack/api/devices/{device_id}/cleanups              # cleanup instances on device
```

Cleanup IDs (C01, C06, C08, C11, C12, C15, etc.) are documented in `policy-compliance.md`.

### Violations (USP)

```
GET /securetrack/api/violating_rules/{device_id}/device_violations?...
GET /securetrack/api/violating_rules?severity=CRITICAL&...
```

Generally easier to query violations through GraphQL since you can filter and shape in one call.

### USP

USP CRUD and queries are best done in GraphQL. The REST surface is thinner. See examples below.

## Common SecureChange REST Endpoints

### Tickets

```
GET    /securechangeworkflow/api/securechange/tickets                  # query tickets
GET    /securechangeworkflow/api/securechange/tickets/{ticket_id}      # one ticket
POST   /securechangeworkflow/api/securechange/tickets                  # create new ticket
PUT    /securechangeworkflow/api/securechange/tickets/{ticket_id}/steps/current/tasks/{task_id} # advance/handle current step
```

`.json` extension on the URL also works: `/tickets/3.json`. Both forms return JSON when Accept is set.

### Ticket Lifecycle Operations

```
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/cancel
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/reject
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/redo
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/reassign
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/resolve
GET /securechangeworkflow/api/securechange/tickets/{ticket_id}/history
```

### Workflows and Devices

```
GET /securechangeworkflow/api/securechange/workflows                   # available workflows
GET /securechangeworkflow/api/securechange/securechange_devices        # devices SecureChange knows about
```

### Users and Groups

```
GET /securechangeworkflow/api/securechange/users
GET /securechangeworkflow/api/securechange/groups
```

### Rule Recertification and Decommission

These have their own endpoints under `/securechange/rule_decommission_request`, `/securechange/rule_modification_request`, and the recertification module under `/securechange/rule_recertification`. See `change-automation.md` for the workflow context.

## Common SecureApp REST Endpoints

```
GET  /securechangeworkflow/api/secureapp/repository/applications
GET  /securechangeworkflow/api/secureapp/repository/applications/{id}/connections
POST /securechangeworkflow/api/secureapp/repository/applications/{id}/connections
GET  /securechangeworkflow/api/secureapp/repository/servers
GET  /securechangeworkflow/api/secureapp/repository/services
```

When a SecureApp connection changes and the user opens a ticket, SecureChange creates the ticket with the access-request fields prefilled.

## Submitting an Access Request (SecureChange)

Minimal request body for an access-request workflow ticket. The schema varies per workflow; check the actual workflow definition first.

```json
POST /securechangeworkflow/api/securechange/tickets
Content-Type: application/json
Accept: application/json

{
  "ticket": {
    "subject": "Block 198.51.100.7 (active C2)",
    "priority": "Critical",
    "domain_name": "Default",
    "workflow": { "name": "Standard Firewall Change" },
    "steps": {
      "step": [{
        "name": "Open request",
        "tasks": {
          "task": [{
            "fields": {
              "field": [{
                "@xsi.type": "multi_access_request",
                "name": "Access Request",
                "access_request": [{
                  "order": "AR1",
                  "use_topology": true,
                  "targets":      { "target":      [{ "@type": "ANY" }] },
                  "users":        { "user":        ["Any"] },
                  "sources":      { "source":      [{ "@type": "IP", "ip_address": "0.0.0.0", "netmask": "0.0.0.0", "cidr": 0 }] },
                  "destinations": { "destination": [{ "@type": "IP", "ip_address": "198.51.100.7", "netmask": "255.255.255.255", "cidr": 32 }] },
                  "services":     { "service":     [{ "@type": "ANY" }] },
                  "action": "Drop",
                  "labels": []
                }]
              }]
            }
          }]
        }
      }]
    }
  }
}
```

Notes:
- `action` accepts `Accept` or `Drop`. Decommission tickets use `Drop`.
- `use_topology: true` lets Designer select target devices automatically; `false` makes you specify targets.
- The `xsi:type` of the field must match the workflow's field schema. For a single access-request field use `multi_access_request`. Generic workflows use `text_area`, `drop_down_list`, `multi_text_field`, `checkbox`, `date`, etc.
- Subject and priority are required by most workflows. Priority values: `Critical`, `High`, `Normal`, `Low`.

## GraphQL: When and How

GraphQL is a better fit when:
- You need nested data in one round trip (e.g. devices + their rules + the matching USP violations).
- You want filtering more expressive than REST query strings.
- You are doing read-heavy automation; mutations exist but are limited to specific schemas (USP alerts, USP exceptions).

Open the live console at `https://<TOS>/v2/api/sync/graphiql`. CTRL+SPACE for autocomplete.

### Filter syntax = TQL

Filters inside GraphQL queries are TQL strings:

```graphql
{
  rules(filter: "name exists and timeLastModified after 90 days ago") {
    count
    values { id name action }
  }
}
```

Up to 20 levels of hierarchy. Operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `in`, `not in`, `exists`, `not exists`, `contains`, `before`, `after`, `and`, `or`. Strings in single quotes. See `tql.md`.

### Useful queries

USPs that include a specific zone:

```graphql
{
  usps(filter: "zones.name = 'Production'") {
    values { name securityZones { name } }
  }
}
```

Devices last revised in the past week:

```graphql
{
  devices(filter: "timeLastRevision after 7 days ago") {
    count
    values { id name vendor model timeLastRevision }
  }
}
```

Critical violations across the estate:

```graphql
{
  violations(filter: "severity = 'CRITICAL'") {
    count
    values {
      severity
      rule { id idOnDevice device { name } source { ... on IpAddressRange { firstIp } } }
      usp { name }
    }
  }
}
```

Mutations exist for `createUspAlertConfig`, `updateUspAlertConfig`, `deleteAlertConfig` (and equivalents on USP exceptions). Most write paths still go through REST.

## pytos2 (Python SDK)

Tufin Professional Services maintains pytos2-CE: `https://gitlab.com/tufinps/pytos2-ce`. Wraps SecureTrack, SecureChange, and GraphQL calls. Useful for custom workflow scripts (mediator-side) where you want typed Python objects instead of hand-rolling XML.

The original `pytos` (`github.com/Tufin/pytos`) is older but still in use. It includes a hook framework: `Secure_Change_Helper` registers Python functions to fire on workflow events (CREATE, CLOSE, CANCEL, REJECT, ADVANCE, REDO, RESUBMIT, REOPEN, RESOLVE, plus auto-step events TARGET_SUGGESTION_STEP, VERIFIER_STEP, DESIGNER_STEP, RISK_STEP, IMPLEMENTATION_STEP).

Reach for pytos2 if writing new mediator-side scripts in Python; treat pytos as legacy.

## Postman

Tufin publishes Postman collections per release: `https://forum.tufin.com/support/kc/rest-api/R25-1/tss_postman_collections.zip`. Import them, set environment variables (`{{securetrack_ip}}`, `{{securechange_ip}}`, `{{username}}`, `{{password}}`), and you can browse the full surface. Note Postman ships SSL verification on by default; turn it off for self-signed labs but leave it on in production.

## Common Patterns and Gotchas

1. **Read default-format trap.** XML by default. Always set `Accept: application/json` or you will get unexpected XML.
2. **JSON single-element arrays.** Some endpoints return a single-element array as a bare object instead of a one-item list. Tufin documents which endpoints fixed this. Defensive code: coerce to a list before iterating.
3. **Pagination cap.** GraphQL `first` is capped at 500. Loop on `offset` past 500.
4. **Ticket schema mismatch.** A POST to `/tickets` against a non-standard workflow will fail validation with a generic 400. Always GET the workflow definition first and mirror the field types and names exactly.
5. **Async tasks.** Designer, Verifier, and Risk Analysis are auto steps that run in the background. Polling the ticket and waiting for the step to advance is the right pattern. The pytos `get_ticket_by_id(retry_until_assigned=True, predicate=...)` pattern works well.
6. **Audit trail.** SecureTrack > Admin > Audit Trail records every user action including API calls. Forward to syslog if you need long-term retention. The recorded source IP may be the in-cluster pod IP rather than the external client IP in proxy/ingress deployments. Plan logging accordingly.
7. **API account password rotation.** When the password changes via the UI, the user is prompted to reset on next login and must complete the reset before any API calls succeed. Rotate carefully: change password, log into UI as that account, complete the reset, then update the credential store. Otherwise the integration breaks.
8. **Multi-domain.** If TOS is configured for multiple domains, the user accounts split into Super Admin / Multi-Domain Admin / Multi-Domain User / Domain User. Cross-domain reads need Super Admin. SecureChange does not support Security Zones in Multi-Domain mode (per Tufin docs).
9. **TLS.** TOS supports TLS 1.2 and later. Check appliance certs; replace self-signed with corporate CA-issued certs before pointing automations at it.
