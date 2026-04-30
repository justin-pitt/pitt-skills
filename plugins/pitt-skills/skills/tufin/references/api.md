# Tufin TOS REST API Reference

Reference for TOS Aurora R25-1 REST endpoints across SecureTrack, SecureChange, and SecureApp. The GraphQL surface lives in `references/graphql.md`. TQL syntax (used by both REST `?filter=` params and GraphQL `filter:` arguments) lives in `references/tql.md`.

Base assumption: HTTPS only, HTTP Basic Auth, JSON via explicit `Accept` header.

## Overview

| Component | Base URL | Default content type |
|-----------|----------|----------------------|
| SecureTrack | `https://<TOS>/securetrack/api/` | XML (request JSON via `Accept`) |
| SecureChange | `https://<TOS>/securechangeworkflow/api/securechange/` | XML (JSON accepted on most endpoints) |
| SecureApp | `https://<TOS>/securechangeworkflow/api/secureapp/` | XML (JSON accepted; `.json` URL suffix works) |
| GraphQL (sync) | `https://<TOS>/v2/api/sync/graphql` | JSON only |
| GraphiQL console | `https://<TOS>/v2/api/sync/graphiql` | interactive |
| Swagger SecureTrack | `https://<TOS>/securetrack/apidoc/` | interactive (authoritative) |
| Swagger SecureChange | `https://<TOS>/securechangeworkflow/apidoc/` | interactive (authoritative) |

`<TOS>` is the SecureTrack/SecureChange host. They may be on the same host or split in distributed deployments. Confirm with the platform owner before hardcoding.

The on-appliance Swagger UI is the source of truth for any endpoint flagged `> NEEDS VERIFICATION` below. Public KC pages cover the API conceptually but the per-endpoint paths live in JS-rendered apidoc only the appliance serves.

## Authentication

HTTP Basic Auth on every request. There is no token, no OAuth, no API key. The user account's permissions in TOS dictate what the API call can do.

```
Authorization: Basic base64(user:password)
```

Recommendations for service accounts:
- One service account per integration (XSIAM, Tines, Torq, ServiceNow, MCP server, etc.). Do not share.
- For SecureTrack/SecureChange/SecureApp interop, the SecureChange-to-SecureTrack service account needs **Super Admin**. For your own automation, scope tighter.
- SecureTrack accepts local users, RADIUS, LDAP, and TACACS for API auth. SecureChange and SecureApp accept whatever the user has permissions for.
- Session duration is enforced. Long-running jobs should expect 401s and re-auth, not assume sticky sessions.
- Multi-domain installs scope responses by the calling user's visible domains. Pass `?context=<domain_id>` on SecureTrack list endpoints; without it, the global domain is used and many calls return only global objects.
- Auth probe: `GET /securetrack/api/domains` is the conventional cheap health probe. Requires only valid login, returns a small JSON body.

## Content Types

Default response is XML. To get JSON, set `Accept: application/json`. For POST/PUT/PATCH, set `Content-Type` to match the body. For most automation work, use JSON. XML is needed when interacting with custom workflow scripts (the mediator pattern passes XML on stdin).

```
Accept: application/json
Content-Type: application/json
```

The OPTIONS HTTP method is not supported (security policy). Supported: GET, POST, PUT, PATCH, DELETE.

SecureChange and SecureApp also accept the `.json` URL-suffix form when `Accept` negotiation is unreliable, e.g. `GET /tickets/3.json`.

## Errors

JSON shape: `{"result": {"code": "...", "message": "..."}}`. XML shape: `<result><code>...</code><message>...</message></result>`.

| Status | Typical cause |
|--------|---------------|
| 400 | Bad params; invalid `workflow.name`; field schema mismatch |
| 401 | Bad auth; expired session |
| 403 | Permission denied; workflow ACL hides workflow from caller |
| 404 | Unknown ticket / device / object id |
| 409 | Conflict; advance attempt against a step whose required fields are not set |
| 5xx | Server-side topology/sync issue |

GraphQL is special: GraphQL-level errors return HTTP 200 with an `errors[]` array. Treat them as failures separately from HTTP status.

---

# SecureTrack

Base: `/securetrack/api/`. Owns device inventory, rules, revisions, network objects, services, zones, USPs, topology, cleanups, audit.

## Devices

### List devices

`GET /securetrack/api/devices`

Query params: `name`, `ip`, `vendor`, `model`, `show_os_version` (`true|false`), `show_license` (`true|false`), `context`, `start`, `count`.

Response shape:
```json
{
  "devices": {
    "count": 2,
    "total": 2,
    "device": [
      {
        "id": 20,
        "name": "fw-dc-edge-01",
        "vendor": "Cisco",
        "model": "asa",
        "domain_id": 1,
        "domain_name": "Default",
        "offline": false,
        "topology": true,
        "ip": "10.10.10.5",
        "latest_revision": 142,
        "module_uid": "",
        "module_type": ""
      }
    ]
  }
}
```

When only one device matches, `device` is a bare object, not a 1-element array. Coerce to list before iterating.

### Get device

`GET /securetrack/api/devices/{device_id}` returns `{ "device": {...} }`. 404 if id unknown.

### Add offline device

`POST /securetrack/api/devices/`

Body:
```json
{"device": {"name": "fw-lab-01", "vendor": "Cisco", "model": "asa", "domain_id": 1, "offline": true}}
```

Returns 201 with `Location: /securetrack/api/devices/{new_id}`.

### Bulk import managed devices

`POST /securetrack/api/devices/bulk/`

Used to import many managed devices in one call (all VDOMs under a Fortinet manager, all CMA gateways under an MDS, all AWS VPCs under an account). Body wraps `devices.device[]`. Returns **202 Accepted** with a `Location` header pointing to a task resource. Poll that URL until status is `DONE`.

> NEEDS VERIFICATION: exact body schema per vendor and the task-status URL pattern. The KC `Performing Bulk Device Tasks` page returns 404 publicly; the on-appliance Swagger UI is authoritative.

### Delete device

`DELETE /securetrack/api/devices/{device_id}?update_topology=true|false`

`update_topology` defaults to false. For management devices, this also removes the managed children.

### Upload offline device config (task)

`POST /securetrack/api/tasks/add_device_config_task`

Multipart form: `device_id=<id>`, `configuration_file=<file>`. Returns 201 with the new task id in `Location`. Tufin parses the config asynchronously; the new revision appears under the device when parsing finishes.

### Generic devices (user-defined topology nodes)

```
GET    /securetrack/api/generic_devices?context={domain_id}&name={name}
POST   /securetrack/api/generic_devices                        # multipart: configuration_file, device_data, update_topology
PUT    /securetrack/api/generic_devices/{id}
DELETE /securetrack/api/generic_devices/{id}?update_topology=true
```

POST is multipart, not JSON. `configuration_file` (txt), `device_data` (JSON string part: `{"generic_device":{"name":"...","customer_id":N}}`), and `update_topology` (bool). `Accept: */*` is required because the API returns 200 with an empty body.

### Topology interfaces for a device

`GET /securetrack/api/devices/topology_interfaces?mgmtId={device_id}` (and `&genericDeviceId=...&is_generic=true` for generic devices).

## Domains (multi-domain)

Base: `/securetrack/api/domains`. Only meaningful when SecureTrack is in multi-domain mode.

```
GET    /securetrack/api/domains                # list, supports name, start, count
GET    /securetrack/api/domains/{domain_id}    # one domain
POST   /securetrack/api/domains/               # create
PUT    /securetrack/api/domains/{id}           # update
```

Body: `{"domain": {"name": "EMEA", "description": "EU sites", "address": ""}}`.

## Revisions

Base: `/securetrack/api/revisions` and `/securetrack/api/devices/{device_id}/revisions`.

### List device revisions

`GET /securetrack/api/devices/{device_id}/revisions/`

```json
{
  "revisions": {
    "count": 2,
    "total": 2,
    "revision": [
      {"id": 142, "revisionId": 142, "guiClient": "Web", "action": "Automatic Polling",
       "date": "2026-04-29T22:14:00Z", "admin": "system", "authorized": true,
       "policy_package": "Standard", "is_ready": true, "ticket_id": ""},
      {"id": 141, "revisionId": 141, "guiClient": "Web", "action": "Manual",
       "date": "2026-04-28T17:02:11Z", "admin": "jdoe", "authorized": true,
       "policy_package": "Standard", "is_ready": true, "ticket_id": "CHG0451"}
    ]
  }
}
```

### Single revision and revision-scoped resources

```
GET /securetrack/api/revisions/{revision_id}
GET /securetrack/api/revisions/{revision_id}/rules
GET /securetrack/api/revisions/{revision_id}/policies
GET /securetrack/api/revisions/{revision_id}/network_objects/{object_ids}    # CSV ids
GET /securetrack/api/revisions/{revision_id}/services/{service_ids}          # CSV ids
GET /securetrack/api/revisions/{revision_id}/config                          # text/plain device config
GET /securetrack/api/devices/{device_id}/config                              # latest revision config
```

### Revision diff

> NEEDS VERIFICATION: SecureTrack supports a revision compare/diff in the UI and via API. pytos1 and pytos2-ce do not surface a wrapper for it that I could read. The KC API Overview names "Revisions" as a resource group; the Swagger UI exposes a `compare` sub-resource. Verify path against the appliance Swagger before wiring an MCP tool.

## Rules

### Rules per device

`GET /securetrack/api/devices/{device_id}/rules`

Query params: `add=documentation` (include documentation block), `uid=<rule_uid>` (filter to one), `start`, `count`.

```json
{
  "rules": {
    "count": 1,
    "total": 152,
    "rule": [{
      "id": 90123,
      "uid": "{1c3b...}",
      "order": 5,
      "name": "permit_web_to_app",
      "comment": "JIRA-1234",
      "action": "Accept",
      "src_network": [{"id": 1, "display_name": "DMZ-Web", "name": "DMZ-Web"}],
      "dst_network": [{"id": 2, "display_name": "App-Tier", "name": "App-Tier"}],
      "src_service": [{"id": 0, "display_name": "Any", "name": "Any"}],
      "dst_service": [{"id": 80, "display_name": "tcp_80", "name": "tcp_80"}],
      "track": {"level": "Log"},
      "disabled": false,
      "implicit": false,
      "documentation": {"tech_owner": "net-team", "business_owner": "ecomm",
                        "record_set": [{"name": "ticket_id", "value": "CHG0123"}]}
    }]
  }
}
```

### Rules per revision

`GET /securetrack/api/revisions/{revision_id}/rules` — same query params and response shape.

### Single rule

`GET /securetrack/api/rules/{rule_id}` returns `{ "rule": {...} }`.

### Search rules across devices (two-step)

This is how the XSOAR Tufin pack calls cross-device rule search.

1. Device fan-out: `GET /securetrack/api/rule_search?search_text=<expr>&context=<domain>`
   ```json
   {"device_list": {"device": [{"device_id": 20, "device_name": "fw-dc-edge-01", "rule_count": 4}, ...]}}
   ```
2. Per device with `rule_count>0`: `GET /securetrack/api/rule_search/{device_id}?search_text=<expr>&start=0&count=100` returns matching rules using the same `rules.rule[]` shape as above.

Search expression syntax: `field:value AND field:value`. Common fields: `text`, `source`, `destination`, `service`, `action`, `comment`, `installedon`, `vendor`, `uid`. Free text is also accepted. Pagination: `start`, `count`. `count` max ~3000.

For complex cross-device search (multiple filters, nested fields, projections), prefer GraphQL `rules(filter: ...)`. See `references/graphql.md`.

### NAT rules per device

`GET /securetrack/api/devices/{device_id}/nat_rules/bindings`

Query params: `input_interface`, `output_interface`, `nat_stage` (`pre_policy|post_policy|both`), `nat_type` (`vip|reverse_vip`).

### Rule documentation

```
GET /securetrack/api/devices/{device_id}/rules/{rule_id}/documentation
PUT /securetrack/api/devices/{device_id}/rules/{rule_id}/documentation
GET /securetrack/api/revisions/{revision_id}/rules/{rule_id}/documentation
```

PUT body sets tech/business owner, record set fields, certification expiration, etc. Treat documentation writes as state-changing and gate them in any MCP wrapper.

### Shadowing detail

`GET /securetrack/api/devices/{device_id}/shadowing_rules?shadowed_uids={uid1,uid2}` returns the rules that shadow the supplied UIDs.

### Rule history

> NEEDS VERIFICATION: present in the apidoc index, exact path string and response shape not captured; pytos uses revision-scoped lookups instead of a dedicated history endpoint.

## Network Objects and Services

### Network objects for a device

`GET /securetrack/api/devices/{device_id}/network_objects/`

Query params: `start`, `count`, `show_members=true|false`, `type` (`host|network|range|group|...`), `name`.

### Search network objects

`GET /securetrack/api/network_objects/search`

Query params: `filter` (`subnet|text|ip|uid|name`), `name` or `exact_subnet` or other filter-specific param, `count` (default 50), `start`, `context`.

Common pattern: resolve which device-side objects represent an IP.

```
GET /securetrack/api/network_objects/search?filter=subnet&exact_subnet=10.20.30.40&count=50
```

```json
{
  "network_objects": {
    "count": 2,
    "total": 2,
    "network_object": [
      {"id": 9001, "uid": "{a1b2...}", "display_name": "H_appserver01",
       "device_id": 20, "type": "host", "ip": "10.20.30.40",
       "comment": "app cluster member"}
    ]
  }
}
```

### Group membership

`GET /securetrack/api/network_objects/{object_id}/groups/?context={domain_id}` returns the groups containing `object_id`.

### Rules referencing object

`GET /securetrack/api/network_objects/{object_id}/rules` returns rules where the object appears in source or destination.

### Services

```
GET /securetrack/api/devices/{device_id}/services                    # name, start, count
GET /securetrack/api/devices/{device_id}/services/{service_id}
```

```json
{"services": {"service": [{"id": .., "name": "tcp_443", "protocol": 6, "min": 443, "max": 443, ...}]}}
```

### Revision-scoped variants

```
GET /securetrack/api/revisions/{rev_id}/network_objects/{object_ids}    # CSV ids
GET /securetrack/api/revisions/{rev_id}/services/{service_ids}          # CSV ids
```

## Network Zones

Base: `/securetrack/api/zones`.

### List zones

`GET /securetrack/api/zones?context={domain_id}`

```json
{
  "zones": {
    "count": 3,
    "total": 3,
    "zone": [
      {"id": 11, "name": "Internet",            "internet": true,  "shared": false},
      {"id": 12, "name": "DMZ",                 "internet": false, "shared": true},
      {"id": 13, "name": "Internal-Production", "internet": false, "shared": false}
    ]
  }
}
```

### Zone subnets/entries

`GET /securetrack/api/zones/{zone_id}/entries?context={domain_id}`

```json
{"zone_entries": {"zone_entry": [
  {"id": 501, "ip": "10.0.0.0",   "prefix": 8,  "comment": "RFC1918 10/8"},
  {"id": 502, "ip": "172.16.0.0", "prefix": 12, "comment": "RFC1918 172.16/12"}
]}}
```

### Zone hierarchy

```
GET /securetrack/api/zones/{zone_id}/descendants?context={domain_id}
PUT /securetrack/api/zones/{parent_id}/descendants/{child_id}/?context={domain_id}    # add child
```

### Mutations

```
POST   /securetrack/api/zones?context={domain_id}
       body: {"zone":{"name":"...","internet":false,"shared":false,"comment":""}}
POST   /securetrack/api/zones/{zone_id}/entries?context={domain_id}
       body: {"zone_entry":{"ip":"10.1.0.0","prefix":16,"comment":""}}
PUT    /securetrack/api/zones/{zone_id}/entries/{entry_id}?context={domain_id}
DELETE /securetrack/api/zones/{zone_id}
DELETE /securetrack/api/zones/{zone_id}/entries/{entry_id}
POST   /securetrack/api/zones/fileResponseAsString?context={domain_id}    # multipart CSV bulk import
```

### Resolve zone for IP (skill helper)

There is no direct `?ip=` zone lookup. Pattern used by the XSOAR Tufin pack: list zones, then list each zone's entries and longest-prefix-match locally.

## Topology

### Path query

`GET /securetrack/api/topology/path`

Query params: `src` (CSV of IPs/CIDRs), `dst` (CSV), `service` (CSV in `proto:port` form, e.g. `tcp:443,udp:53`, or `Any`), `includeIncompletePaths` (`true|false`), `context`.

```json
{
  "path_calc_results": {
    "traffic_allowed": true,
    "device_info": [
      {"name": "fw-dc-edge-01", "vendor": "Cisco", "type": "asa", "device_id": 20,
       "incoming_interfaces": [{"name": "Outside", "ip": "203.0.113.5"}],
       "outgoing_interfaces": [{"name": "DMZ",     "ip": "10.10.10.1"}],
       "binding": {"name": "Standard", "rules": [{"rule_id": 90123, "action": "Accept"}]}
      },
      {"name": "fw-app-core-02", "vendor": "Palo Alto Networks", "type": "panorama_ngfw", "device_id": 24,
       "incoming_interfaces": [{"name": "ethernet1/2", "ip": "10.10.10.2"}],
       "outgoing_interfaces": [{"name": "ethernet1/3", "ip": "10.20.0.1"}],
       "binding": {"name": "vsys1", "rules": [{"rule_id": 71019, "action": "Accept"}]}
      }
    ]
  }
}
```

`traffic_allowed=false` and an empty `device_info` means no path. With `includeIncompletePaths=true`, partial hops up to the blocking device are returned. Always set this unless the caller explicitly wants strict end-to-end; without it, an asymmetric or partially-modeled network returns "no path" with no diagnostic.

### Path image

`GET /securetrack/api/topology/path_image`

Same query params plus `displayBlockedStatus=true|false`. Returns a PNG; request with `Accept: image/png`. A response shorter than ~20 bytes indicates "no path"; treat as a logical no-result, not a transport error. Set `displayBlockedStatus=true` so the rendered PNG shows the blocking firewall.

### Topology sync

```
POST /securetrack/api/topology/synchronize             # 202 + sync job id
GET  /securetrack/api/topology/synchronize/status      # {"status":"in_progress|done|failed", "percentage":NN, ...}
```

> NEEDS VERIFICATION: pytos2-ce exposes `sync_topology()` and `get_topology_sync_status()` as SDK methods but the underlying URL strings are not in the public model files. The R25-1 Swagger UI is authoritative.

### Topology clouds

`GET /securetrack/api/topology/clouds`

Query params: `type` (`joined|non-joined`), `name`, `context`, `start`, `count`.

## Cleanups (Cleanup Browser)

Base: `/securetrack/api/cleanups`.

```
GET /securetrack/api/cleanups?devices={id1,id2}                # cleanup hits across devices
GET /securetrack/api/devices/{device_id}/cleanups?code=C01     # filter to one cleanup code
```

### Built-in cleanup codes

| Code | Name | Notes |
|------|------|-------|
| C01  | Fully shadowed and redundant rules | Rules never hit because earlier rules match the traffic |
| C02  | Disabled / expired rules group | Tufin reorganized over versions; verify per release |
| C05  | Disabled rules | Never hit because they're disabled |
| C06  | Unattached network objects | Not in any rule or group (may still be in NAT/VPN) |
| C08  | Empty groups | Group objects with no members |
| C11  | Duplicate network objects | Same address/config across hosts/networks/ranges |
| C12  | Duplicate services | Same protocol/port/source-port/timeout |
| C15  | Unused network objects | Not in policy and no traffic hits in window. Disabled by default; vendor support is limited |

> NEEDS VERIFICATION: C02-C04, C07, C09, C10, C13, C14 names. The `cleanup_browser.htm` KC page only documented the codes above; full C01-C15 inventory is on the appliance's cleanup configuration UI.

### Run/refresh cleanup analysis

The Cleanup Browser runs continuously; there is no "kick off analysis" REST verb. The GET above returns the current state. To force a recompute, write a new revision (e.g. by re-collecting the device).

## USP (Unified Security Policy) and Violations

Base: `/securetrack/api/security_policies`. For read-heavy USP work prefer GraphQL — the REST surface here covers CRUD on matrices and exceptions.

### List USP matrices

`GET /securetrack/api/security_policies?context={domain_id}`

```json
{"security_policy_list": {"security_policy": [
  {"id": 7, "name": "Corp-USP", "description": "...", "domain_id": 1}
]}}
```

### Export / replace / delete matrix

```
GET    /securetrack/api/security_policies/{security_policy_id}/export    # text/csv
POST   /securetrack/api/security_policies                                 # multipart CSV upload
DELETE /securetrack/api/security_policies/{security_policy_id}
```

### USP exceptions

```
GET    /securetrack/api/security_policies/exceptions?context={domain_id}
GET    /securetrack/api/security_policies/exceptions/{exception_id}?context={domain_id}
POST   /securetrack/api/security_policies/exceptions/?context={domain_id}
DELETE /securetrack/api/security_policies/exceptions/{exception_id}
```

```json
{"security_policy_exception": {
  "name": "Temp DB exception",
  "description": "PROJ-44",
  "creator": "jpitt",
  "expiration_date": "2026-06-30",
  "approved_by": "sec-arch",
  "ticket_id": "CHG0456",
  "exempted_traffic_list": {"exempted_traffic": [
    {"source_zone": "DMZ", "dest_zone": "Internal-Production",
     "services": [{"protocol": "TCP", "port": 1433}]}
  ]}
}}
```

### USP violations (rule-level)

`GET /securetrack/api/violating_rules/{security_policy_id}/device/{device_id}`

Returns rules on `device_id` that violate matrix `security_policy_id`. Filterable by `severity` (`critical|high|medium|low`).

> NEEDS VERIFICATION: exact path. The R25-1 Swagger UI lists "Violations" under the Unified Security Policy group. The path above matches what is referenced in third-party integrations (incl. the stonecircle82/tufin-mcp repo) but the canonical Swagger spec is JS-rendered and not crawlable from outside the appliance.

### USP violations for an access request (sync/async)

`POST /securetrack/api/security_policies/{security_policy_id}/check_violations`

Body contains `sources`, `destinations`, `services`. Sync mode returns the violation list inline; async mode returns 202 + a `Location` to poll.

> NEEDS VERIFICATION: exact path and body. KC references this resource as "Access Request Violations" but does not show the canonical URL outside the appliance Swagger.

## Policy Analysis (rule-level, not topology-level)

```
GET /securetrack/api/devices/{device_id}/policy_analysis?
       sources=Any&destinations=Any&services=Any&action=&exclude=
```

Returns the rules that match the supplied flow on the specified device(s). Different from path analysis: this asks "which rules match," not "what is the path."

---

# SecureChange

Base: `/securechangeworkflow/api/securechange/`. Owns ticket lifecycle, access requests, Designer, Verifier, Risk, recertification, decommission, dynamic assignment.

Auth is the same SecureChange Basic Auth principal across all endpoints. Multi-domain mode: the per-ticket `domain_name` field handles routing. Some endpoints accept an `X-Tufin-Domain` header.

## Tickets

### Create ticket

`POST /securechangeworkflow/api/securechange/tickets`

The body is workflow-shaped. `workflow.name` must match an existing active workflow exactly (case-sensitive). The first `step.tasks.task.fields` shape depends on workflow type. Body for an access-request workflow:

```json
{
  "ticket": {
    "subject": "API: Allow web app to DB",
    "priority": "Normal",
    "domain_name": "Default",
    "workflow": {
      "name": "Firewall Change Request",
      "uses_topology": true
    },
    "requester": "jpitt",
    "steps": {
      "step": [
        {
          "name": "Submit Access Request",
          "tasks": {
            "task": {
              "fields": {
                "field": {
                  "@xsi.type": "multi_access_request",
                  "name": "Required Access",
                  "access_request": {
                    "order": "AR1",
                    "use_topology": true,
                    "targets": { "target": { "@type": "ANY" } },
                    "users":   { "user": ["Any"] },
                    "sources": {
                      "source": [
                        { "@type": "IP", "ip_address": "10.20.30.40", "netmask": "255.255.255.255", "cidr": 32 }
                      ]
                    },
                    "destinations": {
                      "destination": [
                        { "@type": "IP", "ip_address": "10.50.60.70", "netmask": "255.255.255.255", "cidr": 32 }
                      ]
                    },
                    "services": {
                      "service": [
                        { "@type": "PROTOCOL", "protocol": "TCP", "port": 443 }
                      ]
                    },
                    "action": "Accept",
                    "comment": "Submitted via MCP"
                  }
                }
              }
            }
          }
        }
      ]
    },
    "comments": ""
  }
}
```

Field rules:
- `priority`: `Critical | High | Normal | Low` (case-sensitive).
- `action`: `Accept | Drop | Remove`.
- `targets.target.@type`: `ANY` for topology-driven, `{"@type":"Object","object_name":"<device>","object_type":"firewall"}` for device-targeted workflows.
- `services.service.@type`: `PROTOCOL` (with `protocol` + `port`), `PREDEFINED` (with `name`), or `APPLICATION_IDENTITY`.
- `sources` / `destinations` accept `IP`, `RANGE` (with `range_first_ip` / `range_last_ip`), `OBJECT` (with `object_name`, `management_id`), `ANY`, `INTERNET`, `LDAP_ENTITY`, or `DNS`.

Response: `201 Created`. The `Location` header carries the new ticket URL ending in the new numeric ticket ID. Body returns the full ticket as persisted, including `id`, `current_step`, `status: "In Progress"`, and the resolved `requester`. The Firewall-Access-Request demo expects exactly `201` and reads the ID from `Location`.

State on creation: ticket lands at the first step of the named workflow. Assignment behavior follows the workflow's first-step config (auto-assign to handler group, dynamic assignment via custom script, or unassigned/pickup pool).

> NEEDS VERIFICATION: returning the ticket body vs. just `Location` is workflow-config dependent. Some appliances return `201` with empty body; always read the `Location` header and follow up with `GET /tickets/{id}` for guaranteed shape.

### List ticket IDs by status

`GET /securechangeworkflow/api/securechange/tickets?status={status}`

Status values (canonical, from `pytos/securechange/definitions.py`): `In Progress`, `Closed`, `Cancelled`, `Rejected`, `Resolved`, `Pending`, `Pending Update`, `Expired`. URL-encode the space (`In%20Progress`).

Response: a wrapper with `ticket_ids.ticket_id` as a list of integers. This endpoint returns IDs only; expand with `GET /tickets/{id}` per ID for content. Pagination via `start` and `count` (defaults: `start=0`, `count=100`; max page size is appliance-tuned, typically 1000).

### Get ticket by ID

`GET /securechangeworkflow/api/securechange/tickets/{ticket_id}`

Returns the full ticket: id, subject, priority, status, sla_status, requester (id+name+email), current_step (id+name), workflow (id+name), domain_name, open_request_id, completion_data, steps with all tasks and fields. Append `.json` for explicit JSON when `Accept` negotiation is unreliable: `GET /tickets/3.json`.

### Update task fields

`PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}` — whole-task replace. Body is the full `task` element with updated `fields`.

### Update single field

`PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/fields/{field_id}` — touch a single field without re-sending the whole task. Body is the field element with new value. This is the call mediator scripts use to push handler decisions back into the ticket so the workflow can advance. Use `steps/current` instead of a numeric step ID when you don't already know the active step.

### Cancel / Reject

```
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/cancel   # admin/requester action
PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/reject   # in-workflow handler action
```

Both accept a comment param. `cancel` moves to `Cancelled` terminal state; `reject` body is rejection comment (`{"comment":"..."}`) and sets state to `Rejected`.

### Reassign requester

`PUT /securechangeworkflow/api/securechange/tickets/{ticket_id}/change_requester/{user_id}` — body is comment. The new `user_id` must already exist in SecureChange.

### Implement multi-group change (advance hook)

`PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/current/tasks/{task_id}/multi_group_change/implement` — used by the multi-group-change task type to push the implementation, which advances the ticket to the next step.

> NEEDS VERIFICATION: there is no single generic "advance to next step" endpoint. Advancement happens implicitly when handler-side fields are set to terminal values via `PUT .../fields/{field_id}` and the task's completion criteria are met. Multi-group-change has an explicit `implement` action; other task types advance on field write.

### State machine

| From | Trigger | To |
|------|---------|----|
| (new POST) | first-step landing | `In Progress` |
| `In Progress` | handler completes step | `In Progress` (next step) |
| `In Progress` | final automation/closure step finishes | `Resolved` (awaiting requester confirm) |
| `Resolved` | requester confirms or auto-close | `Closed` |
| `Resolved` | requester reopens | `In Progress` (back to a configured step) |
| any | admin/requester `cancel` | `Cancelled` |
| any | handler `reject` | `Rejected` |
| time-bounded | past expiry | `Expired` (resubmittable) |

## Ticket steps and tasks

### Reassign task to user

`PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/reassign/{user_id}` — body is comment. Changes handler for this step's task only; does not alter requester. Used both by humans and dynamic-assignment scripts.

### Redo step

`PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/redo/{to_step_id}` — body is comment. Sends the ticket back to an earlier step for rework. `to_step_id` must be a step the workflow allows redo-to.

### Get current step / task data

Use `GET /tickets/{id}` and read `current_step` plus its `tasks.task[].fields.field[]`. The shape of `field` varies by `@xsi.type`: `multi_access_request`, `text_area`, `checkbox`, `drop_down_list`, `multiple_selection`, `manager`, `approve_reject`, `multi_target`, `server_decommission_request`, `rule_decommission_request`, `rule_modification_request`, `rule_recertification`, `multi_group_change`. Mediator scripts decode the field type to know which fields are set vs. need setting.

## Ticket history and audit

### Get ticket history

`GET /securechangeworkflow/api/securechange/tickets/{ticket_id}/history`

Returns chronological `history_activities.history_activity[]` with: timestamp, performed_by (user), action (`CREATE`, `ASSIGN`, `REASSIGN`, `ADVANCE`, `REDO`, `FIELD_CHANGE`, `COMMENT`, `ATTACHMENT`, `REJECT`, `CANCEL`, `RESOLVE`, `CLOSE`, `REOPEN`), step_name, task_name, and a free-text description. This is the audit log.

> NEEDS VERIFICATION: comments and attachments on a ticket. The R25 KC documents the UI surface (10 MB attachment cap, comment threads), but I did not find a dedicated `POST /tickets/{id}/comments` or `POST /tickets/{id}/attachments` endpoint in the pytos SDK source or the demo scripts. Comments are written as field updates inside a task that has a `text_area` comment field, and as the comment string accepted by `cancel`, `reject`, `change_requester`, `redo_step`, and `reassign_task`. Attachments may require multipart on a path like `/tickets/{id}/attachments` — confirm against the on-appliance Swagger UI before wiring.

## Workflows

### List workflows

`GET /securechangeworkflow/api/securechange/workflows`

> NEEDS VERIFICATION: this endpoint exists per the R25 KC ("To see the available REST APIs for SecureChange, go to https://<host>/securechangeworkflow/apidoc") and the Workflow Integrator docs reference it, but neither pytos 1.x nor the public demo scripts call it directly — they pass workflow names statically. Expect a list of `workflow` elements with `id`, `name`, `description`, `enabled`, and a workflow `type` discriminator (e.g. `ACCESS_REQUEST`, `SERVER_DECOMMISSION`, `RULE_DECOMMISSION`, `RULE_RECERTIFICATION`, `RULE_MODIFICATION`, `GROUP_CHANGE`, `CLONE_SERVER`).

### Get workflow definition

`GET /securechangeworkflow/api/securechange/workflows/{workflow_id}`

> NEEDS VERIFICATION: per Swagger UI on the appliance, this returns the full step list and per-step field definitions (so callers can build a valid ticket body for that workflow). Confirm field-name and pagination on a real instance.

Practical workaround until the workflows endpoint is verified: keep a small static map of supported workflow names → body templates per MCP server install, sourced from the customer's SecureChange admin.

## Access requests (multi_access_request data model)

The data model used inside ticket bodies for access-request workflows. Reused by Designer, Verifier, and Risk endpoints (they index into the ticket via the `multi_access_request` field's order ID).

```
multi_access_request
  access_request[]            # one or more, identified by order (AR1, AR2, ...)
    order                     # AR1, AR2 ...
    use_topology              # bool
    targets.target[]          # ANY | Object (firewall name + management_id)
    users.user[]              # "Any" or LDAP user/group strings
    sources.source[]          # IP | RANGE | OBJECT | ANY | INTERNET | LDAP_ENTITY | DNS
    destinations.destination[]
    services.service[]        # PROTOCOL (protocol+port) | PREDEFINED (name) | APPLICATION_IDENTITY
    action                    # Accept | Drop | Remove
    comment
    labels                    # optional tagging
```

The `order` value (`AR1`, `AR2`, ...) is the index used by Designer, Verifier, and Risk endpoints when dereferencing a specific access request inside the field.

## Designer

### Get Designer results

`GET /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/multi_access_request/{ar_id}/designer`

Returns Designer's per-device implementation suggestions for the access request: per-device `device_suggestion[]` containing rule placement, NAT changes, group object updates, and a status field (`DESIGNER_SUCCESS`, `DESIGNER_PARTIAL`, `DESIGNER_NO_SUGGESTIONS`, `DESIGNER_CALCULATING`).

### Get Designer instructions

`GET .../multi_access_request/{ar_id}/designer/device/{device_id}/instructions` — per-device CLI / API instructions Designer generated. Shape includes ordered `instruction[]` with rule text and binding metadata.

### Update Designer (recalc / apply)

`POST .../multi_access_request/{ar_id}/designer/redesign`

> NEEDS VERIFICATION: the recalc/redesign verb exists in the on-appliance Swagger UI but is not exercised by the public pytos. Confirm path and body.

Async behavior: when a Designer step starts, the GET returns `DESIGNER_CALCULATING` until the topology/path computation completes. Poll with backoff. Inline-Designer (the default in R25) is faster than OPM-Designer; OPM Designer can take minutes for large topologies. The page at https://forum.tufin.com/support/kc/latest/Content/Suite/4381.htm explicitly notes: "API behavior differs between Inline and OPM Designer implementations."

## Verifier

### Get Verifier results

`GET /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/multi_access_request/{ar_id}/verifier`

```
verifier_results
  verifier_target[]
    name                       # device name
    management_id
    verifier_result            # IMPLEMENTED | NOT_IMPLEMENTED | NOT_AVAILABLE | VERIFIED_MANUALLY
    severity                   # Critical | High | Medium | Low | None
    fully_implemented          # bool
    not_implemented_traffic    # array of source/dest/service triples that fail
```

Indicator mapping (from KC): green = fully implemented; red = not implemented (some or all traffic blocked); yellow = `NOT_AVAILABLE` / Verifier could not run (typically missing topology or device offline).

### Get Verifier topology map (PNG)

`GET .../multi_access_request/{ar_id}/verifier/topology_map` — binary PNG of the path topology for the access request. Useful for attaching to ServiceNow tickets or war-room entries; in MCP, return as a base64-encoded resource.

Async behavior: Verifier runs at step entry. If the GET returns no `verifier_result` (or returns a `pending` status), poll until present. SLA is workflow-configured but typically completes in seconds.

## Risk Analysis

### Get Risk results (USP-based)

`GET /securechangeworkflow/api/securechange/tickets/{id}/steps/{step_id}/tasks/{task_id}/multi_access_request/{ar_id}/risk`

> NEEDS VERIFICATION: path string assembled by analogy with `verifier`. Confirm against on-appliance Swagger UI; some R25 builds expose risk under the `/risk_analysis` segment.

### External (third-party) Risk Analysis

Per https://forum.tufin.com/support/kc/latest/Content/Suite/ThirdPartyRiskAnalysis.htm, third-party risk runs as a server-side script under `/opt/tufin/data/securechange/scripts/`, not as a customer-callable REST endpoint. Results land back in the ticket as a Risk field with these per-AR keys:

```
field_uuid              # which access_request this result belongs to
status                  # NO_RISK | HAS_RISK | CANNOT_COMPUTE
score                   # numeric
severity                # CRITICAL | HIGH | MEDIUM | LOW
comment
detailed_report_url     # optional deep-link
```

From the MCP server's perspective: read risk by `GET /tickets/{id}` and inspecting the Risk field on the relevant step's task. Do not try to invoke external risk scripts via REST — that is server-internal.

## Devices in SecureChange

### List excluded devices

`GET /securechangeworkflow/api/securechange/devices/excluded` — returns the device IDs that are excluded from SecureChange ticket targeting (those devices won't appear in target pickers or be considered by Designer/Verifier).

### Set excluded devices

`PUT /securechangeworkflow/api/securechange/devices/excluded` — body: `<excluded_devices><device_id>1</device_id><device_id>5</device_id>...</excluded_devices>`. Whole-list replace, not delta.

### Domain-aware device list

The full device inventory (used to populate `target.object_name` + `management_id`) comes from SecureTrack, not SecureChange:

```
GET /securetrack/api/devices?vendor=&model=&domain_id=N&name=
```

In multi-domain mode, build the targeting picker by combining `GET /securetrack/api/devices?domain_id=N` minus `GET /securechange/devices/excluded`.

## Custom workflow scripts (mediator interface)

SecureChange triggers a server-side mediator script at `/opt/tufin/data/securechange/scripts/<name>` on every workflow event. The mediator receives the trigger envelope on stdin and the event type via the `SCW_EVENT` environment variable.

### Trigger envelope (mediator stdin)

```json
{
  "ticket_info": "<base64-encoded XML>",
  "event": "CREATE | ADVANCE | CLOSE | CANCEL | RESOLVE | REJECT | REDO | REOPEN | RESUBMIT | AUTOMATIC_STEP_FAILED",
  "script": {
    "name": "my_custom_script.py",
    "argv": "extra args from workflow config"
  }
}
```

### Decoded `ticket_info` XML (key fields)

```
<ticket_info>
  <id>1234</id>
  <subject>...</subject>
  <priority><id>2</id><name>Normal</name></priority>
  <createDate>2026-04-30T12:00:00Z</createDate>
  <updateDate>2026-04-30T12:05:00Z</updateDate>
  <requester>
    <id>42</id><name>jpitt</name><email>justin@cdw.com</email>
  </requester>
  <current_stage>
    <id>9876</id><name>Risk Review</name>
    <task><id>...</id><name>...</name></task>
    <handler><id>7</id><name>secops-team</name></handler>
  </current_stage>
  <current_stage_name>Risk Review</current_stage_name>
  <completion_step_id>...</completion_step_id>
  <open_request_id>...</open_request_id>
  <open_request_name>...</open_request_name>
  <comment>optional comment from the triggering action</comment>
</ticket_info>
```

### Events fired

| Event | Fires when |
|-------|-----------|
| `CREATE` | Ticket POSTed and lands at first step |
| `ADVANCE` | Ticket moves to a new step (forward) |
| `REDO` | Handler returns ticket to an earlier step |
| `RESOLVE` | All handler steps complete; awaiting requester confirmation |
| `CLOSE` | Final closure (post-resolve confirmation, or auto-close step) |
| `CANCEL` | Admin / requester cancels |
| `REJECT` | Handler rejects |
| `REOPEN` | Requester reopens after RESOLVE/CLOSE |
| `RESUBMIT` | Expired ticket resubmitted |
| `AUTOMATIC_STEP_FAILED` | An automatic (provisioning) step errored |

### Mediator → SecureChange callbacks

The mediator uses standard SecureChange REST to push handler decisions back. Common patterns:

- Read full ticket: `GET /securechangeworkflow/api/securechange/tickets/{id}.json`
- Set a field value (and thereby advance): `PUT /securechangeworkflow/api/securechange/tickets/{id}/steps/current/tasks/{task_id}/fields/{field_id}` with the field XML/JSON
- Reject: `PUT /tickets/{id}/reject` with `{"comment": "..."}`
- Reassign: `PUT /tickets/{id}/steps/{step_id}/tasks/{task_id}/reassign/{user_id}`

The mediator script itself contains no business logic — it base64-decodes `ticket_info`, forwards to the customer's web service in JSON, and shells the response back. Tufin documents the mediator as fixed-format and uploaded to TOS via the SecureChange admin UI.

### Workflow types and per-type body shapes

The first step's `field` element changes by workflow type. Confirmed from pytos `xml_objects/rest.py`:

- **Access Request** (`Firewall Change Request`, custom): `field @xsi.type="multi_access_request"` (shape above).
- **Server Decommission**: `field @xsi.type="server_decommission_request"` with `<servers><server><ip_address>...</ip_address></server></servers>`. Used by the XSOAR `tufin-create-decom-ticket` command and the Tufin SecureX Cisco demo.
- **Rule Decommission**: `field @xsi.type="rule_decommission_request"` with `<devices><device><management_id/><bindings><binding><uid/><rules><rule><uid/></rule></rules></binding></bindings></device></devices>` referencing SecureTrack rule UIDs.
- **Rule Recertification**: `field @xsi.type="rule_recertification"` with the same rule-UID structure plus a `recertification_status` per rule (`CERTIFY`, `DECERTIFY`, `NEEDS_REVIEW`).
- **Rule Modification**: `field @xsi.type="rule_modification_request"` with original rule references plus the modified source/destination/service deltas.
- **Group Change** / multi-group: `field @xsi.type="multi_group_change"` plus `PUT .../multi_group_change/implement` to advance.

> NEEDS VERIFICATION: full body shapes for Recertification and Rule Modification. The pytos test suite references `server_decomm_ticket.xml` resource but not corresponding recert/modify resource files; build those from the on-appliance Swagger UI or by exporting an existing ticket via `GET /tickets/{id}` and reusing as a template.

## SecureChange notes for MCP / SOAR wrappers

- Default `Accept: application/json`. The XML-native serializer wraps single-element lists oddly (e.g. `services.service` is a single object on POST when there's one service, an array on GET); be lenient on parse, strict on serialize. Use the JSON examples here verbatim and don't second-guess `service` vs `service[]`.
- POST /tickets returns 201 with `Location: .../tickets/{new_id}`. The body may be empty depending on appliance config. Always re-fetch the ticket via `GET /tickets/{new_id}` after create to materialize the canonical state.
- Field names are case-sensitive everywhere: `priority` values, `action` values, `@xsi.type` discriminators, `workflow.name`.
- Polling: Designer can stay in `DESIGNER_CALCULATING` for tens of seconds on OPM mode; Verifier is usually sub-second. Set MCP tool timeouts accordingly and surface "still calculating" as a non-error result so the agent can re-poll.
- Async write semantics: a `PUT .../fields/{field_id}` returns 200 quickly but the workflow advance happens server-side; the next `GET /tickets/{id}` may still show the old `current_step` for ~1 second. If the MCP wraps "advance" as one tool call, do a brief poll-then-return.
- Multi-domain: pass `domain_name` in the ticket body; do not rely on a global default if the appliance has more than one domain.
- Error patterns: 400 on invalid `workflow.name`, 403 on workflow not visible to the auth user, 404 on unknown ticket ID, 409 on advance attempt against a step whose required fields are not yet set.

---

# SecureApp

Base: `/securechangeworkflow/api/secureapp/`. Owns applications, application connections, servers (network objects scoped to an application), application interfaces, and the customer (multi-domain) wrapper.

Auth is the same SecureChange/SecureApp Basic Auth principal. Default content type is XML; append `.json` to the path or set `Accept: application/json` to get JSON. Both formats accepted in request bodies via `Content-Type`.

All write operations against `applications/{app_id}/connections` auto-generate an underlying SecureChange ticket when SecureApp is wired to a workflow. Treat connection writes as state-changing.

Pagination: `start` + `count` query params on list endpoints (default count 50, max 2000 per Tufin guidance). Responses include a `total` attribute on the wrapping list element.

## Applications

### List applications

`GET /securechangeworkflow/api/secureapp/repository/applications`

Query params: `name=<app_name>` (case-insensitive substring), `start`, `count`, `customer_id` (multi-domain).

```json
{
  "applications": {
    "count": 2,
    "total": 2,
    "application": [
      {
        "id": 12,
        "name": "Payments-Prod",
        "comment": "PCI app",
        "decommissioned": false,
        "status": "ACTIVE",
        "created": "2024-11-03T18:21:14Z",
        "modified": "2025-09-30T12:08:09Z",
        "owner": {"id": 7, "name": "jdoe", "display_name": "Jane Doe", "link": {"@href": "..."}},
        "customer": {"id": 1, "name": "Default"}
      }
    ]
  }
}
```

### Get application

`GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}` — returns the full document including `editors`, `viewers`, embedded `connections`, `open_tickets`, `connection_to_application_packs`.

### Create application

`POST /securechangeworkflow/api/secureapp/repository/applications/` (trailing slash required — pytos sends it).

```json
{
  "applications": {
    "application": [
      {
        "name": "Payments-Prod",
        "comment": "PCI app",
        "owner": {"id": 7},
        "customer": {"id": 1},
        "editors": {"editor": [{"id": 7}]},
        "viewers": {"viewer": [{"id": 12}]}
      }
    ]
  }
}
```

Response: `201 Created` with `Location` header. Empty body.

### Update / Delete application

```
PUT    /securechangeworkflow/api/secureapp/repository/applications/             # whole-collection replace; pass full Application object including id
DELETE /securechangeworkflow/api/secureapp/repository/applications/{app_id}
```

## Application connections

Connections are the unit that auto-generates SecureChange tickets when changed. Source / destination / service objects are references by `id` and `type` to entities in the application or in SecureTrack.

### List connections

```
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections           # summary
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections_extended  # sources/destinations/services fully resolved
```

Use `connections_extended` for one-shot detail without N+1 calls.

### Get connection

`GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections/{connection_id}`

```json
{
  "connection": {
    "id": 904,
    "name": "Web-to-DB",
    "external": false,
    "status": "ACTIVE",
    "comment": "App-tier to DB-tier",
    "sources": {
      "source": [
        {"id": 41, "name": "web-svr-grp", "display_name": "Web Server Group",
         "type": "host_group", "link": {"@href": ".../network_objects/41"}}
      ]
    },
    "destinations": {
      "destination": [
        {"id": 58, "name": "db-cluster", "display_name": "DB Cluster",
         "type": "host", "link": {"@href": ".../network_objects/58"}}
      ]
    },
    "services": {
      "service": [
        {"id": 1011, "name": "tcp-1521", "display_name": "Oracle 1521",
         "link": {"@href": ".../services/1011"}}
      ]
    },
    "open_tickets": {"ticket": []},
    "connection_to_application": null
  }
}
```

### Create connections

`POST /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections`

`external: true` flags traffic that exits the app boundary. Source/dest/service objects need at minimum `{id, type}` for refs to existing items, or full inline object for new ad-hoc ones (depends on application policy).

```json
{
  "connections": {
    "connection": [
      {
        "name": "Web-to-DB",
        "external": false,
        "status": "ACTIVE",
        "comment": "Created via API",
        "sources":      {"source":      [{"id": 41, "type": "host_group"}]},
        "destinations": {"destination": [{"id": 58, "type": "host"}]},
        "services":     {"service":     [{"id": 1011}]}
      }
    ]
  }
}
```

Response: `201 Created`. If the application is wired to a workflow, a SecureChange ticket is opened automatically; the ticket id appears in `open_tickets` on subsequent GETs.

### Update / Delete / Repair connection

```
PUT    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections/{connection_id}    # single
PUT    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections                    # bulk collection
DELETE /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections/{connection_id}
POST   /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections/{connection_id}/repair
```

`repair` opens a repair ticket in SecureChange when the connection is broken (missing topology path or rule). No body required.

## Servers (network objects scoped to an application)

In SecureApp, "servers" live under the network_objects endpoint. Types include `host`, `host_group`, `subnet`, `range`, `external`.

```
GET    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/network_objects
GET    /securechangeworkflow/api/secureapp/repository/network_objects                                  # global, supports name filter
GET    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/network_objects/{id}
POST   /securechangeworkflow/api/secureapp/repository/applications/{app_id}/network_objects
PUT    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/network_objects            # collection-level update
DELETE /securechangeworkflow/api/secureapp/repository/applications/{app_id}/network_objects/{id}
```

### Get server (host example)

```json
{
  "network_object": {
    "@type": "host",
    "id": 58,
    "name": "db-cluster",
    "display_name": "DB Cluster",
    "comment": "Primary OLTP cluster",
    "ip": "10.42.7.50",
    "is_global": false,
    "application_id": 12,
    "link": {"@href": ".../network_objects/58"}
  }
}
```

### Create server

The `@type` discriminator selects the schema (`host`, `host_group`, `subnet`, `range`).

```json
{
  "network_objects": {
    "network_object": [
      {
        "@type": "host",
        "name": "new-svr-01",
        "comment": "Onboarded via API",
        "ip": "10.42.7.61"
      }
    ]
  }
}
```

Subnet variant: replace `ip` with `ip` + `netmask`. Range variant: `min_ip` / `max_ip`. Group variant: `members.member[]` referencing existing object ids.

### Cloud-discovered servers (read-only)

`GET /securechangeworkflow/api/secureapp/cloud_console/servers?vendor=<aws|azure|gcp>&search_string=<substring>` — useful to seed application onboarding from existing cloud inventory.

## Application interfaces

Interfaces are reusable connection bundles published by an application for consumption by other applications.

```
GET    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/application_interfaces
GET    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/application_interfaces/{id}
POST   /securechangeworkflow/api/secureapp/repository/applications/{app_id}/application_interfaces
DELETE /securechangeworkflow/api/secureapp/repository/applications/{app_id}/application_interfaces/{id}
```

```json
{
  "application_interface": {
    "id": 301,
    "name": "Public-API",
    "comment": "Externally consumable HTTPS surface",
    "is_published": true,
    "application_id": 12,
    "interface_connections": {
      "interface_connection": [
        {"id": 4001, "name": "ingress-https", "services": {"service": [{"id": 1003, "name": "tcp-443"}]}}
      ]
    }
  }
}
```

> NEEDS VERIFICATION: PUT (update) on a single interface. `pytos/secureapp/helpers.py` exposes only list/get/create/delete for `application_interfaces`. Updates are typically done by deleting and recreating, or by editing through the Connection-to-Application-Pack.

## Connection-to-application mapping (reverse lookup)

Used to ask "what other applications consume my interfaces" or "what interface does this connection bind to."

```
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections_to_applications
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connections_to_applications/{conn_to_app_id}
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connection_to_application_packs
GET /securechangeworkflow/api/secureapp/repository/applications/{app_id}/connection_to_application_packs/{pack_id}
```

> NEEDS VERIFICATION: POST/PUT/DELETE for `connection_to_application_packs`. `pytos` shows only GET helpers; create/edit appears to flow through the SecureChange "Connect Applications" workflow ticket rather than direct REST writes.

## Application owners and ACLs

Owners, editors, and viewers are embedded in the Application resource and modified via the Application PUT, not via standalone endpoints.

- `owner`: single Application_Owner reference (id, name, display_name, link). Required on create.
- `editors.editor[]`: list of user references with edit rights.
- `viewers.viewer[]`: list of user references with read-only rights.

To add an editor: GET the application, append to `editors.editor`, PUT the whole `applications` collection back.

### List SecureApp users

```
GET    /securechangeworkflow/api/secureapp/repository/users
GET    /securechangeworkflow/api/secureapp/repository/users/{user_id}
POST   /securechangeworkflow/api/secureapp/repository/users/
DELETE /securechangeworkflow/api/secureapp/repository/users/{user_id}
```

User fields: `id, name, display_name, type` (LOCAL / LDAP / ROLE), `is_global`, `ip` (for identity-aware policies), `comment`.

## Services (catalog, not a connection field)

Application-scoped and global service catalogs.

```
GET    /securechangeworkflow/api/secureapp/repository/applications/{app_id}/services
GET    /securechangeworkflow/api/secureapp/repository/services                            # global, name=<substring> filter
POST   /securechangeworkflow/api/secureapp/repository/applications/{app_id}/services      # local
POST   /securechangeworkflow/api/secureapp/repository/services/                            # global
PUT    /securechangeworkflow/api/secureapp/repository/...                                  # update on either path
DELETE /securechangeworkflow/api/secureapp/repository/services/{service_id}
DELETE /securechangeworkflow/api/secureapp/repository/services?name=<service_name>
DELETE /securechangeworkflow/api/secureapp/repository/applications/{app_id}/services/{service_id}    # local only
```

Service body shape (TCP example):

```json
{
  "services": {
    "service": [
      {"@type": "tcp_service", "name": "tcp-1521", "min_port": 1521, "max_port": 1521,
       "comment": "Oracle TNS"}
    ]
  }
}
```

ICMP variant uses `@type: icmp_service` with `type_min` / `type_max`. Group: `@type: group_service` with `members.member[]`.

## Customers (multi-domain)

```
GET /securechangeworkflow/api/secureapp/customers
GET /securechangeworkflow/api/secureapp/customers/{customer_id}
GET /securechangeworkflow/api/secureapp/customers/{customer_id}/applications
```

Each application carries a `customer.id`. In single-domain TOS, all apps map to customer id 1 ("Default").

---

# Pagination

REST endpoints that return lists support `start` (zero-based, default 0) and `count` query parameters. Responses include `count` (rows returned) and `total` (total available). To page rows 51-60: `start=50&count=10`.

```
GET /securetrack/api/devices/254/rules?start=0&count=100
GET /securetrack/api/devices/254/rules?start=100&count=100
```

GraphQL uses `first` (default 100, max 500) and `offset` on the `values` field, not on the wrapper. See `references/graphql.md`.

## SecureTrack pagination cheat sheet

| Endpoint family | Default `count` | Max `count` |
|-----------------|-----------------|-------------|
| `devices`, `domains`, `zones` | 50 | 3000 |
| `rule_search/{device_id}`, `devices/{id}/rules`, `revisions/{id}/rules` | 100 | 3000 |
| `network_objects/search`, `devices/{id}/network_objects/` | 50 | 3000 |
| `topology/clouds` | 50 | 3000 |

For really large pulls, the KC explicitly recommends paging instead of `count=3000` ("Performance" doc) because USP-violation and rule-search calls are heavy.

## SecureChange / SecureApp pagination

- SecureChange ticket-list endpoints: `start=0`, `count=100` defaults; max page size is appliance-tuned, typically 1000.
- SecureApp list endpoints: `start` + `count`, default 50, max 2000 per Tufin guidance. Responses include `total` on the wrapping list element.

---

# Errors and Common Quirks

## Error shape

Returned as `{"result": {"code": "...", "message": "..."}}` in JSON or `<result><code>...</code><message>...</message></result>` in XML. See the table in the [Errors](#errors) section above.

## SecureTrack quirks

1. **Always set `Accept: application/json`.** A missing Accept header gets XML and most JSON parsers will choke.
2. **Coerce singletons to lists.** `devices.device`, `network_objects.network_object`, `rules.rule`, `zones.zone`, `services.service` all switch shape between `dict` (count=1) and `list[dict]` (count>1). Wrap reads in an `as_list()` helper.
3. **Pass `context` everywhere in multi-domain installs.** Calls without `context` silently return only the global domain even when the user can see more.
4. **CSV id syntax.** Many resources accept `?devices=20,21,22` or path segments like `revisions/{id}/services/100,101,102`. Build comma-joined lists, not repeated query params.
5. **`includeIncompletePaths=true` on every topology path query** unless the caller explicitly wants strict end-to-end. Without it, an asymmetric or partially-modeled network returns "no path" with no diagnostic.
6. **`displayBlockedStatus=true` on path_image.** Otherwise the rendered PNG hides the blocking firewall, which is exactly the thing operators are looking for.
7. **No `ip=` zone lookup.** Resolve IP-to-zone client-side by listing zones then iterating `zones/{id}/entries` with longest-prefix match.
8. **Bulk add returns 202.** Treat `/devices/bulk/`, `/topology/synchronize`, and access-request violation submissions as async by default; expose poll-status as a separate MCP tool, not a hidden wait.
9. **Generic device upload is multipart, not JSON.** `configuration_file`, `device_data` (JSON string part), and `update_topology` together. Setting `Accept: */*` is required because the API returns 200 with an empty body.
10. **Permissions silently filter.** A 200 with `count=0` on a list endpoint frequently means "the API user can't see those rows," not "they don't exist." Document this in any tool descriptions that wrap list calls.

## SecureChange quirks

1. **Workflow names are exact-match, case-sensitive.** A typo in `workflow.name` returns 400 with the bad name in the message.
2. **POST /tickets returns 201 with `Location` only on some configs.** Always re-fetch via `GET /tickets/{new_id}` to materialize state.
3. **Async write semantics.** `PUT .../fields/{field_id}` returns 200 quickly but workflow advance happens server-side; the next `GET /tickets/{id}` may still show the old `current_step` for ~1 second.
4. **No generic "advance" verb.** Field-write triggers advance. Multi-group-change is the exception — it has an explicit `implement` action.
5. **Designer can stay in `DESIGNER_CALCULATING` for tens of seconds** on OPM mode; Verifier is usually sub-second. Surface "still calculating" as a non-error result.

## SecureApp quirks

1. **Connection writes auto-create SecureChange tickets** when the app is wired to a workflow. Treat these as tier-2 writes with explicit confirmation, not safe metadata edits.
2. **`@type` discriminators are required** on network_objects (`host`, `host_group`, `subnet`, `range`) and services (`tcp_service`, `udp_service`, `icmp_service`, `group_service`).
3. **Bulk PUT replaces the whole collection** for updates; don't send a single-item collection thinking it patches.

## Cross-cutting

1. **Read default-format trap.** XML by default everywhere. Always set `Accept: application/json`.
2. **JSON single-element arrays.** Some endpoints return a single-element array as a bare object instead of a one-item list. Defensive code: coerce to a list before iterating.
3. **GraphQL pagination cap.** `first` is capped at 500. Loop on `offset` past 500.
4. **Audit trail.** SecureTrack > Admin > Audit Trail records every user action including API calls. Forward to syslog if you need long-term retention. The recorded source IP may be the in-cluster pod IP rather than the external client IP in proxy/ingress deployments.
5. **API account password rotation.** When the password changes via the UI, the user is prompted to reset on next login and must complete the reset before any API calls succeed. Rotate carefully: change password, log into UI as that account, complete the reset, then update the credential store. Otherwise the integration breaks.
6. **Multi-domain.** If TOS is configured for multiple domains, the user accounts split into Super Admin / Multi-Domain Admin / Multi-Domain User / Domain User. Cross-domain reads need Super Admin. SecureChange does not support Security Zones in Multi-Domain mode (per Tufin docs).
7. **TLS.** TOS supports TLS 1.2 and later. Check appliance certs; replace self-signed with corporate CA-issued certs before pointing automations at it.

---

# pytos2 (Python SDK)

Tufin Professional Services maintains pytos2-CE: `https://gitlab.com/tufinps/pytos2-ce`. Wraps SecureTrack, SecureChange, and GraphQL calls. Useful for custom workflow scripts (mediator-side) where you want typed Python objects instead of hand-rolling XML.

The original `pytos` (`github.com/Tufin/pytos`) is older but still in use. It includes a hook framework: `Secure_Change_Helper` registers Python functions to fire on workflow events (CREATE, CLOSE, CANCEL, REJECT, ADVANCE, REDO, RESUBMIT, REOPEN, RESOLVE, plus auto-step events TARGET_SUGGESTION_STEP, VERIFIER_STEP, DESIGNER_STEP, RISK_STEP, IMPLEMENTATION_STEP).

Reach for pytos2 if writing new mediator-side scripts in Python; treat pytos as legacy.

# Postman

Tufin publishes Postman collections per release: `https://forum.tufin.com/support/kc/rest-api/R25-1/tss_postman_collections.zip`. Import them, set environment variables (`{{securetrack_ip}}`, `{{securechange_ip}}`, `{{username}}`, `{{password}}`), and you can browse the full surface. Postman ships SSL verification on by default; turn it off for self-signed labs but leave it on in production.

# API version / introspection

No public version endpoint. The Swagger UI on the appliance reports the version (e.g. `SecureTrack Version: 25-1 PHF3.1.0` for R25-1 PHF3). For programmatic identification, use the TOS Version header returned on every response: `X-TOS-Version: <version>` and `Server: Tufin`.

> NEEDS VERIFICATION: header name. Confirm against an actual response from the CDW R25-1 PHF3 appliance.
