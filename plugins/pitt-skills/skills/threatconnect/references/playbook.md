# ThreatConnect Playbook Reference

Reference for ThreatConnect Playbooks, Workflow Playbooks, Playbook Components, App Builder, and TcEx framework.

## 1. Playbook Concepts

### What a Playbook Is
A Playbook automates cyberdefense tasks via a drag-and-drop interface in the Playbook Designer. Each Playbook has exactly one Trigger that passes data to one or more Apps, connected by Operators.

### Top-level Playbook Types
- **Standard Playbook**: Triggered by external event, group/indicator action, timer, etc.
- **Component**: Reusable module of Apps and Operators, called as a single element from another Playbook
- **Workflow Playbook**: Special type triggered from a Workflow Case (manual or automated Task)

### Playbook Lifecycle States
- **Design Mode**: Editable; not running
- **Active Mode**: Running; not editable. Must pass validation before activation. View parameters by double-clicking elements.

### Permissions Required
| Action | Org Role |
|---|---|
| View Playbooks | Any |
| Create/import/clone/delete/export | Standard User, Sharing User, Org Admin, App Developer |
| System Playbooks setting | System Admin |

---

## 2. Triggers

Triggers fire Playbooks. Each Playbook has exactly one Trigger.

### External Triggers
| Trigger | Use |
|---|---|
| **WebHook** | HTTP POST/GET endpoint that fires on external request. Supports Playbook IP Filter for source restriction. |
| **Mailbox** | Polls a mailbox for new emails. Parses headers, body, attachments. |
| **Timer** | Cron-based schedule for recurring runs |
| **UserAction** | Manually invoked by a user from the UI |
| **Custom Trigger** | Service-app-defined trigger (microservice background process) |

### Group Triggers
Fire when a Group of a specific type is created, updated, or deleted in your Organization. One per Group type:
Adversary, Attack Pattern, Campaign, Course of Action, Document, Email, Event, Incident, Intrusion Set, Malware, Report, Signature, Tactic, Task, Threat, Tool, Vulnerability.

### Indicator Triggers
Fire on Indicator events. One per Indicator type:
Address, EmailAddress, File, Host, URL, ASN, CIDR, Email Subject, Hashtag, Mutex, Registry Key, User Agent.

### Other Triggers
- **Case Trigger**: Fires on Workflow Case events
- **Intelligence Requirement Trigger**: Fires on IR events
- **Track Trigger**: Fires on Track-related events
- **Victim Trigger**: Fires on Victim creation or update

### Service Triggers
Microservices that constantly run in the background, defined inside Service Apps.

---

## 3. Apps (15 Categories)

Apps act on data passed from a Trigger or another App.

| Category | Examples |
|---|---|
| Collaboration & Messaging | Slack, Teams, Email |
| Component | Reusable Playbook Components called as Apps |
| Data Enrichment | VirusTotal, Shodan, RiskIQ, AbuseIPDB |
| Email Security | Proofpoint, Mimecast |
| Endpoint Detection & Response | CrowdStrike, SentinelOne, Defender |
| Identity & Access Management | Okta, Entra ID, Duo |
| Incident Response & Ticketing | ServiceNow, Jira, ThreatConnect Cases |
| IT Infrastructure | Active Directory, AWS, Azure |
| Malware Analysis | VMRay, Joe Sandbox, Cuckoo |
| Network Security | Palo Alto NGFW, Cisco, Akamai |
| SIEM & Analytics | Splunk, Sentinel, XSIAM, Elastic |
| Threat Intelligence | Recorded Future, Intel 471, Flashpoint |
| ThreatConnect | Native TC operations (create/update indicators, groups, cases) |
| Utility | String manipulation, JSON parsing, math, date/time |
| Vulnerability Management | Tenable, Qualys, Rapid7 |

### Display Documentation
Click the Display Documentation icon when configuring any Trigger, App, or Operator to see description, input parameters, and output variables.

---

## 4. Operators

Operators provide logic between Apps.

| Operator | Use |
|---|---|
| **If/Then** | Conditional branching based on variable values |
| **Merge** | Combine multiple paths into one |
| **Router** | Send execution down different paths based on conditions |
| **Filter** | Pass data only if condition met |
| **Loop** | Iterate over arrays/lists |
| **Set Variable** | Assign value to a global variable |

---

## 5. Variable System

### Variable Reference Syntax
Reference variables in App parameters using the hashtag syntax:
```
#trigger.indicator
#app.output_variable
#global.my_global_var
#tc.case_id
```

### Variable Sources
- **Trigger output**: `#trigger.<name>`
- **App output**: `#<app_label>.<output_name>`
- **Global Variables**: `#global.<name>` (defined in Playbook Designer)
- **Workflow context**: `#tc.case_id`, `#tc.case`, `#tc.task_id`, `#tc.task` (Workflow Playbooks only)
- **Component variables**: Defined per Component for parameterized reuse

### Data Types
ThreatConnect Playbooks have a typed variable system. Each output variable has an explicit type.

| Type | Description | Array Variant |
|---|---|---|
| **String** | Text value | StringArray |
| **Binary** | Binary data (file content) | BinaryArray |
| **KeyValue** | Single key/value pair | KeyValueArray |
| **TCEntity** | ThreatConnect object reference | TCEntityArray |
| **TCEnhancedEntity** | TCEntity with extended attributes | TCEnhancedEntityArray |

### TCEntity Structure
Used to pass ThreatConnect objects (Indicators, Groups, etc.) between Apps.
```json
{
  "id": 12345,
  "type": "Address",
  "value": "192.168.1.100",
  "ownerName": "My Organization"
}
```
TCEnhancedEntity adds attributes, tags, security labels, ratings, and confidence.

### Visual Type Indicators
The Playbook Designer shows variable types with letter codes in colored shapes:
- Circle: scalar type (S=String, B=Binary, etc.)
- Square: array variant of the same type

### Encrypted/Keychain Variables
Sensitive values (API keys, passwords) marked as **Encrypted & Allow Keychain Variables** can pull from the Keychain rather than being stored in plaintext.

---

## 6. Playbook Designer

### Main Panes
- **Design pane**: Canvas for placing Triggers, Apps, Operators
- **Inputs/Configuration**: Per-element parameter configuration
- **Run Profiles**: Test data sets for executing the Playbook in design without external triggers
- **Audit Log**: All changes made to the Playbook by users
- **Version History**: Past versions of the Playbook (revertable)
- **Execution Logs**: Past runs with input/output details

### Keyboard Shortcuts (most useful)
- **Mousewheel**: Zoom in/out
- **Drag empty area**: Pan
- **Ctrl+Z / Ctrl+Y**: Undo / Redo
- **Delete**: Remove selected element

### Validation
Playbook must pass validation before activation. Common validation errors:
- Unconnected required inputs
- Type mismatches between connected variables
- Missing Trigger
- Disabled or deprecated Apps still in the Playbook

---

## 7. Run Profiles

Run Profiles are saved test data sets for executing a Playbook in Design Mode without firing the actual Trigger.

### Use Cases
- Test new branches before activation
- Reproduce a specific input scenario
- Validate parameter mapping
- Check output of specific Apps

### Behavior
- Run Profiles execute the Playbook end-to-end with the saved test data
- Results appear in Execution Logs
- Apps that would write to external systems still execute (use caution; consider disabling write Apps in test profiles)

---

## 8. Playbook Components

### What a Component Is
A reusable module of Apps and Operators with a single Component Trigger. Called from a Playbook as if it were an App.

### Why Use Components
- Encapsulate repeated logic (e.g., enrichment chain used in multiple Playbooks)
- Reduce duplication
- Centralize updates (one Component change affects all calling Playbooks)

### Component Triggers
Configured similarly to Workflow Triggers. Define input parameters with:
- **Name** and **Label**
- **Data Type** (String, StringArray, KeyValue, TCEntity, etc.)
- **Required** checkbox
- **Allow Text Variables** (variable substitution)
- **Encrypted & Allow Keychain Variables** (for secrets)
- **Enable Multi-line** (for long text inputs)

### Output Variables
Define what the Component returns to the calling Playbook. Output variables must be added after all internal Apps are configured (so values can be selected from upstream output).

---

## 9. Workflow Playbooks

### What They Are
Special Playbook type that uses a Workflow Trigger. Called from a Workflow Case (manually or by an automated Task) and returns output back to the Workflow process.

### Workflow Trigger Variables
Same configuration as Component Triggers (inputs, outputs).

### Built-in Workflow Variables
Available inside Workflow Playbooks:
- `#tc.case_id` (String): Workflow Case ID
- `#tc.case` (TCEntity): Full Case entity
- `#tc.task_id` (String): Calling Task ID (if invoked from Task)
- `#tc.task` (TCEntity): Full Task entity

### Common Patterns
- **Automated Task**: Task in a Workflow Case auto-runs the Workflow Playbook on Case progression
- **Manual Run**: User clicks Run Playbook on a Case Artifact, choosing the Workflow Playbook to execute against that Artifact
- **Conditional Branching**: Workflow Playbook returns values that drive Case state changes

---

## 10. Global Variables

Defined in the Playbook Designer for use anywhere in the Playbook.

### Use Cases
- Configuration values shared across multiple Apps
- Calculated thresholds
- Lookup tables

### Reference Syntax
```
#global.threshold_score
#global.alert_recipients
```

---

## 11. Log Levels

| Level | Captures |
|---|---|
| **TRACE** | Most verbose; full execution detail |
| **DEBUG** | Debug information for development |
| **INFO** | Normal operational messages |
| **WARN** (default) | Unexpected but non-critical issues |
| **ERROR** | Serious failures requiring remediation |

### Setting Log Level
- **Per Playbook**: Settings within Playbook Designer
- **Reset all Apps to WARN**: ⋮ menu in Playbook Designer > **Reset Apps Logging Level**

### Log Storage
Execution Logs visible in the Playbook Designer Logs pane. Server-side logs accessible via System Settings (System Admin).

---

## 12. Activity Screen (Execution Monitoring)

### What It Shows
Control panel for **Organization Administrators**, **Operations Administrators**, and **System Administrators** to monitor Playbook Server and Worker execution.

### Available Metrics
- Current/active Worker allocation per Server
- Past execution metrics
- Worker priorities and processes
- Queue depth and execution latency

### Actions
- View running executions
- Kill in-flight Playbook executions
- Inspect Worker status

### Architecture
- **Playbook Server (Job Server)**: ThreatConnect instance dedicated to Playbook execution
- **Playbook Workers**: Embedded processes executing orchestration logic from a queue

---

## 13. Playbook Environments (Remote Execution)

### Concept
Run Playbook Apps and Service Triggers in a remote environment (e.g., on-prem network for accessing internal-only systems) rather than the cloud-hosted ThreatConnect instance.

### Components
- **Environment Server**: Server registered with ThreatConnect to run remote Apps
- **Environment**: Logical grouping of Servers
- **Activated Apps**: Apps assigned to run in a specific Environment

### Use Cases
- Connect to internal-only systems (no inbound public access)
- Compliance/data residency (keep processing local)
- Network segmentation requirements

### Configuration
1. Install Environment Server software on target host
2. Configure Environment in System Settings
3. Map Server to Environment
4. Activate specific Apps to use the Environment

---

## 14. Service Apps

### What They Are
Microservices that run continuously in the background. Provide custom Triggers, API services, webhook listeners, or feed services.

### Service Types
- **Custom Trigger Service**: Defines a custom Playbook Trigger
- **API Service**: Exposes a custom REST API endpoint within ThreatConnect
- **Webhook Service**: Listens for external webhooks
- **Feed Service**: Custom indicator feed ingestion

### Lifecycle
- Services start when activated
- Persist until deactivated (don't run per-execution like Playbooks)
- Visible in dedicated Services screen

---

## 15. Playbook ROI

Tracks return-on-investment metrics per Playbook:
- Execution count
- Estimated time saved per execution
- Calculated financial savings

Configured per Playbook with custom hour/dollar values. Visible from the ROI graphic icon in the Playbooks screen table.

### Use For
- Demonstrating automation value to leadership
- Identifying high-impact Playbooks
- Justifying automation investment

---

## 16. Import/Export

### Playbook Files
- Current format: `.pbxz` (zip-based, includes all references)
- Legacy format: `.pbx`

### Export
⋮ menu in Playbook Designer > **Export**. Downloads `.pbxz` file.

### Import
- Playbooks screen > Import button
- Or Import New Version from ⋮ menu (replaces existing Playbook)

### Sharing Between Instances
- ⋮ menu > **Share** > select Sharing Server > generates Share Token
- Receiving instance: Playbooks screen > Import Shared > paste Share Token

---

## 17. Cloning

⋮ menu > **Clone** opens Clone Playbook window:
- **Name**: Defaults to "Copy of <original>"
- **Type**: Clone as Playbook, Component, or Workflow Playbook
- Useful for converting Playbooks into reusable Components

---

## 18. Playbook IP Filter

Restricts which IP addresses can send requests to **WebHook Triggers**.

### Configuration
Settings within the WebHook Trigger:
- IP allowlist (specific IPs and CIDR ranges)
- Default: open (no restriction)

### Use Cases
- Restrict webhooks to known partner IPs
- Reduce attack surface
- Compliance requirements

---

## 19. App Builder (In-Platform Python IDE)

### What It Is
Python development environment built into ThreatConnect for creating, editing, and releasing Playbook Apps without leaving the platform.

### Features
- Live debugging with auto-created test Playbook
- Build logs
- Version control with commit comments and reversion
- Autocomplete
- Code snippets (built-in and user-created)
- Input/output variable management UI
- Release management

### Workflow
1. Open App Builder from Playbooks dropdown
2. Create new App or open existing
3. Edit code (Python)
4. Configure inputs/outputs in UI
5. Debug in test Playbook
6. Commit version
7. Release for use in Playbooks

### Caveats
- Debug mode should only be used in **non-production instances**
- Released Apps are tied to the ThreatConnect instance (not portable; export/share via TC Exchange)
- Best for in-house Apps; complex external Apps better built with TcEx CLI

---

## 20. TcEx App Framework

### What It Is
Python framework for building ThreatConnect apps **outside** the platform (vs App Builder which is in-platform).

Current version: **TcEx 4** with separate `tcex-cli` package.

### App Types
| Type | Use |
|---|---|
| **Playbook App** | Executes within Playbook workflows |
| **Job App** | Scheduled or manually triggered (feed ingestion, reports, batch jobs) |
| **Service App** | Long-running microservice (API service, webhook listener, custom trigger) |
| **External App** | Standalone scripts using TC API (run outside ThreatConnect) |

### Installation
```bash
pip install tcex-cli       # CLI for app management (TcEx 4+)
pip install tcex           # Framework library
pip install tcex-app-testing  # Pytest-based test framework
```

### App Structure
```
TCPB_-_MyApp/
├── app.py              # Custom logic (run method)
├── __main__.py         # Entry point
├── install.json        # App definition (inputs, outputs, parameters)
├── requirements.txt    # Python dependencies
├── tcex.json           # Build/test configuration
├── args.py             # Argument definitions
├── run.py              # Runtime bootstrap
└── playbook_app.py     # Base class for Playbook Apps
```

### Key CLI Commands
| Command | Purpose |
|---|---|
| `tcinit --action create --template playbook_utility` | Initialize new app from template |
| `tclib` | Install Python dependencies to local lib directory |
| `tcpackage` | Package app into `.tcx` file for upload |
| `tcprofile` | Generate test profiles from install.json |
| `tctest` | Run app tests locally |
| `tcvalidate` | Validate install.json and app structure |

### Common Errors
- `Can't find '__main__' module in '.'`: Missing `__main__.py` in app root. Required for entry point.

### Testing Framework
```bash
pip install tcex-app-testing
tcprofile --profile_name "test_basic"
pytest tests/
```

### DataStore Access (TcEx)
TcEx provides `tcex.datastore` for accessing the OpenSearch DataStore:
- **Organization scope**: Data scoped to current Org
- **Local scope**: Scoped to specific app instance
- **System scope**: Cross-instance (requires elevated permissions)

---

## 21. Playbook Server Architecture

### Components
| Component | Role |
|---|---|
| **Playbook Server (Job Server)** | Dedicated ThreatConnect instance for Playbook execution |
| **Playbook Workers** | Background processes executing Playbook logic from queue |
| **Environment Server** | Remote server for executing Apps in specific Environment |
| **Service Workers** | Workers running Service App microservices |

### Scaling
- Increase Worker count for higher throughput
- Use Environments for network-segmented execution
- Monitor via Activity screen

---

## 22. Common Playbook Patterns

### Enrichment Chain
WebHook Trigger → Indicator data → Enrichment App (VT) → Enrichment App (AbuseIPDB) → Set Variable (combined score) → If/Then (high score) → Block App / Notify App

### Auto-Triage
Indicator Trigger (created) → CAL score check (TC API) → If/Then (CAL >= 800) → Set Threat Rating to 5 → Tag with "auto-triaged-malicious" → Push to SIEM

### Bulk IOC Distribution
Timer Trigger (hourly) → TC API (get indicators with TQL `threatAssessScore >= 700 and active = true`) → Loop → Push to SIEM/EDR/Firewall App per indicator

### Phishing Email Triage
Mailbox Trigger → Parse Email App → Extract Indicators → Enrich → Create Case → Add Artifacts → Run Workflow Playbook for response

### Workflow-Driven Investigation
Case Trigger (created) → Create Tasks → Workflow Playbook on Task → Update Case Status → Notify analyst

---

## 23. Playbook Glossary (Selected Terms)

| Term | Definition |
|---|---|
| **Active Mode** | Playbook is running; not editable |
| **Audit Log Pane** | Lists all changes by users |
| **Component** | Reusable Playbook module called as a single element |
| **Display Documentation icon** | Shows description/inputs/outputs for selected element |
| **Environment** | Logical group of Environment Servers for remote App execution |
| **Environment Server** | Remote server for executing Apps |
| **Job Server** | Synonym for Playbook Server |
| **Pathways** | Routes between Triggers, Apps, Operators an execution can take |
| **Playbook Designer** | Configuration screen for individual Playbooks |
| **Playbook File** | `.pbxz` (current) or `.pbx` (legacy) export format |
| **Playbook IP Filter** | IP allowlist for WebHook Triggers |
| **Playbook Server** | Dedicated TC instance for Playbook execution |
| **Pathway** | Single path through a Playbook execution |
| **Run Profile** | Saved test data set for executing in Design Mode |
| **Service** | Microservice that runs continuously in background |
| **Trigger** | Element that fires a Playbook (Mailbox, WebHook, Timer, UserAction, Group, Indicator, etc.) |
| **WARN** | Default log level; captures unexpected but non-critical issues |
| **Workflow Playbook** | Playbook called by Workflow Tasks or run ad-hoc on Case Artifacts |
| **Workflow Trigger** | Trigger type used by Workflow Playbooks |

---

## 24. Documentation URLs

| Resource | URL |
|---|---|
| Playbooks (KB) | https://knowledge.threatconnect.com/docs/playbooks |
| Playbooks Glossary | https://knowledge.threatconnect.com/docs/playbooks-glossary |
| Playbook Designer | https://knowledge.threatconnect.com/docs/the-playbook-designer-overview |
| Playbook Environments | https://knowledge.threatconnect.com/docs/playbook-environments |
| App Builder | https://knowledge.threatconnect.com/docs/app-builder-overview |
| Workflow Playbooks | https://knowledge.threatconnect.com/docs/workflow-playbooks-overview |
| Creating a Workflow Playbook | https://knowledge.threatconnect.com/docs/creating-a-workflow-playbook |
| TcEx Framework | https://docs.threatconnect.com/en/latest/tcex/tcex.html |
| TcEx 4 Docs | https://threatconnect.readme.io |
| TC Exchange (Marketplace) | https://threatconnect.com/marketplace |
