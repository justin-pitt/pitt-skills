# SecureChange: Workflows, Tickets, Designer/Verifier, Custom Scripts

Reference for change-automation work. Covers workflow types, the access-request data model, the auto tools (Designer, Verifier, Risk Analysis), the custom-script mediator pattern, and the ticket lifecycle.

## Workflow Types

SecureChange ships with several workflow templates. Each is bound to a workflow definition in `Settings > Workflows`. The **Submit Request** step is always first.

| Workflow Type | Use |
|---|---|
| **Access Request** | Add or remove access between a source and destination. The most common automation surface. Supports adding access, removing access, and combining both in a single ticket. |
| **Decommission Network Object** | Remove an IP from anywhere it appears (firewalls, groups, rules). Includes Designer and Verifier. |
| **Server Cloning** | Clone access from one server to another. |
| **Rule Modification** | Change source, destination, service, or comments on existing rules. |
| **Rule Recertification** | Periodic review and re-certification or removal of existing rules. |
| **Rule Decommission** | Disable or remove rules identified as unused, shadowed, or decertified. |
| **Group Modification** | Add, remove, or modify members of network object groups across devices. |
| **Generic Workflow** | Custom workflow with arbitrary fields. R25-1 has a redesigned UI for these including a Ticket Properties panel. |

Workflows are owned by Workflow Owners in `Settings > Workflows`. Requesters create tickets; Handlers process them.

## Workflow Steps

Each workflow has an ordered list of steps. Steps can be:

- **Manual** (assigned to a user or group, who handles tasks).
- **Auto** (Designer, Verifier, Risk Analysis, Target Suggestion, or Implementation run unattended).
- **Dynamic Assignment** (the system routes the task to a different group based on conditions: SLA status, Verification Status, Risk Status, Risk Severity, target devices, networks, labels, or any ticket field).

Per step you can enable:

- **Designer**: rule recommendations from topology and current rulebase.
- **Verifier**: confirms the change actually got installed on the device.
- **Risk Analyzer**: scores the request against the USP (or against a third-party tool).
- **Provisioning**: pushes the recommended change onto the device (Enterprise tier only).
- **Security Zones**: shows zones for source and destination. Disabled in Multi-Domain mode.
- **Import from other tickets**: lets a handler copy access requests from prior closed tickets.

## Access Request Data Model

The single most important field type in change automation. One Access Request field per ticket per step (multiple request patterns inside the field are fine). Carries forward across steps.

XML schema (also used in third-party risk-analysis input data):

```xml
<field xsi:type="multi_access_request">
  <name>ar</name>
  <access_request>
    <uuid>FIELD_UUID0</uuid>
    <order>AR1</order>
    <use_topology>true</use_topology>
    <targets>
      <target type="ANY" />
    </targets>
    <users>
      <user>Any</user>
    </users>
    <sources>
      <source type="IP">
        <ip_address>10.0.0.5</ip_address>
        <netmask>255.255.255.255</netmask>
        <cidr>32</cidr>
      </source>
    </sources>
    <destinations>
      <destination type="IP">
        <ip_address>198.51.100.10</ip_address>
        <netmask>255.255.255.255</netmask>
        <cidr>32</cidr>
      </destination>
    </destinations>
    <services>
      <service type="ANY" />
    </services>
    <action>Accept</action>
    <labels />
  </access_request>
</field>
```

Key points:

- `targets` accepts `type="ANY"` (Designer/topology picks), specific named devices (`Named_Access_Request_Device`), or a single `Any_Access_Request_Device`.
- `sources` and `destinations` accept types: `IP`, `IP_Range`, `Object` (existing SecureTrack object), `DNS`, `Internet`, `URL_Category`, `LDAP_Group`. Mix freely.
- `services` accepts `type="ANY"`, `Protocol` (with `protocol`/`port`), or `Predefined`.
- `action`: `Accept` or `Drop`. A decommission AR uses `Drop`.
- `use_topology` controls whether Designer auto-selects targets. False makes you specify targets manually.
- LDAP group sources cause behavior described in "Behavior for LDAP Objects in the Source Field" (used with NGFW user identity rules).

JSON shape mirrors XML; nested arrays for sources/destinations/services and singular `field.name`.

## Designer

Auto tool that recommends specific rule changes for an access request, using SecureTrack topology and the current rulebase. Per step you can scope what Designer is allowed to do:

| Capability | Effect |
|---|---|
| Allow design only | Generate recommendations. No write. |
| Allow update only | Save Designer recommendations to the device (provisioning-supported devices). |
| Allow commit only | Push policy from manager onto child firewalls (manager devices that support commit). |
| Allow design and update | Both. |
| Allow update and commit | Both. |
| Allow all | Everything Designer supports for this workflow's targets. |

Behaviors:

- Designer treats rules tagged `LEGACY` (via `automationAttribute`) as shadowed and avoids reusing them.
- Designer places new rules below the `STEALTH` section if one is defined.
- For URL categories in destination, Designer maps to the category's zone (Internet by default; configurable to internal via `Set Zone as URL Category Zone` REST API).
- For Palo Alto, Designer respects the `Applied to` field (R21-2+) when designing.
- For Azure NSGs with ASGs (R25-1), Designer can use ASGs in change suggestions.
- Designer is supported for OPM devices in access requests starting in R25-1.
- Vendor support is in the KC's "SecureChange Features by Vendor" page; do not assume support for a vendor without checking.

When Designer fails in an auto step, the default behavior is to notify and reassign to a handler. You can attach a custom script that inspects the Designer error code and decides whether to advance.

## Verifier

Confirms the requested patterns are actually implemented on the target device(s).

Statuses surfaced on the VER button:

- **Green**: implemented.
- **Yellow**: cannot run (configuration issue or unsupported target).
- **Red**: not implemented.
- **Manually verified**: handler asserted with explanation. The button shows a manual-verify variant.

Per-step settings:

- **Automatically run Verifier after this step**.
- **Do not proceed to next step if not verified**: blocks ticket advancement until success or manual verify.
- **Verify against (Check Point)**: `Saved policies` (changes saved on management) or `Installed policies` (changes saved AND installed on modules).
- For NGFW Application IDs on Palo Alto, Verifier considers the application identity itself; for other vendors it considers the underlying service.

## Risk Analysis

Scores the access request against a security policy. Two modes:

**1. USP-based (default).** Matches request traffic against SecureTrack zones and the USP matrix. Returns risk severity per request. Limitations: rule properties that violate USP are not surfaced as risk in this tool. URL categories use their mapped zone; Internet zone is the default for URL categories. If the USP only references specific subnets (not the whole zone), URL-category destinations will not produce a violation.

For Palo Alto applications, Risk Analysis treats group members as no risk if the USP contains either the parent application group or the member. There is no automatic translation between an application and its services; specify both in USP and request as needed.

**2. External (third-party) risk analysis.** Wire in a script that calls your own risk tool. Configured in `Workflow Properties > Enable external risk analysis`.

Input to the script (XML on stdin):

```xml
<field_info>
  <context xsi:type="ticket_draft" />
  <field xsi:type="multi_access_request"> ... access requests ... </field>
</field_info>
```

Required output (XML on stdout):

```xml
<external_risk_analysis_result>
  <external_risk_analysis_result_for_fields>
    <external_risk_analysis_result_for_field>
      <field_uuid>FIELD_UUID0</field_uuid>
      <status>HAS_RISK</status>
      <score>6.3</score>
      <comment>Inbound rule contains risky service</comment>
      <detailed_report_url>https://example/risk/FIELD_UUID0</detailed_report_url>
      <severity>CRITICAL</severity>
    </external_risk_analysis_result_for_field>
  </external_risk_analysis_result_for_fields>
</external_risk_analysis_result>
```

You must return a result for every access request in the ticket. Mismatched count = error.

The RSK button shows green/yellow/red as with USP. Both modes can be enabled per workflow step.

Adjacent extensions:

- **Vulnerability-based Change Automation App (VCA)**: ranks rules that expose assets to known vulnerabilities; integrates with vuln scanners.
- **Vulnerability Mitigation App (VMA)**: tests proposed rules against vulnerability data before implementation.

## Provisioning

Enterprise tier only. Pushes Designer recommendations onto the device. The capability matrix is per-vendor and per-model. For some devices (Check Point, FMC, Panorama, FortiManager) provisioning means saving the policy on the manager; commit pushes it to the modules.

## Custom Workflow Scripts (Mediator Pattern)

In Aurora, SecureChange runs in a Kubernetes pod. Pods do not retain on-disk script changes across restarts, which breaks the legacy "drop a script in /opt/tufin and call it" model.

The current pattern: Tufin ships a **mediator script** that runs from the SecureChange pod and posts to an HTTPS endpoint outside the pod. Your actual logic lives behind that endpoint as a web service. The mediator forwards ticket info via base64-encoded XML. Your service decodes, processes, and calls back into SecureChange via REST to update fields, advance steps, etc.

### Trigger events (hooks)

| Event | Fires when |
|---|---|
| `CREATE` | Ticket is created. |
| `CLOSE` | Ticket is closed (success path). |
| `CANCEL` | Ticket is canceled. |
| `REJECT` | Ticket is rejected. |
| `ADVANCE` | Ticket advances to next step (the most common hook). |
| `REDO` | Step is sent back. |
| `RESUBMIT` | Ticket is resubmitted. |
| `REOPEN` | Closed ticket is reopened. |
| `RESOLVE` | Ticket is resolved. |
| `PRE_ASSIGNMENT_SCRIPT` | Runs before a step's task assignment is finalized. |

Auto-step events: `TARGET_SUGGESTION_STEP`, `VERIFIER_STEP`, `DESIGNER_STEP`, `RISK_STEP`, `IMPLEMENTATION_STEP`.

The triggering event is exposed to the script in the `SCW_EVENT` environment variable.

### Configuration steps (high level)

1. Stand up your web service somewhere reachable from the pod (typically on the TOS host or an adjacent VM).
2. Install/enable the mediator script in TOS. Tufin ships it; configure its full path via the internal config API:
   ```
   curl -k -X PUT -u <user>:<pass> \
     "https://<TOS>/securechangeworkflow/api/securechange/internal/configuration/set?insert=true&key=webHookMediatorScriptFullPath&value=/opt/tufin/data/securechange/scripts/mediator.sh"
   ```
3. Whitelist your web service's destination via `webHookMediatorScriptWhitelist`:
   ```
   curl -k -X GET -u <user>:<pass> \
     "https://<TOS>/securechangeworkflow/api/securechange/internal/configuration/load?key=webHookMediatorScriptWhitelist"
   ```
4. In SecureChange UI: `Settings > SecureChange API > Add Script`. Set the Full Path (the path on the host outside the pod where your script lives), pass any args, click Test, save.
5. Bind the script to a workflow + event combination.

### Script input format

The mediator passes ticket info as base64-encoded XML on the request body (key `ticket_info`). Decode, parse, act.

```xml
<ticket_info>
  <id>64</id>
  <subject>example</subject>
  <priority><id>3</id><name>Normal</name></priority>
  <createDate>1704707276656</createDate>
  <updateDate>1704707524268</updateDate>
  <requester><id>4</id><login>api</login><display_name>api api</display_name></requester>
  <current_stage>
    <id>253</id>
    <name>example_step</name>
    <ticket_task><id>253</id><name>Default</name>
      <handler><id>4</id><login>api</login><display_name>api api</display_name></handler>
    </ticket_task>
  </current_stage>
  <open_request_stage>...</open_request_stage>
  <comment xsi:type="...">...</comment>
</ticket_info>
```

### Skeleton: Python web service that receives ticket events

```python
# Trigger service: receives base64 XML from the SecureChange mediator,
# pulls the full ticket via REST, and acts on it.
import base64, asyncio, os
from xml.etree.ElementTree import fromstring
from fastapi import FastAPI, Request
import httpx

SC = os.environ["SC_URL"]                # e.g. https://tos/securechangeworkflow/api/securechange
AUTH = (os.environ["SC_USER"], os.environ["SC_PASSWORD"])
app = FastAPI()

async def get_ticket(client, ticket_id):
    r = await client.get(f"{SC}/tickets/{ticket_id}.json")
    r.raise_for_status()
    return r.json()

async def update_field(client, ticket_id, step_id, task_id, field_id, new_value):
    payload = {"field": {"id": field_id, "text": new_value}}
    r = await client.put(
        f"{SC}/tickets/{ticket_id}/steps/{step_id}/tasks/{task_id}/fields/{field_id}",
        json=payload,
    )
    r.raise_for_status()

@app.post("/submit")
async def submit(request: Request):
    body = await request.form()
    raw = base64.b64decode(body["ticket_info"])
    info = fromstring(raw)
    ticket_id = info.findtext("id")
    event = os.environ.get("SCW_EVENT", "ADVANCE")

    async with httpx.AsyncClient(auth=AUTH, verify=True, timeout=30) as client:
        ticket = await get_ticket(client, ticket_id)
        # ... custom logic: enrich, validate, call other systems, update fields ...
    return {"ok": True}
```

Keep the mediator-side surface minimal. Heavy logic belongs in the trigger service. Treat scripts as standard application code: source control, code review, CI, no shell-on-VM cowboy edits.

### Custom-script guardrails

- Custom scripts cannot access the TOS database directly. Use the REST API.
- They must not impede TOS performance. Tufin Support may ask you to disable them during troubleshooting.
- pytos2 (Python SDK at `gitlab.com/tufinps/pytos2-ce`) is the supported way to write trigger-service code in Python.

## Ticket Lifecycle

States and operations:

- **Draft** -> **Open** (after submit)
- **Open** -> step-by-step progression. Each step is **In Progress** until handled, then advances.
- **Resolved**: handler marks complete (workflow-dependent).
- **Closed**: terminal success.
- **Canceled**, **Rejected**: terminal non-success.
- **Reopened**: returns to a prior step.

Operations the API exposes (and that hooks fire on):

- Reassign step to another user/group (`PUT /tickets/{id}/reassign`).
- Redo a step (`PUT /tickets/{id}/redo`).
- Cancel, reject, resolve (`PUT /tickets/{id}/cancel|reject|resolve`).
- History (`GET /tickets/{id}/history`).

## Inbound Mailboxes

Email-driven ticket creation. `Settings > SecureChange API > Add Mail` lets you create an inbound mailbox; emails to that address open tickets in the configured workflow. Useful when integrating with non-API-friendly systems, less useful when you own a SOAR platform.

## Decommission Workflow

The Rule Decommission workflow chains:
1. Search rules in SecureTrack Rule Viewer using TQL (e.g. `certificationStatus = 'DECERTIFIED'`).
2. Add to ticket cart, choose "disabled rules" or "remove rules."
3. Designer recommends the change.
4. Verifier confirms after implementation.

Often paired with the **Rule Lifecycle Management App (RLM)** extension, which automates recertification reminders and opens the decommission ticket when rules are decertified or expired.

## Rule Recertification

Workflow that periodically re-asserts ownership and need for a rule. The rule carries certification metadata (`certificationStatus`, `timeCertification`, `timeCertificationExpiration`, owner). Designer is **not** available in recertification workflows. The RLM extension drives this end-to-end.

## SLA Behavior (R25-1)

R25-1 added pause/resume/reset on ticket SLA. SLA can pause when waiting for non-handler users (requester, third party). Authorized users can pause manually; the SLA automatically resumes when the ticket advances. Useful when computing real handler-team SLA without external waits skewing it.

## Common Patterns

### "Drop traffic from this IP" auto-containment

For a SOAR playbook that wants to block an IOC at the firewall:

1. SOAR detects malicious source IP.
2. SOAR POSTs an Access Request ticket to SecureChange with `action: Drop`, `source: <ioc>`, `destination: ANY`, `service: ANY`, `use_topology: true`, priority `Critical`.
3. Workflow runs Risk Analysis (auto), Designer (auto), implements (auto if your workflow allows), Verifier confirms.
4. SOAR polls ticket for closure or final status, captures the ticket ID for the case.

### "Validate the request against a vuln scanner before approving"

Use the third-party Risk Analysis hook. Your script:

1. Reads `field_info` XML from stdin.
2. For each access request, queries your vuln scanner for the destination IP.
3. Returns an `external_risk_analysis_result` per access request with `HAS_RISK` / `NO_RISK` and a severity.

### "Track every Tufin ticket as a SOAR case"

Hook on `CREATE`, `ADVANCE`, `CLOSE`. Mediator-side service translates each event into a SOAR API call to update the parent case. Don't try to manage state inside the mediator script; delegate to the SOAR.

### "Bulk close tickets that are already implemented"

Periodic job: query open tickets via REST, for each call Verifier (or query last Verifier result), if green, advance and close. The XSOAR `tufin-get-change-info` command is the inspiration but the same logic works in any SOAR.
