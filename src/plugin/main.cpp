// RED4ext plugin: reads head pose from the Tobii runtime and exposes it to game scripts as the native
// class TobiiHeadTracking (static functions, callable from CET Lua and redscript). Applying it to the
// camera, the settings UI and hotkeys live in the CET mod.

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/RTTITypes.hpp>
#include <RED4ext/Scripting/IScriptable.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>
#include <RED4ext/Scripting/Utils.hpp>

#include "tobii/head_pose_reader.hpp"
#include "tracking/pose_smoother.hpp"

#include <mutex>
#include <string>

namespace
{
// THT_VERSION and its parts come from version.txt through CMakeLists.txt, which release-please bumps.
constexpr const char* kVersion = THT_VERSION;

// A sample older than this means the tracker lost the head (looked away, left the seat).
constexpr float kLostAfterMs = 400.f;

const RED4ext::v1::Sdk* g_sdk = nullptr;
RED4ext::v1::PluginHandle g_handle = nullptr;

std::mutex g_controlMutex; // guards starting/stopping the reader and the runtime path
std::filesystem::path g_runtimePath;
tobii::HeadPoseReader g_reader;
tracking::PoseSmoother g_smoother;

void Log(const std::string& message)
{
    if (g_sdk)
    {
        g_sdk->logger->Info(g_handle, message.c_str());
    }
}

void StartReader()
{
    g_smoother.Reset();
    g_reader.Start(g_runtimePath, Log, [](const tobii::HeadPose& pose) {
        tracking::Pose sample{pose.yawDeg, pose.pitchDeg, pose.rollDeg, pose.xMm, pose.yMm, pose.zMm};
        g_smoother.Push(sample, pose.deviceTimeUs, pose.receivedAt);
    });
}

bool Evaluate(tracking::Pose& pose, float& ageMs)
{
    pose = {};
    ageMs = -1.f;
    return g_smoother.Evaluate(tracking::Clock::now(), pose, ageMs);
}
} // namespace

struct TobiiHeadTracking : RED4ext::IScriptable
{
    RED4ext::CClass* GetNativeType();
};

RED4ext::TTypedClass<TobiiHeadTracking> g_class("TobiiHeadTracking");

RED4ext::CClass* TobiiHeadTracking::GetNativeType()
{
    return &g_class;
}

namespace natives
{
// X = pitch, Y = yaw, Z = roll in degrees (Tobii axes, smoothed). W = ms since the last valid sample,
// or -1 if nothing has been received yet.
void GetRotation(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    aFrame->code++; // skip ParamEnd
    tracking::Pose pose;
    float ageMs;
    Evaluate(pose, ageMs);
    if (aOut)
    {
        *aOut = {pose[tracking::Pitch], pose[tracking::Yaw], pose[tracking::Roll], ageMs};
    }
}

// X/Y/Z head position in mm relative to the tracker (+x right, +y up, +z toward the user). W as above.
void GetPosition(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::Vector4* aOut, int64_t)
{
    aFrame->code++;
    tracking::Pose pose;
    float ageMs;
    Evaluate(pose, ageMs);
    if (aOut)
    {
        *aOut = {pose[tracking::X], pose[tracking::Y], pose[tracking::Z], ageMs};
    }
}

void IsTracking(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    aFrame->code++;
    tracking::Pose pose;
    float ageMs;
    bool have = Evaluate(pose, ageMs);
    if (aOut)
    {
        *aOut = g_reader.GetState() == tobii::State::Tracking && have && ageMs < kLostAfterMs;
    }
}

void GetStatus(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    if (!aOut)
    {
        return;
    }

    tobii::State state = g_reader.GetState();
    std::string text = tobii::ToString(state);
    if (state == tobii::State::Tracking)
    {
        tracking::Pose pose;
        float ageMs;
        if (!Evaluate(pose, ageMs) || ageMs >= kLostAfterMs)
        {
            text = "Connected, no head detected";
        }
    }
    else
    {
        std::string detail = g_reader.GetDetail();
        if (!detail.empty())
        {
            text += ": " + detail;
        }
    }
    *aOut = RED4ext::CString(text.c_str());
}

void GetVersion(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    aFrame->code++;
    if (aOut)
    {
        *aOut = RED4ext::CString(kVersion);
    }
}

void SetSmoothing(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    float minCutoffHz = 1.f;
    float beta = 0.05f;
    float interpolationDelayMs = 35.f;
    RED4ext::GetParameter(aFrame, &minCutoffHz);
    RED4ext::GetParameter(aFrame, &beta);
    RED4ext::GetParameter(aFrame, &interpolationDelayMs);
    aFrame->code++;

    g_smoother.Configure({minCutoffHz, beta, interpolationDelayMs});
}

// Starts or stops talking to the tracker. Stopping releases it for other apps.
void SetEnabled(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    bool enabled = true;
    RED4ext::GetParameter(aFrame, &enabled);
    aFrame->code++;

    std::lock_guard lock(g_controlMutex);
    if (enabled && !g_reader.IsRunning())
    {
        StartReader();
    }
    else if (!enabled && g_reader.IsRunning())
    {
        g_reader.Stop();
        Log("Tobii: stopped by settings");
    }
}

// Overrides where tobii_stream_engine.dll is loaded from (the DLL or its folder). Empty string = Tobii
// Experience default.
void SetRuntimePath(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, void*, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);
    aFrame->code++;

    std::lock_guard lock(g_controlMutex);
    std::filesystem::path newPath(std::u8string(reinterpret_cast<const char8_t*>(path.c_str())));
    std::error_code ec;
    if (!newPath.empty() && std::filesystem::is_directory(newPath, ec))
    {
        newPath /= L"tobii_stream_engine.dll";
    }
    if (newPath == g_runtimePath)
    {
        return;
    }
    g_runtimePath = newPath;
    if (g_reader.IsRunning())
    {
        StartReader();
    }
}
} // namespace natives

namespace
{
void AddStatic(const char* name, RED4ext::ScriptingFunction_t<void*> fn, const char* returnType,
               std::initializer_list<std::pair<const char*, const char*>> params = {})
{
    auto* func = RED4ext::CClassStaticFunction::Create(&g_class, name, name, fn);
    func->flags = {.isNative = true, .isStatic = true};
    if (returnType)
    {
        func->SetReturnType(returnType);
    }
    for (const auto& [type, paramName] : params)
    {
        func->AddParam(type, paramName);
    }
    g_class.RegisterFunction(func);
}

template<typename T>
RED4ext::ScriptingFunction_t<void*> Erase(void (*fn)(RED4ext::IScriptable*, RED4ext::CStackFrame*, T*, int64_t))
{
    return reinterpret_cast<RED4ext::ScriptingFunction_t<void*>>(fn);
}

void RegisterTypes()
{
    RED4ext::CNamePool::Add("TobiiHeadTracking");
    g_class.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_class);
}

void PostRegisterTypes()
{
    g_class.parent = RED4ext::CRTTISystem::Get()->GetClass("IScriptable");

    AddStatic("GetRotation", Erase(&natives::GetRotation), "Vector4");
    AddStatic("GetPosition", Erase(&natives::GetPosition), "Vector4");
    AddStatic("IsTracking", Erase(&natives::IsTracking), "Bool");
    AddStatic("GetStatus", Erase(&natives::GetStatus), "String");
    AddStatic("GetVersion", Erase(&natives::GetVersion), "String");
    AddStatic("SetSmoothing", Erase(&natives::SetSmoothing), nullptr,
              {{"Float", "minCutoffHz"}, {"Float", "beta"}, {"Float", "interpolationDelayMs"}});
    AddStatic("SetEnabled", Erase(&natives::SetEnabled), nullptr, {{"Bool", "enabled"}});
    AddStatic("SetRuntimePath", Erase(&natives::SetRuntimePath), nullptr, {{"String", "path"}});
}
} // namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        g_handle = aHandle;
        g_sdk = aSdk;

        auto* rtti = RED4ext::CRTTISystem::Get();
        rtti->AddRegisterCallback(RegisterTypes);
        rtti->AddPostRegisterCallback(PostRegisterTypes);

        Log(std::string("TobiiHeadTracking ") + kVersion + " loaded");
        std::lock_guard lock(g_controlMutex);
        StartReader();
        break;
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        std::lock_guard lock(g_controlMutex);
        g_reader.Stop();
        g_sdk = nullptr;
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"TobiiHeadTracking";
    aInfo->author = L"ihsan";
    aInfo->version = RED4EXT_V1_SEMVER(THT_VERSION_MAJOR, THT_VERSION_MINOR, THT_VERSION_PATCH);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_LATEST;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
