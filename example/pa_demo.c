//
//  pa_demo.c
//  Finds receivers, sends a tone to one of them, and proves the interface works
//  without anything from the app it was written for.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#include "PlayableAirplay.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void onReceivers(void *context, const PAReceiver *receivers, size_t count) {
    (void)context;
    printf("\r%zu receiver(s):\n", count);
    for (size_t index = 0; index < count; index++) {
        printf("  %-24s %-40s :%u  %s\n", receivers[index].name, receivers[index].host,
               receivers[index].port, receivers[index].supportsAirPlay2 ? "AirPlay 2" : "AirPlay 1");
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("usage: pa_demo list\n"
               "       pa_demo play <host> [port] [seconds]\n");
        return 2;
    }

    if (strcmp(argv[1], "list") == 0) {
        PADiscovery *discovery = pa_discovery_start(onReceivers, NULL);
        if (!discovery) { fprintf(stderr, "could not start discovery\n"); return 1; }

        printf("looking for receivers, five seconds\n");
        sleep(5);
        pa_discovery_stop(discovery);
        return 0;
    }

    if (strcmp(argv[1], "play") != 0 || argc < 3) {
        printf("usage: pa_demo play <host> [port] [seconds]\n");
        return 2;
    }

    const char *host = argv[2];
    const uint16_t port = (uint16_t)(argc > 3 ? atoi(argv[3]) : 7000);
    const int seconds = argc > 4 ? atoi(argv[4]) : 5;

    PAResult result = PAResultOK;
    PASession *session = pa_session_open(host, port, "PlayableAirplay demo", &result);
    if (!session) {
        fprintf(stderr, "could not open: %s\n", pa_result_description(result));
        return 1;
    }

    printf("connected to %s:%u, %d seconds at a tenth of full volume\n", host, port, seconds);
    pa_session_set_volume(session, 0.1f);

    // A quiet 440 Hz tone, written in the chunks a live stream would arrive in.
    enum { kFramesPerChunk = 1024 };
    int16_t chunk[kFramesPerChunk * PA_CHANNELS];
    long frame = 0;

    for (int written = 0; written < seconds * PA_SAMPLE_RATE; written += kFramesPerChunk) {
        for (int index = 0; index < kFramesPerChunk; index++, frame++) {
            const double value = 3000.0 * sin(2.0 * M_PI * 440.0 * (double)frame / PA_SAMPLE_RATE);
            chunk[index * 2] = chunk[index * 2 + 1] = (int16_t)value;
        }

        if (!pa_session_write(session, chunk, kFramesPerChunk)) {
            // This tone is generated as fast as the loop runs, so a full buffer
            // means the sender has not caught up yet. A live source would drop
            // the frames here; one that can pause offers them again.
            usleep(10000);
            written -= kFramesPerChunk;
            continue;
        }

        usleep((useconds_t)(1000000.0 * kFramesPerChunk / PA_SAMPLE_RATE));
    }

    pa_session_close(session);
    printf("done\n");

    return 0;
}
