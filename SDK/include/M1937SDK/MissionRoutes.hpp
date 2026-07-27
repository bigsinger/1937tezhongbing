#pragma once

// Generated from SDK/mission-routes.json. Do not edit.
#include <cstddef>
#include <cstdint>

namespace m1937::sdk {

struct MissionRoute final {
    int selector_level;
    int engine_mission;
    const char* id;
    const char* vwf_name;
    bool requires_file;
    std::uintptr_t redirect_rva;
    const char* redirect_expected;
};

inline constexpr MissionRoute mission_routes[] = {
    {1, 1, "m000", "1937M000.VWF", true, 0, ""},
    {2, 2, "m001", "1937M001.VWF", true, 0, ""},
    {3, 3, "m002", "1937M002.VWF", true, 0, ""},
    {4, 4, "m003", "1937M003.VWF", true, 0, ""},
    {5, 5, "m004", "1937M004.VWF", true, 0, ""},
    {6, 6, "m005", "1937M005.VWF", true, 0, ""},
    {7, 7, "m006", "1937M006.VWF", true, 0, ""},
    {8, 8, "m007", "1937M007.VWF", true, 0, ""},
    {9, 9, "m008", "1937M008.VWF", true, 0, ""},
    {10, 10, "m009", "1937M009.VWF", true, 0, ""},
    {11, 11, "m010", "1937M010.VWF", true, 0, ""},
    {12, 12, "m011", "1937M011.VWF", true, 0, ""},
    {13, 12, "m012", "1937M012.VWF", true, 0x000CF4A8, "1937M011.VWF"},
    {14, 7, "m013", "1937M013.VWF", true, 0x000CF4F8, "1937M006.VWF"},
    {15, 7, "m014", "1937M014.VWF", true, 0x000CF4F8, "1937M006.VWF"},
};

inline constexpr std::size_t mission_route_count =
    sizeof(mission_routes) / sizeof(mission_routes[0]);

inline constexpr const MissionRoute* find_mission_route(int selector_level) {
    for (const auto& route : mission_routes) {
        if (route.selector_level == selector_level)
            return &route;
    }
    return nullptr;
}

}  // namespace m1937::sdk
