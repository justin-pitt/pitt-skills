# Tines Self-Hosted on Azure

Reference for deploying Tines self-hosted in Azure. Tines does not publish Azure-specific guidance directly — this doc translates the official self-hosted requirements (Docker Compose, AWS Fargate, Helm Charts) into Azure-native patterns. Validate specifics with a Tines SE during POC and architecture review.

---

## 1. Why Self-Hosted on Azure

Common reasons orgs go self-hosted in Azure rather than SaaS Tines:
- **Performance visibility** — backend metrics, traces, query performance directly observable; no waiting on vendor support to diagnose backend issues
- **Data residency control** — all customer data stays within your Azure subscription
- **Network integration** — direct VNet access to internal systems eliminates much Tunnel complexity
- **Compliance posture** — full ownership of audit logs, encryption, and access controls
- **Predictable cost model** — Azure consumption is forecastable; some SaaS pricing variability is removed

Trade-offs accepted:
- Customer responsibility for: infrastructure, upgrades, backups, scaling, certificate management
- Slower access to new features (must wait for self-hosted release lag, if any)
- More complex troubleshooting when issues span Tines + Azure infrastructure
- Internal expertise required for Postgres, Redis, AKS operations

---

## 2. Prerequisites

### From Tines
1. Engagement with Tines AE/CSM to enable self-hosted access
2. **Docker registry credentials** — Tines self-hosted artifacts are delivered as Docker images from a private registry
3. Helm Charts repository access
4. Image verification keys/process
5. Self-hosted licensing terms (separate from SaaS pricing)

### From your Azure tenant
1. Azure subscription with appropriate quotas
2. Resource Group structure (per environment: dev, staging, prod)
3. Entra ID integration for SSO
4. Network design approved (VNet, subnets, ingress, egress)
5. Backup tooling integration (Azure Backup, Veeam, etc.)
6. Observability stack (Azure Monitor, Container Insights, Log Analytics)
7. Identity strategy for AKS workload identity → managed identities
8. Certificate management (Azure Key Vault + cert-manager, or external CA)

---

## 3. Architecture (AKS + Helm)

### Component Stack
| Component | Azure Service | Notes |
|---|---|---|
| Tines application (web + worker pods) | AKS | Helm chart deploys these as Deployments/StatefulSets |
| **PostgreSQL ≥ 14.17** | Azure Database for PostgreSQL Flexible Server | Tines requires Postgres 14+. Hosted service strongly recommended. |
| **Redis 7.x** | Azure Cache for Redis | Used for sessions, job queues, cache. Hosted service strongly recommended. |
| Object storage | Azure Blob Storage | For files, attachments, exports |
| Ingress | Azure Application Gateway or AKS-managed NGINX/Istio | TLS termination, WAF if required |
| Identity | Entra ID + AKS Workload Identity | App auth + workload-to-Azure auth |
| Secrets | Azure Key Vault + Secrets Store CSI Driver | Pull secrets into pods without storing in Helm values |
| Container registry | Azure Container Registry (or pull through from Tines registry) | Optional cache; Tines images pull from their registry by default |
| SMTP | Azure Communication Services or external SMTP relay | For Send Email actions and platform emails |
| Monitoring | Azure Monitor + Container Insights | App metrics, container metrics, log forwarding |
| Backup | Azure Backup (for PostgreSQL) + Velero (for AKS state) | Postgres is the primary persistence — back it up religiously |

### Reference Topology

```
┌─────────────────────────────────────────────────────────────┐
│ Azure Subscription                                          │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ VNet                                                 │   │
│  │                                                      │   │
│  │  ┌───────────────┐   ┌──────────────────────────┐    │   │
│  │  │ App Gateway / │──▶│ AKS Cluster              │    │   │
│  │  │ Front Door    │   │  - tines-web pods        │    │   │
│  │  └───────────────┘   │  - tines-worker pods     │    │   │
│  │         ▲            │  - tines-tunnel (optional)│   │   │
│  │         │            └────────┬─────────────────┘    │   │
│  │   inbound HTTPS              │                       │   │
│  │                              │                       │   │
│  │                       ┌──────▼───────┐               │   │
│  │                       │ Private      │               │   │
│  │                       │ Endpoints    │               │   │
│  │                       └──┬─────┬─────┘               │   │
│  │                          │     │                     │   │
│  │           ┌──────────────▼─┐ ┌─▼──────────────────┐  │   │
│  │           │ Azure DB for   │ │ Azure Cache for    │  │   │
│  │           │ PostgreSQL FX  │ │ Redis              │  │   │
│  │           └────────────────┘ └────────────────────┘  │   │
│  │                                                      │   │
│  │           ┌────────────────────────────────────┐     │   │
│  │           │ Blob Storage (private endpoint)    │     │   │
│  │           └────────────────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Outbound: NAT Gateway → vendor APIs (CrowdStrike, Entra,   │
│            Akamai, ThreatConnect, etc.)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Sizing Guidance

Tines publishes deployment tiers (small / medium / large / enterprise) with recommended CPU, memory, DB sizing, and Redis sizing. Specific values are gated behind self-hosted access — confirm during the POC with the Tines SE.

### Translating to Azure SKUs (rough starting points — validate)

| Tines Tier | AKS Node Pool | PostgreSQL FX | Redis Cache |
|---|---|---|---|
| Small (eval / pilot) | 2-3× Standard_D4s_v5 (4 vCPU, 16 GB) | General Purpose, 2 vCore, 8 GB | Standard C1 (1 GB) |
| Medium (production base) | 3-4× Standard_D8s_v5 (8 vCPU, 32 GB) | General Purpose, 4 vCore, 16 GB | Standard C2 (2.5 GB) |
| Large | 5-8× Standard_D16s_v5 (16 vCPU, 64 GB) | Memory Optimized, 8 vCore, 64 GB | Premium P1 (6 GB) |
| Enterprise | Multiple node pools, autoscaling | Memory Optimized, 16+ vCore, 128+ GB | Premium P2+ (13+ GB) |

**Real sizing depends on:**
- Concurrent Story runs at peak (correlates with worker pod count)
- Daily action execution volume (correlates with DB write rate)
- Average event payload size (correlates with DB size and Redis cache pressure)
- Number of users with concurrent UI sessions

Get the Tines SE to model your actual workload before finalizing SKUs.

---

## 5. Networking

### Inbound
- App Gateway or Front Door for TLS termination, WAF (if required)
- Restrict to corporate IP ranges via NSG or App Gateway WAF rules (mirrors Tines IP access control)
- Consider Private Endpoint to expose Tines only to your internal network if no external access is needed

### Outbound
- Tines self-hosted needs outbound access to:
  - Tines Docker registry (image pulls and updates)
  - Vendor APIs called by HTTP Request actions (CrowdStrike, Entra, ThreatConnect, etc.)
  - AI provider APIs (if using non-Tines models)
  - SMTP server
- Recommended: NAT Gateway with deterministic egress IP for vendor allowlisting
- Use **Action Egress Control** (built into Tines admin) to allowlist outbound destinations from within Tines as defense-in-depth

### Internal connectivity
- AKS pods → Postgres / Redis / Blob Storage via Private Endpoints (recommended over public endpoints with firewall rules)
- AKS workload identity for Azure Storage access (no static keys)

### Tunnel
For systems Tines can't reach via VNet:
- Deploy Tines Tunnel container in target network
- Tunnel establishes outbound TLS connection to Tines tenant
- For an Azure-native deployment, often unnecessary — VNet peering and ExpressRoute reach most internal targets directly. Tunnel is more relevant for: acquired-company networks during M&A integration, partner networks, isolated environments without VNet peering

---

## 6. Identity and Access

### User authentication
- **Entra ID SSO via SAML or OIDC** — recommended primary auth
- JIT user provisioning on first SSO login
- SCIM for full user lifecycle automation
- Recovery codes for emergency admin access
- Email-based login disabled for production (force SSO)

### Workload identity
- **AKS Workload Identity** for Tines pod → Azure resource auth (Postgres, Redis, Blob, Key Vault)
- No static credentials in Helm values — pull from Key Vault via Secrets Store CSI Driver
- Service principal or managed identity per Tines component

### Tenant-level access controls
- **IP access control** (Tines built-in) — restrict who can reach the tenant by source IP
- **Custom roles** for fine-grained team-level permissions
- **Audit logs** forwarded to Log Analytics for SIEM ingestion

---

## 7. Observability

### What Tines exposes
- Prometheus-compatible metrics endpoints (verify with Tines SE)
- Structured application logs (stdout)
- Health check endpoints for K8s liveness/readiness probes
- Tunnel exposes its own health and metrics

### Recommended Azure stack
- **Container Insights** (Azure Monitor for containers) — pod metrics, container logs
- **Log Analytics Workspace** — centralized log store
- **Azure Monitor Workbooks** — Tines-specific dashboard views
- **Application Insights** — if instrumenting custom probes
- Forward Tines audit logs to your SIEM of record (Microsoft Sentinel is the natural fit on Azure-native deployments; any SIEM works via syslog or HTTP collector)

### Production observability gaps to monitor
- Worker pod queue depth — is action processing keeping up?
- Postgres query performance — slow queries that could degrade UX
- Redis memory pressure — at risk of evictions?
- Per-Story latency — which Stories are slow?
- AI credit burn rate — by team and over time
- Failed action rate — by Story, by Action type
- Tunnel health (if used)

### Alerting
- High queue depth (job processing falling behind)
- High P95 action latency
- Postgres connection pool exhaustion
- Redis memory > 80% used
- Failed action rate spike
- AKS pod restart rate
- AI credit consumption near monthly cap

---

## 8. Backup and DR

### Critical persistence layer
- **PostgreSQL** is the primary persistence — Stories, Cases, Records, audit logs, users, everything
- **Blob Storage** for files and attachments
- **Redis** is cache + queue; can be lost without data loss (but in-flight job loss possible)
- **AKS state** is rebuildable from Helm + Tines images

### Backup strategy
- **Postgres**: Azure DB for PostgreSQL Flexible Server has built-in PITR (point-in-time recovery). Use 14-day retention minimum, 35-day for production.
- **Blob Storage**: enable soft delete + versioning + immutable blob retention if compliance requires
- **Helm values + tenant configuration**: source-controlled in Git
- **Stories themselves**: Story syncing to a DR tenant, OR Terraform-managed for full IaC, OR periodic export to Git

### DR posture
- Hot standby: secondary Postgres replica in another region (cost trade-off)
- Warm standby: backup-restore to secondary region, ~30min RTO
- Cold: backups in geo-redundant storage, ~hours to days RTO

Your exact RTO/RPO requirements drive the choice. For SOAR / automation, you can usually accept hours of RTO if your SIEM and detection pipeline have higher availability — automation can pause without business impact for short windows.

---

## 9. Upgrade Path

### Tines self-hosted upgrade model
- Tines releases new versions periodically (verify cadence)
- Self-hosted customers control timing
- Helm-managed: `helm upgrade` with new chart version
- Image-managed: tag bump, rolling deployment

### Recommended cadence
- **Production**: monthly upgrade window, after 1-2 weeks in dev/staging
- **Staging**: weekly upgrade
- **Dev**: continuous

### Pre-upgrade checks
- Backup Postgres
- Check release notes for breaking changes
- Verify Helm values compatibility
- Test in lower environment first

### Rollback
- Helm rollback to previous chart version
- Postgres PITR if data migration was destructive
- Roll back image tag and re-deploy

---

## 10. Security Hardening Checklist

### Network
- [ ] Tines exposed only via App Gateway with WAF
- [ ] All backend services (Postgres, Redis, Blob) on Private Endpoints
- [ ] NAT Gateway with deterministic egress IP for vendor allowlisting
- [ ] Action Egress Control configured for known vendor destinations only
- [ ] IP access control enabled at tenant level

### Identity
- [ ] SSO enforced via Entra ID, email login disabled
- [ ] SCIM configured for user lifecycle
- [ ] AKS Workload Identity for Azure resource access
- [ ] No static credentials in Helm values
- [ ] Custom roles defined; no default-admin access

### Secrets
- [ ] All secrets in Key Vault, mounted via Secrets Store CSI Driver
- [ ] Tines-managed credentials encrypted in Postgres
- [ ] No secrets in container images
- [ ] Secret rotation procedures documented

### Data
- [ ] Postgres encryption at rest (Azure default)
- [ ] Postgres TLS in transit
- [ ] Blob Storage encryption with customer-managed keys (if required)
- [ ] Sensitive case fields configured for PII/credentials
- [ ] Audit log retention meets compliance requirements

### Operations
- [ ] Image verification process (verify pulled images against Tines signatures)
- [ ] Vulnerability scanning on AKS nodes and pods
- [ ] Network policies in AKS to restrict pod-to-pod traffic
- [ ] Pod Security Standards enforced
- [ ] RBAC configured for K8s admin access

### Monitoring
- [ ] Audit logs forwarded to SIEM
- [ ] Failed login alerts
- [ ] Privileged action alerts (impersonation, role changes)
- [ ] AI credit consumption alerts
- [ ] Queue depth and worker health alerts

---

## 11. Migration from POC SaaS Tenant

If POC runs on a Tines-stood-up SaaS tenant and production goes self-hosted, plan the migration:

### Data
- Story export/import via JSON works between SaaS and self-hosted
- Resources, Credentials, Cases, Records — verify export/import support per object type with Tines SE
- Audit logs and event history typically don't transfer

### Configuration
- Connect Flows configured in POC don't carry over — re-auth in self-hosted
- Page configs, Custom Tools, AI Agent setups need re-creation
- Custom domains and DNS swap

### Cutover
- Low-stakes Stories first; validate parity in self-hosted
- Critical Stories last, with parallel running for a period
- Decommission SaaS tenant after 30+ day cooldown

**Better approach if Tines supports it**: ask Tines whether the POC tenant infrastructure can promote in place to a long-term SaaS, or whether they offer a migration assist. Saves rework.

---

## 12. Open Questions for Tines SE

To resolve during the POC and architecture review:

1. **Helm chart specifics** — current chart version, customization points, breaking changes in recent releases
2. **Azure-specific known issues** — anything specific to AKS or Azure-managed Postgres/Redis that Tines has seen
3. **Reference customer self-hosting on Azure** — anyone willing to share their architecture? At least one reference is critical
4. **Sizing for our workload** — model based on alert volume, expected Story count, expected daily action runs
5. **Image registry caching** — recommended pattern for ACR cache, or pull directly from Tines registry?
6. **Tunnel necessity** — what's reachable from VNet vs. requires Tunnel?
7. **Upgrade testing in air-gapped/restricted environments** — process for offline upgrade
8. **Backup integration** — recommended approach for backing up alongside your existing backup tooling
9. **Multi-tenant patterns** — for multiple environments (dev / staging / prod), is that one cluster with multiple tenants, or separate clusters per environment?
10. **Disaster recovery RPO/RTO** — what does Tines guarantee, what is customer-responsibility?
11. **Performance baselines** — typical action latency, action throughput per worker pod, recommended worker:web pod ratio
12. **AI Agent infrastructure** — does AI Agent traffic leave the self-hosted cluster? Where does the LLM run? What egress is required?

---

## 13. Decision Points

These are decisions to lock in early in the deployment plan:

| Decision | Options | Default Lean |
|---|---|---|
| AKS topology | Single cluster, multi-tenant / Multiple clusters per env | Multiple clusters per env (better blast-radius isolation) |
| Postgres | Azure DB for PostgreSQL FX / Self-managed in AKS | FX Server (managed, less ops burden) |
| Redis | Azure Cache for Redis / Self-managed in AKS | Azure Cache (managed) |
| Ingress | App Gateway / NGINX / Istio | App Gateway (Azure-native, WAF integration) |
| Cert management | Key Vault + cert-manager / Manual | Key Vault + cert-manager (automated rotation) |
| Image registry | Direct from Tines / ACR cache | Direct unless rate-limited or air-gap (then ACR cache) |
| Observability | Azure Monitor / Datadog / Splunk | Azure Monitor (Azure-native, cost-effective) |
| Backup | Azure Backup + Velero / 3rd party | Azure Backup for Postgres + Velero for AKS (cheaper, native) |
| DR | Geo-redundant Postgres / Backup-restore / Hot standby | Backup-restore initially; upgrade to hot standby when justified |
| Tunnel | Required / Skip if VNet peering reaches all targets | Skip on a well-peered Azure deployment unless POC reveals targets that aren't reachable from the VNet |
| AI provider | Tines-bundled / Custom (Anthropic, OpenAI) | Tines-bundled for POC; evaluate custom for prod |

Lock these decisions in the architecture review meeting, then build to them.
