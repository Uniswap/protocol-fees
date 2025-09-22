#!/bin/bash

forge doc --out ../forge-docs

# copy all .md files from ../forge-docs to ./docs/pages/technical-reference, stripping the `<filetype>.<filename>.md` to just `<filename>.md`
mkdir -p ./docs/pages/technical-reference
find ../forge-docs -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
  base=$(basename "$file")
  new="${base#*.}"
  cp "$file" "./docs/pages/technical-reference/$new"
done

# use sed to modify the reference/linking of inheritance
# convert [INonce](/src/interfaces/base/INonce.sol/interface.INonce.md)
# to [INonce](/technical-reference/INonce)
# Use a portable approach that handles both GNU (Linux) and BSD (macOS) sed
# Match the final filename (without .md) and replace the whole parenthetical link with /technical-reference/<filename>
if sed --version >/dev/null 2>&1; then
  # GNU sed
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i -E 's|\(/src/[^)]+/[^/]*\.([^/]+)\.md\)|(/technical-reference/\1)|g' "$file"
  done
else
  # BSD sed (macOS)
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i '' -E 's|\(/src/[^)]+/[^/]*\.([^/]+)\.md\)|(/technical-reference/\1)|g' "$file"
  done
fi

# use sed to replace `| token0Fee` with `\| token0Fee` in all .md files in ./docs/pages/technical-reference
if sed --version >/dev/null 2>&1; then
  # GNU sed
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i -e 's/| token0Fee/\\| token0Fee/g' "$file"
  done
else
  # BSD sed (macOS)
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i '' -e 's/| token0Fee/\\| token0Fee/g' "$file"
  done
fi

# use sed to replace << with \<\< in all .md files in ./docs/pages/technical-reference
if sed --version >/dev/null 2>&1; then
  # GNU sed
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i -e 's/<< /\\<\\< /g' "$file"
  done
else
  # BSD sed (macOS)
  find ./docs/pages/technical-reference -type f -name "*.md" -print0 | while IFS= read -r -d '' file; do
    sed -i '' -e 's/<< /\\<\\< /g' "$file"
  done
fi

rm -rf ../forge-docs
