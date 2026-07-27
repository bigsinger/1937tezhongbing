#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "Addresses.hpp"

namespace m1937::sdk {

enum class BuildCompatibility {
    supported,
    null_module,
    invalid_dos_header,
    invalid_nt_header,
    wrong_architecture,
    wrong_image_base,
    wrong_image_size,
    wrong_timestamp,
    signature_mismatch
};

class ModuleView final {
public:
    explicit ModuleView(HMODULE module) noexcept
        : base_(reinterpret_cast<std::byte*>(module)) {}

    static ModuleView current_process() noexcept {
        return ModuleView(GetModuleHandleW(nullptr));
    }

    [[nodiscard]] std::byte* base() const noexcept {
        return base_;
    }

    template <typename T>
    [[nodiscard]] T* pointer(std::uintptr_t rva_value) const noexcept {
        return reinterpret_cast<T*>(base_ + rva_value);
    }

    template <typename T>
    [[nodiscard]] T& reference(std::uintptr_t rva_value) const noexcept {
        return *pointer<T>(rva_value);
    }

    [[nodiscard]] BuildCompatibility compatibility() const noexcept {
        if (!base_)
            return BuildCompatibility::null_module;
        const auto* dos =
            reinterpret_cast<const IMAGE_DOS_HEADER*>(base_);
        if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0)
            return BuildCompatibility::invalid_dos_header;
        const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(
            base_ + dos->e_lfanew);
        if (nt->Signature != IMAGE_NT_SIGNATURE)
            return BuildCompatibility::invalid_nt_header;
        if (nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
            nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC)
            return BuildCompatibility::wrong_architecture;
        if (nt->OptionalHeader.ImageBase !=
            ExecutableIdentity::preferred_image_base)
            return BuildCompatibility::wrong_image_base;
        if (nt->OptionalHeader.SizeOfImage !=
            ExecutableIdentity::image_size)
            return BuildCompatibility::wrong_image_size;
        if (nt->FileHeader.TimeDateStamp !=
            ExecutableIdentity::pe_timestamp)
            return BuildCompatibility::wrong_timestamp;

        static constexpr unsigned char warning[] = {0x74, 0x0C};
        static constexpr unsigned char level[] = {0x01, 0x00, 0x00, 0x00};
        static constexpr unsigned char safe_blit[] = {
            0x83, 0xEC, 0x2C, 0x53, 0x55, 0x56};
        static constexpr unsigned char menu_poll[] = {
            0x8B, 0x44, 0x24, 0x04, 0x53, 0x55};
        if (!matches(rva::false_resource_warning_branch, warning) ||
            !matches(rva::new_game_level_immediate, level) ||
            !matches(rva::safe_blit, safe_blit) ||
            !matches(rva::menu_poll, menu_poll) ||
            std::memcmp(
                pointer<const char>(rva::mission_12_vwf_name),
                "1937M011.VWF", 13) != 0 ||
            std::memcmp(
                pointer<const char>(rva::mission_7_vwf_name),
                "1937M006.VWF", 13) != 0)
            return BuildCompatibility::signature_mismatch;
        return BuildCompatibility::supported;
    }

    [[nodiscard]] bool is_supported() const noexcept {
        return compatibility() == BuildCompatibility::supported;
    }

private:
    template <std::size_t Size>
    [[nodiscard]] bool matches(
        std::uintptr_t rva_value,
        const unsigned char (&expected)[Size]) const noexcept {
        return std::memcmp(
            pointer<const unsigned char>(rva_value),
            expected,
            Size) == 0;
    }

    std::byte* base_;
};

}  // namespace m1937::sdk
