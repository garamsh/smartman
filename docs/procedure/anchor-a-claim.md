# Anchor a claim

The acts that turn a claim in a document or a GitHub artifact into one a reader can check. The form each claim takes is `docs/convention/documentation.md` §Keep it current and §GitHub artifacts; this file cites them and states none of it.

## Find the subject

Each claim has one of three subjects, and `documentation.md` gives each its own form:

| Subject | Form |
|---|---|
| This repository | `documentation.md` §Keep it current, "Every claim about this repository must be verifiable in it" |
| Anything outside it — a tool, a library, a host, another repository | `documentation.md` §Keep it current, "A claim about anything outside it names what it holds for", and "A file may state once at the top what it was checked against" where one statement at the top of the file covers several claims |
| The project that will carry this document | `documentation.md` §Keep it current, "A claim about the project that will carry this document" |

A sentence holding claims about two subjects is two claims; anchor each.

## Anchor it

1. **Name an object in full.** Cite a commit as `documentation.md` §Keep it current, "A commit is cited by its full object name", states: `git rev-parse <ref>` prints that name.
2. **Cite a rule by its words.** Where the rule is numbered outside this project, the citation takes the form `documentation.md` §Keep it current, "A citation of a rule numbered outside this project", states — quote its heading or opening words.
3. **Record what was read and when.** Name the release or commit, the command with its arguments, and the date, as `documentation.md` §Keep it current, "A claim about anything outside it names what it holds for", and §GitHub artifacts, "A claim names a basis that could have contradicted it", ask.
4. **Ask whether a measurement exists before asserting a behaviour.** Before writing that a tool does something, find the command, run, or source that showed it. Where none exists, either produce one or ask whoever made the claim what established it; where neither yields one, the claim comes out, per `documentation.md` §Keep it current, "Every claim about this repository must be verifiable in it", for this repository.

## Check the anchor

1. Repeat the basis as written — the command, the file at the revision named — and confirm it returns what the claim says.
2. Where the basis is a search, confirm the same expression matches something that is present, as `documentation.md` §GitHub artifacts, "A claim names a basis that could have contradicted it", states.
