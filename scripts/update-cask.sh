#!/bin/sh
# Points the Homebrew cask at a published release and opens a PR on the tap.
#
#   scripts/update-cask.sh <version>        e.g. scripts/update-cask.sh 1.0.3
#
# Needs gh, logged in with push access to the tap. TAP overrides the tap repository.
set -eu

VERSION="${1:?usage: scripts/update-cask.sh <version>}"
REPO="Kombuchelada/fan-control"
TAP="${TAP:-Kombuchelada/homebrew-tap}"
CASK="Casks/fan-control.rb"
URL="https://github.com/$REPO/releases/download/v$VERSION/Fan-Control.zip"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl -fsSL -o "$WORK/Fan-Control.zip" "$URL"
SHA="$(shasum -a 256 "$WORK/Fan-Control.zip" | cut -d' ' -f1)"

gh repo clone "$TAP" "$WORK/tap" -- -q
cd "$WORK/tap"
BRANCH="fan-control-$VERSION"
git switch -q -c "$BRANCH"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
if git diff --quiet; then
    echo "The cask already points at $VERSION."
    exit 0
fi
git diff
git commit -qam "fan-control $VERSION"
git push -q -u origin "$BRANCH"
gh pr create --repo "$TAP" --base main --head "$BRANCH" \
    --title "fan-control $VERSION" \
    --body "Updates the fan-control cask to [$VERSION](https://github.com/$REPO/releases/tag/v$VERSION). sha256 computed from the published zip."
