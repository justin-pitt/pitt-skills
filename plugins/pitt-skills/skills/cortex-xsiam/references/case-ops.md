# Case Operations Reference

> **Terminology Note**: This document uses "case" where Palo Alto's default documentation says "incident." In modern XSIAM, SOC analysts work out of **cases** and **issues** - not incidents. The underlying APIs still use "incident" in endpoint paths and function names (e.g., `/incidents/get_incidents`) - these are preserved as-is in the API section below.
>
> **Quick refresher** - see [SKILL.md](../SKILL.md) (Terminology Note) for the verified definitions:
> - **Issue** = a detection event surfaced on the Issues page from any detection method (correlation, BIOC, ABIOC, IOC, analytics, ASM, vulnerability, custom). Lives in the `issues` dataset.
> - **Case** = top-level grouping of related issues; the primary working object for SOC analysts. AI-grouped by shared entities and attack patterns. Has `case_id` and an `issues` array.
> - **Alert** vs **Issue**: alerts (older XDR surface) and issues (modern XSIAM surface) are both detection events with overlapping IDs but different field shapes. Most analyst triage starts at the Issues page.
> - **Case** vs **Incident**: separate at the API level, both still active. Cases bridge to incidents via `custom_fields.incident_id`. Don't conflate them.

## Table of Contents
1. [Case Lifecycle](#case-lifecycle)
2. [Alert-to-Case Pipeline](#alert-to-case-pipeline)
3. [Causality Chain & Views](#causality-chain--views)
4. [Investigation Workflow](#investigation-workflow)
5. [Response Actions](#response-actions)
6. [Dashboards & Reporting](#dashboards--reporting)
7. [XSIAM APIs](#xsiam-apis)
8. [Operational Best Practices](#operational-best-practices)

## Case Lifecycle

```
[Data Ingestion]
    ↓
[Detection] (Correlation, BIOC, IOC, Analytics, ML)
    ↓
[Alert Generated]
    ↓
[Alert Grouping] (AI-driven stitching into cases)
    ↓
[Case Created] (enriched with context)
    ↓
[Automated Triage] (playbook runs, routine cases auto-handled)
    ↓
[Analyst Review] (for cases requiring human judgment)
    ↓
[Investigation] (causality chain, threat hunting, enrichment)
    ↓
[Response] (contain, eradicate, recover)
    ↓
[Closure] (documented, lessons learned)
```

> **Alert Surfacing**: Low severity alerts only surface when high+ severity alerts correlate them into existing cases. This means analysts see a filtered, higher-signal view of activity.

## Alert-to-Case Pipeline

### How Alerts Become Cases
XSIAM groups related alerts into cases using:
- **Intelligent stitching** - correlates alerts by common entities (endpoint, user, IP, process)
- **AI-driven scoring** - assigns severity based on risk analysis
- **Automatic enrichment** - adds context from threat intelligence, asset inventory, user profiles

### Case Fields
Key case attributes:
- **Case ID** - unique identifier
- **Severity** - Critical, High, Medium, Low, Informational
- **Status** - New, Under Investigation, Resolved, Closed
- **Assigned To** - analyst or group
- **Source** - where the alert originated
- **Alert Count** - number of grouped alerts
- **MITRE Tactic/Technique** - mapped ATT&CK classification

### Alert vs Case
- **Alert**: Single detection event from one rule/engine
- **Case**: Grouped collection of related alerts telling a complete attack story. The primary working object for SOC analysts.

## Causality Chain & Views

### What is the Causality Chain?
When a detection fires, XSIAM builds the full sequence of activity that led to the alert:
- Processes spawned
- Files created/modified
- Network connections made
- Registry changes
- User actions

### Causality Group Owner (CGO)
The CGO is the process identified by the Causality Analysis Engine as being **responsible for or causing** the activity chain leading to the alert. During investigation, always review the CGO to understand root cause.

### Causality Views

| View | Data Source | Shows |
|---|---|---|
| **Network Causality View** | Correlated firewall + endpoint + cloud logs | Network-level attack story with stitched events |
| **Cloud Causality View** | Cloud audit logs, cloud security alerts | Cloud-specific attack paths (no CGO) |
| **SaaS Causality View** | SaaS audit events (e.g., O365 audit logs) | SaaS-related alert stories (no CGO) |

### Log Stitching
XSIAM correlates logs from different sources to build causality:
- Firewall network logs + endpoint raw data + cloud data
- Creates a unified view of the attack across detection sensors
- Enables the Network Causality View

## Investigation Workflow

### Step 1: Review Case Summary
- Check severity, alert count, affected assets
- Review the MITRE ATT&CK tactic/technique classification
- Look at the case timeline

### Step 2: Examine Causality Chain
- Open the causality view for the primary alert
- Identify the CGO
- Trace the full process tree from initial execution to alert

### Step 3: Investigate with XQL
Use the Query Builder for deeper analysis:

```xql
// Process tree for a specific endpoint
dataset = xdr_data
| filter agent_hostname = "affected-host"
| filter _time between timestamp("2025-03-01T00:00:00Z") and timestamp("2025-03-01T23:59:59Z")
| fields _time, causality_actor_process_image_name, actor_process_image_name, action_process_image_name, action_process_command_line
| sort _time asc

// Network connections from suspicious process
dataset = xdr_data
| filter agent_hostname = "affected-host"
| filter action_process_image_name = "suspicious.exe"
| filter action_remote_ip != null
| fields _time, action_remote_ip, action_remote_port, action_local_port

// File activity by process
dataset = xdr_data
| filter agent_hostname = "affected-host"
| filter action_file_path != null
| fields _time, action_process_image_name, action_file_path, action_file_name, action_file_sha256
```

### Step 4: Enrich Indicators
- Check file hashes against threat intelligence
- Investigate suspicious IPs/domains
- Query identity systems for user context

### Step 5: Determine Scope
- How many endpoints are affected?
- What users are involved?
- Is lateral movement detected?

### Step 6: Take Response Actions
Based on findings, execute containment and remediation (see Response Actions below).

## Response Actions

### Action Center - the unifying surface

All endpoint and file response actions route through the **Action Center** (admin doc section 7.4). It's the single place to:
- See in-flight actions across endpoints with pending/in-progress/completed/cancelled status
- Cancel an action that hasn't yet executed on the endpoint
- View the **action report** post-completion (output, exit code, file artifacts)
- Track the action lifecycle for compliance/forensic logging

Action lifecycle: `pending` → `in_progress` (agent picked up) → `completed` / `failed` / `cancelled`. Poll status via the `/actions/get_action_status` API endpoint. Each action has an `action_id` that bridges the API and UI surfaces.

Distinct from playbooks - a playbook can *trigger* an action, but the action itself is tracked in Action Center independently. If a playbook task that runs an action errors, the underlying action may still complete on the endpoint.

### Endpoint Actions
| Action | Command | Effect |
|---|---|---|
| **Isolate Endpoint** | `!xdr-isolate-endpoint` | Network isolation - endpoint can only communicate with XSIAM cloud |
| **Unisolate Endpoint** | `!xdr-unisolate-endpoint` | Restore network connectivity |
| **Pause Protection** | Action Center → Pause Protection | Temporarily disable agent-side prevention (does not affect detection) - useful for incident response on a host running a critical app you can't yet fix the policy for |
| **Remediate Changes** | Action Center → Remediate Changes from Malicious Activity | Roll back file/registry/persistence changes attributed to a specific malicious causality chain (admin doc section 7.6) |
| **Kill Process** | Via live terminal or playbook | Terminate running malicious process |
| **Quarantine File** | Via endpoint agent or playbook | Move file to quarantine |
| **Delete File** | Via live terminal or playbook | Remove malicious file |
| **Retrieve File** | `!xdr-file-retrieve` | Download file from endpoint for analysis. Status via the `/file_retrieval/get_file_retrieval_details` endpoint. |
| **Collect Memory Image** | Action Center → Collect Memory Image | Full live RAM dump for forensic analysis. Large files; staged to cloud bucket post-collection. |
| **Search and Destroy** | Action Center → Search and Destroy | Match-and-remove files by hash/path across the fleet. Audit trail per host. |
| **Retrieve Logs** | Action Center → Retrieve Logs | Pull XDR agent logs from endpoint for support cases |
| **Scan Endpoint** | `!xdr-scan-endpoints` | Trigger full malware scan |
| **Run Script** | `!xdr-run-script` | Execute remediation script on endpoint. Status via the `/scripts/get_script_execution_status` endpoint; output via `/scripts/get_script_execution_results` (and `_files` for files produced). |
| **Execute Command** | `!core-execute-command` | Run shell command on endpoint |
| **External Dynamic Lists** | Action Center → EDLs | Generate per-tenant EDL URLs that the NGFW can subscribe to for IOC propagation |

### Network Actions
| Action | Effect |
|---|---|
| **Block IP** | `!core-block-ip` - Add to blocklist across enforcement points |
| **Block Domain** | Add to External Dynamic List (EDL) on NGFW |
| **Block Hash** | `!xdr-file-blacklist` - Prevent execution of file by hash |
| **Whitelist Hash** | `!xdr-file-whitelist` - Allow known-good file |

### Identity Actions
| Action | Effect |
|---|---|
| **Disable User Account** | Via AD/Azure AD integration |
| **Force Password Reset** | Via identity provider integration |
| **Revoke Sessions** | Via identity provider integration |

## Dashboards & Reporting

### Predefined Dashboards
XSIAM includes several built-in dashboards that display when you log in:
- **Security Operations** - Overall SOC metrics
- **Case Management** - Open cases, MTTR, resolution rates *(UI may label this "Incident Management")*
- **Data Ingestion** - Volume, sources, errors, lag
- **MITRE ATT&CK Coverage** - Detection coverage mapped to framework
- **IT Metrics** - Endpoint health, agent status
- **Risk Management** - (with ITDR add-on) User and host risk scores

### Custom Dashboards
Build custom dashboards with:
- **XQL-powered widgets** - any XQL query can become a dashboard widget
- **Widget types**: Tables, bar charts, pie charts, line charts, numbers, trend graphs
- **Filters**: Time range, data source, custom fields
- **Sharing**: Share with team or set as default landing page

### Creating a Dashboard Widget from XQL
1. Write and test your XQL query in Query Builder
2. Verify results are in the format you want (use `comp` for aggregation)
3. Save the query
4. Navigate to Dashboards → Create Dashboard → Add Widget
5. Select XQL widget type and reference your saved query

### Reports
- **Scheduled reports** - PDF/email reports on a schedule
- **Compliance reports** - pre-built templates for regulatory requirements
- **Custom reports** - build from dashboard widgets

## XSIAM APIs

> **API Terminology**: The API endpoints use Palo Alto's native "incident" naming. When calling these APIs, you are operating on what analysts work with as "cases."

### API Authentication
Generate API keys in: Settings → Configurations → Integrations → API Keys
- **Key ID** + **API Key** for authentication
- Choose between Standard and Advanced API key types

### Key API Endpoints

| Endpoint | Purpose |
|---|---|
| `POST /public_api/v1/incidents/get_incidents` | Retrieve cases |
| `POST /public_api/v1/incidents/get_incident_extra_data` | Get detailed case data |
| `POST /public_api/v1/incidents/update_incident` | Update case fields |
| `POST /public_api/v1/alerts/get_alerts` | Retrieve alerts |
| `POST /public_api/v1/alerts/insert_cef_alerts` | Insert CEF-format alerts |
| `POST /public_api/v1/alerts/insert_parsed_alerts` | Insert parsed alerts |
| `POST /public_api/v1/endpoints/get_endpoint` | Get endpoints |
| `POST /public_api/v1/endpoints/get_all` | List all endpoints |
| `POST /public_api/v1/endpoints/isolate` | Isolate endpoint |
| `POST /public_api/v1/endpoints/unisolate` | Unisolate endpoint |
| `POST /public_api/v1/endpoints/scan` | Trigger endpoint scan |
| `POST /public_api/v1/endpoints/cancel_scan` | Cancel scan |
| `POST /public_api/v1/endpoints/delete` | Delete endpoint |
| `POST /public_api/v1/xql/start_xql_query` | Start XQL query |
| `POST /public_api/v1/xql/get_query_results` | Get XQL results |
| `POST /public_api/v1/xql/get_quota` | Check query quota |
| `POST /public_api/v1/distributions/get_versions` | Get distribution versions |
| `POST /public_api/v1/distributions/create` | Create distribution |
| `POST /public_api/v1/audits/management_logs` | Get audit logs |
| `POST /public_api/v1/audits/agents_reports` | Get agent audit reports |
| `POST /public_api/v1/hash_exceptions/blacklist` | Blacklist file hash |
| `POST /public_api/v1/hash_exceptions/whitelist` | Whitelist file hash |

### API Reference Documentation
Full API docs: https://cortex-panw.stoplight.io/docs/cortex-xsiam-1

### Running XQL Queries via API
```python
import requests

url = "https://<tenant-fqdn>/public_api/v1/xql/start_xql_query"
headers = {
    "x-xdr-auth-id": "<key-id>",
    "Authorization": "<api-key>",
    "Content-Type": "application/json"
}
payload = {
    "request_data": {
        "query": "dataset = xdr_data | filter agent_hostname = 'host1' | limit 10",
        "timeframe": {
            "from": 1704067200000,  # epoch ms
            "to": 1704153600000
        }
    }
}
response = requests.post(url, json=payload, headers=headers)
execution_id = response.json()["reply"]

# Poll for results
results_url = "https://<tenant-fqdn>/public_api/v1/xql/get_query_results"
results_payload = {
    "request_data": {
        "query_id": execution_id,
        "pending_result": True
    }
}
results = requests.post(results_url, json=results_payload, headers=headers)
```

## Operational Best Practices

1. **Set up dashboards for daily ops** - monitor case volume, MTTR, data ingestion health, and detection coverage
2. **Automate routine cases** - configure playbooks to auto-close well-understood, low-risk alert types
3. **Review and tune weekly** - analyze false positive rates, adjust alert exclusions, and refine correlation rules
4. **Use the MITRE ATT&CK dashboard** - identify coverage gaps and prioritize new detection rule development
5. **Document investigation playbooks** - standardize investigation procedures for common case types
6. **Leverage XQL for proactive hunting** - schedule regular threat hunts beyond automated detections
7. **Monitor data ingestion health** - gaps in data ingestion lead to gaps in detection
8. **Practice response actions** - regularly test endpoint isolation, file quarantine, and recovery procedures
9. **Maintain an asset inventory** - keep the endpoints list current for accurate scoping during cases
10. **Track SOC metrics** - MTTD (Mean Time to Detect), MTTR (Mean Time to Respond), case closure rate, false positive rate
