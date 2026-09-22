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

holder="$(lsof -nP -iTCP:7000 -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1; exit}' || true)"
if [ -n "$holder" ]; then
    echo "Port 7000 is held by $holder, so a sender would reach that instead of this."
    echo
    echo "Switch the system's own receiver off first:"
    echo "  System Settings, General, AirDrop and Handoff, AirPlay Receiver."
    echo
    echo "Switch it back on when you are done, or this Mac stops being a speaker."
    exit 1
fi

interface="$(route -n get default | awk '/interface:/{print $2}')"

mkdir -p "$(dirname "$log")"

echo "Listening as \"$name\" on $interface. Ctrl-C to stop."
echo "Writing to $(basename "$log")"
echo
echo "On the iPhone:"
echo "  1. Start playing something with sound."
echo "  2. Open its AirPlay list. \"$name\" is in it."
echo "  3. Tick \"$name\" TOGETHER WITH a HomePod, so the two play as a group."
echo "  4. Move the volume of one of them on its own, then of both together."
echo "  5. Untick one, then the other."
echo
echo "Everything the sender says arrives here in the clear, so step 5 matters as"
echo "much as the rest: it is the only sight of how a member leaves a group."
echo

cd "$receiver"
./.venv/bin/python ap2-receiver.py -m "$name" --netiface="$interface" 2>&1 | tee "$log"
