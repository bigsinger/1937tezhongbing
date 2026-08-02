#pragma once

// Generated from SDK/sound-routes.json. Do not edit.
#include <array>
#include <cstddef>

namespace m1937::sdk::sound {

inline constexpr int slf_entry_count = 126;
inline constexpr int sprite_group_parameter_index = 8;
inline constexpr int audited_sprite_count = 980;
inline constexpr int audited_group_count = 2775;
inline constexpr int sounded_group_count = 1137;
inline constexpr int ui_button_zero_based_index = 124;
inline constexpr int ui_button_gfl_index = 1393;
inline constexpr int global_alarm_zero_based_index = 125;
inline constexpr int global_alarm_gfl_index = 1324;
inline constexpr int global_alarm_update_counter_limit = 240;
inline constexpr int global_alarm_active_request_updates = 241;

inline constexpr std::array<int, 52> sprite_group_one_based_indices{{
    1, 3, 4, 5, 6, 8, 9, 10, 13, 15, 16, 17, 18, 20, 21, 22, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35, 36, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 59, 60, 61, 126
}};
inline constexpr std::array<int, 42> actor_voice_zero_based_indices{{
    63, 65, 66, 70, 74, 75, 78, 79, 83, 86, 87, 88, 89, 90, 91, 92, 93, 94, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122
}};
inline constexpr std::array<int, 95> reachable_zero_based_indices{{
    0, 2, 3, 4, 5, 7, 8, 9, 12, 14, 15, 16, 17, 19, 20, 21, 23, 24, 25, 26, 27, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 58, 59, 60, 63, 65, 66, 70, 74, 75, 78, 79, 83, 86, 87, 88, 89, 90, 91, 92, 93, 94, 96, 97, 98, 99, 101, 102, 103, 104, 105, 106, 107, 108, 110, 111, 112, 113, 114, 115, 116, 117, 118, 120, 121, 122, 124, 125
}};
inline constexpr std::array<int, 31> asset_only_zero_based_indices{{
    1, 6, 10, 11, 13, 18, 22, 28, 36, 57, 61, 62, 64, 67, 68, 69, 71, 72, 73, 76, 77, 80, 81, 82, 84, 85, 95, 100, 109, 119, 123
}};

template <std::size_t Size>
constexpr bool contains(
    const std::array<int, Size>& values, int value) noexcept {
    for (const auto candidate : values)
        if (candidate == value)
            return true;
    return false;
}

constexpr bool is_reachable_zero_based(int index) noexcept {
    return contains(reachable_zero_based_indices, index);
}

constexpr bool is_asset_only_zero_based(int index) noexcept {
    return contains(asset_only_zero_based_indices, index);
}

struct AuditedEnvironmentEntry final {
    int zero_based_index;
    int one_based_index;
    int gfl_index;
    const char* category;
    const char* event_key;
    const char* resource_name;
    const char* reachability;
};

inline constexpr std::array<AuditedEnvironmentEntry, 25> audited_environment_entries{{
    {10, 11, 1277, "vehicle", "boat", "船01.wav", "asset_only"},
    {11, 12, 1278, "vehicle", "boat", "船02.wav", "asset_only"},
    {12, 13, 1279, "animal", "dog", "喘气（狗）.wav", "sprite_group_queued"},
    {15, 16, 1293, "animal", "pig", "低吼（猪）.wav", "sprite_group_queued"},
    {16, 17, 1294, "animal", "chicken", "动作（鸡）.wav", "sprite_group_queued"},
    {17, 18, 1295, "vehicle", "handcart", "独轮车.wav", "sprite_group_queued"},
    {20, 21, 1318, "animal", "seagull", "海鸥01.wav", "sprite_group_queued"},
    {21, 22, 1319, "vehicle", "train", "火车.wav", "sprite_group_queued"},
    {22, 23, 1320, "vehicle", "train", "火车蒸汽.wav", "asset_only"},
    {23, 24, 1321, "vehicle", "train", "火车蒸汽01.wav", "sprite_group_queued"},
    {24, 25, 1322, "animal", "dog", "惊吓（狗）.wav", "sprite_group_queued"},
    {25, 26, 1323, "animal", "chicken", "惊吓（鸡）.wav", "sprite_group_queued"},
    {26, 27, 1334, "animal", "cattle", "鸣叫（牛）.wav", "sprite_group_queued"},
    {27, 28, 1335, "vehicle", "motorcycle", "摩托车.wav", "sprite_group_queued"},
    {28, 29, 1336, "vehicle", "motorcycle", "摩托车02.wav", "asset_only"},
    {30, 31, 1340, "vehicle", "car", "汽车01.wav", "sprite_group_queued"},
    {31, 32, 1341, "vehicle", "car", "汽车02.wav", "sprite_group_queued"},
    {32, 33, 1342, "vehicle", "car", "汽车03.wav", "sprite_group_queued"},
    {33, 34, 1343, "vehicle", "car", "汽车04.wav", "sprite_group_queued"},
    {60, 61, 1307, "animal", "dog", "攻击（军犬）.wav", "sprite_group_queued"},
    {61, 62, 1391, "ambience", "rain", "雨声02.wav", "asset_only"},
    {100, 101, 1333, "ambience", "thunder", "雷声.wav", "asset_only"},
    {123, 124, 1390, "ambience", "rain", "雨声.wav", "asset_only"},
    {124, 125, 1393, "ui", "ui_confirm", "按钮.wav", "ui_button_immediate"},
    {125, 126, 1324, "alert", "alert", "警报.wav", "sprite_group_and_general_queued"},
}};

constexpr const AuditedEnvironmentEntry* find_environment_entry(
    int zero_based_index) noexcept {
    for (const auto& entry : audited_environment_entries)
        if (entry.zero_based_index == zero_based_index)
            return &entry;
    return nullptr;
}

}  // namespace m1937::sdk::sound
