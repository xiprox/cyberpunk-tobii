# Record

What we found and decided while building Tobii head tracking for Cyberpunk 2077, newest entry first.
[README.md](README.md) says what the mod does; this file says why it's that way.

"Replayed" marks a number from a probe in [experiments/](experiments), which runs a JavaScript port of the mod's math on a recorded head or a constructed case, so it shows what the code computes, not what the game draws.
"User" marks what the user saw in the game: Cyberpunk 2077 2.5, Cyber Engine Tweaks 1.38.0, Native Settings 1.97, and Tobii Stream Engine 4.25.0.3 with a Tobii Eye Tracker 5.

Not yet checked in the game: whether raise/lower and forward/back move the right way, whether the car auto-centering values the mod writes to TweakDB take effect, how often the game rewrites the camera transform (the overlay counts it), and the headrest lean from the passenger seat or on a bike.

## 2026-10-27: The settings menu shows every option

Native Settings 1.97 can set an option's value on screen with `setOption`, which the Smoothness preset uses to move its two sliders, but has no way to gray an option out (read in its `init.lua`).
We tried hiding options whose switch was off, and the user rejected it: someone who switches off the neck model by accident would never find the options under it (user).
Every option stays visible, and each description stands on its own and names any switch the option needs.

## 2026-10-27: Past 85 degrees the spine twists, a car seat holds the back, and on foot the head stops at 100 degrees

With the neck alone, the eyes curl round behind the head on a far turn: 5.7 cm left and 13.7 cm back at 135° (replayed).
Past 85°, eased in over 30°, the rest of the turn twists the spine around an axis 4 cm behind the neck, and the body reaches forward 8 cm per 45° of twist, which puts the eyes 15.5 cm left and 9.4 cm back at 135° (replayed).
In a car, not on a bike, the back stays against the seat, so the twist loses any movement backward and the reach goes toward the dashboard.
Looking back from a car seat also leans the eyes sideways past the headrest, 8 cm toward the door and 16 cm toward the middle so the rear window shows, with the side worked out from which side of the car's center line the player sits on.
At 135° the driver's eyes end up 16.7 cm out toward the door or 24.7 cm toward the middle (replayed).
On foot, yaw follows the head to 90° and eases to a stop at 100°, because a person turns their body to look further.
The user found the twist "correct", the headrest lean "excellent", and the on-foot stop "very good" (user).
Evidence: [twist](experiments/areas/camera/results/twist-2026-10-27.txt), [headrest](experiments/areas/camera/results/headrest-2026-10-27.txt).

## 2026-10-27: The plugin's One Euro filter stays, set by a Smoothness preset

With the One Euro filter off, head turns felt janky (user).
Replayed on the turns recording with the jitter filter on:

| One Euro min cutoff / beta | Delay on turns | Roughness while turning |
| --- | --- | --- |
| Off | 19ms | 772°/s² |
| 0.4 Hz / 0.4, Responsive | 33ms | 483°/s² |
| 0.5 Hz / 0.1, Smooth | 54ms | 340°/s² |
| 1.0 Hz / 0.05, Very smooth | 65ms | 290°/s² |

Roughness is the RMS frame-to-frame change in camera speed.
Blending between samples along a curve instead of a straight line made turns rougher, 963°/s² against 772°/s².
The Smoothness choice sets the filter, Responsive by default, and the user found turns smooth again at 0.4 / 0.4 (user).
Evidence: [smooth-motion](experiments/areas/tracking/results/smooth-motion-2026-10-27.txt).

## 2026-10-27: Leaning follows where the head is turned

Leaning forward while looking 90° right moves the camera 10 cm right, toward what the player looks at, and leaning left moves it forward (replayed).
"Leaning follows your view" can also tip the lean by the head's pitch, or turn it off so leaning always moves toward the screen.
Evidence: [lean](experiments/areas/camera/results/lean-2026-10-27.txt).

## 2026-10-27: The tracker's x axis isn't mirrored

Leaning left moved the camera right (user), because the mod negated the tracker's x, as cyber-headtrack, another Tobii mod for the game, does.
In the turns recording, turning the head about 20° the way that turns the camera left reads x -30 mm to -33 mm, and eyes in front of the neck move toward the turn, so the tracker's -x is already the player's left.
The mod takes x as the tracker gives it, and the lean went the right way (user).
Evidence: [analyze-turns](experiments/areas/tracking/results/analyze-turns-2026-10-27.txt).

## 2026-10-27: A neck model puts back the eyes' swing that calibration takes out

Head-turn calibration took the eyes' real swing out along with the tracker's errors, and turning felt unnatural without it (user).
Letting the tracker's own shift back in would tie the swing to position sensitivity and bring back its distance error, so the mod models a neck instead: the eyes sit 8 cm in front of and 7.5 cm above a pivot, and the camera's rotation swings them around it.
A 60° turn moves the eyes 6.9 cm sideways and 4.0 cm back, and looking 30° down moves them 2.7 cm forward and 5.0 cm down (replayed).
Evidence: [neck](experiments/areas/camera/results/neck-2026-10-27.txt).

## 2026-10-27: A jitter filter that caps how far the camera trails replaces the deadzone

Held still, the tracker's pose wanders 0.35° to 0.53° and up to about 1 mm peak to peak, depending on the axis (medians over 262 still windows of the first recording).
A deadzone only works at center, leaves a flat spot there, and keeps the camera short of the head everywhere else.
A threshold that held the camera until the head moved 0.75° and then caught up felt jumpy (user), and replayed on a nudge test it moved the camera 0.77° in one frame while the head moved 0.44°.
A catch-up speed that rises with the gap added 67ms of delay on turns.
Capping the gap at 0.4° and letting the camera settle onto the head over 0.5s never moved the camera faster than the head, didn't shake while holding, ended within 0.1° of the target, and added 17ms (replayed); the user found small adjustments smooth (user).
Evidence: [noise](experiments/areas/tracking/results/noise-2026-10-27.txt), [nudge](experiments/areas/tracking/results/nudge-2026-10-27.txt).

## 2026-10-27: Head-turn calibration takes the V out

Calibrated on the turns from 8s to 20s of the turns recording and replayed on the turns from 20s to 31s, the camera's pitch across the turn went from 2.3° to 9.7° down to 1.1° to 3.6°, and its backward slide at 60° right from 9.4 cm to 0.9 cm (replayed).
Calibration records each axis against yaw in 2.5° steps over 15s and subtracts it, and after calibrating, the user found the V gone (user).
Evidence: [replay-calibration](experiments/areas/tracking/results/replay-calibration-2026-10-27.txt).

## 2026-10-26: Turning the head also reads as pitch and distance

The view traced a V when sweeping side to side, lowest at the center (user).
In the turns recording, pitch read 6.0° still and 8.7° to 9.8° at the ends of turns about 20° each way, which at a pitch sensitivity of 3 is about 10° of camera rise on each side.
Distance grew 32 mm to 35 mm turning one way and 6 mm to 17 mm the other, mostly the tracker's distance estimate (unverified), while x moved 1.76 mm per degree, about what eyes 10 cm in front of the neck do.
The 0.5° deadzone the user suspected couldn't make a dip that size.
Evidence: [analyze-turns](experiments/areas/tracking/results/analyze-turns-2026-10-27.txt), [timeline](experiments/areas/tracking/results/timeline-2026-10-27.txt), and the recordings in [experiments/areas/tracking/results](experiments/areas/tracking/results), made with `tobii_probe record`.

## 2026-10-26: Head turns rotate around a level axis measured from the camera system

Turning the head swept the view along a slant whenever it was pitched, in a car and on foot (user), because the mod turned around the camera's own up.
The mod reads the camera system's right and forward vectors each frame, takes its own offset back out, and turns around the car's up, or the horizon's on foot, which works whether the game holds the pitch in the camera component or above it.
Replayed with the view pitched 12° down and the head held 90° left, the horizon's roll went from 12° to 0°, and to at most 0.95° if the camera system reports a frame late; the user found turns level (user).
Evidence: [level-axis](experiments/areas/camera/results/level-axis-2026-10-27.txt).

## 2026-10-26: The mod works in the game

The user ruled out opentrack, whose Tobii driver breaks Tobii support built into other games such as Microsoft Flight Simulator, and mouse input, which would turn the aim (user).
So a RED4ext plugin loads `tobii_stream_engine.dll` from the Tobii Experience install, with the functions it uses checked against the DLL by disassembly, and smooths each sample, and a Cyber Engine Tweaks mod reads it once a frame and offsets the first-person camera component's local transform.
Stream Engine delivers about 33 head poses a second, 4,016 valid samples in 121.3s of recording; another program can read the tracker while the game holds it, and a paused tracker sends only invalid samples.
The game writes the same camera transform when the player aims or gets in a car, so each frame the mod treats a value it didn't write as the game's new base and offsets that.
In a car the camera turned with the head, and it "worked pretty well" (user).
