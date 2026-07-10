# Engines - Runtime Substrate for Playbooks, Integrations, Scripts

Cortex XSIAM engines are remote-network proxy applications that run playbooks, scripts, integration commands, and analytics outside the tenant. Most "where does my Python actually execute?" questions resolve to "on an engine."

## What an engine is

A Linux daemon installed on a host inside your network. Communicates outbound (always client-initiated) to the XSIAM tenant on TCP/443. Pulls jobs (commands, integration calls, scripts) from the tenant, executes them locally, returns results. (admin doc p. 29407-29420)

## When you need one

| Scenario | Engine? |
|---|---|
| Integration that calls an internal-only API (Active Directory, internal Splunk, on-prem ServiceNow) | Yes |
| Integration whose vendor blocks calls from Palo Alto Cloud egress IPs | Yes |
| Heavy playbook workload that needs horizontal scaling (load-balancing group) | Yes |
| Integration that needs egress through a corporate web proxy that the cloud-side Palo can't reach | Yes |
| Plain SaaS integration (Microsoft Graph, AWS, GCP, etc.) | Optional |
| `Rasterize` integration (image rendering, blocked-by-corp-firewall scenarios) | Yes |

A single host can run **multiple engines** (Shell installation only) - useful for dev/prod separation on shared infrastructure. (admin doc p. 29407)

## Architecture

- **Container runtime**: Docker OR Podman. Shell installer auto-installs one; DEB/RPM/ZIP requires you to pre-install. (admin doc p. 5955-5956, 6034-6038)
- **Migration path**: Docker → Podman is documented (admin doc TOC p. 716). Relevant on RHEL 8/9 where Docker isn't supported and Podman is the default.
- **Listening**: Engine has no inbound port - outbound only.
- **Multi-engine load balancing**: An engine can be part of a load-balancing group. Engines in a group are not selectable individually for integration instances; you assign the group. (admin doc p. 29420)

## Hardware sizing (admin doc p. 29434+)

| Component | Dev minimum | Prod minimum |
|---|---|---|
| CPU | 8 cores | 16 cores |
| CPU arch | x86_64 only | x86_64 only |
| Memory | (see admin doc; depends on workload) | |
| Disk | 50 GB on `/var` partition recommended | |
| OS | Linux only - no Windows or Mac engine | |

## Lifecycle (admin doc sections 6.1.3-6.1.6)

- **Install** (p. 29513): Shell, DEB, RPM, or ZIP. Shell is most common - single-line installer, auto-resolves Docker/Podman.
- **Manage** (p. 30410): list engines, view status, view logs from the tenant UI.
- **Upgrade** (p. 30453): in-place via package manager or shell upgrade script.
- **Remove** (p. 30539): cleans up the daemon + container artifacts; orphaned containers occasionally need manual cleanup.

## Configuration: `d1.conf` (admin doc p. 30554-30620)

Engine config lives at `/usr/local/demisto/d1.conf` (or `/usr/local/demisto/<engine_name>/d1.conf` for multi-engine hosts; same folder as binary for ZIP installs).

Key properties:

| Property | Purpose |
|---|---|
| `http_proxy` / `https_proxy` | Route engine traffic through a corporate web proxy |
| `LogLevel` | `debug` / `info` / `warning` |
| `log.rolling.maxfilesize` | Log rotation size cap |
| `python.engine.docker` / `powershell.engine.docker` | Boolean - set to `true` once Docker/Podman is installed if it wasn't present at install time |

Shell-installed engines also accept JSON config edits via the tenant UI (Engines table → Edit Configuration). UI values override `d1.conf`.

## Use in integrations (admin doc p. 30826)

When configuring an integration instance, select an engine (or load-balancing group) from the dropdown. Without one selected, the integration runs on the tenant. Common pattern: Active Directory and on-prem-only integration instances pinned to a specific engine; SaaS integrations left tenant-side.

## Required egress URLs

Engines need outbound access to a fixed list of Palo Alto + Docker public registry URLs to pull images and communicate with the tenant. (admin doc p. 5997+) Document these in your firewall change-request before installation.

## Operational gotchas

- **Cron is a hard prereq** on the host. The installer doesn't install Cron itself.
- **Docker/Podman flag**: if you install via DEB/RPM/ZIP without Docker/Podman pre-installed, the engine config sets `python.engine.docker = false`. After installing the runtime later, **manually flip the flag** in `d1.conf` - the engine doesn't auto-detect.
- **Engines in a load-balancing group disappear from individual selection**. If a user reports "the engine is missing from my dropdown," check group membership first.
- **Multi-engine installs are Shell-only**. DEB/RPM/ZIP support one engine per host.
- **Outbound-only**: engines never accept inbound. Don't open inbound ports thinking it'll help; it won't.
- **Logs roll on `log.rolling.maxfilesize`**, default modest. Bump it before deep-debugging long playbook runs or you'll lose the trail.
- **Proxy quirks**: corporate MITM proxies that re-sign TLS may break Docker pulls. Workaround is usually to add the proxy CA to the engine's trust store, not to disable cert verification.

## Cross-reference

- `soar-development.md` - integration code conventions; integration instances pin to engines here
- `soar-automation.md` - load-balancing groups for high-volume playbook hosts
- `case-ops.md` - when an analyst's "Run command" hangs, engine availability is the first thing to check
