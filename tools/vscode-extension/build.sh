#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CURRENT_VERSION=$(node -p "require('./package.json').version")

# Check for changes since last build
LAST_BUILD_HASH=""
if [ -f ".last-build-hash" ]; then
    LAST_BUILD_HASH=$(cat .last-build-hash)
fi

# Hash all source files (exclude node_modules, out, .vsix, and the hash file itself)
CURRENT_HASH=$(find . \
    -not -path './node_modules/*' \
    -not -path './out/*' \
    -not -name '*.vsix' \
    -not -name '.last-build-hash' \
    -type f -print0 | sort -z | xargs -0 cat 2>/dev/null | md5sum | cut -d' ' -f1)

if [ "$CURRENT_HASH" = "$LAST_BUILD_HASH" ]; then
    echo "==> No changes detected since last build (v$CURRENT_VERSION). Skipping."
    exit 0
fi

# Bump patch version
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

echo "==> Building CURSED VS Code extension v$NEW_VERSION"

# Update version in package.json
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('./package.json', 'utf8'));
pkg.version = '$NEW_VERSION';
fs.writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');
"

# Install dependencies
echo "==> Installing dependencies..."
npm install --silent

# Compile TypeScript
echo "==> Compiling TypeScript..."
npx tsc -p ./

# Package the extension
echo "==> Packaging .vsix..."
npx @vscode/vsce package --no-git-tag-version --no-update-package-json -o cursed-lang.vsix

if [ ! -f "cursed-lang.vsix" ]; then
    echo "ERROR: cursed-lang.vsix not found"
    exit 1
fi

# Install into VS Code
echo "==> Installing cursed-lang.vsix..."
code --install-extension cursed-lang.vsix --force

# Save build hash (re-hash after version bump so next run sees the bumped package.json as baseline)
find . \
    -not -path './node_modules/*' \
    -not -path './out/*' \
    -not -name '*.vsix' \
    -not -name '.last-build-hash' \
    -type f -print0 | sort -z | xargs -0 cat 2>/dev/null | md5sum | cut -d' ' -f1 > .last-build-hash

echo "==> Done! CURSED Language v$NEW_VERSION installed."
echo "    Reload VS Code window to activate (Ctrl+Shift+P > Developer: Reload Window)"
