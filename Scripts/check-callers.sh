#!/usr/bin/env bash
#
#  check-callers.sh
#  Builds the application that consumes this package.
#
#  PlayableAirplay.h is a published interface, and podlive-macos is its one known
#  Objective-C caller. A local path tests this checkout directly. A remote SPM
#  reference tests the released version instead; it cannot validate unreleased
#  changes here, and the output says so rather than claiming that it does.
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

# Which package that project actually compiles. A local path is resolved from
# the directory holding the project, so two checkouts cannot be confused.
reference="$(sed -n 's/^[[:space:]]*relativePath = \(.*PlayableAirplay\);$/\1/p' \
    "$project/project.pbxproj" | head -1)"

if [[ -z "$reference" ]]; then
    if ! grep -q 'repositoryURL = "https://github.com/phranck/PlayableAirplay.git";' \
        "$project/project.pbxproj"; then
        echo "$project names neither this checkout nor the PlayableAirplay GitHub package." >&2
        exit 1
    fi
    echo "== $caller, which compiles the released PlayableAirplay package from GitHub"
    echo "This checks the released caller, not unreleased code in $root."
    "$caller/Scripts/run-tests.sh"
    exit 0
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
