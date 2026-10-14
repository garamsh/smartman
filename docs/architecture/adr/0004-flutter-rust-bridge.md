# ADR 0004: Bridge the engine through a flutter_rust_bridge crate in `app/rust/`, with its bindings in the `study` domain

> Status: accepted
> Date: 2026-10-14

Append-only: once merged, the body below is not rewritten. A fact later found wrong is corrected in an appended note, not edited out; a revised decision is a new ADR that supersedes this one.

## Context

- Issue #9 (M2b) connects the Rust engine (`engine/`, [ADR 0003](0003-fsrs-engine.md)) to the Flutter app with flutter_rust_bridge v2. The PM decided there:
  - `engine/` takes no flutter_rust_bridge dependency or type;
  - a thin bridge crate in flutter_rust_bridge's standard place inside `app/` declares only what Dart needs;
  - the generated Dart bindings belong to the `study` domain, under `app/lib/study/src/`;
  - generated code is committed and checked ([ADR 0002](0002-domain-public-surface-and-shared-database.md)).
- The current stable release is flutter_rust_bridge 2.13.0 (crates.io and pub.dev, published 2026-08-23); 2.14.0 is in beta. Its documentation, read at tag `v2.13.0` (commit `8631db91a90c699439c9ce2a1fb4164ae8661da9`), integrates an existing app with `flutter_rust_bridge_codegen integrate`. That command offers two backends for compiling and bundling Rust:
  - **Cargokit**, the default. It adds a `rust_builder/` plugin package that builds the crate from Gradle and CocoaPods.
  - **Native assets** (`--integration-backend native-assets`). It adds `hook/build.dart`, a Dart build hook that `flutter build` and `flutter test` run, built on `native_toolchain_rust`.
- Cargokit builds with the toolchain named in a `cargokit.yaml`, `stable` when none is given (`build_tool/lib/src/builder.dart` in the scaffold 2.13.0 writes). It runs `rustup run <toolchain>`, which overrides a `rust-toolchain.toml`. Pinning it would take a second pin that Dependabot's `rust-toolchain` updater does not move.
- `native_toolchain_rust` refuses a crate without a `rust-toolchain.toml` that pins an exact release and lists its targets. That is the file Dependabot's `rust-toolchain` updater moves, as it does for `engine/rust-toolchain.toml`.
- With the native-assets backend, `integrate` changed no file under `app/android/` or `app/ios/`. With Cargokit it added a Podfile and changed both iOS `xcconfig` files.
- The generated loader (`flutter_rust_bridge` 2.13.0, `lib/src/loader/_io.dart`) finds the library under `flutter test` in `rust/target/release/`, the generated `ioDirectory`. The build hook writes its copy elsewhere, so a widget test needs `cargo build --release` in the crate first.
- Alternatives considered for the Dart surface of the crate:
  - Mirroring the engine's own types with `#[frb(mirror)]`. The engine's `Error` would reach Dart under the name of `dart:core`'s `Error`, and its tuple struct `Timestamp` as a class with a `field0`.
  - Passing the engine's `Rating` (1 to 4). The database stores only the app's two answers (`app/lib/shared/database.dart`, table `reviews`).

## Decision

- The bridge crate is `rust_lib_smartman` in `app/rust/`, the place and name `flutter_rust_bridge_codegen integrate` gives it. It depends on `engine/` by path.
- It is built with the **native-assets** backend, through the `app/hook/build.dart` that `integrate --integration-backend native-assets` writes.
- `app/rust/rust-toolchain.toml` pins the same Rust release as `engine/rust-toolchain.toml`. Dependabot's `rust-toolchain` and `cargo` updaters move it and the crate.
- flutter_rust_bridge is pinned to one release in three places: the crate (`=2.13.0` in `app/rust/Cargo.toml`), the Dart runtime and hook packages (`2.13.0` in `app/pubspec.yaml`), and the codegen. CI and `check-generated.sh` take the codegen's release from `app/rust/Cargo.lock`.
- The crate declares its own Dart-facing types and converts to and from the engine's, rather than mirroring them:
  - times are whole seconds, as the engine's `Timestamp` holds them;
  - answers are the app's two buttons;
  - every engine `Error` variant has one `EngineError` variant, mapped by an exhaustive match.
- Generated code is committed: the Rust `app/rust/src/frb_generated.rs` and the Dart under `app/lib/study/src/rust/`. `make lint` reruns the codegen through `check-generated.sh`.
- `make test` builds the crate into `app/rust/target/release/` before `flutter test`, where the generated loader looks.

### Departures from flutter_rust_bridge's documented layout

- **The native-assets backend, not the default Cargokit.** Cargokit's build ignores the crate's `rust-toolchain.toml`, so the Rust pin and its Dependabot mover would not reach the app's build. Both backends are documented for `integrate`.
- **The Dart bindings are in `app/lib/study/src/rust/`, not `lib/src/rust/`.** The engine serves scheduling, the `study` domain's subject, and `structure.md` admits no folder under `app/lib/` that is neither a domain nor `shared/`. `app/flutter_rust_bridge.yaml` sets `dart_output`, and `app/hook/build.dart` sets the matching `assetName`.
- **No web output** (`web: false`). WASM and web are out of scope (issue #9).
- **The codegen stops on the first error** (`stop_on_error: true`) rather than skipping an item it cannot parse, so a stale or partial binding fails `make lint`.
- **The toolchain lists only Android, iOS, and the macOS and Linux hosts** that run `flutter test`. The generated list also names Windows and `wasm32`, which the app does not build.
- **The integration-test scaffold is not kept.** `integrate` writes `integration_test/` and `test_driver/` around its demo function. The bridge is tested by a widget test that `make test` runs instead.

## Consequences

- `engine/` stays a pure crate; a change to the Dart surface is a change to `app/rust/src/api/` only.
- `flutter build apk` and `flutter build ios` build the crate through the hook with the pinned toolchain, for the targets Flutter asks for. No platform build file names the crate.
- A test calling the engine runs on any host that runs `make test`, at the cost of building the crate twice: once for the loader and once by the hook.
- Dependabot proposes the crate, pub, and codegen bumps of flutter_rust_bridge separately. One that moves alone fails `make ci`: the runtime refuses bindings from another codegen release, and `check-generated.sh` finds the bindings stale. Such a bump lands only together with the others and the regenerated code.
- The `EngineError` variant `UnknownRating` cannot arise from this surface, which takes answers rather than rating numbers. It stays, so that the engine's error type and the bridge's correspond one to one.
- Adding a bridge function means editing `app/rust/src/api/`, rerunning `flutter_rust_bridge_codegen generate` in `app/`, and committing what it writes.

## Signs the decision was wrong

- A Flutter upgrade breaks the build hook, or `native_toolchain_rust` falls behind a Flutter release, more often than Cargokit's scaffold would have needed updating.
- The `study` domain's internals and the bindings change for unrelated reasons, or a second domain needs the engine and has to reach into `study/src/`.
- The hand-written conversions in `app/rust/src/api/` drift from the engine's types often enough that mirroring them would have cost less.
- M3 needs the four FSRS ratings at the bridge after all.
