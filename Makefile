.PHONY: lint format test build ci

# Every Dart file under app/ that git tracks or would track; ignored output such as
# build/ and .dart_tool/ stays out. Printed beside each count so the coverage reads true.
DART_SCOPE := git ls-files --cached --others --exclude-standard -- '*.dart'
DART_FILES = files=$$($(DART_SCOPE)); \
	if [ -z "$$files" ]; then echo "no Dart file was selected by: $(DART_SCOPE)" >&2; exit 1; fi

lint:
	./check-contents-list.sh
	cd app && $(DART_FILES); \
	flutter analyze $$files && \
	echo "analyzed $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"

format:
	cd app && $(DART_FILES); \
	dart format --output=none --set-exit-if-changed $$files && \
	echo "format checked $$(echo "$$files" | wc -l | tr -d ' ') Dart files in app/, selected by: $(DART_SCOPE)"

test:
	cd app && flutter test --reporter expanded && \
	echo "ran the tests flutter test selects by default: app/test/**/*_test.dart"

build:
	cd app && flutter build apk --debug

ci: lint format test build
