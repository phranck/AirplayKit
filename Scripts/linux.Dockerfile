# The Swift image CI uses, with the one package this package needs on Linux
# already in it.
#
# Built once and reused, because `apt-get update` in every run costs most of a
# minute and answers the same thing every time.
#
# Copyright © 2026 LAYERED. All rights reserved.

FROM swift:6.2

# dns_sd.h ships with macOS. On Linux it comes from Avahi's compatibility
# package, which is the same header and the same calls.
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends libavahi-compat-libdnssd-dev \
 && rm -rf /var/lib/apt/lists/*
