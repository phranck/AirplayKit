# The Swift image CI uses, with the one package this package needs on Linux
# already in it.
#
# Built once and reused, because `apt-get update` in every run costs most of a
# minute and answers the same thing every time.
#
# The version comes from .swift-version, which Scripts/check-linux.sh reads and
# passes in, so the file at the root of the repository is the only place the
# pinned toolchain is named on this side.
#
# Copyright © 2026 LAYERED. All rights reserved.

ARG SWIFT_VERSION
FROM swift:${SWIFT_VERSION}

# dns_sd.h ships with macOS. On Linux it comes from Avahi's compatibility
# package, which is the same header and the same calls.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends libavahi-compat-libdnssd-dev \
 && rm -rf /var/lib/apt/lists/*
