# ThreatConnect Integration Reference

Reference for integrating ThreatConnect with downstream consumers (SIEM, SOAR, EDR, firewalls, identity platforms). Covers TAXII operations, platform-specific integration patterns, deconfliction strategies, M&A integration, and federal compliance considerations.

## 1. Distribution Architecture Principles

### ThreatConnect as Authoritative Source
ThreatConnect should own the intel lifecycle: ingest, curate, score, distribute. Downstream platforms (SIEM, SOAR, EDR) consume curated output, not raw feeds.

**The pipeline:**
```
External Feeds (Recorded Future, Intel 471, OSINT, ISACs, ThreatConnect TAXII)
    ↓
ThreatConnect (ingest → enrich → score → curate → tag)
    ↓ (TAXII or platform-specific feed integration)
SIEM TIM (IOC matching against live telemetry)
    ↓ (IOC-match alert fires)
SOAR Playbook (automated countermeasures: block, isolate, escalate)
```

### Why TAXII Should Be the Primary Distribution Protocol
TAXII 2.1 is the platform-agnostic indicator distribution protocol. Every major SIEM and SOAR has TAXII client support. Using TAXII as the primary distribution path means:

- **Platform independence**: Switch SIEMs without rebuilding the indicator pipeline
- **M&A flexibility**: Acquired companies' SIEMs can consume CDW's curated indicators without custom integration
- **Reduced vendor lock-in**: TC's value isn't tied to one downstream consumer
- **Federal compliance**: Easier to point separate federal SIEM tenant at the same TAXII feed

### Threshold Policy for Distribution
Not everything in TC should push to SIEM. Recommended thresholds:

| Action | Threshold |
|---|---|
| **Auto-block at enforcement points** | ThreatAssess >= 700 AND Confidence >= 70 AND Critical severity |
| **SOC alert (IOC-match)** | ThreatAssess >= 500 AND active = true |
| **Reference only (Polarity overlay)** | Anything in TC; analyst-driven enrichment |

### Source Attribution
Tag indicators by source so downstream alerts indicate origin:
- `source:threatconnect-curated`
- `source:threatconnect-recorded-future`
- `source:threatconnect-osint`

This enables deconfliction and per-source effectiveness measurement.

---

## 2. TAXII Operations

### Inbound TAXII Exchange Feeds (Pulling External Intel into TC)

**Setup path:** Posts screen > Select Source > Source Config > Data tab > + NEW INBOUND

**Key parameters:**
- **Name**: Descriptive feed name
- **Polling URL**: TAXII polling service URL (provider-specific)
- **Discovery URL**: Optional; some providers use a discovery endpoint
- **STIX Parser**:
  - **STIX 2.1 Parser**: Current standard
  - **STIX 1.1.1 Parser**: Replaces attributes on existing objects
  - **STIX 1.1.1 Parser (Attribute Merge)**: Appends attributes to existing objects
- **Authentication**: Username/password or certificate
- **Collection**: Specific TAXII collection to poll

### ThreatConnect TAXII Ingest App
Enhanced TAXII 2.1 ingestion with built-in mappings for specific providers: AlienVault, FS-ISAC, H-ISAC, ND-ISAC, ReversingLabs, Space-ISAC, VMRay.

**Setup:**
1. Install via TC Exchange
2. Deploy via Feed Deployer
3. Configure per-feed parameters

**Management UI provides:**
- Tasks screen (download/convert/upload monitoring)
- Mappings screen (field/attribute/tag/security label mappings per object type)
- Runtime analytics dashboard

### Outbound TAXII Exchange Feeds (Pushing TC Intel to External Consumers)

**Configuration parameters:**
- **Inbox URL**: Destination TAXII server inbox
- **Translator Version**:
  - **STIX 1.1.1 Indicators TC_V2** (recommended)
  - **TC_V1** (legacy)
- **Collection Interval (hours)**: How often to push updates
- **Package TLP**: Most Restrictive Content TLP, specific color, or None
- **Exchange is Active**: Enable/disable toggle

### STIX 2.1 → ThreatConnect Mapping
| STIX Object | ThreatConnect Object |
|---|---|
| Indicator (atomic patterns) | Indicator (Address, File, Host, URL, etc.) |
| Indicator (complex patterns) | Signature Group (STIX Pattern type) |
| Threat Actor | Adversary Group |
| Campaign | Campaign Group |
| Intrusion Set | Intrusion Set Group |
| Report | Report Group |
| Malware | Threat Group |
| Relationship | Association |

### TAXII 2.1 Server (TC as a TAXII Server)
TC also operates a TAXII 2.1 server, exposing collections that external clients can pull:
```
GET /taxii2/                                          # Discovery
GET /taxii2/<api-root>/                               # API Root
GET /taxii2/<api-root>/collections/                   # List collections
GET /taxii2/<api-root>/collections/{id}/objects/      # Objects in collection
```

Required header: `Accept: application/taxii+json;version=2.1`. Auth: same as REST API (Token or HMAC).

---

## 3. SIEM Integration Patterns

### Microsoft Sentinel

**TAXII path (recommended):**
1. In Sentinel: Data connectors > **Threat Intelligence - TAXII**
2. Configure with TC TAXII 2.1 server URL and auth
3. Sentinel pulls indicators on schedule into the ThreatIntelligenceIndicator table
4. Built-in analytics rules match indicators against logs

**Logic Apps SOAR (Sentinel-side automation):**
- Indicator match alert → Logic App → automated response
- Logic App can call TC API (v3) for enrichment

**Setup considerations:**
- Sentinel TAXII connector polls on schedule; not real-time push
- Use Logic Apps or Sentinel automation rules for response orchestration
- Federal: Sentinel GCC (FedRAMP High) supports TAXII connector

### Splunk + Enterprise Security

**ThreatConnect App for Splunk** (Splunkbase):
- Pulls indicators from TC API into Splunk KV store
- Maps indicators into Enterprise Security threat collections
- Provides dashboards and search commands

**Splunk SOAR (formerly Phantom):**
- Native ThreatConnect connector
- Indicator enrichment, creation, and update from playbooks
- Bi-directional sync with TC

**Setup considerations:**
- Splunk App requires App for Splunk on the Splunk Enterprise instance
- Enterprise Security adds threat matching against ingested data
- TAXII as alternative if you want platform-agnostic distribution

### Elastic Stack

**Elastic Agent with TI module:**
- Built-in support for STIX/TAXII feeds
- Ingest TC TAXII feed into Elasticsearch threat-* indices
- Detection rules match telemetry against indicators

**Elastic Security SIEM:**
- Auto-creates alerts from indicator matches
- Provides graph view of threat associations

**Setup considerations:**
- Elastic Agent's Threat Intel integration directly supports TAXII 2.1
- Federal: Elastic Cloud GovCloud supports the same configuration

### Cortex XSIAM (Currently in Use, Being Replaced)

**Three integration paths:**
| Integration | Direction | Method | Path in XSIAM |
|---|---|---|---|
| **ThreatConnect Feed** | TC → XSIAM | Feed integration | Settings > Configurations > Automation & Feed Integrations |
| **ThreatConnect v3** | Bidirectional | XSOAR integration | Settings > Configurations > Automation & Feed Integrations |
| **TAXII2 Server** | XSIAM → TC | TAXII 2.1 server | Settings > Configurations > Automation & Feed Integrations |

**ThreatConnect Feed (continuous IOC ingestion):**
Maps TC indicator types to XSIAM types (Address→IP, Host→Domain, File→File, URL→URL). Imports ThreatAssess score, ratings, tags, attributes. Indicators match against telemetry for IOC-match alerts.

**ThreatConnect v3 (on-demand operations):**
Full CRUD against TC from XSIAM playbooks/CLI. Key commands: `!tc-get-indicators`, `!ip`, `!url`, `!file`, `!tc-create-indicator`, `!tc-update-indicator`, `!tc-delete-indicator`, `!tc-tag-indicator`, `!tc-get-groups`, `!tc-get-owners`.

**TAXII2 Server (share back to TC):**
XSIAM serves as TAXII 2.1 server exposing curated indicator collections. TC pulls via Inbound TAXII Exchange Feed.

**Note:** XSIAM is being replaced (Sentinel, Splunk+ES, or Elastic TBD). Architecture should pivot to TAXII-primary to avoid platform-specific rebuild.

---

## 4. SOAR Integration Patterns

### Tines (API-First, Likely CDW Direction)

**Pattern:** Tines stories call TC API directly via HTTP Request actions.
- No vendor-specific connector required
- TC API authentication via Tines credentials (Token or HMAC)
- Tines AI Agent action can use TC enrichment data for decisioning

**Common Tines + TC patterns:**
- Indicator enrichment story (input IOC → query TC v3 API → return ThreatAssess + tags + associations)
- IOC submission story (collect indicators from upstream → bulk submit to TC via API)
- Indicator deprecation story (timer trigger → query for stale indicators → set Inactive)

### Torq (API-First)
Similar to Tines: HTTP-based API calls into TC. Workflow steps for enrichment, creation, and update operations.

### BlinkOps (API-First)
Native TC connector available. Provides UI for common operations without custom API calls.

### XSOAR (Currently via XSIAM, Being Replaced)
Native ThreatConnect v3 integration with full command set. Replaced by Tines/Torq/BlinkOps direction.

### SOAR Pattern: Cross-Pillar Countermeasures
Single threat intel signal triggers actions across multiple control planes:

```
TC Indicator (ThreatAssess >= 700, Critical, IP type)
    ↓
SOAR Playbook
    ↓
Parallel actions:
  - Palo Alto NGFW: Add to block list
  - CrowdStrike: Add to detection list
  - Akamai: Add to WAF deny rule
  - Entra ID: Block sign-ins from IP
  - Email Gateway: Block sender domain (if related)
    ↓
Update TC: Tag indicator with "deployed-to-grid", add observation
```

This is the Active Defense Grid pattern: one signal, simultaneous multi-pillar response.

---

## 5. Deconfliction Strategies

### TC + Vendor-Native TI (e.g., Unit 42 in XSIAM, Unit 42 in Cortex)

**Problem:** Same indicator may be in TC (from external feeds) and in XSIAM's Unit 42 feed simultaneously, generating duplicate IOC-match alerts with potentially conflicting scores.

**Resolutions:**
1. **Source tagging**: Tag TC-sourced indicators distinctly (`source:threatconnect`) so alerts indicate origin
2. **Authoritative source policy**: Document which source owns truth per indicator type. Example: Unit 42 owns IPs/domains; TC owns campaign attribution and adversary tracking.
3. **Alert exclusions**: Suppress duplicate alerts from one source for indicators in both
4. **Threshold differentiation**: Use TC's higher analytical depth (Confidence, ThreatAssess) for blocking decisions; use vendor feeds for detection-only

### TC + Multiple External Feeds

**Problem:** Recorded Future, Intel 471, OSINT feeds, and Dataminr may all report the same indicator with different scores.

**TC's built-in resolution:** ThreatAssess weighted-averages Threat Rating and Confidence Rating across all owners reporting the indicator. Configure CAL weight to factor in crowdsourced reputation.

**Operational:** Use Feed Explorer to identify high-overlap feeds. Disable redundant feeds with low Unique Indicators percentage.

### TC + EDR Native Intel

**Problem:** CrowdStrike, Defender, etc., have their own threat intelligence. May surface indicators not in TC, or score TC indicators differently.

**Resolution:**
- TC focuses on enrichment and contextual analysis
- EDR native intel focuses on endpoint-specific threats
- They complement rather than compete; both surface alerts but at different layers (telemetry vs endpoint behavior)

---

## 6. M&A Integration

### Challenge
CDW acquires multiple companies per year. Acquired companies retain their existing tech stacks (Lizzie/IMO doesn't enforce migration). ThreatConnect indicators need to push to non-CDW-standard tools during integration windows.

### TAXII as M&A Accelerator
**Pattern:** Acquired company points its existing SIEM (any vendor) at CDW's TC TAXII feed. No custom integration required.

**Onboarding workflow:**
1. Day 1: Provision TAXII credentials for acquired company's SIEM
2. Day 1-7: Configure their SIEM to pull from CDW TC's TAXII collection
3. Day 7+: Their SIEM matches TC indicators against their telemetry; alerts generated
4. Long-term: Either consolidate to CDW's SIEM (if standardizing) or continue TAXII-only integration

### Integration Architecture for M&A
**Option A: Acquired Company Has SIEM with TAXII Support**
- Configure outbound TAXII feed from CDW TC to their SIEM
- Apply TLP markings appropriately
- Track effectiveness via their SOC's IOC-match metrics

**Option B: Acquired Company Uses Different TIP**
- Configure outbound TAXII feed from CDW TC to their TIP
- Their TIP redistributes to their downstream consumers
- Coordinate scoring and aging policies

**Option C: Acquired Company Has Limited SIEM Capability**
- Provide TC API credentials for on-demand lookups
- Configure their SOAR or scripts to query TC via API
- Plan migration to TAXII as their stack matures

### M&A Deliverables for EDA
- TAXII feed configuration template (covers options A/B/C above)
- Indicator sharing policy (which TLP markings, which thresholds)
- Effectiveness measurement (how to track if their SIEM is using the indicators)
- Cutover playbook (when to deprecate the temporary integration)

---

## 7. Federal Compliance Considerations

### CMMC Level 2 Workload Segregation
Some CDW BUs serve federal customers under CMMC Level 2. Open question: does CER-operated TC support federal workloads or is it fully segregated from commercial?

### Possible Architectures
**Option A: Single TC Instance, Logical Separation**
- One TC tenant
- Federal data in dedicated Source(s) with restricted access
- Risk: shared infrastructure may not meet CMMC Level 2 requirements

**Option B: Separate Federal TC Tenant**
- Commercial TC: existing instance for commercial workloads
- Federal TC: separate instance for federal workloads
- Indicator sharing via TAXII outbound from commercial → inbound to federal (selective)

**Option C: Federal TC Hosted in GCC/FedRAMP Environment**
- Dedicated federal-compliant TC instance
- TAXII bridge from commercial for selective indicator sharing
- Polarity also requires federal-compliant deployment

### Verification Required (with Rick)
- Whether CER-operated SIEM/SOAR must support federal workloads
- Whether TC is in scope for federal compliance requirements
- Whether federal TC tenant procurement is needed

### Federal Capable SIEM/SOAR Candidates
- **Sentinel GCC** (FedRAMP High): Supports TAXII connector; CMMC compatible
- **Splunk Cloud GovCloud**: Supports TC integration; CMMC compatible
- **Elastic Cloud GovCloud**: Supports TAXII; CMMC compatible
- **Tines self-hosted in Azure**: Could be deployed in federal-capable Azure tenant

---

## 8. Effectiveness Measurement

### Per-Indicator Metrics
- **Distribution events**: How many downstream platforms received the indicator
- **Match events**: IOC matches generated against telemetry
- **Action events**: Automated actions taken (blocks, isolations, alerts)
- **False positive rate**: Indicators that triggered actions but were benign

### Per-Feed Metrics
- **Indicator volume**: Indicators contributed by feed
- **Action contribution rate**: Percentage of feed's indicators that triggered actions
- **FP rate by feed**: False positive rate for indicators sourced from each feed
- **Time-to-action**: Time from feed ingestion to first downstream action

### Per-Adversary Metrics
- **Coverage**: ATT&CK techniques covered by intel for the adversary
- **Indicator freshness**: Average age of indicators tied to the adversary
- **Attribution confidence**: Average Confidence Rating for indicators tied to the adversary

### Dashboards to Build
- **Active Defense Grid effectiveness**: Single view of TC indicator volume → SIEM match rate → SOAR action rate → outcome
- **Feed ROI**: Feed cost vs action contribution rate
- **Adversary tracking**: Top adversaries by indicator volume and recent activity

---

## 9. Polarity Cross-Platform Integration

Polarity sits on the analyst's desktop and can query multiple platforms simultaneously during triage. For the Active Defense Grid:

### Common Polarity Integration Stack (Analyst View)
- ThreatConnect Core, IOC Submission, Intel Search, CAL (TC enrichment)
- SIEM integration (Splunk, Sentinel, Elastic, XSIAM): incident history, recent observations
- EDR integration (CrowdStrike, Defender): endpoint context
- ITSM integration (ServiceNow, Jira): related ticket history
- Internal HRIS or asset management: user/asset context

### Operational Value
Analyst opens any tool (browser, ticketing, SIEM console) → Polarity recognizes entities → simultaneous lookups across all integrations → unified context in single overlay → analyst decides response without pivoting between tools.

### Configuration During SIEM/SOAR Transition
When the SIEM/SOAR decision lands, Polarity needs only the new platform's integration enabled. The analyst overlay experience remains consistent. Polarity is platform-agnostic across SIEM/SOAR choices.

---

## 10. Migration Patterns (XSIAM Exit)

### Current State (XSIAM)
- TC indicators flow to XSIAM via ThreatConnect Feed integration
- XSIAM matches against telemetry
- XSOAR (within XSIAM) automates response

### Target State (TBD: Sentinel, Splunk+ES, or Elastic)
- TC indicators flow via TAXII outbound feed (platform-agnostic)
- New SIEM consumes TAXII collection
- New SOAR (Tines/Torq/BlinkOps) consumes TC API for enrichment

### Migration Steps
1. **Configure TAXII outbound**: Set up TC outbound TAXII feed (collection of high-confidence indicators)
2. **Pilot with target SIEM**: Configure new SIEM TAXII connector against the same feed
3. **Parallel run**: Both XSIAM and new SIEM consume; compare match rates
4. **Cutover**: Disable XSIAM ThreatConnect Feed integration; new SIEM is sole consumer
5. **Decommission**: Remove XSIAM ThreatConnect v3 integration; replace with new SOAR connector

### Risks and Mitigations
| Risk | Mitigation |
|---|---|
| New SIEM doesn't match XSIAM's IOC matching capabilities | Validate during parallel run; tune detection rules |
| Loss of XSOAR-specific automations | Rebuild in new SOAR using TC API directly |
| Indicator scoring drift during cutover | Maintain ThreatAssess thresholds in TC; new SIEM uses same threshold |
| Polarity-XSOAR integration loss | Replace with Polarity integration for new platform |

---

## 11. Quick Reference: Integration Decision Tree

**Question: Where should this indicator distribution path be built?**

```
Is the consumer a SIEM with TAXII support?
├── Yes → Use TAXII outbound feed (platform-agnostic, future-proof)
└── No → Is there a vendor-specific TC integration?
    ├── Yes → Use the vendor integration (e.g., ThreatConnect Feed for XSIAM)
    └── No → Use TC API directly from the consumer's SOAR or scripts
```

**Question: Where should automated response logic live?**

```
Is the action vendor-specific (e.g., CrowdStrike isolate)?
├── Yes → Vendor's SOAR or platform-native automation
└── No → SOAR platform (Tines/Torq/BlinkOps/XSOAR)
    └── For cross-pillar actions: SOAR orchestrates across vendors
```

**Question: Where should enrichment happen?**

```
Is enrichment for analyst (real-time, manual)?
├── Yes → Polarity overlay (TC + other sources)
└── Is enrichment for automated response (alert triage)?
    ├── Yes → SOAR playbook calling TC API + other sources
    └── Is enrichment for storage (indicator metadata)?
        └── Yes → TC Playbook with enrichment Apps; results saved as TC attributes
```

---

## 12. Documentation URLs

| Resource | URL |
|---|---|
| TAXII 2.1 (TC Server) | https://docs.threatconnect.com/en/latest/rest_api/taxii/taxii_2.1.html |
| TAXII 1.x (Legacy) | https://docs.threatconnect.com/en/latest/rest_api/taxii/taxii.html |
| TAXII 2.1 Server Overview | https://knowledge.threatconnect.com/docs/taxii-21-server-overview |
| Splunk App | https://threatconnect.readme.io/docs/splunk-1 |
| Apps and Integrations | https://knowledge.threatconnect.com/docs/apps-and-integrations |
| ThreatConnect v3 Integration (XSOAR) | https://xsoar.pan.dev/docs/reference/integrations/threat-connect-v3 |
| ThreatConnect Feed Integration (XSOAR) | https://xsoar.pan.dev/docs/reference/integrations/threat-connect-feed |
| TAXII2 Server Integration (XSOAR) | https://xsoar.pan.dev/docs/reference/integrations/taxii2-server |
| Cortex Marketplace | https://cortex.marketplace.pan.dev |
| OASIS TAXII 2.1 Specification | https://oasis-open.github.io/cti-documentation/resources.html#taxii-21-specification |
