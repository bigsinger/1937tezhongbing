#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include <M1937SDK/M1937SDK.hpp>

namespace {

class PeFile final {
public:
    explicit PeFile(const char* path) {
        std::ifstream stream(path, std::ios::binary);
        if (!stream)
            throw std::runtime_error("cannot open executable");
        stream.seekg(0, std::ios::end);
        const auto length = stream.tellg();
        if (length <= 0)
            throw std::runtime_error("empty executable");
        data_.resize(static_cast<std::size_t>(length));
        stream.seekg(0, std::ios::beg);
        stream.read(
            reinterpret_cast<char*>(data_.data()),
            static_cast<std::streamsize>(data_.size()));
        if (!stream)
            throw std::runtime_error("cannot read executable");
        if (data_.size() < sizeof(IMAGE_DOS_HEADER))
            throw std::runtime_error("truncated DOS header");
        dos_ = reinterpret_cast<const IMAGE_DOS_HEADER*>(data_.data());
        if (dos_->e_magic != IMAGE_DOS_SIGNATURE ||
            dos_->e_lfanew <= 0 ||
            static_cast<std::size_t>(dos_->e_lfanew) >
                data_.size() - sizeof(IMAGE_NT_HEADERS32))
            throw std::runtime_error("invalid DOS header");
        nt_ = reinterpret_cast<const IMAGE_NT_HEADERS32*>(
            data_.data() + dos_->e_lfanew);
        if (nt_->Signature != IMAGE_NT_SIGNATURE)
            throw std::runtime_error("invalid PE signature");
    }

    [[nodiscard]] const IMAGE_NT_HEADERS32& nt() const noexcept {
        return *nt_;
    }
    [[nodiscard]] std::size_t size() const noexcept {
        return data_.size();
    }

    [[nodiscard]] const std::byte* at_rva(
        std::uint32_t rva,
        std::size_t length) const {
        const auto* section = IMAGE_FIRST_SECTION(nt_);
        for (std::uint16_t index = 0;
             index < nt_->FileHeader.NumberOfSections;
             index++, section++) {
            const auto virtual_size = section->Misc.VirtualSize;
            const auto mapped_size =
                virtual_size > section->SizeOfRawData
                    ? virtual_size
                    : section->SizeOfRawData;
            if (rva < section->VirtualAddress ||
                rva >= section->VirtualAddress + mapped_size)
                continue;
            const auto offset =
                static_cast<std::size_t>(section->PointerToRawData) +
                (rva - section->VirtualAddress);
            if (offset > data_.size() ||
                length > data_.size() - offset)
                throw std::runtime_error("RVA extends past file");
            return data_.data() + offset;
        }
        if (rva < nt_->OptionalHeader.SizeOfHeaders &&
            rva <= data_.size() &&
            length <= data_.size() - rva)
            return data_.data() + rva;
        throw std::runtime_error("RVA is not mapped by the PE file");
    }

private:
    std::vector<std::byte> data_;
    const IMAGE_DOS_HEADER* dos_{};
    const IMAGE_NT_HEADERS32* nt_{};
};

template <std::size_t Size>
void require_signature(
    const PeFile& file,
    std::uint32_t rva,
    const unsigned char (&expected)[Size],
    const char* name,
    int& checks) {
    if (std::memcmp(file.at_rva(rva, Size), expected, Size) != 0)
        throw std::runtime_error(std::string("signature mismatch: ") + name);
    checks++;
}

void require(bool value, const char* description, int& checks) {
    if (!value)
        throw std::runtime_error(description);
    checks++;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 2) {
            std::cerr << "Usage: M1937SDK.Tests.exe M1937.exe\n";
            return 2;
        }
        const PeFile file(argv[1]);
        const auto& nt = file.nt();
        int checks = 0;
        require(
            file.size() == m1937::sdk::ExecutableIdentity::file_size,
            "file size mismatch", checks);
        require(
            nt.FileHeader.Machine == IMAGE_FILE_MACHINE_I386,
            "executable is not x86", checks);
        require(
            nt.FileHeader.TimeDateStamp ==
                m1937::sdk::ExecutableIdentity::pe_timestamp,
            "PE timestamp mismatch", checks);
        require(
            nt.OptionalHeader.ImageBase ==
                m1937::sdk::ExecutableIdentity::preferred_image_base,
            "preferred image base mismatch", checks);
        require(
            nt.OptionalHeader.SizeOfImage ==
                m1937::sdk::ExecutableIdentity::image_size,
            "image size mismatch", checks);
        require(
            nt.OptionalHeader.AddressOfEntryPoint ==
                m1937::sdk::ExecutableIdentity::entry_point_rva,
            "entry point mismatch", checks);

        static constexpr unsigned char safe_blit[] = {
            0x83, 0xEC, 0x2C, 0x53, 0x55, 0x56};
        static constexpr unsigned char menu_poll[] = {
            0x8B, 0x44, 0x24, 0x04, 0x53, 0x55};
        static constexpr unsigned char warning[] = {0x74, 0x0C};
        static constexpr unsigned char level[] = {
            0x01, 0x00, 0x00, 0x00};
        require_signature(
            file, m1937::sdk::rva::safe_blit,
            safe_blit, "SafeBlit", checks);
        require_signature(
            file, m1937::sdk::rva::menu_poll,
            menu_poll, "MenuPoll", checks);
        require_signature(
            file, m1937::sdk::rva::false_resource_warning_branch,
            warning, "FalseResourceWarningBranch", checks);
        require_signature(
            file, m1937::sdk::rva::new_game_level_immediate,
            level, "NewGameLevelImmediate", checks);
        require(
            std::memcmp(
                file.at_rva(
                    m1937::sdk::rva::mission_12_vwf_name, 13),
                "1937M011.VWF", 13) == 0,
            "mission 12 filename mismatch", checks);
        require(
            std::memcmp(
                file.at_rva(
                    m1937::sdk::rva::mission_7_vwf_name, 13),
                "1937M006.VWF", 13) == 0,
            "mission 7 filename mismatch", checks);

        std::cout << "M1937SDK validation passed (" << checks
                  << " executable checks, native layout static_asserts passed).\n";
        return 0;
    } catch (const std::exception& exception) {
        std::cerr << "M1937SDK validation failed: "
                  << exception.what() << "\n";
        return 1;
    }
}
