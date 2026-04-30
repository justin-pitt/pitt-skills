# Data Pipeline Reference

## Table of Contents
1. [Data Pipeline Overview](#data-pipeline-overview)
2. [Data Ingestion Methods](#data-ingestion-methods)
3. [Parsing Rules](#parsing-rules)
4. [Data Model Rules (XDM)](#data-model-rules-xdm)
5. [Cortex Data Model (XDM) Schema](#cortex-data-model-xdm-schema)
6. [Custom Datasets](#custom-datasets)
7. [Data Retention & Storage Lifecycle](#data-retention--storage-lifecycle)
8. [AI Detection & Response (Beta) - AIDR](#ai-detection--response-beta--aidr)
9. [Broker VM](#broker-vm)
10. [Log Onboarding Workflow](#log-onboarding-workflow)
11. [Best Practices](#best-practices)

## Data Pipeline Overview

The XSIAM data pipeline follows this flow:

```
Raw Logs/Telemetry
    ↓
[Ingestion] (Syslog, API, Agent, Broker VM, Cloud connectors)
    ↓
[Parsing Rules] (Ingestion-time: extract fields, filter, transform)
    ↓
[Dataset] (Structured table: vendor_product_raw)
    ↓
[Data Model Rules] (Query-time: map to XDM normalized fields)
    ↓
[XDM Fields] (xdm.source.ipv4, xdm.target.user.username, etc.)
    ↓
[Analytics/Correlation/BIOC/Dashboards/Investigation]
```

**Key distinction**: Parsing Rules run at ingestion time (before storage). Data Model Rules run at query time (after storage, when you use the `datamodel` command).

## Data Ingestion Methods

### Native Palo Alto Sources
- **Cortex XDR Agent**: Endpoint telemetry → `xdr_data` dataset
- **NGFW via Strata Logging Service**: Firewall logs → `panw_ngfw_*` datasets
- **Prisma Cloud**: Cloud security posture data
- **Prisma Access**: SASE telemetry

### Third-Party Sources via Marketplace Content Packs
The Cortex Marketplace provides hundreds of pre-built integrations with parsing rules and data model rules included:
- Cloud: AWS, Azure, GCP
- Identity: Okta, Azure AD/Entra ID, Duo
- Network: Cisco, Fortinet, Check Point, Palo Alto
- Endpoint: CrowdStrike, Carbon Black, SentinelOne
- Email: Microsoft 365, Google Workspace
- SaaS: Salesforce, ServiceNow

### Custom Integrations
For sources without a content pack:
1. **Syslog** (TCP/UDP) → Broker VM → Custom parsing rules
2. **HTTP Event Collector** → Direct API ingestion
3. **Filebeat** → Log file collection via Broker VM
4. **Cloud-to-Cloud** → API-based collectors
5. **CEF/LEEF** → Auto-parsed structured formats

## Parsing Rules

### Overview
Parsing rules run at **ingestion time** using a subset of XQL called **XQLi (XQL for Ingestion)**. They process raw logs before storage.

### What Parsing Rules Do
1. **Extract fields** from raw log strings into structured columns
2. **Filter/drop** unwanted logs (reduce storage costs)
3. **Transform** field values (rename, reformat, enrich)
4. **Set timestamp** (`_time`) from the raw log's time field

### Navigation
Settings → Configurations → Data Management → Parsing Rules

### Parsing Rule Syntax

Parsing rules use `[INGEST:...]` blocks:

```xql
[INGEST:vendor="custom", product="myapp", target_dataset="custom_myapp_raw", no_hit=drop]
// Extract fields from syslog-formatted message
alter
    username = regexcapture(_raw_log, "user=(?P<user>\w+)"),
    src_ip = regexcapture(_raw_log, "src=(?P<ip>[\d\.]+)"),
    action = regexcapture(_raw_log, "action=(?P<act>\w+)")
// Set timestamp from log
| alter _time = parse_timestamp("%Y-%m-%dT%H:%M:%SZ", timestamp_field)
// Drop informational logs to save storage
| filter action != "info";
```

### Key XQLi Functions for Parsing
- `regexcapture()` - Extract named groups from raw log strings
- `parse_timestamp()` - Parse time strings into timestamp type
- `to_integer()`, `to_string()` - Type conversions
- `json_extract_scalar()` - Extract from JSON-formatted logs
- `coalesce()` - Return first non-null value from multiple fields
- `trim()`, `lowercase()`, `uppercase()` - String cleanup

### Structured Log Auto-Parsing
For structured formats, XSIAM can auto-parse:
- **CEF (Common Event Format)**: Key-value pairs extracted automatically
- **LEEF (Log Event Extended Format)**: IBM QRadar format, auto-parsed
- **JSON**: Key-value pairs extracted and stored as columns

## Data Model Rules (XDM)

### Overview
Data Model Rules run at **query time** and provide a normalization layer. They map vendor-specific fields to the standardized Cortex Data Model (XDM).

### Why Data Model Rules Matter
- Enable **cross-vendor queries** using unified `xdm.*` fields
- Built-in analytics and correlation rules **depend on XDM fields**
- Without data modeling, custom data sources won't benefit from XSIAM's ML-powered analytics
- Data Model Rules are **retroactive** - they apply to both historical and new data

### Navigation
Settings → Configurations → Data Management → Data Model Rules

### Data Model Rule Syntax

```xql
[MODEL:dataset="custom_myapp_raw", model_name="Custom MyApp"]
alter
    xdm.source.ipv4 = src_ip,
    xdm.source.user.username = username,
    xdm.target.ipv4 = dst_ip,
    xdm.target.port = to_integer(dst_port),
    xdm.event.type = action,
    xdm.event.outcome = if(action = "allow", XDM_CONST.OUTCOME_SUCCESS, XDM_CONST.OUTCOME_FAILURE),
    xdm.network.ip_protocol = if(protocol = "TCP", XDM_CONST.IP_PROTOCOL_TCP, XDM_CONST.IP_PROTOCOL_UDP),
    xdm.observer.name = device_name;
```

### Important: Custom Rules Override Defaults
If you create a user-defined Data Model Rule for a dataset that already has a default (built-in) rule, the custom rule **completely overrides** the default for that dataset. Be sure to include all needed mappings.

## Cortex Data Model (XDM) Schema

### Core XDM Field Categories

| Category | Prefix | Description |
|---|---|---|
| Source | `xdm.source.*` | Originating entity (IP, user, host, process) |
| Target | `xdm.target.*` | Destination entity |
| Event | `xdm.event.*` | Event metadata (type, outcome, description) |
| Network | `xdm.network.*` | Network-level attributes (protocol, HTTP, DNS) |
| Auth | `xdm.auth.*` | Authentication details |
| Email | `xdm.email.*` | Email-specific fields |
| Observer | `xdm.observer.*` | Reporting device/sensor |
| Alert | `xdm.alert.*` | Alert metadata |

### Frequently Used XDM Fields

```
xdm.source.ipv4 / xdm.source.ipv6
xdm.source.port
xdm.source.user.username
xdm.source.user.identifier
xdm.source.user.groups
xdm.source.host.hostname
xdm.source.host.ipv4_addresses
xdm.source.host.ipv4_public_addresses
xdm.source.process.name
xdm.source.process.command_line
xdm.source.user_agent

xdm.target.ipv4 / xdm.target.ipv6
xdm.target.port
xdm.target.url
xdm.target.host.hostname
xdm.target.host.fqdn
xdm.target.resource.id
xdm.target.resource.name
xdm.target.resource.type
xdm.target.user.username
xdm.target.user.identifier
xdm.target.sent_bytes

xdm.event.id
xdm.event.type
xdm.event.outcome (XDM_CONST.OUTCOME_SUCCESS / OUTCOME_FAILURE / OUTCOME_PARTIAL / OUTCOME_UNKNOWN)
xdm.event.outcome_reason
xdm.event.description
xdm.event.original_event_type
xdm.event.operation_sub_type

xdm.network.ip_protocol (XDM_CONST.IP_PROTOCOL_TCP / UDP / ICMP)
xdm.network.http.method (XDM_CONST.HTTP_METHOD_GET / POST / PUT / DELETE)
xdm.network.http.response_code
xdm.network.http.url
xdm.network.dns.dns_question.name
xdm.network.dns.dns_question.type
xdm.network.rule
xdm.network.session_id

xdm.auth.auth_method
xdm.auth.outcome

xdm.observer.name
xdm.observer.type
xdm.observer.version
```

### XDM Constants
Use `XDM_CONST.*` for enum-type fields to ensure consistency:
```
XDM_CONST.OUTCOME_SUCCESS, XDM_CONST.OUTCOME_FAILURE
XDM_CONST.IP_PROTOCOL_TCP, XDM_CONST.IP_PROTOCOL_UDP
XDM_CONST.HTTP_METHOD_GET, XDM_CONST.HTTP_METHOD_POST
XDM_CONST.EVENT_TYPE_NETWORK, XDM_CONST.EVENT_TYPE_PROCESS
```

## Custom Datasets

When you create parsing rules for a new data source, they insert data into a custom dataset. Dataset naming convention: `vendor_product_raw`

Example: `fortinet_fortigate_raw`, `custom_myapp_raw`

Datasets can be browsed in the schema pane of the XQL Query Builder.

## Data Retention & Storage Lifecycle

XSIAM data lives in three tiers with different query characteristics and cost profiles. (admin doc section 1.5)

| Tier | Query latency | Default retention | XQL access |
|---|---|---|---|
| **Hot** | seconds | 30-90 days (license-driven) | Default - no special syntax |
| **Cold (archived)** | minutes | up to 13 months (license-driven) | `archived_data = true` flag in XQL |
| **Beyond cold** | export-only | per agreement | Out of band (S3/ADLS export) |

### License-driven retention defaults

Hot retention varies by license tier (Premium / Enterprise / Enterprise Plus / NG SIEM). Cold retention is typically 13 months on Enterprise+ tiers. Verify your specific tenant's retention via *Settings → Configurations → Data Management → Retention*.

### Archived data queries (admin doc section 8.6)

```xql
dataset = xdr_data
| filter event_type = ENUM.PROCESS
| filter _time >= to_timestamp(now() - to_milliseconds(60, "DAYS"))
| ...
```

For data older than the hot retention window, add `archived_data = true` to the dataset clause. Archived queries take longer (minutes vs seconds) and may consume more compute units.

### Importing historical data into cold storage (admin doc 8.6.1)

You can backfill historical data (e.g., from a prior SIEM during migration) directly into cold storage. Useful for compliance retention or one-time investigation against pre-XSIAM data.

### Compute Units (CU)

XQL queries cost CU based on data volume scanned and query complexity. (admin doc 8.10)

- Always filter by `_time` early in the pipeline.
- Use `fields` to limit columns.
- Use `archived_data = true` only when needed; archived scans cost more per byte.
- Track quota via the `/xql/get_quota` API endpoint before running heavy hunts.

### License expiration

If your tenant license lapses, hot data is queryable for a grace period, then read-only. Cold data may become inaccessible until renewal. (admin doc 1.5.3)

## AI Detection & Response (Beta) - AIDR

Brand-new module (admin doc section 4.2.10). Detects AI-specific threats (model tampering, prompt injection, training data poisoning) using cloud audit logs + prompt logs.

### Enable

1. *Settings → Configurations → Cortex - Analytics → AI Detection & Response*
2. Accept the Beta Evaluation Agreement
3. Toggle on. Requires Instance Admin or Account Admin role.

### Supported sources

- **AWS**: Amazon Bedrock, SageMaker (prompt logs via S3 or CloudWatch invocation logging)
- **Azure**: Azure OpenAI (prompt logs via Event Hub diagnostic settings + HTTP data logging)
- **GCP**: VertexAI for infrastructure-level detections only (no prompt log ingestion path yet)

### Prompt log collection

- **AWS S3**: configure Bedrock model invocation logging to S3, ingest via Generic S3 collector with log type "Prompt logs". (admin doc 4.2.10.3.1)
- **AWS CloudWatch**: configure model invocation logging to CloudWatch, ingest via Amazon CloudWatch collector with log type "Prompt logs".
- **Azure**: 4-step setup - configure Event Hub collection, set up prompt logging in Azure, configure HTTP data logging, configure diagnostic settings. (admin doc 4.2.10.3.2)

### Detections covered

- Cloud audit logs feed infrastructure-layer detections: model theft, denial of ML service, training data poisoning, IAM abuse around AI services.
- Prompt logs feed model-usage visibility: which models are called, by whom, with what prompt patterns.

### AIDR dashboard

Predefined dashboard in the Dashboards selector. Shows managed AI services in use, event trends, identities accessing AI services, and top AIDR-detected issues + cases.

## Broker VM

The Broker VM is a virtual machine deployed in your environment to facilitate log collection from sources that cannot directly send to the cloud. It supports:

- **Syslog collection** (TCP/UDP) - Receives syslog from firewalls, routers, Linux hosts, etc.
- **Filebeat** - Collects log files from servers
- **Docker log collection**
- **Database log collection**

### Broker VM Configuration
Navigate to: Settings → Configurations → Data Collection → Broker VMs

The Broker VM acts as a local collection point and forwards logs to the XSIAM cloud tenant for processing.

## Log Onboarding Workflow

### For Sources with Marketplace Content Packs (Preferred)
1. **Search Marketplace** for the vendor/product
2. **Install the content pack** - includes parsing rules, data model rules, and often playbooks
3. **Configure the data source** - point logs to XSIAM (Syslog to Broker VM, API credentials, etc.)
4. **Verify ingestion** - check the dataset in Query Builder
5. **Validate XDM mapping** - run `datamodel dataset = vendor_product_raw | fields xdm.*` to confirm normalization

### For Custom Sources (No Content Pack)
1. **Configure log forwarding** to XSIAM (Syslog → Broker VM, or HTTP collector)
2. **Create parsing rules** - extract fields from raw logs, set `_time`
3. **Verify dataset population** - query the `vendor_product_raw` dataset
4. **Create data model rules** - map extracted fields to XDM schema
5. **Validate end-to-end** - confirm data appears with correct XDM fields
6. **Create detection rules** - build correlation rules or BIOCs using the new dataset

## Best Practices

1. **Use Marketplace content packs first** - they save significant engineering effort and are maintained by Palo Alto and partners
2. **Filter at ingestion** - use parsing rules to drop noise (informational logs, health checks) before storage to reduce costs
3. **Always set `_time`** - parsing rules should extract and set the correct event timestamp; without it, XSIAM uses ingestion time
4. **Map to XDM** - data without XDM mapping won't benefit from cross-source analytics or built-in ML models
5. **Test parsing rules** - use the parsing rule test feature to validate against sample logs before enabling
6. **Monitor data ingestion** - use the Data Ingestion dashboard to track volume, errors, and lag
7. **Document your pipeline** - maintain a data source inventory with dataset names, parsing rule IDs, and XDM coverage
8. **Plan for storage costs** - XSIAM pricing is partly based on data volume; use parsing rules to filter unnecessary logs
9. **Use `parsed_fields` JSON** - for complex logs, extract key fields into a `parsed_fields` JSON object for flexible querying with `json_extract_scalar()`
10. **Coordinate with detection engineering** - ensure detection rule authors know which fields are available in each dataset
