#!/bin/sh
# Checks the tables in docs/convention/README.md §Stack-neutral and §Stack-specific against the
# convention files, both ways, per that file's §Stack-specific: every file has a row and every
# row names a file. The files are selected by $scope and the count is printed with $scope.
# $scope runs through eval, as a shell runs it when pasted, so the text printed is the text run.
set -euf

index="docs/convention/README.md"
scope="git ls-files --cached --others --exclude-standard -- 'docs/convention/*.md'"

cd "$(dirname "$0")"

files=$(eval "$scope" | awk -v index_file="$index" '$0 != index_file')
count=$(printf '%s\n' "$files" | awk 'NF { n++ } END { print n + 0 }')

rows=$(awk '
	/^```/ { fence = 1 - fence; next }
	fence { next }
	/^## / { table = ($0 == "## Stack-neutral" || $0 == "## Stack-specific"); next }
	table && /^\| `[^`]+` \|/ {
		name = substr($0, 4)
		sub(/`.*/, "", name)
		print name
	}
' "$index")
row_count=$(printf '%s\n' "$rows" | awk 'NF { n++ } END { print n + 0 }')

problems=$(printf '%s\n' "$files" | ROWS="$rows" awk -v index_file="$index" '
	BEGIN {
		n = split(ENVIRON["ROWS"], row, "\n")
		for (i = 1; i <= n; i++) if (row[i] != "") named[row[i]] = 1
	}
	NF {
		base = $0
		sub(/^docs\/convention\//, "", base)
		present[base] = 1
		if (!(base in named)) print $0 ": no row in " index_file
	}
	END {
		for (i = 1; i <= n; i++)
			if (row[i] != "" && !(row[i] in present))
				print index_file ": row names " row[i] ", which is not a selected file"
	}
')
[ -z "$problems" ] || printf '%s\n' "$problems"

echo "checked $count convention files against $row_count index rows in $index, selected by: $scope"
if [ "$count" -eq 0 ] || [ "$row_count" -eq 0 ]; then
	echo "no convention file or no index row was read" >&2
	exit 1
fi
status=0
if [ -n "$problems" ]; then
	echo "rule: docs/convention/README.md §Stack-specific, \"These two tables and those rules are where the split is recorded\"" >&2
	status=1
fi
exit "$status"
