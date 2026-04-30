# Attack Surface Management (ASM) Reference

> **Add-on required.** ASM is a separately licensed add-on for XSIAM. All `Assets → Asset Inventory → All External Services`, `External IP Address Ranges`, websites, attack surface rules, and Threat Response Center pages return empty/forbidden without it (admin doc p. 461, 488, 491).

## What ASM Is - and Isn't

ASM is **outside-in** discovery: it scans the public IPv4/IPv6 internet, attributes assets to your org, and generates alerts on exposure-class risks (open RDP, expired cert, vulnerable OpenSSH, externally inferred CVE). It does **not** touch endpoint telemetry, behavioral analytics, or user UEBA - those are EDR / Cortex Analytics. Cross-link: `detection-engineering.md` for correlation rules; `case-ops.md` for the alert→case pipeline that ASM alerts feed into.

| Engine | Vantage | Data | Output |
|---|---|---|---|
| EDR / XDR agent | Inside the host | `xdr_data` | Behavioral alerts, causality |
| Analytics / UEBA | Inside the network | logs, identity | Anomaly alerts |
| **ASM (Xpanse)** | **Outside the perimeter** | **Internet scans, registries, certs, DNS** | **Exposure alerts, ASM rules** |

ASM alerts fire on attack surface rules (definitions managed by XSIAM, not user-authored like BIOCs). 800+ rules ship out of the box (admin doc p. 461). Website rules are **disabled by default** - enable via `Rules → Attack Surface Rules`, filter `ASM Alert Categories = Web Security Assessments`, right-click → Enable (admin doc p. 468).

## Asset Model

| Object | Definition | UI path |
|---|---|---|
| **External IP range** | IP range attributed to org via ARIN/RIPE/APNIC/LACNIC/AFRINIC registry, ASN/BGP, cert, DNS, or self-provided | `Assets → Network Configuration → IP Address Ranges → External` |
| **External service** | Server at `IP:port` or `domain:port` answering an application protocol (DNS, RDP, HTTP, SSH, etc.) | `Assets → Asset Inventory → All External Services` |
| **Website** | Content + tech stack served over HTTP(S); one website may be backed by many HTTP services | `Assets → Asset Inventory → Websites` |
| **Domain / Cert / Unassociated responsive IP** | Discovered external assets | `Assets → All Assets`, `Specific Assets` |
| **Attack surface rule** | Risk definition that fires alerts when matched against discovered assets | `Rules → Attack Surface Rules` |

Service ≠ website: `external services` are network listeners (one HTTP server). `websites` are content/tech-stack views - a single on-prem HTTP service can serve hundreds of websites; a cloud HTTP service typically serves one (admin doc p. 465).

## Discovery / Scanning

XSIAM-Xpanse runs scans from its own attributed infrastructure. Customer does nothing; results show up in inventory.

| Scan | Cadence | Coverage |
|---|---|---|
| Global Base | 2x/week | ~250 most-common ports across all IPv4 |
| Global Extended | low background | remaining ~65k ports |
| KAM Base (opt-in) | daily | ~300 ports on customer-attributed assets |
| KAM Extended (opt-in) | weekly | ~2800 additional ports on attributed assets |
| Monitoring | daily | all responsive services |
| Attack Surface Testing | daily | configured target services |

(admin doc p. 462-463)

**Attribution methods**: IP registration (regional registries, refreshed ~biweekly), ASN/BGP advertisement, certificate, DNS, self-provided. Cloud assets attribute via domain/cert observation, not IP registration; CSP integrations (AWS/Azure/GCP) feed cloud asset data directly (admin doc p. 462).

**KAM gotcha**: opt-in only, requires Customer Success engagement. Uses heavier payloads than global scans - validate IP space first and confirm IPS/IDS/firewalls won't block scanner IPs (admin doc p. 463).

**GeoIP**: drives compliance checks (data residency) and routes notifications by location; some XSIAM scanner IPs register as US even when scanning from elsewhere - false-positive driver in third-party GeoIP DBs (admin doc p. 463, 681).

## Externally Inferred CVEs

CVE inference works by matching scanner-observed product+version against NVD. Two confidence tiers:

- **High** - both service banner and NVD entry have precise version info
- **Medium** - partial version match; one side has extra characters

Every asset/service with an inferred CVE gets an **Externally Inferred Vulnerability Score** = highest CVSS v3 (or v2 fallback) among its inferred CVEs (admin doc p. 469).

> **Critical caveat from the doc:** "An externally inferred CVE *might* impact your service or asset, but additional investigation is required to confirm that the CVE is actually present." Don't ticket on inferred CVE alone - pair with **Attack Surface Testing** (below) for confirmed-vulnerable verdicts.

View: `Assets → Asset Inventory → All Assets / All External Services` → row → details panel → `Detailed view` next to each CVE for CVSS v3/v2, banner string, and NVD link.

## Attack Surface Testing

Optional benign-exploit confirmation. Distinct from passive CVE inference: ASM Testing **actively probes** directly-discovered services (definitively attributed to your org) on a daily cadence and produces `Confirmed Vulnerable` / `Confirmed Not Vulnerable` verdicts on the service record (admin doc p. 488-490).

Setup (one-time):
1. Role permission: `Vulnerability Testing` edit (`Settings → Configurations → Access Management → Roles → Components → Incident Response → Detections`)
2. `Detection & Threat Intel → Attack Surface → Attack Surface Testing` → accept EULA (one-time)
3. `Settings → Configurations → Attack Surface → Attack Surface Testing` → choose `All Targets` or `Selected Targets`

Operational fields on `All External Services`: `Confirmed Vulnerabilities`, `Confirmed Not Vulnerable`, `Vulnerability Test Result`. Per-service drill-down shows 14-day test history and the evidence payload.

**Pitfall**: source-IP allow-listing is recommended on detection tooling (suppress noise) but **not** on perimeter security controls - the whole point is testing from an attacker's network position (admin doc p. 490).

## Threat Response Center

Single pane for emergent global threat events / zero-days. `Detection → Attack Surface → Threat Response Center`. Each event surfaces: severity, related CVEs, affected software+versions, related attack surface rules (with on/off state), active alerts/incidents per business unit, and Xpanse-curated remediation guidance.

RBAC: requires **Attack Surface Rules** permission under `Detection & Threat Intel` component (admin doc p. 491).

Inclusion criteria for an event: unpatched / KEV-listed / unauth-RCE-over-internet / public PoC / widespread / CVSS ≥ 9 / geopolitical relevance (admin doc p. 491). When a new event is added, check whether your tenant is generating alerts on it before declaring "not affected" - most events ship with associated attack surface rules that may be disabled.

## Automation: ASM Alert Playbook

The `Cortex ASM - ASM Alert` playbook (Marketplace content pack: **Cortex Attack Surface Management**) does enrichment + remediation on every ASM alert. Enable it via:

1. Update the Cortex ASM content pack (Marketplace)
2. Generate API key (Standard, role with ASM+VM edit perms; Instance Administrator works)
3. Add the **Cortex Attack Surface Management** integration instance - `Server URL` is your tenant URL with `api-` prepended (e.g., `https://api-tenant.xdr.us.paloaltonetworks.com`)
4. `Incident Response → Case Configuration → Playbook Triggers → View Recommendations` → add the **ASM** trigger

(admin doc p. 473-475)

**Auto-remediation methods** (for a fixed list of attack surface rules including OpenSSH, RDP, SMB, MongoDB, Telnet, Elasticsearch, etc.):

| Method | Requires |
|---|---|
| **Restrict port access** | Asset on AWS EC2 / GCE / Azure VM (RW credentials) or on-prem behind PAN NGFW; non-prod (tag or Xpanse `Development Environment` classification); ≥1 service owner identified |
| **Patch vulnerable software** | AWS EC2 Linux Ubuntu only, SSM agent active; non-prod; ≥1 owner |
| **Isolate endpoint from network** | Asset NOT on cloud / NGFW-managed; managed by XSIAM Endpoint Security or Cortex XDR Prevent/Pro; non-prod; ≥1 owner |

(admin doc p. 476-477) - `BypassDevCheck` playbook input disables the non-prod gate.

**Remediation Confirmation Scan (RCS)**: subplaybook re-runs the original discovery payload after remediation to confirm the risk is gone. ~4+ hours per scan. Manual trigger via the `RCS Scan Start` / `RCS Scan Status` buttons in the alert war room (admin doc p. 487).

## Alert Resolution Status

ASM alert resolution is either **terminal** or **reopenable**. Terminal statuses (alert won't reopen even if XSIAM keeps observing the issue):

- `Resolved - Duplicate Alert`
- `Resolved - False Positive`
- `Resolved - True Positive`
- `Resolved - Security Testing`

Anything else is reopenable - XSIAM will reopen the alert on next observation (admin doc p. 487-488). Pick deliberately when bulk-resolving via API.

## API Operations

Read endpoints:

| Endpoint | Returns |
|---|---|
| `/asm/get_external_services` | Inventory of external services (paged) |
| `/asm/get_external_service` | Single-service detail (incl. inferred CVEs) |
| `/asm/get_external_websites` | Inventory of websites |
| `/asm/get_external_website` | Single website with security-best-practices results |
| `/asm/get_external_ip_ranges` | Attributed external IP ranges |
| `/asm/get_external_ip_range` | Single range with registration data |
| `/asm/get_attack_surface_rules` | All rules; filter to find disabled categories (e.g., `Web Security Assessments`) |
| `/asm/get_assessment_profile_results` | Attack Surface Test results by profile |
| `/asm/get_website_last_assessment` | Most-recent web assessment for a site |
| `/vulnerabilities/get_vulnerabilities` / `/vulnerabilities/get_vulnerability_tests` | CVE/test inventory (intersects with ASM) |

Write endpoints:

| Endpoint | Use |
|---|---|
| `/asm/upload_asm_data` | Submit asset upload request (domain or IPv4 range; up to 500 assets per request; CSV-shaped fields). Pending → Accepted/Rejected within 5 days. **Instance Administrator role required.** |
| `/asm/remove_asm_data` | Submit asset removal (domain, cert, IPv4 range - IPv6 not supported). Removes related alerts, incidents, services within 24h. Reversible via Undo only - you cannot re-upload a removed asset directly. |
| `/vulnerabilities/bulk_update_vulnerability_tests` | Enable/disable AS Tests at scale instead of clicking through `Policies and Rules → Attack Surface Testing` |

## Common Pitfalls

1. **Inferred CVE ≠ confirmed vulnerable.** Don't escalate on inferred CVEs without an Attack Surface Test result or manual proof. Doc explicitly hedges.
2. **Website rules ship disabled.** New tenants see zero website alerts until you enable the `Web Security Assessments` category.
3. **Asset upload/remove is asymmetric and slow.** Uploads take up to 5 days for review and can be rejected (cloud IPs, for-sale domains, unrelated registration). Removals take up to 24h. You cannot re-upload a removed asset - must `Undo Asset Removal`.
4. **IPv6 ranges and certificates can't be uploaded.** Cert removal works; cert upload doesn't.
5. **Removing an asset removes its alerts and incidents.** This is destructive across the case surface, not just the inventory.
6. **The Cortex ASM integration `Server URL` needs the `api-` prefix.** `https://tenant...` won't work; must be `https://api-tenant...`. Same prefix rule as direct PAPI calls.
7. **KAM is opt-in and not free of side effects.** Heavier payloads can trigger your own IPS. Don't enable without coordinating with network/security tooling owners.
8. **Auto-remediation gates on non-prod.** Production assets won't be auto-fixed by the playbook unless `BypassDevCheck=true` - review the playbook input before assuming a remediation will fire.
9. **Resolution status is sticky for terminal codes.** Closing an alert as `True Positive` prevents reopens even if the exposure persists. For tracking-only closures, pick a reopenable status.
10. **RBAC for Threat Response Center is `Attack Surface Rules` permission**, not a TRC-specific perm - easy to miss when handing out scoped roles.
