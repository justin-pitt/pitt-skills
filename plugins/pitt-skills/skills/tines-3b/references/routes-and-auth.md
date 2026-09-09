# Routes, Webpages, and Authentication

## The route article documents no authentication

The Route documentation lists exactly three key components: route path, HTTP
method (GET, POST, PUT, DELETE, PATCH), and output. The word "auth" does not
appear on it. This is a documentation gap, not a product gap. The canonical
enumeration of auth modes lives in the endpoint-auditing article, and the config
key name and default live in the build-in-your-own-tools article.

## The six `route_auth` modes

| Value | Meaning |
|---|---|
| `space` (**default**) | members of the workflow's space only |
| `tenant` | any member within the tenant |
| `sso` | "Enable access for external users via Single Sign-On" |
| `external_id` | an unguessable identifier, for webhooks |
| `connector` | reached through a connected app or connector, for workflow-to-workflow calls |
| `public` | no authentication, "anyone with the URL can trigger the route" |

The docs flag `public` as "exposed to the open internet and should be reviewed
carefully" and advise keeping routes private unless genuinely needed.

Coverage is uneven: the Webpage article lists only four of the six, silently
omitting `external_id` and `connector`.

## Reaching people who have no account

Three documented paths, with different trade-offs.

**`public`** puts the route on the open internet with no authentication. Simple
and dangerous. Note that the Explore tier explicitly forbids public website
URLs, so this is not available on a free tenant.

**`external_id`** is capability-URL security, the direct analog of a classic
webhook URL. The webhook documentation says it "allows external services to push
data securely without requiring a user to be logged in to your tenant." Verify
this works on the target tenant before designing around it; see
`gotchas.md` for an observed failure.

**`sso`** admits external users through an identity provider. This is the path
for a real internal application with named users, and it is the one most often
overlooked. It requires SSO to be configured on the tenant: check that an
identity provider actually exists before promising it, since an unconfigured
tenant has none.

Whether SSO can gate a *public* website URL specifically is **undocumented**.
The tier limit implies paid tiers can publish public URLs, but nothing states
whether SSO protects them.

## `route_type`

Orthogonal to auth. It controls display, not behavior.

| Value | Surfaces as |
|---|---|
| `webpage` | descriptive label, earth icon, rendered preview thumbnail |
| `api` | programmatic endpoint |
| `webhook` | inbound event endpoint |

Setting it puts the route on the Links tab. Omitting it keeps the route
functional but hidden, which is correct for internal callbacks and helper
endpoints: "plumbing rather than front doors."

## Webpages

"A webpage is a specific type of HTTP route step designed to serve HTML content
that can be opened and viewed directly in a web browser. Unlike API endpoints,
which are designed for machine communication, Webpages are human-facing
interfaces."

**Authoring.** A step directory with `README.md`, `config.toml`, `Dockerfile`,
and source. The react template gives `App.tsx` rendered as a client-side React
app with Tailwind. "Webpages often utilize templates like React + Tailwind,
though you can use any template that outputs valid HTML."

**Serving.** Set `route` to a path and `route_type = "webpage"`. Step stdout
becomes the HTTP response body.

**User input works.** Forms are a named, first-class route pattern: "Form
handlers: Use routes to accept form submissions, process the data, and redirect
users or show success messages." The route article adds "full control over the
response, allowing you to build everything from simple webhook listeners to
interactive web applications."

**You are not expected to hand-write it.** The documented default is prompting:
"Each step runs a small piece of code (shell, Python, TypeScript, or a React app
for pages people can open), and data flows from one step to the next. You don't
have to write any of that yourself." Two always-on built-in skills cover this
ground, one for frontend interfaces and one for analytics dashboards. Visual
refinement happens by pointing at an element in the browser preview and saying
what to change, rather than describing it in words.

What does **not** exist is a drag-and-drop field palette. Forms are generated
code, not a no-code canvas.

**CORS is your responsibility.** The docs say to configure CORS headers
yourself.

## Route troubleshooting

| Symptom | Documented cause |
|---|---|
| 404 | not published to `main`, or HTTP method mismatch |
| 504 | use the async pattern: return 202 Accepted and process in the background |
| Connector missing from the picker | URL pattern mismatch, or a permissions denial rendering it invisible |

A 504 does not mean the step failed. See `gotchas.md`.

## Route auditing

A workflow routes panel renders live-route workflows grouped by auth mode as a
radar chart. A workflow counts for a mode if it contains at least one route
using it, so a workflow with mixed auth appears in several segments. Clicking a
segment lists workflow names, route counts, route types, and paths.

This is the fastest way to answer "what is exposed publicly" across a tenant.

## The identity gap

**[undocumented]** How the authenticated viewer's identity reaches step code.
`route_auth = "sso"` gates access, but no documentation in the surveyed set
describes an injected user header, claim, or session object.

This is load-bearing for anything needing per-user attribution: approvals, audit
trails, "who submitted this," or per-user data isolation. Confirm empirically
before designing an app that depends on knowing who the caller is.

Related **[undocumented]** gaps: whether webpage form submissions produce an
audit trail beyond ordinary run history, whether routes support path parameters
or wildcards, and whether webhooks support signature verification such as HMAC.
The webhook documentation names only `external_id`.
