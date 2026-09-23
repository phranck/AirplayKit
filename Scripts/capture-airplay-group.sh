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
#  Two ways round, and the second is the one that sees everything.
#
#  `sending` records this Mac playing to two speakers. What it misses is this
#  Mac's own timing traffic, because AirPlay between Apple devices runs over the
#  peer-to-peer link rather than over the network everything else uses.
#
#  `receiving` records an iPhone playing to this Mac, with this Mac switched on
#  as an AirPlay receiver. Everything a sender says to a member of a group then
#  arrives here, on this machine's own interfaces, so none of it can be
#  elsewhere. It is also Apple's own sender, which is the one worth copying. What
#  it does not show is what that iPhone says to the other member.
#
#  Needs root, because reading from the network needs /dev/bpf. Nothing else.
#
#  Copyright © 2026 LAYERED. All rights reserved.
#

set -euo pipefail

seconds="${1:-180}"
mode="${2:-sending}"

case "$mode" in
    sending|receiving) ;;
    *) echo "The second argument is 'sending' or 'receiving', not '$mode'." >&2; exit 2 ;;
esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"
capture="$root/build/captures/airplay-group-$stamp.pcap"
notes="${capture%.pcap}.txt"

if [ "$(id -u)" -ne 0 ]; then
    echo "This reads from the network, so it needs root:" >&2
    echo "    sudo $0 ${seconds}" >&2
    exit 1
fi

# Named one by one through pktap rather than asked for as a group. Two earlier
# recordings held the receivers' timing traffic and none of this Mac's own,
# whilst its RTSP was there in both directions, and both files turned out to
# carry en0 alone. AirPlay to an Apple device uses the peer-to-peer interfaces,
# so they are named here and the summary says which ones actually landed.
routed="$(route -n get default | awk '/interface:/{print $2}')"
address="$(ipconfig getifaddr "$routed")"

wanted=("$routed")
for candidate in awdl0 llw0 en1 ap1; do
    if ifconfig "$candidate" > /dev/null 2>&1; then
        wanted+=("$candidate")
    fi
done
interface="pktap,$(IFS=,; echo "${wanted[*]}")"

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
    echo "interfaces  $interface (routed traffic goes over $routed)"
    echo "this Mac    $address"
    echo "started     $(date -Iseconds)"
    echo "filter      $filter"
    echo
    echo "Receivers on the network at the time:"
    timeout 6 dns-sd -Z _raop._tcp local 2>/dev/null | grep -E "SRV|TXT" || true
} > "$notes"

echo "Recording for ${seconds}s into $(basename "$capture")."
echo

if [ "$mode" = "sending" ]; then
    echo "Whilst it runs, do this on this Mac:"
    echo "  1. Start playing something with sound."
    echo "  2. Open Control Centre, then Sound, then the AirPlay list."
    echo "  3. Tick TWO Apple speakers, so they play together. A HomePod and an"
    echo "     Apple TV is the pair to use, because a group of Apple receivers is"
    echo "     what keeps time with PTP."
    echo "  4. Move the volume of ONE of them on its own, then of both together."
    echo "  5. Untick one of them, then untick the other."
else
    echo "Whilst it runs, play from an iPhone TO this Mac:"
    echo "  1. On this Mac, make sure AirPlay Receiver is on, under System"
    echo "     Settings, General, AirDrop and Handoff."
    echo "  2. On the iPhone, start playing something with sound."
    echo "  3. Open its AirPlay list and tick THIS MAC together with a HomePod,"
    echo "     so the two play as a group."
    echo "  4. Move the volume of this Mac on its own, then of both together."
    echo "  5. Untick this Mac, then untick the other one."
    echo
    echo "  If the iPhone will not group a Mac with a HomePod, tick this Mac on"
    echo "  its own. That still records a whole session from Apple's own sender,"
    echo "  which is most of what is wanted."
fi
echo

tcpdump -i "$interface" -s 0 -w "$capture" -G "$seconds" -W 1 "$filter" 2>/dev/null || true

# Everything here ran as root, so the folder and its contents belong to root.
# Hand the whole folder back, not only the two files: a folder owned by root is
# one nothing else can write into, and the next tool to try simply fails with a
# permission error in the middle of a run.
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER" "$(dirname "$capture")"
fi

echo
echo "Wrote $capture"
echo "      $notes"
echo
echo "Interfaces that ended up in the file:"
python3 - "$capture" <<'PY'
import struct, sys

data = open(sys.argv[1], "rb").read()
offset, endian, names = 0, "<", []

while offset + 8 <= len(data):
    kind, length = struct.unpack(endian + "II", data[offset:offset + 8])
    if kind == 0x0A0D0D0A:
        endian = "<" if data[offset + 8:offset + 12] == b"\x4d\x3c\x2b\x1a" else ">"
        kind, length = struct.unpack(endian + "II", data[offset:offset + 8])
    if length < 12 or offset + length > len(data):
        break
    if kind == 1:
        body, position, name = data[offset + 16:offset + length - 4], 0, None
        while position + 4 <= len(body):
            code, size = struct.unpack(endian + "HH", body[position:position + 4])
            if code == 0:
                break
            if code == 2:
                name = body[position + 4:position + 4 + size].decode("utf-8", "replace")
            position += 4 + ((size + 3) // 4) * 4
        names.append(name or "?")
    offset += length

print("  " + (", ".join(names) if names else "none"))
PY
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
echo "PTP at zero means the group never formed. This Mac's own PTP should be in"
echo "there as well as the speakers', and a recording holding only theirs means"
echo "the peer-to-peer interfaces were missed again."
