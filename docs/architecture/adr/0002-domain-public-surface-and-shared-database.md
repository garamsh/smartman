# ADR 0002: Declare a domain's surface in one library file, and keep the database below the domains

> Status: accepted
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- [ADR 0001](0001-domain-structure.md) lets a domain reach a sibling only through its declared public surface, and `structure.md` left open how a Dart domain folder declares that surface. Issue #4 creates the first domain, `deck`, so the question is now met.
- Dart has no module-private visibility across files: any file under `app/lib/` can import any other. The surface therefore has to be a convention a reviewer checks, not one the compiler enforces.
- Issue #4 takes drift for the local SQLite database. A drift database class lists every table it holds and generates code from that list. The `study` domain (M3) will add a `Review` table whose rows reference a `deck` card.
- `structure.md` put shared code below every domain, never beside one as a sibling folder no domain owns. In a Dart `lib/`, every folder is physically a sibling of the others. "Below" can therefore only mean import direction. The PM confirmed that reading in the review of PR #8, and asked that the rule be stated in this project's form and enforced by a check.
- Alternatives considered for the database:
  - One database per domain: a review could not reference its card with a foreign key, and no transaction could span two domains.
  - Tables owned by each domain and the database class assembled at the composition site: the composition site would then own the schema version and migrations, which is deciding rather than constructing, and every domain would export its tables.
  - The database owned by `deck` and reached through its surface: `study` would add its tables inside `deck`.
- The PM asked that the layout follow drift's and Riverpod's documented structure, with each deliberate departure recorded here with its reason (issue #4, PM addendum comment). The same holds for Flutter's localization tool, which the addendum also requires.

## Decision

- A domain declares its public surface in one library file named for it, `app/lib/<domain>/<domain>.dart`, which exports with `show` the names a caller may use. Everything else the domain holds lives under `app/lib/<domain>/src/`.
- Code below every domain lives under `app/lib/shared/`, the one folder under `app/lib/` that is not a domain. "Below" means import direction: nothing there imports a domain, and any domain may import it. The drift database, holding every domain's tables, lives there.
- A test, `app/test/architecture_test.dart`, enforces both import rules: no import from `shared/` into a domain, and no import into a domain's `src/` from outside that domain.
- The drift database is `app/lib/shared/database.dart`. Its schema dumps and migration tests sit where drift's `make-migrations` puts them by default: `app/drift_schemas/` and `app/test/drift/`.
- The localization ARB files and the classes `gen-l10n` writes from them are in `app/lib/shared/l10n/`.
- Generated Dart is committed: `database.g.dart`, the `gen-l10n` output, and the schema helpers under `app/test/drift/*/generated/`. `make lint` regenerates them and fails when a committed file differs.

### Departures from the tools' documented layout

- **The database is in `app/lib/shared/`, not at the top of `lib/` as drift's setup guide shows.** The rule that shared code sits below the domains takes precedence over that example. drift prescribes no folder.
- **The ARB files are in `app/lib/shared/l10n/`, not in `lib/l10n/`, which is Flutter's default `arb-dir`.** One app-wide localization class serves every domain, so it is shared code, and shared code has one folder, `app/lib/shared/`. `app/l10n.yaml` names the directory.
- **Providers are declared by hand, not with `riverpod_generator`.** Riverpod's documentation presents both forms, so this departs from no rule. Writing them by hand avoids a second code generator for a handful of providers.
- **Generated Dart is committed.** Every tool documents generating it at build time. Committing it lets `make ci` analyze, format-check, and test the generated files as they ship, and `check-generated.sh` keeps them in step with their sources.

## Consequences

- A cross-domain reference is checked by one rule: an import of another domain's `src/` path is a defect. The composition site imports domains through their library files too. The architecture test fails on such an import, so the rule does not depend on a reviewer noticing.
- A domain's own tests may import its `src/` files, since they are inside the boundary they test.
- Each domain maps database rows into its own types; row classes do not appear on a domain's surface.
- Adding a domain's tables means editing `app/lib/shared/database.dart`, raising its schema version, and running drift's `make-migrations`, which exports the new schema dump and its test helpers. Then `database.g.dart` is regenerated.
- Every user-facing string of every domain goes through the one ARB set in `app/lib/shared/l10n/`.
- A committed generated file that is out of step with its source fails `make lint`. The cost is that `lint` runs every generator, which adds their run time to each check.
- The schema of every domain sits in one file, so a table is not owned by the domain whose rows it holds; that ownership is recorded in the domain's responsibility document instead.
- `app/lib/shared/` is a folder no domain owns. It is below the domains rather than beside them because of import direction, which the architecture test enforces.

## Signs the decision was wrong

- Domains routinely need a sibling's internals and the library files keep growing to export them.
- `app/lib/shared/` gathers code that belongs to one domain, or starts importing a domain.
- Schema changes for two domains collide in `database.dart` often enough to slow both.
- A committed generated file is found out of date with its source on the default branch.
- The shared ARB set grows conflicting keys between domains, or one domain's strings dominate it.
