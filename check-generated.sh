#!/bin/sh
# Fails when committed generated code in app/ differs from what its generators write
# from the current sources. Each file in $scope is hashed, every generator is rerun
# with the command its documentation gives, and the set is hashed again; a changed,
# added or removed file is stale output. Hashing the working tree rather than diffing
# the index keeps the check true on an uncommitted edit as well as on a clean checkout.
set -euf

scope="git ls-files --cached --others --exclude-standard -- 'lib/*.g.dart' 'lib/*.steps.dart' 'lib/shared/l10n/app_localizations*.dart' 'drift_schemas' 'test/drift/*/generated/*' 'lib/study/src/rust' 'rust/src/frb_generated.rs'"

cd "$(dirname "$0")/app"

snapshot() {
	eval "$scope" | sort | while IFS= read -r file; do
		[ -f "$file" ] && printf '%s %s\n' "$(git hash-object "$file")" "$file"
	done
}

before=$(snapshot)
if [ -z "$before" ]; then
	echo "no generated file was selected by: $scope" >&2
	exit 1
fi

# The codegen must be the release of the flutter_rust_bridge crate in rust/Cargo.lock.
frb_version=$(sed -n '/^name = "flutter_rust_bridge"$/{n;s/^version = "\(.*\)"$/\1/p;}' rust/Cargo.lock)
if [ "$(flutter_rust_bridge_codegen --version)" != "flutter_rust_bridge_codegen $frb_version" ]; then
	echo "flutter_rust_bridge_codegen $frb_version is required, as rust/Cargo.lock pins; found: $(flutter_rust_bridge_codegen --version)" >&2
	exit 1
fi
flutter_rust_bridge_codegen generate
dart run build_runner build
flutter gen-l10n
# Exits non-zero when the dump for the current schema version differs from the schema.
dart run drift_dev make-migrations
# One directory per database; set -f keeps a glob from expanding, so ls names them.
for database in $(ls drift_schemas); do
	dart run drift_dev schema generate --data-classes --companions \
		"drift_schemas/$database/" "test/drift/$database/generated/"
done

after=$(snapshot)
if [ "$before" != "$after" ]; then
	echo "generated code is stale; regenerate it and commit the result:" >&2
	echo "$before" > "${TMPDIR:-/tmp}/generated-before.$$"
	echo "$after" > "${TMPDIR:-/tmp}/generated-after.$$"
	diff "${TMPDIR:-/tmp}/generated-before.$$" "${TMPDIR:-/tmp}/generated-after.$$" >&2 || true
	rm -f "${TMPDIR:-/tmp}/generated-before.$$" "${TMPDIR:-/tmp}/generated-after.$$"
	exit 1
fi

echo "checked $(echo "$after" | wc -l | tr -d ' ') generated files in app/ against their generators, selected by: $scope"
