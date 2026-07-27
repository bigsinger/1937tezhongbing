#pragma once

#include <cstddef>
#include <cstdint>

namespace m1937::sdk::plugin {

inline constexpr std::uint32_t abi_version_v1 = 0x00010000;
inline constexpr std::uint32_t mission_schema_version_v1 = 1;

enum class WorldEventKind : std::uint32_t {
    mission_started = 1,
    reached = 2,
    killed = 3,
    picked_up = 4,
    exploded = 5,
    interacted = 6,
    evacuated = 7,
    mission_succeeded = 8,
    mission_failed = 9,
    save_started = 10,
    save_completed = 11,
    load_started = 12,
    load_completed = 13,
};

// Events contain stable IDs and integer values only. Runtime pointers and
// player input never cross the ABI boundary.
struct WorldEventV1 final {
    std::uint32_t size;
    WorldEventKind kind;
    std::uint64_t sequence;
    std::uint64_t monotonic_milliseconds;
    std::uint32_t mission;
    std::uint32_t subject_id;
    std::uint32_t object_id;
    std::int32_t value;
};

struct HostInfoV1 final {
    std::uint32_t size;
    std::uint32_t abi_version;
    std::uint32_t mission_schema_version;
    std::uint32_t executable_pe_timestamp;
    std::uint32_t executable_image_size;
    const char* executable_sha256;
};

using EmitEventProcV1 = bool (*)(const WorldEventV1*);
using ReadSidecarStateProcV1 = bool (*)(
    const char* slot_id, void* buffer, std::uint32_t* size);
using WriteSidecarStateProcV1 = bool (*)(
    const char* slot_id, const void* buffer, std::uint32_t size);

struct HostApiV1 final {
    std::uint32_t size;
    HostInfoV1 info;
    EmitEventProcV1 emit_event;
    ReadSidecarStateProcV1 read_sidecar_state;
    WriteSidecarStateProcV1 write_sidecar_state;
};

using OnLoadProcV1 = bool (*)(const HostApiV1*);
using OnUnloadProcV1 = void (*)();
using OnWorldEventProcV1 = void (*)(const WorldEventV1*);

struct PluginApiV1 final {
    std::uint32_t size;
    std::uint32_t abi_version;
    std::uint32_t minimum_mission_schema;
    std::uint32_t maximum_mission_schema;
    const char* plugin_id;
    OnLoadProcV1 on_load;
    OnUnloadProcV1 on_unload;
    OnWorldEventProcV1 on_world_event;
};

using QueryPluginV1Proc = const PluginApiV1* (*)();

static_assert(sizeof(WorldEventV1) == 40);

}  // namespace m1937::sdk::plugin
