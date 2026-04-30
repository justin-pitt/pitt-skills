# Identity Threat - Identity Analytics, ITM, Cloud Identity Engine

UEBA layer of XSIAM. Three components, all separately enabled, with sharp dependency chains. The platform's `get_risky_users` / `get_risky_hosts` / `get_risk_score` API endpoints surface scores generated here - but the inputs and detections behind them aren't obvious without this reference.

## Component map

| Component | Add-on? | What it does |
|---|---|---|
| **Cloud Identity Engine (CIE)** | Free | Pulls AD / Okta directory data into XSIAM. Provides user/host attributes for analytics, policy scope, and asset enrichment. (admin doc p. 6150-6170) |
| **Cortex XSIAM - Analytics Engine** | Included | Builds endpoint-data baseline; raises Analytics + Analytics BIOC alerts on anomalies. Needs ≥30 endpoints over 2 weeks of EDR/network logs, OR cloud audit logs ≥5 days. Baseline takes up to 3 hours after enable. (admin doc p. 5922-5945) |
| **Identity Analytics (IA)** | Included | Enriches user-based Analytics alerts with directory + activity context. Toggle in *Settings → Configurations → Cortex XSIAM - Analytics → Featured in Analytics → Enable Identity Analytics*. (admin doc p. 21115) |
| **Identity Threat Module (ITM)** | **Add-on (paid)** | Asset Role classification, Behavioral Analytics tab, Risk Management dashboard, User/Host Risk Views, honey user roles, asset scores. (admin doc p. 21115-21130, 22865, 23700-23800) |

**Dependency chain**: CIE → Analytics Engine → Identity Analytics → ITM. You can't skip steps; ITM features fail silently or hide UI when prereqs aren't enabled.

## Cloud Identity Engine (CIE)

- Optional but required for IA/ITM. Read-only access to your AD/Okta. Activates in the same region as the XSIAM tenant.
- Provides identity for: endpoint group rules, policy scope, alert enrichment (user attributes, group membership, OU, role), authentication (SAML 2.0 IdP profile).
- Setup: Settings → Configurations → Identity → Cloud Identity Engine. Connector lives in Palo Alto cloud, not on-prem.
- **Disconnecting CIE breaks endpoint groups + policy rules that reference AD attributes** (admin doc p. 4813). Plan accordingly.

## Identity Analytics

What you see in alerts after enabling:
- "Identity Analytics" tag in Alerts table → Alert Name and BIOC Rules table → Name (admin doc p. 21115)
- In Analytics Alert View, selecting the User node shows: AD group, OU, role, logins, hosts, alerts, process executions associated with the user
- Risky users/hosts pages populate (via the `/risky_users`, `/risky_hosts`, and `/risk_score` API endpoints)

## Identity Threat Module (paid add-on)

Gated UI features; if a user reports "I don't see the Behavioral Analytics tab" or "Asset Roles is missing", check the ITM license first.

- **Asset Roles** (User + Host) - auto-classified from constant analysis. Editable. Drives risk weighting. (admin doc p. 23700-23756)
- **Risk Management dashboard** - predefined dashboard summarizing org-wide risk posture
- **User Risk View / Host Risk View** - score trend timeline, notable events, peer comparison, hidden-threat surfacing. ITM-only.
- **Behavioral Analytics tab in Alert Panel** - baseline-vs-deviation context for triage. ITM-only.
- **Asset Scores page** (admin doc p. 22865) and **CVE analysis in Host Risk View** (admin doc p. 18659, 22612) - ITM-only.
- **Honey user role** (admin doc p. 23792-23801) - decoy account flagged at the role level so any access attempt fires high-fidelity detection. **Manually configured per user** - no auto-provisioning. Pair with a deceptive AD object.

## XQL surface

`identity_analytics` rows aren't a top-level dataset in default XSIAM tenants - they're surfaced via the alerts dataset (`alert_source` / `alert_category` filters) and the Analytics-specific BIOC dataset. For investigating risky users from XQL, prefer:

```xql
dataset = alerts
| filter alert_source contains "Identity Analytics"
| fields user_name, alert_name, severity, host_name, _time
| sort desc _time | limit 100
```

Cross-correlate with CIE attributes via the `xdm.source.user.*` and `xdm.target.user.*` XDM fields - those are populated downstream of CIE.

## API surface

Read-only endpoints:
- `/risky_users` - ITM/IA-driven user risk scores
- `/risky_hosts` - host risk scores
- `/risk_score` - single asset lookup

No write endpoints exposed for direct score override; risk scoring is computed and is intentionally not externally settable.

## Operational gotchas

- **Baseline window**: 3-hour Analytics baseline build after enable. Don't expect alerts immediately.
- **CIE region pin**: tenant region must match CIE region - late-stage realization breaks setup.
- **ITM is gated by license**: missing dashboards aren't a bug; verify add-on activation.
- **Honey users are manual**: no automation. Document them in the case-mgmt runbook so on-call doesn't dismiss legitimate-looking probes as benign.
- **Alert tag silently disappears** if Identity Analytics is disabled mid-investigation. Tags don't backfill on re-enable.
- **Risky-user score halt**: if CIE is disconnected, scores freeze rather than reset to zero. UI gives no warning.

## Cross-reference

- `case-ops.md` - analyst workflow on user-based alerts
- `detection-engineering.md` - ABIOC rules feeding Identity Analytics
- `data-pipeline.md` - XDM identity fields and DHCP-log ingestion (improves Analytics)
