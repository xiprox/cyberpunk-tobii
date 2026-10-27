#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

namespace tobii
{
struct tobii_head_pose_t;

// One head pose sample in friendly units, still in Tobii's axes:
// +x right, +y up, +z toward the user (out of the screen).
struct HeadPose
{
    float pitchDeg = 0.f; // rotation about x
    float yawDeg = 0.f;   // rotation about y
    float rollDeg = 0.f;  // rotation about z
    float xMm = 0.f;
    float yMm = 0.f;
    float zMm = 0.f;
    bool rotationValid = false; // all three rotation axes valid
    bool positionValid = false;
    int64_t deviceTimeUs = 0;
    std::chrono::steady_clock::time_point receivedAt{};
    uint64_t sequence = 0; // increments per sample; 0 means nothing received yet
};

enum class State
{
    Stopped,
    RuntimeMissing, // tobii_stream_engine.dll not found or unusable
    NoDevice,       // runtime loaded but no tracker found
    Connecting,
    Tracking,
    Error,
};

const char* ToString(State state);

// Owns a background thread that connects to the first Tobii tracker, subscribes to head
// pose and keeps reconnecting if the tracker or the Tobii service goes away.
class HeadPoseReader
{
public:
    using LogFn = std::function<void(const std::string&)>;
    // Called on the tracker thread for every sample with a valid head rotation.
    using SampleFn = std::function<void(const HeadPose&)>;

    HeadPoseReader() = default;
    ~HeadPoseReader();
    HeadPoseReader(const HeadPoseReader&) = delete;
    HeadPoseReader& operator=(const HeadPoseReader&) = delete;

    // dllPath may be empty to use the default Tobii Experience location.
    void Start(std::filesystem::path dllPath, LogFn log, SampleFn onSample = {});
    bool IsRunning() const { return m_thread.joinable(); }
    void Stop();

    HeadPose Latest() const;
    State GetState() const;
    std::string GetDetail() const;

private:
    void Run(std::stop_token stop);
    void SetState(State state, std::string detail);
    void Log(const std::string& message) const;
    bool SleepFor(std::stop_token& stop, std::chrono::milliseconds duration);

    static void OnHeadPose(const tobii_head_pose_t* pose, void* user);
    static void Store(HeadPose& out, const tobii_head_pose_t& pose);

    mutable std::mutex m_mutex;
    HeadPose m_latest;
    State m_state = State::Stopped;
    std::string m_detail;

    std::mutex m_sleepMutex;
    std::condition_variable_any m_sleepCv;

    std::filesystem::path m_dllPath;
    LogFn m_log;
    SampleFn m_onSample;
    std::jthread m_thread;
};
} // namespace tobii
