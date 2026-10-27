-- Tobii Head Tracking: reads head pose from the TobiiHeadTracking RED4ext plugin and turns the
-- first-person camera with it.

local Settings = require("modules/settings")
local Curves = require("modules/curves")
local Turns = require("modules/turns")
local Jitter = require("modules/jitter")
local Camera = require("modules/camera")
local State = require("modules/state")
local AutoCenter = require("modules/autocenter")
local Menu = require("modules/menu")
local Overlay = require("modules/overlay")

-- After a load the game keeps rearranging the camera for a moment; wait before touching it.
local SETTLE_SECONDS = 1.5
local HORIZON = { i = 0, j = 0, k = 0, r = 1 }
local ON_FOOT_STOP_DEGREES = 10 -- the on-foot turn limit eases in over +-this

local mod = {
    settle = SETTLE_SECONDS,
    ready = false,
    native = false,
    hasMenu = false,
    overlayOpen = false,
    holdPaused = false,
    weight = 0,
    current = Curves.zero, -- offset before fading
    latestHead = nil,
    calibrationRecording = false,
    live = { weight = 0 },
}

local function log(message)
    print("[TobiiHeadTracking] " .. message)
end

-- Log, and show on the HUD when in game.
local function notify(message)
    log(message)
    pcall(function()
        Game.GetPlayer():SetWarningMessage(message)
    end)
end

local function applySmoothing()
    local sm = Settings.values.smoothing
    TobiiHeadTracking.SetSmoothing(sm.minCutoffHz, sm.beta, sm.interpolationMs)
end

local function recenter()
    if not mod.latestHead then
        log("Can't recenter: the tracker can't see your head")
        return
    end
    local s = Settings.values
    for key, value in pairs(mod.latestHead) do
        s.center[key] = value
    end
    s.hasCenter = true
    Settings.save()
    log("Recentered")
end

local function setEnabled(enabled)
    Settings.values.enabled = enabled
    Settings.dirty = true
    log(enabled and "Head tracking on" or "Head tracking off")
end

local function setRuntimePath(path)
    Settings.values.runtimePath = path
    Settings.save()
    if mod.native then
        TobiiHeadTracking.SetRuntimePath(path)
    end
end

local function applyAutoCenter()
    local ok, err = pcall(AutoCenter.apply, Settings.values.disableVehicleAutoCenter)
    if not ok then
        log("Couldn't change car camera auto-centering: " .. tostring(err))
    end
end

local function calibrateTurns()
    if not mod.native then
        log("Can't calibrate: the plugin isn't loaded")
        return
    end
    Turns.start()
    mod.calibrationRecording = false
    notify(string.format("Head-turn calibration starts in %d seconds: look at the screen center",
        Turns.LEAD_IN_SECONDS))
end

local function cancelCalibration()
    Turns.cancel()
    log("Head-turn calibration cancelled")
end

local function onSettingChanged(section)
    if section == "autocenter" then
        applyAutoCenter()
        log("Car camera auto-centering change applies next time you get into a vehicle")
    elseif section == "smoothing" and mod.native then
        applySmoothing()
    end
end

local actions = {
    recenter = recenter,
    setEnabled = setEnabled,
    setRuntimePath = setRuntimePath,
    calibrateTurns = calibrateTurns,
    cancelCalibration = cancelCalibration,
}

-- Hotkeys (bind them in the CET overlay under Bindings) ----------------------------------------
registerHotkey("toggle", "Toggle head tracking", function()
    setEnabled(not Settings.values.enabled)
end)
registerHotkey("recenter", "Recenter head tracking", recenter)
registerHotkey("calibrate_turns", "Calibrate head turns", calibrateTurns)
registerInput("hold_pause", "Hold to pause head tracking", function(down)
    mod.holdPaused = down
end)

-- Events -----------------------------------------------------------------------------------------
registerForEvent("onInit", function()
    Settings.load()
    applyAutoCenter()

    local ok, version = pcall(function()
        return TobiiHeadTracking.GetVersion()
    end)
    mod.native = ok and version ~= nil
    if not mod.native then
        log("The TobiiHeadTracking RED4ext plugin isn't loaded; check red4ext/logs. (" .. tostring(version) .. ")")
        mod.live.status = "Plugin not loaded (see red4ext/logs)"
    else
        mod.live.version = version
        applySmoothing()
        if Settings.values.runtimePath ~= "" then
            TobiiHeadTracking.SetRuntimePath(Settings.values.runtimePath)
        end
        log("Ready, plugin v" .. version)
    end

    local okMenu, hasMenu = pcall(Menu.build, Settings, onSettingChanged, actions)
    mod.hasMenu = okMenu and hasMenu
    if not okMenu then
        log("Couldn't build the settings menu: " .. tostring(hasMenu))
    end
    mod.ready = true
end)

local function readPlugin()
    return TobiiHeadTracking.GetRotation(), TobiiHeadTracking.GetPosition(), TobiiHeadTracking.GetStatus()
end

-- Orientation whose up head turns stay level with (see Settings turnAxis), or nil to turn around the
-- camera's own up. On foot "the car" means the horizon.
local function levelReference(vehicle, s)
    if s.turnAxis == 3 then
        return nil
    end
    if s.turnAxis == 1 and vehicle then
        return vehicle:GetWorldOrientation()
    end
    return HORIZON
end

-- Whether the player's back is against a seat: in a car, not on a bike or on foot.
local function isSeated(vehicle)
    return vehicle ~= nil and not vehicle:IsA("vehicleBikeBaseObject")
end

-- Which side of the car the player sits on: -1 left, 1 right, 0 middle.
local function seatSide(player, vehicle)
    local p, v, q = player:GetWorldPosition(), vehicle:GetWorldPosition(), vehicle:GetWorldOrientation()
    local right = { -- the car's right axis
        x = 1 - 2 * (q.j * q.j + q.k * q.k),
        y = 2 * (q.i * q.j + q.r * q.k),
        z = 2 * (q.i * q.k - q.r * q.j),
    }
    local side = (p.x - v.x) * right.x + (p.y - v.y) * right.y + (p.z - v.z) * right.z
    if math.abs(side) < 0.1 then
        return 0
    end
    return side < 0 and -1 or 1
end

local function moveToward(value, goal, step)
    if value < goal then
        return math.min(value + step, goal)
    end
    return math.max(value - step, goal)
end

registerForEvent("onUpdate", function(dt)
    if not mod.ready or not mod.native then
        return
    end
    local s = Settings.values

    local ok, rot, pos, status = pcall(readPlugin)
    if not ok then
        mod.native = false
        mod.live.status = "Plugin call failed: " .. tostring(rot)
        log(mod.live.status)
        Camera.release()
        return
    end
    local ageMs = rot.w
    local head = nil
    if ageMs >= 0 then
        head = { yaw = rot.y, pitch = rot.x, roll = rot.z, x = pos.x, y = pos.y, z = pos.z }
    end
    local lost = head == nil or ageMs > s.lostHeadDelaySeconds * 1000
    mod.latestHead = (head and ageMs < 400) and head or nil

    -- First run: treat wherever you're sitting as straight ahead until you recenter.
    if mod.latestHead and not s.hasCenter then
        recenter()
    end

    local player = Game.GetPlayer()
    if not player then
        mod.settle = SETTLE_SECONDS
        Camera.forget()
    elseif mod.settle > 0 then
        mod.settle = mod.settle - dt
    end

    local active, reason
    if not player then
        active, reason = false, "not in game"
    elseif mod.settle > 0 then
        active, reason = false, "loading"
    elseif not s.enabled then
        active, reason = false, "switched off"
    elseif mod.holdPaused then
        active, reason = false, "paused"
    else
        active, reason = State.evaluate(player, s)
    end

    local vehicle = nil
    if player then
        local okVehicle, mounted = pcall(Game.GetMountedVehicle, player)
        vehicle = okVehicle and mounted or nil
    end

    local delta = (head and not lost) and Curves.deltas(head, s.center) or nil

    local calibration, message = Turns.update(delta, dt)
    if message then
        mod.calibrationRecording = false
        if calibration then
            s.turnCalibration = calibration
            Settings.save()
        end
        notify(message)
    end
    local progress = Turns.progress()
    if progress and not progress.leadIn and not mod.calibrationRecording then
        mod.calibrationRecording = true
        notify(string.format("Now slowly turn your head fully left and right a few times (%d seconds)",
            Turns.RECORD_SECONDS))
    end

    if delta then
        local current = Curves.apply(Jitter.apply(Turns.correct(delta, s), s, dt), s)
        if not vehicle then
            -- On foot you'd turn your body to look further round, so the head eases to a stop.
            current.yaw = Curves.softClamp(current.yaw, s.onFootYawLimit, ON_FOOT_STOP_DEGREES)
        end
        mod.current = current
    else
        Jitter.reset()
        if s.lostHeadBehavior == 1 then
            local rate = math.min(dt / math.max(s.fadeSeconds, 0.05), 1)
            mod.current = Curves.lerp(mod.current, Curves.zero, rate)
        end
    end

    local goal = active and 1 or 0
    if s.fadeSeconds <= 0 then
        mod.weight = goal
    else
        mod.weight = moveToward(mod.weight, goal, dt / s.fadeSeconds)
    end

    if mod.weight > 0 then
        -- Smoothstep so the blend starts and ends gently.
        local w = mod.weight * mod.weight * (3 - 2 * mod.weight)
        local offset = Curves.scale(mod.current, w)
        local okRef, reference = pcall(levelReference, vehicle, s)
        if not okRef then
            reference = HORIZON
        end
        local neck = nil
        if s.neck.enabled then
            local n = s.neck
            neck = { eyes = { x = 0, y = n.forwardCm / 100, z = n.upCm / 100 } }
            if n.twist then
                local seated = false
                if n.seatInCars and vehicle then
                    local okSeat, isCar = pcall(isSeated, vehicle)
                    seated = not okSeat or isCar -- if the check fails, assume a car
                end
                neck.twist = {
                    limit = n.turnLimitDeg,
                    spineBehind = n.spineBehindCm / 100,
                    lean = n.leanCm / 100,
                    seated = seated,
                }
                if seated and n.clearHeadrest then
                    local okSide, side = pcall(seatSide, player, vehicle)
                    neck.twist.headrest = {
                        door = n.headrestDoorCm / 100,
                        middle = n.headrestMiddleCm / 100,
                        seatSide = okSide and side or 0,
                    }
                end
            end
        end
        Camera.apply(offset, dt, { level = reference, neck = neck, leanFollows = s.leanFollowsView })
        mod.live.offset = offset
    else
        Camera.release()
        mod.live.offset = Curves.zero
    end

    mod.live.status = status
    mod.live.head = head
    mod.live.active = active
    mod.live.reason = reason
    mod.live.weight = mod.weight
    mod.live.error = Camera.lastError
    mod.live.rewrites = Camera.lastWindow
    mod.live.axisTilt = Camera.axisTilt
    mod.live.calibration = progress
    mod.live.calibratedReach = Turns.isCalibrated(s) and s.turnCalibration.reach or nil
end)

registerForEvent("onOverlayOpen", function()
    mod.overlayOpen = true
end)

registerForEvent("onOverlayClose", function()
    mod.overlayOpen = false
    if Settings.dirty then
        Settings.save()
        Settings.dirty = false
    end
end)

registerForEvent("onDraw", function()
    if not mod.ready then
        return
    end
    if mod.overlayOpen or Settings.values.showOverlay then
        Overlay.draw(Settings, mod.live, actions, mod.hasMenu)
    end
end)

registerForEvent("onShutdown", function()
    Camera.release()
    if mod.ready and Settings.dirty then
        Settings.save()
    end
end)
