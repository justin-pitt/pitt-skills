# XQL (XDR Query Language) Complete Reference

## Table of Contents
1. [Overview](#overview)
2. [Query Structure](#query-structure)
3. [Datasets & Presets](#datasets--presets)
4. [Config Stage](#config-stage)
5. [Stage Keywords (Complete)](#stage-keywords-complete)
6. [Operators](#operators)
7. [Functions (Complete)](#functions-complete)
8. [Aggregations (comp Functions)](#aggregations-comp-functions)
9. [Joins & Unions](#joins--unions)
10. [ENUM Types & Field Schemas](#enum-types--field-schemas)
11. [Alerts Dataset Field Schema](#alerts-dataset-field-schema)
12. [Correlation Rule XQL Constraints](#correlation-rule-xql-constraints)
13. [Hot & Cold Storage Queries](#hot--cold-storage-queries)
14. [Common Query Patterns](#common-query-patterns)
15. [Compute Units (CU)](#compute-units-cu)
16. [Best Practices](#best-practices)
17. [Common Errors & Troubleshooting](#common-errors--troubleshooting)

---

## Overview

XQL (XDR Query Language) is the query language for Cortex XDR and XSIAM. It queries data stored in datasets - structured tables of security telemetry.

Key characteristics:
- **Non-destructive** - queries never modify underlying data
- **Stage-based** - each stage separated by pipe (`|`)
- **Similar to SQL** - supports joins, unions, aggregations, but with different syntax
- **Results** displayed in table or graph format; can power dashboards, correlation rules, BIOC rules, and widgets

XQL queries are submitted via: **Incident Response → Investigation → Query Builder → XQL Search**

The Query Builder IDE provides syntax highlighting, autocomplete, and inline error detection. The Query Library tab stores saved and Palo Alto-provided queries for reuse.

In XSIAM, SOC analysts work primarily out of **cases** rather than alerts directly. Low-severity alerts often do not surface to analysts unless a high+ severity alert correlates them into an existing case. This makes severity assignment in correlation rules operationally critical.

---

## Query Structure

```
[config stage (optional, must be first)]
| [dataset/preset declaration]
| [stage1 keyword] [expression]
| [stage2 keyword] [expression]
| ...
```

The first non-config line defines the data source. Subsequent lines are stages that filter, transform, and aggregate results.

### Comments
```xql
// Single-line comment
dataset = xdr_data  // inline comment

/* Multi-line comment
   spanning multiple lines */
```

### Style Guide
Each stage should be on its own line, separated by `|`. Comment complex queries to explain each stage for other analysts.

---

## Datasets & Presets

### Dataset Declaration Formats

```xql
// Hot storage (default)
dataset = <dataset_name>

// Multiple datasets
dataset in (dataset1, dataset2, dataset3)

// Data model query (XDM-normalized fields)
datamodel dataset = <dataset_name>
datamodel dataset in (dataset1, dataset2)
```

### Default Dataset
If no dataset is specified, the query runs against `xdr_data`. You can change the default dataset via **Settings → Configurations → Data Management → Dataset Management** (right-click → Set as default).

### Built-in Datasets (XSIAM)

> **CRITICAL NOTE:** Dataset names and field schemas vary between XDR and XSIAM tenants, and may differ by tenant version. Always verify available datasets in the schema pane of your Query Builder before writing queries.

| Dataset | Contains | Notes |
|---|---|---|
| `xdr_data` | All endpoint and network telemetry from XDR agent | Default dataset; contains ENUM-typed event fields |
| `alerts` | Generated alerts (all sources) | **XSIAM uses `alerts`, NOT `xdr_alerts`**. XDR may use `xdr_alerts`. Verify in your tenant. |
| `incidents` | Incident data | Available in XSIAM for dashboard/widget queries |
| `incidents_artifacts` | Incident artifact data | XSIAM-specific |
| `incidents_assets` | Incident asset data | XSIAM-specific |
| `endpoints` | Endpoint inventory and status | Requires Endpoint Admin or Investigator role |
| `host_inventory` | Host inventory data | Excluded from retention enforcement |
| `cloud_audit_log` | Cloud provider audit logs | Used by BIOC rules |
| `correlationsauditing` | Correlation rule audit logs | Tracks rule creation, modification, enable/disable. **Confirmed unavailable in some tenants.** If needed, export rule list from Detection & Threat Intel → Detection Rules → Correlations UI. |
| `panw_ngfw_traffic_raw` | Palo Alto NGFW traffic logs | Via Strata Logging Service |
| `panw_ngfw_threat_raw` | NGFW threat logs | |
| `panw_ngfw_url_raw` | NGFW URL filtering logs | |
| `panw_ngfw_system_raw` | NGFW system logs | Contains auth-fail events for admin access |
| `panw_ngfw_auth_raw` | NGFW authentication logs | |
| `msft_azure_ad_raw` | Azure AD / Entra ID logs | Via Marketplace content pack |
| `msft_o365_general_raw` | Office 365 audit logs | |
| `pan_dss_raw` | Active Directory via Cloud Identity Engine | Identity data |
| `identity_analytics` | Identity Analytics data | UEBA identity scoring |
| `panw_prisma_access_raw` | Prisma Access logs | Cloud-delivered security |
| `aws_s3_raw` | AWS audit logs | Via S3 ingestion |
| `msft_azure_raw` | Azure audit logs | Via Azure Event Hub or API |
| `gcp_pubsub_raw` | GCP audit logs | Via Pub/Sub ingestion |

### Custom Datasets
Third-party data sources create datasets with the pattern: `vendor_product_raw`

Examples: `fortinet_fortigate_raw`, `hashicorp_vault_raw`, `microsoft_dhcp_raw`, `custom_myapp_raw`

Custom datasets are created via:
- Marketplace content packs (include parsing + data model rules)
- Broker VM syslog collection with custom parsing rules
- HTTP Event Collector
- Cloud-to-cloud API collectors
- Pre-XSIAM data routing (e.g., Cribl) - if you route data through a stream processor before XSIAM, dataset names may not follow the `vendor_product_raw` convention. Verify in the schema pane.

### Discovering Your Datasets
```xql
// List all datasets with event counts
dataset = xdr_data
| comp count() by _vendor, _product, _dataset
| sort desc count
| view column order = populated

// Check available alert sources (verify dataset name)
dataset = alerts
| comp count() by alert_source
| sort desc count
| view column order = populated
```

### Presets
Presets are pre-built collections of information for specific activity types. They combine data from multiple datasets into a unified view.

```xql
preset = authentication_story
| filter xdm.auth.outcome = "FAILURE"

preset = network_story
| filter xdm.target.port = 445
```

Known presets: `authentication_story`, `network_story`, `file_transfer_story`

> **Note:** BIOC rules are limited to the `xdr_data` and `cloud_audit_log` datasets, and presets for these datasets. Correlation rules can use any dataset.

---

## Config Stage

The `config` stage configures query behavior. It **must be the first stage** in the query (before the dataset declaration).

### config Functions

#### case_sensitive
Controls whether field value comparisons are case-sensitive. Default is `true`.

```xql
config case_sensitive = false
| dataset = xdr_data
| filter action_process_image_name contains "powershell"
// Matches "PowerShell.exe", "POWERSHELL.EXE", etc.
```

#### timeframe
Sets the query time range programmatically (overrides the UI time picker).

```xql
config timeframe = 2d
| dataset = microsoft_windows_raw
| filter event_id in (4729, 4733, 4735)
```

Supported formats: `1h`, `2d`, `7d`, `30d`, etc.

### Combined Config
```xql
config case_sensitive = false timeframe = 7d
| dataset = panw_ngfw_system_raw
| filter description contains "auth-fail"
```

---

## Stage Keywords (Complete)

The complete list of XQL stages:

| Stage | Purpose |
|---|---|
| `alter` | Create or modify fields |
| `arrayexpand` | Expand array fields into separate rows |
| `bin` | Group events by quantity or time span |
| `call` | Reference saved queries from the Query Library |
| `comp` | Aggregation (GROUP BY equivalent) |
| `config` | Configure query behavior (must be first) |
| `dedup` | Remove duplicate records |
| `fields` | Select specific columns for output |
| `filter` | Restrict records by condition |
| `iploc` | Associate IP addresses with geolocation |
| `join` | Combine data from two queries (new columns) |
| `limit` | Set maximum number of result records |
| `replacenull` | Replace null values with a specified string |
| `search` | Free text search across fields |
| `sort` | Order results |
| `tag` | Tag/label results for categorization |
| `target` | Save query results to a dataset for future use |
| `top` | Return the top N results by frequency |
| `transaction` | Find sequences of related events |
| `union` | Combine two result sets (new rows) |
| `view` | Control result display (graph type, highlight) |
| `windowcomp` | Calculate statistics over groups of rows (window functions) |

### alter
Creates or modifies columns. The field does not need to exist in the dataset schema. You can overwrite existing field values.

```xql
// Create new field
| alter upper_hostname = uppercase(agent_hostname)

// JSON field extraction
| alter client_ip = parsed_fields -> c_ip

// Type conversion
| alter response_code = to_integer(parsed_fields -> sc_status)

// Conditional logic
| alter risk_level = if(failed_attempts > 10, "HIGH", "LOW")

// Coalesce multiple username fields
| alter default_username = coalesce(actor_primary_username, actor_effective_username, "unknown")

// Regex capture to create new fields
| alter username = regexcapture(description, "user '(?P<user>[^']+)'")
```

### arrayexpand
Expands array fields into separate rows, up to an optional limit.

```xql
| arrayexpand dns_resolutions
| arrayexpand array_values limit 3

// Expand then sort
| arrayexpand array_values
| sort asc array_values
```

### bin
Groups events by quantity or time span. Essential for time-series dashboards.

```xql
| bin _time span = 1h
| bin _time span = 1h timeshift = 1615353499 timezone = "+08:00"
| bin _time span = 1h timezone = "America/Los_Angeles"
```

### call
References saved queries from the Query Library.

```xql
| call saved_query_name
```

### comp (compute)
Performs aggregation. Equivalent to SQL `GROUP BY` + aggregate functions. See [Aggregations](#aggregations-comp-functions) for the complete list of comp functions.

```xql
| comp count() as event_count by agent_hostname
| comp count_distinct(agent_hostname) as unique_hosts by action_process_image_name
| comp sum(action_upload) as total_upload by agent_hostname
| comp avg(action_total_download) as avg_download by agent_hostname

// With raw data preservation
| comp sum(Download) as total by Process_Path, Process_CMD addrawdata = true as raw_data
```

### dedup
Removes duplicate records. Can only be used with fields containing numbers or strings. Specify sort order to control which record is kept.

```xql
// Keep first chronological occurrence
| dedup agent_hostname, action_process_image_name by asc _time

// Keep last chronological occurrence
| dedup actor_primary_username by desc _time
```

### fields
Selects specific columns. Supports aliasing with `as`.

```xql
| fields agent_hostname, user_id, dns_query_name
| fields agent_hostname as hostname, action_process_image_name as process_name

// Functions can be used in fields stage
| fields _time, uppercase(agent_hostname) as hostname
```

### filter
Restricts records by condition. Place as early as possible for performance.

```xql
| filter action_process_image_name = "powershell.exe"
| filter action_upload < 10
| filter dns_query_name != null
| filter actor_process_image_name in ("powershell.exe", "wscript.exe", "cmd.exe")
| filter action_file_path not contains "System32"
| filter event_type = ENUM.PROCESS and event_sub_type = ENUM.PROCESS_START

// Regex match
| filter raw_log ~= "error|fail|deny"

// CIDR match
| filter incidr(source_ip, "10.0.0.0/8")

// Time-based
| filter _time >= timestamp("2025-01-01T00:00:00Z")
| filter _time >= subtract(current_time(), to_integer("7d"))
```

> **Important:** The `=` operator is an exact match - it does NOT accept wildcards. Use `contains` for substring matching, or `in` with wildcards. The `in` operator supports wildcards and can function identically to `contains`.

### iploc
Associates IP addresses with geolocation information.

```xql
| iploc action_remote_ip loc_city as city, loc_latlon
| iploc action_remote_ip suffix=_remote_id
```

### join
Combines data from two queries into new columns. Can only join two datasets at a time. See [Joins & Unions](#joins--unions) for details.

### limit
Sets maximum number of result records. Default is 1,000,000.

```xql
| limit 100
```

Using a small limit greatly increases query performance.

### replacenull
Replaces null field values with a specified string.

```xql
| replacenull agent_hostname = "UNKNOWN"
```

### search
Free text search across all fields.

```xql
| search "malware"
```

### sort
Orders results by one or more fields. **Direction goes first** (`desc` or `asc`), then the field name.

```xql
| sort desc event_count
| sort asc _time
| sort desc alert_count
```

### tag
Tags/labels results for categorization and downstream processing.

```xql
| tag "suspicious_activity"
```

### top
Returns the top N results by frequency for a given field. Shorthand for comp + sort + limit pattern.

```xql
// Top 10 most frequent remote IPs
| top action_remote_ip by count

// Top 5 processes by occurrence
| top action_process_image_name limit 5
```

### target
Saves query results to a persistent dataset for future use with `union` or `call`.

```xql
// Save results to a dataset
dataset = xdr_data
| filter event_type = FILE and event_sub_type = FILE_WRITE
| fields agent_id, action_file_sha256 as file_hash, agent_hostname
| target type=dataset file_event
```

### transaction
Finds sequences of related events within a time span.

```xql
| transaction user, agent_id span = 1h
| transaction f1, f2 startswith="str_1" endswith="str2" maxevents=99
| transaction user, agent_id span = 1h timeshift = 1615353499
```

### union
Combines two result sets into one (adds rows). Two modes:
1. **Dataset union** - combines two datasets for the duration of the query
2. **Query union** - combines result sets from two XQL queries

```xql
// Query union
dataset = xdr_data
| filter action_process_image_name = "powershell.exe"
| union (dataset = xdr_data | filter action_process_image_name = "cmd.exe")

// Dataset union (use target first to save results)
dataset = xdr_data
| union (dataset = file_event)
| fields agent_hostname, file_hash
```

> **Key distinction:** `JOIN` combines data into new columns. `UNION` combines data into new rows.

### view
Controls how results are displayed. Used for dashboards and visual output.

```xql
| view graph type = pie
| view graph type = line
| view graph type = column
| view graph type = map xaxis = country yaxis = action_local_port
| view highlight fields = host_name, dpt_name, values = "new-york"
```

### windowcomp
Calculates statistics over groups of rows (window function equivalent).

```xql
| windowcomp count(dns_query_name) by agent_ip_addresses as count_dns_query_name
```

---

## Operators

### Comparison Operators
| Operator | Description | Notes |
|---|---|---|
| `=` | Equal (exact match) | Does NOT accept wildcards |
| `!=` | Not equal | |
| `>`, `>=`, `<`, `<=` | Standard comparisons | |
| `IN`, `NOT IN` | Value in/not in list | Supports wildcards |
| `CONTAINS`, `NOT CONTAINS` | String contains (substring) | Case-sensitive by default |
| `~=` | Regex match | |
| `BETWEEN ... AND` | Range check | |

### Boolean Operators
| Operator | Description |
|---|---|
| `AND` / `and` | Both conditions true |
| `OR` / `or` | Either condition true |
| `NOT` / `not` | Negation |

### Special Operators
| Operator | Description | Example |
|---|---|---|
| `->` | JSON field extraction | `parsed_fields -> c_ip` |
| `!= null` / `= null` | Null check | `filter dns_query_name != null` |
| `INCIDR` | IP in CIDR range | `filter incidr(src_ip, "10.0.0.0/8")` |
| `+` | Add / concatenate | `alter full_path = folder + "\\" + filename` |

> **JSON case sensitivity:** JSON field names accessed via the `->` operator are case-sensitive. The key name must match exactly for results to be returned. This is a common source of empty query results.

---

## Functions (Complete)

All functions can be used in `alter` and/or `filter` stages.

### Math Functions
```xql
add(a, b)              // Add two positive integers
subtract(a, b)         // Subtract b from a
multiply(a, b)         // Multiply
divide(a, b)           // Divide
pow(base, exp)         // Power/exponent
floor(value)           // Floor (round down)
ceil(value)            // Ceiling (round up)
round(value)           // Round to nearest integer
abs(value)             // Absolute value
sqrt(value)            // Square root
log(value)             // Logarithm
```

### String Functions
```xql
lowercase(field)                    // Convert to lowercase
uppercase(field)                    // Convert to uppercase
trim(field)                         // Remove leading/trailing whitespace
len(field)                          // String length (also: length())
concat(field1, field2)              // Concatenate strings
replace(field, "old", "new")        // Replace substring
split(field, "delimiter")           // Split string into array
substring(field, start, length)     // Extract substring
string_count(field, "search")       // Count occurrences of substring
format_string("%s-%d", field1, f2)  // Format string (printf-style)
```

### Regex Functions
```xql
// Extract named capture groups - returns object with named fields
regexcapture(field, "user=(?P<username>\w+)")

// Extract matching groups - returns array
regextract(field, "pattern(\w+)")

// Regex replace
replex(field, "pattern", "replacement")

// Regex match in filter
| filter raw_log ~= "error|fail|deny"
```

### Conversion Functions
```xql
to_integer(field)       // Convert to integer
to_float(field)         // Convert to float
to_number(field)        // Convert to number
to_string(field)        // Convert to string
to_boolean(field)       // Convert to boolean
to_timestamp(field, "MILLIS")  // Convert epoch to timestamp
to_json_string(field)   // Convert to JSON string
```

### Time Functions
```xql
current_time()                              // Current timestamp
extract_time(_time, "HOUR")                 // Extract time component
// Components: YEAR, MONTH, DAY, HOUR, MINUTE, SECOND, DAY_OF_WEEK
timestamp("2025-01-01T00:00:00Z")           // Parse ISO timestamp string
timestamp_diff(_time, prev_time, "SECOND")  // Difference between timestamps
// Units: SECOND, MINUTE, HOUR, DAY
timestamp_seconds(epoch_seconds)            // Convert epoch seconds
format_timestamp(_time, "%Y-%m-%d")         // Format timestamp to string
parse_timestamp(field, format)              // Parse string to timestamp
```

### JSON Functions
```xql
json_extract(json_field, "$.key")                   // Extract JSON value (returns JSON type)
json_extract_scalar(json_field, "$.key.subkey")      // Extract scalar value from JSON
json_extract_array(json_field, "$.items")             // Extract array from JSON
object_create("key1", val1, "key2", val2)             // Create JSON object
```

### Array Functions
```xql
arrayconcat(arr1, arr2)             // Concatenate two arrays
arraycreate(val1, val2, val3)       // Create array from values
arraydistinct(array_field)          // Remove duplicates from array
arrayfilter(array, condition)       // Filter array by condition
arrayindex(array_field, index)      // Get element at index
array_length(array_field)           // Count of elements in array
array_contains(array_field, value)  // Check if array contains a value (returns boolean)
arraymap(array_field, expression)   // Transform each element (@element reference)
arrayrange(start, end, step)        // Generate numeric array
arraystring(array_field, ",")       // Join array elements into string
```

#### arrayfilter Examples
```xql
// Filter array by condition
| alter x = arrayfilter(dfe_labels, array_length(backtrace_identities) > 1)

// Filter using @element reference
| alter x = arrayfilter(dfe_labels, @element != "benign")
```

#### arraymap Examples
```xql
// Transform each element
| alter mapped = arraymap(my_array, uppercase(@element))
```

### Network Functions
```xql
incidr(ip_field, "10.0.0.0/8")             // Check if IP is in CIDR range
incidrlist(ip_field, list_field)             // Check IP against list of CIDRs
```

### Conditional Functions
```xql
// If/else
if(condition, true_value, false_value)

// Coalesce - return first non-null value
coalesce(field1, field2, field3)

// Nested if
if(score > 90, "critical",
   if(score > 70, "high",
      if(score > 50, "medium", "low")))

// Case/when - multi-condition switch (cleaner than nested if)
case_when(
    score > 90, "critical",
    score > 70, "high",
    score > 50, "medium",
    "low"  // default value
)
```

---

## Aggregations (comp Functions)

Used with the `comp` stage. All take a field parameter and support `by` clause for grouping.

| Function | Description | Example |
|---|---|---|
| `count()` | Count of records | `comp count() as total by hostname` |
| `count_distinct(field)` | Count of unique values | `comp count_distinct(user_id) as unique_users` |
| `sum(field)` | Sum of values | `comp sum(bytes_sent) as total_sent` |
| `avg(field)` | Average of values | `comp avg(response_time) as avg_time` |
| `min(field)` | Minimum value | `comp min(_time) as first_seen` |
| `max(field)` | Maximum value | `comp max(_time) as last_seen` |
| `values(field)` | List of distinct values | `comp values(action_file_name) as files` |
| `first(field)` | First value encountered | `comp first(agent_hostname) as host` |
| `last(field)` | Last value encountered | `comp last(agent_hostname) as host` |
| `earliest(field)` | Chronologically earliest value | `comp earliest(action_file_path) by hostname` |
| `latest(field)` | Chronologically latest value | `comp latest(action_file_path) by hostname` |

### addrawdata Option
Preserves raw underlying data alongside aggregated results:
```xql
| comp sum(Download) as total by Process_Path, Process_CMD addrawdata = true as raw_data
```

---

## Joins & Unions

### Join
Combines data from two queries into a single result set (adds columns). Can only join two datasets at a time - for three or more, chain joins using the `target` stage.

#### Join Types
| Type | Description |
|---|---|
| `inner` (default) | Records in common between both queries |
| `left` | All records from parent + matching from join |
| `right` | All records from join + matching from parent |

#### Join Syntax
```xql
dataset = xdr_data
| join type = inner (dataset = endpoints) as e
  on agent_id = e.agent_id
| fields agent_hostname, e.endpoint_name, e.endpoint_status
```

#### Join with Alter (field normalization)
When fields don't match exactly between datasets, use `alter` to normalize before joining:
```xql
dataset = microsoft_dhcp_raw
| filter hostName != "" and ipAddress != ""
| alter hn1 = if(hostname contains ".domain.local", replace(hostname, ".domain.local", ""), hostname)
| join (dataset = endpoints) as EP
  EP.endpoint_name = hn1
| dedup hn1
| fields hostName, hn1, endpoint_name, ipAddress
```

#### Anti-Join Pattern (finding non-matches)
XQL does not have a native anti-join. Use conditional aggregation instead:
```xql
dataset = xdr_data
| alter conditional = if(action_process_image_name ~= "chrome", 1, 0)
| fields agent_hostname as hostname, conditional as runcount
| comp sum(runcount) as totalruns by hostname
| filter totalruns = 0
// Returns hosts that NEVER had a chrome process
```

### Union
Combines two result sets into one (adds rows).

```xql
// Query union
dataset = xdr_data
| filter action_process_image_name = "powershell.exe"
| union (dataset = xdr_data | filter action_process_image_name = "cmd.exe")
```

> **Performance tip:** When checking if a field value exists in another dataset, using `IN`/`NOT IN` with `filter` is often more efficient than a `join`. Consider `filter` + `IN` as an alternative when you only need to check membership rather than pull additional columns from the second dataset.

---

## ENUM Types & Field Schemas

### ENUM Types (xdr_data event filtering)

The `xdr_data` dataset uses ENUM types for event classification:

#### event_type Values
| ENUM Value | Description |
|---|---|
| `ENUM.PROCESS` | Process events |
| `ENUM.FILE` | File events |
| `ENUM.NETWORK` | Network events |
| `ENUM.REGISTRY` | Registry events |
| `ENUM.EVENT_LOG` | Windows event log events |

#### event_sub_type Values (common)
| ENUM Value | Description |
|---|---|
| `ENUM.PROCESS_START` | Process execution start |
| `ENUM.FILE_WRITE` | File write operation |
| `ENUM.FILE_READ` | File read operation |
| `ENUM.FILE_CREATE` | File creation |
| `ENUM.FILE_DELETE` | File deletion |
| `ENUM.LOAD_IMAGE` | DLL/module load |

### xdr_data Key Fields

> **Note:** These are common fields in `xdr_data`. Your tenant may have additional or different fields. Always check the schema pane in the Query Builder for your specific environment.

#### Host & Agent Fields
| Field | Description |
|---|---|
| `agent_hostname` | Endpoint hostname |
| `agent_id` | Unique endpoint identifier |
| `agent_ip_addresses` | Endpoint IP addresses (array) |
| `agent_os_type` | Operating system type |
| `agent_os_sub_type` | OS version details |

#### Process Fields (Actor = parent, Action = child)
| Field | Description |
|---|---|
| `actor_process_image_name` | Parent process executable name |
| `actor_process_image_path` | Parent process full path |
| `actor_process_command_line` | Parent process command line |
| `actor_primary_username` | Username that launched parent process |
| `actor_effective_username` | Effective username of parent process |
| `action_process_image_name` | Child process executable name |
| `action_process_image_path` | Child process full path |
| `action_process_command_line` | Child process command line |
| `action_process_os_pid` | Child process PID |
| `os_actor_process_image_name` | OS-level actor process name |

#### Causality Fields
| Field | Description |
|---|---|
| `causality_actor_process_image_name` | Root cause process name |
| `causality_actor_effective_username` | Root cause process username (**most reliable user context**) |
| `causality_actor_process_command_line` | Root cause command line |

#### File Fields
| Field | Description |
|---|---|
| `action_file_name` | File name |
| `action_file_path` | Full file path |
| `action_file_sha256` | File SHA256 hash |
| `action_file_md5` | File MD5 hash |

#### Network Fields
| Field | Description |
|---|---|
| `action_local_ip` | Local IP address |
| `action_local_port` | Local port |
| `action_remote_ip` | Remote IP address |
| `action_remote_port` | Remote port |
| `action_external_hostname` | External hostname |

#### DNS Fields
| Field | Description |
|---|---|
| `dns_query_name` | DNS query domain |
| `dns_resolutions` | DNS resolution results (array) |
| `dns_query_type` | DNS query type |

#### Data Volume Fields
| Field | Description |
|---|---|
| `action_upload` | Upload bytes |
| `action_total_download` | Download bytes |

#### Event Log Fields
| Field | Description |
|---|---|
| `action_evtlog_message` | Windows event log message |
| `event_id` | Windows event ID |

#### Metadata Fields
| Field | Description |
|---|---|
| `_time` | Event timestamp |
| `_vendor` | Data source vendor |
| `_product` | Data source product |
| `_dataset` | Dataset name |
| `_reporting_device_name` | Reporting device hostname |

### Alerts Dataset Field Schema

> **Important field naming differences:** The `alerts` dataset uses different field names than `xdr_data`. Do not assume field names transfer between datasets.

#### Key Alert Fields
| Field | Type | Description |
|---|---|---|
| `alert_name` | string | Name of the alert/rule that fired |
| `alert_source` | string | Source engine (e.g., `"CORRELATION"`, `"XDR_ANALYTICS_BIOC"`, `"CSPM_SCANNER"`) |
| `severity` | string | Alert severity level |
| `host_name` | string | Hostname (NOT `agent_hostname` - that's `xdr_data`) |
| `user_name` | **array** | Username(s) - **array type, requires `arrayexpand` before `comp`** |
| `mitre_attack_tactic` | string | MITRE ATT&CK tactic |
| `mitre_attack_technique` | string | MITRE ATT&CK technique |
| `resolution_status` | string | Alert resolution status |
| `_time` | timestamp | Alert timestamp |

#### Common alert_source Values
| Value | Description |
|---|---|
| `CORRELATION` | Correlation rule alerts |
| `CSPM_SCANNER` | Cloud security posture alerts (Prisma Cloud) |
| `XDR_ANALYTICS_BIOC` | Behavioral IOC analytics |
| `VULNERABILITY_POLICY` | Vulnerability policy alerts |
| `CIEM_SCANNER` | Cloud identity entitlement alerts |
| `CLOUD_NETWORK_ANALYZER` | Cloud network analysis |
| `HEALTH` | Platform health alerts |
| `ASM` | Attack surface management |
| `PAN_NGFW` | Palo Alto NGFW alerts |
| `XDR_ANALYTICS` | XDR analytics alerts |
| `XDR_BIOC` | XDR behavioral IOC alerts |

> **Note:** `alert_source` values may differ between tenants and product versions. Verify in your tenant before encoding the value into a correlation rule.

---

## Correlation Rule XQL Constraints

### Execution Modes
- **Scheduled** - runs at defined intervals. Required for queries needing historical lookback
- **Real-Time** - processes data as it is ingested. XSIAM automatically recommends this if the query is eligible. Preferred for low-latency detections

### Schedule Options (Scheduled Mode)
| Frequency | Description |
|---|---|
| Every 10 minutes | Minimum frequency |
| Every 20 minutes | |
| Every 30 minutes | |
| Hourly | Runs at the beginning of each hour |
| Daily | Runs at midnight (configurable timezone) |
| Custom | Cron expression |

### Auto-Disable Threshold
Cortex XDR/XSIAM **automatically disables** correlation rules that reach **5,000 or more hits over a 24-hour period**. If your rule exceeds this, you need to tighten the filter logic or add suppression.

### Alert Field Mapping
**Critical for incident grouping quality.** Always map these fields when available:

| Alert Field | Purpose | Example Source Field |
|---|---|---|
| `Hostname` | Links alert to a specific host | `agent_hostname`, `_reporting_device_name` |
| `Username` | Associates alert to a user | `username`, `user_id`, `causality_actor_effective_username` |
| `IP Address` | Source or target IP | `source_ip`, `src_ip`, `action_remote_ip` |
| `Alert Name` | Descriptive name | Static string or dynamic field |
| `External ID` | Correlation with external systems | Custom field |

Mapping fields improves incident grouping logic and enables XSIAM to list artifacts and assets based on the mapped fields in the incident view.

### Alert Suppression
Prevents duplicate alerts with matching field values within a time window:
- **Suppression fields** - which fields must match (e.g., `hostname`, `username`, `source_ip`)
- **Time window** - how long to suppress (e.g., 15 minutes, 1 hour)

### BIOC Rule Limitations
BIOC rules are limited to:
- `xdr_data` dataset
- `cloud_audit_log` dataset
- Presets for these datasets

Correlation rules have no such dataset limitation.

---

## Hot & Cold Storage Queries

### Hot Storage (Default)
```xql
dataset = xdr_data
| filter agent_hostname = "workstation01"
```

### Cold Storage
Cold storage queries use a different format. The retention periods and access methods depend on your license and retention add-ons.

Key retention notes:
- Incident and alert data retained for **180 days** based on last Update Date / Creation Date
- Grace period of up to **31 days** for alerts in Incidents View
- Host Inventory, Vulnerability Assessment, Metrics, and Users datasets are **excluded** from retention enforcement
- Extended retention available as license add-ons

See `data-pipeline.md` for the full hot/cold/archived tier model and `archived_data = true` syntax.

---

## Common Query Patterns

### Discover Datasets and Data Sources
```xql
// What data sources are flowing into the tenant
dataset = xdr_data
| comp count() as event_count by _vendor, _product
| sort desc event_count
| view column order = populated

// What datasets exist and have data
dataset = xdr_data
| comp count() by _dataset
| sort desc count
| view column order = populated
```

### Alert Inventory by Source
```xql
// Count alerts by source and severity (XSIAM)
dataset = alerts
| comp count() as alert_count by alert_source, severity
| sort desc alert_count
| view column order = populated

// Correlation rule alert inventory
config timeframe = 30d
| dataset = alerts
| filter alert_source = "CORRELATION"
| comp count() as alert_count,
      count_distinct(host_name) as unique_hosts,
      min(_time) as first_seen,
      max(_time) as last_seen
  by alert_name, severity
| sort desc alert_count
| view column order = populated
```

> **Notes:** The dataset is `alerts` (not `xdr_alerts`) on XSIAM. The `user_name` field is an array - use `arrayexpand user_name` before aggregating by user. Confirm `alert_source` values for your tenant.

### Correlation Rule Audit Trail
```xql
// NOTE: correlationsauditing dataset is unavailable in some tenants.
// Workaround: Export rule list from the UI:
//   Detection & Threat Intel > Detection Rules > Correlations
// Then diff the UI export against the alerts query below to find
// silent rules (enabled but never firing):
config timeframe = 30d
| dataset = alerts
| filter alert_source = "CORRELATION"
| comp count() as alert_count by alert_name
| sort desc alert_count
| view column order = populated

// Rules in the UI export but absent from this query = silent/broken rules
```

### Threat Hunting: Suspicious Process Execution
```xql
dataset = xdr_data
| filter event_type = ENUM.PROCESS and event_sub_type = ENUM.PROCESS_START
| filter actor_process_image_name in ("powershell.exe", "cmd.exe", "wscript.exe", "cscript.exe", "mshta.exe")
| fields _time, agent_hostname, actor_process_image_path, action_process_image_name, action_process_command_line
| sort desc _time
| limit 500
| view column order = populated
```

### DNS Analysis for a Specific User
```xql
dataset = xdr_data
| fields agent_hostname, user_id, dns_query_name, dns_resolutions, dns_query_type
| filter dns_query_name != null
| filter user_id contains "stanley.hudson"
| comp count() as attempts by dns_query_name
| sort desc attempts
| view column order = populated
```

### Failed Login Analysis (NGFW)
```xql
dataset = panw_ngfw_system_raw
| filter description contains "auth-fail"
| alter username = regexcapture(description, "user '(?P<user>[^']+)'")
| alter source_ip = regexcapture(description, "From: (?P<ip>\d+\.\d+\.\d+\.\d+)")
| comp count() as failed_attempts by username, source_ip, _reporting_device_name
| sort desc failed_attempts
| view column order = populated
```

### Cross-Source IP Investigation with XDM
```xql
datamodel dataset in (panw_ngfw_traffic_raw, xdr_data)
| filter xdm.source.ipv4 = "192.168.1.100"
| fields _time, xdm.source.ipv4, xdm.target.ipv4, xdm.target.port, xdm.event.type
| sort desc _time
| limit 200
| view column order = populated
```

### Top Talkers by Data Volume
```xql
dataset = panw_ngfw_traffic_raw
| comp sum(bytes_sent) as total_sent, sum(bytes_received) as total_received by src_ip
| alter total_bytes = add(total_sent, total_received)
| sort desc total_bytes
| limit 20
| view column order = populated
```

### Process Tree Investigation
```xql
dataset = xdr_data
| filter agent_hostname = "suspect-workstation"
| filter event_type = ENUM.PROCESS
| fields _time, causality_actor_process_image_name, actor_process_image_name, action_process_image_name, action_process_command_line
| sort asc _time
| view column order = populated
```

### File Activity Monitoring
```xql
dataset = xdr_data
| filter action_file_path != null
| filter action_file_path contains ".exe"
| filter causality_actor_process_image_name = "outlook.exe"
| fields _time, agent_hostname, action_file_name, action_file_path, action_file_sha256
| view column order = populated
```

### Windows Event Log Analysis
```xql
config case_sensitive = false
| dataset = microsoft_windows_raw
| filter event_id in (4729, 4733, 4735)
| filter message contains "target_string"
| fields _time, agent_hostname, event_id, message
| sort desc _time
| view column order = populated
```

### Incident Dashboard Queries (XSIAM)
```xql
// Open incidents by severity
dataset = incidents
| filter status = "open"
| comp count() as incident_count by severity
| sort desc incident_count
| view column order = populated

// True positive incident rate
dataset = incidents
| filter resolve_comment contains "True Positive"
| comp count() as tp_count by severity
| view column order = populated
```

### User Context for Process Launch
When you need the most reliable user context for a process, use `causality_actor_effective_username` (not `action_process_username` or `actor_process_username`):

```xql
config case_sensitive = false
| dataset = xdr_data
| filter event_type = ENUM.PROCESS
| filter action_process_image_name = "suspicious.exe"
| fields _time, agent_hostname, causality_actor_effective_username, action_process_command_line
| view column order = populated
```

---

## Compute Units (CU)

XQL queries consume **Compute Units (CU)** based on the volume of data scanned and the complexity of the query. XSIAM provides a free annual CU quota based on your license tier.

Key facts:
- If the annual CU quota is exhausted, queries will fail until the next billing cycle or additional CU are purchased
- Additional CU can be purchased via the **Compute Unit add-on** (minimum 50 CU purchase, provides 1 additional CU per day)
- Daily consumption limits can be configured in the UI to prevent quota burn
- Unfiltered queries against large datasets (e.g., `xdr_data` with no filters over 30d) consume significantly more CU than targeted queries
- Correlation rules running on schedule consume CU on every execution - poorly filtered rules can burn through quota quickly

**CU optimization tips:**
- Filter as early as possible in the query pipeline
- Use `fields` to limit columns returned
- Use `limit` during development and testing
- Set appropriate `config timeframe` - don't query 30d when 24h will do
- Prefer `IN` over `join` when checking field membership
- Monitor CU consumption trends in the platform settings

---

## Best Practices

1. **Always specify the dataset** - avoids querying unnecessary data and improves performance. Never rely on defaults for production queries.
2. **Filter early** - put filter stages as close to the dataset declaration as possible to reduce data scanned.
3. **Use `fields` to limit output** - selecting only needed columns speeds up queries significantly.
4. **Always append `| view column order = populated`** - suppresses empty columns and shows only fields with data. Add this as the last stage in every query.
5. **Comment your queries** - use `//` for inline documentation, especially in correlation rules and shared queries.
6. **Use `dedup` wisely** - deduplication on high-cardinality fields can be expensive.
7. **Test time ranges** - start with shorter time ranges (24h) before expanding to 7d or 30d.
8. **Use XDM fields for cross-source** - when querying multiple datasets, always use `datamodel` with `xdm.*` fields.
9. **Save queries to the library** - Query Builder → Save As → Query to Library for team reuse.
10. **Use `comp` for aggregation** - it's the XQL equivalent of SQL's GROUP BY + aggregate functions.
11. **Validate regex patterns** - test `regexcapture` and `regextract` with a small result set before applying broadly.
12. **Verify dataset names in your tenant** - dataset names (especially `alerts` vs `xdr_alerts`) vary between XDR and XSIAM tenants and versions. Pre-XSIAM stream processors (Cribl, Logstash) may also rename datasets.
13. **Use `config case_sensitive = false`** - for case-insensitive searches, especially on username and hostname fields.
14. **Set appropriate limits** - use `limit` to cap results during development; remove or increase for production.
15. **Watch the 5,000-hit auto-disable** - correlation rules exceeding 5,000 hits in 24 hours are automatically disabled.
16. **Use the schema pane** - browse available fields for any dataset before writing queries against it.
17. **Monitor Compute Unit consumption** - unfiltered queries and frequent correlation rule schedules burn CU. Filter early, limit columns, and use appropriate timeframes to conserve your annual quota.
18. **Prefer `IN` over `join` for membership checks** - when you only need to check if a value exists in another dataset (not pull additional fields), `filter field IN (...)` is more efficient than a join.
19. **JSON keys are case-sensitive** - when using `->` for JSON field extraction, the key name must match exactly. This is a common source of empty results.
20. **Know your dataset field names** - `alerts` uses `host_name` (not `agent_hostname`) and `user_name` (array, not string). Always check the schema pane when switching datasets.
21. **Severity assignment is operationally critical** - in XSIAM, low-severity alerts often only surface when a high+ severity alert pulls them into a case. A miscategorized MEDIUM that should be HIGH may never get analyst eyes.

---

## Common Errors & Troubleshooting

### "ERROR: FAILED TO RUN" with no result
- Usually caused by incorrect `join` syntax or referencing fields that don't exist
- Verify field names in the schema pane
- Test each stage independently before combining

### Query returns no results but no error
- Check the time range - the UI picker may be set too narrow
- Verify the dataset contains data: `dataset = <name> | limit 10`
- Check `config case_sensitive` - field value comparisons are case-sensitive by default
- Verify ENUM types are correct (e.g., `ENUM.PROCESS` not `"PROCESS"`)

### "Aggregation by field of type array is unsupported"
- Use `arrayexpand` to expand the array into individual rows before using `comp`

### Dataset or field not found
- Dataset names are tenant-specific. Use the schema pane to verify
- Third-party datasets follow the pattern `vendor_product_raw`
- Fields may exist in one dataset but not another

### Correlation rule auto-disabled
- Rule exceeded 5,000 hits in 24 hours
- Tighten filter logic, increase threshold, or add suppression
- Review alert volume with: `dataset = alerts | filter alert_name = "Rule Name" | comp count() by bin(_time, 1h) | view column order = populated`

### Wildcards not working with `=` operator
- The `=` operator is exact match only - it does not accept wildcards
- Use `contains` for substring matching
- Use `in` with wildcards, or `~=` for regex matching

### Field names differ between datasets
- The `alerts` dataset uses `host_name`, not `agent_hostname` (which is in `xdr_data`)
- The `alerts` dataset uses `user_name` (array type), not `actor_primary_username`
- Always check the schema pane for field names specific to the dataset you're querying
- Run `dataset = <name> | fields * | limit 1` to discover available fields

### "Aggregation by field of type array is unsupported" in alerts
- Fields like `user_name` in the `alerts` dataset are array types
- Use `arrayexpand user_name` before `comp count_distinct(user_name)`
- Alternatively, use `arrayindex(user_name, 0)` to extract the first element
