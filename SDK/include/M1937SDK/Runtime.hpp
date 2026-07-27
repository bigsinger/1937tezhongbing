#pragma once

#include <cstdint>

#include "Addresses.hpp"
#include "Module.hpp"
#include "Types.hpp"

namespace m1937::sdk {

class RuntimeState final {
public:
    explicit RuntimeState(ModuleView module) noexcept : module_(module) {}

    [[nodiscard]] std::int32_t& current_mission() const noexcept {
        return module_.reference<std::int32_t>(rva::current_mission);
    }
    [[nodiscard]] std::int32_t& cursor_x() const noexcept {
        return module_.reference<std::int32_t>(rva::cursor_x);
    }
    [[nodiscard]] std::int32_t& cursor_y() const noexcept {
        return module_.reference<std::int32_t>(rva::cursor_y);
    }
    [[nodiscard]] std::uint8_t& briefing_advance() const noexcept {
        return module_.reference<std::uint8_t>(rva::briefing_advance);
    }
    [[nodiscard]] std::int32_t& mouse_left_pressed() const noexcept {
        return module_.reference<std::int32_t>(rva::mouse_left_pressed);
    }
    [[nodiscard]] std::int32_t& mouse_left_down() const noexcept {
        return module_.reference<std::int32_t>(rva::mouse_left_down);
    }
    [[nodiscard]] std::int32_t& mouse_left_released() const noexcept {
        return module_.reference<std::int32_t>(rva::mouse_left_released);
    }
    [[nodiscard]] SizeI32 logical_screen_size() const noexcept {
        return {
            module_.reference<std::int32_t>(rva::screen_width),
            module_.reference<std::int32_t>(rva::screen_height)};
    }
    [[nodiscard]] SizeI32 renderer_size() const noexcept {
        return {
            module_.reference<std::int32_t>(rva::renderer_width),
            module_.reference<std::int32_t>(rva::renderer_height)};
    }

private:
    ModuleView module_;
};

}  // namespace m1937::sdk
