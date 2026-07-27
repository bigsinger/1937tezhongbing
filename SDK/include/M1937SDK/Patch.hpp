#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "Module.hpp"

namespace m1937::sdk::patch {

inline bool bytes(
    void* address,
    const void* expected,
    const void* replacement,
    std::size_t size) noexcept {
    if (!address || !expected || !replacement || size == 0 ||
        std::memcmp(address, expected, size) != 0)
        return false;

    DWORD old_protection = 0;
    if (!VirtualProtect(
            address, size, PAGE_EXECUTE_READWRITE, &old_protection))
        return false;
    std::memcpy(address, replacement, size);
    FlushInstructionCache(GetCurrentProcess(), address, size);
    DWORD ignored = 0;
    VirtualProtect(address, size, old_protection, &ignored);
    return true;
}

inline bool bytes(
    const ModuleView& module,
    std::uintptr_t rva_value,
    const void* expected,
    const void* replacement,
    std::size_t size) noexcept {
    return bytes(
        module.pointer<void>(rva_value),
        expected,
        replacement,
        size);
}

inline bool immediate_i32(
    const ModuleView& module,
    std::uintptr_t operand_rva,
    std::int32_t expected,
    std::int32_t replacement) noexcept {
    return bytes(
        module,
        operand_rva,
        &expected,
        &replacement,
        sizeof(replacement));
}

inline bool relative_jump(
    void* address,
    const void* expected,
    std::size_t size,
    const void* destination) noexcept {
    if (!address || !expected || !destination ||
        size < 5 || size > 16 ||
        std::memcmp(address, expected, size) != 0)
        return false;

    unsigned char replacement[16]{};
    std::memset(replacement, 0x90, size);
    replacement[0] = 0xE9;
    const auto from = reinterpret_cast<std::intptr_t>(address) + 5;
    const auto to = reinterpret_cast<std::intptr_t>(destination);
    const auto relative = to - from;
    if (relative < INT32_MIN || relative > INT32_MAX)
        return false;
    const auto displacement = static_cast<std::int32_t>(relative);
    std::memcpy(
        replacement + 1, &displacement, sizeof(displacement));
    return bytes(
        address, expected, replacement, size);
}

}  // namespace m1937::sdk::patch
