---
applyTo: "**"
description: Use whenever the user mentions Tufin, TOS, SecureTrack, SecureChange, SecureApp, USP, TQL, Tufin REST or GraphQL API, Designer, Verifier, access requests, policy violations, zone matrices, network zones, firewall rule cleanup, rule recertification, decommission tickets, topology map, path analysis, OPM agents, TufinMate, Workflow Integrator, or any policy-management or change-automation task involving Tufin. Also trigger when the user wants to write Tufin REST/GraphQL calls, build or modify SecureChange workflows, write TQL queries, design SOAR playbooks that pull policy or topology data from SecureTrack, automate access-request submission, integrate Tufin with ITSM (ServiceNow), SOAR (XSOAR, Tines, Torq), or SIEM, or integrate Tufin into M&A network onboarding. CDW currently runs TOS Aurora R25-1 PHF3.
---

# Tufin Orchestration Suite (TOS) Aurora

Reference skill for Tufin TOS R25-1 (CDW currently runs 25.1 PHF3). Covers the three platform components, the REST and GraphQL APIs, TQL, the Unified Security Policy, change automation, the Workflow Integrator extension, and integration patterns relevant to a security automation engineering team.

## Primary Use Cases

This skill exists to support two specific workstreams:

1. **Building a Tufin MCP server.** Wrapping the TOS REST and GraphQL surface as MCP tools so LLM agents (Claude Code, Claude in chat, automation pipelines) can query policy, run path analysis, search rules, open SecureChange tickets, and check ticket status. The XSOAR Tufin pack's 10 commands are a good MVP toolset; see `soar-integration.md` for the command surface and `api-reference.md` for the underlying endpoints. Pair this skill with the `mcp-builder` skill for MCP server scaffolding.
2. **Co-administering the on-prem TOS instance with Network Security.** NetSec owns the platform; the EDA engineer is helping admin it. Admin tasks in scope: API service accounts, RBAC, WFI configuration, custom workflow scripts, USP exception management, ticket mapping, audit log forwarding, integration with ServiceNow and SOAR. Out of scope for this skill: bare-metal install, version upgrades, backup/restore procedures, hardware (G4/G4.5 appliance) maintenance. Those live in the Tufin KC.

A community Tufin MCP server exists at `github.com/stonecircle82/tufin-mcp` (Python, FastAPI, RBAC, basic SecureChange + SecureTrack endpoint coverage). Worth reading before starting from scratch; may not match CDW's needs but useful as a reference implementation.

## Platform Overview

TOS Aurora is a Kubernetes-based platform with three logical products that share a common topology and policy model.

**SecureTrack (SecureTrack+ tier).** Continuous policy collection and analysis across firewalls, NGFWs, routers, switches, SDN, and cloud. Owns: device inventory, rule and revision history, the Cleanup Browser, the Rule Viewer, the USP and Violations browsers, network zones, topology, and the audit trail. This is where policy data lives.

**SecureChange (SecureChange+ tier).** Workflow engine on top of SecureTrack. Owns: ticket lifecycle, access-request workflows, Designer (recommends rule changes from topology), Verifier (confirms a change was implemented), Risk Analysis (scores against the USP), rule recertification, decommission workflows, and dynamic task assignment. This is where changes happen.

**SecureApp.** Application-centric view on top of the same data. Owns: applications, application connections, servers, application interfaces. Connections that change in SecureApp generate SecureChange tickets automatically.

**Provisioning** (push changes onto devices) is gated behind the **Enterprise tier**. Without it, Designer recommends but does not push.

## Architecture Notes That Matter for Automation

1. SecureChange runs in a Kubernetes pod and cannot retain on-disk script changes across restarts. Custom workflow scripts run via the **mediator** pattern: SecureChange calls an HTTPS webhook (the mediator) which executes the actual script outside the pod and posts results back through the REST API. See `change-automation.md`.
2. The TOS REST API enforces session duration limits (set centrally). Long-running automations need to handle 401 reauthentication, not assume sticky sessions.
3. SecureChange and SecureApp talk to SecureTrack through a dedicated service account configured in `Settings > General > SecureTrack`. That account must have **Super Admin** in SecureTrack for full functionality. Treat this as a privileged credential.
4. There are two separate API surfaces:
   - **REST**: legacy, well-documented, default response format is XML (request `Accept: application/json` to get JSON). Base paths: `/securetrack/api/`, `/securechangeworkflow/api/securechange/`, `/securechangeworkflow/api/secureapp/`.
   - **GraphQL**: newer, lives at `https://<TOS>/v2/api/sync/graphiql`. Filter syntax inside GraphQL queries uses TQL. Use this for read-heavy work that needs nested data in one round trip.
5. Authentication is HTTP **Basic Auth** for both API surfaces. There is no native API token. Account permissions in TOS define what the API call can do. Build a dedicated service account, do not reuse a human user.

## What Component Owns What

| Capability | Component | API Path |
|---|---|---|
| Device inventory, rules, revisions | SecureTrack | `/securetrack/api/devices`, `/securetrack/api/devices/{id}/rules` |
| Network objects, services | SecureTrack | `/securetrack/api/network_objects`, `/securetrack/api/services` |
| Network zones, zone subnets, security groups | SecureTrack | `/securetrack/api/zones` |
| Unified Security Policy (USP) and violations | SecureTrack | GraphQL preferred (`usps`, `violations`) |
| Topology and path analysis | SecureTrack | `/securetrack/api/topology/path`, `/securetrack/api/topology/path_image` |
| Cleanup (shadowed, redundant, unused) | SecureTrack | `/securetrack/api/cleanups` |
| Tickets, access requests, lifecycle | SecureChange | `/securechangeworkflow/api/securechange/tickets` |
| Workflows, ticket history | SecureChange | `/securechangeworkflow/api/securechange/workflows` |
| Designer / Verifier / Risk Analysis | SecureChange | embedded in ticket steps |
| Applications, connections | SecureApp | `/securechangeworkflow/api/secureapp/repository/applications` |
| Custom triggers (create/advance/close/etc.) | SecureChange | mediator script + Settings > SecureChange API |

## When To Use Which Reference File

- **references/api.md**: REST and GraphQL specifics. Authentication, base URLs, common endpoints with examples, pagination, JSON vs XML, GraphiQL console, the pytos2 SDK, error handling.
- **references/tql.md**: TQL syntax, all Rule Viewer fields, all Device Viewer fields, USP TQL, operator reference, common query recipes, IPv4/IPv6 search rules.
- **references/change-automation.md**: SecureChange workflow types, the access-request data model, Designer behaviors, Verifier statuses, Risk Analysis modes (USP and external), custom workflow scripts via the mediator, ticket lifecycle events, decommission and recertification workflows.
- **references/policy-compliance.md**: USP architecture, security zone matrices, network zones (Internet, Unassociated Networks, Users Networks), zone hierarchies, security groups, USP exceptions, violation calculation behaviors and limits, compliance framework templates (PCI DSS, best practices), Cleanup Browser cleanup IDs (C01-C15).
- **references/topology.md**: Topology map, path query mechanics, NAT simulation, blocked-status display, broken paths, generic routes, OPM agents and what features they support per tier, supported devices and vendors, R25-1-specific device support changes.
- **references/workflow-integrator.md**: WFI extension reference. Outbound servers, integration points (step inbound/outbound, step trigger, workflow trigger), full predefined placeholder list (ticket / field / Designer / Risk / Verifier), custom Python placeholders, ServiceNow integration patterns (one-way and two-way), ticket-mapping configuration, when to pick WFI vs. mediator vs. native REST vs. MCP tool.
- **references/soar-integration.md**: XSOAR Tufin pack commands (good starting point for MCP tool design), integration patterns for Tines and Torq, common automation playbooks (enrich-and-respond, contain-via-decommission, vuln-driven access removal), ServiceNow Workflow Integrator pointers, webhook patterns.

## Quick Decision Tree

- "I need to pull rules, devices, objects, or run a policy search" -> SecureTrack REST or GraphQL. Start in `references/api.md` and `references/tql.md`.
- "I need to file a ticket to add or remove access" -> SecureChange access request via REST POST to `/tickets`. Start in `references/change-automation.md`.
- "I need to react to a ticket event (validate, enrich, kick off external work)" -> Workflow Integrator if it's a clean JSON request/response to ITSM. Custom workflow script + mediator pattern if it needs arbitrary logic. Start in `references/workflow-integrator.md` or `references/change-automation.md` (Custom Scripts section).
- "I need to push SecureChange ticket data to ServiceNow on every step" -> Workflow Integrator. Start in `references/workflow-integrator.md`.
- "I need to expose Tufin to an LLM agent or assistant" -> Build an MCP server wrapping the REST endpoints. Start in `references/api.md` and `references/soar-integration.md` (the XSOAR command surface is the right MVP toolset).
- "I need to find what is allowed between A and B" -> Path analysis (topology) or policy analysis (rules). Start in `references/topology.md`.
- "I need to assert that traffic between zones is or is not allowed" -> USP matrix. Start in `references/policy-compliance.md`.
- "I need to identify cleanup candidates" -> Cleanup Browser + TQL on Rule Viewer. Start in `references/policy-compliance.md` (cleanup section) and `references/tql.md`.
- "I need to integrate Tufin with the SOC's playbooks" -> Start in `references/soar-integration.md`.

## Conventions Used Across References

- API examples use `<TOS>` for the SecureTrack/SecureChange host. SecureTrack and SecureChange may run on the same host or separate hosts depending on deployment.
- Examples use `application/json` even though the API defaults to XML. JSON requires explicit `Accept: application/json` (and `Content-Type: application/json` on writes).
- `curl -k` is used for brevity. Production automations should use a trusted CA bundle.
- Pagination uses `start` and `count` query parameters on REST. The response DTO includes a `total` field. GraphQL uses `first` and `offset` (max `first` = 500, default = 100).

## R25-1 Version Notes (CDW: 25.1 PHF3)

Items added or changed in R25-1 that touch automation work:

- **Arista EOS** is now first-class supported (visibility, topology, USP violations, Designer, Verifier).
- **Designer support for OPM devices** in access-request workflows (vendors integrated by Pro Services or partners).
- **Designer for Azure NSGs with ASGs** added.
- **USP violations for Azure NSGs** installed on subnets.
- **AWS Security Group unused-rules cleanup** via rule analytics and last-hit info.
- **Visibility and topology for NSX-T Gateway Firewalls.**
- **Topology and matching rules for Zscaler Internet Access (ZIA)** including GRE/IPSEC tunnels.
- **TufinMate** (AI assistant) GA. Three flavors: TufinMate for IT (Teams), for SOC (Microsoft Copilot for Security), for NetSec engineers (later in 2025).
- **Automatic MZTI (Map Zones To Interfaces)** for SecureTrack+ based on network configuration.
- **Pause/resume/reset ticket SLA.** SLA can now be paused while waiting on requesters or third parties.
- **Generic Workflow UX overhaul** with a Ticket Properties panel.
- **Comments in revision history** (editable for GCP, Meraki, Arista, OPM devices; read-only for others).
- **PHF1+: Zone-Based USP Exceptions.** Use entire zones as source/destination in USP exceptions via API.
- **PHF1+: Dynamic polling** intervals that adjust based on revision processing time.
- **AWS Internet Path support** via NAT Gateway in path analysis.

If you're working in an environment running PHF1+, USP zone-based exceptions and dynamic polling are both available; environments on PHF3 (e.g., CDW) get them by default. Confirm AWS NAT Gateway internet-path coverage if your onboarding work hits AWS-egress access requests (e.g., Mission Cloud-style integrations).

## What Is NOT Covered Here

- TOS installation, upgrade procedure, backup/restore. Search the Tufin KC directly.
- AKIPS by Tufin (separate product, network performance monitoring).
- Detailed device-onboarding instructions for specific vendors. The KC's "Features by vendor" page is authoritative.
- TufinMate prompt engineering. It is configured through the Management App, not through the API.
