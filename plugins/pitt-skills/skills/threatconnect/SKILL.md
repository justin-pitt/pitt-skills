---
name: threatconnect
description: "ThreatConnect TIP and Polarity overlay expert. Use for any task involving ThreatConnect or Polarity: REST API calls (v2/v3), authentication (Token/HMAC), TQL queries, Indicators, Groups, Cases, Workflow, Tags, Security Labels, Associations, ThreatAssess scoring, CAL configuration, indicator deprecation, exclusion lists, TAXII feeds (inbound/outbound), feed metrics, dashboards, Query Cards, Threat Graph, ATT&CK Visualizer, Risk Quantifier, Polarity integrations (Core, IOC Submission, Intel Search, CAL, XSOAR), Polarity custom development (Node.js), Polarity server administration, Playbooks, Components, Workflow Playbooks, App Builder, TcEx, indicator distribution to SIEM/SOAR (XSIAM, Sentinel, Splunk, Elastic, Tines, Torq, BlinkOps), HTTP errors, HMAC signature failures, indicator formatting (ASN, CIDR, Host, URL, Registry Key), or troubleshooting. Trigger even without explicit ThreatConnect/Polarity mention if the task involves threat intelligence platform operations."
license: MIT
---

# ThreatConnect & Polarity Skill

Comprehensive reference for the ThreatConnect TIP and the Polarity federated search overlay. This SKILL.md is the routing layer with core knowledge (data model, terminology, ratings) plus a map to focused reference files.

## Reference Files

Load the relevant reference based on the task:

| Reference | Use For |
|---|---|
| `references/api.md` | REST API (v2/v3), authentication, TQL syntax, indicator/group CRUD, pagination, batch import, HTTP errors, signature troubleshooting |
| `references/playbook.md` | Playbook design, Triggers/Apps/Operators, variable system, Components, Workflow Playbooks, App Builder, TcEx, Run Profiles, debugging, execution monitoring |
| `references/polarity.md` | Polarity overlay integrations, custom integration development (Node.js), server administration, analyst telemetry, recognition modes |
| `references/admin.md` | System and Org roles, ThreatAssess configuration, CAL management, indicator deprecation, feed metrics and report cards, dashboards, Query Cards, Threat Graph, ATT&CK Visualizer, Risk Quantifier, system settings, recent platform features |
| `references/integrations.md` | Distribution architecture (TC as authoritative intel source), TAXII operations, SIEM integration patterns (Sentinel, Splunk, Elastic, XSIAM), SOAR integration patterns (Tines, Torq, BlinkOps, XSOAR), deconfliction, M&A integration, federal compliance |

## Platform Overview

### ThreatConnect
Threat intelligence platform (TIP) for intelligence operations, security operations, and cyber risk management. Uses ML/AI-powered threat intel and cyber risk quantification. Combines feed aggregation, indicator scoring, adversary tracking, case management, and Playbook automation in one platform. Currently on version 7.12.

### Polarity (by ThreatConnect)
Federated search and data aggregation overlay. Sits on top of any application the analyst is using (browser, ticketing, SIEM console, email), recognizes entities on screen (IPs, domains, hashes, CVEs, emails), and runs real-time lookups against connected data sources. Three editions: Intel, Enterprise, Community.

## Data Model (Diamond Model-based)

### Object Hierarchy
1. **Indicators**: Atomic IOCs (12 native types). Unique within an owner.
2. **Groups**: Collections of related behavior/intelligence (17 types).
3. **Victims**: Targeted organizations or assets.
4. **Intelligence Requirements (IRs)**: Research questions reflecting cyber threat priorities (5 subtypes: IR, PIR, SIR, RFI, RR).
5. **Workflow Cases**: Investigation instances with Phases, Tasks, Artifacts, Notes, Timeline.
6. **Artifacts**: Data points within Cases (often map to Indicators).
7. **Tags**: Metadata (Standard or ATT&CK).
8. **Associations**: Relationships between objects.

### Indicator Types (12 native)
`Address` (IP), `EmailAddress`, `File` (hash), `Host` (domain), `URL`, `ASN`, `CIDR`, `Email Subject`, `Hashtag`, `Mutex`, `Registry Key`, `User Agent`. System Admins can create custom types.

### Group Types (17)
`Adversary`, `Attack Pattern` (legacy), `Campaign`, `Course of Action`, `Document`, `Email`, `Event`, `Incident`, `Intrusion Set`, `Malware`, `Report`, `Signature`, `Tactic`, `Task` (legacy), `Threat` (legacy), `Tool`, `Vulnerability`.

Signature types support: Bro, ClamAV, CybOX, Iris Search Hash, KQL, OpenIOC, Regex, SPL, Sigma, Snort, STIX Pattern, Suricata, TQL Query, YARA.

### Owners (3 types)
- **Organization**: Team space; collaborative; members visible to each other
- **Community**: Tightly administered group with voting/discussions
- **Source**: One-way feed; members not visible to each other

Indicators are unique per owner. Same indicator in two owners is two separate copies.

### Indicator Status
- **Active**: Currently considered an IOC; included in API responses
- **Inactive**: Not currently an IOC; kept for historical accuracy; excluded from API responses
- **Unassigned**: Default for newly ingested indicators

CAL can manage status automatically (CAL Status Lock OFF) or be locked to manual control (CAL Status Lock ON).

## Scoring Concepts (configuration in references/admin.md)

### Threat Rating (0-5 skulls)
Analyst-set severity. Standardized scale:
- **0**: Unrated
- **1**: Suspicious
- **2**: Low Threat (commodity malware)
- **3**: Moderate Threat (known campaigns)
- **4**: High Threat (targeted, persistent)
- **5**: Critical Threat (active, confirmed, immediate response)

### Confidence Rating (0-100%)
Analyst-set reliability:
- **90-100**: Confirmed
- **70-89**: Probable
- **50-69**: Possible
- **25-49**: Doubtful
- **0-24**: Improbable

### CAL Score (0-1000)
Crowdsourced reputation from all participating TC instances + OSINT feeds. Bands:
- **0-200**: Low
- **201-500**: Medium
- **501-800**: High
- **801-1000**: Critical

### ThreatAssess Score (0-1000)
Single actionable risk score combining Threat Rating, Confidence, CAL Score, false positive reports, and observation data. Assessment levels (Low/Medium/High/Critical) are admin-configurable.

**Operational threshold (CDW policy)**: Critical severity + score 700+ → block across enforcement points.

## Key Terminology

| Term | Meaning |
|---|---|
| **Owner** | Organization, Community, or Source that owns an object |
| **Association** | Relationship between two objects (Indicator↔Group, Group↔Group, etc.) |
| **Pivot** | Analytic transition from one entity to an associated entity (Diamond Model navigation) |
| **Threat Graph** | Graph-based UI for exploring associations |
| **Pivot with CAL** | Explore relationships within CAL's dataset (vs only your owners) |
| **CAL** | Collective Analytics Layer (crowdsourced reputation/classifiers/feed data) |
| **CAL Classifiers** | 103 NLP-derived labels CAL applies to indicators |
| **CAL ATL** | Automated Threat Library (CAL Source aggregating security blog content) |
| **Feed Explorer** | Table of all OSINT/CAL feeds with quality metrics |
| **Intelligence Anywhere** | Browser extension that scans web pages for indicators/groups |
| **Polarity** | Federated search overlay (separate product, integrates with TC) |
| **TC Exchange** | App marketplace (built-in apps, communities, integrations) |
| **TcEx** | Python framework for building TC apps (current: v4) |
| **App Builder** | In-platform Python IDE for building Playbook Apps |
| **DataStore** | OpenSearch-based persistent storage available to apps |
| **TIM** | Threat Intelligence Management (concept; XSIAM has a TIM module that consumes TC indicators) |
| **TQL** | ThreatConnect Query Language (SQL-like, used in API filtering, dashboards, advanced search) |
| **Cases vs Issues** | CDW XSIAM uses "cases" and "issues" in analyst contexts, not "incidents" |

## System Permissions (Quick Reference)

| Role Type | Examples |
|---|---|
| **System Roles** | Administrator, Operations Administrator, Accounts Administrator, Community Leader, Api User, Exchange Admin, Super User |
| **Organization Roles** | Organization Administrator, Sharing User, User, Read Only User, Read Only Commenter, App Developer |
| **Community Roles** | Director, Editor, Contributor, Commenter, User, Subscriber, Banned |

API users: Token-based auth (TC 7.7+) or HMAC (Access ID + Secret Key). See `references/api.md` for details.

## Polarity-ThreatConnect Integrations (Quick Reference)

Built-in Polarity integrations for TC:
- **ThreatConnect Core**: Address, file, host, email lookups; tag/severity/confidence editing; FP reporting
- **ThreatConnect IOC Submission**: Bulk create/delete indicators (requires FULL indicator permissions)
- **ThreatConnect Intel Search**: Group title search with caching
- **ThreatConnect CAL**: CAL score, status, impact factors, feed info, classifiers
- **Polarity-XSOAR**: Indicator lookup, incident association, playbook execution, evidence addition
- **Polarity-XSOAR IOC Submission**: Bulk indicator submission to XSOAR

See `references/polarity.md` for configuration and development.

## Recent Platform Features (key versions)

- **7.7**: API Token authentication (alongside HMAC)
- **7.8**: AI-powered TQL Generator (Beta), Actionable Search, AbuseIPDB enrichment, MITRE ATT&CK 16.0
- **7.10**: Manual ThreatAssess recalculation, ThreatAssess in indicator export, Unified Vulnerability View
- **7.12**: Threat Actor Profiles, AI Insights for Events, Posts/Notes API, Dataminr Cyber Pulse Limited Feed

See `references/admin.md` for details.

## Documentation URLs

| Resource | URL |
|---|---|
| Knowledge Base | https://knowledge.threatconnect.com/docs |
| Developer Docs | https://docs.threatconnect.com/en/latest/ |
| App/Integration Docs | https://threatconnect.readme.io |
| Polarity Docs | https://docs.polarity.io |
| GitHub | https://github.com/ThreatConnect-Inc, https://github.com/polarityio |
| Support | support@threatconnect.com, support@polarity.io |
