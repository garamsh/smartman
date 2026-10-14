# smartman

A memorization app: decks of cards studied on a phone. This file is the project's entry point for anyone running or changing it.

## Who it is for

- People who memorize material by studying decks of cards on iOS or Android.
- Contributors: start at `AGENTS.md`, then `docs/convention/README.md` and `docs/architecture/README.md`.

## Layout

- `app/` — the Flutter application (iOS and Android).
- `app/config/` — the app's configuration per environment, passed with `--dart-define-from-file`; only `dev.json` exists. Its values are public; a Supabase secret or service-role key never goes there.
- `app/assets/fonts/` — the app's font, IBM Plex Sans KR (Regular, Medium, SemiBold, Bold), bundled under the SIL Open Font License 1.1 in `app/assets/fonts/OFL.txt`; the app downloads no font at run time. The files are those of `ofl/ibmplexsanskr/` in google/fonts at commit `2aa273e00174c62d5de0a8c4365299e26d0ecff2`. No bot proposes their update; the PM decides when to fetch a newer commit.
- `app/rust/` — the flutter_rust_bridge crate through which the app calls the engine.
- `engine/` — the Rust crate that schedules reviews with FSRS.
- `supabase/` — the Supabase CLI project for the backend: its configuration, migrations in `supabase/migrations/`, and pgTAP tests in `supabase/tests/`.
- `docs/convention/` — the conventions every change follows.
- `docs/architecture/` — the structure of the system and the decisions behind it.
- `Makefile` — the entry points for the project's checks.
- `.github/` — the CI workflow, Dependabot configuration, and issue and pull request templates.

## Requirements

- Flutter 3.47.7 (stable channel), pinned once in `app/pubspec.yaml` under `environment: flutter:`; CI reads it from there. The PM bumps it when a new stable Flutter release ships.
- JDK 17 for the Android build; with Flutter, point it at the JDK with `flutter config --jdk-dir`.
- Android SDK 36 for the Android build; Xcode for iOS.
- Supabase CLI 2.120.0 for the backend; CI's ubuntu job installs the same release, set in `.github/workflows/ci.yml`. The PM bumps both when a new release ships.
- Docker for the local backend and its tests; on macOS, `brew install colima docker`, then `colima start`. Without it, `make test` skips the database tests and says so.
- Rust 1.99.0 with clippy and rustfmt for the engine and the bridge crate, pinned in `engine/rust-toolchain.toml` and `app/rust/rust-toolchain.toml`; rustup installs it, and the Android and iOS targets the bridge crate lists, on first use. Dependabot proposes the bump when a new stable Rust release ships.
- flutter_rust_bridge_codegen at the release of the `flutter_rust_bridge` crate in `app/rust/Cargo.lock`, 2.13.0: `cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked`. `make lint` fails when another release is installed.
- The Android NDK release Flutter names (`flutter.ndkVersion` in `app/android/app/build.gradle.kts`), for the bridge crate's Android build.
- jq, which `make lint` uses to list the engine's cargo targets, to read service-role keys' JWT payloads, and to read `app/config/dev.json`.
- uv, only to regenerate the engine's reference values; it fetches the Python and the py-fsrs version the generator pins.

## Run the app

```sh
cd app
flutter run --dart-define-from-file=config/dev.json
```

Without the file the app still runs, with Google sign-in unavailable.

## Run the checks

- `make lint` — checks Markdown Contents lists, fails on a Supabase secret or service-role key in any file, checks that the iOS URL scheme matches the iOS client ID in `app/config/dev.json`, checks that the app's committed generated code (flutter_rust_bridge's included) matches its generators, runs `flutter analyze` over the app's Dart files, and runs clippy over the engine and the bridge crate with warnings denied.
- `make format` — fails when a Dart file in the app or a Rust file in the engine or the bridge crate is not formatted; `dart format` or `cargo fmt` fixes it.
- `make test` — builds the bridge crate for this host, then runs the app's tests, given `app/config/dev.json`, the engine's tests, and the database tests in `supabase/tests/` on a throwaway local stack of their own (`supabase/test-db.sh`), stopped afterwards, so concurrent checkouts do not collide and a running local stack is left untouched. Without Docker it skips the database tests and prints why.
- `make build` — builds, given `app/config/dev.json`, a debug Android APK holding the bridge library, on macOS also the iOS simulator app without code signing, and the engine crate with its rustdoc, warnings denied. It reports which builds it ran.
- `make ci` — runs all four in that order. CI runs the same target.

## Run the backend locally

```sh
supabase start
supabase db reset
supabase test db
supabase stop
```

- `supabase start` runs the local stack from `supabase/config.toml` and applies the migrations in `supabase/migrations/`. It needs Docker.
- `supabase db reset` recreates the local database from the migrations, deleting its rows.
- `supabase test db` runs the pgTAP tests in `supabase/tests/`.
- `supabase stop` stops the stack.

The schema is described in `docs/architecture/server.md`. Only the PM applies a migration to the remote project, with `supabase db push`, after its pull request merges.
