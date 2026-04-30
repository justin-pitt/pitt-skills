# Endpoint Protection - Profiles, Exceptions, Hardening

The largest single section of the XSIAM admin doc (~p. 10015 onward). Covers what the Cortex XDR agent does on a host, how to configure it via profiles, and how to suppress noise via the multiple exception/exclusion mechanisms. Most "I'm seeing too many alerts" or "production app got blocked" tickets land here.

## Module map (admin doc p. 10031-10620)

| Module | What it stops |
|---|---|
| **Malware protection** | Known malware via signatures + ML (WildFire); ransomware behaviors |
| **Exploit protection** | Memory-corruption exploits, exploit techniques on protected processes (browser, Office, etc.) |
| **Restrictions prevention** | Application controls - block scripts, USB, processes by hash/signer/path |
| **Behavioral Threat Protection (BTP)** | Behavioral patterns flagged by the agent independent of cloud analytics |
| **Wildfire analysis** | File-reputation lookup; cloud sandbox detonation for unknown files |
| **Disk encryption** | (admin doc p. 3.2.1.1.5+) BitLocker/FileVault enforcement |
| **Host firewall** | OS-level firewall rule enforcement |
| **Device control** | USB / removable media policy |
| **Host inventory** | Asset discovery from the agent |
| **Vulnerability assessment** | CVE inventory + risk scoring |

Modules are configured via **profiles** (one profile per module type) which are then applied to **endpoint groups** via **policy rules**.

## Profile types (admin doc p. 12226+)

- Malware prevention profile
- Exploit prevention profile
- Agent settings profile (logging, comms, agent-side toggles)
- Restrictions prevention profile
- Exception profiles + rules (see next section)

Default profiles are locked. Clone a default → edit the clone → assign via policy rules.

## Exception mechanisms - six different ones, pick the right one

XSIAM has **six** distinct ways to suppress an alert or relax prevention. They overlap. Picking the wrong one is a common mistake.

| Mechanism | What it does | When to use | Where to configure |
|---|---|---|---|
| **Alert exclusion** | Suppresses alerts matching criteria from XSIAM display + storage. Agent still raises and acts on them locally. (admin doc p. 16307-16316) | Tuning out noisy detections that don't need analyst attention | Settings → Exception Configuration → Alert Exclusions |
| **IOC / BIOC rule exception** | Stops a specific IOC or BIOC rule from matching on specific endpoints/users/processes | Targeted noise from one rule | Settings → Exception Configuration |
| **Disable prevention rule** | Lets the agent detect but not block the matched activity | Production app being killed by malware module - keep visibility, drop the kill | Settings → Exception Configuration |
| **Disable injection and prevention rule** | Same as above PLUS skips agent process injection on the target | Compatibility with apps that don't tolerate Cortex injection | Settings → Exception Configuration |
| **Support exception rule** | Modifies module behavior beyond what UI offers; restricted to Palo Alto support | Engaged via support ticket only | Set by Palo Alto support |
| **Legacy exception rule** | Pre-migration exception format. Continues to function; new ones discouraged | Existing tenants pre-2024 migration | Profiles → Exception |
| **Global endpoint policy exception** | Centralized exception that applies across multiple profiles | Tenant-wide rule that should bypass per-profile config | Settings → Exception Configuration |

**Exception vs Alert Exclusion** (admin doc p. 76984-76988): Exceptions remove an item from baseline evaluation (folder, path, or whole module). Alert Exclusions suppress an alert post-detection - agent still detects/acts, just doesn't surface in XSIAM. **Pick exclusion if the agent should keep working; pick exception if you need to relax the agent's behavior.**

## Endpoint hardening (admin doc p. 3.2.1.6 area)

- **Host firewall** - OS firewall rule enforcement via agent settings profile
- **Disk encryption** - Windows BitLocker / Mac FileVault enforcement + recovery key escrow
- **Host inventory** - what's installed (apps, services, accounts, autoruns)
- **Vulnerability assessment** - CVE matching against installed inventory; ITM add-on adds risk scoring (see `identity-threat.md`)
- **Device control** - USB removable-media policy

## Endpoint groups + policy rules

Profiles attach to endpoints via **endpoint groups** + **policy rules**. Endpoint groups can be:
- Static membership (manually assigned hostnames)
- Dynamic membership (filter expressions on endpoint attributes)
- AD-aware (if Cloud Identity Engine is set up - see `identity-threat.md`)

Policy rules order matters - first match wins. The default policy applies if nothing else matches.

## Operational gotchas

- **Default profiles are locked** - you must clone before editing. The clone retains "default-derived" badge in UI for traceability.
- **Alert exclusion doesn't stop the agent** - agent still takes the configured action (block/quarantine) on the endpoint. This is good for prevention, surprising for noise tuning if you assumed the action also stops.
- **Disable prevention is dangerous if scoped wrong** - over-broad disable rules on `*.exe` paths effectively disable the malware module. Use specific `--actor_process_image_path` and `--causality_actor_process_image_path` filters.
- **Support exceptions are NOT user-editable**. If support adds one for you, document the ticket # in your tenant change log so future engineers know it exists.
- **Legacy exceptions still fire** post-migration but the migration UI may say "all exceptions migrated." Check both surfaces.
- **Endpoint group membership is evaluated periodically**, not in real time. Newly-onboarded endpoints can sit on the default policy for minutes before group assignment.
- **Profile changes require agent check-in** to take effect. Agents check in every ~5 minutes by default; if you need immediate enforcement, force-check-in via Action Center.
- **Disabling injection** breaks several detection capabilities - don't do it for general noise, only for actual app compatibility issues.

## API surface (read)

- `/endpoints/get_endpoints`, `/endpoints/get_all`, `/endpoints/get_filtered_endpoints` - endpoint inventory
- `/endpoints/get_endpoint_policy` - single endpoint's effective policy
- `/agent_tags/assign` / `/agent_tags/remove` - manipulate endpoint group membership via tags
- `/endpoints/update_agent_name`, `/audits/agents_reports`
- `/device_control/get_violations` - USB/removable-media policy hits
- `/vulnerabilities/get_vulnerabilities`, `/vulnerabilities/get_vulnerability_tests`, `/vulnerabilities/bulk_update_vulnerability_tests` - vuln management surface

The public API doesn't currently expose **policy CRUD** (assign profile to endpoints), **profile CRUD** (create/edit malware/exploit profiles), or **exception CRUD** (alert exclusion list, disable-prevention rules) - these are UI-only today and a known gap.

## Cross-reference

- `case-ops.md` - Action Center for force-check-in, isolate, scan
- `identity-threat.md` - vulnerability assessment + risk scoring (ITM add-on)
- `attack-surface-mgmt.md` - separate concept (external surface vs endpoint surface)
- `data-pipeline.md` - XDR Agent telemetry datasets (`xdr_data`) feeding detection
