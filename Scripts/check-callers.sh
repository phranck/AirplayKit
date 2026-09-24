#!/usr/bin/env bash
#
#  check-callers.sh
#  Builds the application that consumes this package by a local path.
#
#  PlayableAirplay.h is a published interface, and its one known caller does not
#  take a release of it. podlive-macos names this working tree by a relative path,
#  so whatever is checked out here is what that application compiles against, and
#  a changed declaration reaches it the moment it is saved. Nothing else in this
#  repository would say so: every gate here was green on the change that stopped
#  it compiling.
#
#  Not in CI, because the runner has no copy of that application and has no
#  business with one. This is the gate for a machine that has it, and on a
#  machine that has not it says so and passes, so it can stand in the pre-push
#  set anywhere.
#
#  Copyright © 2026 LAYERED. All rights reserved.
#

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$root"

# Beside this repository, which is where the project's own reference points.
# Overridable for a checkout kept somewhere else.
caller="${PLAYABLE_AIRPLAY_CALLER:-$root/../Podlive/podlive-macos}"

if [[ ! -d "$caller" ]]; then
    echo "There is no caller at $caller, so no application was built against this header."
    echo "Point PLAYABLE_AIRPLAY_CALLER at a podlive-macos checkout to have it checked."
    exit 0
fi

project="$caller/App/Podlive.xcodeproj"

if [[ ! -f "$project/project.pbxproj" ]]; then
    echo "$caller holds no Podlive project, so there was nothing to build." >&2
    exit 1
fi

# Which package that project actually compiles. It names one by a relative path,
# which is resolved from the directory holding the project, and a machine with
# two checkouts of this package would otherwise build the other one and report a
# green gate about code nobody changed.
reference="$(sed -n 's/^[[:space:]]*relativePath = \(.*PlayableAirplay\);$/\1/p' \
    "$project/project.pbxproj" | head -1)"

if [[ -z "$reference" ]]; then
    echo "$project names no local PlayableAirplay, so building it would prove nothing." >&2
    exit 1
fi

# Empty where that path leads nowhere. `|| true` is what keeps a failed cd from
# ending the script under `set -e` before it can say so.
referenced="$(cd "$project/.." && cd "$reference" 2> /dev/null && pwd -P || true)"

if [[ -z "$referenced" ]]; then
    echo "$project names $reference, and there is nothing at that path." >&2
    exit 1
fi

if [[ "$referenced" != "$root" ]]; then
    echo "$project builds against $referenced rather than $root." >&2
    echo "Building it would say nothing about the change in this checkout." >&2
    exit 1
fi

echo "== $caller, which compiles $referenced"

"$caller/Scripts/run-tests.sh"
