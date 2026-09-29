#!/bin/bash
# Installs the fleet's instructions and room-independent skills into a cloud
# session's ~/.claude. The environment's setup script runs it as root, and
# cloud sessions also run as root with HOME=/root, so $HOME is the right target.
# Copies with -L: some room skills are relative symlinks, and the fleet
# checkout may not outlive setup.
set -euo pipefail
FLEET="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST/skills"

{
  cat "$FLEET/global/manual.md"
  echo
  cat "$FLEET/global/cloud/claude.md"
  echo
  cat "$FLEET/skills/room/no-ai-slop/references/response-rules.md"
} > "$DEST/CLAUDE.md"

SKILLS="$(grep -Ev '^(#|[[:space:]]*$)' "$FLEET/global/cloud/skills.txt")"
for skill in $SKILLS; do
  rm -rf "${DEST:?}/skills/$skill"
  cp -rL "$FLEET/skills/room/$skill" "$DEST/skills/$skill"
done
echo "cloud-setup: $(wc -w <<<"$SKILLS") skills and CLAUDE.md in $DEST"
