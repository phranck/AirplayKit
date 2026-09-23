#!/usr/bin/env bash
#
#  check-linux.sh
#  Compiles this package for Linux, here, before anything is pushed.
#
#  What this catches is the thing a Mac cannot tell you: that the code builds
#  against Glibc as well as Darwin, that every header it includes exists on both,
#  and that no API it reaches for is Apple's alone. That is what breaks when a
#  cross-platform package is written on one platform, and it breaks at compile
#  time, which is why compiling is enough to find it.
#
#  What this does not do is run the tests. They run in CI, on Linux, in about
#  twenty seconds, and they are green there. Running them here hangs: the test
#  process deadlocks inside XCTest before the first test body, having used a
#  sixth of a second of processor time in a quarter of an hour. That is #25, and
#  it is reproducible on this machine and on nobody else's. Architecture, the
#  bind mount, swift-testing and the scratch volume have each been ruled out.
#
#  So this gate checks what it can check quickly and certainly, and says so,
#  rather than waiting a quarter of an hour to tell you nothing.
#
#  Copyright © 2026 LAYERED. All rights reserved.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Built from Scripts/linux.Dockerfile, which is the image CI uses with the one
# package this needs already in it. Building it once takes a minute; not having
# it costs most of a minute in every single run.
image="playable-airplay-linux:6.2"

# Where the Linux build lives between runs. Named, so it survives, and so a
# person can find it with `docker volume ls` and remove it when it is in the way.
# It has to stay off the macOS build, which shares nothing with it, and off the
# bind mount, where SwiftPM's build database does not work at all.
volume="playable-airplay-linux-build"

# A name of its own per run, so the container can be found and removed even
# where this script is killed before it can tidy up.
container="playable-airplay-linux-$$"

# Generous, because a cold volume compiles Mbed TLS, the C++ sender and two
# Swift packages from nothing. A warm one is well under a minute.
minutes="${CHECK_LINUX_MINUTES:-20}"

if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, so there is nothing to check Linux in." >&2
    exit 1
fi

if ! docker image inspect "$image" > /dev/null 2>&1; then
    echo "== building the Linux image, once"
    docker build -q -f Scripts/linux.Dockerfile -t "$image" . > /dev/null
fi

# On every path out, including an interrupt and including the bound below. A
# container left running holds a Swift toolchain image and says nothing.
cleanup() {
    docker rm --force "$container" > /dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --rm --name "$container" \
    --volume "$root:/src" \
    --volume "$volume:/build" \
    --workdir /src \
    "$image" \
    bash -c '
        set -euo pipefail
        echo "== the toolchain"
        swift --version
        echo "== debug"
        swift build --scratch-path /build
        echo "== release"
        swift build -c release --scratch-path /build
        echo "== it compiles on Linux"
    ' &

runner=$!

# Waited on rather than wrapped in `timeout`, because what has to be stopped is
# the container rather than the client talking to it. Killing the client is what
# left containers running for hours.
( sleep $(( minutes * 60 )); kill -TERM "$runner" 2> /dev/null ) &
watchdog=$!

if wait "$runner"; then
    kill "$watchdog" 2> /dev/null || true
    echo
    echo "The tests are not run here. They run on Linux in CI, and #25 says why."
    exit 0
fi

kill "$watchdog" 2> /dev/null || true
echo "The Linux check did not finish within ${minutes} minutes, so its container was removed." >&2
echo "Set CHECK_LINUX_MINUTES to allow longer, or run it by hand to watch where it stops." >&2
exit 1
