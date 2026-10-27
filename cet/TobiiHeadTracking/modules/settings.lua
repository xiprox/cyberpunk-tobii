-- Settings: defaults, load/save to settings.json next to init.lua.
-- Anything missing from the saved file falls back to the defaults below, so new options
-- can be added without breaking old files.

local Settings = {}

local FILE = "settings.json"

local function axis(sensitivity, jitter, curve, limit, enabled, invert)
    return {
        enabled = enabled,
        sensitivity = sensitivity, -- camera degrees per head degree (cm per cm for position)
        jitter = jitter,           -- most the jitter filter may trail your head (degrees / cm)
        curve = curve,             -- 1 = linear, >1 = gentler near center, quicker toward the limit
        limit = limit,             -- most the camera will turn/move (degrees / cm)
        invert = invert,
    }
end

Settings.defaults = {
    enabled = true,

    -- Where it's active
    inVehicles = true,
    onFoot = true,
    onFootYawLimit = 100,       -- degrees the head turns on foot; past that you'd turn your body
    pauseWhileAiming = true,    -- also while shooting from a vehicle; shots follow the camera
    scenePause = 1,             -- 1 = cutscenes only (scene tier 4+), 2 = also limited-control scenes (3+)
    disableVehicleAutoCenter = true,

    -- Behaviour
    fadeSeconds = 0.35,         -- blend in/out when it switches on or off
    lostHeadBehavior = 1,       -- 1 = ease back to center, 2 = hold where it was
    lostHeadDelaySeconds = 0.5, -- how long the head can be missing before that kicks in
    turnAxis = 1,               -- head turns stay level with: 1 = the car, 2 = the horizon, 3 = the camera (tilts with it)
    leanFollowsView = 2,        -- lean moves the camera: 1 = toward the screen, 2 = where you're turned, 3 = also up/down

    -- Jitter sizes cover a Tobii Eye Tracker 5's jitter at rest (about 0.4 deg / 0.1 cm peak to peak).
    rotation = {
        yaw = axis(4.0, 0.4, 1.3, 135, true, false),
        pitch = axis(3.0, 0.4, 1.3, 60, true, false),
        roll = axis(1.0, 0.5, 1.0, 25, false, false),
    },
    position = {
        x = axis(2.0, 0.2, 1.0, 30, true, false), -- left/right lean
        y = axis(2.0, 0.2, 1.0, 30, true, false), -- up/down
        z = axis(2.0, 0.2, 1.0, 30, true, false), -- forward/back
    },

    -- Head-turn correction: how much of the pitch/roll/position change that comes with turning your
    -- head gets removed (0-1), and the per-angle table measured by calibration (empty = not done).
    turnCorrection = 1.0,
    turnCalibration = {},

    -- Neck model: the camera's eyes swing around a neck pivot when it turns, like a real head, instead
    -- of rotating on the spot. Distances from the pivot to the eyes (the usual VR neck model).
    -- Past turnLimitDeg the spine twists the rest of the way (around an axis spineBehindCm behind the
    -- neck pivot) and the body leans in, leanCm per 45 degrees of twist. In a car seat (seatInCars) the
    -- back stays on the seat: no twisting back into it, and leaning in goes toward the dashboard.
    -- clearHeadrest then also leans sideways past the headrest when looking back: headrestDoorCm
    -- toward the door, headrestMiddleCm toward the middle of the car (more, for the rear window).
    neck = {
        enabled = true,
        forwardCm = 8.0,
        upCm = 7.5,
        twist = true,
        turnLimitDeg = 85,
        spineBehindCm = 4.0,
        leanCm = 8.0,
        seatInCars = true,
        clearHeadrest = true,
        headrestDoorCm = 8.0,
        headrestMiddleCm = 16.0,
    },

    -- Three layers. The plugin's One Euro filter keeps movement smooth (without it turns get rough:
    -- the raw tracker's irregularities pass straight through), then it blends between tracker
    -- samples, then each axis's jitter filter (jitter.lua) holds the camera steady when you're still.
    -- The smoothness presets (below) set the One Euro filter; moving its sliders makes it Custom.
    smoothing = {
        preset = 1,             -- index into Settings.SMOOTHNESS_PRESETS, or SMOOTHNESS_CUSTOM
        minCutoffHz = 0.4,      -- lower = smoother, more delay
        beta = 0.4,             -- higher = less delay on quick head turns, rougher movement
        interpolationMs = 35,   -- blend between tracker samples (it reports ~33x/s, so >= 30); 0 = off
        settleSeconds = 0.5,    -- jitter filter: how gently the camera settles onto your head
    },

    -- Head pose treated as "looking straight ahead"; set with the Recenter hotkey.
    -- Tobii axes: yaw/pitch/roll in degrees, x/y/z in mm from the tracker.
    center = { yaw = 0, pitch = 0, roll = 0, x = 0, y = 0, z = 650 },
    hasCenter = false,

    -- Folder override for tobii_stream_engine.dll; empty = Tobii Experience default.
    runtimePath = "",

    showOverlay = false,
}

-- One Euro settings by smoothness, with how far the camera trails your head on turns (measured on
-- recordings). Anything else is Custom.
Settings.SMOOTHNESS_PRESETS = {
    { name = "Responsive", minCutoffHz = 0.4, beta = 0.4 },   -- ~33 ms
    { name = "Smooth", minCutoffHz = 0.5, beta = 0.1 },       -- ~50 ms
    { name = "Very smooth", minCutoffHz = 1.0, beta = 0.05 }, -- ~65 ms
}
Settings.SMOOTHNESS_CUSTOM = #Settings.SMOOTHNESS_PRESETS + 1

-- The preset these smoothing values match, or SMOOTHNESS_CUSTOM. Slider values come back as 32-bit
-- floats, so compare loosely.
function Settings.smoothnessPreset(sm)
    for i, p in ipairs(Settings.SMOOTHNESS_PRESETS) do
        if math.abs(sm.minCutoffHz - p.minCutoffHz) < 1e-3 and math.abs(sm.beta - p.beta) < 1e-3 then
            return i
        end
    end
    return Settings.SMOOTHNESS_CUSTOM
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- Fill `target` with values from `source` where the types match the defaults. An empty table in the
-- defaults (like turnCalibration) takes the saved one whole.
local function merge(target, source)
    for k, v in pairs(source) do
        local current = target[k]
        if type(current) == "table" and next(current) == nil and type(v) == "table" then
            target[k] = v
        elseif type(current) == "table" and type(v) == "table" then
            merge(current, v)
        elseif current ~= nil and type(current) == type(v) then
            target[k] = v
        end
    end
end

function Settings.load()
    local values = deepCopy(Settings.defaults)
    local file = io.open(FILE, "r")
    if file then
        local text = file:read("*a")
        file:close()
        local ok, saved = pcall(json.decode, text)
        if ok and type(saved) == "table" then
            merge(values, saved)
        else
            print("[TobiiHeadTracking] settings.json is unreadable, using defaults")
        end
    end
    -- Older files have no preset, or values edited by hand: show whatever the values really are.
    values.smoothing.preset = Settings.smoothnessPreset(values.smoothing)
    Settings.values = values
    return values
end

function Settings.save()
    local ok, text = pcall(json.encode, Settings.values)
    if not ok then
        print("[TobiiHeadTracking] Could not encode settings: " .. tostring(text))
        return
    end
    local file = io.open(FILE, "w")
    if not file then
        print("[TobiiHeadTracking] Could not write settings.json")
        return
    end
    file:write(text)
    file:close()
end

-- Resets in place so tables held by the menu callbacks stay valid.
function Settings.resetToDefaults(keepCenter)
    local center, hasCenter = deepCopy(Settings.values.center), Settings.values.hasCenter
    merge(Settings.values, deepCopy(Settings.defaults))
    if keepCenter then
        merge(Settings.values.center, center)
        Settings.values.hasCenter = hasCenter
    end
end

return Settings
