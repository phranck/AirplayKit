//
//  pa_tests.c
//  What can be checked without a receiver on the network.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#include "PlayableAirplay.h"
#include "receiver_name.h"

#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition, description)                                        \
    do {                                                                     \
        if (condition) {                                                     \
            printf("  ok    %s\n", (description));                           \
        } else {                                                             \
            printf("  FAIL  %s  (%s:%d)\n", (description), __FILE__, __LINE__); \
            failures++;                                                      \
        }                                                                    \
    } while (0)

static void splitsAnInstanceIntoAddressAndName(void) {
    char identifier[PA_MAX_ID], name[PA_MAX_NAME];

    pa_split_instance_name("48A6B8F7CA56@Room B", identifier, sizeof(identifier), name, sizeof(name));
    CHECK(strcmp(identifier, "48A6B8F7CA56") == 0, "the address is what stands before the separator");
    CHECK(strcmp(name, "Room B") == 0, "the name is what stands after it");
}

static void keepsANameThatCarriesNoAddress(void) {
    char identifier[PA_MAX_ID], name[PA_MAX_NAME];

    pa_split_instance_name("Room A", identifier, sizeof(identifier), name, sizeof(name));
    CHECK(strcmp(identifier, "Room A") == 0, "an instance without a separator identifies itself");
    CHECK(strcmp(name, "Room A") == 0, "and names itself");
}

static void keepsASeparatorInsideTheName(void) {
    char identifier[PA_MAX_ID], name[PA_MAX_NAME];

    // A name may hold the separator too, and only the first one divides.
    pa_split_instance_name("AABBCC@the HomePod mini@Home", identifier, sizeof(identifier), name, sizeof(name));
    CHECK(strcmp(identifier, "AABBCC") == 0, "only the first separator divides");
    CHECK(strcmp(name, "the HomePod mini@Home") == 0, "the rest belongs to the name");
}

static void terminatesWhateverItIsGiven(void) {
    char identifier[4], name[4];

    pa_split_instance_name("48A6B8F7CA56@Room B", identifier, sizeof(identifier), name, sizeof(name));
    CHECK(identifier[3] == '\0', "a short identifier buffer is still terminated");
    CHECK(name[3] == '\0', "and so is a short name buffer");
}

static void survivesNothing(void) {
    char identifier[PA_MAX_ID], name[PA_MAX_NAME];

    pa_split_instance_name(NULL, identifier, sizeof(identifier), name, sizeof(name));
    pa_split_instance_name("x", NULL, 0, name, sizeof(name));
    CHECK(1, "nothing passed in is a reason to crash");
}

static void describesEveryResult(void) {
    const PAResult all[] = { PAResultOK, PAResultUnreachable, PAResultPairingRefused,
                             PAResultSessionEnded, PAResultInvalidArgument, PAResultInternal };

    for (size_t index = 0; index < sizeof(all) / sizeof(all[0]); index++) {
        const char *text = pa_result_description(all[index]);
        if (!text || text[0] == '\0' || strcmp(text, "unknown") == 0) {
            printf("  FAIL  result %d has no description\n", (int)all[index]);
            failures++;
            return;
        }
    }

    CHECK(1, "every result says what it means");
}

static void refusesAnUnusableReceiver(void) {
    PAResult result = PAResultOK;

    CHECK(pa_session_open(NULL, 7000, "test", &result) == NULL, "no host is not a session");
    CHECK(result == PAResultInvalidArgument, "and it says which mistake that was");

    CHECK(pa_session_open("host.local", 0, "test", &result) == NULL, "no port is not a session either");
    CHECK(result == PAResultInvalidArgument, "and it says so too");
}

static void ignoresWritingToNothing(void) {
    const int16_t frames[2] = { 0, 0 };

    CHECK(pa_session_write(NULL, frames, 1) == false, "writing to no session reports that it went nowhere");
    pa_session_set_volume(NULL, 0.5f);
    pa_session_close(NULL);
    CHECK(1, "and closing or setting nothing is allowed");
}

static void startsAndStopsDiscovery(void) {
    // Whether anything is found depends on the network, which a test must not.
    // Whether browsing can start at all depends on an mDNS daemon being there,
    // and a build machine often has none, so a refusal is a result too. What is
    // checked is that both paths come back and that stopping takes either.
    PADiscovery *discovery = pa_discovery_start(NULL, NULL);
    pa_discovery_stop(discovery);
    CHECK(1, "discovery starts and stops, or declines and stops");
}

int main(void) {
    printf("PlayableAirplay\n");
    splitsAnInstanceIntoAddressAndName();
    keepsANameThatCarriesNoAddress();
    keepsASeparatorInsideTheName();
    terminatesWhateverItIsGiven();
    survivesNothing();
    describesEveryResult();
    refusesAnUnusableReceiver();
    ignoresWritingToNothing();
    startsAndStopsDiscovery();

    printf("\n%s\n", failures == 0 ? "all checks passed" : "FAILED");

    return failures == 0 ? 0 : 1;
}
