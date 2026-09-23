//
//  discovery.c
//  Finding AirPlay receivers on the network.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

#include "PlayableAirplay.h"

#include "include/receiver_name.h"
#include "include/receiver_state.h"

#include <arpa/inet.h>
#include <dns_sd.h>
#include <pthread.h>
#include <strings.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

/*
 Why dns_sd rather than each platform's own.

 This header is Apple's, and Linux carries the same one through Avahi's
 compatibility layer. One implementation therefore covers both, which is the
 whole reason this file is C and not an Objective-C category around
 NSNetServiceBrowser.
 */

/**
 The two services a receiver advertises, and why both are browsed.

 RAOP is AirPlay's audio half and has carried that name since it was AirTunes.
 The AirPlay service is the general one. Every shipping receiver measured on one
 network published both, and a receiver that publishes only the second exists
 and is offered by macOS as a sound output, so browsing one type is not enough.

 The second service also carries what the first does not. A receiver's group is
 published there and in no RAOP record.
 */
static const char *const kRaopServiceType = "_raop._tcp";
static const char *const kAirplayServiceType = "_airplay._tcp";

/** Which of the two a callback is reporting about. */
typedef enum PAServiceKind {
    PAServiceRaop,
    PAServiceAirplay,
} PAServiceKind;

/** How many receivers are tracked. A home has a handful; the cap is for safety, not for fit. */
#define PA_MAX_RECEIVERS 64

/**
 One receiver, plus what is needed to keep the two services' sightings of it
 together.

 A service going away names only its own instance, and the two services name the
 same receiver differently, so each instance is kept as it arrived. The receiver
 is dropped when both have gone, because until then it is still out there.
 */
typedef struct PARecord {
    PAReceiver receiver;
    char raopInstance[PA_MAX_NAME];
    char airplayInstance[PA_MAX_NAME];
} PARecord;

/**
 What a browse or resolve callback needs to know: which discovery, and which of
 the two services it is hearing about.

 One of these lives inside the discovery per service, so its lifetime is the
 discovery's exactly. The callbacks have stopped by the time the discovery is
 freed, because stopping joins the thread first.
 */
typedef struct PABrowseContext {
    struct PADiscovery *discovery;
    PAServiceKind kind;
} PABrowseContext;

struct PADiscovery {
    DNSServiceRef browsers[2];
    PABrowseContext contexts[2];
    PADiscoveryHandler handler;
    void *context;

    pthread_t thread;
    volatile bool stopping;

    /**
     Wakes ::runDiscovery the moment stopping is requested, instead of leaving
     it to notice on its next select() timeout.

     ::pa_discovery_stop joins that thread before returning, so whatever the
     timeout is becomes how long the caller blocks. The pipe turns that wait
     from the length of the timeout into the length of a context switch,
     which is worth having on its own terms: a caller has no reason to expect
     stopping to take up to a second.
     */
    int wakePipe[2];

    pthread_mutex_t mutex;
    PARecord records[PA_MAX_RECEIVERS];
    size_t count;

    PADiscoveryProblem problem;
    int32_t problemCode;
};

/*
 Three codes written out rather than named.

 Apple's `dns_sd.h` declares them and Avahi's compatibility header does not, so
 naming them there fails to compile. The numbers are Apple's, taken from that
 header, and they are what its responder returns. Avahi's own responder never
 returns them, because it does not know them, which is exactly right: on Linux
 these branches simply never match.
 */
#define PA_DNS_SERVICE_NOT_RUNNING (-65563)
#define PA_DNS_POLICY_DENIED       (-65570)
#define PA_DNS_NOT_PERMITTED       (-65571)

/**
 What an error from the responder means to somebody holding an empty list.

 `kDNSServiceErr_ServiceNotRunning` is the interesting one and it is ambiguous.
 Measured: a sandboxed application without the network entitlement gets exactly
 that, and so does a machine with no responder at all. The responder does not
 separate the two, so neither does this, and the name says what is true of both.

 The four codes that do say denied in as many words are mapped to a refusal.
 None of them was produced in either run, so that mapping comes from the SDK
 header rather than from an observation.
 */
PADiscoveryProblem pa_discovery_problem_for_error(int32_t error) {
    switch (error) {
        case kDNSServiceErr_NoError:
            return PADiscoveryProblemNone;

        case PA_DNS_POLICY_DENIED:
        case PA_DNS_NOT_PERMITTED:
        case kDNSServiceErr_NoAuth:
        case kDNSServiceErr_Refused:
            return PADiscoveryProblemRefused;

        case PA_DNS_SERVICE_NOT_RUNNING:
            return PADiscoveryProblemNoResponder;

        default:
            return PADiscoveryProblemFailed;
    }
}

/** Copies a terminated string into a fixed buffer, always terminating it. */
static void copyString(char *destination, size_t destinationSize, const char *source) {
    if (!destination || destinationSize == 0) return;

    if (!source) {
        destination[0] = '\0';
        return;
    }

    strncpy(destination, source, destinationSize - 1);
    destination[destinationSize - 1] = '\0';
}

/** Reports the current set to the caller, ordered by name so the list does not jump about. */
static void announce(PADiscovery *discovery) {
    pthread_mutex_lock(&discovery->mutex);

    for (size_t outer = 0; outer + 1 < discovery->count; outer++) {
        for (size_t inner = 0; inner + 1 < discovery->count - outer; inner++) {
            if (strcasecmp(discovery->records[inner].receiver.name,
                           discovery->records[inner + 1].receiver.name) > 0) {
                PARecord swap = discovery->records[inner];
                discovery->records[inner] = discovery->records[inner + 1];
                discovery->records[inner + 1] = swap;
            }
        }
    }

    PAReceiver snapshot[PA_MAX_RECEIVERS];
    for (size_t index = 0; index < discovery->count; index++) {
        snapshot[index] = discovery->records[index].receiver;
    }
    const size_t count = discovery->count;

    pthread_mutex_unlock(&discovery->mutex);

    if (discovery->handler) discovery->handler(discovery->context, snapshot, count);
}

/**
 Copies one TXT value into a fixed buffer, leaving it empty where the key is
 absent. The value is counted rather than terminated where it arrives, so it is
 copied rather than pointed at.
 */
static void copyTextValue(uint16_t txtLength, const unsigned char *txt, const char *key,
                          char *destination, size_t destinationSize) {
    if (!destination || destinationSize == 0) return;

    destination[0] = '\0';

    uint8_t valueLength = 0;
    const void *value = TXTRecordGetValuePtr(txtLength, txt, key, &valueLength);
    if (!value || valueLength == 0) return;

    const size_t room = destinationSize - 1;
    const size_t taken = valueLength < room ? valueLength : room;
    memcpy(destination, value, taken);
    destination[taken] = '\0';
}

/** Finds the record for an identifier, or makes one. NULL when there is no room. */
static PARecord *recordFor(PADiscovery *discovery, const char *identifier) {
    for (size_t index = 0; index < discovery->count; index++) {
        if (strcmp(discovery->records[index].receiver.id, identifier) == 0) {
            return &discovery->records[index];
        }
    }

    if (discovery->count >= PA_MAX_RECEIVERS) return NULL;

    PARecord *record = &discovery->records[discovery->count++];
    memset(record, 0, sizeof(*record));
    copyString(record->receiver.id, sizeof(record->receiver.id), identifier);

    return record;
}

/** Records what resolving one service found, merging it into what is already known. */
static void DNSSD_API onResolved(DNSServiceRef service, DNSServiceFlags flags, uint32_t interfaceIndex,
                                 DNSServiceErrorType error, const char *fullName, const char *hostTarget,
                                 uint16_t port, uint16_t txtLength, const unsigned char *txt, void *context) {
    (void)service; (void)flags; (void)interfaceIndex;

    PABrowseContext *browse = (PABrowseContext *)context;
    PADiscovery *discovery = browse->discovery;
    const bool isRaop = browse->kind == PAServiceRaop;

    if (error != kDNSServiceErr_NoError || !hostTarget || !fullName) return;

    // The instance name up to the service type. A RAOP instance is the hardware
    // address, then `@`, then the display name; an AirPlay instance is the
    // display name alone.
    char escaped[PA_MAX_NAME];
    copyString(escaped, sizeof(escaped), fullName);

    char *separator = strstr(escaped, isRaop ? "._raop." : "._airplay.");
    if (separator) *separator = '\0';

    // The name arrives in its wire form, where a space is `\032` and a dot is
    // `\.`, so it is made readable before anything reads it or shows it.
    char instance[PA_MAX_NAME];
    pa_unescape_instance_name(escaped, instance, sizeof(instance));

    char identifier[PA_MAX_ID];
    char name[PA_MAX_NAME];

    if (isRaop) {
        pa_split_instance_name(instance, identifier, sizeof(identifier), name, sizeof(name));

        // Raised to the case the other service's identity comes out in, but only
        // where the whole of it is an address. An older receiver that announces
        // no address at all puts its display name here, and that is left alone.
        char normalised[PA_MAX_ID];
        pa_identity_from_device_id(identifier, normalised, sizeof(normalised));
        if (strlen(normalised) == strlen(identifier)) {
            copyString(identifier, sizeof(identifier), normalised);
        }
    } else {
        // The AirPlay instance carries no address, so the identity comes out of
        // the record instead, in the spelling the RAOP instance uses.
        char deviceID[PA_MAX_ID];
        copyTextValue(txtLength, txt, "deviceid", deviceID, sizeof(deviceID));
        pa_identity_from_device_id(deviceID, identifier, sizeof(identifier));

        copyString(name, sizeof(name), instance);

        // Without an address there is nothing to recognise the receiver by on
        // the other service, and nothing stable to remember a choice by either.
        if (identifier[0] == '\0') return;
    }

    pthread_mutex_lock(&discovery->mutex);

    PARecord *record = recordFor(discovery, identifier);
    if (!record) {
        pthread_mutex_unlock(&discovery->mutex);
        return;
    }

    // The two services can disagree about the display name, because Bonjour
    // settles a clash within one service by putting a number after the name and
    // settles each service separately. An Apple TV measured on one network
    // announced `Living Room` on the audio service and `Living Room (2)` on the
    // other. The audio service carries the name its owner gave, so it wins
    // wherever both have been seen.
    if (name[0] != '\0' && (isRaop || record->raopInstance[0] == '\0')) {
        copyString(record->receiver.name, sizeof(record->receiver.name), name);
    }

    copyString(isRaop ? record->raopInstance : record->airplayInstance, PA_MAX_NAME, instance);

    // The RAOP port is the one a session is opened on, because that is the one
    // every measured session used. The AirPlay port fills in only for a receiver
    // that publishes nothing else.
    if (isRaop || record->receiver.port == 0) {
        copyString(record->receiver.host, sizeof(record->receiver.host), hostTarget);
        record->receiver.port = ntohs(port);
    }

    // A receiver that announces a pairing key speaks AirPlay 2. Both services
    // carry it under the same name. Measured across every receiver on one
    // network: Sonos, HomePod and macOS all have it, and none offers the older
    // RSA encryption that AirPlay 1 needs.
    //
    // The length is written back rather than optional: this call dereferences
    // that pointer without checking it, so passing NULL crashes inside the
    // system library rather than returning anything.
    uint8_t keyLength = 0;
    if (TXTRecordGetValuePtr(txtLength, txt, "pk", &keyLength) != NULL) {
        record->receiver.supportsAirPlay2 = true;
    }

    // The same facts under two sets of names. Measured at the same minute on
    // three receivers, the pairs agreed every time.
    char model[PA_MAX_MODEL];
    copyTextValue(txtLength, txt, isRaop ? "am" : "model", model, sizeof(model));
    if (model[0] != '\0') copyString(record->receiver.model, sizeof(record->receiver.model), model);

    // What it is doing, out of the status field. The reading of it sits in
    // receiver_state.c, which is where it can be tested without a network.
    uint8_t stateLength = 0;
    const void *state = TXTRecordGetValuePtr(txtLength, txt, isRaop ? "sf" : "flags", &stateLength);
    if (state) {
        pa_read_receiver_state(state, stateLength,
                               &record->receiver.hasSender, &record->receiver.isPlaying);
    }

    // Published on the AirPlay service alone, so a RAOP sighting leaves whatever
    // an AirPlay one already established rather than clearing it.
    if (!isRaop) {
        copyTextValue(txtLength, txt, "gid", record->receiver.groupID, sizeof(record->receiver.groupID));
    }

    pthread_mutex_unlock(&discovery->mutex);

    announce(discovery);
}

/** Resolves a service that appeared, or forgets one that went away. */
static void DNSSD_API onBrowsed(DNSServiceRef service, DNSServiceFlags flags, uint32_t interfaceIndex,
                                DNSServiceErrorType error, const char *instance, const char *type,
                                const char *domain, void *context) {
    (void)service;

    PABrowseContext *browse = (PABrowseContext *)context;
    PADiscovery *discovery = browse->discovery;
    const bool isRaop = browse->kind == PAServiceRaop;

    if (error != kDNSServiceErr_NoError) {
        // A browse that started and then failed is where a refusal of local
        // network access arrives, so the reason is kept and reported rather
        // than dropped, and the caller is told so it can read it.
        pthread_mutex_lock(&discovery->mutex);
        discovery->problem = pa_discovery_problem_for_error(error);
        discovery->problemCode = error;
        pthread_mutex_unlock(&discovery->mutex);

        announce(discovery);
        return;
    }

    if (flags & kDNSServiceFlagsAdd) {
        // Resolved on its own connection, which is closed as soon as it has
        // answered. A resolve left open keeps a socket per receiver for as
        // long as discovery runs.
        DNSServiceRef resolver = NULL;
        if (DNSServiceResolve(&resolver, 0, interfaceIndex, instance, type, domain,
                              onResolved, browse) != kDNSServiceErr_NoError) {
            return;
        }

        // Waited on rather than processed straight away, because processing
        // blocks until an answer arrives and a service can be announced without
        // being resolvable. A record left behind by a receiver that went away
        // without withdrawing it does exactly that, and blocking here holds the
        // whole discovery, including the stop that is waiting for this thread.
        const int socket = DNSServiceRefSockFD(resolver);
        if (socket >= 0) {
            fd_set readable;
            FD_ZERO(&readable);
            FD_SET(socket, &readable);

            struct timeval timeout = { .tv_sec = 2, .tv_usec = 0 };
            if (select(socket + 1, &readable, NULL, NULL, &timeout) > 0) {
                DNSServiceProcessResult(resolver);
            }
        }

        DNSServiceRefDeallocate(resolver);
        return;
    }

    // Only this service has gone. The receiver stays until the other one has
    // gone too, because a receiver that still advertises anywhere is still
    // there, and the instance is the only thing this callback knows it by.
    pthread_mutex_lock(&discovery->mutex);

    for (size_t index = 0; index < discovery->count; index++) {
        PARecord *record = &discovery->records[index];
        char *own = isRaop ? record->raopInstance : record->airplayInstance;
        const char *other = isRaop ? record->airplayInstance : record->raopInstance;

        if (strcmp(own, instance) != 0) continue;

        own[0] = '\0';
        if (other[0] == '\0') {
            discovery->records[index] = discovery->records[discovery->count - 1];
            discovery->count--;
        }
        break;
    }

    pthread_mutex_unlock(&discovery->mutex);

    announce(discovery);
}

/** Waits on both browse sockets and hands anything that arrives to the callbacks. */
static void *runDiscovery(void *argument) {
    PADiscovery *discovery = (PADiscovery *)argument;

    while (!discovery->stopping) {
        fd_set readable;
        FD_ZERO(&readable);

        const int wake = discovery->wakePipe[0];
        FD_SET(wake, &readable);
        int highest = wake;

        int sockets[2] = { -1, -1 };
        bool anyBrowsing = false;

        for (size_t index = 0; index < 2; index++) {
            if (!discovery->browsers[index]) continue;

            sockets[index] = DNSServiceRefSockFD(discovery->browsers[index]);
            if (sockets[index] < 0) continue;

            anyBrowsing = true;
            FD_SET(sockets[index], &readable);
            if (sockets[index] > highest) highest = sockets[index];
        }

        if (!anyBrowsing) break;

        // Unbounded: what ends the wait is either a socket becoming readable
        // or pa_discovery_stop writing to the wake pipe, never a timeout. A
        // caller joining the thread this runs on is waiting for exactly one
        // of those two, so a timeout here would only delay it without telling
        // it anything, and the wake pipe already answers "did stopping happen".
        if (select(highest + 1, &readable, NULL, NULL, NULL) <= 0) continue;

        if (FD_ISSET(wake, &readable)) break;

        for (size_t index = 0; index < 2; index++) {
            if (sockets[index] < 0 || !FD_ISSET(sockets[index], &readable)) continue;

            // One service failing takes only that service down. The other keeps
            // finding receivers, which is better than a list that empties.
            if (DNSServiceProcessResult(discovery->browsers[index]) != kDNSServiceErr_NoError) {
                DNSServiceRefDeallocate(discovery->browsers[index]);
                discovery->browsers[index] = NULL;
            }
        }
    }

    return NULL;
}

PADiscovery *pa_discovery_start(PADiscoveryHandler handler, void *context,
                                PADiscoveryProblem *problem, int32_t *code) {
    if (problem) *problem = PADiscoveryProblemNone;
    if (code) *code = 0;

    PADiscovery *discovery = calloc(1, sizeof(PADiscovery));
    if (!discovery) {
        if (problem) *problem = PADiscoveryProblemFailed;
        return NULL;
    }

    discovery->handler = handler;
    discovery->context = context;
    pthread_mutex_init(&discovery->mutex, NULL);

    if (pipe(discovery->wakePipe) != 0) {
        pthread_mutex_destroy(&discovery->mutex);
        free(discovery);

        if (problem) *problem = PADiscoveryProblemFailed;
        return NULL;
    }

    const char *types[2] = { kRaopServiceType, kAirplayServiceType };
    const PAServiceKind kinds[2] = { PAServiceRaop, PAServiceAirplay };
    size_t started = 0;
    DNSServiceErrorType lastError = kDNSServiceErr_NoError;

    for (size_t index = 0; index < 2; index++) {
        discovery->contexts[index].discovery = discovery;
        discovery->contexts[index].kind = kinds[index];

        const DNSServiceErrorType outcome =
            DNSServiceBrowse(&discovery->browsers[index], 0, 0, types[index], NULL,
                             onBrowsed, &discovery->contexts[index]);

        if (outcome == kDNSServiceErr_NoError) {
            started++;
        } else {
            discovery->browsers[index] = NULL;
            lastError = outcome;
        }
    }

    // One service is enough to find receivers, and neither is enough to fail on
    // its own. Nothing at all is a machine that cannot browse, and the reason
    // the responder gave is what tells a refusal from an absent responder.
    if (started == 0) {
        if (problem) *problem = pa_discovery_problem_for_error(lastError);
        if (code) *code = lastError;

        close(discovery->wakePipe[0]);
        close(discovery->wakePipe[1]);
        pthread_mutex_destroy(&discovery->mutex);
        free(discovery);
        return NULL;
    }

    if (pthread_create(&discovery->thread, NULL, runDiscovery, discovery) != 0) {
        for (size_t index = 0; index < 2; index++) {
            if (discovery->browsers[index]) DNSServiceRefDeallocate(discovery->browsers[index]);
        }
        close(discovery->wakePipe[0]);
        close(discovery->wakePipe[1]);
        pthread_mutex_destroy(&discovery->mutex);
        free(discovery);

        if (problem) *problem = PADiscoveryProblemFailed;
        return NULL;
    }

    return discovery;
}

PADiscoveryProblem pa_discovery_problem(PADiscovery *discovery, int32_t *code) {
    if (code) *code = 0;
    if (!discovery) return PADiscoveryProblemNone;

    pthread_mutex_lock(&discovery->mutex);
    const PADiscoveryProblem problem = discovery->problem;
    if (code) *code = discovery->problemCode;
    pthread_mutex_unlock(&discovery->mutex);

    return problem;
}

void pa_discovery_stop(PADiscovery *discovery) {
    if (!discovery) return;

    discovery->stopping = true;

    // Wakes the select() in runDiscovery at once. What is written does not
    // matter, only that the read end becomes readable.
    const uint8_t wake = 0;
    (void)write(discovery->wakePipe[1], &wake, sizeof(wake));

    pthread_join(discovery->thread, NULL);

    close(discovery->wakePipe[0]);
    close(discovery->wakePipe[1]);

    for (size_t index = 0; index < 2; index++) {
        if (discovery->browsers[index]) DNSServiceRefDeallocate(discovery->browsers[index]);
    }

    pthread_mutex_destroy(&discovery->mutex);
    free(discovery);
}
