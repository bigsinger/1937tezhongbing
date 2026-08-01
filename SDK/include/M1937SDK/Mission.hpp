#pragma once

#include <cstddef>
#include <cstdint>

namespace m1937::sdk::mission {

// Raw values written by sub_405410 to both the game-flow state at +0xA4 and
// the mission-result state at +0xC0. Values outside this recovered transition
// pair are deliberately treated as active/unknown by observers.
enum class Outcome : std::int32_t {
    unknown = 0,
    failed = 2,
    victory = 3,
};

#pragma pack(push, 1)
// State prefix of the main game controller passed as ECX to sub_404BB0 and
// sub_405410. The unknown bytes remain opaque; only fields proven by all
// twelve mission branches are named.
struct RuntimeControllerStateV1 final {
    std::byte unknown_000[0x0A4];
    std::int32_t game_flow_state;        // +0x0A4
    std::byte unknown_0a8[0x14];
    std::int32_t evaluation_active;      // +0x0BC
    std::int32_t result_state;           // +0x0C0
};
#pragma pack(pop)

constexpr Outcome outcome_from_raw(std::int32_t value) noexcept {
    return value == static_cast<std::int32_t>(Outcome::failed)
        ? Outcome::failed
        : value == static_cast<std::int32_t>(Outcome::victory)
            ? Outcome::victory
            : Outcome::unknown;
}

constexpr const char* outcome_name(Outcome value) noexcept {
    switch (value) {
    case Outcome::failed:
        return "failed";
    case Outcome::victory:
        return "victory";
    case Outcome::unknown:
        return "active";
    }
    return "active";
}

static_assert(
    offsetof(RuntimeControllerStateV1, game_flow_state) == 0x0A4);
static_assert(
    offsetof(RuntimeControllerStateV1, evaluation_active) == 0x0BC);
static_assert(
    offsetof(RuntimeControllerStateV1, result_state) == 0x0C0);
static_assert(sizeof(RuntimeControllerStateV1) == 0x0C4);

}  // namespace m1937::sdk::mission
