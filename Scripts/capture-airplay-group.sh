#!/usr/bin/env bash
#
#  capture-airplay-group.sh
#  Records what a Mac sends when it plays to two AirPlay speakers at once.
#
#  Documentation/Research/airplay2-sender-protocol.md ends with nine questions
#  that reading cannot answer, and one recording answers four of them: which PTP
#  domain and profile a group uses, whether the receivers contest the master
#  election, whether the sender opens one session per speaker or addresses a
#  leader, and how the volume of one speaker in a group is set.
#
#  Needs root, because reading from the network needs /dev/bpf. Nothing else.
#
#  Copyright © 2026 cocoa:naut. All rights reserved.
#

set -euo pipefail

seconds="${1:-180}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"
capture="$root/build/captures/airplay-group-$stamp.pcap"
notes="${capture%.pcap}.txt"

if [ "$(id -u)" -ne 0 ]; then
    echo "This reads from the network, so it needs root:" >&2
    echo "    sudo $0 ${seconds}" >&2
    exit 1
fi

interface="$(route -n get default | awk '/interface:/{print $2}')"
address="$(ipconfig getifaddr "$interface")"

mkdir -p "$(dirname "$capture")"

# What is kept, and why each part of it.
#
#   319, 320   PTP, which is what an AirPlay 2 group keeps time with.
#   7000       RTSP, which carries the pairing, both SETUPs, RECORD, SETPEERS,
#              SETRATEANCHORTIME and every volume change.
#   5353       Bonjour, so the recording says what each address was called.
#   small udp  The control and timing packets, whose ports are negotiated and
#              therefore not known in advance. Audio packets are far larger, and
#              leaving them out keeps the file readable and gives away nothing:
#              they are encrypted.
filter='udp port 319 or udp port 320 or tcp port 7000 or udp port 5353 or (udp and less 300)'

{
    echo "interface   $interface"
    echo "this Mac    $address"
    echo "started     $(date -Iseconds)"
    echo "filter      $filter"
    echo
    echo "Receivers on the network at the time:"
    timeout 6 dns-sd -Z _raop._tcp local 2>/dev/null | grep -E "SRV|TXT" || true
} > "$notes"

echo "Recording for ${seconds}s into $(basename "$capture")."
echo
echo "Whilst it runs, do this on this Mac:"
echo "  1. Start playing something with sound."
echo "  2. Open Control Centre, then Sound, then the AirPlay list."
echo "  3. Tick TWO Apple speakers, so they play together. A HomePod and an"
echo "     Apple TV is the pair to use, because a group of Apple receivers is"
echo "     what keeps time with PTP."
echo "  4. Move the volume of ONE of them on its own, then of both together."
echo "  5. Untick one of them, then untick the other."
echo

tcpdump -i "$interface" -s 0 -w "$capture" -G "$seconds" -W 1 "$filter" 2>/dev/null || true

# tcpdump ran as root, so what it wrote belongs to root. Hand it back to whoever
# asked for it, or the next step cannot read it.
if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER" "$capture" "$notes"
fi

echo
echo "Wrote $capture"
echo "      $notes"
echo
echo "What came out:"
tcpdump -r "$capture" -nn 2>/dev/null | awk '
    /\.319 >|\.320 >|> .*\.319|> .*\.320/ { ptp++; next }
    /\.7000 >|> .*\.7000/                 { rtsp++; next }
    /\.5353 >|> .*\.5353/                 { mdns++; next }
                                          { other++ }
    END {
        printf "  PTP      %6d\n", ptp
        printf "  RTSP     %6d\n", rtsp
        printf "  Bonjour  %6d\n", mdns
        printf "  other    %6d\n", other
    }'
echo
echo "PTP at zero means the group never formed, or it formed over a different"
echo "interface than $interface."
