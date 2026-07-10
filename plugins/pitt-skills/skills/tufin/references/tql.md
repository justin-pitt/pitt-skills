# Tufin Query Language (TQL)

TQL is the SQL-like filter language used in the Rule Viewer, Device Viewer, USP Viewer, USP Alerts Manager, USP Exceptions Viewer, and as the filter argument inside GraphQL queries. Same syntax everywhere; available fields differ by context.

## Basic Syntax

```
<field> <operator> <value> [<conjunction> <field> <operator> <value>] ...
```

A query is one or more clauses combined with `and` / `or`. Both have the same precedence and parse left to right. Use parentheses to override.

```
comment exists
permissivenessLevel in ('LOW','MEDIUM')
source.ip = '10.1.1.0/24' and destination.ip = '10.2.2.0/24'
(fullyShadowed = true and timeLastModified before last year) or disabled = true
order by timeLastModified
```

Strings go in single quotes. Field names are dot-separated. The query length cap is 4,000 characters including spaces.

The Tufin UI also offers natural-language search ("AI Assistant Search") that generates TQL. That's a UI feature; the underlying engine is still TQL.

## Operators

| Operator | Use |
|---|---|
| `=` | Exact equality. For IPs, exact match. |
| `!=` | Not equal. |
| `<`, `<=`, `>`, `>=` | Numeric and severity comparisons. |
| `in (...)` | Match any value in list. |
| `not in (...)` | Negation of `in`. |
| `exists` | Field has any value. |
| `not exists` | Field is unset. |
| `contains` | Substring match on text fields. |
| `before <date_or_relative>` | Time field before. |
| `after <date_or_relative>` | Time field after. |
| `order by <field>` | Sort the result. Append at end. |

Relative time literals: `today`, `yesterday`, `tomorrow`, `last week`, `last month`, `next week`, `next month`, `next year`, `<N> days ago`, `<N> weeks ago`, `<N> months ago`.

## IP Address Search Rules

IPv4 must be a complete address or range, optionally with subnet. You cannot search a partial address with `=`. Use `text` for partial-string IP search.

```
source.ip = '1.1.1.1'
source.ip = '1.1.1.1/32'
source.ip = '1.1.1.0/24'
source.ip = '1.1.1.1/255.255.255.0'
```

For an IPv4 search without subnet, the engine returns any subnet that includes the address.

IPv6: any format that resolves to the same address matches. `2001:DB8:ABCD:12::` and `2001:0DB8:ABCD:0012:0000:0000:0000:0000` are equivalent.

## Rule Viewer Fields (Most Common Surface)

This is the field set exposed in `Browser > Rule Viewer` and in GraphQL `rules { ... }` filters.

### Identity and basics

| Field | Values |
|---|---|
| `id` | Rule UUID |
| `idOnDevice` | Vendor-side rule identifier (usually order in policy) |
| `name` | Rule name |
| `comment` | Rule comment text |
| `description` | Rule description |
| `disabled` | true, false |
| `logged` | true, false |
| `priority` | int |

### Action and structure

| Field | Values |
|---|---|
| `action` | `ALLOW`, `DENY`, `GOTO`, `UNSUPPORTED`, `CLIENTAUTH` |
| `direction` | `INBOUND`, `OUTBOUND` |
| `permissivenessLevel` | `HIGH`, `MEDIUM`, `LOW` |
| `fullyShadowed` | true, false |
| `automationAttribute` | `STEALTH`, `LEGACY` (legacy = treat as shadowed by Designer) |
| `policy.name` | Parent policy name |
| `sectionTitle` | Section heading text |
| `goToTarget.name` | Layered policy target |
| `zonesRelation` | `INTERZONE`, `INTRAZONE`, `UNIVERSAL` |

### Source / Destination / Service

For each of `source.*`, `destination.*`, `service.*`, the same shape applies:

| Field | Notes |
|---|---|
| `source.ip` / `destination.ip` | Full IP, range, or CIDR |
| `source.name` / `destination.name` | Object name |
| `source.comment` / `destination.comment` | Object comment |
| `source.isAny` / `destination.isAny` / `service.isAny` | Set to ANY |
| `source.negated` / `destination.negated` / `service.negated` | Object is negated |
| `source.domainAddress` / `destination.domainAddress` | FQDN |
| `service.icmpType`, `service.icmpCode` | ICMP fields |
| `service.protocol`, `service.port` | Numeric values |
| `service.isApplicationDefault` | Service tied to application's default |
| `sourceZone.name`, `destinationZone.name` | **Vendor zones**, not USP zones |
| `sourceZone.isAny`, `destinationZone.isAny` | true, false |

### Users and applications (NGFW)

| Field | Notes |
|---|---|
| `user.name`, `user.dn` | User identity |
| `user.isAny`, `user.isAllIdentity`, `user.isGuest`, `user.isPreAuth` | Identity flags |
| `user.noHit`, `user.timeLastHit` | Identity hit tracking |
| `application.name` | Predefined or custom application |
| `application.isAny`, `application.noHit`, `application.timeLastHit` | App fields |
| `urlCategory.name`, `urlCategory.urls`, `urlCategory.isAny` | URL filtering |

### Ownership, certification, ticket linkage

| Field | Notes |
|---|---|
| `businessOwner.name`, `businessOwner.email` | Business owner of the rule |
| `technicalOwner.name` | Technical owner (documentation field) |
| `certificationStatus` | `CERTIFIED`, `DECERTIFIED` |
| `certification.isExpired` | true, false |
| `certificationOwner.name`, `certificationOwnerEmail`, `certificationComment` | Cert metadata |
| `certificationTicketld`, `certificationTicketSubject` | Linked SecureChange ticket |
| `securechangeTicketInProgressId` | In-flight ticket ID for this rule |
| `relatedTicket.text` | User-entered ticket reference |
| `secureappApplicationName`, `secureappApplicationOwner` | SecureApp linkage |

### Hits and modification

| Field | Notes |
|---|---|
| `timeLastHit` | YYYY-MM-DD, security rules; Check Point also covers NAT |
| `timeLastModified` | YYYY-MM-DD |
| `timeExpiration` | Access expiration as set by requester |
| `object.notHit`, `object.timeLastHit` | At least one rule object never hit / last hit (Azure NSG, Zscaler, Check Point with new syslog method) |

### Violations / USP linkage

| Field | Notes |
|---|---|
| `violationHighestSeverity` | `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`. Supports comparison ops. |
| `violations.fromZone`, `violations.toZone` | USP source / destination zone in the violation |
| `violations.usp.name` | Violated USP name |
| `violations.timeCreated` | Date of last violation calculation |
| `isExemptedFromUsp` | Active exception suppresses violation |
| `uspExceptionName` | Exception name |

### Optimizer / cleanup

| Field | Notes |
|---|---|
| `readyForOptimization` | true, false |
| `ruleOptimizerRecommendations` | `exists`, `not exists` |

### Device fields available in rule context

| Field | Values |
|---|---|
| `device.name` | String |
| `device.model` | Long enum: `ACI`, `ASA`, `AZURE_FIREWALL`, `AZURE_POLICY`, `AZURE_VHUB`, `AZURE_VNET`, `AZURE_VWAN`, `AWS_ACCOUNT`, `AWS_TRANSIT_GATEWAY`, `AWS_GATEWAY_LOAD_BALANCER`, `BIG_IP`, `CMA`, `FMC`, `FORTIGATE`, `FORTIMANAGER`, `FTD`, `GCP_PROJECT`, `GCP_VPC`, `IOS_XE_SDWAN`, `MDS`, `MERAKI_*`, `MX`, `NETSCREEN*`, `NEXUS`, `PANORAMA`, `PANOS`, `ROUTER`, `SMART_CENTER`, `SMART_ONE`, `SRX`, `STONESOFT`, `VMWARE_*` (NSX variants), `ZSCALER_INTERNET_ACCESS`, plus R25-1's `ARISTA_CVP`, `ARISTA_EOS` |
| `vendor` | `AMAZON`, `ARISTA`, `BARRACUDA`, `CHECKPOINT`, `CISCO`, `F5`, `FORCEPOINT`, `FORTINET`, `GOOGLE`, `JUNIPER`, `MICROSOFT`, `PALO_ALTO`, `VMWARE`, `ZSCALER`, `UNKNOWN` |
| `domain.name` | TOS domain name |

### `text` (free-text fallback)

`text = '<value>'` searches every string field across the rule. Useful for quick "find anywhere this string appears" queries.

### Sortable fields

`order by` works only on: `timeLastHit`, `timeLastModified`, `name`, `permissivenessLevel`, `violationHighestSeverity`.

## Device Viewer Fields

Subset relevant to device-scoped queries:

```
device.name
vendor
device.model
domain.name
licenseStatus
revisionStatus
timeLastRevision
```

Example:
```
device.name = 'fw-prod-01' and vendor in ('FORTINET','CHECKPOINT')
```

## USP Fields

Used in `usps { ... }` GraphQL filters:

```
name
changed
zones.name
securityZones.name
```

Example:
```
zones.name = 'Production' and changed after last month
```

## Common Recipes

```
# Stale or unused candidates
timeLastModified before 365 days ago and timeLastHit before 365 days ago

# Disabled or fully shadowed and old
(fullyShadowed = true and timeLastModified before last year) or disabled = true

# Rules without comments (audit hit)
comment not exists

# Permissive rules
permissivenessLevel in ('HIGH','MEDIUM')

# ANY anywhere
source.isAny = true or destination.isAny = true or service.isAny = true or user.isAny = true or application.isAny = true

# Risky services exposed
service.name in ('telnet','rsh','rlogin','ftp')

# Cross-zone (vendor zones, not USP)
sourceZone.name = 'dmz' and destinationZone.name = 'inside'

# Object-level cleanup hint (Azure NSG / Zscaler / Check Point new syslog)
object.notHit = true

# Find rules touching a soon-to-be-decommissioned host
source.ip = '11.22.33.44' or destination.ip = '11.22.33.44'

# Same, by object name
source.name = 'svr-prod-app01' or destination.name = 'svr-prod-app01'

# Decertified rules ready for decommission ticket
certificationStatus = 'DECERTIFIED'

# Rules with USP violations of given severity or worse
violationHighestSeverity <= 'HIGH'

# Rules that violate a specific USP
violations.usp.name = 'PCI-DSS v4'

# Rules currently in flight in a SecureChange ticket
securechangeTicketInProgressId exists

# All SecureApp-linked rules for a given application
secureappApplicationName = 'OnlinePortal'

# Text catchall
text = '198.51.100'
```

## Gotchas

1. **Vendor zones vs USP zones.** `sourceZone.name` and `destinationZone.name` are the firewall's own zone names, not the USP zones used for compliance. Use `violations.fromZone` and `violations.toZone` for USP-side queries.
2. **Auto-complete only shows predefined names.** If you have a custom application or service, type the exact name; it won't appear in the dropdown.
3. **`timeLastHit` for NAT rules** is not supported except on Check Point (with the new syslog processing method enabled).
4. **`object.notHit` and `object.timeLastHit`** are limited to Azure NSG, Zscaler, and Check Point (with new syslog method).
5. **Free text search caveat.** Wildcards on plain identifiers work; `*` is a wildcard in some screens (Free Search) but TQL prefers `contains`. Different screens, different rules. Default to `contains` in TQL.
6. **Order-of-operations.** `and`/`or` have equal precedence. Always parenthesize when mixing them or you will get surprising results.
7. **GraphQL filter quoting.** The TQL string is the value of the GraphQL `filter` argument and goes inside double quotes. Single quotes are required inside the TQL itself for string values, so do not escape them as backslash-double-quote: keep the outer quotes double, the inner quotes single.
   ```graphql
   { rules(filter: "source.ip = '10.0.0.0/8'") { count } }
   ```
