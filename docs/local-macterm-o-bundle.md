# Local Macterm O bundle

This checkout's Release build is installed alongside the normal Macterm and
Macterm Dev applications as `Macterm O`.

## Current installation

- App: `/Applications/Macterm O.app`
- Bundle ID: `com.thdxg.macterm.o`
- Display name: `Macterm O`
- Source branch: `feat/horizontal-tabs`
- Source commit: `4944eb1646083c708950d0b6874c1742aa7027fe` plus this checkout's current changes
- Build configuration: `Release`
- Marketing version: `0.0.0`
- Bundle version: `0.0.0.9999`
- Update channel: `stable`
- Architectures: `arm64`, `x86_64`
- Signature: local ad-hoc signature (`TeamIdentifier=not set`)
- Recorded: 2026-09-04

## Update this installation

From the repository root, after switching to the desired commit:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

mise run macterm-o-install --verbose
```

The task runs the repository's format, lint, and test checks, then performs the
equivalent build and install steps below:

```bash
MACTERM_BUILD_DIR="$PWD/build/o" \
MACTERM_BUILD_BUNDLE_ID="com.thdxg.macterm.o" \
MACTERM_BUILD_DISPLAY_NAME="Macterm O" \
  ./scripts/build.sh

MACTERM_INSTALL_SOURCE_APP="$PWD/build/o/export/Macterm.app" \
MACTERM_INSTALL_DESTINATION_APP="/Applications/Macterm O.app" \
  ./scripts/install.sh
```

The build script archives the app with the Release configuration and creates a
DMG under `build/o`; the install step replaces only `/Applications/Macterm O.app`.
