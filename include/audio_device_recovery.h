// SPDX-FileCopyrightText: 2026 Christopher Conley
// SPDX-License-Identifier: MIT

#ifndef AUDIO_DEVICE_RECOVERY_H
#define AUDIO_DEVICE_RECOVERY_H

#include <chrono>

#ifdef _WIN32
#include "SDL.h"
#else
#include "SDL2/SDL.h"
#endif

namespace dk64 {
    // Retry, stall and logging state for keep_audio_device_playing().
    struct AudioDeviceRecovery {
        std::chrono::steady_clock::time_point next_attempt{};
        std::chrono::steady_clock::time_point backlog_since{};
        bool backlogged = false;
        bool reported_failure = false;
    };

    // Returns true when `device` is open and able to play queued audio.
    //
    // A device is treated as lost in two cases, both of which leave the game
    // running with no sound until a restart:
    //
    // - SDL has stopped it. SDL 2 does this when it loses a device and never
    //   starts it again: on Windows that is any audio error other than the
    //   device being invalidated or the default device changing. A stopped
    //   device still accepts queued audio and drains it at the normal rate,
    //   but plays none of it.
    // - It still reports playing, but its queue has held more than
    //   `stall_bytes` for `stall_time` without stopping. Nothing is consuming
    //   it. SDL 2's Windows backend can wait on such a device indefinitely, and
    //   SDL 3 (sdl2-compat on Linux) does so when its stream is destroyed.
    //
    // A lost device is closed and replaced with the result of `open_device`, at
    // most once per `retry_interval`. `device` is 0 while no replacement could
    // be opened.
    bool keep_audio_device_playing(
        SDL_AudioDeviceID& device,
        SDL_AudioDeviceID (*open_device)(),
        AudioDeviceRecovery& state,
        Uint32 stall_bytes,
        std::chrono::steady_clock::duration stall_time = std::chrono::seconds(1),
        std::chrono::steady_clock::duration retry_interval = std::chrono::seconds(1));
}

#endif
