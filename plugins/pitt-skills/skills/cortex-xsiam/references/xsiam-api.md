# XSIAM API & Integration Patterns Reference

## Table of Contents
1. [Overview](#overview)
2. [API Quirks & Gotchas](#api-quirks--gotchas)
3. [Authentication](#authentication)
4. [API Request/Response Pattern](#api-requestresponse-pattern)
5. [API Endpoint Catalog](#api-endpoint-catalog)
6. [XQL Query APIs](#xql-query-apis)
7. [Event Collector Integrations](#event-collector-integrations)
8. [Mirroring Integration Pattern](#mirroring-integration-pattern)
9. [Integration Cache](#integration-cache)
10. [Long-Running Containers](#long-running-containers)
11. [Docker Image Management](#docker-image-management)
12. [Python Client Pattern](#python-client-pattern)
13. [API Licensing](#api-licensing)
14. [Documentation References](#documentation-references)

---

## Overview

This reference covers the XSIAM platform API and advanced integration patterns: authentication, the XQL query API async flow, event collector integrations, bidirectional mirroring, long-running containers, and integration caching. For basic integration code conventions (Client class, CommandResults, YAML metadata), see `soar-development.md`. For operational API usage (which endpoints to call for case management), see `case-ops.md`.

All Cortex XSIAM API calls use REST over HTTPS. All endpoints use `POST`.

---

## API Quirks & Gotchas

The items below are quirks observed in real-world operational work that don't always appear in Palo Alto's public docs. For deeper field-level details, also consult the official Cortex XSIAM admin documentation - it carries material not in the public API reference.

### 1. Endpoint reality vs naming

XSIAM exposes five overlapping detection/response surfaces with confusingly similar names. Pick by what you're actually doing, not by which word ("alert", "issue", "incident", "case") the user said:

| Endpoint | Surface | ID type in filters/payload | What it really is |
|---|---|---|---|
| `POST /public_api/v1/alerts/get_alerts/` | Older XDR alerts | int (in `alert_id_list` filter) | Read alerts (legacy detection events) |
| `POST /public_api/v1/issue/search/` | Modern XSIAM issues | int (in `id` filter) | Read issues (unified detection events) |
| `POST /public_api/v1/alerts/update_alerts/` | Cross-surface write | **string** (in `alert_id_list` payload) | Write status/resolution for issues AND alerts |
| `POST /public_api/v1/cases/...` | Modern cases | (case_id) | Read/update cases (separate from incidents) |
| `POST /public_api/v1/incidents/...` | Legacy incidents | (incident_id) | Read/update incidents (separate from cases) |

`alert_id_list` requires **integers** in `get_alerts` filters but **strings** in `update_alerts` payloads. Cast at the call site.

### 2. URL transform - browser FQDN vs API FQDN

The tenant browser URL (e.g., `https://yourcorp.xdr.us.paloaltonetworks.com`) is **not** the PAPI host. PAPI requires the `api-` prefix (e.g., `https://api-yourcorp.xdr.us.paloaltonetworks.com`). Some integrations and clients transform this internally; direct httpx/requests scripts must add the prefix themselves:

```python
def build_papi_url(fqdn: str) -> str:
    base = fqdn if "api-" in fqdn else fqdn.replace("https://", "https://api-")
    if not base.startswith("https://"):
        base = f"https://{base}"
    return base
```

### 3. Async writes - `update_alerts` continues after client timeout

`update_alerts` with a large `alert_id_list` can take more than 120 seconds to respond on busy production tenants, but the server keeps processing after the client connection drops. Operational rules:

- Set client timeout >= 300s for bulk writes against prod.
- After any timeout, **read state via `get_alerts` (or `get_issues`) before retrying.** Naive retry double-processes IDs already resolved.
- Make bulk-write scripts idempotent: read state -> filter to unresolved -> write delta.
- Keep batches small (<= 20 IDs) on production tenants. Large batches commonly exceed the 120-second client default while completing server-side.

### 4. `/issue/search/` reliability

`/issue/search/` has been observed to return 500s and 10-minute timeouts on `status:NEW` queries against some production tenants. If your scheduled sweeps lean on it, build them to tolerate failures gracefully and prefer narrower page sizes (`search_to: 100` or smaller) in manual queries.

### 5. Authentication headers

PAPI uses two paired headers; both required:

```python
HEADERS = {
    "x-xdr-auth-id": os.environ["XSIAM_API_KEY_ID"],   # numeric ID, e.g. "39"
    "Authorization": os.environ["XSIAM_API_KEY"],       # the long key string
    "Content-Type": "application/json",
}
```

API-key permissions (set when generating the key in *Settings -> Configurations -> Integrations -> API Keys*) are independent of any client-side write gate your tooling may impose.

### 6. Resolution status enum reference

Read responses surface internal `STATUS_xxx_NAME` values; write parameters use lowercase `resolved_*` forms. They are not interchangeable:

| Internal value (read) | Write param (status=) | Meaning |
|---|---|---|
| `STATUS_010_NEW` | `new` | Not yet triaged |
| `STATUS_020_UNDER_INVESTIGATION` | `under_investigation` | In progress |
| `STATUS_030_RESOLVED_THREAT_HANDLED` | (rare/legacy) | Legacy |
| `STATUS_040_RESOLVED_KNOWN_ISSUE` | `resolved_known_issue` | Triaged as known noise |
| `STATUS_050_RESOLVED_DUPLICATE` | `resolved_duplicate` | Duplicate of another |
| `STATUS_060_RESOLVED_FALSE_POSITIVE` | `resolved_false_positive` | False positive |
| `STATUS_070_RESOLVED_OTHER` | `resolved_other` | Catch-all |
| `STATUS_080_RESOLVED_TRUE_POSITIVE` | `resolved_true_positive` | Confirmed threat |
| `STATUS_090_RESOLVED_SECURITY_TESTING` | `resolved_security_testing` | Internal red team / tooling |
| `STATUS_100_RESOLVED_AUTO_RESOLVE` | `resolved_auto_resolve` | Resolved by playbook |

Treat any value containing `RESOLVED` as final state.

### 7. Detection method enum reference

Values used on the `detection_method` field of issues:

- `CORRELATION` - correlation rules
- `XDR_ANALYTICS` - XSIAM ML analytics
- `XDR_ANALYTICS_BIOC` - analytics-driven BIOC
- `XDR_BIOC` - non-analytics BIOC rules
- `VULNERABILITY_POLICY` - vulnerability detection
- `ASM` - Attack Surface Management
- `CSPM_SCANNER` - Cloud Security Posture
- `CUSTOM_ALERT` - custom-ingested alerts

### 8. Undocumented `parent` context fields on issues

Issues have `parent` context fields that **do not appear in default API responses on production tenants**, are not in any Palo Alto public documentation, and are not in typical example responses. They are effectively hidden by default - Palo Alto support discloses both the field names and the request shape needed to retrieve them. **Don't waste time inspecting raw responses to find these - they aren't there.** If you need parent issue/case relationship context, contact Palo Alto support for the current field list and the API parameters that surface them.

---

## Authentication

Three values are required to authenticate: an **API Key**, an **API Key ID**, and the tenant **FQDN**.

Generate API keys in: **Settings → Configurations → Integrations → API Keys**

### API URI Patterns

```
https://api-{fqdn}/xsiam/public/v1/{endpoint_path}/
```

Older/alternative path (also seen in some docs):
```
https://api-{fqdn}/public_api/v1/{name_of_api}/{name_of_call}/
```

### Standard Key Authentication

```python
import requests

def call_xsiam_api(fqdn, api_key_id, api_key, endpoint, body=None):
    headers = {
        "x-xdr-auth-id": str(api_key_id),
        "Authorization": api_key,
        "Content-Type": "application/json",
    }
    url = f"https://api-{fqdn}/public_api/v1/{endpoint}"
    response = requests.post(url, headers=headers, json=body or {})
    response.raise_for_status()
    return response.json()
```

### Advanced Key Authentication

Advanced keys use HMAC-SHA256 with nonce and timestamp to prevent replay attacks. cURL does not natively support this method.

```python
import requests
import secrets
import string
import hashlib
from datetime import datetime, timezone

def call_xsiam_api_advanced(fqdn, api_key_id, api_key, endpoint, body=None):
    nonce = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(64))
    timestamp = int(datetime.now(timezone.utc).timestamp()) * 1000
    auth_key = "%s%s%s" % (api_key, nonce, timestamp)
    auth_key = auth_key.encode("utf-8")
    api_key_hash = hashlib.sha256(auth_key).hexdigest()
    headers = {
        "x-xdr-timestamp": str(timestamp),
        "x-xdr-nonce": nonce,
        "x-xdr-auth-id": str(api_key_id),
        "Authorization": api_key_hash,
        "Content-Type": "application/json",
    }
    url = f"https://api-{fqdn}/public_api/v1/{endpoint}"
    response = requests.post(url, headers=headers, json=body or {})
    response.raise_for_status()
    return response.json()
```

### Multi-Tenant Headers

For multi-tenant deployments, add this header to target a child tenant:

```
x-child-tenant-id: {child_tenant_id}
```

---

## API Request/Response Pattern

All XSIAM APIs follow a consistent pattern.

### Request Structure

All endpoints use `POST`. Parameters are wrapped in a `request_data` object:

```json
{
  "request_data": {
    "filters": [
      {
        "field": "field_name",
        "operator": "gte",
        "value": 1721149909250
      }
    ],
    "search_from": 0,
    "search_to": 100,
    "sort": {
      "field": "creation_time",
      "keyword": "desc"
    }
  }
}
```

### Response Structure

All responses return a `reply` object:

```json
{
  "reply": {
    "data": [ ... ],
    "total_count": 150,
    "filter_count": 25,
    "result_count": 25
  }
}
```

### Filter Operators

| Operator | Description |
|----------|-------------|
| `eq` | Equal |
| `neq` | Not equal |
| `gte` | Greater than or equal |
| `lte` | Less than or equal |
| `gt` | Greater than |
| `lt` | Less than |
| `contains` | String contains |
| `in` | Value in list |
| `not_in` | Value not in list |

---

## API Endpoint Catalog

All paths are relative to `https://api-{fqdn}/public_api/v1/`.

### Core Operational Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /incidents/get_incidents` | Retrieve incidents |
| `POST /incidents/get_incident_extra_data` | Get detailed incident data |
| `POST /incidents/update_incident` | Update incident fields |
| `POST /alerts/get_alerts` | Retrieve alerts |
| `POST /alerts/insert_cef_alerts` | Insert CEF-format alerts |
| `POST /alerts/insert_parsed_alerts` | Insert parsed alerts |
| `POST /endpoints/get_endpoint` | Get endpoints |
| `POST /endpoints/get_all` | List all endpoints |
| `POST /endpoints/isolate` | Isolate endpoint |
| `POST /endpoints/unisolate` | Unisolate endpoint |
| `POST /endpoints/scan` | Trigger endpoint scan |
| `POST /endpoints/cancel_scan` | Cancel scan |
| `POST /endpoints/delete` | Delete endpoint |

### XQL Query Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /xql/start_xql_query` | Start async XQL query |
| `POST /xql/get_query_results` | Get results (up to 1,000) |
| `POST /xql/get_query_results_stream` | Stream results beyond 1,000 |
| `POST /xql/get_quota` | Check daily query quota |

### Management Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /api_keys/get_api_keys` | List API keys |
| `POST /api_keys/generate_api_key` | Generate new API key |
| `POST /api_keys/delete_api_keys` | Delete API keys |
| `POST /assets/get_assets` | Get asset inventory |
| `POST /assets/get_asset_by_id` | Get single asset |
| `POST /assets/get_schema` | Get asset inventory schema |
| `POST /asset_groups/get_asset_groups` | Get asset groups |
| `POST /asset_groups/create_asset_group` | Create asset group |
| `POST /hash_exceptions/blacklist` | Blacklist file hash |
| `POST /hash_exceptions/whitelist` | Whitelist file hash |
| `POST /audits/management_logs` | Get management audit logs |
| `POST /audits/agents_reports` | Get agent audit reports |
| `POST /distributions/get_versions` | Get distribution versions |
| `POST /distributions/create` | Create distribution |
| `POST /scripts/run_script` | Run script on endpoints |

### Playbook Management Endpoints

Two endpoints, both with non-obvious request shapes - wire format is ZIP-wrapped YAML, not JSON.

| Endpoint | Purpose | Request | Response |
|----------|---------|---------|----------|
| `POST /public_api/v1/playbooks/get` | Fetch a playbook by name | JSON: `{"request_data": {"filter": {"field": "name", "value": "<exact name>"}}}` | ZIP body containing `<name>.yml` (despite `Content-Type: application/json` request header) |
| `POST /public_api/v1/playbooks/get_all` | List all playbooks with metadata | JSON: `{"request_data": {}}` | JSON `{"reply": {"playbooks": [{name, id, modified, tags, ...}]}}` |
| `POST /public_api/v1/playbooks/insert` | Create or update a playbook | `multipart/form-data` with `file=(playbook.zip, <bytes>, application/zip)` where the ZIP contains the playbook YAML at any name (e.g. `playbook.yml`) | 200 on success |
| `POST /public_api/v1/playbooks/delete` | Delete a playbook by name | JSON: `{"request_data": {"filter": {"field": "name", "value": "<exact name>"}}}` | JSON with `succeeded_items` / `failures_items` |

**Auth headers** are the standard pair (`Authorization`, `X-XDR-AUTH-ID`) - no `Content-Type` on `insert` (multipart sets it). Server identifies the playbook by the `name` / `id` fields **inside the YAML**, not by the ZIP filename or the YAML filename inside the ZIP.

### Additional Endpoint Categories

These categories exist in the API but are less commonly used programmatically:
- **Attack Surface Management (ASM)** - external service discovery
- **BIOCs** - behavioral IOC rule management
- **Cases** - case management operations
- **Correlation Rules** - programmatic rule management
- **Dashboards** - dashboard management
- **Dataset Management** - XQL dataset operations
- **Lookup Datasets** - lookup table management for XQL
- **Playbooks** - playbook management and execution
- **Profiles** - security profile management
- **Query Library** - saved XQL query management
- **Scheduled Queries** - recurring query management

---

## XQL Query APIs

Running XQL queries via API follows a **3-step async flow**.

### Prerequisites

- API Key with **Instance Administrator** role permissions
- Available query quota (daily limit based on license)
- Maximum **4 parallel API queries** at once

### Step 1: Start Query

```
POST /xql/start_xql_query
```

```json
{
  "request_data": {
    "query": "dataset = xdr_data | filter action_process_image_name = \"cmd.exe\" | fields agent_hostname, action_process_image_name | limit 100",
    "tenants": ["tenant_id"],
    "timeframe": {
      "from": 1609459200000,
      "to": 1609545600000
    }
  }
}
```

Response returns an `execution_id`:

```json
{
  "reply": "execution_id_string"
}
```

### Step 2: Get Results

```
POST /xql/get_query_results
```

```json
{
  "request_data": {
    "query_id": "execution_id_string",
    "pending_result": true
  }
}
```

Returns up to **1,000 results**. If more exist, response includes a `stream_id`.

```json
{
  "reply": {
    "status": "SUCCESS",
    "number_of_results": 1000,
    "query_cost": { ... },
    "remaining_quota": 123.45,
    "results": {
      "data": [ ... ]
    },
    "stream_id": "stream_id_if_more_results"
  }
}
```

### Step 3: Stream Additional Results (if > 1,000)

```
POST /xql/get_query_results_stream
```

```json
{
  "request_data": {
    "stream_id": "stream_id_string",
    "is_gzip_compressed": false
  }
}
```

### Query Quota

Each query costs query units based on complexity and result count. Track usage via:
- `query_cost` field in results response
- `remaining_quota` field in results response
- `POST /xql/get_quota` endpoint for daily quota check

---

## Event Collector Integrations

Event collectors are the primary mechanism for ingesting data into XSIAM from external products. These are **XSIAM-specific** integrations (not available in XSOAR standalone).

### YAML Configuration

```yaml
script:
  isfetchevents: true
fromversion: 6.8.0
marketplaces:
  - marketplacev2
```

### Naming Convention

Integration names must end with `Event Collector` (e.g., "Okta Event Collector").

### Required Commands

1. `test-module` - Tests connectivity
2. `{vendor-prefix}-get-events` - Fetches events for display in War Room
3. `fetch-events` - Main event ingestion command, runs at configured interval

### Sending Events to XSIAM

```python
from CommonServerPython import *

def main():
    client = Client(...)
    command = demisto.command()

    if command == 'fetch-events':
        events, last_run = fetch_events_command(client)
        # Always call send_events_to_xsiam, even with empty events
        # (updates the UI counter)
        send_events_to_xsiam(
            events=events,           # list of dicts/strings, or newline-separated string
            vendor='MyVendor',       # vendor name
            product='MyProduct',     # product name
            # data_format='cef'      # only for CEF/LEEF string formats
        )
    elif command == '{vendor}-get-events':
        results = get_events_command(client)
        return_results(results)
```

### Viewing Ingested Events

Query the created dataset in XQL:

```xql
dataset = MyVendor_MyProduct_raw
```

> **Important:** `send_events_to_xsiam()` only works in system integrations, not custom integrations.

---

## Mirroring Integration Pattern

Mirroring enables bidirectional sync between XSIAM and external systems (ServiceNow, Jira, etc.).

### YAML Configuration

```yaml
script:
  isfetch: true
  ismappable: true
  isremotesyncin: true
  isremotesyncout: true
```

### Required Commands

| Command | Purpose | Frequency |
|---------|---------|-----------|
| `fetch-incidents` | Initial incident ingestion | Per fetch interval |
| `get-remote-data` | Pull updates from remote system | Every 1 min per incident |
| `get-modified-remote-data` | Check which incidents changed remotely | Every 1 min per instance |
| `update-remote-system` | Push local changes to remote system | On local change |
| `get-mapping-fields` | Pull remote schema for field mapping | On demand |

### Required Incident Fields for Mirroring

```python
incident = {
    'name': 'Incident Name',
    'dbotMirrorDirection': 'Both',          # 'Both', 'In', 'Out', or 'None'
    'dbotMirrorId': str(remote_id),         # ID in external system
    'dbotMirrorInstance': demisto.integrationInstance(),
    'dbotMirrorTags': ['comments', 'files'],
    'rawJSON': json.dumps(raw_data),
}
```

### get-remote-data Implementation

```python
def get_remote_data_command(client, args):
    parsed_args = GetRemoteDataArgs(args)
    new_data = client.get_incident(
        parsed_args.remote_incident_id,
        parsed_args.last_update
    )
    entries = client.get_entries(
        parsed_args.remote_incident_id,
        parsed_args.last_update
    )

    parsed_entries = []
    for entry in entries:
        parsed_entries.append({
            'Type': EntryType.NOTE,
            'Contents': entry.get('contents'),
            'ContentsFormat': EntryFormat.TEXT,
            'Tags': ['comment_tag'],
            'Note': True,
        })

    # To close the incident from remote:
    # parsed_entries.append({
    #     'Contents': {'dbotIncidentClose': True, 'closeReason': 'Resolved'}
    # })
    # To reopen:
    # parsed_entries.append({'Contents': {'dbotIncidentReopen': True}})

    return GetRemoteDataResponse(new_data, parsed_entries)
```

### update-remote-system Implementation

```python
def update_remote_system_command(client, args):
    parsed_args = UpdateRemoteSystemArgs(args)
    remote_id = parsed_args.remote_incident_id

    if parsed_args.incident_changed and parsed_args.delta:
        client.update_incident(remote_id, parsed_args.delta)

    if parsed_args.entries:
        for entry in parsed_args.entries:
            client.add_comment(remote_id, entry)

    if parsed_args.inc_status == IncidentStatus.DONE:
        client.close_incident(remote_id)

    return remote_id
```

---

## Integration Cache

For storing data between command runs (e.g., JWT tokens with expiration):

```python
# Get cached data
context = get_integration_context()
token = context.get('access_token')
valid_until = context.get('valid_until')

if token and int(valid_until) > int(time.time()):
    return token

# Refresh token
new_token = client.get_new_token()
set_integration_context({
    'access_token': new_token,
    'valid_until': str(int(time.time()) + 3600)
})
```

### Rules

- Keys and values must be **strings**
- `set_integration_context()` **overwrites the entire context** - get first, modify, then set
- Not available in `test-module` command
- Stored per integration instance in the database

---

## Long-Running Containers

For integrations that need persistent processes (webhooks, listeners, EDL servers).

### YAML Configuration

```yaml
script:
  longRunning: true
```

### Implementation

```python
def long_running_execution():
    while True:
        try:
            # Persistent logic here (e.g., listen for webhooks)
            process_events()
        except Exception as e:
            demisto.error(f"Error: {e}")
            time.sleep(60)

if demisto.command() == 'long-running-execution':
    long_running_execution()
```

### Server Interaction Functions

| Function | Purpose |
|----------|---------|
| `addEntry(id, entry)` | Add entry to incident War Room |
| `createIncidents(incidents_json)` | Create new incidents |
| `findUser(username)` | Find XSOAR user |
| `updateModuleHealth(message, is_error)` | Update instance status in UI |
| `mirrorInvestigation(id, mirror_type)` | Mirror investigation to chat |
| `demisto.setIntegrationContext(ctx)` | Store state between iterations |
| `demisto.getIntegrationContext()` | Retrieve stored state |

### Best Practices

- **Never** use `sys.exit()` or `return_error()` - these kill the container
- Always catch and log exceptions
- Use async code for parallel processing (see Slack v2 integration as reference)
- Use `updateModuleHealth()` to report status to the UI

---

## Docker Image Management

### Specifying Docker Image

In the integration YAML:

```yaml
script:
  dockerimage: demisto/python3:3.10.13.12345
```

### Disable Auto-Update

To pin a specific image version and prevent automatic updates:

```yaml
script:
  dockerimage: demisto/oauthlib:1.0.0.16907
  autoUpdateDockerImage: false
```

### Available Images

All images are hosted on Docker Hub under the `demisto/` organization. Search image metadata at the `demisto/dockerfiles-info` repository.

---

## Python Client Pattern

Complete client class for direct XSIAM API integration:

```python
from CommonServerPython import *

class Client(BaseClient):
    """Client for Cortex XSIAM API."""

    def __init__(self, base_url, api_key, api_key_id, verify=True, proxy=False):
        headers = {
            'Authorization': api_key,
            'x-xdr-auth-id': str(api_key_id),
            'Content-Type': 'application/json',
        }
        super().__init__(
            base_url=base_url,
            headers=headers,
            verify=verify,
            proxy=proxy
        )

    def get_incidents(self, filters=None, search_from=0, search_to=100):
        body = {
            'request_data': {
                'filters': filters or [],
                'search_from': search_from,
                'search_to': search_to,
            }
        }
        return self._http_request('POST', '/incidents/get_incidents', json_data=body)

    def start_xql_query(self, query, timeframe=None):
        body = {
            'request_data': {
                'query': query,
            }
        }
        if timeframe:
            body['request_data']['timeframe'] = timeframe
        return self._http_request('POST', '/xql/start_xql_query', json_data=body)

    def get_xql_results(self, query_id):
        body = {
            'request_data': {
                'query_id': query_id,
                'pending_result': True,
            }
        }
        return self._http_request('POST', '/xql/get_query_results', json_data=body)

    def run_script(self, script_uid, endpoint_ids, parameters=None):
        body = {
            'request_data': {
                'script_uid': script_uid,
                'filters': [{
                    'field': 'endpoint_id_list',
                    'operator': 'in',
                    'value': endpoint_ids
                }],
                'parameters_values': parameters or {},
            }
        }
        return self._http_request('POST', '/scripts/run_script', json_data=body)

    def get_endpoints(self, filters=None):
        body = {
            'request_data': {
                'filters': filters or [],
            }
        }
        return self._http_request('POST', '/endpoints/get_endpoints', json_data=body)
```

---

## API Licensing

The XSIAM 3.4 API documentation covers:
- **Cortex XSIAM Premium**
- **Cortex XSIAM Enterprise**
- **Cortex XSIAM NG SIEM**
- **Cortex XSIAM Enterprise Plus**

Each individual API endpoint lists its specific license requirements. Always verify the license requirement before building integrations that depend on specific endpoints.

---

## Documentation References

- Full API Reference: https://cortex-panw.stoplight.io/docs/cortex-xsiam-1
- Developer Docs: https://xsoar.pan.dev/
- Docker Images: https://hub.docker.com/u/demisto
- Docker Image Metadata: https://github.com/demisto/dockerfiles-info
