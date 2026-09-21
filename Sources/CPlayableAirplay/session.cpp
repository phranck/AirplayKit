//
//  session.cpp
//  The C session interface, over the C++ sender.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

#include "PlayableAirplay.h"

#include "raop_auth.h"
#include "raop_loop.h"
#include "raop_sender.h"
#include "ring_buffer.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

using namespace fxchain;

namespace {

/**
 How much audio the ring holds.
 *
 * Four seconds at 44100 stereo. Large enough that a caller writing in bursts
 * does not lose frames whilst the sender is between packets, small enough that
 * a stream stopped at the source falls silent rather than playing on.
 */
constexpr size_t kRingFrames = PA_SAMPLE_RATE * 4;

/**
 How long opening a session waits for the receiver to accept or refuse.
 *
 * The pairing is several round trips and a receiver that is asleep takes a
 * moment to wake. A caller blocked for ever is worse than one told no.
 */
constexpr auto kOpenTimeout = std::chrono::seconds(12);

}  // namespace

/**
 One connection to one receiver.
 *
 * The sender needs its loop pumped continuously, so the session owns a thread
 * that does nothing else. Audio arrives from whichever thread the caller is on
 * and is handed over through the ring, which is the only thing the two threads
 * share.
 */
struct PASession {
    RingBuffer<int16_t> ring{kRingFrames * PA_CHANNELS};
    RaopLoop loop;
    std::unique_ptr<RaopSender> sender;
    std::thread pump;

    std::mutex mutex;
    std::condition_variable settled;
    /** Set once the receiver has accepted or refused, which is what open waits for. */
    bool answered = false;
    bool running = false;
    std::string failure;
};

extern "C" {

const char *pa_result_description(PAResult result) {
    switch (result) {
        case PAResultOK:              return "the receiver accepted";
        case PAResultUnreachable:     return "the receiver could not be reached";
        case PAResultPairingRefused:  return "the receiver refused the pairing";
        case PAResultSessionEnded:    return "the receiver ended the session";
        case PAResultInvalidArgument: return "the caller passed something unusable";
        case PAResultInternal:        return "the sender failed for a reason the caller cannot act on";
    }

    return "unknown";
}

PASession *pa_session_open(const char *host, uint16_t port, const char *senderName, PAResult *result) {
    const auto report = [result](PAResult value) { if (result) *result = value; };

    if (!host || host[0] == '\0' || port == 0) {
        report(PAResultInvalidArgument);
        return nullptr;
    }

    auto *session = new PASession();

    RaopEvents events;
    events.launched = [session](bool ok, const std::string &error) {
        {
            std::lock_guard<std::mutex> guard(session->mutex);
            session->answered = true;
            session->running = ok;
            session->failure = ok ? std::string() : error;
        }
        session->settled.notify_all();
    };
    events.closed = [session] {
        {
            std::lock_guard<std::mutex> guard(session->mutex);
            session->answered = true;
            session->running = false;
        }
        session->settled.notify_all();
    };
    // A receiver that asks for a PIN needs a screen and a person. Nothing here
    // can answer it, so the session gives up rather than waiting for a code
    // that is never coming. Apple TV is that case; HomePod and Sonos are not.
    events.pinRequired = [session](const std::string &) {
        {
            std::lock_guard<std::mutex> guard(session->mutex);
            session->answered = true;
            session->running = false;
            session->failure = "the receiver wants a PIN, which this interface cannot ask for";
        }
        session->settled.notify_all();
    };

    session->sender = std::make_unique<RaopSender>(session->loop, std::move(events));
    session->sender->setInputFormat(PA_SAMPLE_RATE);
    session->sender->attachRing(&session->ring);

    RaopIdentity identity;
    identity.name = (senderName && senderName[0] != '\0') ? senderName : "Playable";
    session->sender->setIdentity(identity);

    // Transient pairing with the fixed PIN, which is what a receiver without a
    // screen uses: HomePod, a Mac, and every third-party AirPlay 2 speaker
    // measured so far. Nothing is stored, so there is nothing to keep in step
    // and nothing to leak.
    session->sender->setAuth(RaopDeviceInfo::Auth::HapTransient, true, host, std::string(), std::string());

    session->pump = std::thread([session] {
        while (!session->loop.stopRequested()) {
            session->loop.pump(*session->sender);
        }
    });

    session->sender->start(host, port, identity.name);

    std::unique_lock<std::mutex> guard(session->mutex);
    const bool answered = session->settled.wait_for(guard, kOpenTimeout, [session] { return session->answered; });
    const bool running = session->running;
    const bool refused = answered && !running;
    guard.unlock();

    if (running) {
        report(PAResultOK);
        return session;
    }

    pa_session_close(session);
    report(refused ? PAResultPairingRefused : PAResultUnreachable);

    return nullptr;
}

bool pa_session_write(PASession *session, const int16_t *frames, size_t frameCount) {
    if (!session || !frames || frameCount == 0) return false;

    {
        std::lock_guard<std::mutex> guard(session->mutex);
        if (!session->running) return false;
    }

    // Refused rather than blocked when the ring is full. This runs on whatever
    // thread produces the audio, which for a live stream is one that must not
    // wait, so the choice between dropping the frames and offering them again
    // belongs to the caller, who knows where they came from.
    return session->ring.tryPush(std::span<const int16_t>(frames, frameCount * PA_CHANNELS));
}

bool pa_session_is_running(PASession *session) {
    if (!session) return false;

    std::lock_guard<std::mutex> guard(session->mutex);
    return session->running;
}

void pa_session_set_volume(PASession *session, float volume) {
    if (!session) return;

    const float clamped = volume < 0.0f ? 0.0f : (volume > 1.0f ? 1.0f : volume);
    session->sender->setVolume(clamped * 100.0);
}

void pa_session_close(PASession *session) {
    if (!session) return;

    if (session->sender) session->sender->stop();

    session->loop.requestStop();
    if (session->pump.joinable()) session->pump.join();

    delete session;
}

}  // extern "C"
