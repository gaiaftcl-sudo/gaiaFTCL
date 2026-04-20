#!/usr/bin/env bash
# Wiki hygiene: flag markdown links whose target looks like a raw *.md path,
# except GitHub /blob/ URLs (allowed for main-branch file pointers).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
FAIL=0
while IFS= read -r -d '' f; do
  if perl -ne '
    while (/\]\(([^)]*)\)/g) {
      my $u = $1;
      next if $u =~ /^https:\/\// && $u =~ m{/blob/};
      if ($u =~ /\.md(?:#|\?|$)/i || $u =~ /\.md\)$/i) {
        print "$ARGV:$.:$_";
        exit 2;
      }
    }
  ' "$f" 2>/dev/null; then
    :
  else
    ec=$?
    if [[ "$ec" -eq 2 ]]; then
      echo "lint_wiki: FAIL $f — relative or non-blob *.md link target." >&2
      FAIL=1
    fi
  fi
done < <(find . -maxdepth 1 -name '*.md' -print0)

if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
echo "lint_wiki: OK ($ROOT)"
