.PHONY: lint format test build ci

# Every Dart file under app/ that git tracks or would track; ignored output such as
# build/ and .dart_tool/ stays out. Printed beside each count so the coverage reads true.
DART_SCOPE := git ls-files --cached --others --exclude-standard -- '*.dart'
DART_FILES = files=$$($(DART_SCOPE)); \
	if [ -z "$$files" ]; then echo "no Dart file was selected by: $(DART_SCOPE)" >&2; exit 1; fi

# The same selection for Rust files under engine/; target/ is ignored output.
RUST_SCOPE := git ls-files --cached --others --exclude-standard -- '*.rs'
RUST_FILES = files=$$($(RUST_SCOPE)); \
	if [ -z "$$files" ]; then echo "no Rust file was selected by: $(RUST_SCOPE)" >&2; exit 1; fi
# Every target cargo compiles for engine/Cargo.toml, as "<kind> <name>".
RUST_TARGETS := cargo metadata --no-deps --format-version 1 | jq -r '.packages[].targets[] | "\(.kind[0]) \(.name)"'

lint:
	./check-contents-list.sh
	./check-generated.sh
	cd app && $(DART_FILES); \
	flutter analyze $$files && \
	echo "analyzed $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"
	cd engine && cargo clippy --locked --all-targets -- -D warnings
	cd engine && targets=$$($(RUST_TARGETS)); \
	if [ -z "$$targets" ]; then echo "cargo selected no target in engine/" >&2; exit 1; fi; \
	echo "clippy checked $$(echo "$$targets" | wc -l | tr -d ' ') cargo targets in engine/, selected by cargo --all-targets:"; \
	echo "$$targets"

format:
	cd app && $(DART_FILES); \
	dart format --output=none --set-exit-if-changed $$files && \
	echo "format checked $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"
	cd engine && $(RUST_FILES); \
	edition=$$(sed -n 's/^edition = "\(.*\)"/\1/p' Cargo.toml); \
	rustfmt --edition "$$edition" --check $$files && \
	echo "format checked $$(echo "$$files" | wc -l | tr -d ' ') Rust files in engine/, selected by: $(RUST_SCOPE)"

test:
	cd app && flutter test --reporter expanded && \
	echo "ran the tests flutter test selects by default: app/test/**/*_test.dart"
	cd engine && cargo test --locked && \
	echo "ran the tests cargo test selects by default in engine/: unit tests in src/, engine/tests/*.rs, doc tests"

build:
	cd app && flutter build apk --debug
	cd engine && cargo build --locked && \
	RUSTDOCFLAGS='-D warnings' cargo doc --locked --no-deps && \
	echo "built the library crate smartman_engine and its rustdoc from engine/Cargo.toml"

ci: lint format test build
