#!/usr/bin/env bash
#
#  build-documentation.sh
#  Builds the DocC documentation for the Swift library.
#
#  This package is built by CMake rather than by SwiftPM, so there is no
#  docc plugin to lean on. The symbol graph comes from the compiler and docc
#  turns it, together with the catalogue, into a site.
#
#  Pass --host to build for GitHub Pages, which needs every link prefixed with
#  the repository name.
#
#  Copyright © 2026 cocoa:naut. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

moduleName="PlayableAirplay"
symbolDirectory="build/symbol-graph"
outputDirectory="build/documentation"

hostingArguments=()
if [[ "${1:-}" == "--host" ]]; then
    hostingArguments=(--hosting-base-path "$moduleName")
fi

rm -rf "$symbolDirectory" "$outputDirectory"
mkdir -p "$symbolDirectory"

# The module is compiled only to get its symbols, so the object file goes away
# with the temporary directory it was written into.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

swiftc -emit-symbol-graph -emit-symbol-graph-dir "$symbolDirectory" \
    -emit-module -module-name "$moduleName" \
    -I include \
    Sources/"$moduleName".swift \
    -o "$scratch/$moduleName.o"

# docc lives in the toolchain, which is reached through xcrun on macOS and is
# on the path everywhere else.
docc=docc
if command -v xcrun > /dev/null 2>&1; then
    docc="$(xcrun --find docc)"
fi

# A link to a symbol that was renamed away is documentation that lies, and the
# only moment it is cheap to find is this one.
"$docc" convert "Sources/$moduleName.docc" \
    --fallback-display-name "$moduleName" \
    --fallback-bundle-identifier "at.playable.airplay" \
    --fallback-bundle-version "1" \
    --additional-symbol-graph-dir "$symbolDirectory" \
    --output-path "$outputDirectory" \
    --warnings-as-errors \
    "${hostingArguments[@]}"

if [[ ${#hostingArguments[@]} -gt 0 ]]; then
    # Every page below carries its own index.html, so the one at the root has
    # nothing to show. It sends a reader to the landing page instead.
    landing="/$moduleName/documentation/$(echo "$moduleName" | tr '[:upper:]' '[:lower:]')/"
    cat > "$outputDirectory/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$moduleName</title>
<meta http-equiv="refresh" content="0; url=$landing">
<link rel="canonical" href="$landing">
</head>
<body><a href="$landing">$moduleName documentation</a></body>
</html>
HTML
fi

echo "documentation written to $outputDirectory"
