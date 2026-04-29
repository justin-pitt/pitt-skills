# Topology, Path Analysis, and Device Support

Reference for SecureTrack's topology engine, path-analysis queries, the Open Policy Model (OPM), and device coverage.

## Topology Engine

SecureTrack builds a network topology by collecting routing tables, interfaces, NAT, and policy data from monitored devices. Both physical (firewalls, routers, switches) and virtual (cloud, SDN) devices contribute. The result is a graph used by:

- The Topology Map (UI).
- Path Analysis queries (REST + UI).
- Designer (target selection, change design).
- Verifier (which devices to verify on).
- Risk Analysis (zone determination).

### Topology features per source

- **Static and dynamic routes** are reflected in the map. Static routes may not appear in revisions but are used for path computation.
- **OSPF and BGP** are supported on Cisco ACI and other major routing platforms.
- **Policy-based routing (PBR)** is supported for Cisco IOS routers when the next hop is to a monitored device. R25-2 added generic PBR support across the topology map; in R25-1 PBR coverage is more limited.
- **NAT simulation** is on by default for path analysis, accounting for NAT translations between source and destination.
- **Cisco ACI**: path queries support EPG/ESG-qualified addresses (`1.1.1.1@EPG1`). uEPG and Contract Master are included in revisions and topology in current TOS versions.

## Path Analysis

Two tools live under "path analysis" - know which one you want.

### Map-based Path Analysis

Interactive on the Topology Map. Right-click a device, select Show Routes / Show Interfaces, or run a path query.

Modes:
- **Complete view**: full route across all hops.
- **Step-By-Step Analysis**: one hop at a time.
- **Trace Mode**: detailed hop-by-hop trace.

Display options:
- **Simulate NAT**: NAT-aware path computation.
- **Display Blocked Status**: marks devices that drop the traffic.
- **Show Broken Paths**: shows nodes even when the path doesn't reach the destination.

Performance tip: for repeated path queries you can suppress map rendering.

```
tos config set -p topology.map.lazy.rendering=true -s topology-facade
# ...run queries...
tos config set -p topology.map.lazy.rendering=false -s topology-facade
```

### REST Path Analysis

```
GET /securetrack/api/topology/path?
       src=<ip_or_subnet>&
       dst=<ip_or_subnet>&
       service=<proto>:<port>&
       includeBlockedStatus=true&
       simulateNAT=true&
       showBroken=true
```

Returns the devices and interfaces along the path, with blocked-status flags. The image variant returns a rendered SVG/PNG.

```
GET /securetrack/api/topology/path_image?src=...&dst=...&service=...
```

For ad-hoc traffic queries the UI is faster; for SOAR enrichment the REST endpoints are the right surface.

### Policy Analysis (rule-level, not topology-level)

Different tool. Returns the rules that match supplied flow on specific devices. No topology computation.

```
GET /securetrack/api/devices/{device_id}/policy_analysis?
       sources=Any&destinations=Any&services=Any&action=&exclude=
```

Use Policy Analysis when you already know the device(s) and want to know which rules match. Use Path Analysis when you don't know which devices are in the path.

## Topology Cloud Objects

Cloud topology surface for AWS VPCs, Azure VNets, GCP VPCs, etc.

```
GET /securetrack/api/topology_clouds
GET /securetrack/api/topology_clouds?name=<substring>
```

Pagination defaults: `start=0`, `count=50`.

## Generic Routes

Topology lets you add generic routes for cases where SecureTrack can't auto-detect routing (e.g. for routers it doesn't monitor). Right-click a monitored device > Show Routes > Add Generic Route. Useful around acquisitions where the acquired network's routers aren't onboarded yet.

## Open Policy Model (OPM)

OPM is an SDK for adding support for devices that TOS doesn't support out of the box. An OPM Agent translates between the device's native API and OPM's abstraction. TOS treats OPM-modeled devices as first-class for the features the agent implements.

### Architecture

- **Device**: physical or virtual device the customer wants TOS to monitor.
- **OPM Agent**: software (built by Tufin Pro Services or partners) that connects the device to TOS.
- **TOS Server**: the actual TOS cluster.

To onboard an OPM-modeled device, add it through the Device Viewer (`SecureTrack > Browser > Devices`).

### Feature support per tier (OPM devices)

Not every OPM agent implements every feature. The matrix:

| Tier | Use Case | OPM Support |
|---|---|---|
| SecureTrack+ | Policy Management | Device Viewer, Rule Viewer |
| SecureTrack+ | Compliance | Permissiveness, Violations |
| SecureTrack+ | Audit | Rule History, Revision History |
| SecureTrack+ | Cleanup | Rule Usage and Shadowing **not supported** |
| SecureChange+ | Path Analysis | Includes matching rules |
| SecureChange+ | Automatic Target Selection | Yes (topology-based) |
| SecureChange+ | Risk Analysis | Yes (USP-based) |
| SecureChange+ | Automation Design | Designer for adding access. Decommissioning **not supported.** |
| SecureChange+ | Automation Verification | Designer + Verifier for adding access; Verifier for decommissioning |
| Enterprise | Provisioning | **Not supported** for OPM. |

For OPM-specific support questions Tufin directs to `[email protected]` (informational, not technical support).

R25-1 added Designer support for OPM devices in access-request workflows: the agent's recommendations are surfaced in the same Designer flow as native vendors.

## Supported Vendors and Models

Authoritative source: the KC's "Features by vendor" page. Vendors and broad coverage:

- **Palo Alto Networks**: Panorama, PAN-OS firewalls. Full coverage for visibility, topology, USP, Designer, Verifier. Provisioning supported.
- **Check Point**: SmartCenter, MDS, CMA. Full coverage. Both Saved and Installed policy verification.
- **Cisco**: ASA, FMC/FTD, IOS routers, Nexus, Meraki (network and organization), ACI (with EPG/ESG path support). Cisco IOS PBR support.
- **Fortinet**: FortiGate, FortiManager.
- **Juniper**: NetScreen, NetScreen Cluster, SRX, MDS.
- **F5**: BIG-IP.
- **VMware**: NSX-T (Distributed FW, Edge, Gateway FW, Logical Router, Management), NSX-V, VMware Cloud on AWS, NSX-T in Azure VMware Solution (R25-1).
- **AWS**: AWS_ACCOUNT, AWS_TRANSIT_GATEWAY, AWS_GATEWAY_LOAD_BALANCER. Internet path via NAT Gateway (R25-1).
- **Azure**: AZURE_ACCOUNT, AZURE_FIREWALL, AZURE_LOAD_BALANCER, AZURE_POLICY, AZURE_ROOT_POLICY, AZURE_VHUB, AZURE_VNET, AZURE_VWAN. NSGs with ASGs in Designer (R25-1).
- **GCP**: GCP_PROJECT, GCP_VPC.
- **Zscaler**: Zscaler Internet Access. Topology + path analysis + last-hit info (R25-1).
- **Arista**: EOS and CloudVision Portal (R25-1, first-class).
- **Cisco IOS XE SDWAN**, **Stonesoft**, **Forcepoint**, **Barracuda**: included.

R25-1 specifically adds:
- Arista EOS first-class.
- NSX-T Gateway Firewall topology + USP.
- ZIA topology + last-hit info.
- AWS NAT Gateway Internet path.
- NSX-T in Azure VMware Solution.

For CDW's environment, the relevant devices are **Palo Alto NGFW** (full coverage, native), **Akamai** (not natively supported by Tufin; would need an OPM agent or excluded from TOS coverage). For the M&A flow, when an acquired company introduces a non-native vendor, the path is OPM agent (PS-developed) or onboarding the device's traffic via syslog only.

## Device API

```
GET    /securetrack/api/devices                  # list (paginated)
GET    /securetrack/api/devices?name=<substr>
GET    /securetrack/api/devices?vendor=<vendor>
GET    /securetrack/api/devices?model=<model>
GET    /securetrack/api/devices/{id}             # one device
POST   /securetrack/api/devices                  # add offline (manually fed) device
PUT    /securetrack/api/devices/{id}             # update offline device
DELETE /securetrack/api/devices/{id}
GET    /securetrack/api/generic_devices?name=<name>&context=<domain_id>  # OPM/generic device by name
GET    /securetrack/api/devices/{id}/revisions
GET    /securetrack/api/devices/topology_interfaces?mgmtId=<id>
```

Vendor and model filters use the same enum values as TQL `vendor` and `device.model`.

## R25-1 Topology and Visibility Highlights

- **NSX-T Gateway Firewall** topology and USP violation detection.
- **ZIA** topology including GRE/IPSEC tunnels to organizational locations. Path queries determine if traffic is allowed or blocked by ZIA filtering policy. Supports proxy-based monitoring.
- **AWS Internet Path Support** through NAT Gateway. Improves target selection for Internet Access Requests; improves verification of already-implemented access.
- **AKIPS by Tufin**: separate product for network performance monitoring (out of scope for this skill).
- **Arista EOS / CloudVision Portal**: device management via CVP eliminates per-device onboarding.
- **Encrypted syslog over TLS** for cloud deployments (TCP only). Valuable when running TOS Aurora in cloud and ingesting on-prem device logs.
- **Link redundancy on Tufin G4/G4.5 appliances**: dual-switch connectivity for survivability.
- **Dynamic polling** (PHF1+): TOS adjusts polling intervals based on revision processing time. Replaces fixed polling. Reduces backlog under heavy revision churn.

## Common Patterns

### Path lookup for SOC enrichment

```python
def is_allowed(src, dst, service):
    r = requests.get(
        f"https://{TOS}/securetrack/api/topology/path",
        params={"src": src, "dst": dst, "service": service, "simulateNAT": "true"},
        auth=(USER, PASS),
        headers={"Accept": "application/json"},
        verify=True,
    )
    r.raise_for_status()
    return r.json()
```

Pair this with the SOAR's IOC enrichment step. If `traffic_allowed` is true, raise the case priority; that means the indicator can already reach assets.

### Map source IP to its zone

```
GET /securetrack/api/zones_for_ip?ip=10.1.2.3
```

Or in TQL on the Zones screen:

```
subnets.ip = '10.1.2.3'
```

XSOAR's `tufin-get-zone-for-ip` wraps this.

### Find the firewall that would handle a flow

Use the path-analysis REST call. The response identifies devices in the path; the first device whose policy matches is the one Designer would target.

### Decide if a host is internet-exposed

Run path analysis with `src` set to the host and `dst` set to `0.0.0.0/0` (or use the Internet zone semantics). If the path reaches the Internet zone without being blocked, the host is reachable from inside-out; check the reverse direction for inbound exposure.
