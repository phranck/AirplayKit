#!/usr/bin/env bash
#
#  build-site.sh
#  Builds the site: the page at the root, the DocC reference under /docs.
#
#  The symbol graph comes from the compiler and docc turns it, together with the
#  catalogue, into a site of its own. It does not go through the docc plugin,
#  because one swiftc call over one file is less machinery than a plugin is.
#
#  The reference is served from /docs wherever the site stands, so it is always
#  built to say so. Serve build/site and both halves work.
#
#  Copyright © 2026 LAYERED. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

moduleName="PlayableAirplay"
symbolDirectory="build/symbol-graph"
siteDirectory="build/site"

rm -rf "$symbolDirectory" "$siteDirectory"
mkdir -p "$symbolDirectory" "$siteDirectory"

# The module is compiled only to get its symbols, so the object file goes away
# with the temporary directory it was written into.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# The library imports the sender, which is a Swift module rather than a header,
# so it has to exist before the compiler can be asked about anything. Building
# the package is how it comes to exist, and where it lands is what the bin path
# names.
swift build > /dev/null
binPath="$(swift build --show-bin-path)"

# Where a built module lands differs by build system: beside the products under
# one and in a Modules directory under the other. Both are offered and the
# compiler takes whichever exists.
moduleSearch=(-I "$binPath")
if [[ -d "$binPath/Modules" ]]; then
    moduleSearch+=(-I "$binPath/Modules")
fi

swiftc -emit-symbol-graph -emit-symbol-graph-dir "$symbolDirectory" \
    -emit-module -module-name "$moduleName" \
    -I Sources/CPlayableAirplay/include \
    "${moduleSearch[@]}" \
    Sources/"$moduleName"/"$moduleName".swift \
    -o "$scratch/$moduleName.o"

# docc lives in the toolchain, which is reached through xcrun on macOS and is
# on the path everywhere else.
docc=docc
if command -v xcrun > /dev/null 2>&1; then
    docc="$(xcrun --find docc)"
fi

# A link to a symbol that was renamed away is documentation that lies, and the
# only moment it is cheap to find is this one.
"$docc" convert "Sources/$moduleName/$moduleName.docc" \
    --fallback-display-name "$moduleName" \
    --fallback-bundle-identifier "at.playable.airplay" \
    --fallback-bundle-version "1" \
    --additional-symbol-graph-dir "$symbolDirectory" \
    --output-path "$siteDirectory/docs" \
    --warnings-as-errors \
    --hosting-base-path "docs"

cp -R Website/. "$siteDirectory/"

# The page holds a marker where a snippet goes, and the snippet comes out of the
# example that CI compiles. So the page cannot show code that stopped working.
python3 Scripts/fill-snippets.py "$siteDirectory/index.html" Sources/Demo/Demo.swift

# DocC opens on its own landing page, which is one click further in than the
# link from the site suggests. This sends a reader straight there.
documentationPath="/docs/documentation/$(echo "$moduleName" | tr '[:upper:]' '[:lower:]')/"

# The reference is the renderer's own application and brings its own
# stylesheet. This adds the site's typefaces to it, on every page, because each
# page carries its own shell.
cp Website/docs-theme/fonts.css "$siteDirectory/docs/playable-fonts.css"
python3 Scripts/inject-stylesheet.py "$siteDirectory/docs" /docs/playable-fonts.css

cat > "$siteDirectory/docs/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$moduleName reference</title>
<meta http-equiv="refresh" content="0; url=$documentationPath">
<link rel="canonical" href="$documentationPath">
</head>
<body><a href="$documentationPath">$moduleName reference</a></body>
</html>
HTML

echo "site written to $siteDirectory"
