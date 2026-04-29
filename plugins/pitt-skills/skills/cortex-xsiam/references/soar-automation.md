# SOAR & Automation Reference

## Table of Contents
1. [SOAR in XSIAM Overview](#soar-in-xsiam-overview)
2. [Playbook Fundamentals](#playbook-fundamentals)
3. [Task Types](#task-types)
4. [Integrations](#integrations)
5. [Scripts & Automation](#scripts--automation)
6. [Cortex Marketplace](#cortex-marketplace)
7. [XSIAM Alert Handling Playbooks](#xsiam-alert-handling-playbooks)
8. [Playbook Design Patterns](#playbook-design-patterns)
9. [Best Practices](#best-practices)

## SOAR in XSIAM Overview

XSIAM embeds the Cortex XSOAR engine for security orchestration, automation, and response. Key capabilities:

- **Visual playbook editor** — drag-and-drop workflow builder
- **600+ integrations** — via Cortex Marketplace content packs
- **Incident-driven automation** — playbooks trigger automatically based on alert type
- **Custom scripts** — Python and JavaScript support
- **War Room** — investigation workspace for collaboration
- **Context data** — rich incident context for automated decision-making

### Navigation in XSIAM
- **Playbooks**: Incident Response → Automation → Playbooks
- **Integrations**: Settings → Configurations → Integrations
- **Scripts**: Incident Response → Automation → Scripts
- **Marketplace**: Settings → Configurations → Content Management → Marketplace
- **Playground/CLI**: Incident Response → Automation → Playground

## Playbook Fundamentals

### Three Core Components
1. **Incidents** (The Why) — The trigger and primary data container for an investigation. Ingested from SIEM alerts, phishing reports, XDR alerts, etc.
2. **Indicators** (The What) — Atomic pieces of evidence extracted from an incident: IPs, domains, hashes, URLs, usernames, emails
3. **Playbooks** (The How) — Automated workflows that orchestrate tasks, queries, and tool interactions to investigate, contain, and remediate

### Playbook Execution Flow
```
Incident Created
    ↓
Playbook Triggers (based on incident type)
    ↓
Pre-processing (extract indicators, enrich)
    ↓
Investigation (query data, check TI, correlate)
    ↓
Decision Point (malicious? false positive?)
    ↓
Response (contain, eradicate, recover)
    ↓
Closure (document, close incident)
```

## Task Types

### Standard Tasks
- **Manual tasks**: Require analyst action (e.g., confirm escalation, review findings)
- **Automated tasks**: Execute scripts or integration commands automatically
  - Built-in scripts (e.g., `!file` for file enrichment, `!ip` for IP enrichment)
  - Integration-specific commands (e.g., `!ADGetUser` for Active Directory)

### Conditional Tasks
Decision trees in the workflow:
- Were indicators found? → Yes: enrich; No: mark as non-malicious
- Is severity high? → Yes: escalate; No: auto-remediate
- Can also present a single-question survey to an analyst for decision

### Data Collection Tasks
Interactive surveys for gathering input:
- Hosted on external site (no authentication needed for respondents)
- Responses recorded in incident context
- Can feed into subsequent playbook tasks

### Section Headers
Organize tasks into logical groups (like chapters in a book):
- Investigation section
- Containment section
- Eradication section
- Recovery section

## Integrations

### How Integrations Work
1. **Install** the content pack from Marketplace (includes integration code, playbooks, scripts)
2. **Configure an instance** with credentials (API keys, URLs, username/password)
3. **Test the connection**
4. **Use in playbooks** via integration commands

### Integration Types
- **Inbound**: Create incidents from external sources (e.g., email ingestion, API webhooks)
- **Outbound**: Execute actions on external systems during playbook execution (e.g., block IP on firewall, isolate endpoint)

### Common Integration Categories
| Category | Examples |
|---|---|
| Endpoint | Cortex XDR, CrowdStrike, Carbon Black |
| Network | Palo Alto NGFW, Cisco, Fortinet |
| Email | Microsoft 365, Google Workspace, Mimecast |
| Identity | Active Directory, Okta, Azure AD |
| Threat Intelligence | VirusTotal, AlienVault OTX, Unit 42 |
| Ticketing | ServiceNow, Jira, Zendesk |
| Cloud | AWS, Azure, GCP |
| SIEM/Log | Splunk, QRadar (for migration scenarios) |

### Core Integration Commands (Cortex XDR/XSIAM)
```
!xdr-get-incidents          // Retrieve incidents
!xdr-get-alerts             // Retrieve alerts
!xdr-update-incident        // Update incident fields
!xdr-isolate-endpoint       // Network isolate an endpoint
!xdr-unisolate-endpoint     // Remove network isolation
!xdr-get-endpoints          // List endpoints
!xdr-scan-endpoints         // Trigger endpoint scan
!xdr-file-retrieve          // Retrieve file from endpoint
!xdr-run-script             // Execute script on endpoint
!core-block-ip              // Block IP address
!core-add-indicator-rule    // Upload IOC rules
!core-execute-command       // Run shell command on endpoint
```

## Scripts & Automation

### Script Languages
- **Python** (primary) — runs in Docker containers
- **JavaScript** — for simpler scripts

### Key Built-in Scripts
- `!file` — Enrich file hash across all configured TI sources
- `!ip` — Enrich IP address
- `!domain` — Enrich domain
- `!url` — Enrich URL
- `!email` — Parse email
- `!SearchIndicatorInEvents` — Search for indicator in event data

### Custom Scripts
Create custom Python scripts for:
- Data transformation
- Custom enrichment
- API calls to unsupported systems
- Complex decision logic

### Docker Images
- Scripts run inside Docker containers
- Standard image includes common Python packages
- Custom Docker images can be created for specialized dependencies

### CommonServerPython
All integrations and scripts have access to `CommonServerPython`, which provides:
- `BaseClient` class for API interactions
- `return_error()` for error handling
- `return_results()` for returning data
- `tableToMarkdown()` for formatting output
- `demisto.command()`, `demisto.args()`, `demisto.incidents()` for context access

## Cortex Marketplace

### Overview
The Marketplace is the central hub for downloading and installing content packs that extend XSIAM functionality.

### Content Pack Components
A content pack may include any combination of:
- **Integrations** — connectors to external services
- **Playbooks** — automated workflows
- **Scripts** — custom automation scripts
- **Parsing Rules** — for data ingestion
- **Data Model Rules** — for XDM normalization
- **Correlation Rules** — detection rules
- **Dashboards & Widgets** — visualization
- **Layouts** — incident/alert display configuration
- **Classifiers** — incident type mapping

### Navigation
Settings → Configurations → Content Management → Marketplace

### Content Pack Categories
- Core (built-in XSIAM functionality)
- Vendor-specific (Microsoft, AWS, Google, etc.)
- Use-case packs (Phishing, Malware, Ransomware)
- Community-contributed

## XSIAM Alert Handling Playbooks

XSIAM includes a set of core playbooks based on MITRE ATT&CK tactics and the NIST Incident Handling Guide:

### Modular Sub-Playbooks

| Sub-Playbook | Purpose |
|---|---|
| **Endpoint Investigation** | Hunt for suspicious activity using XDR insights and detectors |
| **Containment Plan** | Modular containment actions (isolate endpoint, block IP, disable user) |
| **Eradication Plan** | Remove threats (kill process, delete file, remove persistence) |
| **Recovery Plan** | Revert containment actions (unisolate, re-enable user) |
| **False Positive Handling** | Process for handling false positive alerts |
| **Enrichment** | Extract and enrich all indicators from the alert |

### Alert-Specific Playbooks
The Core pack includes dedicated playbooks for common XDR alert types that automatically trigger based on alert classification.

## Playbook Design Patterns

### Pattern 1: Triage → Investigate → Respond
```
[Trigger: New Incident]
    ↓
[Triage] Extract indicators, check duplicates
    ↓
[Investigate] Enrich indicators, query logs, check TI
    ↓
[Decision] Malicious? (auto or manual)
    ↓
[Respond] Contain → Eradicate → Recover
    ↓
[Close] Document and close
```

### Pattern 2: Alert-Specific Automation
```
[Trigger: Specific Alert Type]
    ↓
[Sub-Playbook: Enrichment]
    ↓
[Sub-Playbook: Investigation specific to alert type]
    ↓
[Auto-Remediate if confidence > threshold]
    ↓
[Escalate to analyst if uncertain]
```

### Pattern 3: Inline Automation (Alert-Level)
For simple, high-confidence detections:
```
[Alert triggers playbook automatically]
    ↓
[Enrich context]
    ↓
[Take automated action] (e.g., block hash, isolate endpoint)
    ↓
[Close automatically with documentation]
```
This pattern handles routine incidents without analyst intervention.

## Best Practices

1. **Use Marketplace content packs first** — don't build from scratch when a maintained pack exists
2. **Design modular playbooks** — use sub-playbooks for reusable components (enrichment, containment, etc.)
3. **Leverage the NIST framework** — structure playbooks around Identify → Protect → Detect → Respond → Recover
4. **Use section headers** — organize playbook tasks into logical groups
5. **Handle errors gracefully** — use conditional tasks and error handling to prevent playbook failures from blocking investigation
6. **Automate triage first** — the highest ROI automation is typically alert enrichment and initial triage
7. **Use context data** — pull from incident context (indicators, previous enrichment) rather than re-querying
8. **Test in Playground** — use the Playground (CLI) to test integration commands before embedding in playbooks
9. **Version your playbooks** — export playbooks before making changes; use the built-in versioning
10. **Monitor playbook performance** — track execution times and failure rates; optimize slow or unreliable tasks
11. **Use quiet mode judiciously** — quiet mode suppresses War Room output; disable it during debugging
12. **Document custom integrations** — include README, test playbooks, and unit tests for any custom code
