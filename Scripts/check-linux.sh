#!/usr/bin/env bash
#
#  check-linux.sh
#  Runs the gate on Linux, here, before anything is pushed.
#
#  The same Swift image CI uses, with the same script inside it, so a red run on
#  GitHub is one this machine could already have told you about. It needs Docker
#  to be running and nothing else.
#
#  The build goes into .build-linux, so it does not overwrite the macOS one and
#  the two can stand side by side.
#
#  Copyright © 2026 cocoa:naut. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Kept in step with the container in .github/workflows/ci.yml by hand, and there
# is one line of it in each place.
image="swift:6.2"

if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running, so there is nothing to check Linux in." >&2
    exit 1
fi

docker run --rm \
    --volume "$root:/src" \
    --workdir /src \
    --env SWIFT_BUILD_DIR=/src/.build-linux \
    "$image" \
    bash -c '
        set -euo pipefail
        apt-get update -qq
        apt-get install -y -qq libavahi-compat-libdnssd-dev > /dev/null
        Scripts/build-and-test.sh .build-linux
    '
