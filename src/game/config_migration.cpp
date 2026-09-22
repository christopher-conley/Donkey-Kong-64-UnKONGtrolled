// SPDX-FileCopyrightText: 2026 Christopher Conley
// SPDX-License-Identifier: MIT

#include "donk_config.h"
#include "recompui/program_config.h"
#include "util/file.h"

#include <cstdio>
#include <filesystem>
#include <system_error>

namespace {
    // recompui::file::get_app_folder_path() resolves against whichever program id
    // is currently set, and also honours portable.txt, APP_FOLDER_PATH and the
    // macOS application support directory. Asking it twice is deliberate: a
    // second copy of that formula here would drift the first time any of those
    // rules changed.
    std::filesystem::path folder_for(const std::u8string& id) {
        recompui::programconfig::set_program_id(id);
        return recompui::file::get_app_folder_path();
    }

    std::string display(const std::filesystem::path& p) {
        const std::u8string s = p.u8string();
        return std::string(reinterpret_cast<const char*>(s.c_str()), s.size());
    }
}

void dk64::migrate_legacy_config() {
    namespace fs = std::filesystem;
    std::error_code ec;

    const fs::path legacy_dir = folder_for(dk64::legacy_program_id);
    const fs::path current_dir = folder_for(dk64::program_id);

    // folder_for() sets the program id as a side effect. Set it explicitly
    // rather than relying on the order of the two calls above.
    recompui::programconfig::set_program_id(dk64::program_id);

    if (legacy_dir.empty() || current_dir.empty()) {
        return;
    }

    // With portable.txt or APP_FOLDER_PATH the resolved path contains no program
    // id at all, so both resolve to the same directory and there is nothing to
    // do. Copying a directory onto itself would not be harmless.
    if (legacy_dir == current_dir) {
        return;
    }

    // Never touch an existing configuration. This is an import for people
    // upgrading, not a sync.
    if (fs::exists(current_dir, ec)) {
        return;
    }

    if (!fs::is_directory(legacy_dir, ec)) {
        return;
    }

    fs::create_directories(current_dir.parent_path(), ec);
    ec.clear();

    fs::copy(legacy_dir, current_dir, fs::copy_options::recursive, ec);
    if (ec) {
        fprintf(stderr, "Could not import previous settings from %s: %s\n",
                display(legacy_dir).c_str(), ec.message().c_str());
        // A partial copy would look like an existing configuration on the next
        // launch and stop this from ever running again, so remove it and let
        // the next start try afresh.
        std::error_code cleanup_ec;
        fs::remove_all(current_dir, cleanup_ec);
        return;
    }

    printf("Imported settings and saves from %s to %s\n",
           display(legacy_dir).c_str(), display(current_dir).c_str());
    // stdout is block buffered when redirected, and this runs long before the
    // program reaches a clean exit. Without this the one notice that anything
    // was imported is lost whenever the process is killed or crashes.
    fflush(stdout);
}
