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
#define PA_MAX_NAME  128
#define PA_MAX_HOST  256
#define PA_MAX_ID     64
#define PA_MAX_MODEL  64

/**
 How large a group identity may be.

 Wider than an identifier, because a receiver in a group of several publishes
 every member's identifier joined with `+` rather than one value. A stereo pair
 measured on one network published two, at 73 characters together.
 */
#define PA_MAX_GROUP 256

/** The audio the sender takes. Fixed, because this is what AirPlay carries. */
#define PA_SAMPLE_RATE 44100
#define PA_CHANNELS        2

/**
 The bits of a receiver's status field that move with the state of a session.

 Named for what they were measured to indicate rather than for what the
 published tables call them, because those tables disagree and none of them was
 checked against a device. The two connection bits are only ever seen together.
 */
#define PA_STATE_SENDER_CONNECTED 0x20800u
#define PA_STATE_PLAYING          0x100000u

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
    /** What a person calls it, such as "Dining Room". */
    char name[PA_MAX_NAME];
    /** Where to reach it, as a host name rather than an address, since addresses move. */
    char host[PA_MAX_HOST];
    /**
     What it says it is, taken from the `am` field it announces, or `model` on
     the AirPlay service, which carry the same value.

     Apple's receivers give a model identifier, such as `AudioAccessory5,1` for a
     HomePod mini or `AppleTV11,1` for an Apple TV, which is the same code the
     machine answers to elsewhere. Everybody else gives whatever they like: Sonos
     announces product names such as `Arc` or `One`. Empty where a receiver
     announced nothing, so a caller treats it as a hint rather than a fact.
     */
    char model[PA_MAX_MODEL];
    /**
     Which group of receivers it says it belongs to, from the `gid` field.

     Published on the AirPlay service and on no RAOP record, so this is empty
     for a receiver found only through the older service and for one that
     announced nothing. Empty means unknown rather than alone.

     Measured on one network of eight receivers. Every Sonos published its own
     `pi` value here. Apple's devices published a different value from their
     `pi`, and a HomePod mini published two identifiers joined by `+`.

     What two receivers sharing a value means is not established, and for a
     Sonos it is known not to mean grouping: three of them playing together as
     one group each published a different value, and each was its own. Comparing
     the value is the obvious thing to do with it and it is not a tested one.
     */
    char groupID[PA_MAX_GROUP];
    /** The port its RTSP service listens on. */
    uint16_t port;
    /** Whether it announced the AirPlay 2 pairing key. A receiver without one needs the older path. */
    bool supportsAirPlay2;
    /**
     Whether a sender currently holds a session with it.

     Read from the status field the receiver advertises, which changes as its
     state changes, so this arrives with an ordinary Bonjour update and costs no
     request. Measured on a HomePod mini: two bits appear together when a sender
     connects and clear again when it disconnects.

     False for a receiver that does not report its state, which is every receiver
     that is not Apple's. Treat it as a receiver saying it is busy rather than as
     a receiver saying it is free.
     */
    bool hasSender;
    /**
     Whether audio is flowing to it at this moment.

     A third bit of that same field, which appears whilst something is playing
     and clears when it stops whilst the sender stays connected. So a receiver
     can have a sender and not be playing.

     False for a receiver that does not report its state, exactly as above.
     */
    bool isPlaying;
} PAReceiver;

/**
 Why a browse is finding nothing.

 An empty list has several causes that look identical from outside, and they
 want opposite answers. A network with nothing on it is not a problem at all; a
 machine that refused the application access to the local network is one only a
 person can clear.
 */
typedef enum PADiscoveryProblem {
    /** Nothing is wrong. The browse is running and the network is as it is. */
    PADiscoveryProblemNone = 0,
    /** The responder said in as many words that this application may not look. */
    PADiscoveryProblemRefused,
    /**
     No mDNS responder this application can reach.

     Two things arrive here and the responder does not separate them: a machine
     with none at all, and a machine with one that this application is not
     allowed to reach. Measured: a sandboxed application denied the network gets
     exactly the same code as a machine running nothing.
     */
    PADiscoveryProblemNoResponder,
    /** Something else failed, and the code says what the system called it. */
    PADiscoveryProblemFailed,
} PADiscoveryProblem;

/** Finds receivers on the network and reports them as they come and go. */
typedef struct PADiscovery PADiscovery;

/**
 Why this discovery is finding nothing, or PADiscoveryProblemNone.

 A browse can start and be refused afterwards, which is what a machine that
 withholds local network access does, so this is worth reading whenever the set
 of receivers arrives rather than only once at the start.

 @param discovery  The discovery, or NULL, which has no problem to report.
 @param code       Where the system's own error number is written, for a log. May be NULL.
 @return What is wrong.
 */
PADiscoveryProblem pa_discovery_problem(PADiscovery *discovery, int32_t *code);

/**
 What one of the responder's error numbers means.

 Exposed because it is the only part of reporting a problem that can be checked
 without a network, a responder, or a sandbox to be refused by. Discovery reads
 every error through it.

 @param error  The number the responder returned.
 @return What to tell somebody holding an empty list.
 */
PADiscoveryProblem pa_discovery_problem_for_error(int32_t error);

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
 @param problem  Where the reason is written when nothing could be started. May be NULL.
 @param code     Where the system's own error number is written alongside it. May be NULL.
 @return The discovery, or NULL when it could not be started.
 */
PADiscovery *pa_discovery_start(PADiscoveryHandler handler, void *context,
                                PADiscoveryProblem *problem, int32_t *code);

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
 Whether the session is still carrying audio.

 This is what separates the two reasons pa_session_write refuses frames: a
 session that is still running refused them because its buffer is full, and one
 that is not has ended and wants closing.

 @param session  The session, or NULL, which is not running.
 @return Whether the receiver is still taking audio.
 */
bool pa_session_is_running(PASession *session);

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
