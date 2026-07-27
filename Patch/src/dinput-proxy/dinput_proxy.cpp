#define WIN32_LEAN_AND_MEAN
#define DIRECTINPUT_VERSION 0x0300

#include <windows.h>
#include <dinput.h>
#include <mmsystem.h>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

#include <M1937SDK/M1937SDK.hpp>

namespace {

using DirectInputCreateAProc = HRESULT(WINAPI *)(
    HINSTANCE, DWORD, LPDIRECTINPUTA *, LPUNKNOWN);

HMODULE g_real_dinput = nullptr;
DirectInputCreateAProc g_real_create = nullptr;
unsigned char *g_executable_base = nullptr;
HWND g_game_window = nullptr;
bool g_timer_period_active = false;
DWORD g_probe_mission_started_at = 0;
thread_local bool g_pumping_messages = false;
volatile LONG g_last_message_pump_tick = 0;
void *g_safe_blit_trampoline = nullptr;
void *g_menu_poll_trampoline = nullptr;
volatile LONG g_auto_start_consumed = 0;
DWORD g_probe_last_advance_at = 0;
wchar_t g_mod_log[MAX_PATH]{};

struct DiagnosticEntry {
    char event[48]{};
    char status[24]{};
    char detail[96]{};
};

DiagnosticEntry g_diagnostics[64]{};
volatile LONG g_diagnostic_count = 0;

struct ModConfig {
    bool enabled = true;
    bool disable_ime = true;
    bool high_resolution_timer = true;
    int difficulty = 1;
    int ai_level = 2;
    int hearing_radius = 0;
    int alert_radius = 0;
    bool expanded_viewport = false;
    bool preserve_legacy_ui = true;
    int viewport_width = 0;
    int viewport_height = 0;
    int message_pump_interval_ms = 8;
    int message_pump_budget = 4;
    bool system_cursor_mapping = true;
    bool auto_start = false;
    int start_level = 0;
    bool diagnostics = true;
};

ModConfig g_mod_config;
wchar_t g_rungame_ini[MAX_PATH]{};

using ImmDisableIMEProc = BOOL(WINAPI *)(DWORD);
using ImmAssociateContextExProc = BOOL(WINAPI *)(HWND, HANDLE, DWORD);
using SetProcessDpiAwarenessContextProc = BOOL(WINAPI *)(HANDLE);

int ClampSetting(int value, int minimum, int maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

void RecordDiagnostic(
    const char *event, const char *status, const char *detail = "") {
    const LONG index = InterlockedIncrement(&g_diagnostic_count) - 1;
    if (index < 0 ||
        index >= static_cast<LONG>(
            sizeof(g_diagnostics) / sizeof(g_diagnostics[0]))) {
        return;
    }
    lstrcpynA(g_diagnostics[index].event, event,
        static_cast<int>(sizeof(g_diagnostics[index].event)));
    lstrcpynA(g_diagnostics[index].status, status,
        static_cast<int>(sizeof(g_diagnostics[index].status)));
    lstrcpynA(g_diagnostics[index].detail, detail,
        static_cast<int>(sizeof(g_diagnostics[index].detail)));
}

const char *CompatibilityName(
    m1937::sdk::BuildCompatibility compatibility) {
    using Compatibility = m1937::sdk::BuildCompatibility;
    switch (compatibility) {
    case Compatibility::supported:
        return "supported";
    case Compatibility::null_module:
        return "null_module";
    case Compatibility::invalid_dos_header:
        return "invalid_dos_header";
    case Compatibility::invalid_nt_header:
        return "invalid_nt_header";
    case Compatibility::wrong_architecture:
        return "wrong_architecture";
    case Compatibility::wrong_image_base:
        return "wrong_image_base";
    case Compatibility::wrong_image_size:
        return "wrong_image_size";
    case Compatibility::wrong_timestamp:
        return "wrong_timestamp";
    case Compatibility::signature_mismatch:
        return "signature_mismatch";
    }
    return "unknown";
}

void FlushDiagnostics() {
    if (!g_mod_config.diagnostics || !g_mod_log[0]) {
        return;
    }
    const LONG count = InterlockedExchange(&g_diagnostic_count, 0);
    if (count <= 0) {
        return;
    }
    HANDLE file = CreateFileW(
        g_mod_log, FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    SYSTEMTIME time{};
    GetLocalTime(&time);
    const LONG limit = count < static_cast<LONG>(
        sizeof(g_diagnostics) / sizeof(g_diagnostics[0]))
        ? count
        : static_cast<LONG>(
            sizeof(g_diagnostics) / sizeof(g_diagnostics[0]));
    for (LONG index = 0; index < limit; ++index) {
        char line[384]{};
        const int length = snprintf(
            line, sizeof(line),
            "{\"time\":\"%04u-%02u-%02uT%02u:%02u:%02u.%03u\","
            "\"pid\":%lu,\"event\":\"%s\",\"status\":\"%s\","
            "\"detail\":\"%s\"}\r\n",
            time.wYear, time.wMonth, time.wDay,
            time.wHour, time.wMinute, time.wSecond, time.wMilliseconds,
            GetCurrentProcessId(),
            g_diagnostics[index].event,
            g_diagnostics[index].status,
            g_diagnostics[index].detail);
        if (length <= 0) {
            continue;
        }
        DWORD written = 0;
        WriteFile(
            file, line,
            static_cast<DWORD>(
                length < static_cast<int>(sizeof(line))
                    ? length
                    : sizeof(line) - 1),
            &written, nullptr);
    }
    CloseHandle(file);
}

void LoadModConfig() {
    wchar_t executable[MAX_PATH]{};
    const DWORD length =
        GetModuleFileNameW(nullptr, executable, static_cast<DWORD>(MAX_PATH));
    if (length == 0 || length >= MAX_PATH) {
        return;
    }
    wchar_t *separator = wcsrchr(executable, L'\\');
    if (!separator) {
        return;
    }
    *(separator + 1) = L'\0';
    lstrcpynW(g_mod_log, executable, MAX_PATH);
    lstrcatW(g_mod_log, L"M1937Mod.log");
    lstrcpynW(g_rungame_ini, executable, MAX_PATH);
    lstrcatW(g_rungame_ini, L"rungame.ini");

    auto read = [](const wchar_t *key, int fallback) {
        return static_cast<int>(GetPrivateProfileIntW(
            L"mod", key, fallback, g_rungame_ini));
    };
    g_mod_config.enabled = read(L"Enabled", 1) != 0;
    g_mod_config.disable_ime = read(L"DisableIME", 1) != 0;
    g_mod_config.high_resolution_timer = read(L"HighResolutionTimer", 1) != 0;
    g_mod_config.difficulty = ClampSetting(read(L"Difficulty", 1), 0, 3);
    g_mod_config.ai_level = ClampSetting(read(L"AILevel", 2), 0, 3);
    g_mod_config.hearing_radius =
        ClampSetting(read(L"HearingRadius", 0), 0, 2048);
    g_mod_config.alert_radius =
        ClampSetting(read(L"AlertRadius", 0), 0, 4096);
    g_mod_config.expanded_viewport = read(L"ExpandedViewport", 0) != 0;
    g_mod_config.preserve_legacy_ui = read(L"PreserveLegacyUI", 1) != 0;
    g_mod_config.viewport_width =
        ClampSetting(read(L"ViewportWidth", 0), 0, 3840);
    g_mod_config.viewport_height =
        ClampSetting(read(L"ViewportHeight", 0), 0, 2160);
    g_mod_config.message_pump_interval_ms =
        ClampSetting(read(L"MessagePumpIntervalMs", 8), 4, 50);
    g_mod_config.message_pump_budget =
        ClampSetting(read(L"MessagePumpBudget", 4), 1, 8);
    g_mod_config.system_cursor_mapping =
        read(L"SystemCursorMapping", 1) != 0;
    g_mod_config.auto_start = read(L"AutoStart", 0) != 0;
    g_mod_config.start_level = ClampSetting(
        read(L"StartLevel", 0), 0,
        static_cast<int>(m1937::sdk::mission_route_count));
    g_mod_config.diagnostics = read(L"Diagnostics", 1) != 0;
    RecordDiagnostic(
        "configuration", g_mod_config.enabled ? "enabled" : "disabled",
        g_mod_config.diagnostics ? "diagnostics_on" : "diagnostics_off");
}

void EnableModernDpiAwareness() {
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32) {
        return;
    }

    const auto set_context =
        reinterpret_cast<SetProcessDpiAwarenessContextProc>(
            GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
    if (set_context) {
        // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 is ((HANDLE)-4).
        if (set_context(reinterpret_cast<HANDLE>(-4))) {
            return;
        }
    }

    using SetProcessDPIAwareProc = BOOL(WINAPI *)();
    const auto set_legacy = reinterpret_cast<SetProcessDPIAwareProc>(
        GetProcAddress(user32, "SetProcessDPIAware"));
    if (set_legacy) {
        set_legacy();
    }
}

void DisableInputMethodForProcess() {
    HMODULE imm32 = LoadLibraryW(L"imm32.dll");
    if (!imm32) {
        return;
    }

    const auto disable_ime = reinterpret_cast<ImmDisableIMEProc>(
        GetProcAddress(imm32, "ImmDisableIME"));
    if (disable_ime) {
        disable_ime(static_cast<DWORD>(-1));
    }
    FreeLibrary(imm32);
}

void DisableInputMethodForWindow(HWND window) {
    if (!window) {
        return;
    }

    HMODULE imm32 = LoadLibraryW(L"imm32.dll");
    if (!imm32) {
        return;
    }

    const auto associate = reinterpret_cast<ImmAssociateContextExProc>(
        GetProcAddress(imm32, "ImmAssociateContextEx"));
    if (associate) {
        associate(window, nullptr, 0);
    }
    FreeLibrary(imm32);
}

void ProtectGameWindowInput(HWND window) {
    if (!window) {
        return;
    }
    if (!g_mod_config.enabled) {
        return;
    }
    if (g_mod_config.enabled && g_mod_config.disable_ime) {
        DisableInputMethodForWindow(window);
    }
}

void BeginHighResolutionTimer() {
    if (!g_timer_period_active && timeBeginPeriod(1) == TIMERR_NOERROR) {
        g_timer_period_active = true;
    }
}

int RequestedStartLevel() {
    char value[16]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_START_LEVEL", value, static_cast<DWORD>(sizeof(value)));
    if (length == 0 || length >= sizeof(value)) {
        return g_mod_config.start_level;
    }

    char *end = nullptr;
    const long level = strtol(value, &end, 10);
    if (end == value || *end != '\0' ||
        !m1937::sdk::find_mission_route(static_cast<int>(level))) {
        return 0;
    }
    return static_cast<int>(level);
}

bool IsAutomatedProbeEnabled() {
    char value[8]{};
    return GetEnvironmentVariableA(
               "M1937_AUTOTEST", value, static_cast<DWORD>(sizeof(value))) > 0 &&
        strcmp(value, "1") == 0;
}

bool IsAutomaticMissionStartEnabled() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_AUTO_START", value, static_cast<DWORD>(sizeof(value)));
    if (length > 0 && length < sizeof(value)) {
        return strcmp(value, "1") == 0;
    }
    return g_mod_config.auto_start;
}

bool IsAutomatedLaunchEnabled() {
    return IsAutomatedProbeEnabled() || IsAutomaticMissionStartEnabled();
}

bool UseEnhancedEnemyAI() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_AI_ORIGINAL", value, static_cast<DWORD>(sizeof(value)));
    if (length > 0 && length < sizeof(value)) {
        return strcmp(value, "1") != 0;
    }
    return g_mod_config.ai_level > 0;
}

int ConfiguredHearingRadius() {
    if (g_mod_config.hearing_radius > 0) {
        return g_mod_config.hearing_radius;
    }
    static const int ai_base[] = {128, 160, 192, 224};
    static const int difficulty_adjustment[] = {-32, 0, 32, 64};
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return ClampSetting(
        ai_base[ClampSetting(ai, 0, 3)] +
            difficulty_adjustment[g_mod_config.difficulty],
        64, 2048);
}

int ConfiguredAlertRadius() {
    if (g_mod_config.alert_radius > 0) {
        return g_mod_config.alert_radius;
    }
    static const int ai_base[] = {640, 720, 800, 960};
    static const int difficulty_adjustment[] = {-160, 0, 160, 320};
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return ClampSetting(
        ai_base[ClampSetting(ai, 0, 3)] +
            difficulty_adjustment[g_mod_config.difficulty],
        320, 4096);
}

bool PatchExecutableBytes(
    unsigned char *address, const unsigned char *expected,
    const unsigned char *replacement, size_t size) {
    return m1937::sdk::patch::bytes(
        address, expected, replacement, size);
}

bool PatchExecutableJump(
    unsigned char *address, const unsigned char *expected, size_t size,
    const void *destination) {
    return m1937::sdk::patch::relative_jump(
        address, expected, size, destination);
}

using OriginalBlitProc = int(__thiscall *)(
    void *, int, int, void *, int, int);

int __fastcall SafeBlit(
    void *surface, void *, int x, int y, void *source, int flags, int clip) {
    // Several original UI code paths deliberately leave an optional artwork
    // surface empty. Legacy widths never expose all of them, but a wider
    // viewport does. sub_40EE30 assumes ECX is non-null and crashes before it
    // can inspect the source/clip arguments.
    if (!surface || !g_safe_blit_trampoline) {
        return 0;
    }
    return reinterpret_cast<OriginalBlitProc>(g_safe_blit_trampoline)(
        surface, x, y, source, flags, clip);
}

bool InstallSafeBlitGuard(unsigned char *base) {
    static const unsigned char expected[] = {
        0x83, 0xEC, 0x2C, 0x53, 0x55, 0x56};
    auto *entry = base + m1937::sdk::rva::safe_blit;
    if (memcmp(entry, expected, sizeof(expected)) != 0) {
        return false;
    }

    constexpr size_t trampoline_size = sizeof(expected) + 5;
    auto *trampoline = static_cast<unsigned char *>(VirtualAlloc(
        nullptr, trampoline_size, MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE));
    if (!trampoline) {
        return false;
    }
    memcpy(trampoline, expected, sizeof(expected));
    trampoline[sizeof(expected)] = 0xE9;
    const auto resume_from =
        reinterpret_cast<intptr_t>(trampoline + trampoline_size);
    const auto resume_to =
        reinterpret_cast<intptr_t>(entry + sizeof(expected));
    const intptr_t relative = resume_to - resume_from;
    if (relative < INT32_MIN || relative > INT32_MAX) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    const int32_t displacement = static_cast<int32_t>(relative);
    memcpy(
        trampoline + sizeof(expected) + 1, &displacement,
        sizeof(displacement));
    FlushInstructionCache(
        GetCurrentProcess(), trampoline, trampoline_size);

    g_safe_blit_trampoline = trampoline;
    if (!PatchExecutableJump(
            entry, expected, sizeof(expected),
            reinterpret_cast<const void *>(&SafeBlit))) {
        g_safe_blit_trampoline = nullptr;
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    return true;
}

using OriginalMenuPollProc = int(__thiscall *)(void *, int, int);

int __fastcall AutoStartMenuPoll(
    void *menu, void *, int animation_state, int flags) {
    if (IsAutomatedLaunchEnabled() && g_executable_base &&
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::current_mission) == 0 &&
        InterlockedCompareExchange(&g_auto_start_consumed, 1, 0) == 0) {
        // Button identifier 1 is the original Start Game entry. Returning it
        // here follows the exact normal menu path instead of fabricating a
        // mission state or relying on physical mouse coordinates.
        if (IsAutomatedProbeEnabled()) {
            // sub_4031C0 enters its synchronous briefing loop before the
            // regular input poll can run again. Prime the original briefing
            // acknowledgement for non-interactive validation only.
            *reinterpret_cast<unsigned char *>(
                g_executable_base +
                m1937::sdk::rva::briefing_advance) = 1;
        }
        return 1;
    }
    if (!g_menu_poll_trampoline) {
        return 0;
    }
    return reinterpret_cast<OriginalMenuPollProc>(g_menu_poll_trampoline)(
        menu, animation_state, flags);
}

bool InstallAutoStartMenuHook(unsigned char *base) {
    static const unsigned char expected[] = {
        0x8B, 0x44, 0x24, 0x04, 0x53, 0x55};
    auto *entry = base + m1937::sdk::rva::menu_poll;
    if (memcmp(entry, expected, sizeof(expected)) != 0) {
        return false;
    }

    constexpr size_t trampoline_size = sizeof(expected) + 5;
    auto *trampoline = static_cast<unsigned char *>(VirtualAlloc(
        nullptr, trampoline_size, MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE));
    if (!trampoline) {
        return false;
    }
    memcpy(trampoline, expected, sizeof(expected));
    trampoline[sizeof(expected)] = 0xE9;
    const auto resume_from =
        reinterpret_cast<intptr_t>(trampoline + trampoline_size);
    const auto resume_to =
        reinterpret_cast<intptr_t>(entry + sizeof(expected));
    const intptr_t relative = resume_to - resume_from;
    if (relative < INT32_MIN || relative > INT32_MAX) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    const int32_t displacement = static_cast<int32_t>(relative);
    memcpy(
        trampoline + sizeof(expected) + 1, &displacement,
        sizeof(displacement));
    FlushInstructionCache(
        GetCurrentProcess(), trampoline, trampoline_size);

    g_menu_poll_trampoline = trampoline;
    if (!PatchExecutableJump(
            entry, expected, sizeof(expected),
            reinterpret_cast<const void *>(&AutoStartMenuPoll))) {
        g_menu_poll_trampoline = nullptr;
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    return true;
}

bool ReadExpandedViewport(int *width, int *height) {
    if (!width || !height) {
        return false;
    }

    char unsafe_enabled[8]{};
    const DWORD unsafe_length = GetEnvironmentVariableA(
        "M1937_UNSAFE_EXPANDED_VIEWPORT", unsafe_enabled,
        static_cast<DWORD>(sizeof(unsafe_enabled)));
    const bool explicitly_unsafe = unsafe_length > 0 &&
        unsafe_length < sizeof(unsafe_enabled) &&
        strcmp(unsafe_enabled, "1") == 0;
    if (g_mod_config.preserve_legacy_ui && !explicitly_unsafe) {
        // The original interface owns only 640x480, 800x600 and 1024x768
        // artwork/surfaces. Replacing the engine's logical size with a modern
        // desktop size hides the bottom toolbar and leaves help/minimap
        // surfaces null. Modern output scaling remains handled by cnc-ddraw.
        return false;
    }

    char enabled[8]{};
    const DWORD environment_enabled = GetEnvironmentVariableA(
            "M1937_EXPANDED_VIEWPORT", enabled,
            static_cast<DWORD>(sizeof(enabled)));
    const bool expanded = environment_enabled > 0 &&
            environment_enabled < sizeof(enabled)
        ? strcmp(enabled, "1") == 0
        : g_mod_config.expanded_viewport;
    if (!expanded) {
        return false;
    }

    int requested_width = g_mod_config.viewport_width > 0
        ? g_mod_config.viewport_width
        : GetSystemMetrics(SM_CXSCREEN);
    int requested_height = g_mod_config.viewport_height > 0
        ? g_mod_config.viewport_height
        : GetSystemMetrics(SM_CYSCREEN);
    char value[16]{};
    if (GetEnvironmentVariableA(
            "M1937_VIEWPORT_WIDTH", value,
            static_cast<DWORD>(sizeof(value))) > 0) {
        requested_width = static_cast<int>(strtol(value, nullptr, 10));
    }
    memset(value, 0, sizeof(value));
    if (GetEnvironmentVariableA(
            "M1937_VIEWPORT_HEIGHT", value,
            static_cast<DWORD>(sizeof(value))) > 0) {
        requested_height = static_cast<int>(strtol(value, nullptr, 10));
    }

    // The renderer uses 16-bit surfaces. Keep the expanded viewport within
    // well-tested modern desktop sizes while allowing 16:9 and ultrawide
    // layouts that the original three-item settings menu could not express.
    if (requested_width < 800 || requested_width > 3840 ||
        requested_height < 600 || requested_height > 2160) {
        return false;
    }
    *width = requested_width & ~1;
    *height = requested_height & ~1;
    return true;
}

bool PatchImmediate32(
    unsigned char *base, size_t operand_offset, int expected, int replacement) {
    return m1937::sdk::patch::immediate_i32(
        m1937::sdk::ModuleView(
            reinterpret_cast<HMODULE>(base)),
        operand_offset,
        expected,
        replacement);
}

struct ImmediatePatch {
    size_t offset;
    int expected;
    int replacement;
};

bool PatchImmediateTransaction(
    unsigned char *base,
    const ImmediatePatch *patches,
    size_t count) {
    if (!base || !patches || count == 0) {
        return false;
    }
    for (size_t index = 0; index < count; ++index) {
        if (memcmp(
                base + patches[index].offset,
                &patches[index].expected,
                sizeof(patches[index].expected)) != 0) {
            return false;
        }
    }
    for (size_t index = 0; index < count; ++index) {
        if (PatchImmediate32(
                base,
                patches[index].offset,
                patches[index].expected,
                patches[index].replacement)) {
            continue;
        }
        while (index > 0) {
            --index;
            PatchImmediate32(
                base,
                patches[index].offset,
                patches[index].replacement,
                patches[index].expected);
        }
        return false;
    }
    return true;
}

bool ApplyExpandedViewportPatches(unsigned char *base) {
    int width = 0;
    int height = 0;
    if (!ReadExpandedViewport(&width, &height)) {
        return false;
    }

    // Startup selects one of 640x480, 800x600 and 1024x768 from M1937.cfg.
    // Replace all three assignments before the central surface-creation call,
    // so its existing code continues to pass the global width and height.
    struct ResolutionOperand {
        size_t offset;
        int expected;
        bool is_width;
    };
    static const ResolutionOperand startup_operands[] = {
        {m1937::sdk::rva::startup_width_1024, 1024, true},
        {m1937::sdk::rva::startup_height_768, 768, false},
        {m1937::sdk::rva::startup_width_800, 800, true},
        {m1937::sdk::rva::startup_height_600, 600, false},
        {m1937::sdk::rva::startup_width_640, 640, true},
        {m1937::sdk::rva::startup_height_480, 480, false},
    };
    bool success = true;
    for (const auto &operand : startup_operands) {
        const bool patched = PatchImmediate32(
            base, operand.offset, operand.expected,
            operand.is_width ? width : height);
        success = patched && success;
    }

    // The original settings menu can recreate graphics surfaces at runtime.
    // Keep that entry point operational: every legacy resolution choice maps
    // back to the expanded viewport while this launch profile is active.
    static const ResolutionOperand settings_operands[] = {
        {m1937::sdk::rva::settings_width_640_a, 640, true},
        {m1937::sdk::rva::settings_height_480_a, 480, false},
        {m1937::sdk::rva::settings_height_480_b, 480, false},
        {m1937::sdk::rva::settings_width_640_b, 640, true},
        {m1937::sdk::rva::settings_width_800_a, 800, true},
        {m1937::sdk::rva::settings_height_600_a, 600, false},
        {m1937::sdk::rva::settings_height_600_b, 600, false},
        {m1937::sdk::rva::settings_width_800_b, 800, true},
        {m1937::sdk::rva::settings_width_1024_a, 1024, true},
        {m1937::sdk::rva::settings_height_768_a, 768, false},
        {m1937::sdk::rva::settings_height_768_b, 768, false},
        {m1937::sdk::rva::settings_width_1024_b, 1024, true},
    };
    for (const auto &operand : settings_operands) {
        const bool patched = PatchImmediate32(
            base, operand.offset, operand.expected,
            operand.is_width ? width : height);
        success = patched && success;
    }

    // UI artwork is available only in 640, 800 and 1024 variants. The
    // original branch leaves the startup image pointer null for any other
    // width, then sub_4031C0 dereferences it in sub_40EE30. Treat every
    // non-640/non-800 width as the 1024 artwork layout while keeping the
    // renderer globals at the requested desktop-sized viewport.
    static const unsigned char intro_1024_guard[] = {
        0x0F, 0x85, 0xC0, 0x00, 0x00, 0x00};
    static const unsigned char six_nops[] = {
        0x90, 0x90, 0x90, 0x90, 0x90, 0x90};
    success = PatchExecutableBytes(
        base + m1937::sdk::rva::intro_1024_layout_guard,
        intro_1024_guard, six_nops,
        sizeof(six_nops)) && success;

    // The matching menu-layout branch supplies the 1024 artwork offset
    // (192,144). Without it an expanded viewport is usable but the old menu
    // panel is no longer centred relative to its 1024 reference layout.
    static const unsigned char layout_1024_guard[] = {0x75, 0x2C};
    static const unsigned char two_nops[] = {0x90, 0x90};
    success = PatchExecutableBytes(
        base + m1937::sdk::rva::menu_1024_layout_guard,
        layout_1024_guard, two_nops,
        sizeof(two_nops)) && success;
    return success;
}

void ApplyLegacyExecutablePatches() {
    const auto module = m1937::sdk::ModuleView::current_process();
    const auto compatibility = module.compatibility();
    RecordDiagnostic(
        "executable_identity",
        compatibility == m1937::sdk::BuildCompatibility::supported
            ? "accepted"
            : "rejected",
        CompatibilityName(compatibility));
    if (compatibility != m1937::sdk::BuildCompatibility::supported) {
        return;
    }
    auto *base = reinterpret_cast<unsigned char *>(module.base());
    g_executable_base = base;
    if (g_mod_config.enabled) {
        int expanded_width = 0;
        int expanded_height = 0;
        if (ReadExpandedViewport(&expanded_width, &expanded_height)) {
            const bool safe_blit = InstallSafeBlitGuard(base);
            const bool viewport =
                safe_blit && ApplyExpandedViewportPatches(base);
            RecordDiagnostic(
                "expanded_viewport", viewport ? "enabled" : "rejected",
                safe_blit ? "patch_group" : "safe_blit_signature");
        }
    }
    if (IsAutomatedLaunchEnabled()) {
        RecordDiagnostic(
            "automated_start_hook",
            InstallAutoStartMenuHook(base) ? "enabled" : "rejected",
            "menu_poll_signature");
    }

    // The green release reports a false resource-library error even though
    // both GFL archives have already opened successfully.
    static const unsigned char warning_expected[] = {0x74, 0x0C};
    static const unsigned char warning_patch[] = {0xEB, 0x0C};
    RecordDiagnostic(
        "false_resource_warning",
        PatchExecutableBytes(
        base + m1937::sdk::rva::false_resource_warning_branch,
        warning_expected, warning_patch,
        sizeof(warning_patch)) ? "enabled" : "rejected",
        "signature_guard");

    // Skip only the two startup movie enqueue calls. Mission movies and all
    // gameplay resources remain untouched.
    static const unsigned char movies_expected[] = {
        0x68, 0x8C, 0xF7, 0x4C, 0x00, 0x53, 0x53, 0x8B, 0xCE, 0xE8,
        0x7E, 0x9B, 0xFF, 0xFF, 0x68, 0x7C, 0xF7, 0x4C, 0x00, 0x6A,
        0x64, 0x53, 0x8B, 0xCE, 0xE8, 0x6F, 0x9B, 0xFF, 0xFF};
    unsigned char movies_nops[sizeof(movies_expected)];
    memset(movies_nops, 0x90, sizeof(movies_nops));
    RecordDiagnostic(
        "startup_movies",
        PatchExecutableBytes(
        base + m1937::sdk::rva::startup_movie_enqueue,
        movies_expected, movies_nops,
        sizeof(movies_nops)) ? "disabled" : "original",
        "signature_guard");

    // The original "New Game" thunk always writes mission number 1 to
    // The selector-to-engine mapping and optional fixed-length filename
    // redirect come from SDK/mission-routes.json. A normal launch keeps the
    // original first-mission behavior. Validation is completed before any
    // route byte is changed, and a failed second write rolls the first back.
    const int requested_level = RequestedStartLevel();
    const auto *route = m1937::sdk::find_mission_route(requested_level);
    if (route) {
        const size_t vwf_size = strlen(route->vwf_name) + 1;
        auto *level_address =
            base + m1937::sdk::rva::new_game_level_immediate;
        auto *redirect_address = route->redirect_rva == 0
            ? nullptr
            : base + route->redirect_rva;
        const int original_level = 1;
        const bool level_matches =
            memcmp(level_address, &original_level, sizeof(original_level)) == 0;
        const bool redirect_matches =
            !redirect_address ||
            (strlen(route->redirect_expected) + 1 == vwf_size &&
             memcmp(
                 redirect_address, route->redirect_expected, vwf_size) == 0);
        const bool file_exists =
            !route->requires_file ||
            GetFileAttributesA(route->vwf_name) != INVALID_FILE_ATTRIBUTES;

        if (level_matches && redirect_matches && file_exists) {
            const bool redirected =
                !redirect_address ||
                PatchExecutableBytes(
                    redirect_address,
                    reinterpret_cast<const unsigned char *>(
                        route->redirect_expected),
                    reinterpret_cast<const unsigned char *>(route->vwf_name),
                    vwf_size);
            const bool level_patched =
                redirected &&
                PatchImmediate32(
                    base,
                    m1937::sdk::rva::new_game_level_immediate,
                    original_level,
                    route->engine_mission);
            if (!level_patched && redirect_address && redirected) {
                PatchExecutableBytes(
                    redirect_address,
                    reinterpret_cast<const unsigned char *>(route->vwf_name),
                    reinterpret_cast<const unsigned char *>(
                        route->redirect_expected),
                    vwf_size);
            }
            RecordDiagnostic(
                "mission_route",
                level_patched ? "enabled" : "rolled_back",
                route->id);
        } else {
            RecordDiagnostic(
                "mission_route", "original",
                !file_exists ? "missing_vwf" : "signature_guard");
        }
    }

    if (g_mod_config.enabled) {
        // The original unobstructed close-hearing check is 128 world units.
        // Keep its original no-line-of-sight semantics and configure only the
        // comparison operand.
        // Four combat paths broadcast the target's last-known position to
        // nearby allies. The original alert propagation routine still decides
        // eligibility and pathing.
        const int hearing = ConfiguredHearingRadius();
        const int alert = ConfiguredAlertRadius();
        const ImmediatePatch ai_patch_group[] = {
            {m1937::sdk::rva::close_hearing_radius_immediate, 128, hearing},
            {m1937::sdk::rva::alert_radius_operand_1, 640, alert},
            {m1937::sdk::rva::alert_radius_operand_2, 640, alert},
            {m1937::sdk::rva::alert_radius_operand_3, 640, alert},
            {m1937::sdk::rva::alert_radius_operand_4, 640, alert},
        };
        const bool ai_patches = PatchImmediateTransaction(
            base, ai_patch_group,
            sizeof(ai_patch_group) / sizeof(ai_patch_group[0]));
        RecordDiagnostic(
            "enemy_perception",
            ai_patches ? "enabled" : "original",
            "hearing_and_alert_operands");
    }
}

void PumpWindowMessages() {
    // Dispatching a window message can synchronously ask DirectInput for
    // another device state. Without a guard that re-enters this pump and can
    // eventually overflow the 32-bit game's stack on a newly copied path.
    if (g_pumping_messages) {
        return;
    }
    const DWORD now_tick = GetTickCount();
    const DWORD last_tick =
        static_cast<DWORD>(InterlockedCompareExchange(
            &g_last_message_pump_tick, 0, 0));
    if (now_tick - last_tick <
        static_cast<DWORD>(g_mod_config.message_pump_interval_ms)) {
        return;
    }
    InterlockedExchange(
        &g_last_message_pump_tick, static_cast<LONG>(now_tick));
    g_pumping_messages = true;

    // Automated validation must get beyond the mission briefing without
    // activating the window or moving the user's physical mouse. This flag is
    // the same acknowledgement the original briefing click path sets.
    if (IsAutomatedProbeEnabled() && g_executable_base) {
        const int mission =
            *reinterpret_cast<int *>(
                g_executable_base +
                m1937::sdk::rva::current_mission);
        if (mission >= 1 && mission <= 12) {
            if (g_probe_mission_started_at == 0) {
                g_probe_mission_started_at = GetTickCount();
            } else if (
                GetTickCount() - g_probe_mission_started_at >= 1500 &&
                GetTickCount() - g_probe_last_advance_at >= 2000) {
                *reinterpret_cast<unsigned char *>(
                    g_executable_base +
                    m1937::sdk::rva::briefing_advance) = 1;
                g_probe_last_advance_at = GetTickCount();
            }
        }
    }

    // Do not consume keyboard or mouse messages here. The original loop must
    // see them in order for F1, M and the other game hotkeys to toggle their
    // UI. Only service paint/timer/close traffic during synchronous loading.
    static const UINT background_messages[] = {
        WM_PAINT, WM_TIMER, WM_NCPAINT, WM_ERASEBKGND, WM_CLOSE};
    MSG message{};
    int dispatched = 0;
    while (dispatched < g_mod_config.message_pump_budget) {
        bool found = false;
        for (const UINT message_id : background_messages) {
            if (PeekMessageA(
                    &message, nullptr, message_id, message_id, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageA(&message);
                ++dispatched;
                found = true;
                break;
            }
        }
        if (!found) {
            break;
        }
    }
    g_pumping_messages = false;
}

bool LoadRealDInput() {
    if (g_real_create) {
        return true;
    }

    wchar_t system_dinput[MAX_PATH]{};
    const UINT system_length = GetSystemDirectoryW(system_dinput, MAX_PATH);
    if (system_length == 0 || system_length >= MAX_PATH - 13) {
        return false;
    }
    lstrcatW(system_dinput, L"\\dinput.dll");

    // A loaded module with the same basename can win over an absolute path
    // on legacy DLL-redirection configurations, recursively resolving this
    // proxy as the "real" dinput.dll. Copy the OS-matched 32-bit DLL to a
    // unique basename before loading it. CopyFile is subject to WOW64 file
    // redirection, which intentionally selects SysWOW64 for this 32-bit game.
    wchar_t real_copy[MAX_PATH]{};
    const DWORD executable_length =
        GetModuleFileNameW(nullptr, real_copy, MAX_PATH);
    if (executable_length == 0 || executable_length >= MAX_PATH) {
        return false;
    }
    wchar_t *separator = wcsrchr(real_copy, L'\\');
    if (!separator ||
        static_cast<size_t>(separator - real_copy) + 21 >= MAX_PATH) {
        return false;
    }
    *(separator + 1) = L'\0';
    lstrcatW(real_copy, L"dinput_system.dll");
    if (!CopyFileW(system_dinput, real_copy, FALSE)) {
        return false;
    }

    g_real_dinput = LoadLibraryW(real_copy);
    if (!g_real_dinput) {
        return false;
    }
    g_real_create = reinterpret_cast<DirectInputCreateAProc>(
        GetProcAddress(g_real_dinput, "DirectInputCreateA"));
    if (!g_real_create) {
        FreeLibrary(g_real_dinput);
        g_real_dinput = nullptr;
        return false;
    }
    return true;
}

int LogicalScreenWidth() {
    if (!g_executable_base) {
        return 1024;
    }
    const int width =
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::screen_width);
    return width >= 320 && width <= 4096 ? width : 1024;
}

int LogicalScreenHeight() {
    if (!g_executable_base) {
        return 768;
    }
    const int height =
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::screen_height);
    return height >= 240 && height <= 2160 ? height : 768;
}

bool IsGameWindowForeground() {
    if (!g_game_window) {
        return false;
    }
    const HWND foreground = GetForegroundWindow();
    return foreground &&
        GetAncestor(foreground, GA_ROOT) ==
            GetAncestor(g_game_window, GA_ROOT);
}

void MapSystemCursorToGameState(DWORD size, LPVOID data) {
    if (!g_mod_config.system_cursor_mapping || !g_game_window ||
        !g_executable_base || !data || size < sizeof(DIMOUSESTATE)) {
        return;
    }

    auto *mouse = static_cast<DIMOUSESTATE *>(data);
    if (!IsGameWindowForeground()) {
        mouse->lX = 0;
        mouse->lY = 0;
        mouse->lZ = 0;
        memset(mouse->rgbButtons, 0, sizeof(mouse->rgbButtons));
        return;
    }

    POINT cursor{};
    RECT client{};
    if (!GetCursorPos(&cursor) ||
        !ScreenToClient(g_game_window, &cursor) ||
        !GetClientRect(g_game_window, &client)) {
        mouse->lX = 0;
        mouse->lY = 0;
        return;
    }

    const int client_width = client.right - client.left;
    const int client_height = client.bottom - client.top;
    const int logical_width = LogicalScreenWidth();
    const int logical_height = LogicalScreenHeight();
    if (client_width <= 1 || client_height <= 1 ||
        logical_width <= 1 || logical_height <= 1) {
        mouse->lX = 0;
        mouse->lY = 0;
        return;
    }

    // cnc-ddraw preserves the original 4:3 aspect ratio. Map only the actual
    // rendered rectangle, excluding any pillarbox/letterbox area.
    int render_width = client_width;
    int render_height = MulDiv(client_width, logical_height, logical_width);
    int render_left = 0;
    int render_top = 0;
    if (render_height > client_height) {
        render_height = client_height;
        render_width = MulDiv(
            client_height, logical_width, logical_height);
        render_left = (client_width - render_width) / 2;
    } else {
        render_top = (client_height - render_height) / 2;
    }
    if (render_width <= 1 || render_height <= 1) {
        mouse->lX = 0;
        mouse->lY = 0;
        return;
    }

    const int render_x = ClampSetting(
        cursor.x - render_left, 0, render_width - 1);
    const int render_y = ClampSetting(
        cursor.y - render_top, 0, render_height - 1);
    const int target_x =
        MulDiv(render_x, logical_width - 1, render_width - 1);
    const int target_y =
        MulDiv(render_y, logical_height - 1, render_height - 1);
    const int current_x =
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::cursor_x);
    const int current_y =
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::cursor_y);

    // The original DirectInput 3 loop accumulates relative deltas. Limit a
    // single correction so focus changes cannot teleport the in-game cursor.
    mouse->lX = ClampSetting(target_x - current_x, -80, 80);
    mouse->lY = ClampSetting(target_y - current_y, -80, 80);
    // Preserve the real wheel and button state returned by DirectInput.
}

class DeviceProxy final : public IDirectInputDeviceA {
public:
    DeviceProxy(LPDIRECTINPUTDEVICEA real, bool is_mouse)
        : real_(real), is_mouse_(is_mouse) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, LPVOID *object) override {
        if (!object) {
            return E_POINTER;
        }
        if (IsEqualIID(riid, IID_IUnknown) ||
            IsEqualIID(riid, IID_IDirectInputDeviceA)) {
            *object = static_cast<IDirectInputDeviceA *>(this);
            AddRef();
            return S_OK;
        }
        return real_->QueryInterface(riid, object);
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return static_cast<ULONG>(InterlockedIncrement(&references_));
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining =
            static_cast<ULONG>(InterlockedDecrement(&references_));
        if (remaining == 0) {
            real_->Release();
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE GetCapabilities(LPDIDEVCAPS capabilities) override {
        return real_->GetCapabilities(capabilities);
    }
    HRESULT STDMETHODCALLTYPE EnumObjects(
        LPDIENUMDEVICEOBJECTSCALLBACKA callback, LPVOID context,
        DWORD flags) override {
        return real_->EnumObjects(callback, context, flags);
    }
    HRESULT STDMETHODCALLTYPE GetProperty(
        REFGUID property, LPDIPROPHEADER header) override {
        return real_->GetProperty(property, header);
    }
    HRESULT STDMETHODCALLTYPE SetProperty(
        REFGUID property, LPCDIPROPHEADER header) override {
        return real_->SetProperty(property, header);
    }
    HRESULT STDMETHODCALLTYPE Acquire() override {
        PumpWindowMessages();
        return real_->Acquire();
    }
    HRESULT STDMETHODCALLTYPE Unacquire() override {
        return real_->Unacquire();
    }
    HRESULT STDMETHODCALLTYPE GetDeviceState(DWORD size, LPVOID data) override {
        PumpWindowMessages();
        const HRESULT result = real_->GetDeviceState(size, data);
        if (SUCCEEDED(result) && is_mouse_) {
            MapSystemCursorToGameState(size, data);
        }
        return result;
    }
    HRESULT STDMETHODCALLTYPE GetDeviceData(
        DWORD object_size, LPDIDEVICEOBJECTDATA data, LPDWORD count,
        DWORD flags) override {
        PumpWindowMessages();
        return real_->GetDeviceData(object_size, data, count, flags);
    }
    HRESULT STDMETHODCALLTYPE SetDataFormat(LPCDIDATAFORMAT format) override {
        if (format && format->dwDataSize == sizeof(DIMOUSESTATE)) {
            is_mouse_ = true;
        }
        return real_->SetDataFormat(format);
    }
    HRESULT STDMETHODCALLTYPE SetEventNotification(HANDLE event) override {
        return real_->SetEventNotification(event);
    }
    HRESULT STDMETHODCALLTYPE SetCooperativeLevel(HWND window, DWORD flags) override {
        if (is_mouse_) {
            g_game_window = window;
        }
        ProtectGameWindowInput(window);
        const DWORD effective_flags =
            is_mouse_ && g_mod_config.system_cursor_mapping
            ? DISCL_BACKGROUND | DISCL_NONEXCLUSIVE
            : flags;
        return real_->SetCooperativeLevel(window, effective_flags);
    }
    HRESULT STDMETHODCALLTYPE GetObjectInfo(
        LPDIDEVICEOBJECTINSTANCEA info, DWORD object, DWORD how) override {
        return real_->GetObjectInfo(info, object, how);
    }
    HRESULT STDMETHODCALLTYPE GetDeviceInfo(LPDIDEVICEINSTANCEA info) override {
        return real_->GetDeviceInfo(info);
    }
    HRESULT STDMETHODCALLTYPE RunControlPanel(HWND owner, DWORD flags) override {
        return real_->RunControlPanel(owner, flags);
    }
    HRESULT STDMETHODCALLTYPE Initialize(
        HINSTANCE instance, DWORD version, REFGUID guid) override {
        return real_->Initialize(instance, version, guid);
    }

private:
    ~DeviceProxy() = default;
    LPDIRECTINPUTDEVICEA real_;
    bool is_mouse_;
    volatile LONG references_ = 1;
};

class DirectInputProxy final : public IDirectInputA {
public:
    explicit DirectInputProxy(LPDIRECTINPUTA real) : real_(real) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, LPVOID *object) override {
        if (!object) {
            return E_POINTER;
        }
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IDirectInputA)) {
            *object = static_cast<IDirectInputA *>(this);
            AddRef();
            return S_OK;
        }
        return real_->QueryInterface(riid, object);
    }

    ULONG STDMETHODCALLTYPE AddRef() override {
        return static_cast<ULONG>(InterlockedIncrement(&references_));
    }

    ULONG STDMETHODCALLTYPE Release() override {
        const ULONG remaining =
            static_cast<ULONG>(InterlockedDecrement(&references_));
        if (remaining == 0) {
            real_->Release();
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE CreateDevice(
        REFGUID guid, LPDIRECTINPUTDEVICEA *device, LPUNKNOWN outer) override {
        if (!device) {
            return E_POINTER;
        }
        *device = nullptr;

        LPDIRECTINPUTDEVICEA real_device = nullptr;
        const HRESULT result = real_->CreateDevice(guid, &real_device, outer);
        if (FAILED(result)) {
            return result;
        }

        auto *proxy = new (std::nothrow) DeviceProxy(
            real_device, IsEqualGUID(guid, GUID_SysMouse) != FALSE);
        if (!proxy) {
            real_device->Release();
            return E_OUTOFMEMORY;
        }
        *device = proxy;
        return result;
    }

    HRESULT STDMETHODCALLTYPE EnumDevices(
        DWORD type, LPDIENUMDEVICESCALLBACKA callback, LPVOID context,
        DWORD flags) override {
        return real_->EnumDevices(type, callback, context, flags);
    }
    HRESULT STDMETHODCALLTYPE GetDeviceStatus(REFGUID guid) override {
        return real_->GetDeviceStatus(guid);
    }
    HRESULT STDMETHODCALLTYPE RunControlPanel(HWND owner, DWORD flags) override {
        return real_->RunControlPanel(owner, flags);
    }
    HRESULT STDMETHODCALLTYPE Initialize(HINSTANCE instance, DWORD version) override {
        return real_->Initialize(instance, version);
    }

private:
    ~DirectInputProxy() = default;
    LPDIRECTINPUTA real_;
    volatile LONG references_ = 1;
};

}  // namespace

extern "C" HRESULT WINAPI ProxyDirectInputCreateA(
    HINSTANCE instance, DWORD version, LPDIRECTINPUTA *direct_input,
    LPUNKNOWN outer) {
    if (!direct_input) {
        return E_POINTER;
    }
    *direct_input = nullptr;
    EnableModernDpiAwareness();
    if (g_mod_config.enabled && g_mod_config.disable_ime) {
        DisableInputMethodForProcess();
    }
    if (g_mod_config.enabled && g_mod_config.high_resolution_timer) {
        BeginHighResolutionTimer();
    }
    if (!LoadRealDInput()) {
        RecordDiagnostic(
            "system_dinput", "failed", "system_library_resolution");
        FlushDiagnostics();
        return DIERR_NOTINITIALIZED;
    }

    LPDIRECTINPUTA real = nullptr;
    const HRESULT result = g_real_create(instance, version, &real, outer);
    if (FAILED(result)) {
        RecordDiagnostic(
            "direct_input_create", "failed", "original_api");
        FlushDiagnostics();
        return result;
    }

    auto *proxy = new (std::nothrow) DirectInputProxy(real);
    if (!proxy) {
        real->Release();
        return E_OUTOFMEMORY;
    }
    *direct_input = proxy;
    RecordDiagnostic(
        "direct_input_create", "ready", "proxy_active");
    FlushDiagnostics();
    return result;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        LoadModConfig();
        ApplyLegacyExecutablePatches();
    } else if (reason == DLL_PROCESS_DETACH && g_timer_period_active) {
        timeEndPeriod(1);
        g_timer_period_active = false;
    }
    return TRUE;
}
