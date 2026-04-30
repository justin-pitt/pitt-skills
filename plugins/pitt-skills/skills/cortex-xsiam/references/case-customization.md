# Case & Incident Customization Reference

> **Terminology**: This file uses Palo Alto's native "incident" / "alert" naming because the customization UI and API arguments use those terms verbatim. In XSIAM these surface as **cases** and **issues** to analysts. See [case-ops.md](case-ops.md) for the analyst workflow and terminology mapping.

Covers everything under Settings → Configurations → Object Setup → Incidents/Alerts plus Incident Response → Incident Configuration. For playbook authoring that consumes these fields/timers, see [soar-automation.md](soar-automation.md).

## 1. Incident Scoring & Starring

**Starring** (admin doc p. 558): manual prioritization marker. Either click the star on a row, or build a **starring configuration** at Incident Response → Incident Configuration → Starred Alerts. Configurations match incoming alert attributes; matched alerts and their parent incidents get a purple star. SBAC-aware (restrictive vs permissive scoping).

**Scoring** (admin doc p. 559-561): three methods, evaluated in order:
1. **Rule-based** - Incident Response → Incident Configuration → Scoring Rules. Filter on hostname / IP / user / AD or Azure group/OU. Top-level rules + sub-rules; scores aggregate. Default: score applies only to **first matching alert** in the incident - toggle off if you want every matching alert to add to the total.
2. **SmartScore** - ML-based, requires Cortex XSIAM Analytics enabled (Settings → Configurations → Cortex XSIAM-Analytics). Up to 48h after first activation before scores appear. Security domain only.
3. **Manual** - fallback when neither produces a score; analyst sets via Manage Score in the incident pane.

Override path: Incidents → detailed view → click the score → Set score manually. Hover the SmartScore to give thumbs-up/down feedback into the model. Why analysts care: combined with severity, score drives Sort By Score on the Incidents page - primary triage signal alongside severity.

## 2. Custom Incident & Alert Fields

Two parallel field stores (admin doc p. 561-565, 573-576): **Alerts → Fields** and **Incidents → Fields**. Same UI flow, separate scopes.

Path: Settings → Configurations → Object Setup → Alerts (or Incidents) → Fields → +New Field.

Field types: Boolean, Date picker, **Grid (table)**, HTML, Long text, Markdown, Multi select / Array, Number, Short text, Single select, **Timer**, URL.

Gotchas:
- **System fields are locked** - cannot edit, delete, or export. Includes Source Instance, severity, status, etc.
- **Field name and type are immutable after save** - pick carefully; only tooltip and basic settings stay editable.
- **Date picker fields cannot drive filters, starring rules, playbook triggers, layout rules, or alert exclusions** - XSIAM only indexes timestamps for system date fields.
- Grid / HTML / Markdown fields show as `Data Available` placeholder in the table view; values only render in the layout's Investigate panel.
- Multi-select shows first value plus `+N More` in the table.
- Deleting a field (or uninstalling a content pack that owns it) breaks correlation rules, layouts, scoring, starring, and playbook triggers that reference it. Audit before removing.
- Custom fields export/import as JSON - right-click Export, or Export All for the whole set. Useful for moving customization dev → prod.

Use **Grid fields** when an alert/case needs a structured list (e.g., affected users + roles, evidence rows). Set Lock per-column to make values static; otherwise inline editing is on by default.

Update field values from CLI / playbook / script via `setAlert` (alert) or `setIncident` / `setParentIncidentFields` (incident). `setParentIncidentFields` does **not** support grid fields (admin doc p. 737).

## 3. Layouts

Layouts control the Investigate panel - which tabs, sections, fields, and action buttons render for an alert or incident (admin doc p. 567-570, 579-580).

System layouts ship locked. To customize, **right-click → Detach** (stops content updates, keeps the slot) or **Duplicate** (free-standing copy). Detached layouts re-merge via Attach but local edits get overwritten on reattach. Duplicated layouts behave like fully custom.

Build path: Settings → Configurations → Object Setup → Alerts → Layouts → New Layout. Add tabs, drag in sections from Library, drop fields/buttons from Library. **Limit ~50 fields per section** (admin doc p. 568). War Room and Work Plan tabs cannot be edited or deleted, only hidden.

Buttons fire scripts. Mark optional script args as Ask User to prompt the analyst at click time; mandatory-only is a known limitation, so wrap mixed-arity scripts (admin doc p. 568).

**Layout rules** (admin doc p. 570, 580) - Settings → Configurations → Object Setup → Alerts (or Incidents) → Layout Rules. Match incoming alerts/incidents on attributes (source, severity, domain, etc.) → assign a specific layout. Rules evaluate top-down; first match wins. Content-pack rules pin to top by default - drag to reorder. Default fallback layout applies if no rule matches. SBAC-aware on edit.

## 4. Timer Fields & SLAs

**Disabled by default** in XSIAM. Enable at Settings → Configurations → General → Server Settings → Alerts → Enable Timer Field (admin doc p. 564).

**Alert timer** (admin doc p. 564-567): plain stopwatch attached to an alert. Counts up from start; optionally counts down to a target. Risk Threshold flags "at risk" before timeout. Run script on timeout requires the script to carry the `SLA` tag (script settings → tags). Not auto-started - must be triggered via playbook task, CLI, or script.

**Incident timer + SLA pair** (admin doc p. 570-573): the proper SLA pattern.
1. Create the **Timer field** with Incidents Filter (e.g., `Incident Domain = Security`), Start when, End when, optional Pause condition, and reopen behavior (Reset / Continue).
2. Create the **SLA field** referencing that Timer. Add one or more Goals with filter + duration. Goals evaluate in priority order; drag to reorder.

The timer counts **forward**, the SLA counts **backward** to the goal; breached SLAs render red with negative time. A common pattern is the `casetimer` / `responsetimesla` field pair seeded into incident layouts so analysts see remaining time on the Incidents table.

CLI / playbook control (admin doc p. 565-567):
- `Timer.start` / `Timer.pause` / `Timer.stop` actions on a playbook task or section header (Timers tab).
- `!startTimer timerField=<machinename>`, `!pauseTimer`, `!stopTimer`, `!resetTimer` in the War Room CLI.
- `!setAlert sla=30 slaField=<machinename>` to override the target on the fly.
- Use the **machine name** (lowercase, no spaces) - visible by hovering the field in the editor.
- `Timer.stop` without a `resetTimer` afterward cannot be restarted in the same alert. Use `Timer.pause` if you need to resume.
- All timers stop automatically when the alert/incident closes.
- After editing timer/SLA logic on existing incidents: `!RefreshIncidentDynamicCustomFields` in the War Room (admin doc p. 573).

Common scripts gain the `SLA` tag and read alert context to email, escalate, or flip an owner on breach.

## 5. Automation Rules

**Legacy XDR feature, frozen in XSIAM** (admin doc p. 735-736). If migrated from XDR, existing rules at Incident Response → Response → Automation → Automation Rules still execute. You can disable or delete them; you **cannot edit existing rules or create new ones**.

For new automation in XSIAM, build **playbooks** (see [soar-automation.md](soar-automation.md)). Playbooks supersede automation rules, support full SOAR primitives (sub-playbooks, branching, indicator extraction, manual tasks), and are the only path forward for net-new tenants.

When auditing a migrated tenant, list legacy rules first - many are redundant with shipped playbooks and just add noise.

## 6. Custom Statuses & Resolution Reasons

Path: Configurations → Object Setup → Incidents → **Properties** (admin doc p. 716-717).

Built-in resolution reasons: Resolved - True Positive, Resolved - False Positive, Resolved - Security Testing, Resolved - Known Issue, Resolved - Duplicate Incident. **TP/FP feed SmartScore** - using them correctly improves future scoring; using custom reasons does not.

Add a custom status: Properties tab → Add another status field → type → Save. Click Edit to reorder.

Hard gotchas:
- **Custom statuses and resolution reasons cannot be deleted or modified after creation.** Triple-check naming.
- Custom statuses degrade SmartScore's ability to learn - the model is trained on built-in TP/FP signals.
- Built-in dashboards, content-pack widgets, and shipped playbooks may filter on default statuses (`New`, `Under Investigation`, `Resolved`); custom values can silently drop out of those dashboards. Audit any tenant-built XQL widget that filters on `status` after adding a custom value.
- Resolution reasons are **domain-specific** - only the reasons enabled on a domain show up for incidents in that domain (admin doc p. 716).

CLI / playbook: `!setAlertStatus status="Triage"` (custom) or `!setAlertStatus status="Resolved - Known Issue"` (built-in). `closeInvestigation closeReason=...` accepts free text but unrecognized values silently coerce to `Resolved - Other` (admin doc p. 739).

## 7. Incident Domains

A domain is a logical contextual boundary for routing, layouts, and RBAC (admin doc p. 580-582). Each incident and alert is assigned to exactly **one** domain at creation; the assignment is **immutable**.

Built-in: **Security**, **Health**, **IT**, **Hunting**. Custom domains added at Configurations → Object Setup → Incidents → **Domains** → +New Domain. A domain carries a name, color, optional description, allowed Statuses, and allowed Resolution Reasons.

Routing/RBAC effects:
- SBAC has a dedicated **Incident Domains** tag family. Scope users/groups by domain tag to gate visibility (User Groups → Scope).
- Layout rules, scoring rules, starring rules, and playbook triggers can filter on domain - primary mechanism for sending non-security work (Health, IT) to different layouts and analysts.
- **Cannot merge incidents across domains** and **cannot move alerts between incidents in different domains.**
- **SmartScore is Security-only.** Custom domains and Health/IT/Hunting do not get an ML score.
- **Alert grouping into incidents is also Security-only** for ML purposes - non-security domains rely on rule-based grouping.
- Domain choice cascades into custom content: review playbook triggers, starring rules, notifications, alert exclusions, scoring rules, and any XQL hitting `incidents` / `alerts` datasets when adding a custom domain (admin doc p. 581).

Custom domains, like custom statuses, **cannot be deleted or renamed** after save - color and description are the only editable properties.

## Cross-references
- Analyst workflow on cases/issues: [case-ops.md](case-ops.md)
- Playbook authoring (timer tasks, custom field set, status transitions): [soar-automation.md](soar-automation.md)
- API surfaces (`update_incident`, `update_alerts`, custom fields): [xsiam-api.md](xsiam-api.md)
