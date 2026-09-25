//
//  receiver_state.c
//  Reading what a receiver is doing out of the status field it advertises.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

#include "include/receiver_state.h"

#include "AirplayKit.h"

#include <stdlib.h>
#include <string.h>

void pa_read_receiver_state(const void *flags, size_t length,
                            bool *hasSender, bool *isPlaying) {
    if (hasSender) *hasSender = false;
    if (isPlaying) *isPlaying = false;

    if (!flags || length == 0) return;

    // The value arrives out of a TXT record, where it is counted rather than
    // terminated, so it is copied before anything reads it as a string. Long
    // enough for the widest value seen and for a 64 bit one that never appears.
    char text[24];
    const size_t room = sizeof(text) - 1;
    const size_t taken = length < room ? length : room;
    memcpy(text, flags, taken);
    text[taken] = '\0';

    // Base sixteen rather than letting it work the base out, because the field
    // is hexadecimal whether or not it carries the prefix. Working it out reads
    // a bare `1a0c04` as decimal and stops at the first letter, which answers 1
    // and quietly loses every bit that matters. Base sixteen takes the prefix
    // too, so both spellings read the same. Anything unreadable answers zero,
    // which leaves both flags false.
    const unsigned long value = strtoul(text, NULL, 16);

    if (hasSender) *hasSender = (value & PA_STATE_SENDER_CONNECTED) == PA_STATE_SENDER_CONNECTED;
    if (isPlaying) *isPlaying = (value & PA_STATE_PLAYING) != 0;
}
