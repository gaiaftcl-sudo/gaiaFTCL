#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
WIKI_SRC="$REPO_ROOT/docs/wiki"
WIKI_REMOTE="git@github.com:gaiaftcl-sudo/gaiaFTCL.wiki.git"
TMPDIR=$(mktemp -d)

git clone "$WIKI_REMOTE" "$TMPDIR/wiki"
rsync -av --delete --exclude='.git' "$WIKI_SRC/" "$TMPDIR/wiki/"
cd "$TMPDIR/wiki"

if git diff --quiet; then
  echo "CALORIE: wiki already in sync, no publish needed"
  rm -rf "$TMPDIR"
  exit 0
fi

SRC_SHA=$(cd "$REPO_ROOT" && git rev-parse --short HEAD)
git add -A
git commit -S -m "CALORIE(wiki): publish from main@${SRC_SHA}"
git push origin master
rm -rf "$TMPDIR"
echo "CALORIE: wiki published from ${SRC_SHA}"
