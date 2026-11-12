#!/usr/bin/env bash
# release-notes.sh <tag>: GitHub release notes in PortKiller's style (changelogithub, grouped by
# Conventional Commit type and scope), ending with a short note about hamur.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:?usage: release-notes.sh <tag>}"
PREV=$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)

if [ -n "$PREV" ]; then
  # changelogithub prints a "new release" link in dry-run mode; its body parameter is the changelog.
  LINK=$(npx -y changelogithub --dry --from "$PREV" --to "$TAG" 2>&1 | grep -o 'https://github.com/[^ ]*releases/new?[^ ]*' | tail -1)
  python3 -c 'import sys, urllib.parse as u; print(u.parse_qs(u.urlsplit(sys.argv[1]).query)["body"][0])' "$LINK"
elif [ -f "release-notes/${TAG#v}.md" ]; then
  cat "release-notes/${TAG#v}.md"
fi

cat <<'HAMUR'

---

<a href="https://hamur.dev"><img alt="Sponsored by hamur" src="https://raw.githubusercontent.com/productdevbook/lamba/main/.github/assets/sponsor-dark.png"></a>

Lamba is made by the people behind **[hamur](https://hamur.dev)**: headless UI components for React, Vue, Svelte, Angular and Solid, written once and tested the same way in every framework.
HAMUR
