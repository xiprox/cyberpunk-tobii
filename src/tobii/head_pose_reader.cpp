#include "tobii/head_pose_reader.hpp"

#include "tobii/stream_engine.hpp"

#include <numbers>

namespace tobii
{
namespace
{
constexpr float kRadToDeg = 180.f / std::numbers::pi_v<float>;

constexpr auto kRetryNoRuntime = std::chrono::seconds(10);
constexpr auto kRetryNoDevice = std::chrono::seconds(3);
constexpr auto kRetryReconnect = std::chrono::seconds(1);

void ReceiveFirstUrl(char const* url, void* user)
{
    auto* out = static_cast<std::string*>(user);
    if (out->empty() && url)
    {
        *out = url;
    }
}
} // namespace

const char* ToString(State state)
{
    switch (state)
    {
    case State::Stopped:
        return "Stopped";
    case State::RuntimeMissing:
        return "Tobii runtime missing";
    case State::NoDevice:
        return "No tracker found";
    case State::Connecting:
        return "Connecting";
    case State::Tracking:
        return "Tracking";
    case State::Error:
        return "Error";
    }
    return "Unknown";
}

HeadPoseReader::~HeadPoseReader()
{
    Stop();
}

void HeadPoseReader::Start(std::filesystem::path dllPath, LogFn log, SampleFn onSample)
{
    Stop();
    m_dllPath = dllPath.empty() ? StreamEngine::DefaultDllPath() : std::move(dllPath);
    m_log = std::move(log);
    m_onSample = std::move(onSample);
    m_thread = std::jthread([this](std::stop_token stop) { Run(stop); });
}

void HeadPoseReader::Stop()
{
    if (m_thread.joinable())
    {
        m_thread.request_stop();
        m_sleepCv.notify_all();
        m_thread.join();
    }
    SetState(State::Stopped, {});
}

HeadPose HeadPoseReader::Latest() const
{
    std::lock_guard lock(m_mutex);
    return m_latest;
}

State HeadPoseReader::GetState() const
{
    std::lock_guard lock(m_mutex);
    return m_state;
}

std::string HeadPoseReader::GetDetail() const
{
    std::lock_guard lock(m_mutex);
    return m_detail;
}

void HeadPoseReader::SetState(State state, std::string detail)
{
    {
        std::lock_guard lock(m_mutex);
        if (m_state == state && m_detail == detail)
        {
            return;
        }
        m_state = state;
        m_detail = detail;
    }
    if (state != State::Stopped)
    {
        Log(std::string("Tobii: ") + ToString(state) + (detail.empty() ? "" : " - " + detail));
    }
}

void HeadPoseReader::Log(const std::string& message) const
{
    if (m_log)
    {
        m_log(message);
    }
}

bool HeadPoseReader::SleepFor(std::stop_token& stop, std::chrono::milliseconds duration)
{
    std::unique_lock lock(m_sleepMutex);
    m_sleepCv.wait_for(lock, stop, duration, [] { return false; });
    return !stop.stop_requested();
}

void HeadPoseReader::OnHeadPose(const tobii_head_pose_t* pose, void* user)
{
    auto* self = static_cast<HeadPoseReader*>(user);

    HeadPose copy;
    {
        std::lock_guard lock(self->m_mutex);
        Store(self->m_latest, *pose);
        copy = self->m_latest;
    }
    if (copy.rotationValid && self->m_onSample)
    {
        self->m_onSample(copy);
    }
}

void HeadPoseReader::Store(HeadPose& out, const tobii_head_pose_t& pose)
{
    out.rotationValid = pose.rotation_validity_xyz[0] == TOBII_VALIDITY_VALID &&
                        pose.rotation_validity_xyz[1] == TOBII_VALIDITY_VALID &&
                        pose.rotation_validity_xyz[2] == TOBII_VALIDITY_VALID;
    out.positionValid = pose.position_validity == TOBII_VALIDITY_VALID;

    // Keep the last good values when a sample is invalid so the camera holds still.
    if (out.rotationValid)
    {
        out.pitchDeg = pose.rotation_xyz[0] * kRadToDeg;
        out.yawDeg = pose.rotation_xyz[1] * kRadToDeg;
        out.rollDeg = pose.rotation_xyz[2] * kRadToDeg;
    }
    if (out.positionValid)
    {
        out.xMm = pose.position_xyz[0];
        out.yMm = pose.position_xyz[1];
        out.zMm = pose.position_xyz[2];
    }
    out.deviceTimeUs = pose.timestamp_us;
    out.receivedAt = std::chrono::steady_clock::now();
    ++out.sequence;
}

void HeadPoseReader::Run(std::stop_token stop)
{
    StreamEngine engine;
    tobii_api_t* api = nullptr;

    while (!stop.stop_requested())
    {
        if (!engine.IsLoaded())
        {
            std::string error;
            if (!engine.Load(m_dllPath, error))
            {
                SetState(State::RuntimeMissing, error);
                SleepFor(stop, kRetryNoRuntime);
                continue;
            }
            tobii_version_t version{};
            engine.get_api_version(&version);
            Log("Tobii: loaded " + m_dllPath.string() + " (Stream Engine " + std::to_string(version.major) + "." +
                std::to_string(version.minor) + "." + std::to_string(version.revision) + "." +
                std::to_string(version.build) + ")");
        }

        if (!api)
        {
            tobii_error_t error = engine.api_create(&api, nullptr, nullptr);
            if (error != TOBII_ERROR_NO_ERROR)
            {
                api = nullptr;
                SetState(State::Error, "Could not start the Tobii API: " + engine.ErrorText(error));
                SleepFor(stop, kRetryNoRuntime);
                continue;
            }
        }

        std::string url;
        tobii_error_t error = engine.enumerate_local_device_urls(api, ReceiveFirstUrl, &url);
        if (error != TOBII_ERROR_NO_ERROR || url.empty())
        {
            SetState(State::NoDevice, error != TOBII_ERROR_NO_ERROR ? engine.ErrorText(error)
                                                                     : "Is the eye tracker plugged in?");
            SleepFor(stop, kRetryNoDevice);
            continue;
        }

        SetState(State::Connecting, url);
        tobii_device_t* device = nullptr;
        error = engine.device_create(api, url.c_str(), TOBII_FIELD_OF_USE_INTERACTIVE, &device);
        if (error != TOBII_ERROR_NO_ERROR)
        {
            SetState(State::Error, "Could not connect to " + url + ": " + engine.ErrorText(error));
            SleepFor(stop, kRetryNoDevice);
            continue;
        }

        error = engine.head_pose_subscribe(device, &HeadPoseReader::OnHeadPose, this);
        if (error != TOBII_ERROR_NO_ERROR)
        {
            SetState(State::Error, "Tracker does not provide head pose: " + engine.ErrorText(error));
            engine.device_destroy(device);
            SleepFor(stop, kRetryNoRuntime);
            continue;
        }

        SetState(State::Tracking, url);

        while (!stop.stop_requested())
        {
            error = engine.wait_for_callbacks(1, &device);
            if (error != TOBII_ERROR_NO_ERROR && error != TOBII_ERROR_TIMED_OUT &&
                error != TOBII_ERROR_CONNECTION_FAILED)
            {
                SetState(State::Error, "Waiting for data failed: " + engine.ErrorText(error));
                break;
            }

            error = engine.device_process_callbacks(device);
            if (error == TOBII_ERROR_CONNECTION_FAILED)
            {
                SetState(State::Connecting, "Connection lost, reconnecting");
                while (!stop.stop_requested() && engine.device_reconnect(device) != TOBII_ERROR_NO_ERROR)
                {
                    SleepFor(stop, kRetryReconnect);
                }
                if (!stop.stop_requested())
                {
                    SetState(State::Tracking, url);
                }
            }
            else if (error != TOBII_ERROR_NO_ERROR)
            {
                SetState(State::Error, "Reading data failed: " + engine.ErrorText(error));
                break;
            }
        }

        engine.head_pose_unsubscribe(device);
        engine.device_destroy(device);

        if (!stop.stop_requested())
        {
            SleepFor(stop, kRetryReconnect);
        }
    }

    if (api)
    {
        engine.api_destroy(api);
    }
}
} // namespace tobii
