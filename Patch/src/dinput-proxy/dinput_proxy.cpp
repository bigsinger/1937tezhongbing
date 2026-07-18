#define WIN32_LEAN_AND_MEAN
#define DIRECTINPUT_VERSION 0x0300

#include <windows.h>
#include <dinput.h>
#include <cstddef>
#include <cstring>
#include <new>

namespace {

using DirectInputCreateAProc = HRESULT(WINAPI *)(
    HINSTANCE, DWORD, LPDIRECTINPUTA *, LPUNKNOWN);

HMODULE g_real_dinput = nullptr;
DirectInputCreateAProc g_real_create = nullptr;

bool PatchExecutableBytes(
    unsigned char *address, const unsigned char *expected,
    const unsigned char *replacement, size_t size) {
    if (memcmp(address, expected, size) != 0) {
        return false;
    }

    DWORD old_protection = 0;
    if (!VirtualProtect(address, size, PAGE_EXECUTE_READWRITE, &old_protection)) {
        return false;
    }
    memcpy(address, replacement, size);
    FlushInstructionCache(GetCurrentProcess(), address, size);
    DWORD ignored = 0;
    VirtualProtect(address, size, old_protection, &ignored);
    return true;
}

void ApplyLegacyExecutablePatches() {
    auto *base = reinterpret_cast<unsigned char *>(GetModuleHandleW(nullptr));
    if (!base) {
        return;
    }

    const auto *dos = reinterpret_cast<const IMAGE_DOS_HEADER *>(base);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) {
        return;
    }
    const auto *nt = reinterpret_cast<const IMAGE_NT_HEADERS32 *>(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->OptionalHeader.ImageBase != 0x00400000 ||
        nt->OptionalHeader.SizeOfImage != 0x00124000) {
        return;
    }

    // The green release reports a false resource-library error even though
    // both GFL archives have already opened successfully.
    static const unsigned char warning_expected[] = {0x74, 0x0C};
    static const unsigned char warning_patch[] = {0xEB, 0x0C};
    PatchExecutableBytes(
        base + 0x0000734A, warning_expected, warning_patch,
        sizeof(warning_patch));

    // Skip only the two startup movie enqueue calls. Mission movies and all
    // gameplay resources remain untouched.
    static const unsigned char movies_expected[] = {
        0x68, 0x8C, 0xF7, 0x4C, 0x00, 0x53, 0x53, 0x8B, 0xCE, 0xE8,
        0x7E, 0x9B, 0xFF, 0xFF, 0x68, 0x7C, 0xF7, 0x4C, 0x00, 0x6A,
        0x64, 0x53, 0x8B, 0xCE, 0xE8, 0x6F, 0x9B, 0xFF, 0xFF};
    unsigned char movies_nops[sizeof(movies_expected)];
    memset(movies_nops, 0x90, sizeof(movies_nops));
    PatchExecutableBytes(
        base + 0x0000762C, movies_expected, movies_nops,
        sizeof(movies_nops));
}

void PumpWindowMessages() {
    MSG message{};
    for (int count = 0; count < 64; ++count) {
        if (!PeekMessageA(&message, nullptr, 0, 0, PM_REMOVE)) {
            break;
        }
        if (message.message == WM_QUIT) {
            PostQuitMessage(static_cast<int>(message.wParam));
            break;
        }
        TranslateMessage(&message);
        DispatchMessageA(&message);
    }
}

bool LoadRealDInput() {
    if (g_real_create) {
        return true;
    }

    wchar_t system_directory[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(system_directory, MAX_PATH);
    if (length == 0 || length >= MAX_PATH - 12) {
        return false;
    }
    lstrcatW(system_directory, L"\\dinput.dll");

    g_real_dinput = LoadLibraryW(system_directory);
    if (!g_real_dinput) {
        return false;
    }
    g_real_create = reinterpret_cast<DirectInputCreateAProc>(
        GetProcAddress(g_real_dinput, "DirectInputCreateA"));
    return g_real_create != nullptr;
}

class DeviceProxy final : public IDirectInputDeviceA {
public:
    explicit DeviceProxy(LPDIRECTINPUTDEVICEA real) : real_(real) {}

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
        return real_->GetDeviceState(size, data);
    }
    HRESULT STDMETHODCALLTYPE GetDeviceData(
        DWORD object_size, LPDIDEVICEOBJECTDATA data, LPDWORD count,
        DWORD flags) override {
        PumpWindowMessages();
        return real_->GetDeviceData(object_size, data, count, flags);
    }
    HRESULT STDMETHODCALLTYPE SetDataFormat(LPCDIDATAFORMAT format) override {
        return real_->SetDataFormat(format);
    }
    HRESULT STDMETHODCALLTYPE SetEventNotification(HANDLE event) override {
        return real_->SetEventNotification(event);
    }
    HRESULT STDMETHODCALLTYPE SetCooperativeLevel(HWND window, DWORD flags) override {
        return real_->SetCooperativeLevel(window, flags);
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

        auto *proxy = new (std::nothrow) DeviceProxy(real_device);
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
    if (!LoadRealDInput()) {
        return DIERR_NOTINITIALIZED;
    }

    LPDIRECTINPUTA real = nullptr;
    const HRESULT result = g_real_create(instance, version, &real, outer);
    if (FAILED(result)) {
        return result;
    }

    auto *proxy = new (std::nothrow) DirectInputProxy(real);
    if (!proxy) {
        real->Release();
        return E_OUTOFMEMORY;
    }
    *direct_input = proxy;
    return result;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        ApplyLegacyExecutablePatches();
    }
    return TRUE;
}
