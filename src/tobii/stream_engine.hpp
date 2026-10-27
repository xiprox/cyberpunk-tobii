#pragma once

// Minimal runtime binding to the Tobii Stream Engine C API (4.x).
//
// We load tobii_stream_engine.dll from the user's Tobii Experience install instead of
// shipping Tobii binaries. Only the handful of calls needed for head pose are declared.
// Signatures were checked against the exported functions of tobii_stream_engine.dll 4.25.

#include <cstdint>
#include <filesystem>
#include <string>

#include <Windows.h>

namespace tobii
{
using tobii_error_t = int;

constexpr tobii_error_t TOBII_ERROR_NO_ERROR = 0;
constexpr tobii_error_t TOBII_ERROR_CONNECTION_FAILED = 5;
constexpr tobii_error_t TOBII_ERROR_TIMED_OUT = 6;

// TOBII_FIELD_OF_USE_INTERACTIVE (a.k.a. STORE_OR_TRANSFER_FALSE): data is used live, never stored.
constexpr int TOBII_FIELD_OF_USE_INTERACTIVE = 1;

constexpr int TOBII_VALIDITY_VALID = 1;

struct tobii_api_t;
struct tobii_device_t;

struct tobii_version_t
{
    int major;
    int minor;
    int revision;
    int build;
};

// Tobii axes: +x right, +y up, +z toward the user. Position in mm, rotation in radians
// (x = pitch, y = yaw, z = roll).
struct tobii_head_pose_t
{
    int64_t timestamp_us;
    int position_validity;
    float position_xyz[3];
    int rotation_validity_xyz[3];
    float rotation_xyz[3];
};
static_assert(sizeof(tobii_head_pose_t) == 48);

using tobii_device_url_receiver_t = void (*)(char const* url, void* user_data);
using tobii_head_pose_callback_t = void (*)(tobii_head_pose_t const* head_pose, void* user_data);

class StreamEngine
{
public:
    StreamEngine() = default;
    ~StreamEngine();
    StreamEngine(const StreamEngine&) = delete;
    StreamEngine& operator=(const StreamEngine&) = delete;

    // Loads the DLL and resolves every function. On failure returns false and fills error.
    bool Load(const std::filesystem::path& dllPath, std::string& error);
    bool IsLoaded() const { return m_module != nullptr; }
    const std::filesystem::path& Path() const { return m_path; }

    // Default install location of the Tobii Experience runtime (Eye Tracker 4C/5).
    static std::filesystem::path DefaultDllPath();

    std::string ErrorText(tobii_error_t error) const;

    tobii_error_t (*get_api_version)(tobii_version_t* version) = nullptr;
    tobii_error_t (*api_create)(tobii_api_t** api, void const* custom_alloc, void const* custom_log) = nullptr;
    tobii_error_t (*api_destroy)(tobii_api_t* api) = nullptr;
    tobii_error_t (*enumerate_local_device_urls)(tobii_api_t* api, tobii_device_url_receiver_t receiver,
                                                 void* user_data) = nullptr;
    tobii_error_t (*device_create)(tobii_api_t* api, char const* url, int field_of_use,
                                   tobii_device_t** device) = nullptr;
    tobii_error_t (*device_destroy)(tobii_device_t* device) = nullptr;
    tobii_error_t (*device_reconnect)(tobii_device_t* device) = nullptr;
    tobii_error_t (*device_process_callbacks)(tobii_device_t* device) = nullptr;
    tobii_error_t (*wait_for_callbacks)(int device_count, tobii_device_t* const* devices) = nullptr;
    tobii_error_t (*head_pose_subscribe)(tobii_device_t* device, tobii_head_pose_callback_t callback,
                                         void* user_data) = nullptr;
    tobii_error_t (*head_pose_unsubscribe)(tobii_device_t* device) = nullptr;
    char const* (*error_message)(tobii_error_t error) = nullptr;

private:
    void Unload();

    HMODULE m_module = nullptr;
    std::filesystem::path m_path;
};
} // namespace tobii
