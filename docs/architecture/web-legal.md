# Web legal

The web's `legal` feature: the terms of service and the privacy policy at `/terms` and `/privacy`, and the links to them. The app's links to them are [`account.md`](account.md)'s.

## Current decisions

### Documents

- The web publishes the terms of service at `/terms` and the privacy policy at `/privacy`, in Korean, and every link to them, the app's included, leads there ([ADR 0032](adr/0032-publish-the-legal-documents-on-the-web-and-link-both-clients-to-them.md)). The login page's consent line and the account page's foot link to them by those relative paths, through `web/src/features/legal/legal-links.tsx`; nothing configures them.
- Each page is a static Server Component that reads nothing, so `next build` prerenders it; the proxy lets a signed-out visitor reach both.
- `web/src/features/legal/legal-document.tsx` draws both in the list column with the theme's tokens: the title with a back link, "시행일" and the date, the opening paragraph, a "목차" navigation linking to each section, then each section under a second-level heading whose `id` is its anchor.
- The privacy policy's sections are the items collected and how, the purposes, retention and destruction, third-party provision, processors, overseas transfer, the user's rights, automatically collected data and cookies, protection measures, the contact and the effective date with how changes are announced. The terms' are the service, accounts and sign-in, the user's content and the licence for public decks, public sharing with reports, blocks and prohibited content, AI-made cards, service changes, account deletion, liability, governing law, the contact and the effective date (issue #86).
- Both name the operator as "smartman 운영자" and the contact `sauce@garam.sh`, and take effect on 2026-10-16. A change to either is a pull request to its `page.tsx`, and states the new date.

### Tests

Each line names a file and what it covers; the file holds the cases.

- `web/src/app/__tests__/legal-documents.test.tsx` — each document's required section headings, its table of contents links to their anchors, its title, effective date and contact.
- `web/src/features/legal/__tests__/legal.test.tsx` — the legal links' targets; the login and account pages' tests check the links there ([`web-account.md`](web-account.md)).

## Rationale

- [ADR 0032](adr/0032-publish-the-legal-documents-on-the-web-and-link-both-clients-to-them.md) records why the web hosts the legal documents and why no variable configures the links.
- Issue #86 records the legal documents.

## Open questions

- None.
