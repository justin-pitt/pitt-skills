# Detection Engineering Reference

## Table of Contents
1. [Detection Rule Types](#detection-rule-types)
2. [Correlation Rules](#correlation-rules)
3. [BIOC Rules](#bioc-rules)
4. [IOC Rules](#ioc-rules)
5. [Analytics (ABIOC)](#analytics-abioc)
6. [Alert Tuning](#alert-tuning)
7. [MITRE ATT&CK Mapping](#mitre-attck-mapping)
8. [Best Practices](#best-practices)

## Detection Rule Types

XSIAM provides multiple detection mechanisms, each suited for different use cases:

| Type | How It Works | Best For |
|---|---|---|
| **Correlation Rules** | XQL query runs on schedule or real-time against any dataset | Complex multi-field logic, cross-source correlation, custom detections |
| **BIOC Rules** | Pattern matching on endpoint behavioral events (process, file, registry, network) | Known TTPs on endpoints, behavioral detections |
| **IOC Rules** | Match known indicators (hashes, IPs, domains, URLs) against ingested data | Known-bad indicator matching |
| **ABIOC (Analytics)** | ML-based anomaly detection, builds baselines from historical data | Detecting unknown threats, behavioral anomalies |
| **Palo Alto Built-in** | Pre-built detections delivered by Palo Alto, continuously updated | Broad coverage, zero configuration |

## Correlation Rules

### Overview
Correlation Rules use XQL queries to detect specific patterns or conditions in your data. They can run on a **schedule** (every X minutes/hours) or in **real-time** (as data is ingested, if the query is eligible).

### Creating a Correlation Rule
Navigate to: **Detection & Threat Intel → Detection Rules → Correlations → Create**

### Components of a Correlation Rule

1. **Name & Description**: Clear name describing what the rule detects
2. **XQL Query**: The detection logic
3. **Execution Mode**:
   - **Scheduled**: Runs at defined intervals (e.g., every 5 minutes). Use for queries that need historical lookback
   - **Real-Time**: Processes data as it is ingested. XSIAM automatically recommends this if the query is eligible. Use for low-latency detections
4. **Alert Fields Mapping**: Maps query result fields to standard alert fields for proper incident grouping
5. **Alert Suppression**: Prevents duplicate alerts within a time window based on field combinations
6. **Action**: Generate an alert, save results to a dataset, or add/remove from a lookup

### Alert Fields Mapping
This is critical for incident grouping quality. Always map these fields when available:

| Alert Field | Purpose | Example Source Field |
|---|---|---|
| `Hostname` | Links alert to a specific host | `agent_hostname`, `_reporting_device_name` |
| `Username` | Associates alert to a user | `username`, `user_id` |
| `IP Address` | Source or target IP | `source_ip`, `src_ip` |
| `Alert Name` | Descriptive name | Static string or dynamic field |
| `External ID` | Correlation with external systems | Custom field |

### Alert Suppression
Prevents alert fatigue by suppressing duplicate alerts with matching field values within a time window. Configure:
- **Suppression fields**: Which fields must match for suppression (e.g., `hostname`, `username`, `source_ip`)
- **Time window**: How long to suppress (e.g., 15 minutes, 1 hour)

### Example: Failed Login Correlation Rule

```xql
// Detect multiple failed login attempts to NGFW management
dataset = panw_ngfw_system_raw
| filter description contains "auth-fail"
| alter username = regexcapture(description, "user '(?P<user>[^']+)'")
| alter source_ip = regexcapture(description, "From: (?P<ip>[\d\.]+)")
| comp count() as failed_attempts by username, source_ip, _reporting_device_name
| filter failed_attempts >= 5
```

- **Alert Field Mapping**: Map `username`, `source_ip`, `_reporting_device_name`
- **Suppression**: By `_reporting_device_name`, `username`, `source_ip` for 15 minutes
- **Action**: Generate an Alert

### Example: Suspicious PowerShell Downloads

```xql
dataset = xdr_data
| filter action_process_image_name = "powershell.exe"
| filter action_process_command_line contains "downloadstring" or action_process_command_line contains "wget" or action_process_command_line contains "Invoke-WebRequest"
| fields _time, agent_hostname, actor_process_image_name, action_process_command_line
```

## BIOC Rules

### Overview
Behavioral Indicator of Compromise rules detect endpoint behaviors — tactics, techniques, and procedures — rather than static indicators. They match on process, file, registry, and network activity.

### Creating a BIOC Rule
Navigate to: **Detection & Threat Intel → Detection Rules → BIOC → Create**

### BIOC vs Correlation Rules
- **BIOC**: Simple pattern matching on endpoint (xdr_data) events; lower latency, simpler syntax
- **Correlation Rules**: Complex logic, multi-source, aggregation support; more flexible

### BIOC Rule Fields
BIOC rules define conditions on these categories:

- **Process**: `action_process_image_name`, `action_process_command_line`, `actor_process_image_name`
- **File**: `action_file_path`, `action_file_name`, `action_file_sha256`
- **Registry**: `action_registry_key_name`, `action_registry_value_name`
- **Network**: `action_remote_ip`, `action_remote_port`, `action_local_port`

### Example BIOC Pattern
Detect `certutil.exe` used to download files (a common LOLBin technique):
- Process image name: `certutil.exe`
- Command line contains: `-urlcache` AND `-split`

## IOC Rules

IOC rules match known-bad indicators against ingested telemetry. XSIAM supports:
- **File hashes** (SHA256, SHA1, MD5)
- **IP addresses**
- **Domain names**
- **URLs**

IOCs can be ingested from:
- Unit 42 threat intelligence (built-in)
- Third-party TIP feeds
- Custom indicator uploads
- Marketplace content packs

### Managing IOCs
Navigate to: **Detection & Threat Intel → Threat Intelligence → Indicators**

## Analytics (ABIOC)

Analytical Behavioral Indicators of Compromise use machine learning to:
- Build activity baselines from your historical data
- Detect anomalies that deviate from established patterns
- Generate Analytics alerts when the Analytics Engine identifies anomalous behavior

ABIOCs analyze data as it streams into the tenant, including firewall data forwarded via Cortex Data Lake. They are managed by Palo Alto and continuously updated — no user configuration required for built-in ABIOCs.

## Alert Tuning

### Alert Exclusions
Suppress known false positives without modifying the detection rule:
- Navigate to: **Detection & Threat Intel → Alert Exclusions**
- Define conditions (e.g., exclude alerts where hostname matches specific test machines)

### Exceptions
Create exceptions on specific IOC rules or BIOC rules to whitelist known-good activity:
- Exceptions apply to specific rules, not globally
- Can be scoped by endpoint group, user, or other criteria

### Alert vs Exception vs Exclusion
| Mechanism | Scope | Use Case |
|---|---|---|
| **Alert Exclusion** | Global across rules | Known false positives from specific sources |
| **Exception** | Per-rule | Whitelist known-good behavior for a specific detection |
| **Rule Disable** | Per-rule | Completely stop a rule from generating alerts |

## MITRE ATT&CK Mapping

When creating detection rules, always assign the appropriate MITRE ATT&CK tactic and technique:

### Common Mappings for Custom Rules

| Tactic | Technique | Example Detection |
|---|---|---|
| Initial Access | T1566 Phishing | Email with malicious attachment detected |
| Execution | T1059 Command-Line Interface | Suspicious PowerShell/cmd execution |
| Persistence | T1053 Scheduled Task | New scheduled task created by unusual process |
| Privilege Escalation | T1055 Process Injection | Process injection detected via API calls |
| Defense Evasion | T1070 Indicator Removal | Log clearing detected |
| Credential Access | T1110 Brute Force | Multiple failed authentication attempts |
| Discovery | T1087 Account Discovery | Net user / whoami enumeration |
| Lateral Movement | T1021 Remote Services | RDP/SMB/WinRM lateral movement |
| Collection | T1005 Data from Local System | Bulk file access from unusual process |
| Exfiltration | T1041 Exfiltration Over C2 | Large data transfer to suspicious external IP |

XSIAM includes a **MITRE ATT&CK Framework Coverage Dashboard** showing which techniques your detection rules cover.

## Best Practices

1. **Start with a hypothesis**: Define what attack behavior you want to detect before writing the XQL query
2. **Test in Query Builder first**: Validate that your query returns expected results with real data before creating the rule
3. **Map alert fields**: Always configure alert field mappings for hostname, username, and IP at minimum
4. **Set appropriate suppression**: Balance between alert fatigue and detection coverage
5. **Use real-time when eligible**: XSIAM will recommend real-time mode if the query qualifies — prefer it for lower detection latency
6. **Version and document**: Use comments in XQL and descriptive rule names; consider exporting rules for version control
7. **Tune iteratively**: Review alert volume weekly, adjust thresholds, and add exclusions as needed
8. **Map to MITRE ATT&CK**: Enables coverage analysis and reporting
9. **Leverage Palo Alto's GitHub**: https://github.com/PaloAltoNetworks/cortex-xql-queries contains sample correlation rules and queries
10. **Coordinate with data onboarding**: Ensure the datasets your detection rules depend on have proper parsing and data model rules
