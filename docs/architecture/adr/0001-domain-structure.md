# ADR 0001: Partition the app by domain, with siblings reached only through their public surface

> Status: accepted
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- smartman is a memorization app: a Flutter client in `app/` with a Supabase backend in `supabase/`. The client holds no feature code yet.
- The subject areas are already named by the PM who asks for the work: `deck`, `study`, `auth`, `sync` (issue #2).
- The bootstrap candidates were layered, hexagonal, and domain partitioning, read from the template's `docs/architecture/structures/` as adopted in commit `db222b41cab7f02114d028f3b414c80d58167f12`.
- Domain partitioning leaves one point to the project: whether a domain may depend on a sibling at all. *Domain-Driven Design* (Evans, 2003) ranges from Shared Kernel, where two contexts share code, to Separate Ways, where neither references the other.

## Decision

- The app is partitioned by domain. Inside `app/lib/`, each domain gets one folder; the composition site is `app/lib/main.dart`.
- A domain may depend on a sibling only through that sibling's declared public surface, and the dependency graph between domains stays acyclic. Shared Kernel and Separate Ways are not taken.

## Consequences

- A change to one subject area lands inside one folder under `app/lib/`.
- A domain that needs a sibling's behaviour reaches it through the sibling's public surface, so that surface is what a reviewer checks a cross-domain reference against.
- A reference into a sibling's internals, a reference that closes a cycle between domains, and code two domains share as a sibling folder no domain owns are defects.
- Work belonging to no single domain has no home, and the shared code it lands in has to be kept below the domains.
- Layered and hexagonal partitioning are not taken; the top-level division of `app/lib/` is not by technical role.

## Signs the decision was wrong

- Most changes touch several domains at once, and the pair that always move together cannot be released independently.
- The same fix is applied once per domain, and a domain keeps being missed.
- The shared code every domain imports is growing faster than any domain.
- Which domain a new file belongs to cannot be settled without asking someone.
- A domain's public surface has grown until it names what the domain keeps inside.
