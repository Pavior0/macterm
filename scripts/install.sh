#!/usr/bin/env bash
set -euo pipefail

# `dev-install` overrides both paths so the private build can coexist with the
# release app. The default remains the existing release install.
SOURCE_APP="${MACTERM_INSTALL_SOURCE_APP:-./build/export/Macterm.app}"
DESTINATION_APP="${MACTERM_INSTALL_DESTINATION_APP:-/Applications/Macterm.app}"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "ERROR: source app not found at $SOURCE_APP" >&2
  exit 1
fi

case "$DESTINATION_APP" in
  /Applications/*.app) ;;
  *)
    echo "ERROR: install destination must be an app under /Applications: $DESTINATION_APP" >&2
    exit 1
    ;;
esac

rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"

codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"
