# ThreatConnect Administration Reference

Reference for ThreatConnect administration: roles and permissions, ThreatAssess and CAL configuration, feed management and quality metrics, indicator deprecation, dashboards and visualization, system settings, and recent platform features.

## 1. Roles and Permissions

### System Roles
| Role | Description |
|---|---|
| **Administrator** (System Admin) | Full access to all System and Organization settings. Can configure system-wide settings, manage users, install apps, configure feeds. |
| **Operations Administrator** | Read-only System access; full Organization access |
| **Accounts Administrator** | Read-only access; can create/modify Organizations |
| **Community Leader** | Read-only; views all Organizations |
| **Api User** | All v2/v3 endpoints except TC Exchange admin |
| **Exchange Admin** | All endpoints including TC Exchange admin |
| **Super User** | Full data-level access across all Organizations on multitenant instances |

### Organization Roles
| Role | Permissions |
|---|---|
| **Organization Administrator** | Full Org access; manage users, settings, Playbooks |
| **Sharing User** | Standard User + ability to share data |
| **Standard User** | Standard read/write access to Org data |
| **App Developer** | Standard User + App Builder access |
| **Read Only User** | View only; can update `common` API fields if `readOnlyUserUpdatesAllowed` setting is on |
| **Read Only Commenter** | Read Only + ability to add comments |

### Community Roles
| Role | Permissions |
|---|---|
| **Director** | Full Community admin; can delete |
| **Editor** | Create, modify, delete data; manage members |
| **Contributor** | Create and modify data |
| **Commenter** | Read + add comments |
| **User** | Read only |
| **Subscriber** | Limited read access |
| **Banned** | No access |

### Custom Owner Roles
System Administrators can create custom Owner Roles for fine-grained permissions beyond out-of-the-box roles.

---

## 2. ThreatAssess Configuration

### How ThreatAssess Calculates Scores
ThreatAssess produces a single actionable score (0-1000) per indicator from:

1. **Threat Rating**: Weighted average of the indicator's Threat Rating (0-5 skulls) across all owners in the instance
2. **Confidence Rating**: Weighted average of Confidence Rating (0-100%) across all owners
3. **CAL Score**: CAL's reputation score (0-1000) from anonymized crowdsourced data
4. **False Positive status**: Recent FP reports lower the score
5. **Observation data**: Recent observations in actual network traffic may raise or lower the score

### Assessment Levels (admin-configurable thresholds)
| Level | Default Range | Meaning |
|---|---|---|
| Low | 0-200 | Minimal risk |
| Medium | 201-500 | Moderate risk; warrants monitoring |
| High | 501-800 | Significant risk; prioritize |
| Critical | 801-1000 | Immediate threat |

### Configuration (System Admin)
**Path:** Settings > System Settings > ThreatAssess

Configurable parameters:
- **CAL weighting**: How heavily CAL's reputation factors into ThreatAssess
  - Heavy weight: Best for teams bootstrapping their intel program
  - Zero weight: For mature orgs relying entirely on analyst assessments
- **False positive recency window**: Default 7 days; configurable
- **Assessment thresholds**: Customize Low/Medium/High/Critical score ranges
- **Excluded sources**: Sources to exclude from ThreatAssess calculation

### ThreatAssess Impact Factors
Visible on Indicator Details screen:
- **Recent False Positive Reported**: Checkmark = recently reported (lowers score); circle with line = not recently reported
- **Impacted by Recent Observation**: Whether recent observations raised/lowered the score
- **CAL Influence**: How much CAL contributed to the current score
- **Source Threat Rating**: Per-owner Threat Rating contribution
- **Source Confidence Rating**: Per-owner Confidence Rating contribution

### Manual Recalculation (7.10+)
**Recalculate Scoring** button on indicator Details screen for instant refresh after updating Threat or Confidence Ratings. Avoids waiting for scheduled ThreatAssess Monitor run.

### Operational Thresholds (CDW Policy)
- **Block at enforcement points**: ThreatAssess >= 700 AND Confidence >= 70
- **Critical severity + score 700+**: Auto-block across Active Defense Grid
- **SOC alert threshold**: ThreatAssess >= 500 (configurable)

---

## 3. Threat Rating and Confidence Rating Standardization

### Threat Rating Scale (0-5 skulls)
| Skulls | Standard | Example |
|---|---|---|
| 0 | Unrated/Unknown | Newly ingested, no analysis |
| 1 | Suspicious | Anomalous but unconfirmed |
| 2 | Low Threat | Commodity malware, opportunistic scanning |
| 3 | Moderate Threat | Known campaigns, capable adversary, broad targeting |
| 4 | High Threat | Targeted attack, skilled adversary with persistence |
| 5 | Critical Threat | Active, confirmed, high-impact, immediate response |

### Confidence Rating Scale (0-100%)
| Range | Level | Meaning |
|---|---|---|
| 90-100 | Confirmed | Verified by independent sources or direct analysis |
| 70-89 | Probable | Logical, consistent with other info, limited contradictions |
| 50-69 | Possible | Reasonable but not confirmed; some contradictions exist |
| 25-49 | Doubtful | Questionable reliability; significant gaps |
| 0-24 | Improbable | Unreliable; awareness only, not actionable |

---

## 4. CAL (Collective Analytics Layer)

### What CAL Provides
CAL aggregates anonymized data from all participating ThreatConnect instances plus OSINT sources. Provides three insight types:

**Reputation:**
- CAL Score (0-1000) on the same scale as ThreatAssess
- Used as input into ThreatAssess (configurable weight)

**Classifiers:**
- 103 classifiers providing vocabulary for indicator data points
- NLP-derived labels (e.g., "phishing", "C2", "malware-family-X")

**Contextual Fields:**
- Feed Information (which OSINT feeds reported the indicator)
- File Hash Information (for File indicators)
- Geolocation/Provider Information (for Address indicators)
- Observations / Impressions / False Positives across all CAL instances
- Quad9 attempted resolution data

### Enabling CAL
**Path:** System Settings > Indicators > Enrichment Tools

Requires System Admin role. Once enabled, CAL data appears in:
- Indicator Details drawer
- New Indicator Details screen (ThreatAssess & CAL section)
- Legacy Indicator Details screen
- Workflow Case Artifacts card (CAL column)
- Threat Graph (Pivot with CAL)

### CAL Status (Indicator Lifecycle)
CAL determines whether an indicator is currently considered an IOC:
- **Active**: Currently considered an IOC
- **Inactive**: Not currently an IOC; kept for historical accuracy

CAL evaluates: indicator type and metadata, ThreatAssess score, CAL Classifiers, feed activity, observations/impressions/false positives over time.

### CAL Status Lock
Per-indicator setting controlling whether CAL can change the indicator's status:
- **CAL Status Lock OFF (recommended for most orgs)**: CAL automatically manages status
- **CAL Status Lock ON**: Only local analyst actions change status

**Manage from Details Screen:**
1. Navigate to Indicator Details
2. Click ⋯ menu
3. Select **Enable CAL Status Lock** or **Disable CAL Status Lock**

### CAL ATL (Automated Threat Library)
Source aggregating security blog articles, parsing IOCs, malware families, threat actors. Provides finished intelligence Reports with AI Insights summaries (when available).

### CAL Impact Factors
Displayed on Details screen showing why CAL assigned its current score:
- Indicator presence in malicious data sources
- Indicator presence in benign data sources (lowers score)
- Relationships to other known good/bad indicators
- Aggregated false positive reports
- Aggregated observation counts

### Pivot with CAL
Threat Graph feature: explore relationships between indicators within CAL's dataset (vs only your owners' data). Useful for finding adversary infrastructure not yet in your TC instance.

---

## 5. Indicator Deprecation

### Deprecation Monitor
ThreatConnect runs an Indicator Deprecation Monitor on a schedule that ages out indicators per configured policies.

### Configuration (System Admin)
**Setting:** `threatDeprecationIntervalCount`

Determines the number of indicators deprecated per Monitor run.
- **Increasing the value**: Helps catch up if instance is severely behind
- **Setting too high**: May prevent the Monitor from finishing in a single execution, causing it to skip the next run and negate the benefit

**Other deprecation settings:**
- **Deprecation interval**: How often the Monitor runs
- **Per-source deprecation rules**: Different aging rules per Source
- **Indicator type deprecation rules**: Different rules per Indicator type

### Deprecation Lifecycle
1. Indicator ingested
2. Aged based on `dateAdded` and configured thresholds
3. Deprecation Monitor identifies candidates
4. Status set to Inactive (or deleted, depending on config)
5. Excluded from API responses (Inactive indicators not returned by default)

### CAL Auto-Deprecation
When CAL Status Lock is OFF, CAL automatically sets indicators to Inactive based on its own analytics (feed activity, observations, classifiers). Reduces noise from stale indicators.

---

## 6. Indicator Exclusion Lists

### Purpose
Prevent import of known-benign indicators that would generate noise.

### Common Use Cases
- Known-good infrastructure (CDN IPs, company domains, cloud provider ranges)
- Internal IP ranges
- Common benign hashes (OS files, known software)
- Trusted email domains

### Management (UI)
**Path:** Settings > Org Settings > Indicator Exclusion Lists

Create one list per indicator type. Lists can include:
- Specific values (e.g., specific IPs)
- CIDR ranges (for Address type)
- Regex patterns (for Host, URL types)

### Management (API)
See `api.md` Section 10. Endpoint: `/v3/exclusionLists`.

### Best Practices
- Maintain proactively; review quarterly
- Align with downstream alert exclusion lists (e.g., XSIAM/SIEM exclusions)
- Document why each entry is excluded
- Tag organizational owners for accountability

---

## 7. Feed Management and Metrics

### Feed Sources
ThreatConnect ingests from:
- **Built-in CAL feeds** (52+ active OSINT feeds)
- **TAXII inbound feeds** (configured manually)
- **Commercial feeds via integrations** (Recorded Future, Intel 471, Flashpoint Ignite, Dataminr, etc.)
- **Custom feeds** (via TcEx Job Apps or Service Apps)

### Feed Activation/Deactivation
**Path (System Admin):** Settings > TC Exchange Settings > Feeds tab

For each feed:
- **Name** and **Description**
- **Reliability Rating**: Letter grade A+ to F (CAL-derived)
- **Activate/Deactivate** toggle
- Per-feed metrics

### Feed Quality Metrics (CAL-derived)

| Metric | What It Measures |
|---|---|
| **Reliability Rating** | Letter grade A+ (best) to F (worst). Derived from false positive rate and other quality factors. Measures likelihood of negatively impactful FPs. |
| **Unique Indicators** | Percentage of indicators in the feed not present in other feeds. Higher = more unique value. |
| **First Reported** | How often the feed is the first to report an indicator that's later observed in other feeds. Measures earliness/scoop value. |
| **Scoring Disposition** | Weighted average of CAL scores for indicators in the feed. Measures how dangerous the feed's content is. |
| **Classifier Coverage** | Percentage of indicators with at least one Classifier applied by CAL. Measures how well analytics qualitatively understand the feed. |
| **Indicator Status Coverage** | Percentage of indicators with a definitive Indicator Status set by CAL. Measures conclusiveness of CAL's analysis. |

### Metric Visualization
Each metric uses a bar chart:
- **Horizontal black line**: Value for this specific feed
- **Vertical orange line**: Target value across all feeds (computed by CAL)
- **Colored bands**: Red (bad), yellow (medium), green (good) ranges

### Operational Use of Feed Metrics

**Identifying redundant feeds:**
Look for low Unique Indicators percentage combined with overlap with higher-reliability feeds. Disable redundant feeds to reduce duplicate IOC-match alerts downstream.

**Identifying high-value feeds:**
High Unique Indicators + High First Reported + good Reliability Rating = feeds providing differentiated, early intelligence. Prioritize these for blocking decisions.

**Identifying noisy feeds:**
Low Reliability Rating + low Classifier Coverage = feed producing FPs without analytical depth. Candidate for deactivation.

**Feed effectiveness for the Active Defense Grid:**
The CISO directive (capability over visibility) means feed value is measured by how often its indicators trigger automated blocking. Track:
- IOC-match alert rate per feed (downstream SIEM metric)
- Block actions triggered per feed
- False positive rate per feed (operational impact)

### Enabling CAL Data Visibility
**Required for feed metrics to populate:**
1. Log in as System Administrator
2. System Settings > Indicators > Enrichment Tools
3. Select **Enable CAL Data** checkbox
4. Save

---

## 8. Data Sharing and Collaboration

### Collaboration Models
- **Within Organization**: Members share by default (per Org role permissions)
- **Across Organizations**: Use Communities or Sources for cross-org sharing
- **External (other instances)**: Use TAXII outbound feeds or TC Exchange Sharing Servers

### Publishing
Process to share data from your Organization to a Community or Source:
1. Open the Indicator/Group
2. Click Publish from the ⋮ menu
3. Select target Community/Source
4. Confirm

API: Use `/v2/groups/{type}/{id}/publish` or include `publish` in v3 update.

### TC Exchange Sharing Servers
For sharing Playbooks between ThreatConnect instances:
1. System Admin configures Sharing Server in System Administration
2. From source instance: ⋮ menu on Playbook > **Share** > select Sharing Server > generate Share Token
3. From target instance: Playbooks screen > Import Shared > paste Share Token

### Security Labels
Designate sensitivity:
- **TLP:RED**: Personal disclosure only
- **TLP:AMBER**: Limited disclosure to participants' organizations
- **TLP:GREEN**: Community-wide, not via public channels
- **TLP:WHITE/CLEAR**: Unlimited disclosure

Apply via API or UI. Use to control sharing decisions and compliance.

---

## 9. Dashboards and Visualization

### Dashboards
Custom views displaying multiple Cards (widgets) on a single screen.

**Card types:**
- **Query Card**: TQL-driven data widget (lists, tables, single metrics)
- **Chart Card**: Visualizations (bar, line, pie, time series)
- **System Card**: Pre-built ThreatConnect widgets (top indicators, recent activity, etc.)
- **External Card**: Custom external content via iframe

### Creating Dashboards
1. Navigate to Dashboards > Create
2. Name the dashboard, set visibility (Private, Org, Community)
3. Add Cards (drag from Card library)
4. Configure each Card
5. Save

### Query Cards (Most Useful for Custom Metrics)
TQL-powered widgets:
- **Single Value**: Count of objects matching TQL (e.g., "Indicators added today")
- **Table**: List view with selected fields
- **Bar Chart**: Aggregated counts grouped by a field
- **Pie Chart**: Proportional counts
- **Time Series**: Trends over time

**Example TQL queries for Query Cards:**
```
# Active high-risk indicators
typeName in ("Address", "Host", "URL") and threatAssessScore >= 700 and active = true

# Indicators added in last 7 days from a specific source
ownerName = "Recorded Future" and dateAdded > "NOW() - 7 DAYS"

# Critical indicators by tag
tag in ("APT29") and threatAssessScore >= 800

# Open Cases with high severity
status = "Open" and severity in ("High", "Critical")
```

### Threat Graph
Graph-based UI for discovering, visualizing, and exploring associations between threat intelligence objects.

**Capabilities:**
- Visualize indicator-to-group associations
- Visualize group-to-group relationships
- **Pivot with CAL**: Explore associations within CAL's dataset (not just your owners)
- Filter graph by indicator type, group type, owner, score thresholds
- Export graph as image or data

### ATT&CK Visualizer
Maps your intelligence coverage against the MITRE ATT&CK Enterprise Matrix.

**Features:**
- Visualize ATT&CK techniques covered by your tags/groups
- Heat map showing technique frequency
- **Risk Quantifier integration**: Display financial impact estimates per technique (requires RQ enabled)
- Filter by group, campaign, adversary
- Export coverage report

**Use cases:**
- Identify gaps in detection coverage
- Communicate intel coverage to leadership
- Map detection rules to ATT&CK techniques
- Prioritize controls based on financial impact

### Intelligence Reports
Generated reports combining multiple data points:
- PDF export of Group details
- Executive summary reports
- Custom report templates with chart and table sections
- Scheduled automated report generation via Playbooks

---

## 10. Risk Quantifier (RQ)

ThreatConnect's cyber risk quantification module.

### ATT&CK RQ Financial Impact
Calculates potential financial impact of attacks by MITRE ATT&CK technique:
- Leverages 40+ years of loss data (insurance claims, 10-K filings, proprietary research)
- Customized by industry sector and gross revenue
- Available in ATT&CK Visualizer

### Enabling RQ
1. **System level (System Admin):** System Settings > Feature Flags > `financialImpactEstimates` = ON
2. **Organization level (Org Admin):** Organization Settings > Set company firmographics (industry, revenue)

### Use Cases
- Risk-informed prioritization of detection coverage
- Budget justification (link spend to financial risk reduction)
- Board-level risk reporting
- Insurance/cyber risk discussions

---

## 11. Settings and System Administration

### Key System Settings (Feature Flags)
| Setting | Purpose |
|---|---|
| `playbooksEnabled` | Enable Playbooks platform-wide |
| `multiSourceViewEnabled` | Tags Across Owners card and Unified View |
| `readOnlyUserUpdatesAllowed` | Read Only users can update `common` API fields |
| `financialImpactEstimates` | Enable RQ ATT&CK Financial Impact |
| `aiTqlGenerationEnabled` | AI-powered TQL Generator (Beta) |
| `bulkDeleteEnabled` | Allow bulk delete via TQL on v3 endpoints |
| `enableCalData` | Enable CAL data ingestion and display |
| `threatDeprecationIntervalCount` | Indicator Deprecation Monitor batch size |

### User Management
**Path:** Settings > Org Settings > Membership

Functions:
- Create users (Standard or API)
- Assign Org roles
- Generate API tokens (TC 7.7+)
- Configure SSO mappings (SAML, OAuth)
- Lock/unlock accounts

### API User Management
**Create new API user:**
1. Settings > Org Settings > Membership > Create API User
2. Fill required fields
3. Set Token Expiration (days)
4. Save and Generate Token

**Regenerate token for existing API user:**
1. Settings > Org Settings > Membership > click Edit (pencil) for API user
2. Set new Token Expiration
3. Click Generate Token

API User Administration window indicates when tokens are expired.

### SAML Configuration
**Path:** Settings > System Settings > SAML

Supports SSO via SAML 2.0. Configure IdP metadata, attribute mappings, role assignment.

### Authentication Settings
- Password complexity requirements
- Session timeout
- 2FA enforcement
- API token expiration defaults

### Custom Owner Roles
**Path:** Settings > Org Settings > Owner Roles

Create custom roles with granular permissions beyond out-of-the-box roles.

### Custom Indicator Types
**Path:** System Administration > Indicator Types > Add

Create custom Indicator types beyond the 12 native types. Configure:
- Type name and value field name
- Validation regex
- Display attributes
- API exposure

---

## 12. Recent Platform Features

### ThreatConnect 7.7
- **API Token authentication** alongside HMAC

### ThreatConnect 7.8+
- **AI-powered TQL Generator (Beta)**: Generate TQL from plain English. Enable via `aiTqlGenerationEnabled`.
- **Actionable Search**: Parse and search for indicators directly from search bar. Known indicators show owner, ThreatAssess score, dates. Unknown indicators show CAL score.
- **AbuseIPDB Built-in Enrichment**: Real-time IP reputation. Enable in System Settings > Indicators > Enrichment Tools.
- **MITRE ATT&CK 16.0**: 19 new techniques/sub-techniques, 33 software types, 11 groups, 6 campaigns.

### ThreatConnect 7.10+
- **Manual ThreatAssess Recalculation**: Recalculate Scoring button on Indicator Details for instant refresh.
- **ThreatAssess Score in Indicator Export**: Include ThreatAssess in CSV exports from Search: Indicators screen.
- **Unified Vulnerability View**: Aggregate vulnerability data across multiple owners into single Details screen.
- **CAL data through proxies**: Configured proxies no longer block CAL data display.
- **SAML login fixes**: Resolved blocking SAML login issues.

### ThreatConnect 7.12+
- **Threat Actor Profiles**: Detailed Adversary profiles with MITRE IDs, external links, timestamps. Filter via TQL `hasThreatActorProfile()`.
- **AI Insights for Events**: Dataminr-powered AI summaries on Event Groups. Access via API `?fields=insights`.
- **Posts/Notes API**: New `/v3/posts` endpoint for notes with replies.
- **Dataminr Cyber Pulse Limited Feed**: Pulse Cyber Alerts (Urgent/Flash severity) every 5 minutes. Available for all customers on 7.12.1+.

### Built-in Enrichment Sources (current)
- DomainTools
- Farsight Security
- RiskIQ
- Shodan
- urlscan.io
- VirusTotal
- AbuseIPDB (7.8+)

---

## 13. Operational Best Practices

### Daily Operations
- Monitor Activity screen for stuck Playbooks
- Review newly ingested high-score indicators (TQL: `dateAdded > "NOW() - 24 HOURS" and threatAssessScore >= 700`)
- Check feed health (last successful poll, indicator count trends)

### Weekly Operations
- Review feed quality metrics; identify candidates for deactivation
- Audit indicator exclusion lists for staleness
- Review ThreatAssess threshold effectiveness (any FP escalations from automated blocking?)

### Monthly Operations
- Full feed audit (which feeds are producing actionable indicators?)
- Tag taxonomy review (consolidate synonymous tags via Tag Normalization)
- Custom Owner Role review (still appropriate?)
- API user audit (rotate tokens, deactivate unused)

### Quarterly Operations
- ThreatAssess configuration review (assessment thresholds still appropriate?)
- Dashboard portfolio review (still useful, or stale?)
- Platform version upgrade planning
- Comprehensive exclusion list review

---

## 14. Documentation URLs

| Resource | URL |
|---|---|
| ThreatAssess and CAL | https://knowledge.threatconnect.com/docs/threatassess-and-cal |
| What Can CAL Do For You | https://knowledge.threatconnect.com/docs/what-can-cal-do-for-you |
| Indicator Status | https://knowledge.threatconnect.com/docs/indicator-status |
| Feed Metrics and Report Card | https://knowledge.threatconnect.com/docs/feed-metrics-and-report-card |
| The Details Screen | https://knowledge.threatconnect.com/docs/the-details-screen |
| The Details Drawer | https://knowledge.threatconnect.com/docs/the-details-drawer |
| ThreatConnect Owner Roles and Permissions | https://knowledge.threatconnect.com/docs/threatconnect-owner-roles-and-permissions |
| ThreatConnect System Roles and Permissions | https://knowledge.threatconnect.com/docs/threatconnect-system-roles-and-permissions |
| Ownership in ThreatConnect | https://knowledge.threatconnect.com/docs/ownership-in-threatconnect |
| 7.10 Release Notes | https://knowledge.threatconnect.com/docs/7-10-release-notes |
| 7.12 Release Notes | https://knowledge.threatconnect.com/docs/7-12-release-notes |
| Settings and Administration | https://knowledge.threatconnect.com/docs/settings-and-administration |
| Risk Quantifier FAQ | https://knowledge.threatconnect.com/docs/threatconnect-risk-quantifier-faq |
