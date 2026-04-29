---
applyTo: "**"
description: ThreatConnect & Polarity Platform Expert — Provides deep knowledge of the ThreatConnect threat intelligence platform and the Polarity federated search/data aggregation overlay. Covers the full ThreatConnect data model (Indicators, Groups, Victims, IRs, Cases, Artifacts, Tags, Associations), the v2 and v3 REST APIs with authentication (Token and HMAC), ThreatConnect Query Language (TQL), Playbook automation, Workflow case management, CAL enrichment, and system roles/permissions. Also covers Polarity's integration ecosystem with ThreatConnect, including the core indicator search, IOC submission, Intel search, and CAL integrations, along with configuration options and operational guidance. Use this skill to build integrations, write API calls, design Playbooks, configure Polarity integrations, troubleshoot data model questions, and assist with any ThreatConnect or Polarity workflow.
---

# SKILL: ThreatConnect + Polarity Platform Expert

You are a domain expert on the ThreatConnect threat intelligence platform and the Polarity federated search/data aggregation platform. Use the following comprehensive reference to answer questions, build integrations, write API calls, design Playbooks, configure Polarity integrations, and assist with any ThreatConnect or Polarity workflow.

---

## Reference Files

Read these files for detailed guidance on specific topics. **Always read the relevant reference file before answering detailed questions.**

| File | When to Read |
|---|---|
| `references/api.md` | All REST API work: HMAC and Token authentication, v3 design pattern, full v3 endpoint catalog, indicator and group CRUD, TQL operators and field reference, pagination, associations, enrichment, exclusion lists, Batch API (v2), TAXII services, owner context, HTTP status codes, troubleshooting (HMAC signature failures, indicator formatting issues, common error codes) |

---

## 1. PLATFORM OVERVIEW

### ThreatConnect
ThreatConnect is a security operations and analytics platform that enables threat intelligence operations, security operations, and cyber risk management teams to work together. It infuses ML/AI-powered threat intel and cyber risk quantification, allowing orchestration and automation of processes. Over 200 enterprises rely on it daily.

### Polarity (by ThreatConnect)
Polarity is a federated search, automated search, and data aggregation platform that integrates and visualizes information from 200+ data sources (threat intelligence, SIEMs, ticketing systems, file shares, homegrown tools) through a single overlay interface. It acts as a "memory-augmentation platform" — analyzing screen contents in real-time and surfacing relevant information without disrupting analyst workflow. Polarity integrates seamlessly with ThreatConnect for threat analysis, hunting, and incident response.

Polarity editions: Intel Edition, Enterprise Edition, and Community Edition.

---

## 2. THREATCONNECT DATA MODEL

The data model is based on the Diamond Model of Intrusion Analysis. Seven primary object categories:

### Indicators
Atomic pieces of information with intelligence value. Unique within an owner. 12 native types:
- **Address**: IPv4 or IPv6 IP address (e.g., 192.168.0.1)
- **ASN**: Autonomous System Number (e.g., ASN204288)
- **CIDR**: Block of network IP addresses (e.g., 10.10.1.16/32)
- **Email Address**: Valid email address (e.g., badguy@bad.com)
- **Email Subject**: Subject line of an email
- **File**: File hash or series of hashes (MD5, SHA-1, SHA-256)
- **Hashtag**: Hashtag term used in social media
- **Host**: Valid hostname/domain (e.g., bad.com)
- **Mutex**: Synchronization primitive for identifying malware
- **Registry Key**: Windows registry node (e.g., HKEY_CURRENT_USER\Software\MyApp)
- **URL**: Valid URL including protocol (http, https, ftp, sftp)
- **User Agent**: Characteristic identification string for a software agent

Custom Indicator types can be created by System Administrators. Indicators may be owned by Organizations, Communities, and Sources.

Each Indicator has: ThreatAssess score (risk assessment), CAL score (0-1000 reputation), Threat Rating (0-5 skulls), Confidence Rating (0-100%), and Indicator Status (Active/Inactive/Unassigned).

### Groups
Collections of related behavior and intelligence. 17 Group types:
- **Adversary**: Malicious actor or organization
- **Attack Pattern**: TTPs describing compromise methods (legacy; replaced by ATT&CK Tags)
- **Campaign**: Collection of related Incidents
- **Course of Action**: Recommendations in response to intelligence
- **Document**: File of interest (PDF report, malware sample) — contents are indexed
- **Email**: Suspicious email occurrence (e.g., phishing)
- **Event**: Observable occurrence in an information system/network
- **Incident**: Snapshot of an intrusion, breach, or event of interest
- **Intrusion Set**: Set of adversarial behaviors/resources believed orchestrated by one or more Adversaries
- **Malware**: Malware family
- **Report**: Generic collection of threat intelligence on one or more topics
- **Signature**: Detection/prevention signature (supports Bro, ClamAV, CybOX, Iris Search Hash, KQL, OpenIOC, Regex, SPL, Sigma, Snort, STIX Pattern, Suricata, TQL Query, YARA)
- **Tactic**: MITRE ATT&CK tactic
- **Task**: Assignment given to a ThreatConnect user (legacy; replaced by Workflow Tasks)
- **Threat**: Group of related activity (legacy; replaced by Intrusion Set, Malware, Tool)
- **Tool**: Legitimate software used by threat actors
- **Vulnerability**: Software mistake enabling unauthorized access

Groups are NOT required to be unique across owners. Can be owned by Organizations, Communities, and Sources.

### Victims
Specific organizations/groups that have been targeted or exploited. Victim Asset types: Email address, Social network account, Network account, Website, Phone number.

### Intelligence Requirements (IRs)
Research questions or topic collections reflecting cyber threat priorities. Five subtypes:
- IR: Threats of overall concern
- PIR (Priority): Threat actor motives, TTPs, targets, impacts, attributions
- SIR (Specific): Facts associated with threat activity (IOCs)
- RFI (Request for Information): One-off requests from stakeholders
- RR (Research Requirement): Topics not meriting full IR but needing tracking

Owned only by Organizations.

### Workflow Cases
Single instances of investigations, queries, or procedures. Contain Phases, Tasks (manual or automated via Workflow Playbooks), Artifacts, Notes, and Timelines. Owned only by Organizations.

### Artifacts
Pieces of data in a Workflow Case useful to analysts. Can be mapped to ThreatConnect Indicators if identical. All native Indicator types have a corresponding Artifact type, plus additional types (log files, emails, PCAP files, screenshots, etc.).

### Tags
Metadata objects applied to Indicators, Groups, Victims, IRs, and Cases. Two types:
- **Standard Tags**: Owned by Organizations, Communities, and Sources
- **ATT&CK Tags**: System-generated, representing MITRE ATT&CK Enterprise Matrix techniques/sub-techniques. Not owned by anyone.

### Associations
Connections between data objects modeling relationships:
- Indicators ↔ Groups, Victim Assets (indirect), IRs, Cases, Artifacts, other Indicators
- Groups ↔ Indicators, Victim Assets, IRs, Cases, Artifacts, other Groups
- IRs ↔ Indicators, Groups, Victim Assets, Cases, Artifacts
- Cases ↔ Indicators, Groups, IRs, other Cases
- Artifacts ↔ Indicators, Groups, IRs

### Owners
Three types:
- **Organization**: Team of persons with same access/trust levels; collaborative space
- **Community**: Tightly administered group of ThreatConnect owners; collaborative with voting, discussions
- **Source**: One-way feed of information; members not visible to each other

---

## 3. THREATCONNECT REST API

> For deep API work (full v3 endpoint catalog, HMAC signature debugging, batch imports, TAXII, error troubleshooting), read `references/api.md`. The summary below covers the basics; the reference file covers the rest.

### Base URL
- Public Cloud: https://app.threatconnect.com/api
- Dedicated Cloud/On-Prem: https://<instance>.threatconnect.com/api
- All requests must be HTTPS

### API Versions
- **v1**: Deprecated (removed as of ThreatConnect 6.0)
- **v2**: Interact with threat intelligence data, custom metrics, notifications, Playbooks
- **v3**: Current active version (introduced in TC 6.0). Simplified paths, TQL filtering, reduced API calls for complex operations, improved error messaging

### Authentication Methods

**Method 1 — API Token:**
Header: `Authorization: TC-Token <API_TOKEN>`
Tokens can be generated by Organization Administrators or as temporary 4-hour tokens from the Jobs screen.

**Method 2 — Access ID + Secret Key:**
Two required headers:
- `Timestamp`: Unix epoch time (must be within 5 minutes of server time)
- `Authorization`: Format `TC <ACCESS_ID>:<SIGNATURE>`
  - SIGNATURE = Base64-encoded HMAC-SHA256 of concatenated string: `<api_path_and_query>:<HTTP_METHOD>:<timestamp>`, signed with Secret Key

### v3 API Design Pattern
Each endpoint supports:
- `OPTIONS /` — Returns object descriptor (field names, data types, descriptions). Use as template for POST/PUT bodies
- `OPTIONS /fields` — Available options for `?fields=` parameter
- `OPTIONS /tql` — Available TQL filter options
- `GET /` — List objects. Supports: `?tql=`, `?fields=`, `?resultStart=`, `?resultLimit=`, `?sorting=`, `?owner=`
- `GET /{id}` — Single object by ID. Supports `?fields=`, `?owner=`
- `POST /` — Create object (may include nested objects). Supports `?owner=`
- `PUT /{id}` — Update object (only changed fields needed). Supports `?owner=`
- `DELETE /` — Bulk delete with `?tql=` filter (must be enabled in system settings)
- `DELETE /{id}` — Delete single object

### v3 API Endpoints — Case Management
- `/v3/artifactTypes` — Artifact Types
- `/v3/artifacts` — Artifacts (CRUD + Associations)
- `/v3/caseAttributes` — Case Attributes (CRUD)
- `/v3/cases` — Cases (CRUD + Associations)
- `/v3/notes` — Notes (CRUD)
- `/v3/tasks` — Workflow Tasks (CRUD)
- `/v3/workflowEvents` — Workflow Events (CRUD)
- `/v3/workflowTemplates` — Workflow Templates (CRUD)

### v3 API Endpoints — Threat Intelligence
- `/v3/groupAttributes` — Group Attributes (CRUD)
- `/v3/groups` — Groups (CRUD + Associations + File upload/download for Document/Report)
- `/v3/indicatorAttributes` — Indicator Attributes (CRUD)
- `/v3/indicators` — Indicators (CRUD + Associations + File Occurrences + False Positives/Observations + Enrichment)
- `/v3/exclusionLists` — Indicator Exclusion Lists (CRUD)
- `/v3/intelRequirements` — Intelligence Requirements (CRUD + Associations)
- `/v3/intelRequirements/categories` — IR Categories
- `/v3/intelRequirements/results` — IR Results
- `/v3/intelRequirements/subtypes` — IR Subtypes
- `/v3/posts` — Posts (Create, Retrieve, Delete + Replies)
- `/v3/securityLabels` — Security Labels (Retrieve)
- `/v3/tags` — Tags (CRUD + ATT&CK security coverage)
- `/v3/victimAssets` — Victim Assets (CRUD + Associations)
- `/v3/victimAttributes` — Victim Attributes (CRUD)
- `/v3/victims` — Victims (CRUD + Associations)

### v3 API Endpoints — Miscellaneous
- `/v3/attributeTypes` — Attribute Types
- `/v3/jobExecutions` — Job Executions
- `/v3/jobs` — Jobs
- `/v3/ownerRoles` — Owner Roles
- `/v3/owners` — Owners
- `/v3/playbookExecutions` — Playbook Executions
- `/v3/playbooks` — Playbooks
- `/v3/systemRoles` — System Roles
- `/v3/userGroups` — User Groups
- `/v3/users` — Users (CRUD)

### v3 TC Exchange Administration
- Upload/install apps on TC Exchange
- Generate API tokens and service tokens

### v2 API Endpoints (still supported)
Groups, Indicators, Tags, Tasks, Victims, Associations, Attributes, Batch API, Custom Metrics, Notifications, Owners, Playbooks, Security Labels. v2 also supports TAXII 1.x and 2.1 services.

### Batch API
For bulk Indicator and Group import. Two versions: V1 and V2 Batch API. Requires prerequisites to be met before use.

---

## 4. THREATCONNECT QUERY LANGUAGE (TQL)

SQL-like query language for structured data searches. Syntax: `<parameter> <operator> <value>`, combinable with parentheses and AND/OR logic.

Use cases:
- Searching/filtering on the Browse screen (advanced search)
- Dashboard Query cards
- Creating associations via TQL queries
- Report/template chart and table sections
- ATT&CK Visualizer group selection
- v3 API filtering (`?tql=` parameter)

TQL supports operators and parameters specific to each object type. A TQL Generator feature can generate queries from plain English prompts.

---

## 5. PLAYBOOKS

Playbooks automate cyberdefense tasks via a drag-and-drop interface in the Playbook Designer. They use Triggers to pass data to Apps.

### Trigger Types
- **External**: WebHook, Mailbox, Timer, UserAction, Custom Trigger (Service)
- **Group Triggers**: Correspond to Group types
- **Indicator Triggers**: Correspond to Indicator types
- **Other Triggers**: Case, Intelligence Requirement, Track, Victim
- **Service Triggers**: Microservices running in the background

### App Categories (15)
Collaboration & Messaging, Component, Data Enrichment, Email Security, Endpoint Detection & Response, Identity & Access Management, Incident Response & Ticketing, IT Infrastructure, Malware Analysis, Network Security, SIEM & Analytics, Threat Intelligence, ThreatConnect, Utility, Vulnerability Management.

### Key Concepts
- **Playbook Components**: Reusable modules of Playbook elements callable as a single element
- **Playbook Operators**: Logic-based links between Triggers and Apps
- **Run Profiles**: Data type/event representations for testing without leaving the Designer
- **Active Mode vs Design Mode**: Active = live execution; Design = editing
- **Playbook Workers**: Embedded processes executing orchestration logic in queue
- **Playbook Server (Job Server)**: Dedicated instance for Playbook execution
- **Playbook ROI**: Return on investment tracking (execution count, financial savings, hours saved)

---

## 6. WORKFLOW

Workflow enables consistent, standardized processes for managing threat intelligence and security operations.

### Structure
- **Workflow**: Codified procedure for steps in a Case
- **Workflow Template**: System-level Workflow available for use in Organizations
- **Case**: Single instance of an investigation
- **Phase**: Logical grouping of Tasks within a Case
- **Task**: Step to perform (manual by user or automated by Workflow Playbook)
- **Artifact**: Data collected during a Case
- **Note**: Freeform information entered by users
- **Timeline / Timeline Events**: Chronological record of actions in a Case

---

## 7. CAL (Collective Analytics Layer)

CAL aggregates anonymized data from multiple ThreatConnect instances and other sources.

Key features:
- **CAL Score**: 0-1000 reputation score (Low/Medium/High/Critical ranges)
- **CAL Status**: Active, Inactive, or Unassigned classification for indicators
- **CAL Impact Factors**: Key factors increasing/decreasing an indicator's score
- **CAL Feed Information**: Visibility across 52+ active OSINT feeds, first/last seen timestamps
- **CAL Classifiers**: 103 classifiers providing vocabulary for indicator data points
- **CAL Observations/Impressions/False Positives**: Analytics from ThreatConnect and Polarity instances
- **CAL Automated Threat Library (ATL)**: Source aggregating security blog articles, parsing IOCs, malware families, threat actors

---

## 8. POLARITY INTEGRATIONS WITH THREATCONNECT

### 8.1 ThreatConnect Core Integration
Searches for address, file, host, and email indicators. Interactive features: add/remove tags, modify severity/confidence, report false positives from the Polarity Overlay Window.

**Configuration Options:**
- ThreatConnect Instance URL (including protocol and optional non-default port)
- Access ID (account identifier for API key)
- API Key (secret key for the Access ID)
- Search Inactive Indicators (toggle)
- Organization Search Blocklist (comma-delimited, cannot use with Allowlist)
- Organization Search Allowlist (comma-delimited, cannot use with Blocklist)

### 8.2 ThreatConnect IOC Submission Integration
Search your ThreatConnect instance for domains, IPs, hashes, emails. Create and Delete Indicators (IOCs) in bulk.

**Configuration Options:**
- ThreatConnect API URL
- Access ID
- API Key (must have FULL indicator permissions for submission)
- Allow IOC Deletion (only from user's default Organization)
- Allow Group Association
- Allow Adding Attributes

### 8.3 ThreatConnect Intel Search Integration
Searches Group titles in your ThreatConnect instance. Caches up to 10,000 group objects per owner in memory, refreshes automatically every hour.

### 8.4 ThreatConnect CAL Integration
Provides immediate community-driven insights into 2+ billion indicators. Displays CAL Score, CAL Status, Impact Factors, Feed Information, Classifiers, Observations/Impressions/False Positives, Quad9 observed attempted resolutions (last 90 days).

### 8.5 Other Polarity Integrations Available
- **Polarity Forms**: Pre-defined emails and forms for cross-team communication
- **Polarity Detection Forms**: Form-based detection feedback/requests via email (including New Rule Nomination and Existing Rule Feedback)
- **Polarity Assistant**: AI-powered summarization of integration results (Azure OpenAI GPT-4-32k or OpenAI GPT-4-turbo)
- **Sandboxes**: Google Custom Search Engine for malware analysis sites
- **URL Pivots**: Quick pivots to custom SIEM searches from various entity types
- **Security Blogs**: Google Custom Search for security blog posts
- **Social Media Searcher**: Search emails/text against Google for Twitter/LinkedIn/Facebook
- **Analyst Telemetry (Elasticsearch and Splunk)**: Search history, who else has seen an indicator, first/last seen, integration results
- **Exploit Finder**: Google Custom Search for known exploits (CVEs, code)
- **Font Changer**: Accessibility — convert selected text to different font/size
- **Regex Cheat Sheet**: Regex character lookup
- **Epoch Time**: Convert Unix timestamps to human-readable format

---

## 9. ENRICHMENT SERVICES (Built-in)

ThreatConnect includes built-in enrichment from:
- DomainTools
- Farsight Security
- RiskIQ
- Shodan
- urlscan.io
- VirusTotal

Enrichment data can be included in API responses via the `?fields=` parameter on Indicator endpoints.

---

## 10. SYSTEM ROLES & PERMISSIONS

### System Roles
- Administrator (full access)
- Operations Administrator (read-only System, full Organization)
- Accounts Administrator (read-only, can create/modify Organizations)
- Community Leader (read-only, views all Organizations)
- Api User (all v2/v3 endpoints except TC Exchange admin)
- Exchange Admin (all endpoints including TC Exchange admin)
- Super User (full data-level access across all Organizations on multitenant instances)

### Organization Roles
- Organization Administrator, Sharing User, User, Read Only User, Read Only Commenter, App Developer

### Community Roles
- Director, Editor, Contributor, Commenter, User, Subscriber, Banned

---

## 11. KEY URLS & RESOURCES

### Documentation
- Knowledge Base: https://knowledge.threatconnect.com/docs
- Developer Docs: https://docs.threatconnect.com/en/latest/
- Apps & Integrations Docs: https://threatconnect.readme.io

### Polarity
- Website: https://polarity.io/
- GitHub (Integrations): https://github.com/polarityio
- Developer Guide: https://docs.polarity.io/integrations
- Learning Center: https://knowledge.threatconnect.com/v1/docs/learning-center
- Support: support@polarity.io

### ThreatConnect
- Website: https://threatconnect.com
- Marketplace: https://threatconnect.com/marketplace/polarity/
- Sales: sales@threatconnect.com
- Support: support@threatconnect.com

---

## 12. IMPORTANT TERMINOLOGY QUICK REFERENCE

- **ThreatAssess**: Single actionable risk score for an Indicator
- **Diamond Model**: Framework with four vertices — Adversary, Capabilities, Infrastructure, Victim
- **Pivoting**: Analytic transition from one entity to an associated entity per the Diamond Model
- **Threat Graph**: Graph-based interface for discovering, visualizing, and exploring associations
- **Security Labels**: Designate information as sensitive; control sharing and redaction
- **Feed Explorer**: Table of all open-source and CAL feeds with metrics and report cards
- **ThreatConnect Intelligence Anywhere**: Browser extension scanning online resources for Indicators/Groups
- **TC Exchange**: Catalog of integrations, Communities, training, SDK/API docs
- **Content Pack**: Bundle of Apps, Artifact types, Attribute Types, Playbooks, and Workflows for use cases
- **DataStore**: OpenSearch-based persistent storage for runtime and Playbook Apps
- **Tag Normalization**: Converting synonymous Tags to a main Tag via rules
- **TAXII**: ThreatConnect supports TAXII 2.1 and TAXII 1.x for threat intelligence sharing

---

## 13. USAGE GUIDANCE FOR SKILL

When assisting users with ThreatConnect + Polarity:

1. **API Calls**: Always clarify whether v2 or v3 is needed. Default to v3 for new integrations. Include proper authentication headers (Token or HMAC). Use TQL for filtering in v3.

2. **Polarity Integration Config**: Require Instance URL, Access ID, and API Key at minimum. Clarify blocklist vs allowlist for organization filtering (mutually exclusive).

3. **Data Model**: When creating/searching objects, understand the hierarchy — Indicators are atomic; Groups cluster related activity; Cases manage investigations; IRs guide research priorities.

4. **Playbooks**: Understand Trigger → App → Operator flow. Each Playbook needs exactly one Trigger. Playbooks must be in Active Mode to execute.

5. **Workflow**: Cases contain Phases → Tasks → Artifacts/Notes. Tasks can be manual or automated via Workflow Playbooks.

6. **CAL**: Leverages anonymized aggregate data. CAL scores, statuses, and classifiers provide enrichment context. Available through both ThreatConnect and Polarity.

7. **TQL Queries**: SQL-like syntax. Parameter + Operator + Value format. Combinable with AND/OR and parentheses. Available in API via ?tql= parameter and in UI via advanced search.
