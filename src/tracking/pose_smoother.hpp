#pragma once

#include <array>
#include <chrono>
#include <cstdint>
#include <deque>
#include <mutex>

namespace tracking
{
using Clock = std::chrono::steady_clock;

// Channel order used throughout: yaw, pitch, roll (degrees), x, y, z (mm). Tobii axes.
enum Channel
{
    Yaw,
    Pitch,
    Roll,
    X,
    Y,
    Z,
    ChannelCount
};

using Pose = std::array<float, ChannelCount>;

struct SmoothingSettings
{
    // One Euro filter: lower min cutoff = steadier at rest but more lag; higher beta = less lag on fast moves.
    float minCutoffHz = 1.0f;
    float beta = 0.05f;
    // The tracker only reports ~33 times a second. Rendering this far behind the newest sample lets us
    // interpolate between samples so the camera moves every frame instead of stepping. 0 disables it.
    float interpolationDelayMs = 35.f;
};

// One Euro filter (Casiez et al. 2012) for a single channel.
class OneEuroFilter
{
public:
    float Apply(float value, float dtSeconds, float minCutoffHz, float beta);
    void Reset() { m_initialized = false; }

private:
    static float Alpha(float cutoffHz, float dtSeconds);

    bool m_initialized = false;
    float m_value = 0.f;
    float m_derivative = 0.f;
};

// Filters tracker samples as they arrive (tracker thread) and serves an interpolated pose for any
// moment (game thread).
class PoseSmoother
{
public:
    void Configure(const SmoothingSettings& settings);
    SmoothingSettings Settings() const;

    void Push(const Pose& pose, int64_t deviceTimeUs, Clock::time_point receivedAt);

    // Returns false until the first valid sample. ageMs is the time since the last valid sample.
    bool Evaluate(Clock::time_point now, Pose& out, float& ageMs) const;

    void Reset();

private:
    struct Sample
    {
        Pose pose;
        Clock::time_point time;
    };

    mutable std::mutex m_mutex;
    SmoothingSettings m_settings;
    std::array<OneEuroFilter, ChannelCount> m_filters;
    std::deque<Sample> m_samples; // oldest first
    int64_t m_lastDeviceTimeUs = 0;
    bool m_haveClockOffset = false;
    double m_clockOffsetUs = 0.0; // local arrival time minus device time
    Clock::time_point m_lastValidAt{};
};
} // namespace tracking
