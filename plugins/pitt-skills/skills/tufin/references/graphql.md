# Tufin TOS GraphQL API Reference

GraphQL surface for TOS Aurora R25-1 (CDW: 25.1 PHF3). Use this for read-heavy work that needs nested data in one round trip, cross-device rule search with rich filters, and any TQL-driven query that would be awkward as a series of REST calls. Mutations exist (USP, USP exception, USP alert, rule metadata, rule operations) but the surface is lower priority for read-mostly automation.

REST endpoint reference lives in `references/api.md`. TQL field/operator reference lives in `references/tql.md`.

## Endpoint and access

- GraphQL HTTP endpoint: `https://<TOS host>/v2/api/sync/graphql`
- GraphiQL interactive console: `https://<TOS host>/v2/api/sync/graphiql` (also reachable inside the SecureTrack UI under "GraphQL APIs")
- Distinct SNMP-only endpoint: `https://<TOS host>/v2/monitor-tower/graphiql` — do NOT route normal queries here.
- Required header: `Content-Type: application/json` (also accepts `application/graphql` for raw query body).
- Hierarchy depth limit: 20 levels per query (server-enforced).

The reference Tufin MCP at `stonecircle82/tufin-mcp` (`src/app/clients/tufin.py:execute_graphql_query`) defaults to `{securetrack_base_url}/sg/api/v1/graphql` — that path works on TOS Classic and on early Aurora releases. For Aurora R25-1 prefer `/v2/api/sync/graphql` per the official KC. Make the path env-configurable.

Request shape:

```json
{
  "query": "query($f: String) { rules(filter: $f) { count values { id name } } }",
  "variables": {"f": "action='Accept'"}
}
```

Response shape:

```json
{
  "data": {"rules": {"count": 12, "values": [{"id": "1#rule_1234", "name": "DMZ-allow"}]}},
  "errors": null
}
```

GraphQL-level errors return HTTP 200 with an `errors[]` array; treat them as failures separately from HTTP status.

## Authentication

HTTP Basic Auth, same credentials as REST. No bearer/JWT path documented in R25-1.

```
Authorization: Basic base64(user:password)
```

Account permissions in TOS scope what the query can return — multi-domain users see only their domains. Filter explicitly via `domain.name='...'` in TQL when crossing domains.

## Top-level queries (R25-1, ~21 entries)

Common pattern: each entity query returns `{ count, values(first, offset) { ...fields } }`. `count` ignores `first`/`offset` and reports total matching rows.

| Query | Args | Return | Notes |
|-------|------|--------|-------|
| `auth` | (none) | `AuthQuery { sessionUser }` | session probe |
| `version` | (none) | `VersionQuery` | version + changelog |
| `devices(filter: String)` | TQL | `DeviceQuery { count, values: [Device] }` | |
| `devicesStatus(filter: String)` | TQL | `DeviceStatusQuery` | last revision, sync status |
| `rules(filter: String)` | TQL | `RuleQuery { count, counts, values: [Rule] }` | `counts` for grouped aggregations |
| `networkObjects(filter: String)` | TQL | `NetworkObjectQuery` | polymorphic union, requires inline fragments |
| `services(filter: String)` | TQL | `ServiceQuery` | TCP/UDP/ICMP/group |
| `securityZones(filter: String)` | TQL | `SecurityZoneQuery` | |
| `zones` | (none) | `[Zone!]!` | flat list, no pagination |
| `systems(filter: String)` | TQL | `SystemQuery` | root device mgmt |
| `interfaces(filter: String)` | TQL | `InterfaceQuery` | device interfaces |
| `domains(filter: String)` | TQL | `DomainQuery` | multi-domain |
| `users(filter: String)` | TQL | `UserQuery` | TOS users |
| `usps(filter: String)` | TQL | `UspQuery { count, values: [Usp] }` | Unified Security Policies |
| `getUsps` | (none) | `[Usp]` | shorthand, no filter/pagination |
| `uspRequirements(filter: String)` | TQL | `UspRequirementQuery` | individual policy rules |
| `uspExceptions(filter: String)` | TQL | `UspExceptionQuery` | exemptions |
| `uspAlertConfigs(filter: String)` | TQL | `UspAlertConfigQuery` | violation alerting |
| `uspRiskAnalysisTask(filter: String)` | TQL | `UspRiskAnalysisTaskQuery` | risk analyses |
| `opmAgents(filter: String)` | TQL | `OPMAgentQuery` | OPM/Cloud agents |
| `userTQLSearches(filter: String)` | TQL | `UserTQLSearchQuery` | saved searches |
| `userWorkflows` | (none) | `UserWorkflowsQuery` | available workflow templates |
| `trend(input: TrendQueryInput!)` | input | `TrendResult` | time-series counts |
| `deviceConfig` | (none) | `DeviceConfigQuery` | adjustments tree |
| `ruleOptimizer` | (none) | `RuleOptimizerQuery` | optimization analysis |

> NEEDS VERIFICATION: a top-level `violations` or `uspViolations` query. Tufin's KC documents violations as a Usp sub-relationship and via the Violations browser UI. Searching violations by criteria typically goes through `usps(filter: ...)` → nested `requirements → violations` traversal, or via the REST violations endpoints under `/securetrack/api/violating_rules/`. Use `usps` first, fall back to REST if richer filter is needed.

## TQL filter syntax in GraphQL

TQL is the same DSL used in the SecureTrack UI Rule Viewer / Device Viewer. Only the surface differs from REST:

- REST passes TQL as a `?filter=` query string (URL-encoded).
- GraphQL passes TQL as the value of the `filter` argument, always a String, always wrapped in `"`.

Operators: `=`, `!=`, `contains`, `not contains`, `in`, `not in`, `exists`, `not exists`, `intersects with`, `not intersects`, `before`, `after`, `gt`, `lt`. Logical: `and`, `or`, `not`. Group with parentheses.

Field-type rules:
- Strings: single-quoted inside the TQL: `name='DMZ-allow'`. Outside the GraphQL string is the `"` wrapper.
- Booleans: bare: `disabled=true`.
- Timestamps: `YYYY-MM-DD` or relative (`30 days ago`, `last week`, `last month`). Pair with `before`/`after`.
- IPv4/IPv6: full address or CIDR. `=` matches exactly or matches containing subnets. `contains` matches subnets. `intersects with` matches any range overlap.

Composite example, in a GraphQL doc:

```graphql
query {
  rules(filter: "(action='Accept' and source.ip intersects with 10.0.0.0/8) and disabled=false") {
    count
    values(first: 100) { id name device { name } }
  }
}
```

For the full TQL field catalog (rule fields, device fields, USP fields, network-object fields), see `references/tql.md`.

## Pagination

- `first: Int` and `offset: Long` live on the `values` field of each entity query. They do not appear on the wrapper.
- `count` on the wrapper always reports unfiltered-by-pagination total. Use it for "more pages?" math: `offset + len(values) < count`.
- Default `first` = 100, max `first` = 500. Above 500 either silently caps or errors depending on entity.
- For deep traversal use offset paging in a loop. There is no cursor token in R25-1 GraphQL.

```graphql
query Page($off: Long) {
  rules(filter: "vendor='checkpoint'") {
    count
    values(first: 500, offset: $off) { id name }
  }
}
```

## Field selection patterns

Single round trip across rule → device → domain:

```graphql
query {
  rules(filter: "comment contains 'PCI'") {
    values(first: 200) {
      id
      name
      action
      device {
        id
        name
        vendor
        domain { id name }
      }
    }
  }
}
```

NetworkObjectQuery is a union — fragments required:

```graphql
query {
  networkObjects(filter: "name contains 'db'") {
    values {
      ... on Host    { id name ip }
      ... on Subnet  { id name ip netmask }
      ... on IpRange { id name minIp maxIp }
      ... on Group   { id name members { ... on Host { id name ip } } }
    }
  }
}
```

Aggregations via `counts`:

```graphql
query {
  rules(filter: "action='Accept'") {
    counts(groupBy: "device.name") { group count }
  }
}
```

> NEEDS VERIFICATION: exact `groupBy` argument name. KC describes the `counts` field shape but does not document the grouping argument name in the R25-1 page; `pytos`/MCP examples use the field but rarely the group-by clause.

## Example queries

### 1. Rules with `action=Accept` and a source in a given subnet

```graphql
query AcceptRulesFromSubnet($f: String) {
  rules(filter: $f) {
    count
    values(first: 200) {
      id name action
      source { text }
      destination { text }
      service { text }
      device { id name vendor }
    }
  }
}
```

With `variables = {"f": "action='Accept' and source.ip intersects with 10.42.0.0/16"}`.

Response:

```json
{"data":{"rules":{"count":7,"values":[
  {"id":"1#cp-mgmt-01#rule_4231","name":"Web-to-DB","action":"Accept",
   "source":{"text":"web-svr-grp"},"destination":{"text":"db-cluster"},
   "service":{"text":"tcp-1521"},
   "device":{"id":"1","name":"cp-mgmt-01","vendor":"Checkpoint"}}
]}}}
```

### 2. USP violations by matrix name (via Usp traversal)

```graphql
query ViolationsForMatrix($matrix: String) {
  usps(filter: $matrix) {
    values {
      id
      name
      securityZones { name }
      requirements {
        id
        name
        violations { id rule { id name device { name } } severity }
      }
    }
  }
}
```

With `variables = {"matrix": "name='Production-Matrix'"}`.

> NEEDS VERIFICATION: exact field names `requirements.violations`, `severity`, `rule`. Pulled from R25-2 schema page descriptions; field naming on R25-1 PHF3 may be `violatingRules` or `ruleViolations`. Confirm via GraphiQL introspection on the live tenant before relying on these.

### 3. List all devices with last revision time

```graphql
query {
  devices {
    count
    values(first: 500) {
      id
      name
      vendor
      model
      domain { name }
    }
  }
  devicesStatus {
    values(first: 500) {
      device { id name }
      lastRevision
      status
    }
  }
}
```

Two top-level queries in one request — GraphQL supports this; both resolved server-side and returned in one round trip. Join in the client by `device.id`.

### 4. Find network objects matching a name pattern

```graphql
query NetObjByName($f: String) {
  networkObjects(filter: $f) {
    count
    values(first: 100) {
      ... on Host    { id name ip device { name } }
      ... on Subnet  { id name ip netmask device { name } }
      ... on Group   { id name members { ... on Host { id name ip } } }
    }
  }
}
```

With `variables = {"f": "name contains 'db'"}`.

### 5. Cross-device rule search by destination + service

```graphql
query DstSvcRules($f: String) {
  rules(filter: $f) {
    count
    values(first: 500) {
      id name action
      device { name vendor domain { name } }
      destination { text }
      service { text }
    }
  }
}
```

With TQL like: `"destination.ip intersects with 10.42.7.50/32 and service.port=1521 and action='Accept'"`.

### 6. Recently-modified, uncertified rules

```graphql
query {
  rules(filter: "timeLastModified after 30 days ago and certificationStatus!='Certified'") {
    count
    values(first: 200) {
      id name
      timeLastModified
      metadata { certificationStatus technicalOwner applicationOwner businessOwner }
      device { name }
    }
  }
}
```

### 7. Permissive accept rules (for rule-cleanup hunts)

```graphql
query {
  rules(filter: "permissivenessLevel='HIGH' and action='Accept' and disabled=false") {
    count
    values(first: 200) {
      id name permissivenessLevel
      source { text } destination { text } service { text }
      device { name vendor }
    }
  }
}
```

### 8. Shadowed rules per device

```graphql
query {
  rules(filter: "fullyShadowed=true") {
    counts(groupBy: "device.name") { group count }
    values(first: 100) { id name device { name } }
  }
}
```

> NEEDS VERIFICATION: same `groupBy` caveat as above.

### 9. Devices by vendor with interface count

```graphql
query {
  devices(filter: "vendor='Palo Alto'") {
    count
    values(first: 200) {
      id name model
      interfaces { count }
    }
  }
}
```

### 10. USPs touching a given security zone

```graphql
query UspsForZone($f: String) {
  usps(filter: $f) {
    count
    values { id name changed securityZones { name } }
  }
}
```

With `variables = {"f": "zones.name='DMZ'"}`.

## Mutations (overview)

Top-level mutation entry points:

- `system` — add / update / delete root systems
- `deviceConfiguration` — adjustments, domain migration
- `usp` — CRUD USPs, manage zone wiring + requirements
- `uspException` — rule/traffic exceptions
- `uspAlertConfig` — violation alert config
- `ruleOperations` — ticket draft creation
- `ruleUserData` — write rule metadata (descriptions, ownership, tickets)
- `ruleOptimizer` — kick off optimization tasks
- `userTQLSearch` — saved-search CRUD + ownership
- `version` — metadata
- `zoneMapping` — zone configuration
- `riskAnalysis` — risk analysis tasks

All mutations return a `ResultStatus { success, message }` plus operation-specific output (created IDs, affected counts).

For an MCP read-mostly profile, gate mutations behind an env flag the same way `cortex-mcp` gates writes. `ruleUserData` (rule descriptions, ownership) is the most useful safe-write target.

## Notes for the MCP wrapper

- Wrap GraphQL as a single `tql_query` MCP tool plus per-entity convenience tools (`search_rules`, `search_devices`, `search_usps`). The convenience tools just compose TQL + a fixed field projection.
- Return the `count` separately so the agent can decide on pagination.
- Encode `first`/`offset` as MCP tool params; cap `first` at 500 server-side to mirror the API limit.
- Multi-domain handling: filter via `domain.name=...` in TQL.
- GraphQL-level errors come back as HTTP 200 with `errors[]`. Don't rely on HTTP status alone.
