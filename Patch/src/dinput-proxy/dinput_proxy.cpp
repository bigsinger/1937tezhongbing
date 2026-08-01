#define WIN32_LEAN_AND_MEAN
#define DIRECTINPUT_VERSION 0x0300

#include <windows.h>
#include <dinput.h>
#include <mmsystem.h>
#include <intrin.h>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <new>
#include <string>
#include <string_view>
#include <vector>

#include <M1937SDK/M1937SDK.hpp>

namespace {

using DirectInputCreateAProc = HRESULT(WINAPI *)(
    HINSTANCE, DWORD, LPDIRECTINPUTA *, LPUNKNOWN);

HMODULE g_real_dinput = nullptr;
HINSTANCE g_proxy_instance = nullptr;
DirectInputCreateAProc g_real_create = nullptr;
unsigned char *g_executable_base = nullptr;
HWND g_game_window = nullptr;
bool g_timer_period_active = false;
thread_local bool g_pumping_messages = false;
volatile LONG g_last_message_pump_tick = 0;
void *g_safe_blit_trampoline = nullptr;
void *g_menu_poll_trampoline = nullptr;
void *g_alert_propagation_trampoline = nullptr;
void *g_crt_rand_trampoline = nullptr;
volatile LONG g_auto_start_consumed = 0;
wchar_t g_mod_log[MAX_PATH]{};
wchar_t g_telemetry_log[MAX_PATH]{};
wchar_t g_real_dinput_copy[MAX_PATH]{};
volatile LONG g_replay_menu_command = 0;
unsigned char g_replay_keyboard[256]{};
DIMOUSESTATE g_replay_mouse{};
volatile LONG g_replay_message_count = 0;
volatile LONG g_replay_state_reads = 0;
volatile LONGLONG g_replay_input_qpc = 0;
volatile LONG g_replay_world_item_id = 0;
volatile LONG g_replay_world_item_x = 0;
volatile LONG g_replay_world_item_y = 0;
volatile LONG g_replay_world_item_spawn_pending = 0;
volatile LONG g_replay_inventory_seed_pending = 0;
volatile LONG g_replay_disguise_transition_pending = 0;
volatile LONG g_replay_weapon_selection_pending = 0;
volatile LONG g_replay_special_attention_commit_pending = 0;
WNDPROC g_original_replay_window_proc = nullptr;
HWND g_replay_subclass_window = nullptr;
volatile LONG g_extension_briefing_pending = 0;
volatile LONG g_extension_briefing_mouse_released = 0;
volatile LONG g_extension_briefing_keyboard_released = 0;
volatile LONG g_extension_resume_hotkey_armed = 0;
volatile LONG g_extension_resume_mouse_released = 0;
volatile LONG g_extension_resume_keyboard_released = 0;
volatile LONG g_extension_resume_accept_tick = 0;
volatile LONG g_extension_selection_hotkey_phase = 0;
volatile LONG g_extension_selection_hotkey_due_tick = 0;
volatile LONG g_extension_selection_hotkey_release_tick = 0;

constexpr UINT kWindowReplayMessage = WM_APP + 0x137;

enum WindowReplayCommand : WPARAM {
    replay_key_down = 1,
    replay_key_up = 2,
    replay_mouse_delta = 3,
    replay_mouse_button_down = 4,
    replay_mouse_button_up = 5,
    replay_menu_command = 6,
    replay_clear = 7,
    replay_ai_alert = 8,
    replay_camera_center = 9,
    replay_seed_world_item = 10,
    replay_spawn_world_item = 11,
    replay_seed_weapon_inventory = 12,
    replay_complete_guming_disguise = 13,
    replay_select_weapon_inventory_item = 14,
    replay_commit_special_attention = 15,
};

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
    bool telemetry = false;
    int telemetry_interval_ms = 1000;
    bool key_remapping = false;
    int max_reinforcements = 0;
    int search_points = 0;
    int search_timeout_ms = 0;
    int intercept_distance = 0;
    int ai_tick_interval_ms = 100;
    bool mission_sidecar = false;
    bool plugins = false;
    bool text_briefings = true;
};

ModConfig g_mod_config;
wchar_t g_rungame_ini[MAX_PATH]{};

struct KeyAlias {
    unsigned char source = 0;
    unsigned char target = 0;
};

KeyAlias g_key_aliases[16]{};
int g_key_alias_count = 0;

struct TelemetryCounters {
    volatile LONG pump_calls = 0;
    volatile LONG pump_messages = 0;
    volatile LONG pump_microseconds = 0;
    volatile LONG pump_max_microseconds = 0;
    volatile LONG input_state_calls = 0;
    volatile LONG input_state_microseconds = 0;
    volatile LONG input_state_max_microseconds = 0;
    volatile LONG input_data_calls = 0;
    volatile LONG input_data_microseconds = 0;
    volatile LONG input_data_max_microseconds = 0;
    volatile LONG replay_messages = 0;
    volatile LONG replay_reads = 0;
    volatile LONG replay_latency_samples = 0;
    volatile LONG replay_latency_microseconds = 0;
    volatile LONG replay_latency_max_microseconds = 0;
    volatile LONG player_ground_reroutes = 0;
    volatile LONG ai_ticks = 0;
    volatile LONG ai_tick_microseconds = 0;
    volatile LONG ai_tick_max_microseconds = 0;
    volatile LONG ai_alerts = 0;
    volatile LONG ai_reinforcements = 0;
    volatile LONG ai_searches_started = 0;
    volatile LONG ai_search_replans = 0;
    volatile LONG ai_intercepts = 0;
    volatile LONG ai_reaction_samples = 0;
    volatile LONG ai_reaction_total_ms = 0;
    volatile LONG ai_reaction_max_ms = 0;
    volatile LONG ai_search_completed = 0;
    volatile LONG ai_reacquisitions = 0;
    volatile LONG ai_escape_timeouts = 0;
};

TelemetryCounters g_telemetry{};
volatile LONG g_last_telemetry_tick = 0;
ULONGLONG g_last_telemetry_read_bytes = 0;
int g_last_telemetry_mission = -1;
int g_last_telemetry_camera_x = INT32_MIN;
int g_last_telemetry_camera_y = INT32_MIN;

// Telemetry must never perform disk I/O from DirectInput/GetDeviceState.
// A fixed queue bounds memory and a dedicated writer drains it in the
// background. When a very slow disk fills the queue, the oldest diagnostic
// line is discarded and the loss is reported in the next snapshot.
constexpr size_t kTelemetryQueueCapacity = 64;
constexpr size_t kTelemetryLineCapacity = 1536;
struct TelemetryLine {
    DWORD length = 0;
    char text[kTelemetryLineCapacity]{};
};
TelemetryLine g_telemetry_lines[kTelemetryQueueCapacity]{};
size_t g_telemetry_queue_head = 0;
size_t g_telemetry_queue_tail = 0;
SRWLOCK g_telemetry_queue_lock = SRWLOCK_INIT;
INIT_ONCE g_telemetry_writer_once = INIT_ONCE_STATIC_INIT;
HANDLE g_telemetry_writer_event = nullptr;
HANDLE g_telemetry_writer_thread = nullptr;
volatile LONG g_telemetry_lines_dropped = 0;

// Test-only process-local capture of the original executable's shared CRT
// rand() stream. The hot hook writes fixed-size memory records only; the
// existing below-normal telemetry writer performs all disk I/O after the
// message pump drains records into bounded JSON batches.
bool g_crt_random_trace_enabled = false;
constexpr LONG kCrtRandomTraceCapacity = 131072;
struct CrtRandomTraceRecord {
    volatile LONG sequence = 0;
    DWORD thread_id = 0;
    DWORD tick_ms = 0;
    std::uint32_t call_site_rva = 0;
    std::uint32_t caller_esi = 0;
    int value = 0;
};
CrtRandomTraceRecord *g_crt_random_trace = nullptr;
volatile LONG g_crt_random_trace_count = 0;
volatile LONG g_crt_random_trace_flushed = 0;
volatile LONG g_crt_random_trace_dropped = 0;

struct EnhancedSearchState {
    std::uintptr_t actor = 0;
    int anchor_x = 0;
    int anchor_y = 0;
    int direction = 1;
    int next_point = 0;
    int point_count = 0;
    DWORD started_at = 0;
    DWORD last_progress_at = 0;
    int last_actor_x = 0;
    int last_actor_y = 0;
    DWORD activation_at = 0;
    int pending_goal_x = 0;
    int pending_goal_y = 0;
    bool pending_activation = false;
    bool intercept_assigned = false;
};

EnhancedSearchState g_search_states[256]{};
volatile LONG g_last_ai_tick = 0;
int g_ai_last_mission = -1;
std::uintptr_t g_ai_actor_table = 0;

void ClearEnhancedSearchStates();

using ImmDisableIMEProc = BOOL(WINAPI *)(DWORD);
using ImmAssociateContextExProc = BOOL(WINAPI *)(HWND, HANDLE, DWORD);
using SetProcessDpiAwarenessContextProc = BOOL(WINAPI *)(HANDLE);

void RecordDiagnostic(
    const char *event, const char *status, const char *detail);

int ClampSetting(int value, int minimum, int maximum) {
    if (value < minimum) {
        return minimum;
    }
    if (value > maximum) {
        return maximum;
    }
    return value;
}

LONGLONG PerformanceCounterNow() {
    LARGE_INTEGER value{};
    QueryPerformanceCounter(&value);
    return value.QuadPart;
}

LONG ElapsedMicroseconds(LONGLONG started) {
    static LONGLONG frequency = []() -> LONGLONG {
        LARGE_INTEGER value{};
        QueryPerformanceFrequency(&value);
        return value.QuadPart > 0 ? value.QuadPart : 1;
    }();
    const LONGLONG elapsed = PerformanceCounterNow() - started;
    const LONGLONG micros = elapsed > 0
        ? elapsed * 1000000LL / frequency
        : 0;
    return static_cast<LONG>(
        micros > LONG_MAX ? LONG_MAX : micros);
}

void UpdateMaximum(volatile LONG *target, LONG value) {
    if (!target) {
        return;
    }
    LONG current = InterlockedCompareExchange(target, 0, 0);
    while (value > current) {
        const LONG observed =
            InterlockedCompareExchange(target, value, current);
        if (observed == current) {
            break;
        }
        current = observed;
    }
}

void AddTiming(
    volatile LONG *calls, volatile LONG *total,
    volatile LONG *maximum, LONGLONG started) {
    const LONG elapsed = ElapsedMicroseconds(started);
    InterlockedIncrement(calls);
    InterlockedExchangeAdd(total, elapsed);
    UpdateMaximum(maximum, elapsed);
}

int ParseDikName(const wchar_t *value) {
    if (!value || !*value) {
        return -1;
    }
    wchar_t *end = nullptr;
    const long numeric = wcstol(value, &end, 0);
    if (end != value && *end == L'\0') {
        return numeric >= 1 && numeric <= 255
            ? static_cast<int>(numeric)
            : -1;
    }
    struct NamedDik {
        const wchar_t *name;
        int code;
    };
    static const NamedDik names[] = {
        {L"ESC", DIK_ESCAPE}, {L"ESCAPE", DIK_ESCAPE},
        {L"TAB", DIK_TAB}, {L"ENTER", DIK_RETURN},
        {L"SPACE", DIK_SPACE}, {L"BACKSPACE", DIK_BACK},
        {L"F1", DIK_F1}, {L"F2", DIK_F2}, {L"F3", DIK_F3},
        {L"F4", DIK_F4}, {L"F5", DIK_F5}, {L"F6", DIK_F6},
        {L"F7", DIK_F7}, {L"F8", DIK_F8}, {L"F9", DIK_F9},
        {L"F10", DIK_F10}, {L"F11", DIK_F11}, {L"F12", DIK_F12},
        {L"UP", DIK_UP}, {L"DOWN", DIK_DOWN},
        {L"LEFT", DIK_LEFT}, {L"RIGHT", DIK_RIGHT},
        {L"HOME", DIK_HOME}, {L"END", DIK_END},
        {L"PGUP", DIK_PRIOR}, {L"PGDN", DIK_NEXT},
        {L"INSERT", DIK_INSERT}, {L"DELETE", DIK_DELETE},
        {L"CTRL", DIK_LCONTROL}, {L"SHIFT", DIK_LSHIFT},
        {L"ALT", DIK_LMENU},
        {L"A", DIK_A}, {L"B", DIK_B}, {L"C", DIK_C},
        {L"D", DIK_D}, {L"E", DIK_E}, {L"F", DIK_F},
        {L"G", DIK_G}, {L"H", DIK_H}, {L"I", DIK_I},
        {L"J", DIK_J}, {L"K", DIK_K}, {L"L", DIK_L},
        {L"M", DIK_M}, {L"N", DIK_N}, {L"O", DIK_O},
        {L"P", DIK_P}, {L"Q", DIK_Q}, {L"R", DIK_R},
        {L"S", DIK_S}, {L"T", DIK_T}, {L"U", DIK_U},
        {L"V", DIK_V}, {L"W", DIK_W}, {L"X", DIK_X},
        {L"Y", DIK_Y}, {L"Z", DIK_Z},
        {L"0", DIK_0}, {L"1", DIK_1}, {L"2", DIK_2},
        {L"3", DIK_3}, {L"4", DIK_4}, {L"5", DIK_5},
        {L"6", DIK_6}, {L"7", DIK_7}, {L"8", DIK_8},
        {L"9", DIK_9},
    };
    for (const auto &entry : names) {
        if (_wcsicmp(value, entry.name) == 0) {
            return entry.code;
        }
    }
    return -1;
}

void LoadKeyAliases() {
    g_key_alias_count = 0;
    if (!g_mod_config.key_remapping || !g_rungame_ini[0]) {
        return;
    }
    for (int index = 1; index <= 16; ++index) {
        wchar_t key[24]{};
        wchar_t value[96]{};
        swprintf_s(key, L"Alias%d", index);
        GetPrivateProfileStringW(
            L"keymap", key, L"", value,
            static_cast<DWORD>(sizeof(value) / sizeof(value[0])),
            g_rungame_ini);
        if (!value[0]) {
            continue;
        }
        wchar_t *separator = wcschr(value, L',');
        if (!separator) {
            RecordDiagnostic("key_alias", "rejected", "missing_comma");
            continue;
        }
        *separator = L'\0';
        const int source = ParseDikName(value);
        const int target = ParseDikName(separator + 1);
        if (source < 1 || target < 1 || source == target) {
            RecordDiagnostic("key_alias", "rejected", "invalid_mapping");
            continue;
        }
        bool conflict = false;
        for (int existing = 0; existing < g_key_alias_count; ++existing) {
            if (g_key_aliases[existing].source == source ||
                g_key_aliases[existing].target == target) {
                conflict = true;
                break;
            }
        }
        if (conflict) {
            RecordDiagnostic("key_alias", "rejected", "conflict");
            continue;
        }
        g_key_aliases[g_key_alias_count].source =
            static_cast<unsigned char>(source);
        g_key_aliases[g_key_alias_count].target =
            static_cast<unsigned char>(target);
        ++g_key_alias_count;
    }
    char detail[48]{};
    snprintf(detail, sizeof(detail), "aliases=%d", g_key_alias_count);
    RecordDiagnostic("key_remapping", "ready", detail);
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

LONG TakeCounter(volatile LONG *value) {
    return InterlockedExchange(value, 0);
}

void WriteCrtRandomTraceRecords(HANDLE file) {
    if (!g_crt_random_trace_enabled ||
        !g_crt_random_trace ||
        file == INVALID_HANDLE_VALUE) {
        return;
    }
    LONG flushed = InterlockedCompareExchange(
        &g_crt_random_trace_flushed, 0, 0);
    const LONG recorded = InterlockedCompareExchange(
        &g_crt_random_trace_count, 0, 0);
    const LONG available =
        recorded < kCrtRandomTraceCapacity
            ? recorded
            : kCrtRandomTraceCapacity;
    while (flushed < available) {
        char line[kTelemetryLineCapacity]{};
        int length = snprintf(
            line, sizeof(line),
            "{\"event\":\"crt_rand_batch\",\"pid\":%lu,"
            "\"records\":[",
            GetCurrentProcessId());
        if (length <= 0 ||
            length >= static_cast<int>(sizeof(line) - 4)) {
            return;
        }
        int appended = 0;
        while (flushed < available && appended < 12) {
            const LONG expected_sequence = flushed + 1;
            auto &record = g_crt_random_trace[flushed];
            if (InterlockedCompareExchange(
                    &record.sequence, 0, 0) !=
                expected_sequence) {
                break;
            }
            const int written = snprintf(
                line + length,
                sizeof(line) - static_cast<size_t>(length),
                "%s{\"sequence\":%ld,\"thread\":%lu,"
                "\"tick_ms\":%lu,"
                "\"call_site_rva\":\"0x%08lX\","
                "\"caller_esi\":\"0x%08lX\",\"value\":%d}",
                appended == 0 ? "" : ",",
                expected_sequence,
                record.thread_id,
                record.tick_ms,
                static_cast<unsigned long>(
                    record.call_site_rva),
                static_cast<unsigned long>(record.caller_esi),
                record.value);
            if (written <= 0 ||
                written >= static_cast<int>(
                    sizeof(line) - static_cast<size_t>(length) - 3)) {
                break;
            }
            length += written;
            ++flushed;
            ++appended;
        }
        if (appended == 0) {
            break;
        }
        line[length++] = ']';
        line[length++] = '}';
        line[length++] = '\r';
        line[length++] = '\n';
        DWORD written = 0;
        WriteFile(
            file, line, static_cast<DWORD>(length),
            &written, nullptr);
        InterlockedExchange(
            &g_crt_random_trace_flushed, flushed);
    }
}

DWORD WINAPI TelemetryWriterThread(void *) {
    for (;;) {
        if (WaitForSingleObject(
                g_telemetry_writer_event, INFINITE) != WAIT_OBJECT_0) {
            return 0;
        }
        HANDLE file = CreateFileW(
            g_telemetry_log, FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        WriteCrtRandomTraceRecords(file);
        for (;;) {
            TelemetryLine line{};
            bool available = false;
            AcquireSRWLockExclusive(&g_telemetry_queue_lock);
            if (g_telemetry_queue_tail != g_telemetry_queue_head) {
                line = g_telemetry_lines[g_telemetry_queue_tail];
                g_telemetry_queue_tail =
                    (g_telemetry_queue_tail + 1) %
                    kTelemetryQueueCapacity;
                available = true;
            }
            ReleaseSRWLockExclusive(&g_telemetry_queue_lock);
            if (!available) {
                break;
            }
            if (file != INVALID_HANDLE_VALUE && line.length > 0) {
                DWORD written = 0;
                WriteFile(
                    file, line.text, line.length,
                    &written, nullptr);
            }
        }
        if (file != INVALID_HANDLE_VALUE) {
            CloseHandle(file);
        }
    }
}

BOOL CALLBACK InitializeTelemetryWriter(
    PINIT_ONCE, PVOID, PVOID *) {
    g_telemetry_writer_event =
        CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!g_telemetry_writer_event) {
        return FALSE;
    }
    g_telemetry_writer_thread = CreateThread(
        nullptr, 0, &TelemetryWriterThread, nullptr, 0, nullptr);
    if (!g_telemetry_writer_thread) {
        CloseHandle(g_telemetry_writer_event);
        g_telemetry_writer_event = nullptr;
        return FALSE;
    }
    SetThreadPriority(
        g_telemetry_writer_thread,
        THREAD_PRIORITY_BELOW_NORMAL);
    return TRUE;
}

bool QueueTelemetryLine(const char *text, DWORD length) {
    if (!text || length == 0) {
        return false;
    }
    if (!InitOnceExecuteOnce(
            &g_telemetry_writer_once,
            &InitializeTelemetryWriter,
            nullptr, nullptr) ||
        !g_telemetry_writer_event) {
        InterlockedIncrement(&g_telemetry_lines_dropped);
        return false;
    }
    const DWORD bounded_length =
        length < kTelemetryLineCapacity
            ? length
            : static_cast<DWORD>(kTelemetryLineCapacity - 1);
    AcquireSRWLockExclusive(&g_telemetry_queue_lock);
    const size_t next =
        (g_telemetry_queue_head + 1) %
        kTelemetryQueueCapacity;
    if (next == g_telemetry_queue_tail) {
        g_telemetry_queue_tail =
            (g_telemetry_queue_tail + 1) %
            kTelemetryQueueCapacity;
        InterlockedIncrement(&g_telemetry_lines_dropped);
    }
    auto &slot = g_telemetry_lines[g_telemetry_queue_head];
    memcpy(slot.text, text, bounded_length);
    slot.text[bounded_length] = '\0';
    slot.length = bounded_length;
    g_telemetry_queue_head = next;
    ReleaseSRWLockExclusive(&g_telemetry_queue_lock);
    SetEvent(g_telemetry_writer_event);
    return true;
}

void FlushCrtRandomTrace() {
    if (!g_crt_random_trace_enabled ||
        !g_crt_random_trace ||
        !InitOnceExecuteOnce(
            &g_telemetry_writer_once,
            &InitializeTelemetryWriter,
            nullptr, nullptr) ||
        !g_telemetry_writer_event) {
        return;
    }
    SetEvent(g_telemetry_writer_event);
}

void FlushTelemetrySnapshot(bool force = false) {
    if (!g_mod_config.telemetry || !g_telemetry_log[0]) {
        return;
    }
    FlushCrtRandomTrace();
    const DWORD now = GetTickCount();
    const DWORD last = static_cast<DWORD>(
        InterlockedCompareExchange(&g_last_telemetry_tick, 0, 0));
    if (!force && now - last <
        static_cast<DWORD>(g_mod_config.telemetry_interval_ms)) {
        return;
    }
    if (InterlockedCompareExchange(
            &g_last_telemetry_tick,
            static_cast<LONG>(now),
            static_cast<LONG>(last)) != static_cast<LONG>(last)) {
        return;
    }

    int mission = 0;
    int camera_x = INT32_MIN;
    int camera_y = INT32_MIN;
    if (g_executable_base) {
        mission = *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::current_mission);
        camera_x = *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::camera_x);
        camera_y = *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::camera_y);
    }
    const bool camera_moved =
        g_last_telemetry_camera_x != INT32_MIN &&
        (camera_x != g_last_telemetry_camera_x ||
         camera_y != g_last_telemetry_camera_y);
    g_last_telemetry_camera_x = camera_x;
    g_last_telemetry_camera_y = camera_y;
    const bool mission_changed =
        g_last_telemetry_mission >= 0 &&
        mission != g_last_telemetry_mission;
    g_last_telemetry_mission = mission;

    IO_COUNTERS io{};
    GetProcessIoCounters(GetCurrentProcess(), &io);
    const ULONGLONG read_delta =
        io.ReadTransferCount >= g_last_telemetry_read_bytes
        ? io.ReadTransferCount - g_last_telemetry_read_bytes
        : 0;
    g_last_telemetry_read_bytes = io.ReadTransferCount;

    const LONG pump_calls = TakeCounter(&g_telemetry.pump_calls);
    const LONG pump_messages = TakeCounter(&g_telemetry.pump_messages);
    const LONG pump_us = TakeCounter(&g_telemetry.pump_microseconds);
    const LONG pump_max = TakeCounter(&g_telemetry.pump_max_microseconds);
    const LONG state_calls = TakeCounter(&g_telemetry.input_state_calls);
    const LONG state_us = TakeCounter(&g_telemetry.input_state_microseconds);
    const LONG state_max =
        TakeCounter(&g_telemetry.input_state_max_microseconds);
    const LONG data_calls = TakeCounter(&g_telemetry.input_data_calls);
    const LONG data_us = TakeCounter(&g_telemetry.input_data_microseconds);
    const LONG data_max =
        TakeCounter(&g_telemetry.input_data_max_microseconds);
    const LONG replay_messages =
        TakeCounter(&g_telemetry.replay_messages);
    const LONG replay_reads = TakeCounter(&g_telemetry.replay_reads);
    const LONG replay_latency_samples =
        TakeCounter(&g_telemetry.replay_latency_samples);
    const LONG replay_latency_us =
        TakeCounter(&g_telemetry.replay_latency_microseconds);
    const LONG replay_latency_max =
        TakeCounter(&g_telemetry.replay_latency_max_microseconds);
    const LONG player_ground_reroutes =
        TakeCounter(&g_telemetry.player_ground_reroutes);
    const LONG ai_ticks = TakeCounter(&g_telemetry.ai_ticks);
    const LONG ai_us = TakeCounter(&g_telemetry.ai_tick_microseconds);
    const LONG ai_max = TakeCounter(&g_telemetry.ai_tick_max_microseconds);
    const LONG ai_alerts = TakeCounter(&g_telemetry.ai_alerts);
    const LONG reinforcements =
        TakeCounter(&g_telemetry.ai_reinforcements);
    const LONG searches_started =
        TakeCounter(&g_telemetry.ai_searches_started);
    const LONG replans = TakeCounter(&g_telemetry.ai_search_replans);
    const LONG intercepts = TakeCounter(&g_telemetry.ai_intercepts);
    const LONG reaction_samples =
        TakeCounter(&g_telemetry.ai_reaction_samples);
    const LONG reaction_total =
        TakeCounter(&g_telemetry.ai_reaction_total_ms);
    const LONG reaction_max =
        TakeCounter(&g_telemetry.ai_reaction_max_ms);
    const LONG search_completed =
        TakeCounter(&g_telemetry.ai_search_completed);
    const LONG reacquisitions =
        TakeCounter(&g_telemetry.ai_reacquisitions);
    const LONG escapes = TakeCounter(&g_telemetry.ai_escape_timeouts);
    const LONG writer_dropped =
        TakeCounter(&g_telemetry_lines_dropped);
    const char *phase = mission > 0 ? "gameplay" : "menu_or_startup";
    char line[kTelemetryLineCapacity]{};
    const int length = snprintf(
        line, sizeof(line),
        "{\"schema\":1,\"tick_ms\":%lu,\"mission\":%d,"
        "\"phase\":\"%s\",\"mission_changed\":%s,"
        "\"camera_moved\":%s,\"first_load_io\":%s,"
        "\"disk_read_bytes\":%llu,\"writer_queue_dropped\":%ld,"
        "\"pump\":{\"calls\":%ld,\"messages\":%ld,"
        "\"total_us\":%ld,\"max_us\":%ld},"
        "\"input\":{\"state_calls\":%ld,\"state_total_us\":%ld,"
        "\"state_max_us\":%ld,\"data_calls\":%ld,"
        "\"data_total_us\":%ld,\"data_max_us\":%ld},"
        "\"replay\":{\"messages\":%ld,\"reads\":%ld,"
        "\"latency_samples\":%ld,\"latency_total_us\":%ld,"
        "\"latency_max_us\":%ld},"
        "\"player\":{\"ground_reroutes\":%ld},"
        "\"ai\":{\"ticks\":%ld,\"tick_total_us\":%ld,"
        "\"tick_max_us\":%ld,\"alerts\":%ld,"
        "\"reinforcements\":%ld,\"searches_started\":%ld,"
        "\"search_replans\":%ld,\"intercepts\":%ld,"
        "\"reaction_samples\":%ld,\"reaction_total_ms\":%ld,"
        "\"reaction_max_ms\":%ld,\"search_completed\":%ld,"
        "\"reacquisitions\":%ld,\"escape_timeouts\":%ld}}\r\n",
        static_cast<unsigned long>(now), mission, phase,
        mission_changed ? "true" : "false",
        camera_moved ? "true" : "false",
        read_delta >= 1024ULL * 1024ULL ? "true" : "false",
        static_cast<unsigned long long>(read_delta),
        writer_dropped,
        pump_calls, pump_messages, pump_us, pump_max,
        state_calls, state_us, state_max,
        data_calls, data_us, data_max,
        replay_messages, replay_reads,
        replay_latency_samples, replay_latency_us,
        replay_latency_max, player_ground_reroutes,
        ai_ticks, ai_us, ai_max, ai_alerts,
        reinforcements, searches_started, replans, intercepts,
        reaction_samples, reaction_total, reaction_max,
        search_completed, reacquisitions, escapes);
    if (length > 0) {
        QueueTelemetryLine(
            line,
            static_cast<DWORD>(
                length < static_cast<int>(sizeof(line))
                    ? length
                    : sizeof(line) - 1));
    }
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
    lstrcpynW(g_telemetry_log, executable, MAX_PATH);
    lstrcatW(g_telemetry_log, L"M1937Telemetry.jsonl");
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
    g_mod_config.telemetry = read(L"Telemetry", 0) != 0;
    char telemetry_environment[8]{};
    if (GetEnvironmentVariableA(
            "M1937_TELEMETRY", telemetry_environment,
            static_cast<DWORD>(sizeof(telemetry_environment))) > 0) {
        g_mod_config.telemetry =
            strcmp(telemetry_environment, "1") == 0;
    }
    char crt_random_trace_environment[8]{};
    if (GetEnvironmentVariableA(
            "M1937_RNG_TRACE", crt_random_trace_environment,
            static_cast<DWORD>(
                sizeof(crt_random_trace_environment))) > 0) {
        g_crt_random_trace_enabled =
            strcmp(crt_random_trace_environment, "1") == 0;
        if (g_crt_random_trace_enabled &&
            !g_crt_random_trace) {
            g_crt_random_trace =
                static_cast<CrtRandomTraceRecord *>(VirtualAlloc(
                    nullptr,
                    sizeof(CrtRandomTraceRecord) *
                        static_cast<size_t>(
                            kCrtRandomTraceCapacity),
                    MEM_COMMIT | MEM_RESERVE,
                    PAGE_READWRITE));
            g_crt_random_trace_enabled =
                g_crt_random_trace != nullptr;
        }
        // The trace uses the same asynchronous destination as ordinary
        // telemetry. Enabling this explicit test seam therefore also enables
        // that writer even if rungame.ini keeps player telemetry disabled.
        if (g_crt_random_trace_enabled) {
            g_mod_config.telemetry = true;
        }
    }
    g_mod_config.telemetry_interval_ms =
        ClampSetting(read(L"TelemetryIntervalMs", 1000), 250, 10000);
    g_mod_config.key_remapping = read(L"KeyRemapping", 0) != 0;
    g_mod_config.max_reinforcements =
        ClampSetting(read(L"MaxReinforcements", 0), 0, 8);
    g_mod_config.search_points =
        ClampSetting(read(L"SearchPoints", 0), 0, 4);
    g_mod_config.search_timeout_ms =
        ClampSetting(read(L"SearchTimeoutMs", 0), 0, 120000);
    g_mod_config.intercept_distance =
        ClampSetting(read(L"InterceptDistance", 0), 0, 512);
    g_mod_config.ai_tick_interval_ms =
        ClampSetting(read(L"AITickIntervalMs", 100), 50, 1000);
    g_mod_config.mission_sidecar = read(L"MissionSidecar", 0) != 0;
    g_mod_config.plugins = read(L"EnablePlugins", 0) != 0;
    g_mod_config.text_briefings = read(L"TextBriefings", 1) != 0;
    LoadKeyAliases();
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

bool IsLegacyBriefingReplacementEnabled() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_REPLACE_LEGACY_BRIEFING",
        value,
        static_cast<DWORD>(sizeof(value)));
    if (length > 0 && length < sizeof(value)) {
        return strcmp(value, "1") == 0;
    }
    return g_mod_config.text_briefings;
}

const m1937::sdk::MissionRoute *RequestedBriefingRoute() {
    if (!IsLegacyBriefingReplacementEnabled()) {
        return nullptr;
    }
    int selector_level = RequestedStartLevel();
    if (selector_level == 0) {
        // The unmodified full-menu New Game path always starts mission one.
        selector_level = 1;
    }
    const auto *route =
        m1937::sdk::find_mission_route(selector_level);
    return route && route->replace_legacy_briefing ? route : nullptr;
}

bool RequiresExtensionBriefingContinuation() {
    const auto *route = RequestedBriefingRoute();
    return route && route->selector_level >= 13;
}

void ArmExtensionBriefingContinuation(
    const m1937::sdk::MissionRoute *route) {
    if (!route || route->selector_level < 13 || !g_executable_base) {
        InterlockedExchange(&g_extension_briefing_pending, 0);
        InterlockedExchange(&g_extension_resume_hotkey_armed, 0);
        InterlockedExchange(&g_extension_selection_hotkey_phase, 0);
        return;
    }
    // The same button/key that selected "Start Game" must be released before
    // a second action can dismiss the briefing. This preserves the visible
    // briefing instead of consuming the menu click as its confirmation.
    InterlockedExchange(&g_extension_briefing_mouse_released, 0);
    InterlockedExchange(&g_extension_briefing_keyboard_released, 0);
    InterlockedExchange(&g_extension_resume_hotkey_armed, 0);
    InterlockedExchange(&g_extension_resume_mouse_released, 0);
    InterlockedExchange(&g_extension_resume_keyboard_released, 0);
    InterlockedExchange(&g_extension_resume_accept_tick, 0);
    InterlockedExchange(&g_extension_selection_hotkey_phase, 0);
    InterlockedExchange(&g_extension_selection_hotkey_due_tick, 0);
    InterlockedExchange(&g_extension_selection_hotkey_release_tick, 0);
    InterlockedExchange(&g_extension_briefing_pending, 1);
    RecordDiagnostic(
        "extension_briefing", "armed", route->id);
}

void CompleteExtensionBriefingContinuation(const char *input_source) {
    if (!g_executable_base ||
        InterlockedCompareExchange(
            &g_extension_briefing_pending, 0, 1) != 1) {
        return;
    }
    *reinterpret_cast<unsigned char *>(
        g_executable_base + m1937::sdk::rva::briefing_advance) = 1;
    // Require a release after the briefing action. The next menu action
    // returns to the mission and schedules the original F4 character hotkey.
    // That engine-owned path selects the extension player, centers its camera
    // and invalidates the full world surface together.
    InterlockedExchange(&g_extension_resume_mouse_released, 0);
    InterlockedExchange(&g_extension_resume_keyboard_released, 0);
    InterlockedExchange(
        &g_extension_resume_accept_tick,
        static_cast<LONG>(GetTickCount() + 250));
    InterlockedExchange(&g_extension_resume_hotkey_armed, 1);
    RecordDiagnostic(
        "extension_briefing", "continued", input_source);
}

bool IsWindowReplayEnabled() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_WINDOW_REPLAY", value, static_cast<DWORD>(sizeof(value)));
    return IsAutomatedProbeEnabled() &&
        length > 0 && length < sizeof(value) &&
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

bool HoldAutomatedBriefingForCapture() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_AUTOTEST_BRIEFING_HOLD",
        value,
        static_cast<DWORD>(sizeof(value)));
    return length > 0 && length < sizeof(value) &&
        strcmp(value, "1") == 0;
}

// Historical note: v1.4.1 temporarily rendered the briefing in a separate
// top-level Win32 dialog. Keep the old parser/renderer below excluded for one
// release so existing diagnostics can still be compared, but it is no longer
// compiled or reachable. Text is now rasterized into the original GFL briefing
// picture and displayed by the game's own screen and continuation loop.
#if 0
struct TextBriefingContent {
    std::wstring title;
    std::wstring briefing;
    std::wstring objective_1;
    std::wstring objective_2;
    std::wstring objective_3;
};

class JsonReader {
public:
    explicit JsonReader(std::wstring_view text)
        : text_(text) {}

    bool Consume(wchar_t expected) {
        SkipWhitespace();
        if (position_ >= text_.size() ||
            text_[position_] != expected) {
            return false;
        }
        ++position_;
        return true;
    }

    bool ParseString(std::wstring &value) {
        SkipWhitespace();
        if (position_ >= text_.size() ||
            text_[position_] != L'"') {
            return false;
        }
        ++position_;
        value.clear();
        while (position_ < text_.size()) {
            const wchar_t character = text_[position_++];
            if (character == L'"') {
                return true;
            }
            if (character < 0x20) {
                return false;
            }
            if (character != L'\\') {
                value.push_back(character);
                continue;
            }
            if (position_ >= text_.size()) {
                return false;
            }
            const wchar_t escaped = text_[position_++];
            switch (escaped) {
            case L'"':
            case L'\\':
            case L'/':
                value.push_back(escaped);
                break;
            case L'b':
                value.push_back(L'\b');
                break;
            case L'f':
                value.push_back(L'\f');
                break;
            case L'n':
                value.push_back(L'\n');
                break;
            case L'r':
                value.push_back(L'\r');
                break;
            case L't':
                value.push_back(L'\t');
                break;
            case L'u': {
                wchar_t code_unit = 0;
                if (!ParseHexCodeUnit(code_unit)) {
                    return false;
                }
                value.push_back(code_unit);
                break;
            }
            default:
                return false;
            }
        }
        return false;
    }

    bool ParseInteger(int &value) {
        SkipWhitespace();
        if (position_ >= text_.size()) {
            return false;
        }
        bool negative = false;
        if (text_[position_] == L'-') {
            negative = true;
            ++position_;
        }
        if (position_ >= text_.size() ||
            text_[position_] < L'0' ||
            text_[position_] > L'9') {
            return false;
        }
        int parsed = 0;
        while (position_ < text_.size() &&
               text_[position_] >= L'0' &&
               text_[position_] <= L'9') {
            if (parsed > 1000000) {
                return false;
            }
            parsed = parsed * 10 +
                static_cast<int>(text_[position_] - L'0');
            ++position_;
        }
        value = negative ? -parsed : parsed;
        return true;
    }

    bool ParseBoolean(bool &value) {
        SkipWhitespace();
        if (MatchLiteral(L"true")) {
            value = true;
            return true;
        }
        if (MatchLiteral(L"false")) {
            value = false;
            return true;
        }
        return false;
    }

    bool SkipValue(int depth = 0) {
        if (depth > 32) {
            return false;
        }
        SkipWhitespace();
        if (position_ >= text_.size()) {
            return false;
        }
        if (text_[position_] == L'"') {
            std::wstring ignored;
            return ParseString(ignored);
        }
        if (text_[position_] == L'{') {
            ++position_;
            SkipWhitespace();
            if (ConsumeIf(L'}')) {
                return true;
            }
            while (true) {
                std::wstring key;
                if (!ParseString(key) ||
                    !Consume(L':') ||
                    !SkipValue(depth + 1)) {
                    return false;
                }
                SkipWhitespace();
                if (ConsumeIf(L'}')) {
                    return true;
                }
                if (!ConsumeIf(L',')) {
                    return false;
                }
            }
        }
        if (text_[position_] == L'[') {
            ++position_;
            SkipWhitespace();
            if (ConsumeIf(L']')) {
                return true;
            }
            while (true) {
                if (!SkipValue(depth + 1)) {
                    return false;
                }
                SkipWhitespace();
                if (ConsumeIf(L']')) {
                    return true;
                }
                if (!ConsumeIf(L',')) {
                    return false;
                }
            }
        }
        if (MatchLiteral(L"true") ||
            MatchLiteral(L"false") ||
            MatchLiteral(L"null")) {
            return true;
        }
        return SkipNumber();
    }

private:
    void SkipWhitespace() {
        while (position_ < text_.size()) {
            const wchar_t character = text_[position_];
            if (character != L' ' &&
                character != L'\t' &&
                character != L'\r' &&
                character != L'\n') {
                break;
            }
            ++position_;
        }
    }

    bool ConsumeIf(wchar_t expected) {
        SkipWhitespace();
        if (position_ < text_.size() &&
            text_[position_] == expected) {
            ++position_;
            return true;
        }
        return false;
    }

    bool MatchLiteral(std::wstring_view value) {
        if (text_.substr(position_, value.size()) != value) {
            return false;
        }
        position_ += value.size();
        return true;
    }

    bool ParseHexCodeUnit(wchar_t &value) {
        if (position_ + 4 > text_.size()) {
            return false;
        }
        unsigned int parsed = 0;
        for (int index = 0; index < 4; ++index) {
            const wchar_t character = text_[position_++];
            parsed <<= 4;
            if (character >= L'0' && character <= L'9') {
                parsed += character - L'0';
            } else if (
                character >= L'a' && character <= L'f') {
                parsed += character - L'a' + 10;
            } else if (
                character >= L'A' && character <= L'F') {
                parsed += character - L'A' + 10;
            } else {
                return false;
            }
        }
        value = static_cast<wchar_t>(parsed);
        return true;
    }

    bool SkipNumber() {
        const size_t start = position_;
        if (position_ < text_.size() &&
            text_[position_] == L'-') {
            ++position_;
        }
        if (position_ >= text_.size()) {
            position_ = start;
            return false;
        }
        if (text_[position_] == L'0') {
            ++position_;
        } else if (
            text_[position_] >= L'1' &&
            text_[position_] <= L'9') {
            while (position_ < text_.size() &&
                   text_[position_] >= L'0' &&
                   text_[position_] <= L'9') {
                ++position_;
            }
        } else {
            position_ = start;
            return false;
        }
        if (position_ < text_.size() &&
            text_[position_] == L'.') {
            ++position_;
            const size_t fraction = position_;
            while (position_ < text_.size() &&
                   text_[position_] >= L'0' &&
                   text_[position_] <= L'9') {
                ++position_;
            }
            if (fraction == position_) {
                position_ = start;
                return false;
            }
        }
        if (position_ < text_.size() &&
            (text_[position_] == L'e' ||
             text_[position_] == L'E')) {
            ++position_;
            if (position_ < text_.size() &&
                (text_[position_] == L'+' ||
                 text_[position_] == L'-')) {
                ++position_;
            }
            const size_t exponent = position_;
            while (position_ < text_.size() &&
                   text_[position_] >= L'0' &&
                   text_[position_] <= L'9') {
                ++position_;
            }
            if (exponent == position_) {
                position_ = start;
                return false;
            }
        }
        return true;
    }

    std::wstring_view text_;
    size_t position_ = 0;
};

bool ParseObjectiveArray(
    JsonReader &reader,
    std::vector<std::wstring> &objectives) {
    if (!reader.Consume(L'[')) {
        return false;
    }
    objectives.clear();
    for (int index = 0; index < 3; ++index) {
        std::wstring objective;
        if (!reader.ParseString(objective) ||
            objective.empty()) {
            return false;
        }
        objectives.push_back(std::move(objective));
        if (index < 2 && !reader.Consume(L',')) {
            return false;
        }
    }
    return reader.Consume(L']');
}

bool ParseBriefingMission(
    JsonReader &reader,
    const m1937::sdk::MissionRoute &route,
    TextBriefingContent &content,
    bool &matched) {
    if (!reader.Consume(L'{')) {
        return false;
    }
    int number = 0;
    std::wstring id;
    std::wstring title;
    std::wstring briefing;
    std::vector<std::wstring> objectives;
    bool first = true;
    while (true) {
        if (!first && reader.Consume(L'}')) {
            break;
        }
        first = false;
        std::wstring key;
        if (!reader.ParseString(key) ||
            !reader.Consume(L':')) {
            return false;
        }
        if (key == L"number") {
            if (!reader.ParseInteger(number)) {
                return false;
            }
        } else if (key == L"id") {
            if (!reader.ParseString(id)) {
                return false;
            }
        } else if (key == L"title") {
            if (!reader.ParseString(title)) {
                return false;
            }
        } else if (key == L"briefing") {
            if (!reader.ParseString(briefing)) {
                return false;
            }
        } else if (key == L"objectives") {
            if (!ParseObjectiveArray(reader, objectives)) {
                return false;
            }
        } else if (!reader.SkipValue()) {
            return false;
        }
        if (reader.Consume(L'}')) {
            break;
        }
        if (!reader.Consume(L',')) {
            return false;
        }
    }

    const std::wstring route_id(
        route.id,
        route.id + strlen(route.id));
    if ((number == route.selector_level || id == route_id) &&
        !title.empty() &&
        !briefing.empty() &&
        objectives.size() == 3) {
        content.title = std::move(title);
        content.briefing = std::move(briefing);
        content.objective_1 = std::move(objectives[0]);
        content.objective_2 = std::move(objectives[1]);
        content.objective_3 = std::move(objectives[2]);
        matched = true;
    }
    return true;
}

bool ParseBriefingCatalog(
    std::wstring_view json,
    const m1937::sdk::MissionRoute &route,
    TextBriefingContent &content) {
    JsonReader reader(json);
    if (!reader.Consume(L'{')) {
        return false;
    }
    bool first = true;
    while (true) {
        if (!first && reader.Consume(L'}')) {
            return false;
        }
        first = false;
        std::wstring key;
        if (!reader.ParseString(key) ||
            !reader.Consume(L':')) {
            return false;
        }
        if (key == L"missions") {
            if (!reader.Consume(L'[')) {
                return false;
            }
            for (int index = 0; index < 15; ++index) {
                bool matched = false;
                if (!ParseBriefingMission(
                        reader,
                        route,
                        content,
                        matched)) {
                    return false;
                }
                if (matched) {
                    return true;
                }
                if (index < 14 && !reader.Consume(L',')) {
                    return false;
                }
            }
            return false;
        }
        if (!reader.SkipValue()) {
            return false;
        }
        if (reader.Consume(L'}')) {
            return false;
        }
        if (!reader.Consume(L',')) {
            return false;
        }
    }
}

bool ReadUtf8TextFile(
    const wchar_t *path,
    std::wstring &text) {
    HANDLE file = CreateFileW(
        path,
        GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return false;
    }
    LARGE_INTEGER size{};
    if (!GetFileSizeEx(file, &size) ||
        size.QuadPart <= 0 ||
        size.QuadPart > 1024 * 1024) {
        CloseHandle(file);
        return false;
    }
    std::string bytes(
        static_cast<size_t>(size.QuadPart),
        '\0');
    DWORD read = 0;
    const BOOL read_ok = ReadFile(
        file,
        bytes.data(),
        static_cast<DWORD>(bytes.size()),
        &read,
        nullptr);
    CloseHandle(file);
    if (!read_ok || read != bytes.size()) {
        return false;
    }
    const int wide_length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        bytes.data(),
        static_cast<int>(bytes.size()),
        nullptr,
        0);
    if (wide_length <= 0) {
        return false;
    }
    text.assign(
        static_cast<size_t>(wide_length),
        L'\0');
    if (MultiByteToWideChar(
            CP_UTF8,
            MB_ERR_INVALID_CHARS,
            bytes.data(),
            static_cast<int>(bytes.size()),
            text.data(),
            wide_length) != wide_length) {
        return false;
    }
    if (!text.empty() && text.front() == 0xFEFF) {
        text.erase(text.begin());
    }
    return true;
}

bool LoadBriefingCatalogOverride(
    const m1937::sdk::MissionRoute &route,
    TextBriefingContent &content) {
    wchar_t path[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(
        g_proxy_instance,
        path,
        MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return false;
    }
    wchar_t *file_name = wcsrchr(path, L'\\');
    if (!file_name) {
        return false;
    }
    *++file_name = L'\0';
    if (wcscat_s(
            path,
            L"关卡名称.json") != 0) {
        return false;
    }
    std::wstring json;
    return ReadUtf8TextFile(path, json) &&
        ParseBriefingCatalog(json, route, content);
}

struct TextBriefingDialog {
    bool accepted = false;
    HFONT title_font = nullptr;
    HFONT body_font = nullptr;
    HFONT button_font = nullptr;
};

void CloseTextBriefing(HWND window, bool accepted) {
    auto *dialog = reinterpret_cast<TextBriefingDialog *>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (dialog) {
        dialog->accepted = accepted;
    }
    DestroyWindow(window);
}

LRESULT CALLBACK TextBriefingWindowProc(
    HWND window,
    UINT message,
    WPARAM value,
    LPARAM parameter) {
    if (message == WM_NCCREATE) {
        const auto *create =
            reinterpret_cast<const CREATESTRUCTW *>(parameter);
        SetWindowLongPtrW(
            window,
            GWLP_USERDATA,
            reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    switch (message) {
    case WM_COMMAND:
        if (LOWORD(value) == IDOK) {
            CloseTextBriefing(window, true);
            return 0;
        }
        if (LOWORD(value) == IDCANCEL) {
            CloseTextBriefing(window, false);
            return 0;
        }
        break;
    case WM_TIMER:
        if (value == kTextBriefingTimer) {
            KillTimer(window, kTextBriefingTimer);
            CloseTextBriefing(window, true);
            return 0;
        }
        break;
    case WM_CLOSE:
        CloseTextBriefing(window, false);
        return 0;
    }
    return DefWindowProcW(window, message, value, parameter);
}

bool EnsureTextBriefingWindowClass() {
    WNDCLASSEXW existing{};
    existing.cbSize = sizeof(existing);
    if (GetClassInfoExW(
            g_proxy_instance,
            kTextBriefingWindowClass,
            &existing)) {
        return true;
    }
    WNDCLASSEXW window_class{};
    window_class.cbSize = sizeof(window_class);
    window_class.style = CS_DBLCLKS;
    window_class.lpfnWndProc = TextBriefingWindowProc;
    window_class.hInstance = g_proxy_instance;
    window_class.hCursor =
        LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
    window_class.hbrBackground =
        reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    window_class.lpszClassName = kTextBriefingWindowClass;
    return RegisterClassExW(&window_class) != 0;
}

HFONT CreateBriefingFont(
    int point_size,
    int weight,
    int dpi) {
    return CreateFontW(
        -MulDiv(point_size, dpi, 72),
        0,
        0,
        0,
        weight,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE,
        L"Microsoft YaHei UI");
}

void ApplyControlFont(HWND control, HFONT font) {
    if (control && font) {
        SendMessageW(
            control,
            WM_SETFONT,
            reinterpret_cast<WPARAM>(font),
            TRUE);
    }
}

bool ShowTextMissionBriefing(
    const m1937::sdk::MissionRoute &route) {
    TextBriefingContent briefing_content{
        route.title,
        route.briefing,
        route.objective_1,
        route.objective_2,
        route.objective_3};
    const bool catalog_override =
        LoadBriefingCatalogOverride(
            route,
            briefing_content);
    RecordDiagnostic(
        "briefing_text",
        catalog_override ? "catalog" : "compiled_fallback",
        route.id);
    std::wstring window_title =
        L"游戏内文字任务简报｜第 " +
        std::to_wstring(route.selector_level) +
        L" 关　" + briefing_content.title;
    std::wstring content = briefing_content.briefing;
    content += L"\r\n\r\n任务目标\r\n";
    content += L"1. ";
    content += briefing_content.objective_1;
    content += L"\r\n2. ";
    content += briefing_content.objective_2;
    content += L"\r\n3. ";
    content += briefing_content.objective_3;
    content +=
        L"\r\n\r\n可直接编辑游戏目录中的“关卡名称.json”，"
        L"下次开始任务即可生效。";

    if (!EnsureTextBriefingWindowClass()) {
        RecordDiagnostic(
            "text_briefing", "failed", "window_class");
        return false;
    }

    HWND owner = g_game_window ? g_game_window : GetActiveWindow();
    HDC device = GetDC(owner);
    const int dpi = device ? GetDeviceCaps(device, LOGPIXELSX) : 96;
    if (device) {
        ReleaseDC(owner, device);
    }
    const int scale_dpi = dpi > 0 ? dpi : 96;
    RECT dialog_rect{
        0,
        0,
        MulDiv(760, scale_dpi, 96),
        MulDiv(560, scale_dpi, 96)};
    const DWORD window_style =
        WS_POPUP | WS_CAPTION | WS_SYSMENU;
    const DWORD extended_style =
        WS_EX_DLGMODALFRAME | WS_EX_CONTROLPARENT;
    AdjustWindowRectEx(
        &dialog_rect,
        window_style,
        FALSE,
        extended_style);
    const int width = dialog_rect.right - dialog_rect.left;
    const int height = dialog_rect.bottom - dialog_rect.top;
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    GetMonitorInfoW(
        MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST),
        &monitor);
    const int x =
        monitor.rcWork.left +
        ((monitor.rcWork.right - monitor.rcWork.left) - width) / 2;
    const int y =
        monitor.rcWork.top +
        ((monitor.rcWork.bottom - monitor.rcWork.top) - height) / 2;

    TextBriefingDialog dialog;
    dialog.title_font = CreateBriefingFont(18, FW_BOLD, scale_dpi);
    dialog.body_font = CreateBriefingFont(11, FW_NORMAL, scale_dpi);
    dialog.button_font = CreateBriefingFont(10, FW_NORMAL, scale_dpi);
    HWND window = CreateWindowExW(
        extended_style,
        kTextBriefingWindowClass,
        window_title.c_str(),
        window_style,
        x,
        y,
        width,
        height,
        owner,
        nullptr,
        g_proxy_instance,
        &dialog);
    if (!window) {
        DeleteObject(dialog.title_font);
        DeleteObject(dialog.body_font);
        DeleteObject(dialog.button_font);
        RecordDiagnostic(
            "text_briefing", "failed", "window_create");
        return false;
    }

    RECT client{};
    GetClientRect(window, &client);
    const int margin = MulDiv(22, scale_dpi, 96);
    const int title_height = MulDiv(50, scale_dpi, 96);
    const int button_height = MulDiv(38, scale_dpi, 96);
    const int button_width = MulDiv(142, scale_dpi, 96);
    const int gap = MulDiv(12, scale_dpi, 96);
    const int footer_y =
        client.bottom - margin - button_height;
    HWND title = CreateWindowExW(
        0,
        L"STATIC",
        (L"第 " + std::to_wstring(route.selector_level) +
            L" 关　" + briefing_content.title).c_str(),
        WS_CHILD | WS_VISIBLE | SS_LEFT,
        margin,
        margin,
        client.right - margin * 2,
        title_height,
        window,
        nullptr,
        g_proxy_instance,
        nullptr);
    HWND body = CreateWindowExW(
        WS_EX_CLIENTEDGE,
        L"EDIT",
        content.c_str(),
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL |
            ES_LEFT | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY,
        margin,
        margin + title_height,
        client.right - margin * 2,
        footer_y - (margin + title_height) - gap,
        window,
        reinterpret_cast<HMENU>(100),
        g_proxy_instance,
        nullptr);
    HWND cancel = CreateWindowExW(
        0,
        L"BUTTON",
        L"返回原版菜单",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
        client.right - margin - button_width * 2 - gap,
        footer_y,
        button_width,
        button_height,
        window,
        reinterpret_cast<HMENU>(IDCANCEL),
        g_proxy_instance,
        nullptr);
    HWND accept = CreateWindowExW(
        0,
        L"BUTTON",
        L"开始任务",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
        client.right - margin - button_width,
        footer_y,
        button_width,
        button_height,
        window,
        reinterpret_cast<HMENU>(IDOK),
        g_proxy_instance,
        nullptr);
    ApplyControlFont(title, dialog.title_font);
    ApplyControlFont(body, dialog.body_font);
    ApplyControlFont(cancel, dialog.button_font);
    ApplyControlFont(accept, dialog.button_font);

    const DWORD auto_close_ms =
        TextBriefingAutoCloseMilliseconds();
    const bool no_activate = auto_close_ms > 0;
    if (!no_activate && owner) {
        EnableWindow(owner, FALSE);
    }
    if (auto_close_ms > 0) {
        SetTimer(
            window,
            kTextBriefingTimer,
            auto_close_ms,
            nullptr);
    }
    ShowWindow(
        window,
        no_activate ? SW_SHOWNOACTIVATE : SW_SHOW);
    UpdateWindow(window);

    bool received_quit = false;
    WPARAM quit_code = 0;
    MSG message{};
    while (IsWindow(window)) {
        const BOOL result = GetMessageW(
            &message, nullptr, 0, 0);
        if (result <= 0) {
            if (result == 0) {
                received_quit = true;
                quit_code = message.wParam;
            }
            if (IsWindow(window)) {
                DestroyWindow(window);
            }
            break;
        }
        if (!IsDialogMessageW(window, &message)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    if (!no_activate && owner) {
        EnableWindow(owner, TRUE);
    }
    if (received_quit) {
        PostQuitMessage(static_cast<int>(quit_code));
    }
    DeleteObject(dialog.title_font);
    DeleteObject(dialog.body_font);
    DeleteObject(dialog.button_font);
    RecordDiagnostic(
        "text_briefing",
        dialog.accepted ? "accepted" : "cancelled",
        route.id);
    return dialog.accepted;
}
#endif

bool UseEnhancedEnemyAI() {
    char value[8]{};
    const DWORD length = GetEnvironmentVariableA(
        "M1937_AI_ORIGINAL", value, static_cast<DWORD>(sizeof(value)));
    if (length > 0 && length < sizeof(value)) {
        return strcmp(value, "1") != 0;
    }
    return g_mod_config.ai_level > 0;
}

int ConfiguredMaxReinforcements() {
    if (g_mod_config.max_reinforcements > 0) {
        return ClampSetting(g_mod_config.max_reinforcements, 1, 4);
    }
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return m1937::sdk::enemy_ai::tuning_for(
        ai, g_mod_config.difficulty).maximum_reinforcements;
}

int ConfiguredReactionDelayMs() {
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return m1937::sdk::enemy_ai::tuning_for(
        ai, g_mod_config.difficulty).reaction_delay_ms;
}

int ConfiguredSearchPoints() {
    if (g_mod_config.search_points > 0) {
        return g_mod_config.search_points;
    }
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return m1937::sdk::enemy_ai::tuning_for(
        ai, g_mod_config.difficulty).search_point_count;
}

int ConfiguredSearchTimeoutMs() {
    if (g_mod_config.search_timeout_ms > 0) {
        return g_mod_config.search_timeout_ms;
    }
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return m1937::sdk::enemy_ai::tuning_for(
        ai, g_mod_config.difficulty).search_timeout_ms;
}

int ConfiguredInterceptDistance() {
    if (g_mod_config.intercept_distance > 0) {
        return g_mod_config.intercept_distance;
    }
    const int ai = UseEnhancedEnemyAI() ? g_mod_config.ai_level : 0;
    return m1937::sdk::enemy_ai::tuning_for(
        ai, g_mod_config.difficulty).intercept_distance;
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

bool PatchExecutableCall(
    unsigned char *address,
    const unsigned char *expected,
    const void *destination) {
    if (!address || !expected || !destination ||
        memcmp(address, expected, 5) != 0) {
        return false;
    }
    const auto from =
        reinterpret_cast<intptr_t>(address + 5);
    const auto to =
        reinterpret_cast<intptr_t>(destination);
    const auto relative = to - from;
    if (relative < INT32_MIN || relative > INT32_MAX) {
        return false;
    }
    unsigned char replacement[5] = {0xE8, 0, 0, 0, 0};
    const int32_t displacement =
        static_cast<int32_t>(relative);
    memcpy(replacement + 1, &displacement, sizeof(displacement));
    return PatchExecutableBytes(
        address, expected, replacement, sizeof(replacement));
}

using OriginalCrtRandProc = int(__cdecl *)();

void RecordCrtRandomTrace(
    void *caller_return_address,
    std::uintptr_t caller_esi,
    int value) {
    if (!g_crt_random_trace_enabled ||
        !g_crt_random_trace ||
        !g_executable_base ||
        !caller_return_address) {
        return;
    }
    const auto caller_return =
        reinterpret_cast<std::uintptr_t>(caller_return_address);
    const auto executable_base =
        reinterpret_cast<std::uintptr_t>(g_executable_base);
    if (caller_return < executable_base + 5) {
        return;
    }
    const auto call_site = caller_return - executable_base - 5;
    if (call_site > UINT32_MAX) {
        return;
    }
    const LONG index =
        InterlockedIncrement(&g_crt_random_trace_count) - 1;
    if (index < 0 || index >= kCrtRandomTraceCapacity) {
        InterlockedIncrement(&g_crt_random_trace_dropped);
        return;
    }
    auto &record = g_crt_random_trace[index];
    record.thread_id = GetCurrentThreadId();
    record.tick_ms = GetTickCount();
    record.call_site_rva =
        static_cast<std::uint32_t>(call_site);
    record.caller_esi =
        static_cast<std::uint32_t>(caller_esi);
    record.value = value;
    // Publish the record only after every payload field is complete.
    InterlockedExchange(&record.sequence, index + 1);
}

int __cdecl TracedCrtRand() {
    void *caller_return_address = _ReturnAddress();
    std::uintptr_t caller_esi = 0;
#if defined(_M_IX86)
    // Every recovered actor constructor/update keeps its RuntimeActorV1
    // pointer in ESI across the CRT rand() call. Capture the callee-saved
    // register before invoking the relocated original body; the test-only
    // startup summarizer joins it to the process-local actor table without
    // modifying game state or adding a second gameplay hook.
    __asm mov caller_esi, esi
#endif
    const int value = g_crt_rand_trampoline
        ? reinterpret_cast<OriginalCrtRandProc>(
              g_crt_rand_trampoline)()
        : 0;
    RecordCrtRandomTrace(
        caller_return_address, caller_esi, value);
    return value;
}

bool InstallCrtRandomTraceHook(unsigned char *base) {
    if (!g_crt_random_trace_enabled || !base) {
        return false;
    }
    static const unsigned char expected[] = {
        0xE8, 0xA7, 0x47, 0x00, 0x00};
    auto *entry = base + m1937::sdk::rva::crt_rand;
    if (memcmp(entry, expected, sizeof(expected)) != 0) {
        return false;
    }

    // The first instruction calls the CRT thread-data accessor. Relocate that
    // relative CALL before jumping back to entry+5; copying its original
    // displacement verbatim would target the wrong address from VirtualAlloc.
    int32_t original_call_displacement = 0;
    memcpy(
        &original_call_displacement,
        expected + 1,
        sizeof(original_call_displacement));
    auto *original_call_target =
        entry + sizeof(expected) + original_call_displacement;
    constexpr size_t trampoline_size = 10;
    auto *trampoline = static_cast<unsigned char *>(VirtualAlloc(
        nullptr, trampoline_size, MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE));
    if (!trampoline) {
        return false;
    }
    trampoline[0] = 0xE8;
    const auto call_relative =
        reinterpret_cast<intptr_t>(original_call_target) -
        reinterpret_cast<intptr_t>(trampoline + 5);
    trampoline[5] = 0xE9;
    const auto resume_relative =
        reinterpret_cast<intptr_t>(entry + sizeof(expected)) -
        reinterpret_cast<intptr_t>(
            trampoline + trampoline_size);
    if (call_relative < INT32_MIN ||
        call_relative > INT32_MAX ||
        resume_relative < INT32_MIN ||
        resume_relative > INT32_MAX) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    const int32_t call_displacement =
        static_cast<int32_t>(call_relative);
    const int32_t resume_displacement =
        static_cast<int32_t>(resume_relative);
    memcpy(
        trampoline + 1,
        &call_displacement,
        sizeof(call_displacement));
    memcpy(
        trampoline + 6,
        &resume_displacement,
        sizeof(resume_displacement));
    FlushInstructionCache(
        GetCurrentProcess(), trampoline, trampoline_size);

    g_crt_rand_trampoline = trampoline;
    if (!PatchExecutableJump(
            entry, expected, sizeof(expected),
            reinterpret_cast<const void *>(&TracedCrtRand))) {
        g_crt_rand_trampoline = nullptr;
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    return true;
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

int FinalizeMenuCommand(int command) {
    if (command != 1 || !g_executable_base) {
        return command;
    }
    const int mission = *reinterpret_cast<int *>(
        g_executable_base + m1937::sdk::rva::current_mission);
    if (mission == 0) {
        const auto *route = RequestedBriefingRoute();
        if (route) {
            // Keep the original synchronous briefing screen and its original
            // click/Enter continuation path. Only the GFL picture payload (or
            // the extension-level resource name) is replaced with text art.
            RecordDiagnostic(
                "legacy_briefing", "original_text_asset", route->id);
            ArmExtensionBriefingContinuation(route);
        }
        FlushDiagnostics();
    }
    return command;
}

int __fastcall AutoStartMenuPoll(
    void *menu, void *, int animation_state, int flags) {
    if (IsAutomatedLaunchEnabled() && g_executable_base &&
        *reinterpret_cast<int *>(
            g_executable_base + m1937::sdk::rva::current_mission) == 0 &&
        InterlockedCompareExchange(&g_auto_start_consumed, 1, 0) == 0) {
        // Button identifier 1 is the original Start Game entry. Returning it
        // here follows the exact normal menu path instead of fabricating a
        // mission state or relying on physical mouse coordinates.
        return FinalizeMenuCommand(1);
    }
    if (IsWindowReplayEnabled()) {
        const LONG command =
            InterlockedExchange(&g_replay_menu_command, 0);
        if (command > 0 && command <= 64) {
            const char *stage = "ui_action";
            if (command == 7) {
                stage = "save";
            } else if (command == 17) {
                stage = "load";
            } else if (command == 42) {
                stage = "failure";
            } else if (command == 43) {
                stage = "victory";
            }
            if ((command == 7 || command == 17) &&
                g_executable_base) {
                // Regression uses a disposable runtime and an isolated slot.
                // The original menu normally chooses this value before it
                // returns 7/17; window replay has no global mouse with which
                // to click that selector, so prime slot zero only here.
                *reinterpret_cast<int *>(
                    g_executable_base +
                    m1937::sdk::rva::selected_save_slot) = 0;
            }
            if (command == 17 || command == 42 || command == 43) {
                // These transitions destroy or replace world objects even if
                // the numeric mission remains unchanged. Never carry actor
                // addresses from the old world into the new one.
                ClearEnhancedSearchStates();
                g_ai_actor_table = 0;
            }
            RecordDiagnostic(
                "window_replay_transition", "dispatched", stage);
            FlushDiagnostics();
            return FinalizeMenuCommand(static_cast<int>(command));
        }
    }
    if (!g_menu_poll_trampoline) {
        return 0;
    }
    return FinalizeMenuCommand(
        reinterpret_cast<OriginalMenuPollProc>(g_menu_poll_trampoline)(
            menu, animation_state, flags));
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

bool IsReadableRange(const void *address, size_t size) {
    if (!address || size == 0) {
        return false;
    }
    MEMORY_BASIC_INFORMATION information{};
    if (VirtualQuery(
            address, &information, sizeof(information)) !=
        sizeof(information)) {
        return false;
    }
    if (information.State != MEM_COMMIT ||
        (information.Protect & (PAGE_NOACCESS | PAGE_GUARD)) != 0) {
        return false;
    }
    const auto start = reinterpret_cast<std::uintptr_t>(address);
    const auto region = reinterpret_cast<std::uintptr_t>(
        information.BaseAddress);
    return start >= region &&
        start + size >= start &&
        start + size <= region + information.RegionSize;
}

m1937::sdk::RuntimeWorldV1 *RuntimeWorld() {
    if (!g_executable_base) {
        return nullptr;
    }
    const std::uint32_t address = *reinterpret_cast<std::uint32_t *>(
        g_executable_base + m1937::sdk::rva::world_root);
    auto *world = reinterpret_cast<m1937::sdk::RuntimeWorldV1 *>(
        static_cast<std::uintptr_t>(address));
    return IsReadableRange(world, sizeof(*world)) ? world : nullptr;
}

bool RuntimeActors(
    m1937::sdk::RuntimeActorV1 ***actors, int *count) {
    if (!actors || !count) {
        return false;
    }
    auto *world = RuntimeWorld();
    if (!world || world->actor_count <= 0 ||
        world->actor_count > 4096 ||
        world->actor_array_address == 0) {
        return false;
    }
    auto **array = reinterpret_cast<m1937::sdk::RuntimeActorV1 **>(
        static_cast<std::uintptr_t>(world->actor_array_address));
    if (!IsReadableRange(
            array,
            static_cast<size_t>(world->actor_count) *
                sizeof(std::uint32_t))) {
        return false;
    }
    *actors = array;
    *count = world->actor_count;
    return true;
}

void DirectionVector(int direction, int *x, int *y) {
    static const int dx[] = {0, 0, 1, 1, 1, 0, -1, -1, -1};
    static const int dy[] = {0, -1, -1, 0, 1, 1, 1, 0, -1};
    const int index = direction >= 1 && direction <= 8 ? direction : 1;
    if (x) {
        *x = dx[index];
    }
    if (y) {
        *y = dy[index];
    }
}

EnhancedSearchState *FindSearchState(
    m1937::sdk::RuntimeActorV1 *actor, bool create) {
    const auto address = reinterpret_cast<std::uintptr_t>(actor);
    EnhancedSearchState *empty = nullptr;
    for (auto &state : g_search_states) {
        if (state.actor == address) {
            return &state;
        }
        if (!empty && state.actor == 0) {
            empty = &state;
        }
    }
    if (!create || !empty) {
        return nullptr;
    }
    *empty = EnhancedSearchState{};
    empty->actor = address;
    return empty;
}

void AssignSearchGoal(
    m1937::sdk::RuntimeActorV1 *actor, int x, int y) {
    if (!actor || !IsReadableRange(actor, sizeof(*actor))) {
        return;
    }
    actor->goal_kind = 1;
    actor->goal_x = x;
    actor->goal_y = y;
    actor->command_variant = 1;
    actor->command_pending = 1;
    actor->search_or_return_active = 1;
    actor->movement_active = 1;
}

void ClearEnhancedSearchStates() {
    memset(g_search_states, 0, sizeof(g_search_states));
}

void RetainSearchStatesInActorTable(
    m1937::sdk::RuntimeActorV1 **actors,
    int actor_count) {
    for (auto &state : g_search_states) {
        if (state.actor == 0) {
            continue;
        }
        bool retained = false;
        for (int index = 0; index < actor_count; ++index) {
            if (reinterpret_cast<std::uintptr_t>(actors[index]) ==
                state.actor) {
                retained = true;
                break;
            }
        }
        if (!retained) {
            state = EnhancedSearchState{};
        }
    }
}

bool StartEnhancedSearch(
    m1937::sdk::RuntimeActorV1 *actor,
    int anchor_x, int anchor_y, int direction,
    bool intercept, int first_x, int first_y) {
    auto *state = FindSearchState(actor, false);
    // A last-known observation is immutable for the lifetime of its bounded
    // search. Crowded missions can propagate the same alarm every frame; if
    // those repeats reset started_at, the timeout never expires and the
    // nearest guards remain permanently commandeered. Preserve the active
    // search until it completes, times out or the original engine reacquires
    // a target.
    if (state && state->started_at != 0) {
        return false;
    }
    state = FindSearchState(actor, true);
    if (!state) {
        return false;
    }
    state->anchor_x = anchor_x;
    state->anchor_y = anchor_y;
    state->direction = direction;
    state->next_point = 0;
    state->point_count =
        ClampSetting(ConfiguredSearchPoints(), 0, 4);
    state->started_at = GetTickCount();
    state->last_progress_at = state->started_at;
    state->last_actor_x = actor->world_x;
    state->last_actor_y = actor->world_y;
    const int reaction_delay = ConfiguredReactionDelayMs();
    state->activation_at =
        state->started_at + static_cast<DWORD>(reaction_delay);
    state->pending_goal_x = first_x;
    state->pending_goal_y = first_y;
    state->pending_activation = reaction_delay > 0;
    state->intercept_assigned = intercept;
    if (!state->pending_activation) {
        AssignSearchGoal(actor, first_x, first_y);
    }
    InterlockedIncrement(&g_telemetry.ai_searches_started);
    return true;
}

using OriginalAlertPropagationProc =
    int(__thiscall *)(m1937::sdk::RuntimeActorV1 *, int);
using ActorDistanceProc =
    int(__thiscall *)(
        m1937::sdk::RuntimeActorV1 *,
        m1937::sdk::RuntimeActorV1 *);
using AlertEffectiveRadiusProc =
    int(__thiscall *)(
        m1937::sdk::RuntimeActorV1 *,
        m1937::sdk::RuntimeActorV1 *, int);

int __fastcall EnhancedAlertPropagation(
    m1937::sdk::RuntimeActorV1 *source, void *, int radius) {
    if (!UseEnhancedEnemyAI() || !source || !g_executable_base) {
        return g_alert_propagation_trampoline
            ? reinterpret_cast<OriginalAlertPropagationProc>(
                  g_alert_propagation_trampoline)(source, radius)
            : 0;
    }
    m1937::sdk::RuntimeActorV1 **actors = nullptr;
    int actor_count = 0;
    if (!RuntimeActors(&actors, &actor_count) ||
        !IsReadableRange(source, sizeof(*source))) {
        return 0;
    }
    const auto distance_proc =
        reinterpret_cast<ActorDistanceProc>(
            g_executable_base + m1937::sdk::rva::actor_distance);
    const auto effective_radius_proc =
        reinterpret_cast<AlertEffectiveRadiusProc>(
            g_executable_base +
            m1937::sdk::rva::alert_effective_radius);
    constexpr int maximum_candidates = 1024;
    m1937::sdk::enemy_ai::Candidate candidates[maximum_candidates]{};
    int candidate_count = 0;
    const int limit = ConfiguredMaxReinforcements();
    for (int index = 0; index < actor_count; ++index) {
        auto *candidate = actors[index];
        if (!candidate || candidate == source ||
            !IsReadableRange(candidate, sizeof(*candidate)) ||
            candidate->faction_id != 1 ||
            candidate->runtime_type == 91 ||
            candidate->dead_or_disabled != 0 ||
            (candidate->contact_state == 1 &&
             candidate->target_lost != 1)) {
            continue;
        }
        const int distance = distance_proc(source, candidate);
        const int effective =
            effective_radius_proc(source, candidate, radius);
        if (distance >= effective) {
            continue;
        }
        if (candidate_count < maximum_candidates)
            candidates[candidate_count++] = {
                reinterpret_cast<std::uintptr_t>(candidate),
                distance,
                true};
    }
    std::uintptr_t selected[4]{};
    const int selected_count = static_cast<int>(
        m1937::sdk::enemy_ai::select_reinforcements(
            candidates,
            static_cast<std::size_t>(candidate_count),
            selected,
            sizeof(selected) / sizeof(selected[0]),
            limit));

    auto *target = reinterpret_cast<m1937::sdk::RuntimeActorV1 *>(
        static_cast<std::uintptr_t>(source->target_actor_address));
    const bool target_is_valid =
        target && IsReadableRange(target, sizeof(*target));
    const bool use_source_position =
        source->faction_id == 3 || !target_is_valid;
    const int anchor_x =
        use_source_position ? source->world_x : target->world_x;
    const int anchor_y =
        use_source_position ? source->world_y : target->world_y;
    const int direction =
        target_is_valid ? target->facing_direction
                        : source->facing_direction;
    const int intercept_distance = ConfiguredInterceptDistance();
    const m1937::sdk::enemy_ai::LastKnownObservation observation{
        anchor_x, anchor_y, direction, GetTickCount()};
    const auto tuning = m1937::sdk::enemy_ai::Tuning{
        0, limit, ConfiguredSearchPoints(),
        ConfiguredSearchTimeoutMs(), intercept_distance};
    m1937::sdk::enemy_ai::Point search_points[4]{};
    const auto search_point_count =
        m1937::sdk::enemy_ai::build_search_pattern(
            observation, tuning, search_points,
            sizeof(search_points) / sizeof(search_points[0]));

    int searches_started = 0;
    for (int index = 0; index < selected_count; ++index) {
        auto *candidate =
            reinterpret_cast<m1937::sdk::RuntimeActorV1 *>(
                selected[index]);
        int goal_x = anchor_x;
        int goal_y = anchor_y;
        bool intercept = false;
        if (index > 0 &&
            static_cast<std::size_t>(index - 1) <
                search_point_count) {
            goal_x = search_points[index - 1].x;
            goal_y = search_points[index - 1].y;
            intercept = index == 1;
        }
        if (StartEnhancedSearch(
                candidate, anchor_x, anchor_y, direction,
                intercept, goal_x, goal_y)) {
            candidate->interest_actor_address = 0;
            if (intercept) {
                InterlockedIncrement(&g_telemetry.ai_intercepts);
            }
            ++searches_started;
        }
    }
    if (selected_count > 0) {
        source->search_delay_counter = 0;
        source->search_delay_limit = rand() % 40 + 40;
        source->reaction_state = 0;
        source->path_override_active = 0;
    }
    InterlockedIncrement(&g_telemetry.ai_alerts);
    InterlockedExchangeAdd(
        &g_telemetry.ai_reinforcements, searches_started);
    return 1;
}

bool InstallAlertPropagationHook(unsigned char *base) {
    static const unsigned char expected[] = {
        0x51, 0x56, 0x8B, 0xF1, 0x8B,
        0x0D, 0x0C, 0x70, 0x4E, 0x00};
    auto *entry = base + m1937::sdk::rva::alert_propagation;
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
    const intptr_t relative =
        reinterpret_cast<intptr_t>(entry + sizeof(expected)) -
        reinterpret_cast<intptr_t>(trampoline + trampoline_size);
    if (relative < INT32_MIN || relative > INT32_MAX) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    const int32_t displacement = static_cast<int32_t>(relative);
    memcpy(
        trampoline + sizeof(expected) + 1,
        &displacement, sizeof(displacement));
    FlushInstructionCache(
        GetCurrentProcess(), trampoline, trampoline_size);
    g_alert_propagation_trampoline = trampoline;
    if (!PatchExecutableJump(
            entry, expected, sizeof(expected),
            reinterpret_cast<const void *>(
                &EnhancedAlertPropagation))) {
        g_alert_propagation_trampoline = nullptr;
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    return true;
}

void AdvanceEnhancedSearchPoint(
    m1937::sdk::RuntimeActorV1 *actor,
    EnhancedSearchState *state) {
    if (!actor || !state ||
        state->next_point >= state->point_count) {
        if (state) {
            *state = EnhancedSearchState{};
            InterlockedIncrement(
                &g_telemetry.ai_search_completed);
        }
        return;
    }
    const m1937::sdk::enemy_ai::LastKnownObservation observation{
        state->anchor_x, state->anchor_y,
        state->direction, state->started_at};
    const auto tuning = m1937::sdk::enemy_ai::Tuning{
        0, ConfiguredMaxReinforcements(),
        ConfiguredSearchPoints(), ConfiguredSearchTimeoutMs(),
        ConfiguredInterceptDistance()};
    m1937::sdk::enemy_ai::Point points[4]{};
    const auto count = m1937::sdk::enemy_ai::build_search_pattern(
        observation, tuning, points,
        sizeof(points) / sizeof(points[0]));
    if (state->next_point >= static_cast<int>(count)) {
        *state = EnhancedSearchState{};
        InterlockedIncrement(
            &g_telemetry.ai_search_completed);
        return;
    }
    const int goal_x = points[state->next_point].x;
    const int goal_y = points[state->next_point].y;
    ++state->next_point;
    state->last_progress_at = GetTickCount();
    AssignSearchGoal(actor, goal_x, goal_y);
    InterlockedIncrement(&g_telemetry.ai_search_replans);
}

void TickEnhancedEnemyAI() {
    if (!UseEnhancedEnemyAI() || !g_executable_base) {
        return;
    }
    const DWORD now = GetTickCount();
    const DWORD previous = static_cast<DWORD>(
        InterlockedCompareExchange(&g_last_ai_tick, 0, 0));
    if (now - previous <
        static_cast<DWORD>(g_mod_config.ai_tick_interval_ms)) {
        return;
    }
    if (InterlockedCompareExchange(
            &g_last_ai_tick, static_cast<LONG>(now),
            static_cast<LONG>(previous)) != static_cast<LONG>(previous)) {
        return;
    }
    const LONGLONG started = PerformanceCounterNow();
    const int mission = *reinterpret_cast<int *>(
        g_executable_base + m1937::sdk::rva::current_mission);
    m1937::sdk::RuntimeActorV1 **current_actors = nullptr;
    int current_actor_count = 0;
    const bool has_world =
        RuntimeActors(&current_actors, &current_actor_count);
    const auto current_actor_table =
        has_world
            ? reinterpret_cast<std::uintptr_t>(current_actors)
            : 0;
    if (mission != g_ai_last_mission) {
        ClearEnhancedSearchStates();
        g_ai_last_mission = mission;
    } else if (current_actor_table != g_ai_actor_table) {
        // Several original missions resize/reallocate the actor pointer table
        // while keeping the actor objects alive. Clearing every search on a
        // table-address change starves its timeout under repeated alarms.
        // Retain only pointers that are still present in the new table.
        if (has_world) {
            RetainSearchStatesInActorTable(
                current_actors, current_actor_count);
        } else {
            ClearEnhancedSearchStates();
        }
    }
    g_ai_actor_table = current_actor_table;
    const int timeout = ConfiguredSearchTimeoutMs();
    for (auto &state : g_search_states) {
        if (state.actor == 0) {
            continue;
        }
        auto *actor =
            reinterpret_cast<m1937::sdk::RuntimeActorV1 *>(state.actor);
        if (!IsReadableRange(actor, sizeof(*actor))) {
            state = EnhancedSearchState{};
            continue;
        }
        // Some missions temporarily mark an actor disabled while changing
        // scripted state. Dropping the search immediately lets the next
        // repeated alarm recreate it from zero forever. Keep the immutable
        // observation and allow its normal timeout to retire the state.
        if (actor->dead_or_disabled != 0) {
            if (timeout > 0 &&
                now - state.started_at >=
                    static_cast<DWORD>(timeout)) {
                state = EnhancedSearchState{};
                InterlockedIncrement(
                    &g_telemetry.ai_escape_timeouts);
            }
            continue;
        }
        if (state.pending_activation) {
            if (now < state.activation_at) {
                continue;
            }
            AssignSearchGoal(
                actor,
                state.pending_goal_x,
                state.pending_goal_y);
            state.pending_activation = false;
            const LONG reaction_ms = static_cast<LONG>(
                now - state.started_at);
            InterlockedIncrement(
                &g_telemetry.ai_reaction_samples);
            InterlockedExchangeAdd(
                &g_telemetry.ai_reaction_total_ms,
                reaction_ms);
            UpdateMaximum(
                &g_telemetry.ai_reaction_max_ms,
                reaction_ms);
            continue;
        }
        // Once the original engine reacquires a target, it owns the actor
        // again. No target coordinates are sampled by this coordinator.
        if (actor->target_actor_address != 0 &&
            actor->target_lost == 0) {
            state = EnhancedSearchState{};
            InterlockedIncrement(
                &g_telemetry.ai_reacquisitions);
            continue;
        }
        if (timeout > 0 && now - state.started_at >=
            static_cast<DWORD>(timeout)) {
            state = EnhancedSearchState{};
            InterlockedIncrement(&g_telemetry.ai_escape_timeouts);
            continue;
        }
        if (actor->world_x != state.last_actor_x ||
            actor->world_y != state.last_actor_y) {
            state.last_actor_x = actor->world_x;
            state.last_actor_y = actor->world_y;
            state.last_progress_at = now;
        }
        const long long delta_x =
            static_cast<long long>(actor->world_x) -
            actor->goal_x;
        const long long delta_y =
            static_cast<long long>(actor->world_y) -
            actor->goal_y;
        const bool arrived =
            delta_x * delta_x + delta_y * delta_y <= 32LL * 32LL;
        const bool path_stalled =
            now - state.last_progress_at >= 1800;
        if (arrived || path_stalled) {
            AdvanceEnhancedSearchPoint(actor, &state);
        }
    }
    AddTiming(
        &g_telemetry.ai_ticks,
        &g_telemetry.ai_tick_microseconds,
        &g_telemetry.ai_tick_max_microseconds,
        started);
}

using ActorMovementProc =
    void(__thiscall *)(m1937::sdk::RuntimeActorV1 *);

// This wrapper replaces only the first cleanup CALL in command-dispatch case
// 1. At this exact point the original code has established that the queued
// ground cell differs from the resolved cell, but has not overwritten the
// resolved destination or rebuilt A*. Synchronizing the cached navigation
// origin and clearing an active player path here makes the remainder of the
// original case rebuild its waypoints and facing in one coherent update.
void __fastcall ResetPlayerPathBeforeGroundCommand(
    m1937::sdk::RuntimeActorV1 *actor, void *) {
    if (actor && g_executable_base &&
        IsReadableRange(actor, sizeof(*actor)) &&
        actor->faction_id == 3 &&
        actor->dead_or_disabled == 0) {
        // Extension missions redeploy the serialized actor's world vector,
        // while the legacy loader can retain the source mission's cached
        // navigation cell at +0x108/+0x110. The movement routine steers from
        // those cached cells, so a mismatch makes the sprite run away from
        // the clicked goal. Re-derive exactly as sub_455E30 does.
        actor->navigation_cell_x = actor->world_x / 32;
        actor->navigation_height_cell =
            actor->world_height / 16;
        actor->navigation_cell_y = actor->world_y / 16;
        reinterpret_cast<ActorMovementProc>(
            g_executable_base +
            m1937::sdk::rva::reset_actor_movement)(actor);
        InterlockedIncrement(
            &g_telemetry.player_ground_reroutes);
    }
    if (actor && g_executable_base) {
        reinterpret_cast<ActorMovementProc>(
            g_executable_base +
            m1937::sdk::rva::clear_actor_command_targets)(actor);
    }
}

bool InstallPlayerGroundRedirectFix(unsigned char *base) {
    static const unsigned char expected[] = {
        0xE8, 0x5A, 0x36, 0x00, 0x00};
    return PatchExecutableCall(
        base +
            m1937::sdk::rva::player_ground_command_reset_call,
        expected,
        reinterpret_cast<const void *>(
            &ResetPlayerPathBeforeGroundCommand));
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

using WindowQueryProc = HWND(WINAPI *)();
WindowQueryProc g_real_game_get_foreground_window = nullptr;
WindowQueryProc g_real_game_get_focus = nullptr;
WindowQueryProc g_real_game_get_active_window = nullptr;

HWND WINAPI AutomatedGameGetForegroundWindow() {
    return g_game_window
        ? g_game_window
        : (g_real_game_get_foreground_window
            ? g_real_game_get_foreground_window()
            : nullptr);
}

HWND WINAPI AutomatedGameGetFocus() {
    return g_game_window
        ? g_game_window
        : (g_real_game_get_focus ? g_real_game_get_focus() : nullptr);
}

HWND WINAPI AutomatedGameGetActiveWindow() {
    return g_game_window
        ? g_game_window
        : (g_real_game_get_active_window
            ? g_real_game_get_active_window()
            : nullptr);
}

bool PatchWindowQueryImport(
    unsigned char *base,
    std::uintptr_t slot_rva,
    const char *name,
    void *replacement,
    WindowQueryProc *original) {
    if (!base || !name || !replacement || !original) {
        return false;
    }
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    auto expected = user32
        ? reinterpret_cast<void *>(GetProcAddress(user32, name))
        : nullptr;
    auto **slot = reinterpret_cast<void **>(base + slot_rva);
    // cnc-ddraw may already wrap these imports before the proxy initializes.
    // The executable identity and cataloged IAT slot still provide the guard;
    // accept either USER32's pointer or its existing non-null local wrapper.
    if (!expected || !*slot) {
        return false;
    }
    DWORD previous = 0;
    if (!VirtualProtect(
            slot, sizeof(*slot), PAGE_READWRITE, &previous)) {
        return false;
    }
    *original = reinterpret_cast<WindowQueryProc>(*slot);
    *slot = replacement;
    DWORD ignored = 0;
    VirtualProtect(slot, sizeof(*slot), previous, &ignored);
    FlushInstructionCache(GetCurrentProcess(), slot, sizeof(*slot));
    return true;
}

bool InstallAutomatedForegroundQueryHooks(unsigned char *base) {
    if (!IsWindowReplayEnabled()) {
        return false;
    }
    const bool foreground = PatchWindowQueryImport(
        base,
        m1937::sdk::rva::get_foreground_window_iat,
        "GetForegroundWindow",
        reinterpret_cast<void *>(&AutomatedGameGetForegroundWindow),
        &g_real_game_get_foreground_window);
    const bool focus = PatchWindowQueryImport(
        base,
        m1937::sdk::rva::get_focus_iat,
        "GetFocus",
        reinterpret_cast<void *>(&AutomatedGameGetFocus),
        &g_real_game_get_focus);
    const bool active = PatchWindowQueryImport(
        base,
        m1937::sdk::rva::get_active_window_iat,
        "GetActiveWindow",
        reinterpret_cast<void *>(&AutomatedGameGetActiveWindow),
        &g_real_game_get_active_window);
    return foreground && focus && active;
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
    if (g_crt_random_trace_enabled) {
        RecordDiagnostic(
            "crt_random_trace",
            InstallCrtRandomTraceHook(base)
                ? "process_local"
                : "rejected",
            "memory_ring_async_writer");
    }
    if (IsWindowReplayEnabled()) {
        RecordDiagnostic(
            "autotest_window_queries",
            InstallAutomatedForegroundQueryHooks(base)
                ? "process_local"
                : "rejected",
            "no_system_focus_change");
    }
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
    if (IsAutomatedLaunchEnabled() ||
        RequiresExtensionBriefingContinuation()) {
        RecordDiagnostic(
            "menu_command_hook",
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
    // The selector-to-engine mapping and optional fixed-length VWF/briefing
    // resource redirects come from SDK/mission-routes.json. A normal launch
    // keeps the original first-mission behavior. The first twelve Intro_*.psd
    // GFL payloads are text-rendered pictures, while extension missions point
    // their reused engine slot at a unique appended Brief_*.psd resource.
    // Every address is signature-checked before the route is changed.
    const int requested_level = RequestedStartLevel();
    const auto *route = m1937::sdk::find_mission_route(requested_level);
    if (route) {
        const size_t vwf_size = strlen(route->vwf_name) + 1;
        auto *level_address =
            base + m1937::sdk::rva::new_game_level_immediate;
        auto *redirect_address = route->redirect_rva == 0
            ? nullptr
            : base + route->redirect_rva;
        unsigned char *briefing_address = nullptr;
        const char *briefing_expected = nullptr;
        const char *briefing_replacement = nullptr;
        if (route->selector_level == 13) {
            briefing_address =
                base + m1937::sdk::rva::intro_11_resource_name;
            briefing_expected = "Intro_011.psd";
            briefing_replacement = "Brief_012.psd";
        } else if (route->selector_level == 14) {
            briefing_address =
                base + m1937::sdk::rva::intro_6_resource_name;
            briefing_expected = "Intro_006.psd";
            briefing_replacement = "Brief_013.psd";
        } else if (route->selector_level == 15) {
            briefing_address =
                base + m1937::sdk::rva::intro_6_resource_name;
            briefing_expected = "Intro_006.psd";
            briefing_replacement = "Brief_014.psd";
        }
        const size_t briefing_size = briefing_expected
            ? strlen(briefing_expected) + 1
            : 0;
        const int original_level = 1;
        const bool level_matches =
            memcmp(level_address, &original_level, sizeof(original_level)) == 0;
        const bool redirect_matches =
            !redirect_address ||
            (strlen(route->redirect_expected) + 1 == vwf_size &&
             memcmp(
                 redirect_address, route->redirect_expected, vwf_size) == 0);
        const bool briefing_matches =
            !briefing_address ||
            (strlen(briefing_replacement) + 1 == briefing_size &&
             memcmp(
                 briefing_address,
                 briefing_expected,
                 briefing_size) == 0);
        const bool file_exists =
            !route->requires_file ||
            GetFileAttributesA(route->vwf_name) != INVALID_FILE_ATTRIBUTES;

        if (level_matches && redirect_matches &&
            briefing_matches && file_exists) {
            const bool redirected =
                !redirect_address ||
                PatchExecutableBytes(
                    redirect_address,
                    reinterpret_cast<const unsigned char *>(
                        route->redirect_expected),
                    reinterpret_cast<const unsigned char *>(route->vwf_name),
                    vwf_size);
            const bool briefing_redirected =
                redirected &&
                (!briefing_address ||
                 PatchExecutableBytes(
                     briefing_address,
                     reinterpret_cast<const unsigned char *>(
                         briefing_expected),
                     reinterpret_cast<const unsigned char *>(
                         briefing_replacement),
                     briefing_size));
            const bool level_patched =
                briefing_redirected &&
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
            if (!level_patched &&
                briefing_address && briefing_redirected) {
                PatchExecutableBytes(
                    briefing_address,
                    reinterpret_cast<const unsigned char *>(
                        briefing_replacement),
                    reinterpret_cast<const unsigned char *>(
                        briefing_expected),
                    briefing_size);
            }
            RecordDiagnostic(
                "mission_route",
                level_patched ? "enabled" : "rolled_back",
                route->id);
        } else {
            RecordDiagnostic(
                "mission_route", "original",
                !file_exists
                    ? "missing_vwf"
                    : (!briefing_matches
                        ? "briefing_signature_guard"
                        : "signature_guard"));
        }
    }

    if (g_mod_config.enabled) {
        RecordDiagnostic(
            "player_ground_redirect",
            InstallPlayerGroundRedirectFix(base)
                ? "enabled"
                : "original",
            "case1_pre_path_rebuild");
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
        const bool alert_hook =
            UseEnhancedEnemyAI() &&
            InstallAlertPropagationHook(base);
        RecordDiagnostic(
            "enemy_coordination",
            alert_hook ? "enabled" : "original",
            alert_hook
                ? "bounded_last_known_search"
                : "signature_or_ai_disabled");
    }
}

void HandleWindowReplayMessage(const MSG &message) {
    if (!IsWindowReplayEnabled()) {
        return;
    }
    const int argument = static_cast<int>(message.lParam);
    bool input_command = false;
    switch (message.wParam) {
    case replay_key_down:
        if (argument >= 0 && argument < 256) {
            g_replay_keyboard[argument] = 0x80;
            input_command = true;
        }
        break;
    case replay_key_up:
        if (argument >= 0 && argument < 256) {
            g_replay_keyboard[argument] = 0;
            input_command = true;
        }
        break;
    case replay_mouse_delta:
        g_replay_mouse.lX +=
            static_cast<short>(LOWORD(message.lParam));
        g_replay_mouse.lY +=
            static_cast<short>(HIWORD(message.lParam));
        input_command = true;
        break;
    case replay_mouse_button_down:
        if (argument >= 0 && argument < 4) {
            g_replay_mouse.rgbButtons[argument] = 0x80;
            input_command = true;
        }
        break;
    case replay_mouse_button_up:
        if (argument >= 0 && argument < 4) {
            g_replay_mouse.rgbButtons[argument] = 0;
            input_command = true;
        }
        break;
    case replay_menu_command:
        if (argument > 0 && argument <= 64) {
            InterlockedExchange(
                &g_replay_menu_command,
                static_cast<LONG>(argument));
        }
        break;
    case replay_clear:
        memset(g_replay_keyboard, 0, sizeof(g_replay_keyboard));
        memset(&g_replay_mouse, 0, sizeof(g_replay_mouse));
        InterlockedExchange(&g_replay_menu_command, 0);
        InterlockedExchange(&g_replay_world_item_id, 0);
        InterlockedExchange(&g_replay_world_item_spawn_pending, 0);
        InterlockedExchange(&g_replay_inventory_seed_pending, 0);
        InterlockedExchange(
            &g_replay_disguise_transition_pending, 0);
        InterlockedExchange(
            &g_replay_weapon_selection_pending, 0);
        InterlockedExchange(
            &g_replay_special_attention_commit_pending, 0);
        break;
    case replay_ai_alert: {
        m1937::sdk::RuntimeActorV1 **actors = nullptr;
        int actor_count = 0;
        bool raised = false;
        if (RuntimeActors(&actors, &actor_count)) {
            for (int index = 0; index < actor_count; ++index) {
                auto *actor = actors[index];
                if (!actor ||
                    !IsReadableRange(actor, sizeof(*actor)) ||
                    actor->faction_id != 1 ||
                    actor->dead_or_disabled != 0)
                    continue;
                raised = EnhancedAlertPropagation(
                    actor, nullptr, ConfiguredAlertRadius()) != 0;
                break;
            }
        }
        RecordDiagnostic(
            "replay_ai_alert",
            raised ? "raised" : "unavailable",
            "isolated_probe_only");
        break;
    }
    case replay_camera_center: {
        // Isolated regression probes need to click faithful world coordinates
        // that may begin outside the current 1024x768 viewport. The command is
        // unavailable unless the opt-in window replay channel is enabled, and
        // it changes only this test process' original viewport controller.
        auto **controller_slot =
            reinterpret_cast<m1937::sdk::RuntimeViewportControllerV1 **>(
                g_executable_base +
                m1937::sdk::rva::viewport_controller);
        auto *controller =
            IsReadableRange(controller_slot, sizeof(*controller_slot))
                ? *controller_slot
                : nullptr;
        bool centered = false;
        if (controller &&
            IsReadableRange(controller, sizeof(*controller)) &&
            controller->viewport_width > 0 &&
            controller->viewport_height > 0 &&
            controller->world_width >= controller->viewport_width &&
            controller->world_height >= controller->viewport_height) {
            const int world_x =
                static_cast<unsigned short>(LOWORD(message.lParam));
            const int world_y =
                static_cast<unsigned short>(HIWORD(message.lParam));
            auto *controller_fields =
                reinterpret_cast<std::int32_t *>(controller);
            // sub_44A870 clamps against this[10]-this[8] and
            // this[11]-this[9]. The public +0x28/+0x2C values are right and
            // bottom bounds, not reliable spans when a mission has a
            // non-zero viewport origin (m009 uses 302 horizontal pixels).
            const int viewport_span_width =
                controller_fields[10] - controller_fields[8];
            const int viewport_span_height =
                controller_fields[11] - controller_fields[9];
            if (viewport_span_width <= 0 || viewport_span_height <= 0 ||
                controller->world_width < viewport_span_width ||
                controller->world_height < viewport_span_height)
                break;
            const int camera_left = std::clamp(
                world_x - controller->viewport_width / 2,
                0,
                controller->world_width - viewport_span_width);
            const int camera_top = std::clamp(
                world_y - controller->viewport_height / 2,
                0,
                controller->world_height - viewport_span_height);
            using SetCameraOriginFn = int(__thiscall *)(
                m1937::sdk::RuntimeViewportControllerV1 *, int, int);
            auto set_camera_origin =
                reinterpret_cast<SetCameraOriginFn>(
                    g_executable_base +
                    m1937::sdk::rva::set_camera_origin);
            // sub_44A870 is the original camera setter. Besides updating the
            // public bounds it calls the terrain, foreground and auxiliary
            // viewport scroll hooks, preventing mixed old/new layer caches.
            // This isolated replay command never moves the system cursor.
            // A horizontal-only jump can take the legacy strip renderer's
            // incremental path and retain unloaded rows (notably mission
            // m009). Prime the requested X at an alternate Y first; the
            // original setter then refreshes both scroll axes before the
            // final exact origin.
            int prime_top = 0;
            if (camera_top == 0 && controller->world_height > 1) {
                prime_top = controller->viewport_height / 2;
                if (prime_top < 1)
                    prime_top = 1;
                if (prime_top >= controller->world_height)
                    prime_top = controller->world_height - 1;
            }
            if (prime_top != camera_top)
                set_camera_origin(controller, camera_left, prime_top);
            set_camera_origin(controller, camera_left, camera_top);
            centered =
                controller->camera_left == camera_left &&
                controller->camera_top == camera_top;
        }
        RecordDiagnostic(
            "replay_camera",
            centered ? "centered" : "unavailable",
            "isolated_probe_only");
        break;
    }
    case replay_seed_world_item: {
        // This command exists only inside the opt-in, automated-probe replay
        // channel. It never alters player input or the system cursor. A
        // second command supplies a bounded world point and asks the original
        // sub_44A350 factory to create the authentic runtime actor; all
        // scanning, acceptance, transfer and effect logic remains original.
        const bool supported =
            argument == m1937::sdk::world_item::chicken ||
            argument == m1937::sdk::world_item::canned_meat ||
            argument == m1937::sdk::world_item::hypnosis_doll ||
            argument == m1937::sdk::world_item::poisoned_wine ||
            argument == m1937::sdk::world_item::dog_bone ||
            argument == m1937::sdk::world_item::cigarette;
        InterlockedExchange(
            &g_replay_world_item_id,
            supported ? static_cast<LONG>(argument) : 0);
        RecordDiagnostic(
            "replay_world_item",
            supported ? "staged" : "rejected",
            "isolated_probe_only");
        break;
    }
    case replay_spawn_world_item: {
        const int world_x =
            static_cast<unsigned short>(LOWORD(message.lParam));
        const int world_y =
            static_cast<unsigned short>(HIWORD(message.lParam));
        const int item_id = static_cast<int>(
            InterlockedExchange(&g_replay_world_item_id, 0));
        const bool supported =
            item_id == m1937::sdk::world_item::chicken ||
            item_id == m1937::sdk::world_item::canned_meat ||
            item_id == m1937::sdk::world_item::hypnosis_doll ||
            item_id == m1937::sdk::world_item::poisoned_wine ||
            item_id == m1937::sdk::world_item::dog_bone ||
            item_id == m1937::sdk::world_item::cigarette;
        // Never mutate the original actor array while a window procedure is
        // running. The game can dispatch this private replay message from
        // inside its own object update. Calling sub_44A350 there re-enters the
        // actor factory and corrupts the active traversal. Queue the request;
        // PumpWindowMessages processes it at a stable input-poll boundary.
        if (supported) {
            InterlockedExchange(&g_replay_world_item_x, world_x);
            InterlockedExchange(&g_replay_world_item_y, world_y);
            InterlockedExchange(
                &g_replay_world_item_spawn_pending,
                static_cast<LONG>(item_id));
        }
        RecordDiagnostic(
            "replay_world_item",
            supported ? "queued" : "unavailable",
            "isolated_probe_only");
        break;
    }
    case replay_seed_weapon_inventory: {
        const int slot =
            static_cast<unsigned short>(HIWORD(message.lParam));
        const int item_id =
            static_cast<unsigned short>(LOWORD(message.lParam));
        const bool supported =
            slot >= 1 && slot <= 5 && item_id == 42;
        InterlockedExchange(
            &g_replay_inventory_seed_pending,
            supported
                ? static_cast<LONG>((slot << 16) | item_id)
                : 0);
        RecordDiagnostic(
            "replay_weapon_seed",
            supported ? "queued" : "rejected",
            "isolated_probe_only");
        break;
    }
    case replay_complete_guming_disguise: {
        const bool supported = argument == 4;
        InterlockedExchange(
            &g_replay_disguise_transition_pending,
            supported ? 4 : 0);
        RecordDiagnostic(
            "replay_disguise",
            supported ? "queued" : "rejected",
            "isolated_probe_only");
        break;
    }
    case replay_select_weapon_inventory_item: {
        const int slot =
            static_cast<unsigned short>(HIWORD(message.lParam));
        const int item_id =
            static_cast<unsigned short>(LOWORD(message.lParam));
        const bool supported =
            slot >= 1 && slot <= 5 &&
            ((item_id >= 36 && item_id <= 45) ||
             item_id == 99);
        InterlockedExchange(
            &g_replay_weapon_selection_pending,
            supported
                ? static_cast<LONG>((slot << 16) | item_id)
                : 0);
        RecordDiagnostic(
            "replay_weapon_select",
            supported ? "queued" : "rejected",
            "isolated_probe_only");
        break;
    }
    case replay_commit_special_attention: {
        const int source_slot =
            static_cast<unsigned short>(HIWORD(message.lParam));
        const int target_scene =
            static_cast<unsigned short>(LOWORD(message.lParam));
        const bool supported =
            source_slot >= 1 && source_slot <= 5 &&
            target_scene > 0;
        InterlockedExchange(
            &g_replay_special_attention_commit_pending,
            supported
                ? static_cast<LONG>(
                    (source_slot << 16) | target_scene)
                : 0);
        RecordDiagnostic(
            "replay_attention",
            supported ? "queued" : "rejected",
            "isolated_probe_only");
        break;
    }
    default:
        return;
    }
    if (input_command)
        InterlockedExchange64(
            &g_replay_input_qpc, PerformanceCounterNow());
    InterlockedIncrement(&g_replay_message_count);
    InterlockedIncrement(&g_telemetry.replay_messages);
}

std::uintptr_t PlayerActorSlotRva(int slot) {
    switch (slot) {
    case 1:
        return m1937::sdk::rva::player_actor_slot_1;
    case 2:
        return m1937::sdk::rva::player_actor_slot_2;
    case 3:
        return m1937::sdk::rva::player_actor_slot_3;
    case 4:
        // This fourth fixed player pointer is also the source anchor used by
        // original type 11, hence the older public SDK symbol name.
        return m1937::sdk::rva::special_attention_source;
    case 5:
        return m1937::sdk::rva::player_actor_slot_5;
    default:
        return 0;
    }
}

m1937::sdk::RuntimeActorV1 *PlayerActorForSlot(int slot) {
    if (!g_executable_base) {
        return nullptr;
    }
    const auto rva = PlayerActorSlotRva(slot);
    if (!rva) {
        return nullptr;
    }
    auto **actor_slot =
        reinterpret_cast<m1937::sdk::RuntimeActorV1 **>(
            g_executable_base + rva);
    auto *actor =
        IsReadableRange(actor_slot, sizeof(*actor_slot))
            ? *actor_slot
            : nullptr;
    return actor && IsReadableRange(actor, sizeof(*actor))
        ? actor
        : nullptr;
}

bool InventoryContainsItem(
    std::uint32_t container_address,
    int item_id) {
    auto *container =
        reinterpret_cast<m1937::sdk::RuntimeInventoryContainerV1 *>(
            static_cast<std::uintptr_t>(container_address));
    if (!container ||
        !IsReadableRange(container, sizeof(*container)) ||
        container->item_count < 0 ||
        container->item_count > 256) {
        return false;
    }
    if (container->item_count == 0) {
        return false;
    }
    auto *item_ids = reinterpret_cast<const std::int32_t *>(
        static_cast<std::uintptr_t>(
            container->item_ids_address));
    if (!item_ids ||
        !IsReadableRange(
            item_ids,
            sizeof(*item_ids) *
                static_cast<std::size_t>(
                    container->item_count))) {
        return false;
    }
    for (int index = 0;
         index < container->item_count;
         ++index) {
        if (item_ids[index] == item_id) {
            return true;
        }
    }
    return false;
}

void ProcessPendingReplayInventoryMutations() {
    const LONG packed = InterlockedExchange(
        &g_replay_inventory_seed_pending, 0);
    if (packed) {
        const int slot =
            static_cast<unsigned short>(
                HIWORD(static_cast<DWORD>(packed)));
        const int item_id =
            static_cast<unsigned short>(
                LOWORD(static_cast<DWORD>(packed)));
        auto *actor = PlayerActorForSlot(slot);
        bool seeded = false;
        if (actor &&
            actor->dead_or_disabled == 0 &&
            actor->faction_id == 3 &&
            item_id == 42) {
            using AddInventoryItemFn =
                int(__thiscall *)(
                    m1937::sdk::RuntimeActorV1 *,
                    int,
                    int);
            auto add_inventory_item =
                reinterpret_cast<AddInventoryItemFn>(
                    g_executable_base +
                    m1937::sdk::rva::add_inventory_item);
            seeded =
                InventoryContainsItem(
                    actor->inventory_address, item_id) ||
                add_inventory_item(actor, item_id, 1) != 0;
        }
        RecordDiagnostic(
            "replay_weapon_seed",
            seeded ? "seeded" : "unavailable",
            "safe_input_poll_boundary");
    }

    const int disguise_slot = static_cast<int>(
        InterlockedExchange(
            &g_replay_disguise_transition_pending, 0));
    if (disguise_slot != 0) {
        auto *actor = PlayerActorForSlot(disguise_slot);
        bool transitioned = false;
        if (actor &&
            actor->runtime_type == 10 &&
            actor->dead_or_disabled == 0 &&
            actor->faction_id == 3) {
            using AddInventoryItemFn =
                int(__thiscall *)(
                    m1937::sdk::RuntimeActorV1 *,
                    int,
                    int);
            auto add_inventory_item =
                reinterpret_cast<AddInventoryItemFn>(
                    g_executable_base +
                    m1937::sdk::rva::add_inventory_item);
            const bool has_uniform =
                InventoryContainsItem(
                    actor->item_inventory_address, 54) ||
                add_inventory_item(actor, 54, 1) != 0;
            if (has_uniform) {
                actor->disguise_transition_ready = 1;
                using FinalizeDisguiseFn = int(__cdecl *)();
                auto finalize_disguise =
                    reinterpret_cast<FinalizeDisguiseFn>(
                        g_executable_base +
                        m1937::sdk::rva::player_disguise_toggle);
                finalize_disguise();
                auto *disguised =
                    PlayerActorForSlot(disguise_slot);
                transitioned =
                    disguised &&
                    disguised != actor &&
                    disguised->runtime_type == 91 &&
                    InventoryContainsItem(
                        disguised->inventory_address, 99);
            }
        }
        RecordDiagnostic(
            "replay_disguise",
            transitioned ? "transitioned" : "unavailable",
            "safe_input_poll_boundary");
    }

    const LONG selected_packed = InterlockedExchange(
        &g_replay_weapon_selection_pending, 0);
    if (selected_packed) {
        const int selected_slot =
            static_cast<unsigned short>(
                HIWORD(static_cast<DWORD>(selected_packed)));
        const int selected_item_id =
            static_cast<unsigned short>(
                LOWORD(static_cast<DWORD>(selected_packed)));
        auto *selected_actor = PlayerActorForSlot(selected_slot);
        int attack_type = 0;
        if (selected_item_id >= 36 && selected_item_id <= 45) {
            attack_type = selected_item_id - 35;
        } else if (selected_item_id == 99) {
            attack_type = 11;
        }
        const bool selected =
            selected_actor &&
            selected_actor->dead_or_disabled == 0 &&
            attack_type > 0 &&
            InventoryContainsItem(
                selected_actor->inventory_address,
                selected_item_id);
        if (selected) {
            // Isolated-probe fallback for no-focus runs in which the original
            // W-panel hover widget misses its click. This writes the recovered
            // +0x20C selection field only. Original target acquisition,
            // pathing, animation, hit-frame dispatch, quantity handling and
            // world effects remain untouched.
            selected_actor->default_attack_type = attack_type;
        }
        RecordDiagnostic(
            "replay_weapon_select",
            selected ? "selected" : "unavailable",
            "safe_input_poll_boundary");
    }

    const LONG attention_packed = InterlockedExchange(
        &g_replay_special_attention_commit_pending, 0);
    if (!attention_packed) {
        return;
    }
    const int source_slot =
        static_cast<unsigned short>(
            HIWORD(static_cast<DWORD>(attention_packed)));
    const int target_scene =
        static_cast<unsigned short>(
            LOWORD(static_cast<DWORD>(attention_packed)));
    auto *source = PlayerActorForSlot(source_slot);
    m1937::sdk::RuntimeActorV1 *target = nullptr;
    m1937::sdk::RuntimeActorV1 **actors = nullptr;
    int actor_count = 0;
    if (RuntimeActors(&actors, &actor_count)) {
        for (int index = 0; index < actor_count; ++index) {
            auto *candidate = actors[index];
            if (candidate &&
                IsReadableRange(candidate, sizeof(*candidate)) &&
                candidate->world_scene_index == target_scene) {
                target = candidate;
                break;
            }
        }
    }
    bool committed = false;
    if (source &&
        source->runtime_type == 91 &&
        source->faction_id == 1 &&
        source->dead_or_disabled == 0 &&
        InventoryContainsItem(source->inventory_address, 99) &&
        target &&
        target != source &&
        target->dead_or_disabled == 0) {
        using ActorResetFn =
            void(__thiscall *)(m1937::sdk::RuntimeActorV1 *);
        auto reset_actor_movement =
            reinterpret_cast<ActorResetFn>(
                g_executable_base +
                m1937::sdk::rva::reset_actor_movement);
        auto clear_actor_command_targets =
            reinterpret_cast<ActorResetFn>(
                g_executable_base +
                m1937::sdk::rva::clear_actor_command_targets);
        reset_actor_movement(source);
        clear_actor_command_targets(source);
        const auto original_current_attack =
            source->current_attack_type;
        const auto original_target =
            source->target_actor_address;
        source->current_attack_type = 11;
        source->target_actor_address =
            static_cast<std::uint32_t>(
                reinterpret_cast<std::uintptr_t>(target));
        using SpecialAttackDispatchFn =
            int(__thiscall *)(m1937::sdk::RuntimeActorV1 *);
        auto special_attack_dispatch =
            reinterpret_cast<SpecialAttackDispatchFn>(
                g_executable_base +
                m1937::sdk::rva::special_attack_dispatch);
        special_attack_dispatch(source);
        committed = target->special_attention_hold == 1;
        source->current_attack_type = original_current_attack;
        source->target_actor_address = original_target;
    }
    RecordDiagnostic(
        "replay_attention",
        committed ? "committed" : "unavailable",
        "original_hit_frame_dispatch");
}

void ProcessPendingReplayWorldItem() {
    const int item_id = static_cast<int>(
        InterlockedExchange(&g_replay_world_item_spawn_pending, 0));
    if (item_id == 0) {
        return;
    }
    const int world_x = static_cast<int>(
        InterlockedCompareExchange(&g_replay_world_item_x, 0, 0));
    const int world_y = static_cast<int>(
        InterlockedCompareExchange(&g_replay_world_item_y, 0, 0));
    bool spawned = false;
    if (g_executable_base) {
        auto **controller_slot =
            reinterpret_cast<m1937::sdk::RuntimeViewportControllerV1 **>(
                g_executable_base +
                m1937::sdk::rva::viewport_controller);
        auto *controller =
            IsReadableRange(controller_slot, sizeof(*controller_slot))
                ? *controller_slot
                : nullptr;
        if (controller &&
            IsReadableRange(controller, sizeof(*controller)) &&
            world_x >= 0 && world_y >= 0 &&
            world_x < controller->world_width &&
            world_y < controller->world_height) {
            auto **factory_slot = reinterpret_cast<void **>(
                g_executable_base +
                m1937::sdk::rva::world_actor_factory);
            void *factory =
                IsReadableRange(factory_slot, sizeof(*factory_slot))
                    ? *factory_slot
                    : nullptr;
            using CreateWorldActorFn =
                m1937::sdk::RuntimeActorV1 *(__thiscall *)(
                    void *, int, int, int, int);
            auto create_world_actor =
                reinterpret_cast<CreateWorldActorFn>(
                    g_executable_base +
                    m1937::sdk::rva::create_world_actor);
            spawned = factory &&
                IsReadableRange(factory, sizeof(std::uint32_t) * 4) &&
                create_world_actor(
                    factory, world_x, 0, world_y, item_id) != nullptr;
        }
    }
    RecordDiagnostic(
        "replay_world_item",
        spawned ? "spawned" : "unavailable",
        "safe_input_poll_boundary");
}

LRESULT CALLBACK ReplayWindowProcedure(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == kWindowReplayMessage &&
        IsWindowReplayEnabled()) {
        MSG replay{};
        replay.hwnd = window;
        replay.message = message;
        replay.wParam = wparam;
        replay.lParam = lparam;
        HandleWindowReplayMessage(replay);
        return 0;
    }
    return g_original_replay_window_proc
        ? CallWindowProcA(
              g_original_replay_window_proc,
              window, message, wparam, lparam)
        : DefWindowProcA(window, message, wparam, lparam);
}

bool InstallReplayWindowProcedure(HWND window) {
    if (!IsWindowReplayEnabled() || !window) {
        return false;
    }
    if (g_replay_subclass_window == window &&
        g_original_replay_window_proc) {
        return true;
    }
    SetLastError(ERROR_SUCCESS);
    const LONG_PTR previous = SetWindowLongPtrA(
        window, GWLP_WNDPROC,
        reinterpret_cast<LONG_PTR>(&ReplayWindowProcedure));
    if (previous == 0 && GetLastError() != ERROR_SUCCESS) {
        return false;
    }
    g_original_replay_window_proc =
        reinterpret_cast<WNDPROC>(previous);
    g_replay_subclass_window = window;
    RecordDiagnostic(
        "window_replay", "ready", "process_local_subclass");
    FlushDiagnostics();
    return true;
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
    const LONGLONG pump_started = PerformanceCounterNow();

    // Do not consume keyboard or mouse messages here. The original loop must
    // see them in order for F1, M and the other game hotkeys to toggle their
    // UI. Only service paint/timer/close traffic during synchronous loading.
    static const UINT background_messages[] = {
        WM_PAINT, WM_TIMER, WM_NCPAINT, WM_ERASEBKGND, WM_CLOSE};
    MSG message{};
    int dispatched = 0;
    if (IsWindowReplayEnabled()) {
        while (dispatched < g_mod_config.message_pump_budget &&
               PeekMessageA(
                   &message, nullptr,
                   kWindowReplayMessage, kWindowReplayMessage,
                   PM_REMOVE)) {
            HandleWindowReplayMessage(message);
            ++dispatched;
        }
    }
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
    TickEnhancedEnemyAI();
    g_pumping_messages = false;
    ProcessPendingReplayInventoryMutations();
    ProcessPendingReplayWorldItem();
    InterlockedExchangeAdd(
        &g_telemetry.pump_messages, dispatched);
    AddTiming(
        &g_telemetry.pump_calls,
        &g_telemetry.pump_microseconds,
        &g_telemetry.pump_max_microseconds,
        pump_started);
    // Formatting and queueing are intentionally outside the measured message
    // pump. The writer thread performs all file open/write/close operations.
    FlushTelemetrySnapshot();
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
    wchar_t game_directory[MAX_PATH]{};
    const DWORD executable_length =
        GetModuleFileNameW(nullptr, game_directory, MAX_PATH);
    if (executable_length == 0 || executable_length >= MAX_PATH) {
        return false;
    }
    wchar_t *separator = wcsrchr(game_directory, L'\\');
    if (!separator ||
        static_cast<size_t>(separator - game_directory) + 48 >= MAX_PATH) {
        return false;
    }
    *(separator + 1) = L'\0';

    // A prior game process can remain in teardown briefly after its window
    // has closed. A fixed copy name makes the next launch race that mapped
    // image and intermittently fail every other rapid restart. Remove only
    // stale, unlocked proxy-owned copies, then use a PID-unique name.
    wchar_t pattern[MAX_PATH]{};
    lstrcpynW(pattern, game_directory, MAX_PATH);
    lstrcatW(pattern, L"dinput_system_*.dll");
    WIN32_FIND_DATAW found{};
    HANDLE search = FindFirstFileW(pattern, &found);
    if (search != INVALID_HANDLE_VALUE) {
        do {
            wchar_t stale[MAX_PATH]{};
            lstrcpynW(stale, game_directory, MAX_PATH);
            lstrcatW(stale, found.cFileName);
            DeleteFileW(stale);
        } while (FindNextFileW(search, &found));
        FindClose(search);
    }

    wchar_t unique_name[48]{};
    swprintf_s(
        unique_name, L"dinput_system_%lu.dll",
        static_cast<unsigned long>(GetCurrentProcessId()));
    lstrcpynW(g_real_dinput_copy, game_directory, MAX_PATH);
    lstrcatW(g_real_dinput_copy, unique_name);
    if (!CopyFileW(system_dinput, g_real_dinput_copy, FALSE)) {
        return false;
    }

    g_real_dinput = LoadLibraryW(g_real_dinput_copy);
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

void ApplyKeyboardAliases(DWORD size, LPVOID data) {
    if (!g_mod_config.key_remapping || !data || size < 256) {
        return;
    }
    auto *keys = static_cast<unsigned char *>(data);
    for (int index = 0; index < g_key_alias_count; ++index) {
        const auto &alias = g_key_aliases[index];
        if ((keys[alias.source] & 0x80) != 0) {
            keys[alias.target] |= 0x80;
        }
    }
}

void ApplyWindowReplayKeyboard(DWORD size, LPVOID data) {
    if (!IsWindowReplayEnabled() || !data || size < 256) {
        return;
    }
    auto *keys = static_cast<unsigned char *>(data);
    bool changed = false;
    for (int index = 0; index < 256; ++index) {
        if ((g_replay_keyboard[index] & 0x80) != 0) {
            keys[index] |= 0x80;
            changed = true;
        }
    }
    if (changed) {
        const LONGLONG sent = InterlockedExchange64(
            &g_replay_input_qpc, 0);
        if (sent > 0)
            AddTiming(
                &g_telemetry.replay_latency_samples,
                &g_telemetry.replay_latency_microseconds,
                &g_telemetry.replay_latency_max_microseconds,
                sent);
        InterlockedIncrement(&g_replay_state_reads);
        InterlockedIncrement(&g_telemetry.replay_reads);
    }
}

void ApplyWindowReplayMouse(DWORD size, LPVOID data) {
    if (!IsWindowReplayEnabled() || !data ||
        size < sizeof(DIMOUSESTATE)) {
        return;
    }
    auto *mouse = static_cast<DIMOUSESTATE *>(data);
    const LONG delta_x = g_replay_mouse.lX;
    const LONG delta_y = g_replay_mouse.lY;
    g_replay_mouse.lX = 0;
    g_replay_mouse.lY = 0;
    mouse->lX += delta_x;
    mouse->lY += delta_y;
    bool changed = delta_x != 0 || delta_y != 0;
    for (int index = 0; index < 4; ++index) {
        if ((g_replay_mouse.rgbButtons[index] & 0x80) != 0) {
            mouse->rgbButtons[index] |= 0x80;
            changed = true;
        }
    }
    if (changed) {
        const LONGLONG sent = InterlockedExchange64(
            &g_replay_input_qpc, 0);
        if (sent > 0)
            AddTiming(
                &g_telemetry.replay_latency_samples,
                &g_telemetry.replay_latency_microseconds,
                &g_telemetry.replay_latency_max_microseconds,
                sent);
        InterlockedIncrement(&g_replay_state_reads);
        InterlockedIncrement(&g_telemetry.replay_reads);
    }
}

void ObserveExtensionBriefingMouse(DWORD size, LPVOID data) {
    if (InterlockedCompareExchange(
            &g_extension_briefing_pending, 0, 0) != 1 ||
        !data || size < sizeof(DIMOUSESTATE)) {
        return;
    }
    const auto *mouse = static_cast<const DIMOUSESTATE *>(data);
    bool pressed = false;
    for (int index = 0; index < 4; ++index) {
        pressed = pressed || (mouse->rgbButtons[index] & 0x80) != 0;
    }
    if (!pressed) {
        InterlockedExchange(&g_extension_briefing_mouse_released, 1);
        return;
    }
    if (InterlockedCompareExchange(
            &g_extension_briefing_mouse_released, 0, 0) == 1) {
        CompleteExtensionBriefingContinuation("mouse");
    }
}

void ObserveExtensionBriefingKeyboard(DWORD size, LPVOID data) {
    if (InterlockedCompareExchange(
            &g_extension_briefing_pending, 0, 0) != 1 ||
        !data || size < 256) {
        return;
    }
    const auto *keys = static_cast<const unsigned char *>(data);
    const bool pressed =
        (keys[DIK_RETURN] & 0x80) != 0 ||
        (keys[DIK_NUMPADENTER] & 0x80) != 0;
    if (!pressed) {
        InterlockedExchange(&g_extension_briefing_keyboard_released, 1);
        return;
    }
    if (InterlockedCompareExchange(
            &g_extension_briefing_keyboard_released, 0, 0) == 1) {
        CompleteExtensionBriefingContinuation("enter");
    }
}

void ScheduleExtensionSelectionHotkey(const char *input_source) {
    if (InterlockedCompareExchange(
            &g_extension_resume_hotkey_armed, 0, 1) != 1) {
        return;
    }
    // Let the original Return-to-Mission click finish its transition before
    // presenting F4 to DirectInput. Holding the synthetic key across several
    // polls reproduces a normal key press without touching the desktop input
    // queue or the system cursor.
    InterlockedExchange(
        &g_extension_selection_hotkey_due_tick,
        static_cast<LONG>(GetTickCount() + 500));
    InterlockedExchange(&g_extension_selection_hotkey_phase, 1);
    const DWORD accept = static_cast<DWORD>(
        InterlockedCompareExchange(
            &g_extension_resume_accept_tick, 0, 0));
    char detail[48]{};
    snprintf(
        detail,
        sizeof(detail),
        "%s_after_%lu_ms",
        input_source,
        static_cast<unsigned long>(GetTickCount() - accept));
    RecordDiagnostic(
        "extension_full_redraw", "scheduled", detail);
}

void ObserveExtensionResumeMouse(DWORD size, LPVOID data) {
    if (InterlockedCompareExchange(
            &g_extension_resume_hotkey_armed, 0, 0) != 1 ||
        !data || size < sizeof(DIMOUSESTATE)) {
        return;
    }
    const DWORD accept = static_cast<DWORD>(
        InterlockedCompareExchange(
            &g_extension_resume_accept_tick, 0, 0));
    if (static_cast<LONG>(GetTickCount() - accept) < 0) {
        return;
    }
    const auto *mouse = static_cast<const DIMOUSESTATE *>(data);
    bool pressed = false;
    for (int index = 0; index < 4; ++index) {
        pressed = pressed || (mouse->rgbButtons[index] & 0x80) != 0;
    }
    if (!pressed) {
        InterlockedExchange(&g_extension_resume_mouse_released, 1);
        return;
    }
    if (InterlockedCompareExchange(
            &g_extension_resume_mouse_released, 0, 0) == 1) {
        ScheduleExtensionSelectionHotkey("mouse");
    }
}

void ObserveExtensionResumeKeyboard(DWORD size, LPVOID data) {
    if (InterlockedCompareExchange(
            &g_extension_resume_hotkey_armed, 0, 0) != 1 ||
        !data || size < 256) {
        return;
    }
    const DWORD accept = static_cast<DWORD>(
        InterlockedCompareExchange(
            &g_extension_resume_accept_tick, 0, 0));
    if (static_cast<LONG>(GetTickCount() - accept) < 0) {
        return;
    }
    const auto *keys = static_cast<const unsigned char *>(data);
    const bool pressed =
        (keys[DIK_RETURN] & 0x80) != 0 ||
        (keys[DIK_NUMPADENTER] & 0x80) != 0;
    if (!pressed) {
        InterlockedExchange(&g_extension_resume_keyboard_released, 1);
        return;
    }
    if (InterlockedCompareExchange(
            &g_extension_resume_keyboard_released, 0, 0) == 1) {
        ScheduleExtensionSelectionHotkey("enter");
    }
}

void ApplyExtensionSelectionHotkey(DWORD size, LPVOID data) {
    if (!data || size < 256) {
        return;
    }
    LONG phase = InterlockedCompareExchange(
        &g_extension_selection_hotkey_phase, 0, 0);
    if (phase == 0) {
        return;
    }
    const DWORD now = GetTickCount();
    if (phase == 1) {
        const DWORD due = static_cast<DWORD>(
            InterlockedCompareExchange(
                &g_extension_selection_hotkey_due_tick, 0, 0));
        if (static_cast<LONG>(now - due) < 0 ||
            !g_executable_base ||
            *reinterpret_cast<int *>(
                g_executable_base +
                m1937::sdk::rva::current_mission) <= 0) {
            return;
        }
        m1937::sdk::RuntimeActorV1 **actors = nullptr;
        int actor_count = 0;
        if (!RuntimeActors(&actors, &actor_count) || actor_count <= 0) {
            return;
        }
        if (InterlockedCompareExchange(
                &g_extension_selection_hotkey_phase, 2, 1) != 1) {
            return;
        }
        InterlockedExchange(
            &g_extension_selection_hotkey_release_tick,
            static_cast<LONG>(now + 180));
        RecordDiagnostic(
            "extension_full_redraw", "pressed", "original_f4");
        FlushDiagnostics();
        phase = 2;
    }
    if (phase != 2) {
        return;
    }
    const DWORD release = static_cast<DWORD>(
        InterlockedCompareExchange(
            &g_extension_selection_hotkey_release_tick, 0, 0));
    if (static_cast<LONG>(now - release) < 0) {
        auto *keys = static_cast<unsigned char *>(data);
        keys[DIK_F4] |= 0x80;
        return;
    }
    InterlockedExchange(&g_extension_selection_hotkey_phase, 0);
    RecordDiagnostic(
        "extension_full_redraw", "released", "original_f4");
    FlushDiagnostics();
}

class DeviceProxy final : public IDirectInputDeviceA {
public:
    DeviceProxy(
        LPDIRECTINPUTDEVICEA real, bool is_mouse, bool is_keyboard)
        : real_(real),
          is_mouse_(is_mouse),
          is_keyboard_(is_keyboard) {}

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
        const LONGLONG started = PerformanceCounterNow();
        const HRESULT result = real_->GetDeviceState(size, data);
        if (SUCCEEDED(result) && is_mouse_) {
            MapSystemCursorToGameState(size, data);
            ApplyWindowReplayMouse(size, data);
            ObserveExtensionBriefingMouse(size, data);
            ObserveExtensionResumeMouse(size, data);
        }
        if (SUCCEEDED(result) && is_keyboard_) {
            ApplyKeyboardAliases(size, data);
            ApplyWindowReplayKeyboard(size, data);
            ObserveExtensionBriefingKeyboard(size, data);
            ObserveExtensionResumeKeyboard(size, data);
            ApplyExtensionSelectionHotkey(size, data);
        }
        AddTiming(
            &g_telemetry.input_state_calls,
            &g_telemetry.input_state_microseconds,
            &g_telemetry.input_state_max_microseconds,
            started);
        FlushTelemetrySnapshot();
        return result;
    }
    HRESULT STDMETHODCALLTYPE GetDeviceData(
        DWORD object_size, LPDIDEVICEOBJECTDATA data, LPDWORD count,
        DWORD flags) override {
        PumpWindowMessages();
        const LONGLONG started = PerformanceCounterNow();
        const HRESULT result =
            real_->GetDeviceData(object_size, data, count, flags);
        AddTiming(
            &g_telemetry.input_data_calls,
            &g_telemetry.input_data_microseconds,
            &g_telemetry.input_data_max_microseconds,
            started);
        FlushTelemetrySnapshot();
        return result;
    }
    HRESULT STDMETHODCALLTYPE SetDataFormat(LPCDIDATAFORMAT format) override {
        if (format && format->dwDataSize == sizeof(DIMOUSESTATE)) {
            is_mouse_ = true;
        } else if (format && format->dwDataSize >= 256) {
            is_keyboard_ = true;
        }
        return real_->SetDataFormat(format);
    }
    HRESULT STDMETHODCALLTYPE SetEventNotification(HANDLE event) override {
        return real_->SetEventNotification(event);
    }
    HRESULT STDMETHODCALLTYPE SetCooperativeLevel(HWND window, DWORD flags) override {
        if (is_mouse_ || IsWindowReplayEnabled()) {
            g_game_window = window;
        }
        if (IsWindowReplayEnabled()) {
            InstallReplayWindowProcedure(window);
        }
        ProtectGameWindowInput(window);
        const DWORD effective_flags =
            IsWindowReplayEnabled()
            ? DISCL_BACKGROUND | DISCL_NONEXCLUSIVE
            : is_mouse_ && g_mod_config.system_cursor_mapping
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
    bool is_keyboard_;
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
            real_device,
            IsEqualGUID(guid, GUID_SysMouse) != FALSE,
            IsEqualGUID(guid, GUID_SysKeyboard) != FALSE);
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
        g_proxy_instance = instance;
        DisableThreadLibraryCalls(instance);
        LoadModConfig();
        ApplyLegacyExecutablePatches();
    } else if (reason == DLL_PROCESS_DETACH && g_timer_period_active) {
        timeEndPeriod(1);
        g_timer_period_active = false;
    }
    return TRUE;
}
