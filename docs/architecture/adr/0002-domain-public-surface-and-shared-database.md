# ADR 0002: Declare a domain's surface in one library file, and keep the database below the domains

> Status: accepted
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0001](0001-domain-structure.md) lets a domain reach a sibling only through its declared public surface, and `structure.md` left open how a Dart domain folder declares that surface. Issue #4 creates the first domain, `deck`, so the question is now met.
- Dart has no module-private visibility across files: any file under `app/lib/` can import any other. The surface therefore has to be a convention a reviewer checks, not one the compiler enforces.
- Issue #4 takes drift for the local SQLite database. A drift database class lists every table it holds and generates code from that list. The `study` domain (M3) will add a `Review` table whose rows reference a `deck` card.
- `structure.md` puts shared code below every domain, never beside one as a sibling folder no domain owns.
- Alternatives considered for the database:
  - One database per domain: a review could not reference its card with a foreign key, and no transaction could span two domains.
  - Tables owned by each domain and the database class assembled at the composition site: the composition site would then own the schema version and migrations, which is deciding rather than constructing, and every domain would export its tables.
  - The database owned by `deck` and reached through its surface: `study` would add its tables inside `deck`.

## Decision

- A domain declares its public surface in one library file named for it, `app/lib/<domain>/<domain>.dart`, which exports with `show` the names a caller may use. Everything else the domain holds lives under `app/lib/<domain>/src/`.
- Code below every domain lives under `app/lib/shared/`. Nothing there imports a domain; any domain may import it. The drift database, holding every domain's tables, lives there.

## Consequences

- A reviewer checks a cross-domain reference by one rule: an import of another domain's `src/` path is a defect. The composition site imports domains through their library files too.
- A domain's own tests may import its `src/` files, since they are inside the boundary they test.
- Each domain maps database rows into its own types; row classes do not appear on a domain's surface.
- Adding a domain's tables means editing `app/lib/shared/database.dart` and regenerating `database.g.dart`, which is committed so that the checks need no code generation step.
- The schema of every domain sits in one file, so a table is not owned by the domain whose rows it holds; that ownership is recorded in the domain's responsibility document instead.
- `app/lib/shared/` is a folder no domain owns. What makes it below rather than beside is the import direction, which a reviewer checks.

## Signs the decision was wrong

- Domains routinely need a sibling's internals and the library files keep growing to export them.
- `app/lib/shared/` gathers code that belongs to one domain, or starts importing a domain.
- Schema changes for two domains collide in `database.dart` often enough to slow both.
- The committed `database.g.dart` is found out of date with `database.dart` on the default branch.
