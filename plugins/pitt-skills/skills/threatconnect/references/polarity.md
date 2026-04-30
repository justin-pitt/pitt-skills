# Polarity Reference

Reference for Polarity overlay integrations, custom integration development, and server administration. Polarity is owned by ThreatConnect and integrates deeply with TC, but is a separate product.

## 1. Polarity Overview

### What It Does
Federated search and data aggregation overlay. Sits on top of any application (browser, ticketing, SIEM console, email), recognizes entities on screen (IPs, domains, hashes, CVEs, emails), and runs real-time lookups against connected data sources. Eliminates "swivel-chair" pivoting between tools.

### Editions
- **Intel Edition**: Threat-intel-focused; best for analyst triage workflows
- **Enterprise Edition**: Full feature set including all integrations, governance, advanced admin
- **Community Edition**: Free tier; limited features

### Key Concepts
- **Overlay**: The floating window showing lookup results
- **Recognition**: Auto-detection of entities on screen
- **Subscription**: User opt-in to receive results from a specific integration
- **Suppression**: Time window before re-notifying on a previously seen entity

---

## 2. ThreatConnect Integrations for Polarity

### 2.1 ThreatConnect Core Integration
Searches your TC instance for address, file, host, and email indicators. Interactive features in the overlay:
- Add/remove tags
- Modify Threat Rating and Confidence Rating
- Report false positives

**Configuration:**
| Option | Description |
|---|---|
| ThreatConnect Instance URL | Including protocol and optional non-default port |
| Access ID | Account identifier for API key |
| API Key | Secret key for the Access ID |
| Search Inactive Indicators | Toggle to include inactive indicators in lookups |
| Organization Search Blocklist | Comma-delimited owners to exclude (cannot use with Allowlist) |
| Organization Search Allowlist | Comma-delimited owners to include only (cannot use with Blocklist) |

### 2.2 ThreatConnect IOC Submission Integration
Bulk indicator management. Searches TC for domains, IPs, hashes, emails, then create/delete in bulk.

**Configuration:**
| Option | Description |
|---|---|
| ThreatConnect API URL | Base API URL |
| Access ID | Account identifier |
| API Key | Must have **FULL indicator permissions** for submission |
| Allow IOC Deletion | Limited to user's default Organization |
| Allow Group Association | Permit associating indicators with groups |
| Allow Adding Attributes | Permit setting attributes during submission |

### 2.3 ThreatConnect Intel Search Integration
Searches Group titles in your TC instance. Caches up to 10,000 group objects per owner in memory; refreshes automatically every hour.

### 2.4 ThreatConnect CAL Integration
Provides community-driven insights into 2+ billion indicators. Displays:
- CAL Score (0-1000)
- CAL Status (Active/Inactive)
- CAL Impact Factors
- CAL Feed Information
- CAL Classifiers
- Observations / Impressions / False Positives
- Quad9 observed attempted resolutions (last 90 days)

---

## 3. Other Polarity Integrations (Selected)

### Polarity-XSOAR Integration
In-overlay access to XSOAR/XSIAM data:
- Indicator lookup (severity, reputation, first/last seen)
- Incident association (view linked incidents)
- Playbook execution (trigger from overlay)
- Indicator and incident creation
- Evidence addition

**Configuration:** XSOAR/XSIAM URL, API key with appropriate permissions.

### Polarity-XSOAR IOC Submission Integration
Bulk indicator management:
- Identify which indicators on screen are NOT in XSOAR
- Submit indicators in bulk
- Create incidents and associate with submitted indicators
- Assign types, severity, and trigger playbooks on submission

### Polarity Forms
Pre-defined emails and forms for cross-team communication. Trigger forms from the overlay to send standardized requests.

### Polarity Detection Forms
Form-based detection feedback/requests via email. Workflow tool for analysts to submit detection improvement requests.

### Polarity Assistant
AI-powered summarization of integration results. Supports:
- Azure OpenAI GPT-4-32k
- OpenAI GPT-4-turbo

Summarizes long enrichment results into digestible context.

### Sandboxes
Google Custom Search Engine integration for malware analysis sites.

### URL Pivots
Quick pivots to custom SIEM searches from various entity types. Configurable per entity type.

### Security Blogs
Google Custom Search for security blog posts. Returns relevant blog content for entities.

### Social Media Searcher
Search emails/text against Google for social media presence.

### Analyst Telemetry (Elasticsearch and Splunk)
Search history, who else has seen an indicator, first/last seen by analysts.

### Exploit Finder
Google Custom Search for known exploits associated with the entity.

### Font Changer
Accessibility integration. Convert selected text to different font/size in the overlay.

### Regex Cheat Sheet
Regex character lookup directly in the overlay.

### Epoch Time
Convert Unix timestamps to human-readable format.

---

## 4. User Settings (Subscriber-configurable)

### Overlay Behavior
| Setting | Description |
|---|---|
| **Always on Top** | Overlay persists vs auto-hide after timeout |
| **Overlay Opacity** | Adjustable transparency slider |
| **Suppression Duration** | Seconds before Polarity re-notifies on previously seen entity |
| **Overlay Open Duration** | How long overlay stays visible when not pinned |
| **Show Missed Data** | Notification when scrolled down and new entities appear |

### Recognition Modes
| Mode | Behavior |
|---|---|
| **Automatic** | Continuously scans active application window; highlights recognized entities |
| **On-Demand** | Integrations only triggered by user action (search bar, clipboard, shortcut, Focus Mode) |
| **On-Demand Only** | Admin-set per integration; integration only runs during explicit on-demand searches |

---

## 5. Polarity Server Administration

### Architecture
Polarity Server is a Node.js application with:
| Component | Path |
|---|---|
| Server process | `polarity-server` daemon |
| Integrations directory | `/app/polarity-server/integrations/` |
| Server config | `/app/polarity-server/config/config.js` |
| Process owner | `polarityd` user |

### Integration Management
**Start/stop integrations:** Admin or Integration Manager via Settings > Integrations in web UI. Stopped integrations appear blocked out in users' subscription lists.

**User permissions:**
- Admins control which integrations users can see and subscribe to
- Per-integration settings can be admin-only or user-configurable
- API keys, instance URLs typically admin-managed

### Installing Integrations
1. Copy integration directory to `/app/polarity-server/integrations/`
2. `cd <integration-dir> && npm install`
3. `chown -R polarityd:polarityd /app/polarity-server/integrations/<integration-name>`
4. Restart Polarity Server for first-time load

### User Management
- Admins create user accounts and assign roles
- SSO supported (SAML, OAuth)
- Role-based access to integrations and settings

### Analyst Telemetry
Polarity tracks (via Elasticsearch or Splunk integration):
| Metric | Description |
|---|---|
| Search history | Entities each analyst has looked up |
| Who else has seen it | Other analysts who encountered the same entity |
| First/last seen | When entity was first and most recently viewed by any analyst |
| Integration results | Enrichment data returned per lookup |

Use telemetry for:
- Workload distribution analysis
- Identifying emerging threats (high-attention indicators)
- Polarity adoption metrics
- Forensic reconstruction of analyst investigation paths

---

## 6. Custom Integration Development

### Integration Structure (Node.js)
```
my-integration/
├── components/              # Client-side JS (optional)
│   └── my-integration-block.js
├── config/
│   └── config.js            # Integration configuration (required)
├── styles/
│   └── my-integration.less  # LESS/CSS styles (optional)
├── templates/
│   └── my-integration.hbs   # Handlebars template (optional)
├── test/
│   └── my-integration-test.js
├── integration.js           # Main module entry point (required)
├── package.json             # NPM package definition (required)
└── README.md                # Documentation (recommended)
```

### Configuration File (config.js)
```javascript
module.exports = {
  name: "My Integration",
  acronym: "MI",
  description: "Searches my internal tool for context",
  entityTypes: ['IPv4', 'IPv6', 'domain', 'MD5', 'SHA1', 'SHA256', 'email', 'url'],
  // Custom entity types via regex
  customTypes: [
    { key: 'hostname', regex: /[a-z]+-[a-z]+-\d{3}/i }
  ],
  // User/admin configurable options
  options: [
    { key: 'apiUrl', name: 'API URL', type: 'text', default: '', userCanEdit: false },
    { key: 'apiKey', name: 'API Key', type: 'password', default: '', userCanEdit: false },
    { key: 'showInactive', name: 'Show Inactive Results', type: 'boolean', default: false, userCanEdit: true }
  ],
  logging: { level: 'info' }
};
```

### Lifecycle Methods (integration.js)

| Method | Purpose | When Called |
|---|---|---|
| `startup(logger)` | Initialize connections, validate config | Once on integration load |
| `doLookup(entities, options, cb)` | Core lookup logic; called for each batch of recognized entities | Every time entities recognized on screen |
| `onDetails(lookupObject, options, cb)` | Fetch additional detail when user expands an entity card | User clicks Details in overlay |
| `onMessage(payload, options, cb)` | Handle interactive actions (button clicks, form submissions) | User interacts with overlay UI elements |
| `validateOptions(options, cb)` | Validate user-provided configuration | When user saves settings |

### doLookup Pattern
```javascript
function doLookup(entities, options, cb) {
  const results = [];
  async.each(entities, (entity, done) => {
    request({
      url: `${options.apiUrl}/lookup`,
      qs: { query: entity.value },
      headers: { 'Authorization': `Bearer ${options.apiKey}` },
      json: true
    }, (err, response, body) => {
      if (err) return done(err);
      if (response.statusCode === 404 || !body.found) {
        results.push({ entity, data: null }); // No result; Polarity hides this entity
      } else {
        results.push({
          entity,
          data: {
            summary: [body.score, body.category],  // Tags shown in overlay summary
            details: body                            // Full object for Handlebars template
          }
        });
      }
      done();
    });
  }, (err) => cb(err, results));
}
```

### Entity Types
**Built-in:** IPv4, IPv6, domain, MD5, SHA1, SHA256, email, url, cve

**Custom (via regex):**
```javascript
customTypes: [
  { key: 'incident_id', regex: /INC[-_]?\d{6,}/i },
  { key: 'asset_tag', regex: /AST-[A-Z]{3}-\d{4}/i }
]
```

### Overlay Customization (Handlebars Templates)
Templates use Handlebars syntax with access to the `details` object from `doLookup`:
```handlebars
<div class="mi-container">
  <h3>{{details.name}}</h3>
  <div class="mi-score">
    Score: <span class="{{#if (gt details.score 70)}}mi-high{{else}}mi-low{{/if}}">
      {{details.score}}
    </span>
  </div>
  {{#if details.tags}}
    <div class="mi-tags">
      {{#each details.tags}}
        <span class="mi-tag">{{this}}</span>
      {{/each}}
    </div>
  {{/if}}
</div>
```

### Interactive Actions (Buttons in Overlay)
```javascript
// In doLookup, include action buttons in data
data: {
  summary: ['Score: 85'],
  details: {
    score: 85,
    actions: [
      { name: 'Block IP', method: 'blockIndicator' },
      { name: 'Add to Case', method: 'addToCase' }
    ]
  }
}

// In onMessage, handle the action
function onMessage(payload, options, cb) {
  if (payload.action === 'blockIndicator') {
    // Call firewall API, update ThreatConnect, etc.
    cb(null, { status: 'success', message: 'IP blocked' });
  }
}
```

### Logging
```javascript
logger.info('Lookup completed', { count: results.length });
logger.error('API error', { error: err });
logger.debug('Request body', { body });
```
Log levels: trace, debug, info, warn, error.

### Cache Settings
Specified in config.js:
```javascript
options: [
  { key: 'cacheResultsTTL', name: 'Cache TTL (seconds)', type: 'number', default: 300, userCanEdit: false }
]
```

---

## 7. Polarity Operational Patterns

### High-Value Workflow Examples

**Triage workflow:**
Analyst opens alert in SIEM → Polarity recognizes IPs/domains/hashes → overlay shows TC ThreatAssess + CAL + VirusTotal + internal incident history → analyst decides response without leaving the SIEM.

**Bulk IOC submission:**
Analyst reviews threat report in browser → Polarity's IOC Submission integration highlights known and unknown indicators → analyst selects unknowns → submits to TC in bulk with tags and group association.

**Cross-tool context:**
Analyst working in ServiceNow ticket → Polarity overlay shows TC indicator history, Splunk recent observations, Active Directory user details, Jira related tickets, all simultaneously.

---

## 8. Common Issues and Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Integration not appearing in subscriptions | Not installed or not owned by polarityd | Verify directory exists; `chown -R polarityd:polarityd` |
| No entities recognized | Integration not subscribed or entity type not configured | Check subscription; verify `entityTypes` in config.js |
| Overlay not showing | Overlay minimized or suppression duration too high | Check Always on Top; reduce suppression duration |
| Integration errors in logs | Missing npm dependencies or API connectivity | `npm install`; verify API endpoint reachable from server |
| High memory usage | Large integration cache (e.g., Intel Search caching 10K+ groups) | Adjust cache refresh interval; increase server resources |
| Custom regex not matching | Regex flags incorrect | Use case-insensitive flag (`/pattern/i`); test with online regex tester |
| onMessage actions not firing | `actions` not in data structure | Verify `details.actions` array structure |

---

## 9. Documentation URLs

| Resource | URL |
|---|---|
| Polarity Overview (TC KB) | https://knowledge.threatconnect.com/docs/polarity |
| Polarity Docs | https://docs.polarity.io |
| Polarity Integration Developer Guide | https://docs.polarity.io/integrations |
| Polarity Community Edition Guide | https://docs.polarity.io/community-edition-guide |
| GitHub (Polarity Integrations) | https://github.com/polarityio |
| ThreatConnect Marketplace (Polarity) | https://threatconnect.com/marketplace/polarity/ |
| Support | support@polarity.io |
