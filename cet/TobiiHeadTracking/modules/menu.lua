-- In-game Settings menu (Settings > Mods > Head Tracking) via the Native Settings mod.
--
-- Native Settings can't collapse or hide options, so the order does the work: setup first, then the
-- everyday tuning, then how the head moves, then the car, then everything advanced at the bottom.

local Menu = {}

local TAB = "/tobiiHeadTracking"

-- onChange(section) is called after a value changes; section is "general", "smoothing", "enabled",
-- "autocenter" or "axes" so the caller can push the change where it needs to go. version is the
-- plugin's, or nil when the plugin didn't load.
function Menu.build(Settings, onChange, actions, version)
    local ns = GetMod("nativeSettings")
    if not ns then
        print("[TobiiHeadTracking] Native Settings not found; settings are only in the CET overlay and settings.json")
        return false
    end

    local s = Settings.values
    local d = Settings.defaults
    local r, rd = s.rotation, d.rotation
    local p, pd = s.position, d.position
    local n, nd = s.neck, d.neck
    local sm, smd = s.smoothing, d.smoothing

    ns.addTab(TAB, "Head Tracking", function()
        Settings.save()
    end)

    local function set(tbl, key, section)
        return function(value)
            tbl[key] = value
            Settings.dirty = true
            onChange(section)
        end
    end

    -- Smoothness presets set the movement smoothing sliders in Advanced: Smoothing; moving those by
    -- hand switches the preset to whichever matches, or Custom.
    local presetOption, cutoffOption, betaOption
    local applyingPreset = false

    local presetNames = {}
    for i, preset in ipairs(Settings.SMOOTHNESS_PRESETS) do
        presetNames[i] = preset.name
    end
    presetNames[Settings.SMOOTHNESS_CUSTOM] = "Custom"

    local function onPreset(index)
        sm.preset = index
        Settings.dirty = true
        local preset = Settings.SMOOTHNESS_PRESETS[index]
        if not preset then
            return -- Custom: the sliders stay as they are
        end
        sm.minCutoffHz, sm.beta = preset.minCutoffHz, preset.beta
        applyingPreset = true
        pcall(ns.setOption, cutoffOption, preset.minCutoffHz)
        pcall(ns.setOption, betaOption, preset.beta)
        applyingPreset = false
        onChange("smoothing")
    end

    local function onFilterSlider(key)
        return function(value)
            sm[key] = value
            Settings.dirty = true
            onChange("smoothing")
            if not applyingPreset then
                local preset = Settings.smoothnessPreset(sm)
                if preset ~= sm.preset then
                    sm.preset = preset
                    pcall(ns.setOption, presetOption, preset)
                end
            end
        end
    end

    -- Getting started -------------------------------------------------------------------------------
    local start = TAB .. "/start"
    ns.addSubcategory(start, "Getting started")
    local versionNote = version and ("Version " .. version .. ". ") or ""
    ns.addSwitch(start, "Head tracking", versionNote .. "Master switch. Also on a hotkey (CET > Bindings).",
        s.enabled, d.enabled, set(s, "enabled", "enabled"))
    ns.addButton(start, "Recenter", "Sit how you normally look at the screen, then press. Also on a hotkey.",
        "Recenter", 45, actions.recenter)
    ns.addButton(start, "Calibrate head turns",
        "Stops the view rising, dipping or sliding as you turn your head. Recenter first. Press, close the menu, and when told, slowly turn your head fully left and right a few times for 15 seconds. Also on a hotkey.",
        "Calibrate", 45, actions.calibrateTurns)
    ns.addSwitch(start, "In vehicles", "Look around with your head while driving or riding in first person.",
        s.inVehicles, d.inVehicles, set(s, "inVehicles", "general"))
    ns.addSwitch(start, "On foot", "Also use head tracking when walking around.",
        s.onFoot, d.onFoot, set(s, "onFoot", "general"))
    presetOption = ns.addSelectorString(start, "Smoothness",
        "Responsive follows your head most closely (about 33 ms behind). Smooth (about 50 ms) and Very smooth (about 65 ms) trade a little delay for silkier movement. Fine-tune in Advanced: Smoothing.",
        presetNames, sm.preset, smd.preset, onPreset)

    -- Sensitivity -----------------------------------------------------------------------------------
    local sens = TAB .. "/sensitivity"
    ns.addSubcategory(sens, "Sensitivity")
    ns.addRangeFloat(sens, "Look left / right", "Camera degrees per degree you turn your head.",
        0.5, 10, 0.1, "%.1fx", r.yaw.sensitivity, rd.yaw.sensitivity, set(r.yaw, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Look up / down", "Camera degrees per degree you tilt your head up or down.",
        0.5, 10, 0.1, "%.1fx", r.pitch.sensitivity, rd.pitch.sensitivity, set(r.pitch, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Tilt", "Camera degrees per degree you tilt your head sideways. Switch it on in Advanced: Tilt.",
        0.5, 10, 0.1, "%.1fx", r.roll.sensitivity, rd.roll.sensitivity, set(r.roll, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Lean left / right", "Camera movement per cm you lean sideways.",
        0, 4, 0.05, "%.2fx", p.x.sensitivity, pd.x.sensitivity, set(p.x, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Raise / lower", "Camera movement per cm you raise or lower your head.",
        0, 4, 0.05, "%.2fx", p.y.sensitivity, pd.y.sensitivity, set(p.y, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Lean forward / back", "Camera movement per cm you lean toward or away from the screen.",
        0, 4, 0.05, "%.2fx", p.z.sensitivity, pd.z.sensitivity, set(p.z, "sensitivity", "axes"))
    ns.addRangeFloat(sens, "Turn limit in vehicles", "The furthest the camera turns left or right in a vehicle.",
        5, 180, 1, "%.0f deg", r.yaw.limit, rd.yaw.limit, set(r.yaw, "limit", "axes"))
    ns.addRangeFloat(sens, "Turn limit on foot",
        "On foot you'd turn your body to look further round, so the head eases to a stop here.",
        30, 180, 1, "%.0f deg", s.onFootYawLimit, d.onFootYawLimit, set(s, "onFootYawLimit", "axes"))

    -- Pause -----------------------------------------------------------------------------------------
    local pausing = TAB .. "/pausing"
    ns.addSubcategory(pausing, "Pause")
    ns.addSwitch(pausing, "Pause while aiming",
        "Fade out while aiming down sights or shooting from a vehicle. Shots follow the camera, so this keeps your aim true.",
        s.pauseWhileAiming, d.pauseWhileAiming, set(s, "pauseWhileAiming", "general"))
    ns.addSelectorString(pausing, "Pause during scenes", "When story scenes take over the camera.",
        { "Cutscenes only", "Also when movement is limited" }, s.scenePause, d.scenePause,
        set(s, "scenePause", "general"))
    ns.addSelectorString(pausing, "When your head is lost", "What the camera does if the tracker can't see you.",
        { "Ease back to center", "Hold position" }, s.lostHeadBehavior, d.lostHeadBehavior,
        set(s, "lostHeadBehavior", "general"))
    ns.addRangeFloat(pausing, "Head lost delay",
        "How long the tracker can lose sight of your head before the camera reacts (eases back to center or holds where it is).",
        0, 3, 0.1, "%.1f s", s.lostHeadDelaySeconds, d.lostHeadDelaySeconds, set(s, "lostHeadDelaySeconds", "general"))
    ns.addRangeFloat(pausing, "Fade time", "Seconds to blend in and out when head tracking pauses or resumes.",
        0, 2, 0.05, "%.2f s", s.fadeSeconds, d.fadeSeconds, set(s, "fadeSeconds", "general"))

    -- Natural movement ------------------------------------------------------------------------------
    local natural = TAB .. "/natural"
    ns.addSubcategory(natural, "Natural movement")
    ns.addSelectorString(natural, "Keep head turns level with",
        "What turning your head rotates around. The car or horizon keeps the view level when it's tilted up or down; the camera tilts the turn with it.",
        { "The car", "The horizon", "The camera" }, s.turnAxis, d.turnAxis, set(s, "turnAxis", "general"))
    ns.addSelectorString(natural, "Leaning follows your view",
        "Lean forward while looking right and the camera moves right, toward what you're looking at. Off: leaning always moves toward the screen.",
        { "Off (toward the screen)", "When turning", "When turning and looking up/down" },
        s.leanFollowsView, d.leanFollowsView, set(s, "leanFollowsView", "general"))
    ns.addRangeFloat(natural, "Head-turn correction strength",
        "How much of the rise, dip and slide measured by Calibrate head turns to remove.",
        0, 1, 0.05, "%.2f", s.turnCorrection, d.turnCorrection, set(s, "turnCorrection", "general"))
    ns.addSwitch(natural, "Neck model",
        "When the camera turns, your eyes swing around a neck like a real head (to the side and back when turning, forward and down when looking down) instead of rotating on the spot.",
        n.enabled, nd.enabled, set(n, "enabled", "general"))
    ns.addRangeFloat(natural, "Eyes in front of neck", "How far forward of the neck pivot your eyes are. More = bigger swing when turning.",
        0, 20, 0.5, "%.1f cm", n.forwardCm, nd.forwardCm, set(n, "forwardCm", "general"))
    ns.addRangeFloat(natural, "Eyes above neck", "How far above the neck pivot your eyes are. More = bigger swing when looking up, down or tilting.",
        0, 20, 0.5, "%.1f cm", n.upCm, nd.upCm, set(n, "upCm", "general"))

    -- Looking far back ------------------------------------------------------------------------------
    local farBack = TAB .. "/far_back"
    ns.addSubcategory(farBack, "Looking far back")
    ns.addSwitch(farBack, "Twist when looking far back",
        "Past the neck's turning range, the spine twists the rest of the way and you reach forward, instead of the head turning further on its own. Needs the neck model.",
        n.twist, nd.twist, set(n, "twist", "general"))
    ns.addRangeFloat(farBack, "Neck turn limit", "How far the neck turns before the spine takes over (eased in over 30 degrees around it).",
        45, 150, 1, "%.0f deg", n.turnLimitDeg, nd.turnLimitDeg, set(n, "turnLimitDeg", "general"))
    ns.addRangeFloat(farBack, "Spine behind neck", "How far behind the neck pivot the spine twists. More = your head swings further to the side when twisting.",
        0, 15, 0.5, "%.1f cm", n.spineBehindCm, nd.spineBehindCm, set(n, "spineBehindCm", "general"))
    ns.addRangeFloat(farBack, "Reach forward when twisting",
        "How far you lean in per 45 degrees of twist: toward where your body now faces, or toward the dashboard in a car seat.",
        0, 25, 0.5, "%.1f cm", n.leanCm, nd.leanCm, set(n, "leanCm", "general"))

    -- In the car ------------------------------------------------------------------------------------
    local car = TAB .. "/car"
    ns.addSubcategory(car, "In the car")
    ns.addSwitch(car, "Disable car camera auto-centering",
        "Stop the vehicle camera swinging back to the front after mouse look. Takes effect next time you get in.",
        s.disableVehicleAutoCenter, d.disableVehicleAutoCenter, set(s, "disableVehicleAutoCenter", "autocenter"))
    ns.addSwitch(car, "Car seat holds your back",
        "When twisting to look back, your back stays against the seat: no moving back into it, and reaching forward goes toward the dashboard. Bikes and on foot twist freely.",
        n.seatInCars, nd.seatInCars, set(n, "seatInCars", "general"))
    ns.addSwitch(car, "Clear the headrest",
        "When you look far back from a car seat, also lean sideways to see past the headrest. Needs \"Car seat holds your back\" and \"Twist when looking far back\".",
        n.clearHeadrest, nd.clearHeadrest, set(n, "clearHeadrest", "general"))
    ns.addRangeFloat(car, "Headrest: door side", "How far to lean sideways past the headrest when looking back over your door-side shoulder.",
        0, 30, 0.5, "%.1f cm", n.headrestDoorCm, nd.headrestDoorCm, set(n, "headrestDoorCm", "general"))
    ns.addRangeFloat(car, "Headrest: middle side", "How far to lean sideways past the headrest when looking back toward the middle of the car. Usually more than on the door side, so you can see the whole rear window.",
        0, 40, 0.5, "%.1f cm", n.headrestMiddleCm, nd.headrestMiddleCm, set(n, "headrestMiddleCm", "general"))

    -- Advanced: per axis ----------------------------------------------------------------------------
    local JITTER_DESC = "Smooths out tracker jitter, but never lets the camera trail your head by more than this. Bigger = steadier, smaller = tighter. 0 = off."

    -- limitMax nil = the limit lives in Sensitivity instead.
    local function rotationAxis(key, title, limitMax)
        local path = TAB .. "/rot_" .. key
        local axis, def = r[key], rd[key]
        ns.addSubcategory(path, "Advanced: " .. title)
        ns.addSwitch(path, "Enabled", "", axis.enabled, def.enabled, set(axis, "enabled", "axes"))
        ns.addRangeFloat(path, "Curve", "1 = linear. Higher = calmer near center, faster toward the limit.",
            0.5, 3, 0.05, "%.2f", axis.curve, def.curve, set(axis, "curve", "axes"))
        if limitMax then
            ns.addRangeFloat(path, "Limit", "The furthest the camera will turn.",
                5, limitMax, 1, "%.0f deg", axis.limit, def.limit, set(axis, "limit", "axes"))
        end
        ns.addRangeFloat(path, "Jitter filter", JITTER_DESC,
            0, 2, 0.05, "%.2f deg", axis.jitter, def.jitter, set(axis, "jitter", "axes"))
        ns.addSwitch(path, "Invert", "", axis.invert, def.invert, set(axis, "invert", "axes"))
    end
    rotationAxis("yaw", "Look left / right", nil)
    rotationAxis("pitch", "Look up / down", 89)
    rotationAxis("roll", "Tilt", 60)

    local function positionAxis(key, title)
        local path = TAB .. "/pos_" .. key
        local axis, def = p[key], pd[key]
        ns.addSubcategory(path, "Advanced: " .. title)
        ns.addSwitch(path, "Enabled", "", axis.enabled, def.enabled, set(axis, "enabled", "axes"))
        ns.addRangeFloat(path, "Limit", "The furthest the camera will move.",
            0, 60, 0.5, "%.1f cm", axis.limit, def.limit, set(axis, "limit", "axes"))
        ns.addRangeFloat(path, "Jitter filter", JITTER_DESC,
            0, 1, 0.05, "%.2f cm", axis.jitter, def.jitter, set(axis, "jitter", "axes"))
        ns.addSwitch(path, "Invert", "", axis.invert, def.invert, set(axis, "invert", "axes"))
    end
    positionAxis("x", "Lean left / right")
    positionAxis("y", "Raise / lower")
    positionAxis("z", "Lean forward / back")

    -- Advanced: smoothing ---------------------------------------------------------------------------
    local smoothing = TAB .. "/smoothing"
    ns.addSubcategory(smoothing, "Advanced: Smoothing")
    cutoffOption = ns.addRangeFloat(smoothing, "Movement smoothing",
        "Lower = smoother movement, but the camera trails your head more. Set by the Smoothness choice; changing it makes that Custom. (Filter min cutoff, Hz)",
        0.05, 5, 0.05, "%.2f", sm.minCutoffHz, smd.minCutoffHz, onFilterSlider("minCutoffHz"))
    betaOption = ns.addRangeFloat(smoothing, "Responsiveness",
        "Higher = less trailing on quick head turns, but rougher movement. Set by the Smoothness choice; changing it makes that Custom. (Filter beta)",
        0, 1, 0.01, "%.2f", sm.beta, smd.beta, onFilterSlider("beta"))
    ns.addRangeFloat(smoothing, "Settle time",
        "How gently the camera settles onto where you're looking. Longer = steadier, shorter = settles faster. Each axis's jitter filter sets how far behind it may fall.",
        0, 2, 0.05, "%.2f s", sm.settleSeconds, smd.settleSeconds, set(sm, "settleSeconds", "general"))
    ns.addRangeFloat(smoothing, "Frame blending",
        "The tracker updates about 33 times a second; this blends between updates so the camera moves every frame. Needs at least 30 ms. 0 = off.",
        0, 100, 5, "%.0f ms", sm.interpolationMs, smd.interpolationMs, set(sm, "interpolationMs", "smoothing"))

    -- Native Settings resets each widget and calls its callback, so the saved center survives.
    ns.registerRestoreDefaultsCallback(TAB, false, function() end)

    return true
end

return Menu
