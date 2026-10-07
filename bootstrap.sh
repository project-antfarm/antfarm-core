#!/usr/bin/env bash
# Turn an existing, empty-or-not GitHub repository into an Antfarm specimen.
# Idempotent: safe to rerun. Needs gh (logged in as a repository admin), jq.
#
# usage: bootstrap.sh <owner/repo> [core-sha]
#   core-sha defaults to the HEAD of this checkout. It is written into the
#   caller workflows (uses: ...@sha and core_ref), so commit this repository
#   before bootstrapping a specimen from it.
#
# What it does, in order:
#   1. copies template/ into a fresh clone of the specimen (never overwrites
#      GOAL.md, config.yml or toolkit.yml that already exist) and pushes main;
#   2. creates the colony labels;
#   3. creates the `main` ruleset from ruleset.json;
#   4. sets the repository variable ANTFARM_ENABLED=false (the human flips it);
#   5. creates the status Issue (#1 on a new repository) with label colony-status.
#
# What it cannot do, and prints at the end: install the four GitHub Apps on the
# specimen, add the secrets (or make the organisation secrets visible to it),
# enable GitHub Pages, and write GOAL.md.
set -euo pipefail
repo=${1:?usage: bootstrap.sh <owner/repo> [core-sha]}
here=$(cd "$(dirname "$0")" && pwd)
sha=${2:-$(git -C "$here" rev-parse HEAD)}
[ -z "$(git -C "$here" status --porcelain)" ] || echo "warning: this checkout has uncommitted changes; the pinned sha $sha may not contain them" >&2

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
gh repo clone "$repo" "$work/spec" -- -q
cd "$work/spec"
git checkout -q -B main 2>/dev/null || true

# 1. files
(cd "$here/template" && find . -type f) | while read -r f; do
  case "$f" in ./GOAL.md|./.antfarm/config.yml|./.antfarm/toolkit.yml) [ -e "$f" ] && continue;; esac
  mkdir -p "$(dirname "$f")"
  sed "s/CORE_SHA/$sha/g" "$here/template/$f" > "$f"
done
cp "$here/.gitattributes" .gitattributes
git add -A
if ! git diff --cached --quiet; then
  git -c user.name="antfarm bootstrap" -c user.email="bootstrap@antfarm.invalid" commit -qm "ci(antfarm): bootstrap specimen from antfarm-core ${sha:0:12}"
  git push -q -u origin main
fi

# 2. labels
jq -c '.[]' "$here/labels.json" | while read -r l; do
  name=$(jq -r .name <<<"$l"); color=$(jq -r .color <<<"$l"); desc=$(jq -r '.description // ""' <<<"$l")
  gh label create "$name" -R "$repo" --color "$color" --description "$desc" --force >/dev/null
done
echo "labels: ok"

# 3. ruleset (create or update by name)
rid=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name=="main") | .id' 2>/dev/null || true)
if [ -n "$rid" ]; then
  gh api -X PUT "repos/$repo/rulesets/$rid" --input "$here/ruleset.json" >/dev/null && echo "ruleset: updated"
else
  gh api -X POST "repos/$repo/rulesets" --input "$here/ruleset.json" >/dev/null && echo "ruleset: created"
fi

# 4. kill switch, off until the human flips it
gh variable set ANTFARM_ENABLED -R "$repo" --body false
echo "variable: ANTFARM_ENABLED=false"

# 5. status Issue
if [ "$(gh issue list -R "$repo" --label colony-status --state all --json number --jq length)" = 0 ]; then
  gh issue create -R "$repo" --title "Colony status" --label colony-status \
    --body "Status of the colony, rewritten by the infrastructure after every execution. Not a log." >/dev/null
  echo "status issue: created"
fi

cat <<EOF

Done. Remaining steps for the human, in the GitHub UI:
  - Install the Apps antfarm-queen, antfarm-worker, antfarm-oracle and antfarm-telemetry on $repo.
  - Secrets visible to $repo (organisation secrets or repository secrets):
      CLAUDE_CODE_OAUTH_TOKEN, CODEX_MENTION_TOKEN,
      QUEEN_APP_ID, QUEEN_APP_PRIVATE_KEY, WORKER_APP_ID, WORKER_APP_PRIVATE_KEY,
      ORACLE_APP_ID, ORACLE_APP_PRIVATE_KEY, TELEMETRY_APP_ID, TELEMETRY_APP_PRIVATE_KEY
  - Enable GitHub Pages from main / (root) if the product is a static site.
  - Write GOAL.md, set run: in .antfarm/config.yml, then set ANTFARM_ENABLED=true.
EOF
