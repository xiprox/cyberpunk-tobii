#include "tracking/pose_smoother.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace tracking
{
namespace
{
// Derivative cutoff for the One Euro filter; the paper's recommended default.
constexpr float kDerivativeCutoffHz = 1.0f;

// A gap longer than this means the head was lost; start fresh instead of blending across it.
constexpr int64_t kGapResetUs = 500'000;

constexpr size_t kMaxSamples = 16;

int64_t ToMicroseconds(Clock::time_point time)
{
    return std::chrono::duration_cast<std::chrono::microseconds>(time.time_since_epoch()).count();
}
} // namespace

float OneEuroFilter::Alpha(float cutoffHz, float dtSeconds)
{
    float tau = 1.f / (2.f * std::numbers::pi_v<float> * cutoffHz);
    return 1.f / (1.f + tau / dtSeconds);
}

float OneEuroFilter::Apply(float value, float dtSeconds, float minCutoffHz, float beta)
{
    if (!m_initialized)
    {
        m_initialized = true;
        m_value = value;
        m_derivative = 0.f;
        return value;
    }

    float derivative = (value - m_value) / dtSeconds;
    m_derivative += Alpha(kDerivativeCutoffHz, dtSeconds) * (derivative - m_derivative);

    float cutoff = std::max(minCutoffHz, 0.001f) + std::max(beta, 0.f) * std::abs(m_derivative);
    m_value += Alpha(cutoff, dtSeconds) * (value - m_value);
    return m_value;
}

void PoseSmoother::Configure(const SmoothingSettings& settings)
{
    std::lock_guard lock(m_mutex);
    m_settings = settings;
}

SmoothingSettings PoseSmoother::Settings() const
{
    std::lock_guard lock(m_mutex);
    return m_settings;
}

void PoseSmoother::Reset()
{
    std::lock_guard lock(m_mutex);
    for (auto& filter : m_filters)
    {
        filter.Reset();
    }
    m_samples.clear();
    m_lastDeviceTimeUs = 0;
    m_haveClockOffset = false;
}

void PoseSmoother::Push(const Pose& pose, int64_t deviceTimeUs, Clock::time_point receivedAt)
{
    std::lock_guard lock(m_mutex);

    int64_t gapUs = deviceTimeUs - m_lastDeviceTimeUs;
    if (m_lastDeviceTimeUs == 0 || gapUs <= 0 || gapUs > kGapResetUs)
    {
        for (auto& filter : m_filters)
        {
            filter.Reset();
        }
        m_samples.clear();
        gapUs = 30'000;
    }
    m_lastDeviceTimeUs = deviceTimeUs;

    // Map the tracker clock onto ours. Delivery delay only ever adds latency, so the smallest offset
    // seen is the best estimate; let it creep upward slowly to follow clock drift.
    double offset = static_cast<double>(ToMicroseconds(receivedAt) - deviceTimeUs);
    if (!m_haveClockOffset || offset < m_clockOffsetUs)
    {
        m_clockOffsetUs = offset;
        m_haveClockOffset = true;
    }
    else
    {
        m_clockOffsetUs += (offset - m_clockOffsetUs) * 0.01;
    }

    float dt = static_cast<float>(gapUs) / 1'000'000.f;
    Sample sample;
    for (int i = 0; i < ChannelCount; ++i)
    {
        sample.pose[i] = m_filters[i].Apply(pose[i], dt, m_settings.minCutoffHz, m_settings.beta);
    }
    sample.time = Clock::time_point(
        std::chrono::microseconds(deviceTimeUs + static_cast<int64_t>(m_clockOffsetUs)));

    m_samples.push_back(sample);
    while (m_samples.size() > kMaxSamples)
    {
        m_samples.pop_front();
    }
    m_lastValidAt = receivedAt;
}

bool PoseSmoother::Evaluate(Clock::time_point now, Pose& out, float& ageMs) const
{
    std::lock_guard lock(m_mutex);
    if (m_samples.empty())
    {
        return false;
    }

    ageMs = std::chrono::duration<float, std::milli>(now - m_lastValidAt).count();

    auto delay = std::chrono::duration_cast<Clock::duration>(
        std::chrono::duration<float, std::milli>(std::max(m_settings.interpolationDelayMs, 0.f)));
    if (delay.count() == 0 || m_samples.size() == 1)
    {
        out = m_samples.back().pose;
        return true;
    }

    Clock::time_point renderAt = now - delay;
    if (renderAt <= m_samples.front().time)
    {
        out = m_samples.front().pose;
        return true;
    }
    if (renderAt >= m_samples.back().time)
    {
        out = m_samples.back().pose;
        return true;
    }

    for (size_t i = 1; i < m_samples.size(); ++i)
    {
        const Sample& b = m_samples[i];
        if (b.time < renderAt)
        {
            continue;
        }
        const Sample& a = m_samples[i - 1];
        float span = std::chrono::duration<float>(b.time - a.time).count();
        float t = span > 0.f ? std::chrono::duration<float>(renderAt - a.time).count() / span : 1.f;
        for (int c = 0; c < ChannelCount; ++c)
        {
            out[c] = a.pose[c] + (b.pose[c] - a.pose[c]) * t;
        }
        return true;
    }

    out = m_samples.back().pose;
    return true;
}
} // namespace tracking
