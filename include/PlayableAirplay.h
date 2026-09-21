//
//  PlayableAirplay.h
//  A C interface for finding AirPlay 2 receivers and sending audio to them.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#ifndef PLAYABLE_AIRPLAY_H
#define PLAYABLE_AIRPLAY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 Why this interface is C rather than C++ or Objective-C.

 Swift imports a C header directly, on macOS and on Linux alike, with no
 bridging layer and no C++ interoperability. Everything below is therefore
 plain C: no classes across the boundary, no exceptions, no ownership rules
 that a caller in another language has to learn.

 Nothing here touches AVFoundation, CoreAudio or AppKit. The audio arrives as
 interleaved signed 16-bit frames and leaves as an encrypted stream, and what
 produced those frames is the caller's business.
 */

/** How large a name or address may be, including its terminator. */
#define PA_MAX_NAME 128
#define PA_MAX_HOST 256
#define PA_MAX_ID    64

/** The audio the sender takes. Fixed, because this is what AirPlay carries. */
#define PA_SAMPLE_RATE 44100
#define PA_CHANNELS        2

/** What went wrong, where anything did. */
typedef enum PAResult {
    PAResultOK = 0,
    /** The receiver could not be reached at all. */
    PAResultUnreachable,
    /** The receiver answered and refused the pairing. */
    PAResultPairingRefused,
    /** The session was set up and the receiver ended it. */
    PAResultSessionEnded,
    /** The caller passed something this interface cannot use. */
    PAResultInvalidArgument,
    /** Something failed that the caller can do nothing about. */
    PAResultInternal,
} PAResult;

/** One receiver, as discovery found it. */
typedef struct PAReceiver {
    /** Stable across sightings, taken from the service instance name. */
    char id[PA_MAX_ID];
    /** What a person calls it, such as "Esszimmer". */
    char name[PA_MAX_NAME];
    /** Where to reach it, as a host name rather than an address, since addresses move. */
    char host[PA_MAX_HOST];
    /** The port its RTSP service listens on. */
    uint16_t port;
    /** Whether it announced the AirPlay 2 pairing key. A receiver without one needs the older path. */
    bool supportsAirPlay2;
} PAReceiver;

/** Finds receivers on the network and reports them as they come and go. */
typedef struct PADiscovery PADiscovery;

/**
 Called whenever the set of receivers changes.

 The array belongs to the discovery and is valid only for the duration of the
 call, so a caller that keeps it copies it.

 @param context    Whatever was handed to pa_discovery_start.
 @param receivers  Every receiver currently visible, ordered by name.
 @param count      How many there are.
 */
typedef void (*PADiscoveryHandler)(void *context, const PAReceiver *receivers, size_t count);

/**
 Starts looking for receivers.

 @param handler  Called on a thread of the discovery's own, whenever the set changes.
 @param context  Passed back to the handler untouched.
 @return The discovery, or NULL when it could not be started.
 */
PADiscovery *pa_discovery_start(PADiscoveryHandler handler, void *context);

/**
 Stops looking and releases the discovery. The handler is not called again, and
 the call returns once the thread carrying it has finished. Safe to call with NULL.
 */
void pa_discovery_stop(PADiscovery *discovery);

/** A connection to one receiver, carrying audio. */
typedef struct PASession PASession;

/**
 Opens a session with a receiver and pairs with it.

 Blocks until the receiver has accepted or refused, which takes a moment.

 @param host        The receiver's host name, from a PAReceiver.
 @param port        Its port.
 @param senderName  What the receiver shows as the source, such as "Podlive" or "Playable".
 @param result      Where the outcome is written. May be NULL.
 @return The session, or NULL when it could not be opened.
 */
PASession *pa_session_open(const char *host, uint16_t port, const char *senderName, PAResult *result);

/**
 Hands the session the next audio to play.

 Interleaved, signed 16-bit, two channels, 44100 Hz. The call copies what it
 needs and returns without waiting, because the thread producing live audio is
 one that must not block.

 A false result means the frames were not taken, and there are two reasons for
 that. Either the session has ended, in which case the next call says so too and
 the caller closes it, or the buffer is full because the sender is still working
 through four seconds of audio. The second is back pressure rather than a
 failure: a live source drops the frames and carries on, and a source reading
 faster than real time waits and offers them again.

 @param session     The open session.
 @param frames      Interleaved samples, two per frame.
 @param frameCount  How many frames, not samples.
 @return Whether the frames were taken.
 */
bool pa_session_write(PASession *session, const int16_t *frames, size_t frameCount);

/**
 Sets the receiver's own volume.

 This is the device's volume rather than a gain applied to the samples, so it
 moves the receiver's control and survives a track change.

 @param session  The open session.
 @param volume   From 0 for silent to 1 for full.
 */
void pa_session_set_volume(PASession *session, float volume);

/** Ends the session and releases it. Safe to call with NULL. */
void pa_session_close(PASession *session);

/** A sentence describing a result, in English, for a log rather than a person. */
const char *pa_result_description(PAResult result);

#ifdef __cplusplus
}
#endif

#endif /* PLAYABLE_AIRPLAY_H */
