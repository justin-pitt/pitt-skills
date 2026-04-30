# ThreatConnect API Reference

Complete REST API reference for ThreatConnect v2 and v3. Default to **v3 for all new work**; v2 is supported but legacy.

## Base URLs
- Public Cloud: `https://app.threatconnect.com/api`
- Dedicated/On-Prem: `https://<instance>.threatconnect.com/api`
- All requests must be HTTPS (otherwise 403)

---

## 1. Authentication

### Method 1: API Token (TC 7.7+, preferred)

Single header:
```
Authorization: TC-Token <API_TOKEN>
```

**Generate a token:** Settings > Org Settings > Membership tab > Create API User (or Edit existing) > set Token Expiration (days) > Save/Generate Token.

Token format example:
```
APIV2:430:c8mTcH:1234567890123:7mbiy0OnuSIq0ujNbkrqEB3RlpplzNL3CcQsYGso8ZQ=
```

Tokens are scoped to the API user's role and owner access. Expired tokens return **401 Unauthorized**.

### Method 2: HMAC (Access ID + Secret Key)

Two required headers:
```
Timestamp: <unix_epoch_seconds>
Authorization: TC <ACCESS_ID>:<SIGNATURE>
```

**Signature construction:**
1. Concatenate: `<api_path_with_query>:<HTTP_METHOD>:<timestamp>`
   - Example: `/api/v3/indicators?tql=typeName in ("Address"):GET:1713100000`
2. Sign with Secret Key using **HMAC-SHA256**
3. **Base64-encode** the result

**Critical rules:**
- Timestamp must be within **5 minutes** of server time (sync NTP)
- Path in signature must exactly match the request URL including query parameters and encoding
- HTTP method must be uppercase in the concatenated string

### Connectivity Test
```bash
curl -H "Authorization: TC-Token $TOKEN" \
     -H "Accept: application/json" \
     "https://app.threatconnect.com/api/v2/owners"
# Expected: 200 with list of accessible owners
```

---

## 2. v3 API Design Pattern

Every v3 endpoint supports a consistent set of methods:

| Method | Purpose | Key Parameters |
|---|---|---|
| `OPTIONS /v3/<type>` | Field names, types, descriptions | `?show=readOnly` for read-only fields |
| `OPTIONS /v3/<type>/fields` | Available `?fields=` options | |
| `OPTIONS /v3/<type>/tql` | Available TQL filter parameters | |
| `GET /v3/<type>` | List objects | `?tql=`, `?fields=`, `?resultStart=`, `?resultLimit=`, `?sorting=`, `?owner=` |
| `GET /v3/<type>/{id}` | Single object by ID | `?fields=`, `?owner=` |
| `POST /v3/<type>` | Create (supports nested objects) | `?owner=` |
| `PUT /v3/<type>/{id}` | Update (only changed fields needed) | `?owner=` |
| `DELETE /v3/<type>/{id}` | Delete single object | `?owner=` |
| `DELETE /v3/<type>?tql=` | Bulk delete (must be enabled in system settings) | `?owner=` |

**Self-documenting:** Always use `OPTIONS` to discover field names, types, and TQL parameters. Never guess.

### Response Format
```json
{
  "status": "Success",
  "data": { ... },
  "count": 42,
  "next": "https://app.threatconnect.com/api/v3/indicators?resultStart=100&resultLimit=100",
  "prev": "https://app.threatconnect.com/api/v3/indicators?resultStart=0&resultLimit=100"
}
```
Error responses include a `message` field with details.

---

## 3. v3 Endpoint Catalog

### Threat Intelligence
| Endpoint | Object |
|---|---|
| `/v3/indicators` | Indicators (CRUD + Associations + File Occurrences + False Positives/Observations) |
| `/v3/indicators/enrich` | Indicator Enrichment |
| `/v3/groups` | Groups (CRUD + Associations + File upload/download for Document/Report + PDF reports) |
| `/v3/indicatorAttributes` | Indicator Attributes (CRUD) |
| `/v3/groupAttributes` | Group Attributes (CRUD) |
| `/v3/tags` | Tags (CRUD + ATT&CK security coverage) |
| `/v3/securityLabels` | Security Labels (Retrieve only) |
| `/v3/exclusionLists` | Indicator Exclusion Lists (CRUD) |
| `/v3/victimAssets` | Victim Assets (CRUD + Associations) |
| `/v3/victimAttributes` | Victim Attributes (CRUD) |
| `/v3/victims` | Victims (CRUD + Associations) |
| `/v3/posts` | Posts/Notes (Create, Retrieve, Delete + Replies) [7.12+] |

### Intelligence Requirements
| Endpoint | Object |
|---|---|
| `/v3/intelRequirements` | IRs (CRUD + Associations) |
| `/v3/intelRequirements/categories` | IR Categories (Retrieve) |
| `/v3/intelRequirements/results` | IR Results (Retrieve, Update, Delete) |
| `/v3/intelRequirements/subtypes` | IR Subtypes (Retrieve) |

### Case Management
Requires **Organization Administrator** role for CRUD operations.

| Endpoint | Object |
|---|---|
| `/v3/cases` | Cases (CRUD + Associations) |
| `/v3/artifacts` | Artifacts (CRUD + Associations) |
| `/v3/artifactTypes` | Artifact Types (Retrieve) |
| `/v3/caseAttributes` | Case Attributes (CRUD) |
| `/v3/notes` | Notes (CRUD) |
| `/v3/tasks` | Workflow Tasks (CRUD) |
| `/v3/workflowEvents` | Workflow Events (CRUD) |
| `/v3/workflowTemplates` | Workflow Templates (CRUD) |

### Administration & System
| Endpoint | Object |
|---|---|
| `/v3/security/owners` | Owners (Retrieve) |
| `/v3/security/ownerRoles` | Owner Roles (Retrieve) |
| `/v3/security/systemRoles` | System Roles (Retrieve) |
| `/v3/security/users` | Users (CRUD) |
| `/v3/security/userGroups` | User Groups (Retrieve) |
| `/v3/attributeTypes` | Attribute Types (Retrieve) |
| `/v3/jobs` | Jobs (Retrieve) |
| `/v3/job/executions` | Job Executions (Retrieve) |
| `/v3/playbooks` | Playbooks (Retrieve) |
| `/v3/playbook/executions` | Playbook Executions (Retrieve) |
| `/v3/openApi` | OpenAPI specification |

### TC Exchange Administration
- Upload/install apps
- Generate API tokens and service tokens

Requires **Exchange Admin** system role.

---

## 4. Indicators

### Indicator Types and Required Fields

| Type | `type` Value | Required Field | Format Rules |
|---|---|---|---|
| IP Address | `Address` | `ip` | IPv4 or IPv6 |
| Email | `EmailAddress` | `address` | Valid email |
| File Hash | `File` | `md5`, `sha1`, or `sha256` | At least one hash required |
| Domain/Host | `Host` | `hostName` | ASCII only; Punycode for IDN |
| URL | `URL` | `text` | Domain lowercase; include protocol |
| ASN | `ASN` | `AS Number` | Prefix `ASN`, no space: `ASN12345` |
| CIDR | `CIDR` | `Block` | IPv6: no `::` compression, no leading zeros, replace `0000` with `0` |
| Email Subject | `Email Subject` | `Subject` | |
| Hashtag | `Hashtag` | `Hashtag` | |
| Mutex | `Mutex` | `Mutex` | |
| Registry Key | `Registry Key` | `Key Name`, `Value Name` | Key starts with full hive (e.g., `HKEY_LOCAL_MACHINE`); Value Name required (use `" "` for empty) |
| User Agent | `User Agent` | `User Agent` | |

### Common Fields (All Indicator Types)

| Field | Type | Notes |
|---|---|---|
| `active` | Boolean | Active status |
| `activeLocked` | Boolean | Lock status (CAL Status Lock) |
| `confidence` | Integer 0-100 | Confidence Rating |
| `rating` | Decimal 0.0-5.0 | Threat Rating |
| `privateFlag` | Boolean | Private indicator |
| `firstSeen` / `lastSeen` | DateTime | First/last observation |
| `externalDateAdded` | DateTime | External creation date |
| `externalDateExpires` | DateTime | External expiration |
| `tags` | Tag Object | `{"data": [{"name": "TagName"}]}` |
| `securityLabels` | Security Label Object | `{"data": [{"name": "TLP:AMBER"}]}` |
| `attributes` | Attribute Object | `{"data": [{"type": "Description", "value": "...", "default": true}]}` |
| `associatedGroups` | Group Object | `{"data": [{"id": 12345}]}` |
| `associatedIndicators` | Indicator Object | `{"data": [{"id": 12345}]}` |
| `associatedCases` | Case Object | `{"data": [{"id": 12345}]}` |

**Read-only fields:** `description` and `source` are read-only. Use the `attributes` field with type `"Description"` or `"Source"` instead.

### Create Indicator Example
```json
POST /v3/indicators
{
  "type": "Host",
  "hostName": "bad-actor.com",
  "rating": 4.0,
  "confidence": 85,
  "active": true,
  "tags": {"data": [{"name": "Targeted Attack"}, {"name": "APT29"}]},
  "attributes": {"data": [{"type": "Description", "value": "Known C2 domain", "default": true}]},
  "securityLabels": {"data": [{"name": "TLP:AMBER"}]},
  "associatedGroups": {"data": [{"id": 12345}]}
}
```

### Update Indicator (only changed fields)
```json
PUT /v3/indicators/{id}
{"rating": 5.0, "confidence": 95}
```

### Retrieve by Summary
```
GET /v3/indicators/bad-actor.com
```
Searches your Organization by default. Add `?owner=<ownerName>` for Community/Source.

### False Positives and Observations
```
POST /v3/indicators/{id}/falsePositive
POST /v3/indicators/{id}/observations
{"count": 1}
```

### File-Specific Operations
- **File Occurrences:** Track where a file hash was seen (path, date, filename)
- **Merge File Hashes:** Combine separate MD5/SHA1/SHA256 entries into one indicator
- **File Actions:** Track malicious file behaviors

### Indicator Formatting Gotchas (400 Error Causes)
- **ASN:** `ASN12345` correct; `AS12345`, `AS 12345`, `12345`, `ASN 12345` all wrong
- **Host:** ASCII only. `österreich.icom.museum` becomes `xn--sterreich-z7a.icom.museum`
- **URL:** Domain lowercase. `http://EXAMPLE.com` becomes `http://example.com`. ASCII domain.
- **CIDR (IPv6):** No `::` compression. No leading zeros. `0000` becomes `0`. Example: `abc:def:10:0:0:0:0:0/48`
- **Registry Key:** Expand `HKLM\` to `HKEY_LOCAL_MACHINE\`. Value Name required (`" "` for empty)

### IPv6 CIDR Conversion (Python)
```python
import ipaddress
incoming = "2001:db8:1234::/48"
sections = [s.replace("0000", "xxxx").lstrip("0")
            for s in ipaddress.IPv6Network(incoming).exploded.split(":")]
formatted = ":".join(sections).replace("xxxx", "0")
# Result: "2001:db8:1234:0:0:0:0:0/48"
```

---

## 5. Groups

### Create Group Example
```json
POST /v3/groups
{
  "type": "Campaign",
  "name": "Operation Nightfall",
  "firstSeen": "2025-01-15T00:00:00Z",
  "tags": {"data": [{"name": "APT29"}]},
  "associatedIndicators": {"data": [{"id": 56789}]}
}
```

### Document and Report Groups (file handling)
```
POST /v3/groups/{id}/upload
Content-Type: application/octet-stream
<binary file data>

GET /v3/groups/{id}/download
GET /v3/groups/{id}/pdf       # PDF report for any group
```

### Threat Actor Profiles (7.12+)
Retrieve via `?fields=threatActorProfile` on Adversary groups. Filter via TQL: `hasThreatActorProfile(mitre_id = "G0016")`.

### AI Insights for Events (7.12+)
Retrieve via `?fields=insights` on Event groups. Returns `insights` (AI summary) and `aiProvider` (source, e.g., Dataminr).

### Intelligence Reviews
Available on Group endpoints via `?fields=intelligenceReview`.

### Event Status (Event groups only)
Possible values: `Needs Review`, `False Positive`, `Confirmed`. Settable via PUT.

---

## 6. TQL (ThreatConnect Query Language)

### Syntax
```
<parameter> <operator> <value>
```
Combine with `AND`, `OR`, and parentheses.

### Operators
| Operator | Usage | Example |
|---|---|---|
| `=`, `!=` | Equals / not equals | `typeName = "Address"` |
| `>`, `>=`, `<`, `<=` | Numeric/date comparison | `threatAssessScore >= 500` |
| `in` | Value in list | `typeName in ("Address", "Host")` |
| `like` | Wildcard match (`%`) | `summary like "%bad%"` |
| `startswith` | Starts with | `techniqueId startswith "T1001"` |
| `contains` | Contains substring | `tag contains "malicious"` |
| `GEQ`, `LEQ` | Date comparison | `caseOpenTime GEQ "2023-02-01"` |

### Escape Characters
| Character | Escape Sequence |
|---|---|
| `'` | `\'` |
| `"` | `\"` |
| `` ` `` | `` \` `` |
| `\` | `\\` |

### Discovering Parameters
```
OPTIONS /v3/<type>/tql
```
Returns all valid filter parameters with types and descriptions.

### Common Queries
```
# Indicators by type
?tql=typeName in ("Address", "Host")

# Indicators by ThreatAssess score
?tql=threatAssessScore >= 500

# Indicators updated today with high score
?tql=threatAssessLastUpdated > "TODAY()" and threatAssessScore >= 700

# Indicators by enrichment score (AbuseIPDB)
?tql=abuseIpdbConfidenceScore >= 50

# Groups by type and tag
?tql=typeName in ("Adversary") and tag in ("APT29")

# Cases by date range
?tql=caseOpenTime GEQ "2025-01-01" and caseOpenTime LEQ "2025-03-31"

# ATT&CK tags by technique ID
?tql=techniqueId startswith "T1059"

# Indicators with specific group association
?tql=hasGroup(typeName = "Campaign" and name = "Operation Nightfall")

# Threat Actor Profiles (7.12+)
?tql=hasThreatActorProfile(mitre_id = "G0016")

# Indicators by owner with active status and high confidence
?tql=ownerName = "My Organization" and active = true and confidence >= 70 and rating >= 4.0
```

### TQL Date Functions
| Function | Description |
|---|---|
| `"TODAY()"` | Start of today (midnight) |
| `"NOW()"` | Current timestamp |
| `"2025-01-15"` | Specific date |
| `"2025-01-15T14:30:00Z"` | Specific datetime (ISO 8601) |

### AI-Powered TQL Generator (7.8+ Beta)
Generate TQL from plain English. Enable: System Settings > Feature Flags > `aiTqlGenerationEnabled`.

---

## 7. Pagination

| Parameter | Default | Max | Description |
|---|---|---|---|
| `resultStart` | 0 | (none) | Starting index |
| `resultLimit` | 100 | 10,000 | Items per page |

```
GET /v3/indicators?resultStart=0&resultLimit=100
GET /v3/indicators?resultStart=100&resultLimit=100
```

Response includes `next` and `prev` URLs. Use `count=true` to get total items.

**Warning:** Do not cache pagination indices. Dataset changes over time cause skipped or duplicated objects.

---

## 8. Associations

### v3 Pattern (nested in POST/PUT)
```json
// Associate indicator to group
PUT /v3/indicators/{id}
{"associatedGroups": {"data": [{"id": 67890}]}}

// Associate group to indicator
PUT /v3/groups/{id}
{"associatedIndicators": {"data": [{"id": 12345}]}}

// Create indicator with association in one call
POST /v3/indicators
{
  "type": "Address",
  "ip": "192.168.1.100",
  "associatedGroups": {"data": [{"name": "Bad Campaign", "type": "Campaign"}]}
}
```

### Association Types
- Indicators: Groups, Cases, Artifacts, other Indicators (custom), Victim Assets
- Groups: Groups, Indicators, Cases, Victim Assets, IRs
- Cases: Cases, Indicators, Groups, IRs

### Custom Indicator-to-Indicator Associations
```
GET /v3/indicators/{id}/associatedIndicators
PUT /v3/indicators/{id}
{"associatedIndicators": {"data": [{"id": 12345}, {"id": 67890}]}}
```

---

## 9. Enrichment

### Available Built-in Services
DomainTools, Farsight Security, RiskIQ, Shodan, urlscan.io, VirusTotal, AbuseIPDB (7.8+).

### Enrich an Indicator
```
POST /v3/indicators/enrich
{"type": "Address", "ip": "192.168.1.100"}
```

### Include Enrichment in Responses
```
GET /v3/indicators/{id}?fields=enrichment
```

### Filter by Enrichment Data
```
?tql=abuseIpdbConfidenceScore >= 50
?tql=whoisActive = true
```

---

## 10. Exclusion Lists

```json
// Create
POST /v3/exclusionLists
{
  "name": "CDN IPs",
  "description": "Known CDN infrastructure",
  "type": "Address",
  "entries": {"data": ["13.32.0.0/15", "52.84.0.0/15"]}
}

// Retrieve
GET /v3/exclusionLists
GET /v3/exclusionLists/{id}

// Update
PUT /v3/exclusionLists/{id}

// Delete
DELETE /v3/exclusionLists/{id}
```

---

## 11. Batch API (v2)

For bulk indicator and group import. Endpoint: `/v2/batch`

### Workflow
1. Create batch job: `POST /v2/batch` with configuration
2. Upload data: `POST /v2/batch/{id}` with JSON payload
3. Poll status: `GET /v2/batch/{id}`
4. Review results: Check for per-record errors

### Versions
- V1 Batch API (legacy)
- V2 Batch API (current)

### Notes
- Indicators are unique per owner
- Existing indicators won't re-create (deduplicated)
- Supports bulk creation of Indicators and Groups with attributes, tags, and associations
- Prerequisites must be met before use (check version-specific docs)

### Bulk Indicator Reports (v2)
```
POST /v2/indicators/bulk/<reportType>
GET /v2/indicators/bulk/json?modifiedSince=2025-01-01T00:00:00Z
```

---

## 12. TAXII Services

### TAXII 2.1
```
GET /taxii2/                                          # Discovery
GET /taxii2/<api-root>/                               # API Root
GET /taxii2/<api-root>/collections/                   # List collections
GET /taxii2/<api-root>/collections/{id}/objects/      # Objects in collection
```

Authentication: Same as REST API (Token or HMAC). Required header: `Accept: application/taxii+json;version=2.1`

### TAXII 1.x (Legacy)
Discovery, Collection Management, and Poll services at `/taxii/` endpoints.

See `integrations.md` for inbound/outbound feed configuration and STIX mapping.

---

## 13. Owner Context

### Default Behavior
- **v3:** Operations default to your Organization
- **Override:** `?owner=<ownerName>` query parameter
- **In POST body:** `ownerId` or `ownerName` field

### Verify Accessible Owners
```
GET /v2/owners
GET /v3/security/owners
```

### Permissions by Role
| Role | API Access |
|---|---|
| Api User | All v2/v3 endpoints except TC Exchange admin |
| Exchange Admin | All endpoints including TC Exchange admin |
| Organization Administrator | Required for Case Management CRUD |
| Read Only User | GET only; can update `common` fields if `readOnlyUserUpdatesAllowed` system setting is enabled |

---

## 14. HTTP Status Codes

| Code | Meaning | Common Causes |
|---|---|---|
| 200 | Success | |
| 201 | Created | Object created |
| 400 | Bad Request | Malformed body, invalid field values, missing required fields, indicator format errors. Check `message` field. |
| 401 | Unauthorized | Expired token, insufficient permissions, URL encoding mismatch in HMAC signature |
| 403 | Forbidden | Wrong auth credentials, owner doesn't exist, no access to owner, HMAC signature mismatch |
| 404 | Not Found | Object ID doesn't exist, wrong endpoint path |
| 500 | Internal Server Error | Server-side issue; retry, then contact support |
| 503 | Service Unavailable | Instance not licensed for API |

---

## 15. Troubleshooting

### Auth Errors
| Error Message | Cause | Fix |
|---|---|---|
| "Signature Data Did Not Match Expected Result" | HMAC signature wrong | Verify path matches request exactly, HTTP method uppercase, using HMAC-SHA256, result is Base64 |
| "Timestamp Out of Acceptable Time Range" | Clock drift > 5 min | Sync NTP; verify with `date +%s` |
| "Access Denied" | Wrong credentials or no access to owner | Verify Access ID and Secret Key; check owner access |
| "Unauthorized" | Expired or old token | Regenerate token in Org Settings |

### Common Failures
| Symptom | Likely Cause | Fix |
|---|---|---|
| Empty results | Wrong owner context | Add `?owner=` parameter; verify with `GET /v2/owners` |
| 400 on indicator creation | Invalid format | Check indicator formatting rules in Section 4 |
| TQL query timeout | Query too complex or timeout too low | Check Custom TQL Timeout setting; simplify query |
| 401 on TQL query | URL encoding mismatch | Some tools need manual encoding; verify encoded URL matches signature |
| Batch import fails | Prerequisites not met | Check Batch API prerequisites; review per-record errors |
| `description` field ignored | Read-only field | Use `attributes` field with type `"Description"` |
| Pagination returns duplicates | Dataset changed between requests | Expected behavior; don't cache indices |
| v3 field not found | Using wrong field name | Use `OPTIONS /v3/<type>` to discover exact field names |
| Inactive indicators missing | API excludes inactive by default | Check Indicator Status; use `active = false` in TQL to find inactive |

### TcEx App Errors
- `Can't find '__main__' module in '.'`: Missing `__main__.py` in app root. Required for app entry point.

---

## 16. v2 API Notes (Legacy)

Still supported for: Groups, Indicators, Tags, Tasks, Victims, Associations, Attributes, Batch API, Custom Metrics, Notifications, Owners, Playbooks, Security Labels.

**Pagination (v2):** `?resultStart=0&resultLimit=100`

**Specifying owner (v2):** `?owner=<ownerName>` query parameter (case-sensitive name).

**Recently Deleted Indicators:**
```
GET /v2/indicators/deleted?modifiedSince=2025-01-01T00:00:00Z
```

**Private Indicators (v2):** Set `privateFlag` field on creation/update; affects visibility per owner role.

---

## 17. Documentation URLs

| Resource | URL |
|---|---|
| v3 API Docs | https://docs.threatconnect.com/en/latest/rest_api/rest_api.html#v3-api |
| v3 Quick Start | https://docs.threatconnect.com/en/latest/rest_api/quick_start.html |
| v3 Indicators | https://docs.threatconnect.com/en/latest/rest_api/v3/indicators/indicators.html |
| v3 Groups | https://docs.threatconnect.com/en/latest/rest_api/v3/groups/groups.html |
| TQL Filtering | https://docs.threatconnect.com/en/latest/rest_api/v3/filter_results.html |
| HTTP Status Codes | https://docs.threatconnect.com/en/latest/rest_api/v3/http_status_codes.html |
| Pagination | https://docs.threatconnect.com/en/latest/rest_api/v3/enable_pagination.html |
| Batch API | https://docs.threatconnect.com/en/latest/rest_api/v2/batch_api/batch_api.html |
| TAXII 2.1 | https://docs.threatconnect.com/en/latest/rest_api/taxii/taxii_2.1.html |
| Common Errors | https://docs.threatconnect.com/en/latest/common_errors.html |
| TQL KB | https://knowledge.threatconnect.com/docs/threatconnect-query-language-tql |
| OpenAPI (self-serve) | `GET /v3/openApi` |
| Postman Config | https://docs.threatconnect.com/en/latest/rest_api/v3/postman_config.html |
