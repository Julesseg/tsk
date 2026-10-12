#!/usr/bin/env bash
# One-shot rename of the template's placeholder identity.
#
#   scripts/rename.sh <AppName> <bundle.identifier>
#   e.g. scripts/rename.sh Zenith com.acme.zenith
#
# Replaces every occurrence of the placeholders and renames the files/dirs
# that carry them, keeping the Xcode project, workflows, hooks, and Core
# package consistent:
#   MyApp            -> <AppName>        (project, scheme, targets, MyAppCore -> <AppName>Core)
#   com.example.myapp -> <bundle.id>     (PRODUCT_BUNDLE_IDENTIFIER, release.yml)
#
# <AppName> must be a valid Swift identifier (it names the app target and the
# Core module). Run from anywhere inside the repo; requires a clean-ish tree
# so you can review the result with `git diff`.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <AppName> <bundle.identifier>" >&2
  exit 1
fi

NAME="$1"
BUNDLE="$2"

if ! [[ "$NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "error: '$NAME' is not a valid Swift identifier (letters, digits, _; no leading digit)" >&2
  exit 1
fi
if ! [[ "$BUNDLE" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "error: '$BUNDLE' does not look like a bundle identifier" >&2
  exit 1
fi

cd "$(git rev-parse --show-toplevel)"

# BSD (macOS) and GNU sed disagree on -i's argument.
sedi() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

# 1. Replace placeholder strings in every tracked text file (skipping this
#    script, so the placeholders below stay literal).
git ls-files -z | while IFS= read -r -d '' f; do
  [ "$f" = "scripts/rename.sh" ] && continue
  LC_ALL=C sedi \
    -e "s/com\.example\.myapp/${BUNDLE}/g" \
    -e "s/MyApp/${NAME}/g" \
    "$f"
done

# 2. Rename the paths that embed the placeholder name (deepest first).
mv App/MyApp.xcodeproj/xcshareddata/xcschemes/MyApp.xcscheme \
   "App/MyApp.xcodeproj/xcshareddata/xcschemes/${NAME}.xcscheme"
mv App/MyApp/MyApp.entitlements "App/MyApp/${NAME}.entitlements"
mv App/MyApp/MyAppApp.swift "App/MyApp/${NAME}App.swift"
mv App/MyAppUITests/MyAppUITests.swift "App/MyAppUITests/${NAME}UITests.swift"
mv App/MyApp "App/${NAME}"
mv App/MyAppUITests "App/${NAME}UITests"
mv App/MyApp.xcodeproj "App/${NAME}.xcodeproj"
mv Core/Sources/MyAppCore "Core/Sources/${NAME}Core"
mv Core/Tests/MyAppCoreTests "Core/Tests/${NAME}CoreTests"

echo "Renamed to ${NAME} (${BUNDLE})."
echo "Review with: git diff && git status"
echo "Then verify: cd Core && swift test"
