#!/usr/bin/env bash
#
#  build-and-test.sh
#  Builds the package, runs the tests, and runs the example.
#
#  This is the gate, and it is one file so that what runs locally and what runs
#  in CI cannot drift apart. Scripts/check-linux.sh runs it inside the Swift
#  image, and the workflow runs it on both platforms.
#
#  Pass a scratch directory to keep two platforms' output apart. It defaults to
#  SwiftPM's own .build.
#
#  Copyright © 2026 LAYERED. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Written out at each use as ${scratch[@]+...}, because bash 3.2, which is what
# macOS ships and what the runner uses, treats an empty array as unset under
# set -u and stops there.
scratch=()
if [[ -n "${1:-}" ]]; then
    scratch=(--scratch-path "$1")
fi

echo "== the toolchain"
swift --version

echo "== build"
swift build -c release ${scratch[@]+"${scratch[@]}"}

echo "== test"
swift test ${scratch[@]+"${scratch[@]}"}

# The binary that was just built, rather than swift run, which re-plans the
# build and trips over the debug description the tests left behind.
#
# Called without arguments the example prints its usage and exits with 2, and
# anything else means it is broken.
echo "== the example"
"$(swift build -c release ${scratch[@]+"${scratch[@]}"} --show-bin-path)/Demo" || [[ $? -eq 2 ]]

echo "== all green"
