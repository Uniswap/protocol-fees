#!/bin/bash

forge doc --out ../forge-docs

# copy all .md files from ../forge-docs to ./docs/pages/technical-reference
mkdir -p ./docs/pages/technical-reference
find ../forge-docs -type f -name "*.md" -exec cp {} ./docs/pages/technical-reference/ \;

# use sed to modify the reference/linking of inheritance
# convert [INonce](/src/interfaces/base/INonce.sol/interface.INonce.md)
# to [INonce](/technical-reference/interface.INonce)
# Use a portable approach that handles both GNU (Linux) and BSD (macOS) sed
# Match the final filename (without .md) and replace the whole parenthetical link with /technical-reference/<filename>
if sed --version >/dev/null 2>&1; then
  # GNU sed
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i -E 's|\(/src/[^)]+/([^/]+)\.md\)|(/technical-reference/\1)|g' "$file"
  done
else
  # BSD sed (macOS)
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i '' -E 's|\(/src/[^)]+/([^/]+)\.md\)|(/technical-reference/\1)|g' "$file"
  done
fi

rm -rf ../forge-docs
