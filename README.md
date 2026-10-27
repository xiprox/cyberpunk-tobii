# Tobii Head Tracking for Cyberpunk 2077

Head tracking for Cyberpunk 2077 with a Tobii Eye Tracker 5.
A RED4ext plugin reads head pose from Tobii's Stream Engine, and a Cyber Engine Tweaks (CET) mod offsets the first-person camera with it, in vehicles and on foot.
It doesn't use opentrack or mouse emulation.

## Parts

- `TobiiHeadTracking.dll`, the RED4ext plugin, loads `tobii_stream_engine.dll` from your Tobii Experience install, reads about 33 head poses a second, and smooths and blends them so the camera moves every frame.
- `cet/TobiiHeadTracking`, the CET mod, turns the pose into a camera offset with your settings every frame, and runs the settings menu, the hotkeys, and the overlay.

[RECORD.md](RECORD.md) explains why each part works the way it does.

## Requirements

- A Tobii Eye Tracker 5, with Tobii Experience installed and tracking not paused.
  Other trackers that Tobii Experience drives, such as the Eye Tracker 4C, may work, but none has been tried.
- RED4ext.
- Cyber Engine Tweaks.
- Native Settings, for the in-game settings page.
  Without it, you change settings in `settings.json`, and the CET overlay keeps Recenter and Calibrate head turns.

Tested with Cyberpunk 2077 2.5, Cyber Engine Tweaks 1.38.0, Native Settings 1.97, and Tobii Stream Engine 4.25.

## Installation

Each release on the repository's Releases page has a zip, `TobiiHeadTracking-<version>.zip`, laid out as the game folder is, so you extract it into the game folder.
You can also build the mod and let `cmake --install` copy it into the game, as [Build](#build) describes.
Either way, the game folder then holds:

```text
<Cyberpunk 2077>/red4ext/plugins/TobiiHeadTracking/TobiiHeadTracking.dll
<Cyberpunk 2077>/bin/x64/plugins/cyber_engine_tweaks/mods/TobiiHeadTracking/
```

The second folder is a copy of this repository's `cet/TobiiHeadTracking`.

## First run

1. In the game, sit the way you normally look at the screen, and press Recenter, in Settings > Mods > Head Tracking, in the CET overlay, or on its hotkey.
   The overlay's Center row then matches its Head row.
2. Press Calibrate head turns, close the menu, and look at the screen center.
   A message counts down 5 seconds, then tells you to turn your head.
3. Slowly turn your head fully left and right a few times, for 15 seconds.
   A message then gives the range you covered, such as "Head turns calibrated from -25 to 23 degrees".

Turning your head also makes the tracker report some pitch and position change, which would make the view rise, dip, and slide as you look around.
Calibration records how much at each angle, and the mod subtracts it.

## Settings

The settings are in Settings > Mods > Head Tracking, and the mod saves them to `settings.json` in its CET folder.
You bind the hotkeys, for toggling head tracking, recentering, calibrating head turns, and holding to pause, in the CET overlay under Bindings.
The CET overlay also shows the tracker's status and the mod's version, with your head pose and the camera's offset under Diagnostics.

| Section | Options |
| --- | --- |
| Getting started | Head tracking, Recenter, Calibrate head turns, In vehicles, On foot, and Smoothness |
| Sensitivity | How far the camera moves per degree or cm of head movement on each axis, and the turn limits in vehicles and on foot |
| Pause | Aiming, scenes, losing your head, and the fade time |
| Natural movement | Level head turns, leaning that follows your view, head-turn correction strength, and the neck model |
| Looking far back | The spine twist past the neck's range, and how far you reach forward |
| In the car | Car camera auto-centering, the seat holding your back, and leaning past the headrest |
| Advanced | Each axis's on/off, curve, limit, jitter filter, and invert, and the smoothing filter |

Smoothness picks how closely the camera follows your head: Responsive trails it by about 33ms, Smooth by about 50ms, and Very smooth by about 65ms.

## Camera movement

- Head turns rotate around the car's up, or the horizon's on foot, so the horizon stays level when the view is pitched up or down.
- The camera's eyes swing around a modeled neck, 8 cm behind and 7.5 cm below them, so turning moves them to the side and back, and looking down moves them forward and down.
  Calibration removes the tracker's own version of that shift, which position sensitivity would amplify.
- Past 85° the spine twists the rest of the way, and you reach forward.
- In a car your back stays against the seat, and looking back leans you past the headrest, further toward the middle of the car so you can see the rear window.
  The mod works out which seat you're in.
- On foot, head turns ease to a stop at 100°, because you'd turn your body to look further.
- Leaning follows your view: lean forward while looking right, and the camera moves right.
- The jitter filter holds the camera still against the tracker's jitter, and never lets it trail your head by more than 0.4°.

## Build

You need Visual Studio 2022 with the C++ workload, CMake 3.25 or newer, and git.

1. Clone the RED4ext SDK into `deps/`:

   ```powershell
   git clone --depth 1 https://github.com/WopsS/RED4ext.SDK deps/RED4ext.SDK
   ```

2. Configure the build:

   ```powershell
   cmake -S . -B build -G "Visual Studio 17 2022" -A x64
   ```

   CMake ends with "Build files have been written to".
3. Build it:

   ```powershell
   cmake --build build --config Release
   ```

   `build/Release` then holds `TobiiHeadTracking.dll` and `tobii_probe.exe`.
4. If the game is running, close it, because it holds the plugin's DLL open.
5. Install the mod into the game, with your game folder as the prefix if it isn't Steam's default:

   ```powershell
   cmake --install build --config Release --prefix "C:/Program Files (x86)/Steam/steamapps/common/Cyberpunk 2077"
   ```

If the repository sits in a deep folder, MSVC fails on paths longer than 260 characters, so put the build folder and the SDK somewhere short and pass `-DRED4EXT_SDK_DIR=<path>`.
Without the SDK, CMake builds only `tobii_probe.exe`.
A change to the Lua alone takes effect with the game running, through "Reload all mods" in the CET overlay.

## Development

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org), because [release-please](https://github.com/googleapis/release-please) reads them to version releases and write the changelog.
A `feat:` commit raises the minor version, a `fix:` commit the patch version, and a `!` after the type, as in `feat!:`, the major version, while `style:`, `refactor:`, `docs:`, `test:`, `ci:`, and `chore:` commits make no release.
[CLAUDE.md](CLAUDE.md#commits) has the rules for types, scopes, titles, and descriptions.
After each push to `main`, release-please updates a pull request with the next version and its changelog.
Merging that pull request publishes the release, and only then does the workflow build the mod and attach its zip.

The workflow also uploads each release's zip to Nexus Mods, through Nexus Mods' [upload action](https://github.com/Nexus-Mods/upload-action), which is in beta.
The action only adds a version to a file the mod page already has, so it needs a one-time setup:

1. On Nexus Mods, create the mod page and upload the first zip by hand.
2. In the mod page's Files tab, turn on Advanced.
   The mod's ID and the file's ID show beside the file.
3. Create an API key in your Nexus Mods account's [API keys settings](https://www.nexusmods.com/settings/api-keys).
4. In the GitHub repository's Settings, under Secrets and variables > Actions, add the key as the secret `NEXUSMODS_API_KEY`, and the IDs as the variables `NEXUSMODS_MOD_ID` and `NEXUSMODS_FILE_ID`.

From the next release on, the workflow uploads the zip as a new version of that file, with the release notes as its changelog, archives the version before it, and sets the mod page's version.
Until both variables exist, releases skip Nexus Mods.

- `tobii_probe.exe [seconds]` checks the tracker without the game and prints raw and smoothed head pose, and `tobii_probe.exe record <seconds> <file.csv>` saves every sample.
- [RECORD.md](RECORD.md) records what was found and decided while building the mod, and why.
- [experiments/](experiments) holds the probes and head-pose recordings the record cites, each probe's output in the `results` folder beside it.
  Each probe runs with Node:

  ```powershell
  node experiments/areas/camera/neck.js
  ```

## License

MIT, as [LICENSE](LICENSE) says.
The mod ships nothing from Tobii: it loads the Stream Engine that Tobii Experience installs.
