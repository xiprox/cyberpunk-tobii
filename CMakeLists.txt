cmake_minimum_required(VERSION 3.25)

# version.txt holds the mod's version, and release-please bumps it when it opens a release.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt" THT_VERSION LIMIT_COUNT 1)
project(TobiiHeadTracking VERSION ${THT_VERSION} LANGUAGES CXX)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_definitions(WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
add_compile_options(/W4 /utf-8 /permissive-)

# MSVC can't open files past 260 characters, so the SDK may need to live somewhere short.
set(RED4EXT_SDK_DIR "${CMAKE_SOURCE_DIR}/deps/RED4ext.SDK" CACHE PATH "Path to a RED4ext.SDK checkout")

# Tobii Stream Engine binding, background head pose reader and smoothing, shared by the plugin and the probe.
add_library(tracking STATIC
    src/tobii/stream_engine.cpp
    src/tobii/head_pose_reader.cpp
    src/tracking/pose_smoother.cpp
)
target_include_directories(tracking PUBLIC src)

add_executable(tobii_probe tools/tobii_probe.cpp)
target_link_libraries(tobii_probe PRIVATE tracking)

if(EXISTS "${RED4EXT_SDK_DIR}/CMakeLists.txt")
    set(RED4EXT_HEADER_ONLY ON CACHE BOOL "" FORCE)
    add_subdirectory("${RED4EXT_SDK_DIR}" red4ext_sdk EXCLUDE_FROM_ALL)

    add_library(TobiiHeadTracking SHARED src/plugin/main.cpp)
    target_link_libraries(TobiiHeadTracking PRIVATE tracking RED4ext::SDK)
    target_compile_definitions(TobiiHeadTracking PRIVATE
        THT_VERSION="${PROJECT_VERSION}"
        THT_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        THT_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        THT_VERSION_PATCH=${PROJECT_VERSION_PATCH})
    # The SDK headers don't build cleanly at /W4.
    target_compile_options(TobiiHeadTracking PRIVATE /W3)

    install(TARGETS TobiiHeadTracking RUNTIME DESTINATION "red4ext/plugins/TobiiHeadTracking")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/cet/TobiiHeadTracking/"
            DESTINATION "bin/x64/plugins/cyber_engine_tweaks/mods/TobiiHeadTracking"
            PATTERN "settings.json" EXCLUDE)
else()
    message(WARNING "RED4ext.SDK not found at ${RED4EXT_SDK_DIR}; only the probe will be built.")
endif()
