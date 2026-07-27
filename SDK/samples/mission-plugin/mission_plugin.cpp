#include <M1937SDK/M1937SDK.hpp>

#include <cstdint>
#include <cstring>

namespace {

m1937::sdk::plugin::HostApiV1 g_host{};
std::uint64_t g_event_count = 0;

bool OnLoad(const m1937::sdk::plugin::HostApiV1* host) {
    if (!host ||
        host->size < sizeof(m1937::sdk::plugin::HostApiV1) ||
        host->info.size < sizeof(m1937::sdk::plugin::HostInfoV1) ||
        host->info.abi_version !=
            m1937::sdk::plugin::abi_version_v1 ||
        host->info.mission_schema_version !=
            m1937::sdk::plugin::mission_schema_version_v1 ||
        !host->info.executable_sha256 ||
        std::strcmp(
            host->info.executable_sha256,
            m1937::sdk::ExecutableIdentity::sha256) != 0) {
        return false;
    }
    // Copy function pointers and immutable identity values. A plugin must not
    // retain the transient pointer passed to OnLoad.
    g_host = *host;
    return true;
}

void OnUnload() {
    g_host = {};
}

void OnWorldEvent(
    const m1937::sdk::plugin::WorldEventV1* event) {
    if (!event || event->size <
            sizeof(m1937::sdk::plugin::WorldEventV1)) {
        return;
    }
    ++g_event_count;
    if (g_host.write_sidecar_state) {
        g_host.write_sidecar_state(
            "sample-event-count",
            &g_event_count,
            static_cast<std::uint32_t>(sizeof(g_event_count)));
    }
}

const m1937::sdk::plugin::PluginApiV1 kPlugin{
    sizeof(m1937::sdk::plugin::PluginApiV1),
    m1937::sdk::plugin::abi_version_v1,
    m1937::sdk::plugin::mission_schema_version_v1,
    m1937::sdk::plugin::mission_schema_version_v1,
    "org.m1937.sample.event-counter",
    &OnLoad,
    &OnUnload,
    &OnWorldEvent,
};

}  // namespace

extern "C" __declspec(dllexport)
const m1937::sdk::plugin::PluginApiV1*
M1937QueryPluginV1() {
    return &kPlugin;
}
