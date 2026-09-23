#!/usr/bin/env bash
#
#  check-linux.sh
#  Runs the gate on Linux, here, before anything is pushed.
#
#  The same Swift image CI uses, with the same script inside it, so a red run on
#  GitHub is one this machine could already have told you about. It needs Docker
#  to be running and nothing else.
#
#  The build goes into a Docker volume of its own rather than into the checkout.
#  It has to stay off the macOS one, which would otherwise be overwritten, and it
#  has to stay off the shared folder as well: SwiftPM writes its build database
#  there and the bind mount does not give it what it needs, so every run stops at
#  "unknown build description" before compiling a line. The volume keeps the
#  build between runs, which is what makes a second run quick.
#
#  Copyright © 2026 LAYERED. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Kept in step with the container in .github/workflows/ci.yml by hand, and there
# is one line of it in each place.
image="swift:6.2"

# Where the Linux build lives between runs. Named, so it survives, and so a
# person can find it with `docker volume ls` and remove it when it is in the way.
volume="playable-airplay-linux-build"

# How long the whole run may take. A cold volume compiles Mbed TLS, the C++
# sender and two Swift packages from nothing, which is slow but not unbounded.
# Beyond this something is wrong, and saying so beats waiting for ever.
minutes="${CHECK_LINUX_MINUTES:-30}"

# A name of its own per run, so the container can be found and removed even
# where this script is killed before it can tidy up after itself.
container="playable-airplay-linux-$$"

if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, so there is nothing to check Linux in." >&2
    exit 1
fi

# On every path out, including an interrupt and including the timeout below.
# A container left running holds a Swift toolchain image and says nothing.
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
        apt-get update -qq
        apt-get install -y -qq libavahi-compat-libdnssd-dev > /dev/null
        Scripts/build-and-test.sh /build
    ' &

runner=$!

# Waited on rather than wrapped in `timeout`, because the process that has to
# be stopped is the container rather than the client talking to it, and killing
# the client leaves the container running. That is the defect this replaces.
( sleep $(( minutes * 60 )); kill -TERM "$runner" 2> /dev/null ) &
watchdog=$!

if wait "$runner"; then
    kill "$watchdog" 2> /dev/null || true
    exit 0
fi

kill "$watchdog" 2> /dev/null || true
echo "The Linux check did not finish within ${minutes} minutes, so its container was removed." >&2
echo "Set CHECK_LINUX_MINUTES to allow longer, or run it by hand to watch where it stops." >&2
exit 1
