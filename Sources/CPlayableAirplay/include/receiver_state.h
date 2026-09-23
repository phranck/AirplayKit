//
//  receiver_state.h
//  Reading what a receiver is doing out of the status field it advertises.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

#ifndef PLAYABLE_AIRPLAY_RECEIVER_STATE_H
#define PLAYABLE_AIRPLAY_RECEIVER_STATE_H

#include <stdbool.h>
#include <stddef.h>

/**
 Reads a receiver's state out of the `sf` field of its service record.

 The field is a set of flags written as hexadecimal text, and three of its bits
 move with the state of a session. Measured on a HomePod mini at four moments,
 reading the same value from its Bonjour record and from its own `/info` each
 time:

     at rest                       0x80404
     a sender connected, playing   0x1a0c04
     stopped, still connected      0xa0c04
     the sender disconnected       0x80404

 Bits 11 and 17 move together and say a sender holds a session. Bit 20 says
 audio is flowing now. What the bits are called is not settled, because the
 published tables disagree and none of them was checked against a device. What
 they indicate was measured.

 Anything unreadable leaves both answers false, which is also what a receiver
 that does not publish the field gets. A false answer therefore means "this
 receiver is not saying it is busy" rather than "this receiver is free".

 Kept apart from the discovery itself because it is the only part of it that can
 be tested without a network.

 @param flags       The field's text, with or without a `0x` prefix. May be NULL.
 @param length      How many bytes of it to read, since the value arrives from a
                    TXT record and is not terminated.
 @param hasSender   Set to whether a sender holds a session. May be NULL.
 @param isPlaying   Set to whether audio is flowing now. May be NULL.
 */
void pa_read_receiver_state(const void *flags, size_t length,
                            bool *hasSender, bool *isPlaying);

#endif /* PLAYABLE_AIRPLAY_RECEIVER_STATE_H */
