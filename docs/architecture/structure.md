# Structure

The structural rules of the app: what the unit is, what may reference what, and when a new unit is earned.

## Current decisions

The app is partitioned by domain ([ADR 0001](adr/0001-domain-structure.md)). Domains live as folders under `app/lib/`; none exists yet. The composition site is `app/lib/main.dart`.

### Boundaries and dependency direction

- **A domain is the unit.** One folder per domain, named for its subject matter and never for a technical role.
- **A domain is reached only through what it declares public.** Everything else it holds is internal, and reaching past that surface is a defect even where the language permits it.
- **Whether a domain may depend on a sibling at all is contested.** *Domain-Driven Design* (Evans, 2003) gives no single answer: its relations between contexts run from Shared Kernel, where two share code, to Separate Ways, where neither may reference the other. A project takes one, records which, and a reference the recorded choice does not permit is a defect.
  - This project's choice: a domain may depend on a sibling only through that sibling's declared public surface, and the dependency graph between domains stays acyclic. Shared Kernel and Separate Ways are not taken.
- **Shared code sits below every domain, never beside one.** What two domains both need is extracted below them, or owned by one and reached through its declared surface; it never becomes a sibling folder no domain owns.
- **A cycle between domains means the split is wrong**, and so does a file that belongs in two of them.
- **A new domain is earned** by subject matter with its own lifecycle and vocabulary, which something outside it depends on, and whose public surface can stay stable while its inside changes.

### Composition

- **The application has one composition site.** It is the one place that constructs concrete implementations, and it decides which implementation each declared abstraction receives.
- **Every other unit receives what it depends on and constructs none of it**, whatever the shape makes the unit — a domain, a layer, or an adapter.
- **The composition site stays thin.** It constructs and passes; it decides nothing else.

## Rationale

- [ADR 0001](adr/0001-domain-structure.md) records why the app is partitioned by domain and which sibling-dependency relation it takes.

## Open questions

- How a Dart domain folder declares its public surface (for example, one library file the siblings import) is not settled. No domain exists yet to need it.
