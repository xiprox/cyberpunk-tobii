-- Decides whether head tracking should drive the camera right now, from the player state machine
-- blackboard. Field IDs are looked up once; a field the game doesn't have is skipped.

local State = {}

-- gamePSMVehicle
local VEHICLE_NONE = 0
local VEHICLE_COMBAT = 2
local VEHICLE_TRANSITION = 4
local VEHICLE_TURRET = 5
local VEHICLE_DRIVER_COMBAT = 6
-- gamePSMUpperBodyStates.Aim
local UPPER_BODY_AIM = 6
-- gamePSMVitals.Dead
local VITALS_DEAD = 1

local ids = nil
local reported = {}

local function report(where, err)
    if not reported[where] then
        reported[where] = true
        print("[TobiiHeadTracking] State check '" .. where .. "' unavailable: " .. tostring(err))
    end
end

local function field(def, name)
    local ok, value = pcall(function()
        return def[name]
    end)
    if ok and value then
        return value
    end
    report(name, value or "missing")
    return nil
end

local function cacheIds()
    local defs = Game.GetAllBlackboardDefs()
    local psm = defs.PlayerStateMachine
    ids = {
        psm = psm,
        vitals = field(psm, "Vitals"),
        sceneTier = field(psm, "SceneTier"),
        vehicle = field(psm, "Vehicle"),
        upperBody = field(psm, "UpperBody"),
        vehicleTpp = field(psm, "IsVehicleInTPP"),
        driverCombatTpp = field(psm, "IsDriverCombatInTPP"),
        braindance = defs.Braindance,
        braindanceActive = field(defs.Braindance, "IsActive"),
    }
end

local function getInt(bb, id, default)
    if not id then
        return default
    end
    local ok, value = pcall(bb.GetInt, bb, id)
    if ok and value then
        return value
    end
    return default
end

local function getBool(bb, id)
    if not id then
        return false
    end
    local ok, value = pcall(bb.GetBool, bb, id)
    return ok and value == true
end

local function check(player, s)
    if not ids then
        cacheIds()
    end
    local system = Game.GetBlackboardSystem()
    local bb = system:GetLocalInstanced(player:GetEntityID(), ids.psm)
    if not bb then
        return false, "loading"
    end

    if getInt(bb, ids.vitals, 0) == VITALS_DEAD then
        return false, "dead"
    end
    -- Scene tiers: 1 gameplay, 2 staged, 3 limited, 4 first-person cinematic, 5 cinematic.
    if getInt(bb, ids.sceneTier, 1) >= (s.scenePause == 2 and 3 or 4) then
        return false, "scene"
    end
    if Game.GetPhotoModeSystem():IsPhotoModeActive() then
        return false, "photo mode"
    end
    if ids.braindanceActive then
        local bd = system:Get(ids.braindance)
        if bd and getBool(bd, ids.braindanceActive) then
            return false, "braindance"
        end
    end

    local vehicle = getInt(bb, ids.vehicle, VEHICLE_NONE)
    if vehicle ~= VEHICLE_NONE then
        if not s.inVehicles then
            return false, "off in vehicles"
        end
        if getBool(bb, ids.vehicleTpp) or getBool(bb, ids.driverCombatTpp) then
            return false, "third-person camera"
        end
        if vehicle == VEHICLE_TRANSITION then
            return false, "getting in/out"
        end
        if vehicle == VEHICLE_TURRET then
            return false, "turret"
        end
        -- Shots follow the camera, so keep the aim true while shooting from a vehicle.
        if s.pauseWhileAiming and (vehicle == VEHICLE_COMBAT or vehicle == VEHICLE_DRIVER_COMBAT) then
            return false, "shooting"
        end
        return true, nil
    end

    if not s.onFoot then
        return false, "not in a vehicle"
    end
    if s.pauseWhileAiming and getInt(bb, ids.upperBody, 0) == UPPER_BODY_AIM then
        return false, "aiming"
    end
    return true, nil
end

-- Returns active (bool) and a short reason when inactive.
function State.evaluate(player, s)
    local ok, active, reason = pcall(check, player, s)
    if not ok then
        report("player state", active)
        return false, "state check failed (see CET console)"
    end
    return active, reason
end

return State
