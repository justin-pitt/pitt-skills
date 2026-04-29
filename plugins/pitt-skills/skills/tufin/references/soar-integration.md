# Tufin SOAR and Automation Integration Patterns

How to wire Tufin into security automation. Covers the XSOAR Tufin pack, the Tines/Torq webhook patterns, ServiceNow Workflow Integrator, and the EDA-team-relevant playbooks.

## Why Tufin is in Your SOAR Toolchain

Two value propositions for SOC and security automation:

1. **Enrichment.** Tufin knows the network better than any other tool. Path analysis answers "can this attacker actually reach that asset?" before the SOC escalates. Zone lookup answers "what's the blast radius if this IP is compromised?"
2. **Containment without ad-hoc firewall changes.** Submitting a SecureChange ticket from a SOAR playbook gives you topology-aware blocking with risk analysis, change tracking, and audit. Beats SSHing into firewalls.

For a CISO mandate of "capability over visibility," Tufin is a capability-enabler at the network layer. Every detection that produces an IOC IP can route through Tufin to ask the network: enrich + contain.

## XSOAR Tufin Pack

Available on Cortex XSOAR Marketplace. Tested with TOS 19.3 originally; works with current versions including R25-1. Configure under `Settings > Integrations > Servers & Services`.

### Configuration parameters

- TOS IP or FQDN
- TOS user credentials (Basic Auth)
- Trust any certificate (lab only; do not enable in prod)
- Use system proxy settings
- Maximum number of rules returned from device during a policy search

### Commands

| Command | Purpose | Required args | Optional args |
|---|---|---|---|
| `tufin-search-topology` | Path analysis (text result) | `source`, `destination` | `service` |
| `tufin-search-topology-image` | Path analysis (image) | `source`, `destination` | `service` |
| `tufin-object-resolve` | Resolve IP to network object | `ip` |  |
| `tufin-policy-search` | Free-text policy search across devices | `search` |  |
| `tufin-get-zone-for-ip` | Map IP to its Tufin zone | `ip` |  |
| `tufin-submit-change-request` | Open a SecureChange ticket | `request-type`, `priority`, `source`, `subject` | `destination`, `protocol`, `port`, `action`, `comment` |
| `tufin-search-devices` | List devices | (any of) `name`, `ip`, `vendor`, `model` |  |
| `tufin-get-change-info` | Get a SecureChange ticket | `ticket-id` |  |
| `tufin-search-applications` | SecureApp app search | (any of) `name` |  |
| `tufin-search-application-connections` | App connections | `application-id` |  |

### Context outputs (key paths)

```
Tufin.Topology.TrafficAllowed       boolean
Tufin.Topology.TrafficDevices       string (path)
Tufin.ObjectResolve.NumberOfObjects number
Tufin.Policysearch.NumberRulesFound number
Tufin.Zone.ID                       string
Tufin.Zone.Name                     unknown
Tufin.Request.Status                unknown
Tufin.Device.{ID,Name,Vendor,Model,IP}
Tufin.Ticket.{ID,Subject,Priority,Status,Requester,WorkflowID,WorkflowName,CurrentStep}
Tufin.App.{ID,Name,Status,Decommissioned,OwnerID,OwnerName,Comments}
Tufin.AppConnections.{ID,Name,Status,Source.*,Destination.*,Service.*,Comment,ApplicationID}
```

### Policy search syntax (XSOAR `tufin-policy-search`)

Same syntax as the SecureTrack Policy Browser free-search. `field:value` for typed match, bareword for free text.

```
!tufin-policy-search search="source:192.168.1.1"
!tufin-policy-search search="destination:198.51.100.0/24 service:443"
```

### Submit-change-request patterns

```
# Add access
!tufin-submit-change-request request-type="Access Request" priority=High \
    source=10.5.5.5 destination=10.6.6.6 protocol=tcp port=443 action=Accept \
    subject="Allow app A to DB B"

# Containment via decommission
!tufin-submit-change-request request-type="Decommission Request" priority=High \
    source=192.168.1.1 \
    subject="This host is infected with ransomware"
```

### Built-in playbook

`Tufin - Enrich Source & Destination IP Information`: enriches an incident's source and destination IPs with associated zones, network objects, policy hits, and a topology image. Good starting point for SOC playbooks.

## Patterns for Tines and Torq

The XSOAR pack maps cleanly to Tines/Torq HTTP Request actions. For Tines specifically (CDW's POC):

### Tines: enrich-then-contain story

Story actions (in order):
1. **Receive Alert** (webhook trigger, e.g. from XSIAM).
2. **Tufin Path Query** (HTTP Request to `/securetrack/api/topology/path`).
3. **Decision**: traffic allowed?
4. **Tufin Submit Decommission Ticket** (HTTP Request POST to `/tickets`).
5. **Wait for Ticket Closure** (polling loop or page-driven hold).
6. **Update XSIAM Case** with Tufin ticket ID and final status.

Credential setup in Tines:
- Type: HTTP Request credential.
- Domain: TOS host.
- Auth: Basic, username/password.
- Allowlist the credential to specific Stories (Resources > Credentials > Limit access).

Use a dedicated SecureChange service account with minimum permissions for the workflows your Stories use.

### Torq: similar shape

Torq's HTTP integration handles Basic Auth and JSON natively. Same flow. Torq's case management can carry the Tufin ticket ID through the lifecycle.

### Webhook-back from Tufin

Tufin's mediator pattern (see `change-automation.md`) lets SecureChange events post into your SOAR. For Tines, expose a Tines webhook URL; configure a custom workflow script in SecureChange to POST ticket updates there. The mediator forwards ticket info as base64-encoded XML; your Tines Event Transform decodes it.

Sample mediator -> Tines webhook payload (after decode):

```xml
<ticket_info>
  <id>{{ ticket.id }}</id>
  <subject>{{ ticket.subject }}</subject>
  <current_stage>
    <name>Implementation</name>
    <ticket_task><handler><login>api</login></handler></ticket_task>
  </current_stage>
</ticket_info>
```

The transform: base64 decode `ticket_info` -> XML to dict -> dispatch on event type. Pass `SCW_EVENT` as a header from the mediator script.

## ServiceNow Integration

Tufin offers a **Workflow Integrator App** (free with SecureChange+) that bidirectionally syncs SecureChange tickets and ServiceNow records. Approvals, status, custom fields all sync via REST.

Without Workflow Integrator:
- ServiceNow ITSM as the requester surface; Tufin REST API as the implementation surface.
- A custom SecureChange workflow script posts ticket events to ServiceNow's Table API to update the parent CHG/INC record.
- ServiceNow business rules call SecureChange REST `/tickets` to open the change in Tufin when an INC moves to a containment state.

For CDW (ServiceNow IRM owner: Service Central): the Workflow Integrator App is the lower-friction path. Validate it carries through the IRM custom fields you need before committing.

## High-Value Automation Use Cases

### 1. Block-on-Detection (containment)

Trigger: high-confidence IOC IP from XSIAM, threat intel push, or detection rule.

Steps:
1. Tufin path analysis: is the IOC reachable to crown-jewel zones?
2. If reachable, submit a SecureChange Decommission ticket (or Access Request with action=Drop) targeting the IOC.
3. Workflow auto-runs Risk Analysis + Designer + Implementation if your workflow allows it.
4. Verifier confirms the block is in place on every relevant device.
5. SOAR poll the ticket; on closure update the case. Set ticket ID as case attribute for the audit trail.

Guardrails:
- Confidence threshold gate before Tufin call. False-positive blocks have real impact.
- Blast radius check: don't drop subnets when the IOC is a single host.
- Approval queue for Critical priority tickets (workflow-level dynamic assignment).
- Rollback path: SecureChange ticket history makes this clean. Re-open or open a reverse Access Request.

### 2. Vulnerability-Driven Access Removal

Trigger: vuln scanner reports critical CVE on an exposed asset.

Steps:
1. Pull vuln details (CVE, CVSS, affected service).
2. Tufin policy search for rules allowing the affected service to the asset.
3. Open Rule Modification or Decommission ticket(s) for the relevant rules.
4. Workflow runs through normal change automation.

Tufin's **Vulnerability-based Change Automation App (VCA)** does this end to end if you license it. For the EDA team running Rapid7/Tenable/Qualys, VCA is the simpler path. Without it, the playbook above replicates the value with more code.

### 3. SOC Enrichment Per Alert

Trigger: any case opens.

Steps:
1. Extract source/destination IPs from the alert.
2. `tufin-get-zone-for-ip` for each.
3. `tufin-search-topology` between them.
4. `tufin-policy-search source:<src> destination:<dst>` to find which rules apply.
5. Append zone names, topology image, and matching rules to the case.

Cheap and consistently useful. Good first Tufin playbook because it carries no risk of unintended change.

### 4. Bulk Recertification Reminder

Trigger: nightly scheduler.

Steps:
1. TQL query for rules with `certification.isExpired = true` or `timeCertificationExpiration before 30 days ago`.
2. For each rule, look up `businessOwner.email`.
3. Send a notification (Teams/email).
4. After N days without action, open a Rule Recertification ticket programmatically.

The **Rule Lifecycle Management (RLM)** extension does this natively. If you can deploy it, prefer it over a homegrown script. If not, this pattern works.

### 5. M&A Network Onboarding

Trigger: an acquired company is added to the M&A pipeline.

Steps (one-time per acquisition):
1. Create a network zone for the acquired CIDR space.
2. Build a scoped USP that expresses the integration-period segmentation rules.
3. Onboard the company's firewalls into TOS (native vendor or OPM agent).
4. Build SecureChange workflows scoped to the new zone for change automation.
5. Set up a daily report on USP violations against the new USP.

Continuous (per ticket):
- Every access request between the acquired zone and the corporate zone goes through the M&A workflow with required Risk Analysis and Verifier.

## Anti-Patterns

1. **Reading rules every minute.** TOS revisions change on device pull cadence. Querying every minute hits cache the same as every hour. Pull on demand or on revision-change webhook, not on a tight loop.
2. **Submitting tickets on every alert.** Without dedup, one IOC reused across 50 alerts opens 50 tickets. Cache the IOC -> ticket-ID mapping in your SOAR for the lifetime of the IOC.
3. **Treating Designer recommendations as final.** Designer is precise but sometimes wants to add a new rule when modifying an existing one is cleaner. Have a human review on `Critical` workflows.
4. **Hardcoding workflow IDs and field IDs.** They differ per environment and break on workflow revisions. Look them up at runtime via `/workflows`.
5. **One-off password rotation.** When the API service account password rotates, the user is forced through the UI password-reset flow on next login before any API works. Plan rotations.
6. **Skipping the audit trail.** Document automation actions in ticket comments. Tufin's audit trail captures the API call but not your intent. Future you needs the comment.
7. **Bypassing change windows.** Even auto-implemented tickets respect the SecureChange workflow. If your workflow has a manual approval step, automation will queue. Configure a "fast track" workflow with auto-implementation if you need true automated containment.
8. **Multi-tenancy assumptions.** In Multi-Domain TOS, every API call has an implicit domain context. Cross-domain reads need Super Admin. Single-domain code breaks when the deployment switches to multi-domain.

## Checklist for New Tufin Automations

- [ ] Dedicated service account, scoped permissions, password in vault.
- [ ] Workflow ID, step IDs, field IDs looked up at runtime, not hardcoded.
- [ ] Idempotency: rerunning the playbook with the same input doesn't open duplicate tickets.
- [ ] Confidence gating: high-impact actions (decommission, drop) require a confidence threshold or human approval.
- [ ] Rollback path documented and tested.
- [ ] Audit trail: ticket subject and comment include the source case ID, the playbook name, and the trigger reason.
- [ ] Failure mode: if Tufin is down or returns 500, the playbook surfaces this to the SOC, not silently swallows it.
- [ ] Rate limiting: handle 429s and 401s (session expiry) gracefully.
- [ ] Test in a non-prod TOS instance first, or use a test workflow that doesn't push to devices.
- [ ] Sign off from network team before automating any change that pushes to production firewalls.
