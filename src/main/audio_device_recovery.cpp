// SPDX-FileCopyrightText: 2026 Christopher Conley
// SPDX-License-Identifier: MIT

#include "audio_device_recovery.h"

#include <cstdio>

namespace {
    // True once the queue has stayed above `stall_bytes` for `stall_time`.
    bool queue_stalled(SDL_AudioDeviceID device, dk64::AudioDeviceRecovery& state, Uint32 stall_bytes,
                       std::chrono::steady_clock::duration stall_time, std::chrono::steady_clock::time_point now) {
        if (SDL_GetQueuedAudioSize(device) <= stall_bytes) {
            state.backlogged = false;
            return false;
        }
        if (!state.backlogged) {
            state.backlogged = true;
            state.backlog_since = now;
        }
        return now - state.backlog_since >= stall_time;
    }
}

bool dk64::keep_audio_device_playing(
    SDL_AudioDeviceID& device,
    SDL_AudioDeviceID (*open_device)(),
    AudioDeviceRecovery& state,
    Uint32 stall_bytes,
    std::chrono::steady_clock::duration stall_time,
    std::chrono::steady_clock::duration retry_interval)
{
    const auto now = std::chrono::steady_clock::now();

    if (device != 0) {
        // A paused device is left alone: only SDL stops a device, and only when
        // it has lost it.
        const bool stopped = SDL_GetAudioDeviceStatus(device) == SDL_AUDIO_STOPPED;
        const bool stalled = !stopped && queue_stalled(device, state, stall_bytes, stall_time, now);
        if (!stopped && !stalled) {
            return true;
        }

        fprintf(stderr, "Audio output device %s; reopening the default device.\n",
                stopped ? "stopped" : "stopped consuming audio");
        SDL_CloseAudioDevice(device);
        device = 0;
        state.backlogged = false;
        state.next_attempt = {};
    }

    if (now < state.next_attempt) {
        return false;
    }
    state.next_attempt = now + retry_interval;

    device = open_device();
    if (device == 0) {
        if (!state.reported_failure) {
            fprintf(stderr, "Could not reopen an audio output device, retrying: %s\n", SDL_GetError());
            state.reported_failure = true;
        }
        return false;
    }

    SDL_PauseAudioDevice(device, 0);
    state.reported_failure = false;
    fprintf(stderr, "Audio output device reopened.\n");
    return true;
}
