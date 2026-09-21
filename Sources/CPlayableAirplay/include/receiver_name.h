//
//  receiver_name.h
//  Reading a receiver's identifier and its name out of a service instance.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#ifndef PLAYABLE_AIRPLAY_RECEIVER_NAME_H
#define PLAYABLE_AIRPLAY_RECEIVER_NAME_H

#include <stddef.h>

/**
 Splits a RAOP service instance into an identifier and a name.

 A receiver is announced as `48A6B8F7CA56@Dining Room`: the part before the
 separator is its hardware address and the part after is what a person calls
 it. Both are wanted. The address survives a rename, so it is what identifies a
 receiver across sightings; the name is what goes on screen.

 An instance without a separator is used for both, which is what an older
 receiver announces.

 Kept apart from the discovery itself because it is the only part of it that
 can be tested without a network.

 @param instance        The service instance name, without its type and domain.
 @param identifier      Where the address is written, always terminated.
 @param identifierSize  How large that buffer is, including the terminator.
 @param name            Where the name is written, always terminated.
 @param nameSize        How large that buffer is, including the terminator.
 */
void pa_split_instance_name(const char *instance, char *identifier, size_t identifierSize,
                            char *name, size_t nameSize);

#endif /* PLAYABLE_AIRPLAY_RECEIVER_NAME_H */
