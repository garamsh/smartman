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
  - **The issuer from `SUPABASE_URL`.** Its value under a custom domain is not documented, and an issuer that silently followed it would bring back the mismatch.
  - **An `MCP_AUTH_ISSUER` secret**, as the BYO-MCP guide does. A secret is a project setting outside the repository; the issuer is one fixed URL of the one project the function serves.
  - **The Vercel host rewrite of the first scope** (`mcp.smartman.garam.sh`). Dropped with the domain it served.

## Decision

- **The authorization server is Auth's issuer**, `https://jaxltcczmioxrineznfu.supabase.co/auth/v1`, a constant in `supabase/functions/mcp/handler.ts` built from the project's host, whichever host the client used.
- **The resource is the host the client used, from a list.** `PUBLIC_HOSTS` in the same file holds `api.knowno.app` and `jaxltcczmioxrineznfu.supabase.co`. When the gateway's `X-Forwarded-Host` is one of them, the resource is `https://<host>/functions/v1/mcp`, in the 401's `resource_metadata` and in the metadata; any other host is given the first, `api.knowno.app`, and never named. `X-Forwarded-Proto` and `-Port` are no longer read: every listed host is HTTPS on its standard port.
- **A new host** is added to `PUBLIC_HOSTS`; the first entry is the address 설정 shows.
- **The settings entry** shows `https://api.knowno.app/functions/v1/mcp`, a constant in `ai-connection.tsx`, in place of `NEXT_PUBLIC_SUPABASE_URL` with the function's path.
- This supersedes ADR 0126's resource and authorization server read from the gateway's forwarded origin, and its settings entry's address.

## Consequences

- Claude and ChatGPT connect with `https://api.knowno.app/functions/v1/mcp`. A connection made with the project's URL keeps working, since Supabase Auth does not reflect the `resource` parameter in a token ([ADR 0126](0126-connect-claude-and-chatgpt-through-one-remote-mcp-server-acting-as-the-signed-in-user.md)).
- No migration, no secret and no change to the web's Supabase URL.
- The project's ref is written into the function; a second project would need its own entries.
- `supabase functions serve` names `api.knowno.app` and the hosted issuer, since its host is not listed; local OAuth discovery is not served.
- 설정 shows the production address in every environment, a local web included.

## Signs the decision was wrong

- Supabase moves Auth's issuer to the custom domain, so the constant stops matching `/.well-known/oauth-authorization-server`.
- Claude or ChatGPT refuses an authorization server on another host than the resource.
- The project gains a second environment that serves the function.
