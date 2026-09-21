//
//  discovery.c
//  Finding AirPlay receivers on the network.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#include "PlayableAirplay.h"

#include "receiver_name.h"

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

/** The service AirPlay audio receivers advertise. */
static const char *const kServiceType = "_raop._tcp";

/** How many receivers are tracked. A home has a handful; the cap is for safety, not for fit. */
#define PA_MAX_RECEIVERS 64

struct PADiscovery {
    DNSServiceRef browser;
    PADiscoveryHandler handler;
    void *context;

    pthread_t thread;
    volatile bool stopping;

    pthread_mutex_t mutex;
    PAReceiver receivers[PA_MAX_RECEIVERS];
    size_t count;
};

/** Reports the current set to the caller, ordered by name so the list does not jump about. */
static void announce(PADiscovery *discovery) {
    pthread_mutex_lock(&discovery->mutex);

    for (size_t outer = 0; outer + 1 < discovery->count; outer++) {
        for (size_t inner = 0; inner + 1 < discovery->count - outer; inner++) {
            if (strcasecmp(discovery->receivers[inner].name, discovery->receivers[inner + 1].name) > 0) {
                PAReceiver swap = discovery->receivers[inner];
                discovery->receivers[inner] = discovery->receivers[inner + 1];
                discovery->receivers[inner + 1] = swap;
            }
        }
    }

    PAReceiver snapshot[PA_MAX_RECEIVERS];
    memcpy(snapshot, discovery->receivers, sizeof(PAReceiver) * discovery->count);
    const size_t count = discovery->count;

    pthread_mutex_unlock(&discovery->mutex);

    if (discovery->handler) discovery->handler(discovery->context, snapshot, count);
}


/** Records what resolving one service found, replacing any earlier sighting of it. */
static void DNSSD_API onResolved(DNSServiceRef service, DNSServiceFlags flags, uint32_t interfaceIndex,
                                 DNSServiceErrorType error, const char *fullName, const char *hostTarget,
                                 uint16_t port, uint16_t txtLength, const unsigned char *txt, void *context) {
    (void)service; (void)flags; (void)interfaceIndex; (void)fullName;

    PADiscovery *discovery = (PADiscovery *)context;
    if (error != kDNSServiceErr_NoError || !hostTarget) return;

    PAReceiver receiver;
    memset(&receiver, 0, sizeof(receiver));

    char instance[PA_MAX_NAME];

    // A receiver that announces a pairing key speaks AirPlay 2. Measured across
    // every receiver on one network: Sonos, HomePod and macOS all carry it, and
    // none offers the older RSA encryption that AirPlay 1 needs.
    //
    // The length is written back rather than optional: this call dereferences
    // that pointer without checking it, so passing NULL crashes inside the
    // system library rather than returning anything.
    uint8_t valueLength = 0;
    receiver.supportsAirPlay2 = TXTRecordGetValuePtr(txtLength, txt, "pk", &valueLength) != NULL;

    strncpy(instance, fullName, sizeof(instance) - 1);
    instance[sizeof(instance) - 1] = '\0';
    char *dot = strstr(instance, "._raop.");
    if (dot) *dot = '\0';

    pa_split_instance_name(instance, receiver.id, sizeof(receiver.id), receiver.name, sizeof(receiver.name));
    strncpy(receiver.host, hostTarget, sizeof(receiver.host) - 1);
    receiver.port = ntohs(port);

    pthread_mutex_lock(&discovery->mutex);

    size_t slot = discovery->count;
    for (size_t index = 0; index < discovery->count; index++) {
        if (strcmp(discovery->receivers[index].id, receiver.id) == 0) {
            slot = index;
            break;
        }
    }

    if (slot < PA_MAX_RECEIVERS) {
        discovery->receivers[slot] = receiver;
        if (slot == discovery->count) discovery->count++;
    }

    pthread_mutex_unlock(&discovery->mutex);

    announce(discovery);
}

/** Resolves a service that appeared, or forgets one that went away. */
static void DNSSD_API onBrowsed(DNSServiceRef service, DNSServiceFlags flags, uint32_t interfaceIndex,
                                DNSServiceErrorType error, const char *instance, const char *type,
                                const char *domain, void *context) {
    (void)service;

    PADiscovery *discovery = (PADiscovery *)context;
    if (error != kDNSServiceErr_NoError) return;

    if (flags & kDNSServiceFlagsAdd) {
        // Resolved on its own connection, which is closed as soon as it has
        // answered. A resolve left open keeps a socket per receiver for as
        // long as discovery runs.
        DNSServiceRef resolver = NULL;
        if (DNSServiceResolve(&resolver, 0, interfaceIndex, instance, type, domain,
                              onResolved, discovery) == kDNSServiceErr_NoError) {
            DNSServiceProcessResult(resolver);
            DNSServiceRefDeallocate(resolver);
        }
        return;
    }

    char identifier[PA_MAX_ID];
    char name[PA_MAX_NAME];
    pa_split_instance_name(instance, identifier, sizeof(identifier), name, sizeof(name));

    pthread_mutex_lock(&discovery->mutex);
    for (size_t index = 0; index < discovery->count; index++) {
        if (strcmp(discovery->receivers[index].id, identifier) != 0) continue;

        discovery->receivers[index] = discovery->receivers[discovery->count - 1];
        discovery->count--;
        break;
    }
    pthread_mutex_unlock(&discovery->mutex);

    announce(discovery);
}

/** Waits on the browse socket and hands anything that arrives to the callbacks. */
static void *runDiscovery(void *argument) {
    PADiscovery *discovery = (PADiscovery *)argument;
    const int socket = DNSServiceRefSockFD(discovery->browser);

    while (!discovery->stopping) {
        fd_set readable;
        FD_ZERO(&readable);
        FD_SET(socket, &readable);

        // A second at a time, so stopping is noticed promptly without spinning.
        struct timeval timeout = { .tv_sec = 1, .tv_usec = 0 };
        if (select(socket + 1, &readable, NULL, NULL, &timeout) > 0 && FD_ISSET(socket, &readable)) {
            if (DNSServiceProcessResult(discovery->browser) != kDNSServiceErr_NoError) break;
        }
    }

    return NULL;
}

PADiscovery *pa_discovery_start(PADiscoveryHandler handler, void *context) {
    PADiscovery *discovery = calloc(1, sizeof(PADiscovery));
    if (!discovery) return NULL;

    discovery->handler = handler;
    discovery->context = context;
    pthread_mutex_init(&discovery->mutex, NULL);

    if (DNSServiceBrowse(&discovery->browser, 0, 0, kServiceType, NULL,
                         onBrowsed, discovery) != kDNSServiceErr_NoError) {
        pthread_mutex_destroy(&discovery->mutex);
        free(discovery);
        return NULL;
    }

    if (pthread_create(&discovery->thread, NULL, runDiscovery, discovery) != 0) {
        DNSServiceRefDeallocate(discovery->browser);
        pthread_mutex_destroy(&discovery->mutex);
        free(discovery);
        return NULL;
    }

    return discovery;
}

void pa_discovery_stop(PADiscovery *discovery) {
    if (!discovery) return;

    discovery->stopping = true;
    pthread_join(discovery->thread, NULL);

    DNSServiceRefDeallocate(discovery->browser);
    pthread_mutex_destroy(&discovery->mutex);
    free(discovery);
}
