#!/usr/bin/env bash
#
#  probe-airplay-sender.sh
#  Listens as an AirPlay 2 receiver and writes down what a sender says to it.
#
#  A packet recording cannot answer the questions left in
#  Documentation/Research/airplay2-sender-protocol.md, because everything after
#  pair-verify rides an encrypted channel. Measured on 2026-09-22: an iPhone
#  streaming to this Mac showed `GET /info`, `POST /pair-verify` and nothing
#  else in the clear. SETPEERS, the anchor and the volume commands are all
#  behind that.
#
#  A receiver holds the keys, so it reads them. This runs openairplay's
#  airplay2-receiver, which pairs, decrypts and prints the whole RTSP exchange,
#  and keeps the print in a file.
#
#  Needs no root. It does need the port, which macOS holds whilst its own
#  AirPlay Receiver is switched on.
#
#  Copyright © 2026 cocoa:naut. All rights reserved.
#

set -euo pipefail

name="${1:-PlayableProbe}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
receiver="$root/build/airplay2-receiver"
stamp="$(date +%Y%m%d-%H%M%S)"
log="$root/build/captures/airplay-sender-$stamp.log"

if [ ! -x "$receiver/.venv/bin/python" ]; then
    echo "The receiver is not set up at $receiver." >&2
    echo "Clone openairplay/airplay2-receiver there and make a .venv in it." >&2
    exit 1
fi

# Said rather than refused. ControlCenter listens on port 7000 whether or not the
# system's own AirPlay Receiver is switched on, and this receiver binds its own
# address alongside it and works. What the system receiver does cost is clarity,
# because then two receivers answer and only the name in the sender's list says
# which is which.
holder="$(lsof -nP -iTCP:7000 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1; exit}' || true)"
if [ -n "$holder" ]; then
    echo "Note: $holder is also listening on port 7000."
    echo "If this Mac appears twice in the sender's list, the other one is the"
    echo "system's own receiver, under System Settings, General, AirDrop and"
    echo "Handoff. Pick the one named below."
    echo
fi

interface="$(route -n get default | awk '/interface:/{print $2}')"

mkdir -p "$(dirname "$log")"

echo "Listening as \"$name\" on $interface. Ctrl-C to stop."
echo "Writing to $(basename "$log")"
echo
echo "On the iPhone, and leave about ten seconds between each step so the log"
echo "shows where one ends and the next begins:"
echo "   1. Start playing something with sound."
echo "   2. Open its AirPlay list. \"$name\" is in it."
echo "   3. Tick \"$name\" ON ITS OWN, and let it play."
echo "   4. Now tick a HomePod as well, so the two play as a group."
echo "   5. Move the volume of \"$name\" on its own."
echo "   6. Move the volume of the HomePod on its own."
echo "   7. Move the iPhone's own volume, which is the whole group at once."
echo "   8. Untick the HomePod, leaving \"$name\" playing."
echo "   9. Untick \"$name\"."
echo "  10. Stop this with Ctrl-C."
echo
echo "Steps 3 and 4 are two different things and both are wanted: one session"
echo "starting alone, and a second speaker joining one that is already playing."
echo "Steps 8 and 9 are the only sight of how a member leaves a group."
echo

# The log is written first and reported afterwards, so a run that produced
# nothing says so here rather than being discovered as a missing file later.
# Unbuffered on both sides, or the times say when a buffer flushed rather than
# when something happened. The gap in front of each line is what separates one
# step from the next, because the operator pauses between them.
cd "$receiver"
./.venv/bin/python -u ap2-receiver.py -m "$name" --netiface="$interface" 2>&1 \
    | "$root/Scripts/stamp.py" \
    | tee "$log"

echo
if [ -s "$log" ]; then
    echo "Wrote $(wc -l < "$log" | tr -d ' ') lines to $log"
else
    echo "Nothing was written to $log. The receiver never got going."
fi
