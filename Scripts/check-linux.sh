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
#  Copyright © 2026 cocoa:naut. All rights reserved.
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

if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, so there is nothing to check Linux in." >&2
    exit 1
fi

docker run --rm \
    --volume "$root:/src" \
    --volume "$volume:/build" \
    --workdir /src \
    "$image" \
    bash -c '
        set -euo pipefail
        apt-get update -qq
        apt-get install -y -qq libavahi-compat-libdnssd-dev > /dev/null
        Scripts/build-and-test.sh /build
    '
