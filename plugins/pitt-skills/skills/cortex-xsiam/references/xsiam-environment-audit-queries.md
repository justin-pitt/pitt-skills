# XSIAM Environment Audit Queries

> **Purpose**: Copy-paste these into the XQL Query Builder to assess current state across playbooks, integrations, detection rules, data pipeline, and SOC operations.
> **Note**: Verify dataset names in your tenant schema pane before running. XSIAM uses `alerts` (not `xdr_alerts`). Append `| view column order = populated` to any query if you want cleaner output.

---

## 1. Playbook & Automation Audit

### 1.1 — Alert Types With vs. Without Playbook Coverage
```xql
// Which alert sources are generating work and do they have automation?
// Run this first to find your biggest automation gaps
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as alert_count,
      count_distinct(agent_hostname) as unique_hosts
  by alert_source, alert_name, severity
| sort alert_count desc
| limit 100
```

### 1.2 — Alert Volume by Severity (Last 30 Days)
```xql
// Understand the shape of your alert load
// High volume + low severity = automation candidates
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as alert_count by severity
| sort alert_count desc
```

### 1.3 — Top 20 Noisiest Alert Names
```xql
// These are your top tuning or automation targets
// Cross-reference with SOC lead to confirm which are pain points
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as alert_count,
      count_distinct(agent_hostname) as unique_hosts,
      count_distinct(action_remote_ip) as unique_ips
  by alert_name, severity, alert_source
| sort alert_count desc
| limit 20
```

### 1.4 — Alert Volume Trend by Hour (Spot Spikes & Patterns)
```xql
// Look for recurring spikes that indicate noisy rules or scheduled scans
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("7d"))
| comp count() as alert_count by bin(_time, 1h)
| sort _time asc
```

### 1.5 — Alerts That Never Became Cases
```xql
// These alerts fire but don't correlate into cases
// Either they're low-severity noise or the grouping logic isn't catching them
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter severity in ("LOW", "INFORMATIONAL")
| comp count() as alert_count by alert_name, alert_source
| sort alert_count desc
| limit 50
```

---

## 2. Detection Rules Audit

### 2.1 — Correlation Rule Change History
```xql
// Who changed what and when — audit trail for all rule modifications
dataset = correlationsauditing
| fields _time, rule_name, action, user_name, status
| sort _time desc
| limit 200
```

### 2.2 — Correlation Rules by Alert Volume (Find Noisy & Silent Rules)
```xql
// High-volume rules need tuning or suppression
// Zero-volume rules may be broken or targeting missing data
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter alert_source = "Correlation Rule"
| comp count() as alert_count,
      count_distinct(agent_hostname) as unique_hosts,
      min(_time) as first_seen,
      max(_time) as last_seen
  by alert_name, severity
| sort alert_count desc
```

### 2.3 — Rules Approaching Auto-Disable Threshold
```xql
// XSIAM auto-disables rules at 5,000 hits/24h
// Find rules trending toward that limit
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("24h"))
| filter alert_source = "Correlation Rule"
| comp count() as hits_24h by alert_name
| filter hits_24h >= 1000
| sort hits_24h desc
```

### 2.4 — BIOC Rule Alert Inventory
```xql
// Separate BIOC signal from correlation rule signal
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter alert_source = "BIOC"
| comp count() as alert_count,
      count_distinct(agent_hostname) as unique_hosts
  by alert_name, severity
| sort alert_count desc
```

### 2.5 — Alert Sources Summary (All Detection Types)
```xql
// Full picture: what's generating alerts and how much
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as alert_count,
      count_distinct(alert_name) as unique_rules
  by alert_source
| sort alert_count desc
```

---

## 3. Case & SOC Workflow Audit

### 3.1 — Case Volume and Resolution Metrics
```xql
// Baseline MTTR and case volume — you'll use this to show automation impact later
dataset = incidents
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as case_count,
      avg(close_time - creation_time) as avg_resolution_ms
  by severity
| sort case_count desc
```

### 3.2 — Cases by Status (Open vs. Closed Backlog)
```xql
// How many cases are sitting open? Is there a backlog?
dataset = incidents
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as case_count by status, severity
| sort case_count desc
```

### 3.3 — Cases by Assigned Analyst (Workload Distribution)
```xql
// See if work is evenly distributed or if certain analysts are overloaded
dataset = incidents
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter status != "resolved_threat_handled"
| comp count() as open_cases by assigned_user_mail
| sort open_cases desc
```

### 3.4 — Case Close Reasons (False Positive Rate)
```xql
// High FP rate = detection tuning needed
// This directly feeds your tuning backlog
dataset = incidents
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter status contains "resolved"
| comp count() as case_count by resolve_comment
| sort case_count desc
```

### 3.5 — Alerts Per Case (Grouping Quality Check)
```xql
// Very high alert-per-case ratios may indicate over-grouping
// Very low (1:1) may indicate under-grouping
dataset = incidents
| filter _time >= subtract(current_time(), to_integer("30d"))
| comp count() as case_count,
      avg(alert_count) as avg_alerts_per_case,
      max(alert_count) as max_alerts_per_case
  by severity
```

---

## 4. Data Pipeline Health Audit

### 4.1 — Data Sources Inventory (What's Flowing)
```xql
// Master list of everything ingesting into the tenant
// Cross-reference against expected sources
dataset = xdr_data
| comp count() as event_count,
      min(_time) as first_seen,
      max(_time) as last_seen
  by _vendor, _product
| sort event_count desc
```

### 4.2 — Data Source Freshness Check
```xql
// Find sources that have gone silent — gap = detection blind spot
// Any source with last_seen > 24h ago needs investigation
dataset = xdr_data
| comp max(_time) as last_event by _vendor, _product
| alter hours_since_last = timestamp_diff(current_time(), last_event, "HOUR")
| sort hours_since_last desc
```

### 4.3 — Data Volume by Source (Last 7 Days, Daily)
```xql
// Look for volume drops — a 50% drop often means a broken feed
dataset = xdr_data
| filter _time >= subtract(current_time(), to_integer("7d"))
| comp count() as event_count by _vendor, _product, bin(_time, 1d)
| sort _vendor, _product, _time
```

### 4.4 — XDM Coverage Check (Which Sources Are Normalized)
```xql
// Sources without XDM mapping don't benefit from cross-source analytics
// Run this per dataset to check XDM field population
// Replace vendor_product_raw with actual dataset names from 4.1
datamodel dataset = xdr_data
| comp count() as event_count,
      count(xdm.source.ipv4) as has_src_ip,
      count(xdm.target.ipv4) as has_dst_ip,
      count(xdm.source.user.username) as has_username,
      count(xdm.event.type) as has_event_type
  by _vendor, _product
| sort event_count desc
```

### 4.5 — Endpoint Agent Health
```xql
// Find endpoints with stale heartbeats or disconnected status
dataset = endpoints
| filter last_seen < subtract(current_time(), to_integer("24h"))
| fields endpoint_name, endpoint_type, endpoint_status, ip, os_type, last_seen, install_date
| sort last_seen asc
| limit 200
```

### 4.6 — Endpoint Coverage Summary
```xql
// How many endpoints are healthy vs. disconnected vs. lost
dataset = endpoints
| comp count() as endpoint_count by endpoint_status, os_type
| sort endpoint_count desc
```

---

## 5. Indicator & Threat Intel Audit

### 5.1 — IOC Match Activity
```xql
// Are IOC matching rules actually finding hits?
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter alert_source = "IOC"
| comp count() as alert_count by alert_name, severity
| sort alert_count desc
```

### 5.2 — Indicator Volume and Types
```xql
// What types of indicators are loaded and how many
// This tells you if ThreatConnect feed ingestion is working
dataset = alerts
| filter _time >= subtract(current_time(), to_integer("30d"))
| filter alert_source = "IOC"
| comp count() as matches by alert_name
| sort matches desc
```

---

## 6. Integration Health (Run in Playground)

These are CLI commands to run in the **Playground** (Incident Response → Investigation → Playground), not XQL queries.

```
// List all configured integrations and their status
!getModules

// Test a specific integration instance
!test-module using="CrowdStrike Falcon"

// Test ThreatConnect connectivity
!test-module using="ThreatConnect v3"

// Test ServiceNow connectivity  
!test-module using="ServiceNow v2"

// List all enabled playbooks
!getList listName=playbooks
```

> **Note**: Integration instance names may differ in your tenant. Check Settings → Configurations → Integrations for exact names.

---

## 7. Content Pack & Marketplace Audit

### 7.1 — Check Marketplace for Pending Updates
Navigate to: **Settings → Configurations → Content Management → Marketplace**
- Filter by "Updates Available"
- Note any packs with updates for CrowdStrike, ThreatConnect, ServiceNow, Prisma Cloud

### 7.2 — Installed Content Packs
Navigate to: **Settings → Configurations → Content Management → Installed Content Packs**
- Document what's installed
- Cross-reference against your tool stack — are there packs for tools you use that aren't installed?

---

## 8. Management Audit Log (Admin Activity)

### 8.1 — Recent Admin Actions
```xql
// Track who's making changes to the platform
// Useful for change management and troubleshooting
dataset = audits
| fields _time, AUDIT_OWNER_NAME, AUDIT_DESCRIPTION, AUDIT_ENTITY, AUDIT_RESULT
| sort _time desc
| limit 200
```

> **Note**: The `audits` dataset name may vary. Check your schema pane. Alternative: use the API endpoint `POST /audits/management_logs`.

---

## Priority Order for Running These

1. **4.1 + 4.2** — Data Source Inventory & Freshness (know what you're working with)
2. **1.3** — Noisiest Alerts (find the SOC's biggest pain points)
3. **2.2** — Correlation Rule Volume (find noisy and silent rules)
4. **3.1 + 3.4** — Case Metrics & FP Rate (baseline for improvement)
5. **4.5 + 4.6** — Endpoint Health (know your agent coverage)
6. **1.1** — Alert-to-Playbook Coverage Map (find automation gaps)
7. **5.1** — IOC Match Activity (verify TI is working)
8. **Playground commands** — Integration Health Checks
