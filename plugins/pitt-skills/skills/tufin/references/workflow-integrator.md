# Workflow Integrator (WFI) Reference

WFI is the Tufin Extension that wires SecureChange workflows to ITSM and other REST-capable systems without writing custom mediator scripts. Free with SecureChange+. The intended path for ServiceNow integration at most CDW-equivalent shops.

## What WFI Is and Is Not

**Is:** A no-code/low-code integration engine that turns SecureChange workflow events into outbound REST calls and maps responses back into SecureChange ticket fields. JSON request/response, placeholder substitution, optional emails before and after the request.

**Is not:** A general-purpose ETL or scheduler. Every action fires off a SecureChange workflow event. Cannot run independently of a workflow.

**Replaces:** Hand-rolled custom workflow scripts via the mediator pattern, for the common case of "post ticket data to my ITSM and update ticket fields with the response." Mediator is still the right tool for arbitrary logic, multi-step orchestration, or when you need code in the path. WFI is the right tool when the integration is a clean request/response over JSON.

## How It Works

1. Define an **outbound server** (the ITSM endpoint). One default per workflow; can override per integration point if you have multiple targets.
2. Pick a SecureChange workflow.
3. For each place in that workflow where you want to call the ITSM, define an **integration point**. Bind it to a step or a workflow trigger.
4. Write a JSON body with `#placeholder#` substitutions for ticket data.
5. Optionally write a response mapping (ITSM JSON to SecureChange field placeholders).
6. Optionally configure a custom email before and after the request.
7. Enable.

The mediator that ships with WFI runs inside the SecureChange pod, parses the JSON template, resolves placeholders, sends the request, and pushes the response into ticket fields.

## Outbound Server

Configured in the WFI Server menu. Required for any integration point that talks to a remote system. One row per ITSM instance. Servers carry: base URL, authentication (Basic, certificate-based), TLS settings.

If you have multiple ITSMs (production ServiceNow, a Jira sandbox, a partner API), define each as its own outbound server and override per integration point.

## Integration Point Types

For each integration point you choose between **step** and **trigger**.

### Step integration points

Bound to a specific workflow step. Three placement options:

| Placement | Fires when |
|---|---|
| **Inbound** | Actions first become available in the step. Use for fetching enrichment data before the handler sees the step. |
| **Outbound** | Actions are no longer available for the step (the step is exiting). Use for pushing status updates after handler work. |
| **Step Trigger** | A specific event happens inside the step. The only valid trigger on automatic steps is `Automation Failed`. |

Inbound integration points support `GET` (retrieve and apply to ticket fields) along with `POST` and `PUT`. Outbound and step-trigger integration points support `POST` and `PUT`.

### Workflow trigger integration points

Apply to the entire workflow regardless of step. Available triggers:

| Trigger | Fires on |
|---|---|
| `Autoclose` | Ticket is closed before reaching the last step (typically when fully implemented). |
| `Close` | Ticket is closed normally. |
| `Cancel` | Ticket is canceled. |
| `Reject` | Ticket is rejected. |
| `Redo` | Ticket is sent back to a previous step. |
| `Reopen` | Closed ticket is reopened. |
| `Pre-assignment script` | Fires before a step is assigned to a user. **Requires manual setup**: copy the path `/opt/tufin/extensions/workflowintegrator/bin/rest_integration` into the Assignments tab of the relevant SecureChange step. |
| `Automation failed` | An automatic step fails. |

If a step trigger and a workflow trigger conflict for the same event, WFI sends the **step** payload, not the workflow one.

## Integration Point Configuration

Per integration point, the configuration is in five rows.

### General

| Field | Notes |
|---|---|
| `Trigger Type` | Step triggers only. Choose which workflow event fires the request. Auto steps allow only `Automation Failed`. |
| `URL path` | Path on the outbound server. Empty = no remote request, action-only integration point. |
| `Request method` | `POST` (create), `PUT` (update), `GET` (retrieve, inbound only). |
| `Before request` | Predefined actions before the request: send email, advance ticket, do nothing if previous step skipped, etc. Runs even if URL path is empty. |
| `After request` | Predefined actions after the response: send email, advance, etc. |
| `Overwrite server` | Pick a non-default outbound server for this integration point. |

### Upstream to ITSM

JSON body sent to the ITSM. Placeholders are wrapped in `#hash#`. If a placeholder cannot be resolved, the literal `#hash#` is sent. Catch this in the receiver to detect missing data.

```json
{
  "ticket_number":     "#ticket_id#",
  "subject":           "#ticket_subject#",
  "requester":         "#ticket_requester_full_name#",
  "current_step":      "#step_name#",
  "ar":                "#ar_as_string#",
  "risk_results":      "#risk_status#",
  "designer_status":   "#designer_status#",
  "verifier_status":   "#verifier_status#",
  "comments":          "#latest_comment_content#"
}
```

### ITSM Response (inbound only)

JSON mapping that pulls fields out of the ITSM response and writes them back to ticket fields. Use the destination ticket field name as the placeholder.

```json
{
  "External Ticket ID":  "#result.itsm_id#",
  "External Status":     "#result.state#",
  "External Comment":    "#result.notes#"
}
```

The destination on the SecureChange side has to match an existing field name on the workflow.

### Email

Template for the email sent if `Before request` or `After request` includes a "send email" action. Uses the same placeholder syntax. Configure `Settings > Outgoing SMTP Server` for sending.

### Enable toggle

Off by default. Flip to On after testing.

## Predefined Placeholders

The `Info` menu in WFI lists these. They resolve from the ticket; field names also resolve as placeholders if they exist on the workflow.

### Ticket placeholders

| Placeholder | Returns |
|---|---|
| `ticket_id` | SecureChange ticket ID. |
| `ticket_subject` | Ticket subject. |
| `ticket_comments` | All ticket comments as JSON. |
| `latest_comment_content` | Most recent comment body. |
| `workflow_name` | Workflow name. |
| `ticket_requester` | Requester username. |
| `ticket_requester_full_name` | Requester full name. |
| `ticket_start_time` | Ticket start, format `Y/m/d H:M:S`. |
| `ticket_end_time` | Ticket end, format `Y/m/d H:M:S`. |
| `domain_name` | Ticket domain (Segregated mode only). |
| `ticket_task_url` | URL to the current task. |
| `assignee` | Current step assignee name. |
| `step_name` | Current step name. |
| `redo_reason` | Redo comment. Only valid with `REDO` trigger. |
| `reject_reason` | Reject comment. Only valid with `REJECT` trigger. |
| `automatic_step_failure_reason` | Auto-step failure description. Only valid with `Automation Failed`. |
| `current_time` | Date and time, format `YYYY-mm-dd HH:MM:00`. |
| `date_only` | Date only, format `YYYY-mm-dd`. |
| `current_step_id` | Current step ID if ticket is in progress. |
| `current_task_id` | Current task ID if ticket is in progress. |

### Field placeholders

| Placeholder | Returns |
|---|---|
| `approve_reject_reason` | Reason from Approve/Reject field. With `reject` from ticket-level rejection, the reject trigger must be set. |
| `approve_reject_status` | `Approved` or `Rejected`. Same caveat. |
| `selected_plus_options` | Selected options from a drop-down field. |
| `firewall_list` | Firewalls from the Access-Request field, structured as `{ 'AR1': ['device1', 'device2'] }`. |
| `ar_as_string` | Access requests rendered as readable text (Targets / Sources / Destinations / Services / Users blocks). |
| `gm_as_string` | Modify-Group request rendered as readable text. |

### Tool result placeholders

| Placeholder | Returns |
|---|---|
| `designer_commands` | Designer commands for FW-based commands. |
| `designer_status` | Empty string if Designer succeeded, `Error: Problem with Designer` if it failed. |
| `designer_results_json` | Designer results as JSON. |
| `risk_status` | `YES` if risk found, `NO` otherwise. |
| `risk_results` | JSON: `{ severity, violations: { sources, destinations, violating_services }, security_requirements: { policy, from_zone, to_zone, allowed_services } }`. |
| `verifier_status` | `Fully implemented` or `Not implemented`. |

## Custom Placeholders

When a predefined placeholder doesn't return what you need (different date format, derived field, computed value), drop a Python module on the WFI host.

### Mechanism

Create `custom_functions.py`. Each function takes a `ticket` object and returns a string. The function name becomes the placeholder name. WFI resolves custom placeholders before predefined ones, so naming a custom placeholder identical to a predefined one shadows the built-in.

```python
from datetime import datetime
from dateutil.tz import UTC

def ticket_utc(ticket, **kwargs):
    """Convert ticket.create_date to UTC ISO."""
    fmt = '%Y-%m-%dT%H:%M:%S.%f%z'
    dt = datetime.strptime(ticket.create_date, fmt)
    return datetime.strftime(dt.astimezone(UTC), '%Y-%m-%d %H:%M:%S')

def current_step_id(ticket, **kwargs):
    try:
        return ticket.get_current_step().id
    except Exception:
        return ''
```

### Deployment

```bash
mkdir -p /opt/tufin/extensions/workflowintegratorserver/plugins
cp custom_functions.py /opt/tufin/extensions/workflowintegratorserver/
chown -R tomcat:apache /opt/tufin/extensions/workflowintegratorserver
```

The directory ownership matters: SecureChange runs as the `tomcat` user and reads from this path through the WFI extension. Wrong ownership = silent placeholder resolution failures.

## Resolution Order

When WFI hits a `#name#` placeholder, it tries in this order:
1. Custom placeholder function in `custom_functions.py`.
2. Predefined helper placeholder.
3. Ticket field with that exact name.
4. If no match, the literal `#name#` is sent in the JSON.

Treat that fallback as a contract failure on the receiver side, not on Tufin. Validate inbound JSON before processing.

## Setting Up WFI

In `Settings`:
- **SecureChange connection**: WFI needs API credentials to read workflows and write back to fields. Use a dedicated service account, scoped to the workflows it operates on.
- **Outgoing SMTP server**: required if any integration point sends emails.
- **Log levels**: for debugging. Bring up to DEBUG only while testing; revert to INFO or WARN in steady state.

If logged into SecureTrack, you are auto-logged into WFI.

## ServiceNow-Specific Patterns

### One-way: SecureChange to ServiceNow updates

Ticket Status step, outbound integration point, `PUT` to a custom Scripted REST API on ServiceNow.

URL path: `/api/y_tufin_tufin_app/risk_status` (matches the example in Tufin docs).

```json
{
  "tufin_ticket": "#ticket_id#",
  "subject": "#ticket_subject#",
  "step": "#step_name#",
  "risk_status": "#risk_status#",
  "risk_results": "#risk_results#",
  "ar_summary": "#ar_as_string#",
  "verifier_status": "#verifier_status#"
}
```

After Request: Advance the ticket to the next step.

ServiceNow side: a Scripted REST API endpoint maps the payload onto a custom CHG/INC field set; a Business Rule triggers downstream notification or approval.

### Two-way: ServiceNow approval gate

ServiceNow handles the change-approval workflow; SecureChange holds the ticket until ServiceNow returns approval.

1. Outbound step integration point on the "Awaiting Approval" step. POSTs to ServiceNow to create the CHG. Includes Tufin ticket ID for callback.
2. ServiceNow CHG approval flow runs.
3. On approval, ServiceNow PUTs back to SecureChange via the standard REST API (not WFI; WFI is outbound from Tufin). Update the ticket's "Approval Status" field via `/securechangeworkflow/api/securechange/tickets/{id}/steps/...`.
4. A SecureChange ticket-update event fires; the Tufin workflow advances on field change.

For this you need both WFI (Tufin to ServiceNow) and ServiceNow's outbound REST scripting (ServiceNow to Tufin). Tufin's marketplace ServiceNow Connector ships some of this scaffolding; check before reinventing.

### Linking ticket IDs in the rule trail

Beyond WFI, configure SecureTrack `Settings > Configuration > Ticket Mapping`:
- **Automatically Link Revisions to SecureChange Tickets**: links rule changes to the ticket that authorized them.
- **Ticket ID Pattern (regex)**: case-sensitive regex matching ServiceNow CHG IDs in rule names or comments. Example: `^(CR|CHG)\d+$`.
- **Link Ticket IDs to Ticketing System**: URL pattern to make ticket IDs in the rule view clickable.

Pattern matching only happens when new revisions arrive. Changes to the regex re-match on the next revision and update `Last Modified Date` on affected rules. Don't churn the regex.

## Limits and Behaviors

- WFI sends the JSON template literally if a placeholder cannot resolve. The receiver must reject `#name#`-style strings.
- Step integration points fire on every entry (Inbound) or exit (Outbound) of the step. If a ticket bounces between steps via Redo, you get repeated fires. Deduplicate on the receiver.
- Auto steps can only have step-trigger integration points, and the only allowed trigger is `Automation Failed`.
- Pre-assignment script triggers require copying `/opt/tufin/extensions/workflowintegrator/bin/rest_integration` into the SecureChange step's Assignments tab. Forgetting this is the single most common WFI configuration mistake.
- WFI does not retry failed outbound requests. Receiver must be idempotent or implement its own retry queue.
- Custom emails through the WFI flow respect the same SMTP server, sender, and signing as native SecureChange emails.

## When to Pick WFI vs. Mediator vs. Native REST vs. MCP Tool

| Scenario | Pick |
|---|---|
| Push ticket data to ITSM, update fields from response | WFI |
| Trigger a vendor-specific webhook on ticket events | WFI |
| Send a templated email on workflow events | WFI |
| Run multi-step logic across multiple systems per event | Mediator (custom workflow script) |
| Conditional branching on Designer error codes | Mediator |
| Initiate Tufin tickets from a SOAR | Native REST POST to `/tickets` |
| Bidirectional sync with custom transformation logic | Combination: WFI outbound + native REST inbound |
| Quick prototype with arbitrary code | Mediator |
| Expose Tufin to an LLM agent or assistant | MCP server wrapping the REST API (see `soar-integration.md` and `mcp-builder` skill) |

WFI is configured by the platform admin (NetSec at CDW). When admin'ing WFI, treat the JSON templates as code: source-control them, review changes, and test in a non-prod workflow before enabling on production tickets.
