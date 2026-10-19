#!/bin/sh
# Checks docs/architecture/README.md §Index against the responsibility documents and the ADRs, both
# ways, per that file's §Rules, rule 4: every document has exactly one line, every line names a
# file, and the ADRs are listed in number order, the template apart. The files are selected by
# $scope and the count is printed with $scope. $scope runs through eval, as a shell runs it when
# pasted, so the text printed is the text run.
set -euf

index="docs/architecture/README.md"
scope="git ls-files --cached --others --exclude-standard -- 'docs/architecture/*.md' 'docs/architecture/adr/*.md'"

cd "$(dirname "$0")"

files=$(eval "$scope" | awk -v index_file="$index" '$0 != index_file')
count=$(printf '%s\n' "$files" | awk 'NF { n++ } END { print n + 0 }')

# Each index line's path, relative to docs/architecture/, with its line number.
lines=$(awk '
	/^```/ { fence = 1 - fence; next }
	fence { next }
	/^## / { listing = ($0 == "## Index"); next }
	listing && /^- `[^`]+` — / {
		name = substr($0, 4)
		sub(/`.*/, "", name)
		print NR " " name
	}
' "$index")
line_count=$(printf '%s\n' "$lines" | awk 'NF { n++ } END { print n + 0 }')

problems=$(printf '%s\n' "$files" | LINES="$lines" awk -v index_file="$index" '
	BEGIN {
		n = split(ENVIRON["LINES"], entry, "\n")
		for (i = 1; i <= n; i++) {
			if (entry[i] == "") continue
			split(entry[i], part, " ")
			at = part[1]; name = part[2]
			listed[name]++
			where[name] = where[name] (where[name] == "" ? "" : ", ") at
			# ADRs in number order; the template, adr/0000-template.md, stands apart.
			if (name ~ /^adr\/[0-9][0-9][0-9][0-9]-/ && name != "adr/0000-template.md") {
				number = substr(name, 5, 4) + 0
				if (seen_adr && number < last)
					print index_file ":" at ": " name " is listed after ADR " sprintf("%04d", last)
				seen_adr = 1; last = number
			}
		}
	}
	NF {
		base = $0
		sub(/^docs\/architecture\//, "", base)
		present[base] = 1
		if (!(base in listed)) print $0 ": no line in " index_file
		else if (listed[base] > 1) print $0 ": " listed[base] " lines in " index_file ", at lines " where[base]
	}
	END {
		for (name in listed)
			if (!(name in present))
				print index_file ":" where[name] ": names " name ", which is not a selected file"
	}
')
[ -z "$problems" ] || printf '%s\n' "$problems"

echo "checked $count architecture documents against $line_count index lines in $index, selected by: $scope"
if [ "$count" -eq 0 ] || [ "$line_count" -eq 0 ]; then
	echo "no architecture document or no index line was read" >&2
	exit 1
fi
status=0
if [ -n "$problems" ]; then
	echo "rule: docs/architecture/README.md §Rules, rule 4, \"Keep this index current: every responsibility document and every ADR is listed here\"" >&2
	status=1
fi
exit "$status"
