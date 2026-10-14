# Structure

The structural rules of the app: what the unit is, what may reference what, and when a new unit is earned.

## Current decisions

The app is partitioned by domain ([ADR 0001](adr/0001-domain-structure.md)). Domains live as folders under `app/lib/`: `deck` ([`deck.md`](deck.md)), `study` ([`study.md`](study.md)) and `account` ([`account.md`](account.md)). The composition site is `app/lib/main.dart`.

### Boundaries and dependency direction

- **A domain is the unit.** One folder per domain, named for its subject matter and never for a technical role.
- **A domain is reached only through what it declares public.** Everything else it holds is internal, and reaching past that surface is a defect even where the language permits it.
- **Whether a domain may depend on a sibling at all is contested.** *Domain-Driven Design* (Evans, 2003) gives no single answer: its relations between contexts run from Shared Kernel, where two share code, to Separate Ways, where neither may reference the other. A project takes one, records which, and a reference the recorded choice does not permit is a defect.
  - This project's choice: a domain may depend on a sibling only through that sibling's declared public surface, and the dependency graph between domains stays acyclic. Shared Kernel and Separate Ways are not taken.
- **Shared code sits below every domain, in `app/lib/shared/`.** "Below" refers to import direction, not folder depth:
  - nothing in `app/lib/shared/` imports a domain, and any domain may import it;
  - what two domains both need moves there, or is owned by one domain and reached through its declared surface;
  - a file in `app/lib/shared/` that serves only one domain is a defect;
  - `app/lib/shared/` is the only folder under `app/lib/` that is not a domain (see [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- **A cycle between domains means the split is wrong**, and so does a file that belongs in two of them.
- **A new domain is earned** by subject matter with its own lifecycle and vocabulary, which something outside it depends on, and whose public surface can stay stable while its inside changes.

### Public surface and shared code

- **A domain declares its public surface in one library file named for it**, `app/lib/<domain>/<domain>.dart`, which exports with `show` the names a caller may use ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- **Everything else a domain holds lives under `app/lib/<domain>/src/`.** An import of another domain's `src/` path is a defect, from a sibling or from the composition site. A domain's own tests may import its `src/` files.
- **The import rules are checked by a test.** `app/test/architecture_test.dart` fails on two kinds of import under `app/lib/`: one from `shared/` into a domain, and one into a domain's `src/` from outside that domain.
- **The drift database is shared code.** `app/lib/shared/database.dart` holds every domain's tables. A domain maps rows into its own types and does not export row classes.
- **Every schema change goes through a migration.** The change raises `schemaVersion`. In `app/`, `dart run drift_dev make-migrations` then exports the new schema to `drift_schemas/` and its helpers to `test/drift/`, and the migration test there must pass.
- **User-facing strings come from one ARB set.** It lives in `app/lib/shared/l10n/`, with Korean as the template and default locale. No widget hardcodes a string the user reads.
- **Generated code is committed and regenerated from its source.** This covers `database.g.dart` (via `dart run build_runner build`), the `gen-l10n` output (via `flutter gen-l10n`), the drift schema dumps, helpers and `database.steps.dart` (via `make-migrations`), and flutter_rust_bridge's Rust and Dart output (via `flutter_rust_bridge_codegen generate`, [ADR 0004](adr/0004-flutter-rust-bridge.md)). `make lint` runs `check-generated.sh`, which reruns every generator and fails when a committed file differs from what it writes.

### Composition

- **The application has one composition site.** It is the one place that constructs concrete implementations, and it decides which implementation each declared abstraction receives.
- **Every other unit receives what it depends on and constructs none of it**, whatever the shape makes the unit — a domain, a layer, or an adapter.
- **The composition site stays thin.** It constructs and passes; it decides nothing else.

## Rationale

- [ADR 0001](adr/0001-domain-structure.md) records why the app is partitioned by domain and which sibling-dependency relation it takes.
- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md) records how a domain declares its public surface and why the database sits below the domains.
- [ADR 0004](adr/0004-flutter-rust-bridge.md) records why the generated engine bindings sit inside the `study` domain.
- [ADR 0006](adr/0006-account-native-google-sign-in.md) records why only the `account` domain imports the Supabase and Google packages.

## Open questions

- None.
