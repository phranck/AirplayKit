# Audio

The two paths audio takes, what a packet looks like on each, and how a lost one is recovered.

## Overview

AirPlay 2 has two audio paths and a sender picks one per stream.

Realtime audio, payload type 96, goes over UDP and arrives at the rate it is played. It is used where delay matters more than robustness, such as system sounds and telephony.

Buffered audio, payload type 103, goes over TCP. Audio arrives faster than it is played and sits in the receiver's buffer until its moment comes, which is what makes the playback delay short and the stream resistant to a lossy network (reported confirmed, [shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md)).

Buffered is the path Apple uses for music. An iPhone playing to a receiver used type 103 and nothing else, and type 96 appeared in no measured session at all (measured 2026-09-22, decrypted, F-038). That matters for a sender, because the path Apple's own phone takes to a speaker is the buffered one.

No open sender implements buffered audio. pyatv and the C++ sender say so in their own documentation, and owntone hardcodes the realtime payload type in a constant whose own comment names 103 as the alternative it does not take (reported confirmed, [pyatv](https://github.com/postlund/pyatv), [airplay2-sender-cpp](https://github.com/akustikrausch/airplay2-sender-cpp) and [owntone, `src/outputs/airplay.c`](https://github.com/owntone/owntone-server/blob/master/src/outputs/airplay.c)). A sender that wants multi-room builds this path from the receiver side of the sources rather than from an existing sender.

A receiver has to advertise `features` bit 40 for buffered audio, and the specification's own note on that bit and on bit 41 is that each is needed for a device to show as supporting multi-room audio (reported confirmed, [openairplay, `src/features.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/features.md)).

## Realtime audio, payload type 96

### The packet

Realtime audio goes over UDP to the `dataPort` the stream SETUP returned. Each packet is a standard 12-byte RTP header followed by the payload, and all fields are big-endian ([RFC 3550](https://www.rfc-editor.org/rfc/rfc3550.txt)).

```text
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|1 0 0 0 0 0 0 0|M|   PT = 96   |      sequence number          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        RTP timestamp                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    SSRC = the session id                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          payload ...                          |
```

The first byte is always 0x80, meaning RTP version 2 with no padding, no extension and no contributing sources. The second byte is 0xE0 on the first packet of a stream and 0x60 afterwards, which is payload type 96 with the marker bit set on the first packet only. The marker bit is set again on the first packet after a FLUSH (reported confirmed, [openairplay, RTP Streams](https://openairplay.github.io/airplay-spec/audio/rtp_streams.html), and reported likely for the choice of the session identifier as the synchronisation source, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

The sequence number is a 16-bit counter that starts at a random value and wraps. The RTP timestamp counts frames at 44100 Hz, and <doc:Protocol-Timing> covers its starting value and its relationship to the clock.

Each packet carries exactly 352 frames. That number is fixed in RAOP and is what the receiver expects (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp); it also appears as the first ALAC parameter in every published AirPlay SDP, which corroborates it).

### The payload is ALAC, whatever the sender asks for

On the realtime stream the receiver fixes the codec at ALAC, which is Apple Lossless, and ignores both `ct` and `audioFormat`. A sender must ALAC-encode.

This is visible in a receiver's own SETUP handling. shairport-sync reads `audioFormat` only in the branch for stream type 103, and never in the branch for stream type 96, where the format is fixed at ALAC, 16 bit, 44100 Hz, stereo (reported confirmed, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [`AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md)). A working sender reports the same behaviour from the other side against an Apple TV (reported confirmed as observed behaviour, [airplay2-sender-cpp, README](https://github.com/akustikrausch/airplay2-sender-cpp)).

The cheapest correct way to satisfy that is the uncompressed ALAC escape. ALAC's bitstream has an escape flag meaning that the samples which follow are raw, so a sender produces a valid ALAC frame without implementing any of the prediction machinery. The bitstream is read most-significant-bit first.

The field order comes from Apple's own decoder (reported confirmed, [Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp)).

```text
 3 bits   element tag          1 = ID_CPE, a channel pair element
 4 bits   elementInstanceTag   0
12 bits   unusedHeader         0, and the decoder errors if it is not
 1 bit    partialFrame         0, so the frame length comes from the configuration
 2 bits   bytesShifted         0
 1 bit    escape flag          1, meaning the samples are uncompressed
          then, for each of the 352 frames:
16 bits       left sample, most-significant bit first
16 bits       right sample, most-significant bit first
 3 bits   element tag          7 = ID_END
          zero-pad to the next byte boundary
```

The element tag numbers come from the same project (reported confirmed, [Apple, `macosforge/alac`, `ALACBitUtilities.h`](https://github.com/macosforge/alac/blob/master/codec/ALACBitUtilities.h)).

| Value | Name |
|---|---|
| 0 | ID_SCE |
| 1 | ID_CPE |
| 2 | ID_CCE |
| 3 | ID_LFE |
| 4 | ID_DSE |
| 5 | ID_PCE |
| 6 | ID_FIL |
| 7 | ID_END |

Two details are worth stating because they are easy to get wrong. The two channels are interleaved one sample at a time rather than written as two blocks. And `mixBits` and `mixRes` are not present at all in the uncompressed case, because Apple's decoder sets them to zero rather than reading them (reported confirmed, [Apple, `macosforge/alac`, `ALACDecoder.cpp`](https://github.com/macosforge/alac/blob/master/codec/ALACDecoder.cpp)).

### The ALAC configuration, and the `fmtp` parameter list

The eleven numbers in an AirPlay `a=fmtp:96` line are the fields of Apple's `ALACSpecificConfig`, in declaration order (reported confirmed for the struct, [Apple, `macosforge/alac`, `ALACAudioTypes.h`](https://github.com/macosforge/alac/blob/master/codec/ALACAudioTypes.h), and reported confirmed for the example line, [openairplay, ANNOUNCE](https://openairplay.github.io/airplay-spec/audio/rtsp_requests/announce.html)).

```text
a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
```

| Position | Field | Value here |
|---|---|---|
| 1 | `frameLength` | 352 |
| 2 | `compatibleVersion` | 0 |
| 3 | `bitDepth` | 16 |
| 4 | `pb` | 40 |
| 5 | `mb` | 10 |
| 6 | `kb` | 14 |
| 7 | `numChannels` | 2 |
| 8 | `maxRun` | 255 |
| 9 | `maxFrameBytes` | 0 |
| 10 | `avgBitRate` | 0 |
| 11 | `sampleRate` | 44100 |

AirPlay 2 sends no SDP, so this line matters only on the AirPlay 1 path and as the definition of what `audioFormat` and `spf` describe.

### The `audioFormat` bitfield

`audioFormat` is a bitfield with one bit per concrete format rather than a small enumeration. Three tables give the same mapping, so it is settled (reported confirmed, [openairplay, `airplay2-receiver`, `ap2-receiver.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py) and [`ap2/connections/audio.py`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2/connections/audio.py), and [Cozzi, Audio](https://web.archive.org/web/20220214214824/https://emanuelecozzi.net/docs/airplay2/audio/)).

| Bits | Formats |
|---|---|
| 2 to 17 | PCM at various rates and channel counts |
| 18 to 21 | The four ALAC variants |
| 22 and 23 | AAC-LC at 44100 Hz and at 48000 Hz |
| 24 to 27, 31 and 32 | AAC-ELD variants |
| 28 to 30 | Opus |

Bit 18 is ALAC at 44100 Hz, 16 bit, stereo, which is the value `0x40000` a working sender sends.

### Encrypting the payload

The ALAC frame is encrypted with ChaCha20-Poly1305 under the `shk` key that <doc:Protocol-Session> describes. The additional authenticated data is bytes 4 to 11 of the RTP header, which is the RTP timestamp and the synchronisation source, eight bytes in total. The nonce is a 64-bit counter that starts at zero and increases by one per packet, padded to twelve bytes with four leading zero bytes.

The counter is appended to the packet after the ciphertext and the tag, as eight little-endian bytes, so the receiver can decrypt a packet that arrived out of order (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp), attributed there to pyatv).

```text
+---------------------+------------------+------------------+------------------+
| 12-byte RTP header  |    ciphertext    |  Poly1305 tag    | nonce counter    |
|                     |                  |    (16 bytes)    |   (8 bytes, LE)  |
+---------------------+------------------+------------------+------------------+
        AAD = header bytes 4 to 11
```

One published diagram of that trailer puts the nonce first and the tag after it. A receiver's own decryption reads it the other way round, taking the last eight bytes as the nonce and the sixteen before them as the tag, which is what the combined-mode AEAD call expects, so the order above is the one that works (reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c), against [Cozzi, RTP](https://web.archive.org/web/20220214214827/https://emanuelecozzi.net/docs/airplay2/rtp/)). The same receiver code path serves both the realtime and the buffered stream, which is why the two constructions are identical.

### Pacing

Frames leave the machine at the rate wall-clock time advances, which is 44100 frames per second. A working sender runs an 8 millisecond deadline, which is about one packet per tick, and uses a token bucket so that a late tick is repaid rather than lost. The number of packets sent in one catch-up burst is capped, so a stalled thread cannot flood the network (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

When the source has no audio, the sender pushes silence rather than stopping. A receiver whose timeline stops advancing treats the stream as dead (reported likely, same source).

### Retransmission

The receiver asks for a lost packet with payload type 85 on the sender's control port, naming the first missing sequence number and how many are missing. The request is eight bytes, and a receiver's own sending code settles the layout (reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c)).

```text
offset  size  field
  0      1    0x80
  1      1    0xD5, which is payload type 85 with the marker bit set,
              and the same byte on both AirPlay versions
  2      2    a sequence number of the receiver's own, which
              shairport-sync always sets to 1, big-endian
  4      2    the first missing sequence number, big-endian
  6      2    how many are missing, big-endian
```

pyatv reads the same eight bytes at the same offsets (reported confirmed, [pyatv, `pyatv/protocols/raop/packets.py`](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/raop/packets.py)). openairplay's twelve-byte description puts the two fields after an eight-byte header rather than inside it, and neither the receiver that sends these requests nor the sender that parses them uses that layout ([openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md)). Read the pair at offset 4.

The sender answers with payload type 86: a four-byte header followed by the complete original audio packet, which brings its own RTP header with it, so the embedded sequence number sits at offset 6 of the reply. Both of a receiver's code paths read it at exactly that offset (reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c)). The last two bytes of that four-byte header are a 16-bit counter of the sender's own (reported likely, [openairplay, `src/audio/rtp_streams.md`](https://raw.githubusercontent.com/openairplay/airplay-spec/master/src/audio/rtp_streams.md)).

A sender therefore keeps a backlog of packets it has already sent. A ring of 1024 entries indexed by the low ten bits of the sequence number is enough, and a request for something older than that is simply not answered (reported likely, [airplay2-sender-cpp, `raop_sender.cpp`](https://github.com/akustikrausch/airplay2-sender-cpp)).

Buffered audio needs none of this, because TCP recovers loss itself. No source states that outright, so it is likely rather than confirmed.

## Buffered audio, payload type 103

### What the SETUP reply gives back

The stream dictionary carries `type: 103`, and a receiver reads `shk`, `ct`, `spf` and, unlike the realtime case, `audioFormat` (reported confirmed, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c)).

The reply differs from the realtime reply in two ways. `dataPort` names a TCP port rather than a UDP one, and the reply additionally carries `audioBufferSize`, an integer naming how much audio the receiver is prepared to hold. `controlPort` is a UDP port opened once for the connection and shared with the realtime stream (reported confirmed, same source).

`audioBufferSize` is a capacity the receiver reports, not something the sender chooses. The receiver allocates a buffer of that size, and beyond it the TCP connection simply stops draining, so flow control falls out of the transport rather than out of a protocol message (reported confirmed, [shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c)).

### The TCP framing

The buffered connection is a stream of length-prefixed blocks.

```text
+---------+-------------------------------------------------------+
| length  |                     block                             |
| 2 bytes |                                                       |
| BE u16  |                                                       |
+---------+-------------------------------------------------------+
  the length counts itself, so the block is (length - 2) bytes
```

Each block then looks like this (reported confirmed, [shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c)).

```text
offset  size  field
  0      4    big-endian u32: the top bit is the marker bit, always set,
              and the low 23 bits are the sequence number
  4      4    big-endian u32: timestamp
  8      4    big-endian u32: SSRC, which names the codec of THIS block
 12      n    ChaCha20-Poly1305 ciphertext
12+n    16    Poly1305 tag
28+n     8    the nonce counter, little-endian
```

The sequence number is 23 bits wide here rather than the 16 bits RTP normally gives it. The synchronisation source is not a stream identifier in the RTP sense: the receiver reads it to decide what codec the block holds, so the codec can change from one block to the next within a single connection.

The encryption is the same construction as the realtime path. The key is `shk` used directly. The additional authenticated data is the eight bytes at offset 4, which are the timestamp and the synchronisation source. The nonce is the trailing eight bytes, padded at the front with four zero bytes to make twelve (reported confirmed, same source, and the realtime path feeds in the same two fields, reported confirmed, [shairport-sync, `rtp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtp.c)).

### The codec

Buffered audio is ALAC when lossless and AAC when lossy (reported confirmed, [shairport-sync, `AIRPLAY2.md`](https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md)). The AAC is AAC-LC, and it arrives as raw AAC frames with no ADTS framing at all, so a receiver builds an ADTS header itself before handing the frame to a decoder (reported confirmed, [shairport-sync, `ap2_buffered_audio_processor.c`](https://github.com/mikebrady/shairport-sync/blob/master/ap2_buffered_audio_processor.c)). AAC-ELD is the realtime and mirroring codec, not the buffered one.

### FLUSHBUFFERED

`FLUSHBUFFERED` carries four fields (reported confirmed by both, [shairport-sync, `rtsp.c`](https://github.com/mikebrady/shairport-sync/blob/master/rtsp.c) and [openairplay, `airplay2-receiver`](https://github.com/openairplay/airplay2-receiver/blob/master/ap2-receiver.py)).

| Field | Meaning |
|---|---|
| `flushFromSeq` | The sequence number the flush starts at. Absent for an immediate flush. |
| `flushFromTS` | The timestamp the flush starts at. |
| `flushUntilSeq` | The sequence number the flush runs to. |
| `flushUntilTS` | The timestamp the flush runs to. |

With no `flushFromSeq` it is an immediate flush up to the `until` point, which is what a stop does. With `flushFromSeq` present it is a range flush, which drops only the blocks between the two points and leaves audio queued beyond them alone. That is what makes a track change seamless: the tail of the old track goes and the head of the new one stays.

<doc:Protocol-Control> covers where `FLUSHBUFFERED` sits in a running session.
