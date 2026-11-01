# ADR 0133: Serve the MCP server at api.knowno.app, name a listed host as its resource, and Auth's issuer as its authorization server

> Status: accepted
> Date: 2026-11-01

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- **Issue #520**, re-scoped by the PM on 2026-11-01: the owner activated Supabase's custom domain `api.knowno.app` for the project and is retiring `smartman.garam.sh`. The MCP server's address becomes `https://api.knowno.app/functions/v1/mcp`, served by Supabase directly; the web fronts nothing.
- **Before this change** ([ADR 0126](0126-connect-claude-and-chatgpt-through-one-remote-mcp-server-acting-as-the-signed-in-user.md)): the function built both the resource and the authorization server from the gateway's `X-Forwarded-Host`, `-Proto` and `-Port`, and 설정's "AI 연결" showed `NEXT_PUBLIC_SUPABASE_URL` with `/functions/v1/mcp`.
- **What the deployed function answered on 2026-11-01:** `curl -s https://api.knowno.app/functions/v1/mcp/oauth-protected-resource` named `authorization_servers` `["https://api.knowno.app/auth/v1"]`, while `curl -s https://api.knowno.app/.well-known/oauth-authorization-server/auth/v1` and the same path on `jaxltcczmioxrineznfu.supabase.co` both reported `issuer` `https://jaxltcczmioxrineznfu.supabase.co/auth/v1`. RFC 8414 §3.3 requires the issuer a client reads to equal the authorization server it was given, so a client may refuse that pair.
- **The gateway sets the forwarded host.** The same day, `curl -i -X POST -H "X-Forwarded-Host: evil.example" https://jaxltcczmioxrineznfu.supabase.co/functions/v1/mcp` was answered with `resource_metadata` on `jaxltcczmioxrineznfu.supabase.co`: the gateway replaces a caller's header. A request through `api.knowno.app` is named on `api.knowno.app`.
- **Supabase's documentation**, read 2026-11-01, neither page dated:
  - `supabase.com/docs/guides/platform/custom-domains`, §Prepare to activate your domain: "MCP servers that use Supabase Auth need `authorizationServer` set explicitly to the project Auth issuer, not the custom domain"; "OAuth flows will advertise the custom domain as a callback URL", so each third-party provider's console needs `https://<custom domain>/auth/v1/callback` "in addition to the Supabase project URL"; a SAML project's `EntityID` changes; the project's Supabase domain keeps serving requests.
  - `supabase.com/docs/guides/ai-tools/byo-mcp`, §Use a custom domain: Auth "keeps its issuer on the project domain", `https://<project-ref>.supabase.co/auth/v1`; the resource follows the domain the client used, so both addresses keep working. It sets the issuer through an `MCP_AUTH_ISSUER` secret.
  - `supabase.com/docs/guides/functions/secrets`: `SUPABASE_URL` is "The API gateway for your Supabase project", which does not say whether it names the project's domain or the custom one.
- **Alternatives considered:**
  - **The production project's issuer as a constant.** It would send a local stack's or another project's clients to production's Auth, and configuration belongs at the boundary, read from the environment.
  - **An `MCP_AUTH_ISSUER` secret**, as the BYO-MCP guide does. A secret is a project setting outside the repository, and `SUPABASE_URL` already names the project.
  - **The Vercel host rewrite of the first scope** (`mcp.smartman.garam.sh`). Dropped with the domain it served.

## Decision

- **The project's origin is `SUPABASE_URL`'s**, read once by `supabase/functions/mcp/config.ts` and parsed as an http(s) URL; any other value leaves the function unconfigured, answering 503.
- **The authorization server is Auth's issuer**, `<project origin>/auth/v1`, whichever host the client used.
- **The resource is the host the client used, from a list.** When the gateway's `X-Forwarded-Host` is in `CUSTOM_DOMAINS` (`supabase/functions/mcp/handler.ts`), holding `api.knowno.app`, the resource is `https://<host>/functions/v1/mcp`, in the 401's `resource_metadata` and in the metadata. Any other host falls back to the project's origin, so it is never named. `X-Forwarded-Proto` and `-Port` are no longer read.
- **A new custom domain** is added to `CUSTOM_DOMAINS`.
- **The settings entry** shows `https://api.knowno.app/functions/v1/mcp`, a constant in `ai-connection.tsx`, in place of `NEXT_PUBLIC_SUPABASE_URL` with the function's path.
- This supersedes ADR 0126's resource and authorization server read from the gateway's forwarded origin, and its settings entry's address.

## Consequences

- Claude and ChatGPT connect with `https://api.knowno.app/functions/v1/mcp`. A connection made with the project's URL keeps working, since Supabase Auth does not reflect the `resource` parameter in a token ([ADR 0126](0126-connect-claude-and-chatgpt-through-one-remote-mcp-server-acting-as-the-signed-in-user.md)).
- No migration, no secret and no change to the web's Supabase URL.
- Each project names its own origin and issuer; only the custom domain is written into the function.
- Supabase does not document whether the hosted `SUPABASE_URL` names the project's domain or the custom domain once one is active. The issuer is right only while it names the project's domain; the post-deploy check compares the two.
- A local stack names whatever its `SUPABASE_URL` is inside the runtime, not the address a client on the host used.
- 설정 shows the production address in every environment, a local web included.

## Signs the decision was wrong

- After a deploy, the metadata's `authorization_servers` differs from `issuer` in Auth's `/.well-known/oauth-authorization-server`, which means the hosted `SUPABASE_URL` is not the project's domain.
- Claude or ChatGPT refuses an authorization server on another host than the resource.
- A local client cannot reach the address a local stack names.
