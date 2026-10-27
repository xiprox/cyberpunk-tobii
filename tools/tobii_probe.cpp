// Console check that head pose comes through from the Tobii runtime, without the game.
//
//   tobii_probe [seconds] [path\to\tobii_stream_engine.dll]
//   tobii_probe record <seconds> <file.csv>     every raw sample, for looking at how axes interact

#include "tobii/head_pose_reader.hpp"
#include "tobii/stream_engine.hpp"
#include "tracking/pose_smoother.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static int Record(int seconds, const char* file)
{
    std::FILE* csv = nullptr;
    if (fopen_s(&csv, file, "w") != 0 || !csv)
    {
        std::printf("FAIL: can't write %s\n", file);
        return 1;
    }
    std::fprintf(csv, "t_ms,yaw,pitch,roll,x,y,z,rot_ok,pos_ok\n");

    tobii::HeadPoseReader reader;
    int64_t firstUs = -1;
    reader.Start(
        tobii::StreamEngine::DefaultDllPath(), [](const std::string& message) { std::printf("[log] %s\n", message.c_str()); },
        [&](const tobii::HeadPose& p) {
            if (firstUs < 0)
            {
                firstUs = p.deviceTimeUs;
            }
            std::fprintf(csv, "%.1f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%d,%d\n", (p.deviceTimeUs - firstUs) / 1000.0,
                         p.yawDeg, p.pitchDeg, p.rollDeg, p.xMm, p.yMm, p.zMm, p.rotationValid ? 1 : 0,
                         p.positionValid ? 1 : 0);
        });
    for (int s = seconds; s > 0; --s)
    {
        std::printf("recording, %d s left (%s)\n", s, tobii::ToString(reader.GetState()));
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    reader.Stop();
    std::fclose(csv);
    std::printf("done: %llu samples\n", static_cast<unsigned long long>(reader.Latest().sequence));
    return 0;
}

int main(int argc, char** argv)
{
    if (argc > 3 && std::strcmp(argv[1], "record") == 0)
    {
        return Record(std::atoi(argv[2]), argv[3]);
    }

    int seconds = argc > 1 ? std::atoi(argv[1]) : 10;
    std::filesystem::path dllPath = argc > 2 ? std::filesystem::path(argv[2]) : tobii::StreamEngine::DefaultDllPath();

    {
        tobii::StreamEngine engine;
        std::string error;
        if (!engine.Load(dllPath, error))
        {
            std::printf("FAIL: %s\n", error.c_str());
            return 1;
        }
        tobii::tobii_version_t version{};
        engine.get_api_version(&version);
        std::printf("Stream Engine %d.%d.%d.%d at %s\n", version.major, version.minor, version.revision,
                    version.build, dllPath.string().c_str());
        std::printf("Error codes: 5=%s | 6=%s\n", engine.ErrorText(5).c_str(), engine.ErrorText(6).c_str());
    }

    tracking::PoseSmoother smoother;
    tobii::HeadPoseReader reader;
    reader.Start(
        dllPath, [](const std::string& message) { std::printf("[log] %s\n", message.c_str()); },
        [&smoother](const tobii::HeadPose& pose) {
            smoother.Push({pose.yawDeg, pose.pitchDeg, pose.rollDeg, pose.xMm, pose.yMm, pose.zMm},
                          pose.deviceTimeUs, pose.receivedAt);
        });

    uint64_t firstSequence = 0;
    auto startTime = std::chrono::steady_clock::now();
    for (int tick = 0; tick < seconds * 4; ++tick)
    {
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
        tobii::HeadPose pose = reader.Latest();
        if (pose.sequence == 0)
        {
            std::printf("  waiting... state=%s %s\n", tobii::ToString(reader.GetState()), reader.GetDetail().c_str());
            continue;
        }
        if (firstSequence == 0)
        {
            firstSequence = pose.sequence;
            startTime = std::chrono::steady_clock::now();
        }
        std::printf("  #%-6llu rot(p/y/r) %7.2f %7.2f %7.2f %s | pos(x/y/z mm) %7.1f %7.1f %7.1f %s",
                    static_cast<unsigned long long>(pose.sequence), pose.pitchDeg, pose.yawDeg, pose.rollDeg,
                    pose.rotationValid ? "ok " : "INV", pose.xMm, pose.yMm, pose.zMm,
                    pose.positionValid ? "ok" : "INV");

        tracking::Pose smoothed;
        float ageMs = 0.f;
        if (smoother.Evaluate(tracking::Clock::now(), smoothed, ageMs))
        {
            std::printf(" || smoothed p/y/r %7.2f %7.2f %7.2f age %3.0fms", smoothed[tracking::Pitch],
                        smoothed[tracking::Yaw], smoothed[tracking::Roll], ageMs);
        }
        std::printf("\n");
    }

    tobii::HeadPose last = reader.Latest();
    double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - startTime).count();
    if (last.sequence > firstSequence && elapsed > 0)
    {
        std::printf("Sample rate: %.1f Hz\n", (last.sequence - firstSequence) / elapsed);
    }

    auto stopStart = std::chrono::steady_clock::now();
    reader.Stop();
    std::printf("Stop took %.0f ms\n",
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - stopStart).count());
    return last.sequence > 0 ? 0 : 2;
}
