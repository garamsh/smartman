# ADR 0018: Build the engine as WebAssembly in `engine-wasm/` with the wasm-bindgen CLI, returning engine errors as typed values

> Status: accepted
> Date: 2026-10-15

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #43 (M8a) builds the engine for the PC web app, which calls the same crate compiled to WebAssembly. The PM decided there:
  - a crate `engine-wasm/` at the repository root depends on `engine/` by path, as the bridge crate does ([ADR 0004](0004-flutter-rust-bridge.md)); `engine/` gains no WASM or JS dependency;
  - it exports the bridge's operations, with the optional fuzz factor ([ADR 0012](0012-fuzz-review-intervals.md)); times cross as whole seconds since the epoch, and engine errors as typed values TypeScript can switch on, never as a thrown string;
  - `wasm-bindgen`, through `wasm-pack` or the `wasm-bindgen` CLI, target `web`, writes `engine-wasm/pkg/`, committed and checked by `check-generated.sh`;
  - `wasm-bindgen-test` runs the reference values on `wasm32-unknown-unknown` in Node.
- On the question that the reference values hold Hard and Easy ratings the two answers cannot express (93 of 348 steps), the PM decided (2026-10-15, amending issue #43) that the surface takes the app's two answers, as the bridge does, so the button mapping stays in the Rust binding crates, and that the WASM tests run every sequence made only of Again and Good.
- wasm-bindgen 0.2.129 is the current release (crates.io, 2026-09-25). Its CLI release archive holds both `wasm-bindgen` and `wasm-bindgen-test-runner`; `taiki-e/install-action` at the commit CI already pins installs it prebuilt (`manifests/wasm-bindgen.json` there). wasm-bindgen-test 0.3.79 and js-sys 0.3.106 require wasm-bindgen `=0.2.129` exactly (crates.io dependency lists).
- With a `Result<T, E>` return, wasm-bindgen's JS glue throws `E`, and TypeScript cannot type a thrown value. A returned union can be typed, and narrowed with `in` or a `kind` switch.
- tsify 0.5.8 (crates.io, 2026-08-23) derives the TypeScript declaration of a serde type into the `.d.ts`, so the declared shape and the serialized one come from one Rust definition. Its README at tag `v0.5.8` deprecates the `into_wasm_abi` and `from_wasm_abi` attributes, which leak on a failed conversion, in favour of `Ts<T>`.
- A release build for `wasm32-unknown-unknown` embeds the absolute source paths of dependencies, under the builder's Cargo home, in panic locations. Cargo's `trim-paths` profile option is unstable in Cargo 1.99.0. Its name section also carries symbol names whose crate hashes differ with the checkout's path: two checkouts of one commit at different paths built different modules until the symbols were stripped. With them stripped, the prebuilt 0.2.129 CLI from the release archive wrote one module on macOS and Linux, and the same release built from source by `cargo install wasm-bindgen-cli --version 0.2.129 --locked` wrote another, from the same input.

## Decision

- **Crate.** `engine-wasm/`, the crate `smartman_engine_wasm`, built only for `wasm32-unknown-unknown` (`engine-wasm/.cargo/config.toml`), with the Rust release of `engine/rust-toolchain.toml`.
- **Surface.** `reviewNewCard`, `reviewCard`, `replay` and `retrievability`, as the bridge's, with the answers `"know"` and `"dontKnow"`, an optional fuzz factor, and times as `bigint` whole seconds.
- **Errors.** Each operation returns `Outcome<T>`: `{ ok: T }`, or `{ error: EngineError }`, where `EngineError` is a union told apart by `kind`, one member per engine `Error` variant. An argument the TypeScript types rule out is thrown as a JS `Error`, as a programming error.
- **Types.** The crate declares its own types with serde and tsify, and converts to and from the engine's by exhaustive matches, as the bridge crate does.
- **Build.** The `wasm-bindgen` CLI, not wasm-pack, at the release `engine-wasm/Cargo.lock` pins, from its prebuilt release archive, writes `--target web` output to `engine-wasm/pkg/`. `wasm-bindgen.sh generate` builds it with the Cargo home and the repository mapped to fixed prefixes and the release profile stripping symbols, so every host writes the same module, and `check-generated.sh` reruns it.
- **Tests.** `wasm-bindgen.sh test` runs `cargo test` in `engine-wasm/` through `wasm-bindgen-test-runner` in Node.

## Consequences

- The web app imports `engine-wasm/pkg/` and needs no Rust toolchain.
- One tool generates the module and runs its tests, so the project pins one more CLI, not two. It is installed and version-checked as the flutter_rust_bridge codegen is: its release comes from a lock file.
- A contributor installs the prebuilt CLI, not a build from source, or `check-generated.sh` finds `pkg/` stale.
- A wasm-bindgen bump moves wasm-bindgen, wasm-bindgen-test and js-sys together, and lands with the regenerated `pkg/`; a bump alone fails to resolve or fails `check-generated.sh`.
- The web app's button mapping is the binding's, so web and phone schedule a "Know" the same way. Hard and Easy have no path from the web app, and their reference steps are checked natively only.
- A refusal is a value the caller must unwrap before reading the result; a call that forgets fails to type-check.
- Building with remapped paths takes a second target directory (`engine-wasm/target/generate/`), so `make ci` compiles the crate's release build twice: once there and once for `make build`.

## Signs the decision was wrong

- `pkg/` differs between the macOS and Linux jobs for a reason other than the paths remapped and the symbols stripped.
- tsify falls behind a wasm-bindgen release often enough that hand-written declarations would have cost less.
- The web app wraps every call to turn `Outcome` back into a throw, or needs a rating the two answers do not give.
- wasm-pack's packaging (`package.json`, a bundler target) turns out to be what the web app's build needs.
