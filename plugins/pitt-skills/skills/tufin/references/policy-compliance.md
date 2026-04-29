# Unified Security Policy, Network Zones, Compliance, and Cleanup

Reference for SecureTrack's policy and compliance surface. USP, network zones, security zone matrices, the Cleanup Browser, and how compliance frameworks (PCI DSS, NERC CIP, etc.) get implemented as USP matrices.

## Network Zones

A **network zone** is a named group of IPv4 or IPv6 network addresses, security groups, or other zones. Zones are the source/destination atom for the USP and for compliance evaluation.

### Built-in zones (cannot be deleted)

- **Internet**: all addresses considered public; everything not in another zone. Cannot be edited. In access requests, used for paths to URL categories or Internet objects (default IP `8.8.8.8`). If your URL categories are inside your network, use the `Set Zone as URL Category Zone` REST API to remap.
- **Unassociated Networks**: RFC 1918 private IPv4 addresses not assigned to any other zone. Included in violations, risk, and compliance calculations. Excluded from policy analysis, compliance policy definition, business ownership, risk reports, risk security zone configuration (Internal/DMZ/External), and PCI profile definition.
- **Users Networks**: subnets users connect from; available for devices that support User Identity. Not supported for USPs.

### What a zone can contain

- IPv4 / IPv6 subnets (entries).
- Security groups (cloud SG names matched by pattern; e.g. AWS, Azure, GCP).
- Other zones (zone hierarchy).

Zones can include other zones to build hierarchy, used for compliance zone collection.

### Zone names

Avoid `>` in zone names (compatibility issue across some devices).

### Managing zones

- UI: `SecureTrack > Browser > Zones`.
- REST: `/securetrack/api/zones` for CRUD; `/zones/{id}/entries` for subnets; separate sub-resources for security groups and patterns.
- CSV import/export for bulk zone load.
- **IPAM Security Policy App (ISPA)** integrates with external IPAMs to keep zones in sync automatically.

## Unified Security Policy (USP)

A USP is a matrix that defines what traffic is allowed (or required to be blocked) between zones. Cells in the matrix specify:

- Required services (allowed list, blocked list, or any).
- Required rule properties (logging on, comments present, no `ANY`, etc.).
- Severity if violated (Critical, High, Medium, Low).
- Flow type restrictions (Host-to-Host, Subnet-to-Host, Host-to-Subnet) and quantitative restrictions (max destination IPs).

You can have multiple USPs. Each one expresses a different policy domain (PCI DSS, NERC CIP, internal best practices, segmentation between business units).

SecureTrack continuously matches the actual rulebases against every USP and surfaces violations. SecureChange's Risk Analysis evaluates new access requests against USPs before approval.

### Limits and behaviors

- Max 100 source or destination zones per matrix (hard UI limit).
- Any-to-Any rules: SecureTrack shows only the first 100 violations for these rules to keep performance sane.
- Global cap: when total violations across the system reach 850,000, SecureTrack shows only the first 100 violations per rule.
- IPv6 is **not** supported for USPs.
- User Networks zones is **not** supported for USPs.
- Only administrators and super administrators can access the USP tab.

### Building a USP

1. Prep zones first. Use a zone hierarchy that reflects the policy structure.
2. Create the matrix: `SecureTrack > Browser > USP Viewer > +`.
3. Add zones to rows and columns. Mark each cell with the requirement.
4. Save. Violations populate against the new matrix on the next revision pull.

CSV import/export is available for matrix definitions. ISPA can keep zones aligned automatically.

### USP exceptions

When a known violation is acceptable, document it as a USP exception. Exceptions suppress violations for matching rules.

R25-1 PHF1+ added **zone-based USP exceptions**: you can use entire zones as source or destination in exceptions, not just IPs. Cuts down on unnecessary violations when the exception applies to entire zone subnets. Implemented via API.

### USP API

REST surface for USPs is thin. Use GraphQL.

```graphql
{
  usps {
    values {
      name
      changed
      securityZones { name }
    }
  }
}
```

Filter by zone:

```graphql
{
  usps(filter: "zones.name = 'Production'") {
    values {
      name
      securityZones { name }
    }
  }
}
```

USP alert config and exception mutations exist in GraphQL: `createUspAlertConfig`, `updateUspAlertConfig`, `deleteAlertConfig`, plus exception equivalents.

## Violations

Surfaced in the Violations browser. Each violation links a rule to the USP cell it violates and the severity. Tracked per device.

REST:
```
GET /securetrack/api/violating_rules/{device_id}/device_violations?...
```

GraphQL is more flexible:

```graphql
{
  violations(filter: "severity = 'CRITICAL'") {
    count
    values {
      severity
      rule { id idOnDevice device { name } }
      usp { name }
    }
  }
}
```

To see violations on a specific rule: query Rule Viewer with `violations.usp.name = '...'` or `violationHighestSeverity <= 'HIGH'`.

R25-1 added USP violations for **Azure NSGs installed on subnets**. R25-1 PHF1+ added cloud-policy USP compliance for AWS, GCP, and Azure NSGs installed on a NIC.

## Compliance Frameworks

Compliance frameworks are built as USP matrices using compliance zones (placeholder zones). You map your real zones into the compliance zones via the zone hierarchy. As the network evolves, periodically review the hierarchy.

### Built-in compliance USPs

- **PCI DSS v4**: workflow creates a PCI USP with the required compliance zones; you select the appropriate user zones for each.
- **Best Practices**: matrix that flags risky services (telnet, rsh, etc.), required rule properties (comments present, logging on, no `ANY`, no `ANY` source/destination).
- **NERC CIP**: similar pattern.

### Required rule properties (Best Practices)

- All rules must have comments.
- Rule logging must be enabled.
- Rules may not allow `Any` service. Use Automatic Policy Generation (APG) to tighten overly permissive rules.

## Cleanup Browser

`SecureTrack > Browser > Cleanup` surfaces redundant, shadowed, unused, and duplicate items. Each cleanup category has an ID (C-prefix) and a configurable severity.

| Cleanup ID | Description | Notes |
|---|---|---|
| C01 | Fully shadowed and redundant rules | Rules that never get hit because higher rules cover them. Click Details to see shadowing rules. |
| C06 | Unattached network objects | Objects not used in security policy. Verify they aren't used in NAT rules or VPN connections. |
| C08 | Empty groups | Group objects with no members. |
| C11 | Duplicate network objects | Same IP/netmask, same zone. Group dupes match on members. |
| C12 | Duplicate services | Match on protocol/port/range fields. Excludes some vendor-specific fields (PA source port, PA timeout, JNS service timeout, CP protocol type). |
| C15 | Unused network objects | Disabled by default. Enable in `Settings > Configuration > Cleanup` and pick the usage period. Not supported on Panorama, FortiManager, Cisco Firepower, Cisco Meraki, or AWS. |

Other cleanup types exist; the IDs above are the most common automation targets. Use the Cleanup Configuration UI to see the full set and adjust severities.

### Cleanup REST

```
GET /securetrack/api/cleanups
GET /securetrack/api/devices/{device_id}/cleanups
GET /securetrack/api/devices/{device_id}/cleanups/{cleanup_id}
```

Export cleanup instances to CSV for downstream automation (e.g. feeding a SecureChange Rule Decommission ticket).

### Limitations

- Some cleanups don't support IPv6 (except NSM IPv6 objects in unused-objects).
- For VIP-supporting devices (e.g. F5), the cleanup rule must be global to match.
- Rule and object usage data is required for unused-* cleanups; ensure usage is enabled per device.

## Rule Optimization

Beyond cleanup, SecureTrack offers rule tightening:

- **Automatic Policy Generation (APG)**: builds an optimized rulebase by allowing only the traffic actually in use, based on real traffic logs.
- **Rule Optimizer** (R25-2 added support for AWS, Azure NSGs, Zscaler ZIA): suggests tighter source/destination/service for existing rules using last-hit data. Adjustable strictness.
- **Best Practices Report**: surfaces violations of the property USPs (no comment, not logged, etc.).

Rule Viewer TQL can find optimization candidates directly:

```
permissivenessLevel = 'HIGH' and timeLastHit after 90 days ago
ruleOptimizerRecommendations exists
readyForOptimization = true
```

## R25-1 Cleanup-Adjacent Features

- **AWS Security Group unused-rule cleanup** via rule analytics, last-hit info, scheduled best-practice reports. Removes need for manual log analysis.
- **Last Hit on Check Point objects**: identifies unused objects in CP rules. Requires switching to the new Check Point syslog processing method.
- **Last hit for Zscaler ZIA cloud firewall** rules and objects. Enables Rule Analytics-based cleanup on Zscaler.
- **Comments in revision history**: editable for GCP, Meraki, Arista, OPM devices.
- **Automatic MZTI (Map Zones To Interfaces)** for SecureTrack+. Improves USP precision; reduces false positives. Maps interface to zone based on network configuration.

## Compliance Frameworks Mapping (CDW Examples)

For Justin's M&A integration runbook, the USP-as-compliance-control pattern is high leverage:

- For acquired companies, build a **scoped USP** named after the acquisition (`Acquired-CompanyA-Inbound-Restrictions`). Use it to express the temporary segmentation constraints during the integration window. Violations flag any rule that breaks the acquisition's transit policy.
- For federal customers under CMMC Level 2, the USP can express the segregation requirements between commercial and federal workloads.
- For internal best practices, a single **Best Practices** USP carrying property requirements (logging on, comments present, no ANY) enforces consistency across all monitored devices.

The shape these take is always: zones first, hierarchy second, USP matrix third. CSV import the matrix once you have it stable.

## Common Patterns

### "Build a zone for an acquired company's CIDR space"

```
POST /securetrack/api/zones
{ "zone": { "name": "Acquired-MissionCloud", "description": "..." } }

POST /securetrack/api/zones/{id}/entries
{ "zone_entry": { "ip": "172.31.0.0", "netmask": "255.255.0.0" } }
```

Or import from CSV via the Zones UI.

### "Find all critical USP violations on a vendor"

```graphql
{
  violations(filter: "severity = 'CRITICAL'") {
    values {
      severity
      rule { device { name vendor } idOnDevice }
      usp { name }
    }
  }
}
```

Then filter client-side on `vendor = 'PALO_ALTO'`.

### "Identify rules that are decommissioning candidates today"

```
permissivenessLevel = 'HIGH' and timeLastHit before 365 days ago and timeLastModified before 180 days ago
```

Pipe results into a SecureChange Rule Decommission ticket.

### "Find all rules touching a USP exception"

```
isExemptedFromUsp = true
```

Or scope to one exception:

```
uspExceptionName = 'PCI-Allowed-Outbound-DNS'
```

### "Periodically resync zones from IPAM"

Use ISPA. If ISPA is not in scope, write a script that:
1. Pulls zones from your IPAM.
2. Diffs against `/securetrack/api/zones` + `/zones/{id}/entries`.
3. POSTs new entries; DELETEs entries that no longer exist.
4. Logs the diff for the audit trail.

Keep zone churn low. Frequent resyncs with broad subnet changes regenerate USP violations and burn CPU.
