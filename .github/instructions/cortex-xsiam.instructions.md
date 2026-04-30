---
applyTo: "**"
description: Cortex XSIAM (Extended Security Intelligence and Automation Management) by Palo Alto Networks - the AI-driven SOC platform unifying SIEM, SOAR, XDR, EDR, ASM, UEBA, TIP, and CDR. Use this skill whenever the user mentions XSIAM, Cortex, XQL queries, correlation rules, BIOC rules, parsing rules, data modeling rules, XDM (Cortex Data Model), XSOAR playbooks in XSIAM, case or issue or incident investigation, threat hunting, alert triage, data ingestion, causality chains, the Cortex Marketplace, content packs, dashboards, widgets, XSIAM APIs, Broker VM, Identity Threat Module, Attack Surface Management, endpoint protection profiles, engines, or any SOC automation and detection engineering tasks within the Palo Alto Cortex ecosystem. Also trigger when the user asks about writing detection rules, building custom integrations, onboarding log sources, creating automations, or investigating security cases - even if they don't explicitly say "XSIAM." This skill covers XQL syntax, data pipelines, detection engineering, SOAR automation, identity threat, ASM, endpoint protection, engines, tenant administration, and operational best practices.
---

# Cortex XSIAM Skill

## Terminology Note

> **XSIAM has two overlapping detection surfaces and one grouping entity:**
>
> - **Alerts surface** - older XDR alerts surface. The Alerts page lists detections from data sources (Splunk, CrowdStrike, MSFT Defender, Azure AD, Okta, Palo Alto NGFW, etc.). API: `POST /public_api/v1/alerts/get_alerts/`, `alerts` dataset.
>
> - **Issues surface** - modern unified XSIAM detection surface. The Issues page lists detections from any detection method: `CORRELATION`, `XDR_ANALYTICS`, `XDR_ANALYTICS_BIOC`, `XDR_BIOC`, `VULNERABILITY_POLICY`, `ASM`, `CSPM_SCANNER`, `CUSTOM_ALERT`. API: `POST /public_api/v1/issue/search/`, `issues` dataset. Most analyst triage starts here because it's the unified view.
>
>   The two surfaces share IDs but return different field shapes - calling them by the same ID against different endpoints returns different objects.
>
> - **Case** - top-level grouping for related issues. The primary working object for SOC analysts. AI-driven grouping stitches issues sharing entities (host, user, hash, IP) and attack patterns into one case. Cases carry severity, status, assignee, SLAs. API: `case_id` field, with an `issues` array listing member issues.
>
> **"Incident" - separate from "case."** Palo Alto's older XDR/XSOAR APIs use "incident" as a grouping entity (`/incidents/`, `demisto.incidents()`, `fetch-incidents`). At the API level, **cases and incidents are separate, both still active.** Cases bridge to incidents via `custom_fields.incident_id`. Don't conflate them.
>
> **Field schema gotchas:**
> - `parent` context fields exist on issues but **do not appear in default API responses** and are not in any Palo Alto public documentation. They are effectively hidden by default - Palo Alto support discloses both names and request shape on request.
> - Reads (`/alerts/get_alerts/`, `/issue/search/`) require **integer** IDs in `id` / `alert_id_list` filters. Writes (`/alerts/update_alerts/`) require **string** IDs in payload.
> - Issue resolution writes route through `alerts/update_alerts/` even though the entity is an issue.
>
> See [references/xsiam-api.md](references/xsiam-api.md) for the working contract per endpoint.

## What This Skill Covers

This skill helps you work effectively with Palo Alto Networks Cortex XSIAM across its major functional areas:

1. **XQL (XDR Query Language)** - Writing queries for threat hunting, investigation, dashboards, and detection rules
2. **Detection Engineering** - Correlation rules, BIOC rules, analytics alerts
3. **Data Pipeline** - Data ingestion, parsing rules, data model (XDM) rules, datasets
4. **SOAR & Automation** - Playbooks, integrations, scripts, the Cortex Marketplace
5. **Case Management** - Triage, case investigation, causality chains, response actions
6. **Platform Operations** - Dashboards, widgets, reports, APIs, Broker VM, agent management
7. **Identity Threat** - Identity Analytics, Identity Threat Module (ITM), Cloud Identity Engine
8. **Attack Surface Management** - External asset discovery, ASM rules, attack surface testing
9. **Endpoint Protection** - Profiles, exception mechanisms, host hardening
10. **Engines** - Runtime substrate for playbooks, scripts, and integrations
11. **Tenant Administration** - Cortex Gateway, BYOK, Remote Repository, RBAC, SSO

## Reference Files

Read these files for detailed guidance on specific topics. **Always read the relevant reference file before answering detailed questions.**

| File | When to read (concrete trigger phrases) |
|---|---|
| [references/xql-reference.md](references/xql-reference.md) | Writing or debugging XQL - syntax, datasets, operators, functions, stages, examples, performance |
| [references/detection-engineering.md](references/detection-engineering.md) | Authoring or tuning correlation, BIOC, IOC, ABIOC rules; alert mapping; MITRE ATT&CK classification |
| [references/data-pipeline.md](references/data-pipeline.md) | Onboarding a log source, parsing rules, data model rules, XDM mapping, custom datasets, Broker VM, XDRC, **data retention + cold storage**, **AI Detection & Response (AIDR)** |
| [references/soar-automation.md](references/soar-automation.md) | Designing or debugging playbooks, integration instances, content packs, **Marketplace lifecycle / support tiers / version-pin**, automation patterns |
| [references/soar-development.md](references/soar-development.md) | Building custom integrations or scripts - Python/JS conventions, YAML metadata, demisto-sdk, content pack structure, conditional task YAML grammar, unit tests, reputation commands |
| [references/case-ops.md](references/case-ops.md) | Investigating a case - War Room, Causality View, Timeline, **Action Center**, response actions (isolate, live terminal, search-and-destroy, memory image, remediate changes), CLI commands |
| [references/case-customization.md](references/case-customization.md) | Customizing case/alert UX - incident scoring & starring, custom fields, layouts, timer fields & SLAs, automation rules, custom statuses, incident domains |
| [references/identity-threat.md](references/identity-threat.md) | Identity Analytics, Identity Threat Module (ITM add-on), Cloud Identity Engine, risky users/hosts, honey users, asset roles, asset scores |
| [references/endpoint-protection.md](references/endpoint-protection.md) | Endpoint profiles (malware/exploit/restrictions/agent settings), exception rules (alert exclusion, disable prevention, IOC/BIOC exception, support exception, global policy exception), endpoint hardening, host firewall, disk encryption, vuln assessment |
| [references/attack-surface-mgmt.md](references/attack-surface-mgmt.md) | ASM - external services/IPs/websites discovery, scanning cadence, externally inferred CVEs, Threat Response Center, Attack Surface Testing, attack surface rules |
| [references/engines.md](references/engines.md) | Engines - runtime substrate for playbooks/scripts/integrations, Docker/Podman, install/upgrade/remove, d1.conf configuration, load-balancing groups, web-proxy setup |
| [references/tenant-administration.md](references/tenant-administration.md) | Tenant onboarding - Cortex Gateway, BYOK, native Remote Repository (dev→prod content sync), RBAC roles + user scope, SSO/SAML setup (Okta, Azure AD) |
| [references/xsiam-api.md](references/xsiam-api.md) | Calling the XSIAM API directly - endpoints, auth headers, request/response shapes, ID-type quirks, async write behavior, status enums, `parentIncidentFields` |
| [references/xsiam-environment-audit-queries.md](references/xsiam-environment-audit-queries.md) | Pre-built XQL queries for auditing a tenant: data sources, parsing rule coverage, correlation rule inventory, alert volumes by source, content pack inventory |

## Top Rules

When helping with XSIAM tasks:

1. **Specify the dataset** in every XQL query - don't rely on defaults unless the user is explicitly querying `xdr_data`.
2. **Use XDM-normalized fields** (`xdm.*`) for cross-source queries; raw dataset fields for vendor-specific queries.
3. **Map correlation rule alert fields** to improve case grouping - minimum: hostname, username, IP, alert name.
4. **Test XQL in the Query Builder** before deploying in correlation rules, dashboards, or scheduled queries.
5. **Watch the 5,000-hit auto-disable** - correlation rules exceeding 5,000 hits per 24h are automatically disabled.
6. **Verify dataset names in the tenant** - `alerts` vs `xdr_alerts` and similar pairs vary between XDR and XSIAM tenants.
7. **Mind Compute Unit (CU) consumption** - filter early, `fields` to limit columns, avoid unfiltered full-dataset scans in production queries and scheduled rules.
8. **Reference MITRE ATT&CK** tactics/techniques on detection rules for proper classification.
9. **Use precise terminology** - "alert," "issue," "case," and "incident" are distinct entities (see terminology block above). Don't conflate.
10. **Reach for the Marketplace first** for integrations and content packs before custom-building.

## Quick Orientation

Cortex XSIAM is a cloud-delivered, AI-driven SOC platform combining SIEM, SOAR, XDR, EDR, ASM, UEBA, TIP, and CDR.

### Sensors & Data Collection

- **Cortex XDR Agent** - endpoint sensor on Windows/Mac/Linux/Android. EDR telemetry, malware/exploit prevention, response.
- **Broker VM** - on-prem VM running collector applets (Syslog, Kafka, CSV, DB, NetFlow, WEC, etc.). **XDR Collector (XDRC)** is a separate Filebeat/Winlogbeat-based log collector - distinct from the XDR agent.
- **Cloud-to-Cloud + NGFW** - API collectors for SaaS (Azure AD, O365, AWS, GCP). Palo Alto firewalls forward via Strata Logging Service.

### Cortex Data Model (XDM)

The normalized cross-source schema. Pipeline flow:

**Raw Logs → Parsing Rules (ingest-time) → Dataset → Data Model Rules (query-time) → XDM fields**

Use `xdm.*` for cross-source queries; raw dataset fields for vendor-specific work.

### Causality

XSIAM stitches processes/files/network/cloud events into causality chains automatically.

- **Causality Group Owner (CGO)** - root process of a chain.
- **Causality Chain** - full tree under the CGO.
- **Spawners** - normal-OS parent processes (`explorer.exe`, `services.exe`, `wininit.exe`, `userinit.exe`); know these to distinguish benign vs. suspicious ancestry.
- **Causality View** - visual surface for process, network, cloud, and SaaS causality.

### Cases, Issues, Alerts

See the terminology block above for the verified definitions. The short version: **Alerts** (older XDR surface) and **Issues** (modern unified surface) are detection events; **Cases** group related issues for analyst work; **Incidents** are a separate Palo Alto grouping concept that still exists at the API level. Cases are the primary working object for SOC analysts on XSIAM.

### Detection Rules

| Type | How It Works | Best For |
|---|---|---|
| **Correlation Rules** | XQL query runs on schedule or real-time against any dataset | Complex multi-field logic, cross-source correlation, custom detections |
| **BIOC** | Pattern matching on endpoint behavioral events (process, file, registry, network) | Known TTPs on endpoints. Limited to `xdr_data` and `cloud_audit_log` datasets |
| **IOC** | Match known indicators (hashes, IPs, domains, URLs) against ingested data | Known-bad indicator matching |
| **ABIOC (Analytics)** | ML-based anomaly detection, builds baselines from historical data | Detecting unknown threats, behavioral anomalies |
| **Attack Surface Rules** | Rules for external-facing asset risk detection | ASM-driven detections |
| **Palo Alto Built-in** | Pre-built detections delivered by Palo Alto, continuously updated | Broad coverage, zero configuration |

## Key Navigation Paths in XSIAM UI

- **XQL Query Builder**: Incident Response → Investigation → Query Builder
- **Correlation Rules**: Detection & Threat Intel → Detection Rules → Correlations
- **BIOC Rules**: Detection & Threat Intel → Detection Rules → BIOC
- **Parsing Rules**: Settings → Configurations → Data Management → Parsing Rules
- **Data Model Rules**: Settings → Configurations → Data Management → Data Model Rules
- **Playbooks**: Incident Response → Automation → Playbooks
- **Marketplace**: Settings → Configurations → Content Management → Marketplace
- **Dashboards**: Dashboards (top nav)
- **Cases**: Incident Response → Incidents *(UI label may still say "Incidents" - this is where cases live)*
- **Endpoints**: Assets → Endpoints
- **Playground**: Incident Response → Investigation → Playground
- **Quick Launcher**: Keyboard shortcut for fast navigation and action execution

> **UI Note**: Some XSIAM navigation labels still use "Incident" (e.g., "Incident Response" menu). These are Palo Alto's default UI labels - the objects you're working with are cases.

## Common XQL Patterns (Quick Reference)

```xql
// Basic query with filter
dataset = xdr_data
| filter agent_hostname = "workstation01"
| fields agent_hostname, action_process_image_name, action_file_path

// Count events by type
dataset = xdr_data
| comp count() as event_count by action_process_image_name
| sort event_count desc

// Cross-dataset query using XDM
datamodel dataset = panw_ngfw_traffic_raw
| filter xdm.source.ipv4 = "10.0.0.5"
| fields xdm.source.ipv4, xdm.target.ipv4, xdm.target.port

// Time-bounded search
dataset = xdr_data
| filter _time >= timestamp("2025-01-01T00:00:00Z")
| filter action_process_image_name contains "powershell"
```

## Developer Reference

### Content Development Artifacts

When building custom content packs, integrations, or automations:

| Artifact | Format | Purpose |
|---|---|---|
| Integration Definition | YAML | Defines commands, parameters, and configuration |
| Integration Code | Python / JavaScript | Implementation logic for integration commands |
| Playbook | YAML | Defines workflow tasks, conditions, and connections |
| Script (Automation) | Python / JavaScript | Standalone automation scripts |
| Incident Type | JSON | Custom incident type definitions |
| Incident Field | JSON | Custom field definitions for incidents |
| Layout | JSON | UI layout definitions for incidents and alerts |
| Widget | JSON | Dashboard widget definitions |
| Classifier | JSON | Incoming data classification rules |
| Mapper | JSON | Field mapping rules for incoming data |

### Development Tools

- **demisto-sdk**: CLI tool for development, linting, testing, and packaging content packs
- **Docker/Podman**: Execution environment for integrations and scripts
- **GitHub**: Contribution workflow for Marketplace content
- **Developer docs**: https://xsoar.pan.dev/

## Licensing Tiers

- **XSIAM Enterprise**: Core platform with SIEM, XDR, SOAR, EDR, UEBA, CDR
- **XSIAM Enterprise Plus**: Adds advanced capabilities
- **Add-ons**: ASM, TIM (Threat Intelligence Management), Forensics, ITDR (Identity Threat Detection and Response), Compute Units, Endpoint Event Forwarding

## Glossary

| Term | Definition |
|---|---|
| **Alert** | A detection event from a data source (Splunk, CrowdStrike, MSFT Defender, Azure AD, etc.) or XSIAM analytics, surfaced on the Alerts page. Older XDR concept; lives in the `alerts` dataset. |
| **Issue** | A detection event surfaced on the Issues page from any detection method (correlation, BIOC, ABIOC, IOC, analytics, ASM, vulnerability, custom). Modern unified detection entity; lives in the `issues` dataset. |
| **Case** | Top-level grouping of related issues. The primary working object for SOC analysts. Carries severity, status, assignee, SLAs. |
| **Incident** | Palo Alto's older XDR/XSOAR grouping concept, separate from "case" at the API level. Both are still active. Cases bridge to incidents via `custom_fields.incident_id`. |
| **CGO** | Causality Group Owner - root process in a causality chain |
| **XDM** | Cortex Data Model - normalized data schema |
| **BIOC** | Behavioral Indicators of Compromise - pattern-based endpoint detections |
| **ABIOC** | Analytics Behavioral Indicators of Compromise - ML-driven behavioral detections |
| **ASM** | Attack Surface Management - continuous external asset discovery |
| **BYOML** | Bring Your Own Machine Learning - custom ML model integration |
| **CDR** | Cloud Detection and Response |
| **DBot** | Automated reputation scoring engine for indicators |
| **IOC** | Indicator of Compromise - known malicious indicators |
| **ITDR / ITM** | Identity Threat Detection and Response / Identity Threat Module |
| **NGFW** | Next-Generation Firewall |
| **TIM** | Threat Intelligence Management |
| **UEBA** | User and Entity Behavior Analytics |
| **WEC** | Windows Event Collector |
| **Broker VM** | On-premise virtual machine for data collection via applets |
| **XDRC** | XDR Collector - on-premise log collector using Filebeat/Winlogbeat, distinct from XDR agent |
| **XQL** | XSIAM Query Language |

## Key Documentation Links

- Official Docs: https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-Documentation
- XSOAR Developer Hub: https://xsoar.pan.dev
- Cortex Marketplace: https://cortex.marketplace.pan.dev
- XQL Queries GitHub: https://github.com/PaloAltoNetworks/cortex-xql-queries
- API Reference: https://cortex-panw.stoplight.io/docs/cortex-xsiam-1
- Training: https://beacon.paloaltonetworks.com
