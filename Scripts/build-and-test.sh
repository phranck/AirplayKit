#!/usr/bin/env bash
#
#  build-and-test.sh
#  Builds the library, runs the tests, and builds and runs the example.
#
#  This is the gate, and it is one file so that what runs locally and what runs
#  in CI cannot drift apart. Scripts/check-linux.sh runs it inside the Swift
#  image, and the workflow runs it on both platforms.
#
#  Pass a build directory to keep two platforms' output apart. It defaults to
#  build, which is what the README tells a reader to use.
#
#  Copyright © 2026 cocoa:naut. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

buildDirectory="${1:-build}"

if [[ "$(uname)" == "Darwin" ]]; then
    linkFlags=(-lc++ -framework CoreFoundation)
else
    linkFlags=(-lstdc++ -lpthread -ldns_sd)
fi

echo "== the toolchain"
swift --version
cmake --version | head -1

echo "== configure"
cmake -S . -B "$buildDirectory" -DCMAKE_BUILD_TYPE=Release

echo "== build"
cmake --build "$buildDirectory" -j4

echo "== test"
ctest --test-dir "$buildDirectory" --output-on-failure

# The README tells a consumer that the Swift wrapper, the one archive and a
# handful of system libraries are the whole of it. Building the example exactly
# that way is what keeps the instruction honest.
echo "== the example"
swiftc -O -I include Sources/PlayableAirplay.swift example/Demo.swift \
    -o "$buildDirectory/Demo" -Xlinker "$buildDirectory/libPlayableAirplay.a" "${linkFlags[@]}"

# Called without arguments it prints its usage and exits with 2, and anything
# else means it is broken.
"$buildDirectory/Demo" || [[ $? -eq 2 ]]

echo "== all green"
