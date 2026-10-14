# smartman

A memorization app: decks of cards studied on a phone. This file is the project's entry point for anyone running or changing it.

## Who it is for

- People who memorize material by studying decks of cards on iOS or Android.
- Contributors: start at `AGENTS.md`, then `docs/convention/README.md` and `docs/architecture/README.md`.

## Layout

- `app/` — the Flutter application (iOS and Android).
- `engine/` — the Rust crate that schedules reviews with FSRS.
- `supabase/` — the Supabase CLI project for the backend.
- `docs/convention/` — the conventions every change follows.
- `docs/architecture/` — the structure of the system and the decisions behind it.
- `Makefile` — the entry points for the project's checks.
- `.github/` — the CI workflow, Dependabot configuration, and issue and pull request templates.

## Requirements

- Flutter 3.47.7 (stable channel), pinned once in `app/pubspec.yaml` under `environment: flutter:`; CI reads it from there. The PM bumps it when a new stable Flutter release ships.
- JDK 17 for the Android build; with Flutter, point it at the JDK with `flutter config --jdk-dir`.
- Android SDK 36 for the Android build; Xcode for iOS.
- Supabase CLI 2.120.0 for the backend.
- Rust 1.99.0 with clippy and rustfmt for the engine, pinned in `engine/rust-toolchain.toml`; rustup installs it on first use. Dependabot proposes the bump when a new stable Rust release ships.
- jq, which `make lint` uses to list the engine's cargo targets.
- uv, only to regenerate the engine's reference values; it fetches the Python and the py-fsrs version the generator pins.

## Run the app

```sh
cd app
flutter run
```

## Run the checks

- `make lint` — checks Markdown Contents lists, runs `flutter analyze` over the app's Dart files, and runs clippy over the engine with warnings denied.
- `make format` — fails when a Dart file in the app or a Rust file in the engine is not formatted; `dart format` or `cargo fmt` fixes it.
- `make test` — runs the app's tests and the engine's tests.
- `make build` — builds a debug Android APK and the engine crate.
- `make ci` — runs all four in that order. CI runs the same target.

## Run the backend locally

```sh
supabase start
```

This needs Docker. It runs the local stack from `supabase/config.toml`.
