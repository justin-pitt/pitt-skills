# SOAR Development Reference

> **CDW Terminology Note**: At CDW, SOC analysts work out of **cases** and **issues** — not "incidents." However, this development reference preserves Palo Alto's original "incident" terminology in all code, API, YAML, and directory structure references because those are the actual function names, parameter names, and directory names in the platform (e.g., `fetch-incidents`, `demisto.incidents()`, `IncidentTypes/`, `IncidentFields/`). Narrative and operational language uses "case" where appropriate.

## Table of Contents
1. [Overview](#overview)
2. [Playbook Development](#playbook-development)
3. [Python Code Conventions](#python-code-conventions)
4. [Integration YAML Metadata](#integration-yaml-metadata)
5. [Content Pack Structure](#content-pack-structure)
6. [Context and Outputs](#context-and-outputs)
7. [Reputation Commands (IOC)](#reputation-commands-ioc)
8. [Unit Testing](#unit-testing)
9. [CLI Tools (demisto-sdk)](#cli-tools-demisto-sdk)
10. [Helper Functions Reference](#helper-functions-reference)
11. [Documentation References](#documentation-references)

---

## Overview

This reference covers the development side of XSIAM/XSOAR automation: building custom integrations, writing scripts, creating content packs, and developing playbooks. For operational playbook usage, design patterns, and Marketplace content, see `soar-automation.md`.

All new integrations and scripts must be written in **Python 3**. Python 2 is deprecated (end of support October 2025).

---

## Playbook Development

### Parent vs Sub-Playbooks

**Parent playbooks** run as the main playbook of a case (e.g., "Phishing Investigation - Generic v2", "Endpoint Malware Investigation - Generic").

**Sub-playbooks** are called by other playbooks as reusable building blocks (e.g., "IP Enrichment - Generic v2", "Retrieve File From Endpoint - Generic"). Sub-playbooks must define inputs and outputs so data flows between them and the parent.

### Task Types

**Standard tasks** — Range from manual tasks (create case, escalate) to automated tasks (parse file, enrich indicators). Automated tasks are based on integration commands or scripts. Commands can be integration-specific (e.g., `!ADGetUser`) or multi-integration (e.g., `!file` runs across ALL installed file-reputation integrations simultaneously).

**Conditional tasks** — Decision-tree branching. Check whether indicators were found, whether an integration is enabled, or ask a single-question survey whose answer determines the next branch.

**Data collection tasks** — Interact with users via external surveys (no authentication required). Responses are collected in case context data and can populate custom fields like Grid fields.

**Section headers** — Organizational groupings for related tasks (like chapters in a book). For example, a phishing playbook might have sections for "Indicator Enrichment" and "User Communication."

### Inputs and Outputs

Playbook tasks have **inputs** (data pieces present in the playbook) and **outputs** (objects produced by task execution). Outputs are stored in context and serve downstream tasks. You can map command output directly to case fields as an alternative to using a `setIncident` task.

> **API Note**: The task to update case fields is still called `setIncident` at the API level.

### Key Design Questions

When building a playbook, consider:
- What actions are needed?
- Which conditions apply (manual or automatic decisions)?
- Do you need looping for iterative tasks?
- Are there time-sensitive aspects (SLAs, timeouts)?
- When is the case considered remediated?

---

## Python Code Conventions

### File Structure (Integration)
```
Packs/
└── MyPack/
    └── Integrations/
        └── MyIntegration/
            ├── MyIntegration.py              # Main Python code
            ├── MyIntegration.yml             # Integration YAML metadata
            ├── MyIntegration_test.py         # Unit tests
            ├── MyIntegration_description.md  # Detailed description
            ├── MyIntegration_image.png       # Integration icon
            ├── README.md                     # Auto-generated docs
            └── command_examples              # Example outputs
```

### Required Imports
```python
import demistomock as demisto
from CommonServerPython import *
from CommonServerUserPython import *

import json
import urllib3
urllib3.disable_warnings()
```

### Constants (Module-Level)
```python
DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
```

> **Rules:** Never define global mutable variables. Do not call `demisto.params()` at the module level.

### Client Class Pattern

The Client class inherits from `BaseClient` (provided by `CommonServerPython`). It encapsulates all HTTP communication with the third-party API and should NOT contain any XSOAR logic.

```python
class Client(BaseClient):
    def get_ip_reputation(self, ip: str) -> Dict[str, Any]:
        return self._http_request(
            method='GET',
            url_suffix='/ip',
            params={'ip': ip}
        )

    def get_alert(self, alert_id: str) -> Dict[str, Any]:
        return self._http_request(
            method='GET',
            url_suffix='/get_alert_details',
            params={'alert_id': alert_id}
        )
```

**Client instantiation with API key:**
```python
client = Client(
    base_url=base_url,
    verify=verify_certificate,
    headers={'Authorization': f'Bearer {api_key}'},
    proxy=proxy
)
```

**Client instantiation with Basic Auth:**
```python
client = Client(
    base_url=base_url,
    verify=verify_certificate,
    auth=(username, password),
    proxy=proxy
)
```

### Main Function Pattern

The main function handles parameter extraction, client instantiation, and command routing. This is the only place where `demisto.params()`, `demisto.command()`, and `demisto.args()` should be called.

```python
def main():
    params = demisto.params()
    username = params.get('credentials', {}).get('identifier')
    password = params.get('credentials', {}).get('password')
    base_url = urljoin(params['url'], '/api/v1/suffix')
    verify_certificate = not params.get('insecure', False)
    first_fetch_time = params.get('fetch_time', '3 days').strip()
    proxy = params.get('proxy', False)
    command = demisto.command()
    demisto.debug(f'Command being called is {command}')

    try:
        client = Client(
            base_url=base_url,
            verify=verify_certificate,
            auth=(username, password),
            proxy=proxy
        )

        if command == 'test-module':
            result = test_module(client)
            return_results(result)

        elif command == 'fetch-incidents':
            next_run, incidents = fetch_incidents(
                client=client,
                last_run=demisto.getLastRun(),
                first_fetch_time=first_fetch_time
            )
            demisto.setLastRun(next_run)
            demisto.incidents(incidents)

        elif command == 'myintegration-get-alerts':
            return_results(get_alerts_command(client, demisto.args()))

    except Exception as e:
        return_error(f'Failed to execute {command} command. Error: {str(e)}')


if __name__ in ('__main__', '__builtin__', 'builtins'):
    main()
```

> **Code Note**: `fetch-incidents` and `demisto.incidents()` are the actual API function names — these create what CDW operationally calls "cases."

### Command Function Pattern

Each command gets its own `_command` function. It receives the `client` instance and `args` dict, and returns a `CommandResults` object. Do NOT use `demisto.results()` or global functions inside command functions — keep them unit-testable.

```python
def get_alerts_command(client, args):
    alert_id = args.get('alert_id')
    result = client.get_alert(alert_id)

    readable_output = tableToMarkdown('Alert Details', result)

    return CommandResults(
        outputs_prefix='MyIntegration.Alert',
        outputs_key_field='id',
        outputs=result,
        readable_output=readable_output,
        raw_response=result
    )
```

### CommandResults Class

The primary way to return data to the War Room and context.

| Argument | Type | Description |
|----------|------|-------------|
| `outputs_prefix` | str | Context path prefix (e.g., `CortexXDR.Incident`) |
| `outputs_key_field` | str or list | Primary key field(s) for deduplication |
| `outputs` | list/dict | Data returned to context |
| `readable_output` | str | Markdown for War Room display |
| `raw_response` | object | Original raw API response |
| `indicator` | Common.Indicator | Indicator object (IP, URL, File, Domain, etc.) |
| `indicators_timeline` | IndicatorsTimeline | Timeline data for indicators |
| `ignore_auto_extract` | bool | Prevent auto-extraction of indicators from results |
| `mark_as_note` | bool | Mark entry as a note |
| `relationships` | list | EntityRelationship objects |
| `scheduled_command` | ScheduledCommand | For polling commands |

> **Code Note**: `outputs_prefix` values like `CortexXDR.Incident` use Palo Alto's API naming convention — this is the expected format.

### test-module Implementation

When users click "Test" on the integration settings, `test-module` executes. Return `'ok'` for success; any other string shows as the failure message.

```python
def test_module(client):
    result = client.say_hello('DBot')
    if 'Hello DBot' == result:
        return 'ok'
    else:
        return 'Test failed because ...'
```

### fetch-incidents Implementation

Runs periodically when "Fetch incidents" is enabled. Must be unit-testable — receive `last_run` as a parameter, return `next_run` and `incidents` to main. This is the mechanism that creates cases in XSIAM.

> **Code Note**: The function name, parameter names, and variable names all use "incident" — this is Palo Alto's API convention. The objects created by this function are what CDW calls "cases."

```python
def fetch_incidents(client, last_run, first_fetch_time):
    last_fetch = last_run.get('last_fetch')
    if last_fetch is None:
        last_fetch, _ = dateparser.parse(first_fetch_time)
    else:
        last_fetch = dateparser.parse(last_fetch)

    latest_created_time = last_fetch
    incidents = []

    for item in client.list_incidents():
        incident_created_time = dateparser.parse(item['created_time'])
        incidents.append({
            'name': item['description'],
            'occurred': incident_created_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'rawJSON': json.dumps(item)
        })
        if incident_created_time > latest_created_time:
            latest_created_time = incident_created_time

    next_run = {'last_fetch': latest_created_time.strftime(DATE_FORMAT)}
    return next_run, incidents
```

### Pagination Pattern

Support two use cases with three arguments: `page`, `page_size`, `limit`.

- **Manual pagination**: User provides `page` + `page_size`; `limit` is ignored
- **Automatic pagination**: User provides `limit`; code iterates pages internally until `limit` results are collected

Defaults: `limit` = 50 in YAML, `page_size` = 50 in code. No maximum for `limit`.

### Logging

```python
demisto.debug('DEBUG level message')
demisto.info('INFO level message')
demisto.error('ERROR level message')
```

Use the `@logger` decorator on functions to auto-log function name and arguments. Never print sensitive data to logs.

### Dates

Always use human-readable format `%Y-%m-%dT%H:%M:%SZ` in customer-facing results. Convert epoch internally if the API requires it:

```python
formatted_time = timestamp_to_datestring(time_epoch, "%Y-%m-%dT%H:%M:%S")
```

---

## Integration YAML Metadata

### Top-Level Structure

```yaml
commonfields:
  id: MyIntegration
  version: -1

name: MyIntegration
display: My Integration Display Name
category: Data Enrichment & Threat Intelligence
description: Short description
detaileddescription: |
  Longer description with setup instructions

configuration:
  - display: Server URL
    name: url
    type: 0          # Short text
    required: true
    section: Connect

  - displaypassword: API Key
    name: credentials
    type: 9          # Credentials
    required: true
    hiddenusername: true
    section: Connect

  - display: Use system proxy settings
    name: proxy
    type: 8          # Boolean checkbox
    required: false
    section: Connect
    advanced: true

  - display: Trust any certificate (not secure)
    name: insecure
    type: 8
    required: false
    section: Connect
    advanced: true

  - display: Fetch incidents
    name: isFetch
    type: 8
    required: false
    section: Collect

sectionOrder:
  - Connect
  - Collect

script:
  type: python
  subtype: python3
  dockerimage: demisto/python3:3.10.x.xxxxx
  isfetch: true
  commands:
    - name: myintegration-get-alerts
      description: Retrieves alerts from the service
      arguments:
        - name: alert_id
          description: The alert ID
          required: false
        - name: limit
          description: Maximum number of results
          required: false
          defaultValue: '50'
      outputs:
        - contextPath: MyIntegration.Alert.id
          description: The alert ID
          type: String
        - contextPath: MyIntegration.Alert.name
          description: The alert name
          type: String
        - contextPath: MyIntegration.Alert.severity
          description: Alert severity
          type: Number

fromversion: 6.5.0
tests:
  - MyIntegration Test
```

> **YAML Note**: The `Fetch incidents` display label and `isFetch`/`isfetch` parameter names are Palo Alto's required naming — do not change these even though CDW uses "case" operationally.

### YAML Parameter Types

| Type | Description |
|------|-------------|
| 0 | Short text field |
| 4 | Encrypted text field |
| 8 | Boolean checkbox |
| 9 | Authentication (credentials vault support) |
| 12 | Long text block |
| 13 | Case type single-select dropdown *(API-level: "Incident type")* |
| 15 | Single-select dropdown |
| 16 | Multi-select dropdown |

### Configuration Sections

As of XSIAM 1.3+, parameters are grouped into sections:

- **Connect** — URL, credentials, mandatory params; advanced: proxy, TLS, log level
- **Collect** — Fetch toggles, first fetch time, fetch count; advanced: intervals, mirroring
- **Optimize** — Thresholds, advanced queries, other non-connect/collect params

### Command Argument Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | str | Argument name |
| `required` | bool | Whether the argument is required |
| `default` | bool | If true, value can be passed without naming the argument |
| `isArray` | bool | If true, accepts CSV list; command runs once for all inputs |
| `secret` | bool | If true, value is hidden in War Room output |
| `execution` | bool | If true, command is marked "Potentially harmful" |
| `description` | str | Argument description |

---

## Content Pack Structure

> **Directory Note**: Directory names like `IncidentTypes/` and `IncidentFields/` are Palo Alto's required naming convention for the content pack structure. These directories contain what CDW operationally calls case types and case fields.

```
Packs/
└── MyPackName/
    ├── pack_metadata.json
    ├── README.md
    ├── Author_image.png
    ├── .secrets-ignore
    ├── .pack-ignore
    ├── CONTRIBUTORS.json
    ├── Integrations/
    │   └── MyIntegration/
    │       ├── MyIntegration.py
    │       ├── MyIntegration.yml
    │       ├── MyIntegration_test.py
    │       ├── MyIntegration_description.md
    │       ├── MyIntegration_image.png
    │       └── README.md
    ├── Scripts/
    │   └── MyScript/
    │       ├── MyScript.py
    │       ├── MyScript.yml
    │       ├── MyScript_test.py
    │       └── README.md
    ├── Playbooks/
    │   ├── playbook-MyPlaybook.yml
    │   └── playbook-MyPlaybook_README.md
    ├── TestPlaybooks/
    │   └── playbook-MyIntegration_Test.yml
    ├── IncidentTypes/          # Case types (API naming: "IncidentTypes")
    │   └── incidenttype-MyType.json
    ├── IncidentFields/         # Case fields (API naming: "IncidentFields")
    │   └── incidentfield-MyField.json
    ├── IndicatorTypes/
    ├── IndicatorFields/
    ├── Layouts/
    ├── Classifiers/
    ├── Dashboards/
    ├── Reports/
    └── Connections/
```

### pack_metadata.json

```json
{
  "name": "My Pack Name",
  "description": "Short pack description",
  "support": "community",
  "currentVersion": "1.0.0",
  "author": "Your Name",
  "url": "https://github.com/your-repo",
  "email": "",
  "categories": ["Endpoint"],
  "tags": [],
  "created": "2026-04-06T10:00:00Z",
  "useCases": [],
  "keywords": [],
  "marketplaces": ["xsoar", "marketplacev2"],
  "dependencies": {}
}
```

### Marketplace Values

| Value | Platform |
|-------|----------|
| `xsoar` | XSOAR 6 + 8 |
| `xsoar_on_prem` | XSOAR 6 only |
| `xsoar_saas` | XSOAR 8 only |
| `marketplacev2` | XSIAM |
| `xpanse` | XPANSE |

### Version Format

`MAJOR.MINOR.REVISION` — major for breaking changes, minor for new features, revision for bug fixes.

---

## Context and Outputs

### Context Path Convention

`BrandName.Object.Property` — e.g., `CortexXDR.Incident.incident_id`

> **Code Note**: Context paths like `CortexXDR.Incident` use Palo Alto's naming convention — do not change these to `CortexXDR.Case` as they must match the platform's expected schema.

### Context Standards

Return BOTH vendor-specific AND standard context:

```json
{
  "VendorName": { "Object": { "...vendor fields..." } },
  "StandardObject": { "...standard fields..." },
  "DBotScore": { "...reputation score..." }
}
```

### Linking Context (DT - Demisto Transform Language)

Link context entries to prevent duplicates and enable enrichment:

```python
ec = {
    'URLScan(val.URL && val.URL == obj.URL)': cont_array,
    'URL': url_array,
    'IP': ip_array,
}
```

With `CommandResults`, linking is automatic via `outputs_key_field`.

---

## Reputation Commands (IOC)

For `!ip`, `!url`, `!file`, `!domain`, `!email` commands: the argument of the same name must have `default: true` and `isArray: true` in the YAML. Return both vendor-specific context AND standard context objects.

### DBotScore Values

| Constant | Value | Meaning |
|----------|-------|---------|
| `Common.DBotScore.NONE` | 0 | Unknown / not enough data |
| `Common.DBotScore.GOOD` | 1 | Known good |
| `Common.DBotScore.SUSPICIOUS` | 2 | Suspicious |
| `Common.DBotScore.BAD` | 3 | Known malicious |

### Standard Indicator Classes

Available from `CommonServerPython`:
- `Common.IP` — IP address indicator
- `Common.URL` — URL indicator
- `Common.File` — File hash indicator
- `Common.Domain` — Domain indicator
- `Common.CVE` — CVE indicator
- `Common.CustomIndicator` — Custom indicator types

### Reputation Command Example

```python
def ip_command(client, args):
    ip = args.get('ip')
    result = client.get_ip_reputation(ip)

    score = Common.DBotScore.SUSPICIOUS if result.get('risk') > 50 else Common.DBotScore.NONE

    dbot_score = Common.DBotScore(
        indicator=ip,
        indicator_type=DBotScoreType.IP,
        integration_name='MyIntegration',
        score=score,
        reliability=demisto.params().get('integrationReliability')
    )

    ip_indicator = Common.IP(
        ip=ip,
        dbot_score=dbot_score,
        asn=result.get('asn'),
        geo_country=result.get('country')
    )

    return CommandResults(
        outputs_prefix='MyIntegration.IP',
        outputs_key_field='address',
        outputs=result,
        indicator=ip_indicator,
        readable_output=tableToMarkdown('IP Reputation', result)
    )
```

### "Not Found" Response

Use the helper to return a consistent "unknown" response when an indicator isn't found:

```python
create_indicator_result_with_dbotscore_unknown(
    indicator='8.8.8.8',
    indicator_type=DBotScoreType.IP,
    reliability=demisto.params().get('integrationReliability')
)
```

---

## Unit Testing

Every command must have unit tests in a `_test.py` file. Use the Given-When-Then documentation pattern. Use `requests_mock` for HTTP mocking and `mocker` for general mocks.

### Test Pattern

```python
from MyIntegration import Client, get_alerts_command

def test_get_alerts_command(requests_mock):
    """
    Given: An alert ID to look up
    When: Calling get_alerts_command
    Then: Outputs match expected values with correct prefix
    """
    mock_response = {'id': '123', 'name': 'Test Alert', 'severity': 'high'}
    requests_mock.get('https://test.com/api/v1/get_alert_details', json=mock_response)

    client = Client(
        base_url="https://test.com/api/v1",
        verify=False,
        auth=("test", "test"),
        proxy=False
    )
    args = {"alert_id": "123"}
    results = get_alerts_command(client, args)

    assert results.outputs_prefix == 'MyIntegration.Alert'
    assert results.outputs['id'] == '123'
    assert results.outputs['severity'] == 'high'
```

### Testing fetch-incidents

```python
def test_fetch_incidents(requests_mock):
    """
    Given: A first fetch time and no previous last_run
    When: Calling fetch_incidents
    Then: Returns cases (API: incidents) and sets next_run timestamp
    """
    mock_incidents = [{'description': 'Test', 'created_time': '2026-04-01T00:00:00Z'}]
    requests_mock.get('https://test.com/api/v1/incidents', json=mock_incidents)

    client = Client(base_url="https://test.com/api/v1", verify=False, auth=("t", "t"), proxy=False)
    next_run, incidents = fetch_incidents(client, last_run={}, first_fetch_time='3 days')

    assert len(incidents) == 1
    assert 'last_fetch' in next_run
```

---

## CLI Tools (demisto-sdk)

### Core Commands

| Command | Purpose |
|---------|---------|
| `demisto-sdk init --pack` | Scaffold a new content pack |
| `demisto-sdk init --integration` | Scaffold a new integration |
| `demisto-sdk lint` | Lint Python code |
| `demisto-sdk validate` | Validate YAML/JSON structure |
| `demisto-sdk format` | Normalize YAML files |
| `demisto-sdk json-to-outputs -c <cmd> -p <prefix>` | Generate YAML outputs from JSON response |
| `demisto-sdk test-content` | Run tests |
| `demisto-sdk secrets` | Check for exposed secrets |
| `demisto-sdk generate-docs` | Auto-generate README |

### XSOAR/XSIAM CLI Commands (War Room / Playground)

- **System commands** prefixed with `/` — e.g., `/playground_create`, `/close_investigation`
- **External commands** prefixed with `!` — e.g., `!ip 8.8.8.8`, `!domain google.com`

---

## Helper Functions Reference

Functions available from `CommonServerPython`:

| Function | Purpose |
|----------|---------|
| `tableToMarkdown(name, data, headers, removeNull, headerTransform, url_keys, date_fields)` | Convert dict/list to markdown table for War Room display |
| `fileResult(filename, data, file_type)` | Return a file entry to the War Room |
| `return_error(message, error)` | Return error entry and stop script execution |
| `return_results(results)` | Return CommandResults to War Room |
| `create_indicator_result_with_dbotscore_unknown()` | Generic "not found" indicator response |
| `timestamp_to_datestring(timestamp, format)` | Convert epoch to human-readable date |
| `dateparser.parse(date_string)` | Parse human-readable date string to datetime |
| `urljoin(base, suffix)` | Safely join URL components |
| `demisto.command()` | Get the current command being executed |
| `demisto.args()` | Get command arguments as dict |
| `demisto.params()` | Get integration configuration parameters |
| `demisto.incidents(incidents)` | Submit fetched cases *(API naming: "incidents")* |
| `demisto.getLastRun()` | Get last run state for fetch-incidents |
| `demisto.setLastRun(obj)` | Set last run state for fetch-incidents |
| `demisto.debug(msg)` / `demisto.info(msg)` / `demisto.error(msg)` | Logging |

---

## Documentation References

- Developer Docs Home: https://xsoar.pan.dev/
- Code Conventions: https://xsoar.pan.dev/docs/integrations/code-conventions
- YAML File Reference: https://xsoar.pan.dev/docs/integrations/yaml-file
- Context and Outputs: https://xsoar.pan.dev/docs/integrations/context-and-outputs
- Context Standards: https://xsoar.pan.dev/docs/integrations/context-standards-about
- Content Pack Structure: https://xsoar.pan.dev/docs/packs/packs-format
- Playbook Overview: https://xsoar.pan.dev/docs/playbooks/playbooks-overview
- Playbook Contribution Guide: https://xsoar.pan.dev/docs/playbooks/playbook-contributions
- HelloWorld Example Integration: https://github.com/demisto/content/tree/master/Packs/HelloWorld
