# Structure

The structural rules of the app: what the unit is, what may reference what, and when a new unit is earned.

## Current decisions

The app is partitioned by domain ([ADR 0001](adr/0001-domain-structure.md)). Domains live as folders under `app/lib/`; the first is `deck` ([`deck.md`](deck.md)). The composition site is `app/lib/main.dart`.

### Boundaries and dependency direction

- **A domain is the unit.** One folder per domain, named for its subject matter and never for a technical role.
- **A domain is reached only through what it declares public.** Everything else it holds is internal, and reaching past that surface is a defect even where the language permits it.
- **Whether a domain may depend on a sibling at all is contested.** *Domain-Driven Design* (Evans, 2003) gives no single answer: its relations between contexts run from Shared Kernel, where two share code, to Separate Ways, where neither may reference the other. A project takes one, records which, and a reference the recorded choice does not permit is a defect.
  - This project's choice: a domain may depend on a sibling only through that sibling's declared public surface, and the dependency graph between domains stays acyclic. Shared Kernel and Separate Ways are not taken.
- **Shared code sits below every domain, never beside one.** What two domains both need is extracted below them, or owned by one and reached through its declared surface; it never becomes a sibling folder no domain owns.
- **A cycle between domains means the split is wrong**, and so does a file that belongs in two of them.
- **A new domain is earned** by subject matter with its own lifecycle and vocabulary, which something outside it depends on, and whose public surface can stay stable while its inside changes.

### Public surface and shared code

- **A domain declares its public surface in one library file named for it**, `app/lib/<domain>/<domain>.dart`, which exports with `show` the names a caller may use ([ADR 0002](adr/0002-domain-public-surface-and-shared-database.md)).
- **Everything else a domain holds lives under `app/lib/<domain>/src/`.** An import of another domain's `src/` path is a defect, from a sibling or from the composition site. A domain's own tests may import its `src/` files.
- **Code below every domain lives under `app/lib/shared/`.** Nothing there imports a domain; any domain may import it.
- **The drift database is shared code.** `app/lib/shared/database.dart` holds every domain's tables; a domain maps rows into its own types and does not export row classes. Its generated `database.g.dart` is committed and regenerated with `dart run build_runner build` in `app/` after a schema change.

### Composition

- **The application has one composition site.** It is the one place that constructs concrete implementations, and it decides which implementation each declared abstraction receives.
- **Every other unit receives what it depends on and constructs none of it**, whatever the shape makes the unit — a domain, a layer, or an adapter.
- **The composition site stays thin.** It constructs and passes; it decides nothing else.

## Rationale

- [ADR 0001](adr/0001-domain-structure.md) records why the app is partitioned by domain and which sibling-dependency relation it takes.
- [ADR 0002](adr/0002-domain-public-surface-and-shared-database.md) records how a domain declares its public surface and why the database sits below the domains.

## Open questions

- None.
