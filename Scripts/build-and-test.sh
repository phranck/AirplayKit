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

# .swift-version names the compiler this package is built and tested with, and
# the workflow pins both of its runners to it. A gate run on anything else says
# less than it appears to: Swift 6.1.2 rejected code that 6.4 compiled without a
# word, and the difference only showed up after the push.
#
# In CI that is a fault, because the runners are pinned and a disagreement means
# the pin and this file have drifted apart. On a person's machine it is a note,
# since the toolchain there is whichever Xcode they have and this gate is still
# worth running on it.
pinned_version="$(cat .swift-version)"
running_version="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -1)"

if [[ "$running_version" != "$pinned_version" ]]; then
    echo "This is Swift ${running_version}, and .swift-version pins ${pinned_version}." >&2

    if [[ -n "${CI:-}" ]]; then
        echo "The runner is pinned, so this is the pin and .swift-version disagreeing." >&2
        exit 1
    fi

    echo "CI runs ${pinned_version}, so a green run here does not promise a green run there." >&2
fi

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
