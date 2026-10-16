# ADR 0032: Publish the terms of service and the privacy policy as the web's own pages, and link both clients to them without configuration

> Status: accepted
> Date: 2026-10-16

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0027](0027-draw-both-clients-in-the-smartman-brand-and-the-v2-screens.md) made the legal links optional configuration: `TERMS_URL` and `PRIVACY_URL` in `app/config/*.json`, `NEXT_PUBLIC_TERMS_URL` and `NEXT_PUBLIC_PRIVACY_URL` on the web, and a "준비 중" page in each client while a value was empty. `app/config/dev.json` left both empty, so the app's links opened that page.
- Issue #86: the owner decided on 2026-10-16 that the service hosts both documents itself, as the web's `/terms` and `/privacy`, and that both clients link to `https://smartman.garam.sh/terms` and `https://smartman.garam.sh/privacy` so the "준비 중" state is never reached. The issue left whether the variables stay as overrides to the pull request.
- The PM chose, in the dispatch of #86, to drop the variables: the web publishes the documents, so a variable pointing elsewhere would leave a second copy beside the one the web serves, and a setting no deployment needs is the configuration simplicity.md's "No speculative abstraction" names.

## Decision

- The web renders both documents as static pages at `/terms` and `/privacy`, which always render and never redirect. Its links are those relative paths, so on `smartman.garam.sh` they are the URLs above, and any other origin the web is served from shows its own build's copy.
- The app links to the two absolute URLs, held as constants in the `account` domain and opened in the platform's browser.
- The four variables and both "준비 중" pages are removed.
- This supersedes ADR 0027's "Legal links" decision except its `url_launcher` and `package_info_plus` pins.

## Consequences

- No deployment can link to a missing document, and no configuration can make the clients show different documents.
- Changing a document is a pull request to `web/src/app/terms/` or `web/src/app/privacy/`, which reaches the app's users once the web deploys, without an app release.
- Moving the documents to another host means changing the app's constants and releasing the app; the web needs no change.
- The Vercel project's `NEXT_PUBLIC_TERMS_URL` and `NEXT_PUBLIC_PRIVACY_URL`, if set, are no longer read; removing them is the owner's.

## Signs the decision was wrong

- A second environment, a staging flavor of the app (M7) for one, needs its own documents, and the constants have to become configuration again.
- The documents need a host other than the web app, such as a notice platform or a counsel's page, which the app cannot reach without a release.
