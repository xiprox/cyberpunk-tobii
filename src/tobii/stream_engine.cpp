#include "tobii/stream_engine.hpp"

#include <type_traits>

namespace tobii
{
StreamEngine::~StreamEngine()
{
    Unload();
}

std::filesystem::path StreamEngine::DefaultDllPath()
{
    wchar_t programFiles[MAX_PATH]{};
    DWORD len = GetEnvironmentVariableW(L"ProgramW6432", programFiles, MAX_PATH);
    if (len == 0 || len >= MAX_PATH)
    {
        len = GetEnvironmentVariableW(L"ProgramFiles", programFiles, MAX_PATH);
    }
    std::filesystem::path root = (len > 0 && len < MAX_PATH) ? programFiles : L"C:\\Program Files";
    return root / L"Tobii" / L"Tobii EyeX" / L"tobii_stream_engine.dll";
}

bool StreamEngine::Load(const std::filesystem::path& dllPath, std::string& error)
{
    Unload();

    if (!std::filesystem::exists(dllPath))
    {
        error = "Tobii runtime not found at " + dllPath.string() + " (is Tobii Experience installed?)";
        return false;
    }

    // Let the DLL resolve its own dependencies from its folder.
    m_module = LoadLibraryExW(dllPath.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!m_module)
    {
        error = "Could not load " + dllPath.string() + " (Windows error " + std::to_string(GetLastError()) + ")";
        return false;
    }
    m_path = dllPath;

    bool ok = true;
    auto resolve = [&](auto& fn, const char* name) {
        fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(GetProcAddress(m_module, name));
        if (!fn)
        {
            error = std::string("Tobii runtime is missing ") + name;
            ok = false;
        }
    };

    resolve(get_api_version, "tobii_get_api_version");
    resolve(api_create, "tobii_api_create");
    resolve(api_destroy, "tobii_api_destroy");
    resolve(enumerate_local_device_urls, "tobii_enumerate_local_device_urls");
    resolve(device_create, "tobii_device_create");
    resolve(device_destroy, "tobii_device_destroy");
    resolve(device_reconnect, "tobii_device_reconnect");
    resolve(device_process_callbacks, "tobii_device_process_callbacks");
    resolve(wait_for_callbacks, "tobii_wait_for_callbacks");
    resolve(head_pose_subscribe, "tobii_head_pose_subscribe");
    resolve(head_pose_unsubscribe, "tobii_head_pose_unsubscribe");
    resolve(error_message, "tobii_error_message");
    if (!ok)
    {
        Unload();
        return false;
    }

    // The 4-argument tobii_device_create we declare only exists from 4.x on.
    tobii_version_t version{};
    if (get_api_version(&version) != TOBII_ERROR_NO_ERROR || version.major < 4)
    {
        error = "Unsupported Tobii runtime version " + std::to_string(version.major) + "." +
                std::to_string(version.minor) + " (need 4.x or newer; update Tobii Experience)";
        Unload();
        return false;
    }

    return true;
}

std::string StreamEngine::ErrorText(tobii_error_t error) const
{
    const char* text = error_message ? error_message(error) : nullptr;
    return std::string(text ? text : "unknown error") + " (" + std::to_string(error) + ")";
}

void StreamEngine::Unload()
{
    if (m_module)
    {
        FreeLibrary(m_module);
        m_module = nullptr;
    }
    m_path.clear();
}
} // namespace tobii
