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

/**
 Turns a `deviceid` field into the identifier the RAOP instance name carries.

 The two services name the same receiver differently. A RAOP instance begins
 `48A6B8F7CA56@`, whilst the AirPlay service publishes `deviceid=48:A6:B8:F7:CA:56`
 in its record and puts only the display name in its instance. Stripping the
 separators and raising the case turns the second into the first, which is what
 lets one receiver seen on both services be recognised as one receiver.

 Everything that is not a hexadecimal digit is dropped, so a receiver that
 separates its address some other way still lands on the same value.

 @param deviceID       The field as published, or NULL.
 @param identifier     Where the result is written, always terminated.
 @param identifierSize How large that buffer is, including the terminator.
 */
void pa_identity_from_device_id(const char *deviceID, char *identifier, size_t identifierSize);

/**
 Undoes the escaping a service's full name arrives in.

 A resolve answers with the name in its wire form, where a dot inside a label is
 written `\.`, a backslash `\\`, and anything outside printable ASCII as a
 backslash and three decimal digits. A receiver called "Dining Room" therefore
 arrives as `Dining\032Room`, and putting that on screen is putting the escaping
 on screen.

 @param escaped   The name as it arrived, or NULL.
 @param plain     Where the readable form is written, always terminated.
 @param plainSize How large that buffer is, including the terminator.
 */
void pa_unescape_instance_name(const char *escaped, char *plain, size_t plainSize);

#endif /* PLAYABLE_AIRPLAY_RECEIVER_NAME_H */
