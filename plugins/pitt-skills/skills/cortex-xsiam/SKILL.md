---
name: cortex-xsiam
description: >
  Cortex XSIAM (Extended Security Intelligence and Automation Management) by Palo Alto Networks — the AI-driven SOC platform unifying SIEM, SOAR, XDR, EDR, ASM, UEBA, TIP, and CDR. Use this skill whenever the user mentions XSIAM, Cortex, XQL queries, correlation rules, BIOC rules, parsing rules, data modeling rules, XDM (Cortex Data Model), XSOAR playbooks in XSIAM, incident investigation, threat hunting, alert triage, data ingestion, causality chains, the Cortex Marketplace, content packs, dashboards, widgets, XSIAM APIs, Broker VM, or any SOC automation and detection engineering tasks within the Palo Alto Cortex ecosystem. Also trigger when the user asks about writing detection rules, building custom integrations, onboarding log sources, creating automations, or investigating security incidents — even if they don't explicitly say "XSIAM." This skill covers XQL syntax, data pipelines, detection engineering, SOAR automation, and operational best practices.
license: MIT
---

# Cortex XSIAM Skill

## What This Skill Covers

This skill helps you work effectively with Palo Alto Networks Cortex XSIAM across its major functional areas:

1. **XQL (XDR Query Language)** — Writing queries for threat hunting, investigation, dashboards, and detection rules
2. **Detection Engineering** — Correlation rules, BIOC rules, analytics alerts
3. **Data Pipeline** — Data ingestion, parsing rules, data model (XDM) rules, datasets
4. **SOAR & Automation** — Playbooks, integrations, scripts, the Cortex Marketplace
5. **Incident Management** — Alert triage, incident investigation, causality chains, response actions
6. **Platform Operations** — Dashboards, widgets, reports, APIs, Broker VM, agent management

## Quick Orientation

Cortex XSIAM is a cloud-delivered, AI-driven security operations platform. It replaces traditional SIEM + SOAR + XDR point products with a single unified platform. Key architectural concepts:

- **Data Foundation**: All telemetry (endpoint, network, cloud, identity, third-party) is ingested, parsed, normalized to XDM, and stored in **datasets** (queryable tables)
- **Analytics Engine**: 2,900+ ML models, BIOC/ABIOC rules, correlation rules, and IOC matching run against ingested data to generate **alerts**
- **Alert-to-Incident Pipeline**: Alerts are grouped into **incidents** via intelligent stitching and AI-driven scoring; routine incidents are auto-handled
- **Causality Chain**: When a detection fires, XSIAM builds the full chain of processes/events leading to the alert, with a **Causality Group Owner (CGO)** identified as the root cause
- **SOAR Engine**: Embedded playbook engine (based on Cortex XSOAR) with visual editor, marketplace content packs, and custom automation
- **Attack Surface Management (ASM)**: Continuous discovery of internet-facing assets and vulnerabilities
- **Cortex Copilot**: Built-in AI assistant for investigation assistance and threat research within the XSIAM interface

## Reference Files

Read these files for detailed guidance on specific topics. **Always read the relevant reference file before answering detailed questions.**

| File | When to Read |
|---|---|
| `references/xql-reference-v3.md` | Any XQL query writing, syntax questions, datasets, operators, functions, stages, examples, CDW dataset names, alerts field schema |
| `references/detection-engineering.md` | Correlation rules, BIOC rules, IOC rules, ABIOC, alert tuning, MITRE ATT&CK mapping |
| `references/data-pipeline.md` | Data ingestion, parsing rules, data model rules, XDM schema, custom datasets, Broker VM, log onboarding |
| `references/soar-automation.md` | Playbooks, integrations, scripts, marketplace content packs, automation design patterns |
| `references/soar-development.md` | Building custom integrations, Python code conventions, YAML metadata, content pack structure, unit testing, demisto-sdk CLI commands, reputation commands |
| `references/xsiam-api.md` | XSIAM REST API authentication, XQL query API async flow, event collector integrations, mirroring patterns, long-running containers, integration cache, API endpoint catalog |
| `references/case-ops.md` | Case lifecycle (CDW terminology), alert-to-case pipeline, causality views, investigation workflow, response actions, operational dashboards |
| `references/xsiam-environment-audit-queries.md` | Pre-built XQL queries for auditing the CDW XSIAM environment: data sources, parsing rule coverage, correlation rule inventory, alert volumes by source, content pack inventory |

## Core Architecture

### Sensors & Data Collection

- **Cortex XDR Agent**: Endpoint sensor deployed on Windows, Mac, Linux, Android. Provides EDR telemetry, malware prevention, exploit prevention, and response capabilities.
- **Broker VM**: On-premise virtual machine for data collection. Runs collector applets for Syslog, Kafka, CSV, Database, NetFlow, WEC, and other protocols.
- **XDR Collector (XDRC)**: On-premise data collector for Windows/Linux using Filebeat and Winlogbeat for centralized log collection. Distinct from the XDR agent — XDRC collects logs from infrastructure, while the agent provides endpoint protection and telemetry.
- **Cloud-to-Cloud Integrations**: API-based collectors for SaaS and cloud provider logs (Azure AD, O365, AWS, GCP, etc.)
- **Palo Alto Firewalls**: VM-Series, hardware NGFW, Prisma Access, and GlobalProtect forward logs via Strata Logging Service.

### Cortex Data Model (XDM)

The normalized data schema used across the platform. All ingested data gets normalized into XDM fields for consistent cross-source querying. The data pipeline flow is:

**Raw Logs → Parsing Rules (ingestion-time) → Dataset → Data Model Rules (query-time) → XDM fields**

### Causality

Causality is XSIAM's automated story-building capability. The platform continuously stitches all collected data points (processes, files, network connections, etc.) into causality chains.

Key causality concepts:
- **Causality Group Owner (CGO)**: The root process in a causality chain.
- **Causality Chain**: The full tree of process relationships stemming from a CGO.
- **Spawners**: Processes that spawn other sub-processes as part of normal OS flow. Common spawners include `explorer.exe`, `services.exe`, `wininit.exe`, `userinit.exe`. Knowing these is critical for distinguishing normal process ancestry from suspicious execution chains.
- **Causality Analysis Engine**: Automatically builds and analyzes causality chains.
- **Causality View**: Visual representation showing network, cloud, and SaaS causality relationships.

### Incidents and Alerts

- **Alert**: A single security event generated by a detection rule, analytics engine, or external source. Has fields, types, and associated playbooks.
- **Incident**: A collection of one or more related alerts grouped together via AI-driven grouping. Has severity, status, assignee, SLAs, and custom fields.
- **Incident Scoring**: AI-driven prioritization based on overall risk assessment.
- **Incident Starring**: Manual prioritization mechanism for analyst workflow.
- **Alert Exclusion**: Rules to suppress known false positives.

**Incident Lifecycle:**
1. Data is ingested from sensors, integrations, and external sources
2. Detection rules, analytics, and correlation rules generate alerts
3. Alerts are grouped into incidents via AI-driven grouping
4. Playbooks automatically run on incidents for enrichment and response
5. Analysts investigate using the War Room, Causality View, and Timeline
6. Incidents are resolved with resolution reasons and status updates

### Detection Rules

| Type | How It Works | Best For |
|---|---|---|
| **Correlation Rules** | XQL query runs on schedule or real-time against any dataset | Complex multi-field logic, cross-source correlation, custom detections |
| **BIOC** | Pattern matching on endpoint behavioral events (process, file, registry, network) | Known TTPs on endpoints. Limited to `xdr_data` and `cloud_audit_log` datasets |
| **IOC** | Match known indicators (hashes, IPs, domains, URLs) against ingested data | Known-bad indicator matching |
| **ABIOC (Analytics)** | ML-based anomaly detection, builds baselines from historical data | Detecting unknown threats, behavioral anomalies |
| **Attack Surface Rules** | Rules for external-facing asset risk detection | ASM-driven detections |
| **Palo Alto Built-in** | Pre-built detections delivered by Palo Alto, continuously updated | Broad coverage, zero configuration |

## SOAR & Automation

### Content Packs

All XSIAM/XSOAR content is organized in **Packs** — bundles of artifacts that implement use cases. Available through the Cortex Marketplace. Packs can include integrations, automations, playbooks, incident types, widgets, layouts, classifiers, mappers, and more.

### Integrations

Product integrations are how XSIAM communicates with other products via REST APIs, webhooks, etc.

Key concepts:
- Each integration can have multiple **instances** (e.g., different environments or tenants)
- Integrations run on **engines** — Docker or Podman containers deployed on-premise or in cloud
- Categories include: Analytics/SIEM, Authentication, Case Management, Data Enrichment, Threat Intelligence, Database, Endpoint, Forensics/Malware Analysis, IT Services, Messaging, Network Security, Vulnerability Management

### Playbooks

Playbooks are task-based graphical workflows that automate security response. Written in YAML format.

**Task Types:**
- **Manual**: Require analyst interaction (confirm info, escalate alerts)
- **Conditional**: Branch based on values/parameters
- **Communication**: Interact with users in the organization (email, Slack, etc.)
- **Automation**: Run integration commands, scripts, or sub-playbooks

**Key Features:**
- Sub-playbooks for modular design
- Filters and transformers for data manipulation
- Playbook polling for async operations
- Playbook triggers for alerts
- Context data access (alert context, incident context, search context)

### Context Data

Every incident and playbook has a **JSON context store**. All integration command and automation script results are stored in context. This is how different tasks share data within a playbook workflow. Example: `!whois query="cnn.com"` stores results in context for downstream tasks to consume.

### Scripts (Automations)

Scripts perform specific actions and are used within playbook tasks and CLI commands. Written in Python or JavaScript. Scripts can access all XSIAM/XSOAR APIs, including incidents, investigations, and War Room data.

### Jobs

Scheduled events triggered by time or feed updates. Can trigger playbooks on schedule (e.g., run TIM feed playbook when feed data changes, run a daily cleanup playbook).

### Lists

Reusable data structures (JSON lists, arrays) that can be referenced across playbooks and automations. Useful for maintaining allow/block lists, configuration data, threshold values, etc.

## Investigation & Response

### War Room

Chronological journal of all investigation actions, artifacts, and collaboration for an incident. Analysts can run commands and playbooks directly from the War Room. All actions are logged for audit trail.

### CLI Commands

Two command types are available in the War Room and Playground:
- **System commands**: Prefixed with `/` (e.g., `/playground_create`, `/close_investigation`)
- **External commands**: Prefixed with `!` (e.g., `!ip`, `!whois`, `!domain`) — these execute integration commands

### Playground

Non-production environment for testing automations, scripts, APIs, and commands without affecting live investigations. Use this to validate playbook logic, test new integrations, and develop custom scripts.

### Response Actions

Available response actions for endpoint and network containment:
- **Live Terminal**: Interactive command-line session on an endpoint
- **Endpoint Isolation**: Network-isolate a compromised endpoint (maintains agent communication)
- **Pause Endpoint Protection**: Temporarily disable protection modules for troubleshooting
- **Remediate Malicious Changes**: Reverse changes made by malicious processes
- **Run Scripts on Endpoints**: Execute remediation or collection scripts remotely
- **Search and Destroy**: Find and remove malicious files across endpoints
- **External Dynamic Lists**: Push indicators to NGFW block lists
- **Memory Image Collection**: Capture memory dumps for forensic analysis

### Alert Investigation Views

- **Alert Side Panel**: Quick view of alert details without leaving the incident
- **Causality View**: Visual process tree (network, cloud, SaaS variants)
- **Timeline View**: Chronological event sequence
- **Analytics Alert View**: ML model details and scoring for analytics-generated alerts

## General Guidelines

When helping with XSIAM tasks:

1. **Always specify the dataset** when writing XQL queries — don't rely on defaults unless the user is querying `xdr_data`
2. **Use XDM-normalized fields** (`xdm.*`) for cross-source queries; use raw dataset fields for vendor-specific queries
3. **Follow the data pipeline order**: Raw Logs → Parsing Rules (ingestion-time) → Dataset → Data Model Rules (query-time) → XDM fields
4. **Map correlation rule alert fields** to improve incident grouping — always include at minimum: hostname, username, IP, alert name
5. **Use the Cortex Marketplace** as the first option for integrations and content packs before building custom solutions
6. **Test XQL in the Query Builder** before deploying in correlation rules or dashboards
7. **Comment XQL queries** using `//` for maintainability
8. **Consider real-time vs scheduled** execution for correlation rules — XSIAM can detect if a query is eligible for real-time processing
9. **For playbooks**, follow the modular pattern: investigation sub-playbook → containment → eradication → recovery
10. **Reference MITRE ATT&CK** tactics and techniques when creating detection rules for proper classification
11. **Watch the 5,000-hit auto-disable threshold** — correlation rules exceeding 5,000 hits in 24 hours are automatically disabled
12. **Verify dataset names in the tenant** — dataset names (especially `alerts` vs `xdr_alerts`) vary between XDR and XSIAM tenants
13. **Mind Compute Unit (CU) consumption** — XQL queries consume CUs from an annual quota. Filter early, use `fields` to limit columns, and avoid unfiltered full-dataset scans in production queries and scheduled correlation rules

## Key Navigation Paths in XSIAM UI

- **XQL Query Builder**: Incident Response → Investigation → Query Builder
- **Correlation Rules**: Detection & Threat Intel → Detection Rules → Correlations
- **BIOC Rules**: Detection & Threat Intel → Detection Rules → BIOC
- **Parsing Rules**: Settings → Configurations → Data Management → Parsing Rules
- **Data Model Rules**: Settings → Configurations → Data Management → Data Model Rules
- **Playbooks**: Incident Response → Automation → Playbooks
- **Marketplace**: Settings → Configurations → Content Management → Marketplace
- **Dashboards**: Dashboards (top nav)
- **Incidents**: Incident Response → Incidents
- **Endpoints**: Assets → Endpoints
- **Playground**: Incident Response → Investigation → Playground
- **Quick Launcher**: Keyboard shortcut for fast navigation and action execution

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
| **ABIOCs** | Analytics Behavioral Indicators of Compromise — ML-driven behavioral detections |
| **ASM** | Attack Surface Management — continuous external asset discovery |
| **BIOCs** | Behavioral Indicators of Compromise — pattern-based endpoint detections |
| **Broker VM** | On-premise virtual machine for data collection via applets |
| **BYOML** | Bring Your Own Machine Learning — custom ML model integration |
| **CDR** | Cloud Detection and Response |
| **CGO** | Causality Group Owner — root process in a causality chain |
| **DBot** | Automated reputation scoring engine for indicators |
| **IOC** | Indicator of Compromise — known malicious indicators |
| **ITDR** | Identity Threat Detection and Response |
| **NGFW** | Next-Generation Firewall |
| **TIM** | Threat Intelligence Management |
| **UEBA** | User and Entity Behavior Analytics |
| **WEC** | Windows Event Collector |
| **XDM** | Cortex Data Model — normalized data schema |
| **XDRC** | XDR Collector — on-premise log collector using Filebeat/Winlogbeat, distinct from XDR agent |
| **XQL** | XSIAM Query Language |

## Key Documentation Links

- Official Docs: https://docs-cortex.paloaltonetworks.com/r/Cortex-XSIAM/Cortex-XSIAM-Documentation
- XSOAR Developer Hub: https://xsoar.pan.dev
- Cortex Marketplace: https://cortex.marketplace.pan.dev
- XQL Queries GitHub: https://github.com/PaloAltoNetworks/cortex-xql-queries
- API Reference: https://cortex-panw.stoplight.io/docs/cortex-xsiam-1
- Training: https://beacon.paloaltonetworks.com
