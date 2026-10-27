-- Stops the first-person vehicle camera from swinging back to the front after mouse look, and from
-- snapping back vertically. Same TweakDB values as the "No Camera Auto Centering - FPP" mod.
-- The game reads them when a vehicle camera profile is applied, so changes take effect the next time
-- you get into a vehicle.

local AutoCenter = {}

local FLATS = {
    { "fppCameraParamSets.Vehicle.headingResetTimeout", 10000.0 },
    { "fppCameraParamSets.Bike.headingResetTimeout", 10000.0 },
    { "fppCameraParamSets.DriverCombat.headingResetTimeout", 10000.0 },
    { "fppCameraParamSets.Vehicle.pitchRubberBandLimit", 0.0 },
    { "fppCameraParamSets.Vehicle.yawRubberBandLimit", 0.0 },
    { "fppCameraParamSets.Bike.pitchRubberBandLimit", 0.0 },
    { "fppCameraParamSets.Bike.yawRubberBandLimit", 0.0 },
}

local original = {}

function AutoCenter.apply(disable)
    local failed = 0
    for _, flat in ipairs(FLATS) do
        local name, value = flat[1], flat[2]
        if original[name] == nil then
            original[name] = TweakDB:GetFlat(name) or false
        end
        if original[name] == false then
            failed = failed + 1
        else
            local target = disable and value or original[name]
            if not TweakDB:SetFlat(name, target) then
                failed = failed + 1
            end
        end
    end
    if failed > 0 then
        print(string.format("[TobiiHeadTracking] Auto-centering: %d of %d camera values couldn't be changed", failed, #FLATS))
    end
end

return AutoCenter
