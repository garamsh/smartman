.PHONY: lint format test build ci

# Every Dart file under app/ that git tracks or would track; ignored output such as
# build/ and .dart_tool/ stays out. Printed beside each count so the coverage reads true.
DART_SCOPE := git ls-files --cached --others --exclude-standard -- '*.dart'
DART_FILES = files=$$($(DART_SCOPE)); \
	if [ -z "$$files" ]; then echo "no Dart file was selected by: $(DART_SCOPE)" >&2; exit 1; fi

# The same selection for Rust files under each crate; target/ is ignored output.
RUST_SCOPE := git ls-files --cached --others --exclude-standard -- '*.rs'
RUST_FILES = files=$$($(RUST_SCOPE)); \
	if [ -z "$$files" ]; then echo "no Rust file was selected by: $(RUST_SCOPE)" >&2; exit 1; fi
# The engine crate, and the bridge crate flutter_rust_bridge builds into the app.
RUST_CRATES := engine app/rust
# Every target cargo compiles for the crate's Cargo.toml, as "<kind> <name>".
RUST_TARGETS := cargo metadata --no-deps --format-version 1 | jq -r '.packages[].targets[] | "\(.kind[0]) \(.name)"'

# What make build produces, relative to app/, and the bridge crate library each must hold.
APK := build/app/outputs/flutter-apk/app-debug.apk
IOS_APP := build/ios/iphonesimulator/Runner.app
BRIDGE_LIB := rust_lib_smartman

lint:
	./check-contents-list.sh
	./check-generated.sh
	cd app && $(DART_FILES); \
	flutter analyze $$files && \
	echo "analyzed $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"
	for crate in $(RUST_CRATES); do \
		(cd $$crate && cargo clippy --locked --all-targets -- -D warnings) || exit 1; \
		targets=$$(cd $$crate && $(RUST_TARGETS)); \
		if [ -z "$$targets" ]; then echo "cargo selected no target in $$crate/" >&2; exit 1; fi; \
		echo "clippy checked $$(echo "$$targets" | wc -l | tr -d ' ') cargo targets in $$crate/, selected by cargo --all-targets:"; \
		echo "$$targets"; \
	done

format:
	cd app && $(DART_FILES); \
	dart format --output=none --set-exit-if-changed $$files && \
	echo "format checked $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"
	for crate in $(RUST_CRATES); do \
		(cd $$crate && $(RUST_FILES); \
		edition=$$(sed -n 's/^edition = "\(.*\)"/\1/p' Cargo.toml); \
		rustfmt --edition "$$edition" --check $$files && \
		echo "format checked $$(echo "$$files" | wc -l | tr -d ' ') Rust files in $$crate/, selected by: $(RUST_SCOPE)") || exit 1; \
	done

test:
	cd app/rust && cargo build --locked --release && \
	echo "built the bridge library into app/rust/target/release/, where flutter_rust_bridge loads it under flutter test"
	cd app && flutter test --reporter expanded && \
	echo "ran the tests flutter test selects by default: app/test/**/*_test.dart"
	cd engine && cargo test --locked && \
	echo "ran the tests cargo test selects by default in engine/: unit tests in src/, engine/tests/*.rs, doc tests"

build:
	cd app && flutter build apk --debug && \
	libs=$$(unzip -Z1 $(APK) 'lib/*/lib$(BRIDGE_LIB).so'); \
	if [ -z "$$libs" ]; then echo "app/$(APK) holds no lib$(BRIDGE_LIB).so" >&2; exit 1; fi; \
	echo "built the debug APK app/$(APK), holding the bridge library for $$(echo "$$libs" | wc -l | tr -d ' ') ABIs:"; \
	echo "$$libs"
	if [ "$$(uname -s)" = Darwin ]; then \
		cd app && flutter build ios --simulator --debug --no-codesign && \
		test -f $(IOS_APP)/Frameworks/$(BRIDGE_LIB).framework/$(BRIDGE_LIB) && \
		echo "built the unsigned iOS simulator app app/$(IOS_APP), holding $(BRIDGE_LIB).framework"; \
	else \
		echo "skipped the iOS simulator build: it needs macOS, and this host is $$(uname -s)"; \
	fi
	cd engine && cargo build --locked && \
	RUSTDOCFLAGS='-D warnings' cargo doc --locked --no-deps && \
	echo "built the library crate smartman_engine and its rustdoc from engine/Cargo.toml"

ci: lint format test build
