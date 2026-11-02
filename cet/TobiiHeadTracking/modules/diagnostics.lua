-- Keeps a record for bug reports in TobiiHeadTracking.log beside init.lua: what the mod's state was,
-- and each time something else wrote the camera, the first frames one by one. The file stays on the
-- player's machine until they choose to send it.

local Diagnostics = {}

local MAX_LINES = 2000 -- per game session
local ROWS_PER_RUN = 30 -- frames logged one by one when something starts writing the camera
local STILL_WRITING_FRAMES = 300 -- after those, log one frame in this many
local QUIET_FRAMES = 30 -- frames without a write that end a run of writes

local lines = 0
local run = nil -- { frames, quiet } while something is writing the camera
local tracked = {}

function Diagnostics.log(message)
    if lines > MAX_LINES then
        return
    end
    lines = lines + 1
    if lines > MAX_LINES then
        message = "Log limit reached: nothing more is logged until the game restarts"
    end
    pcall(function()
        spdlog.info(message)
    end)
end

-- Logs a value when it changes, so the log shows what else happened around a camera write.
function Diagnostics.track(name, value)
    if tracked[name] ~= value then
        tracked[name] = value
        Diagnostics.log(name .. ": " .. tostring(value))
    end
end

-- A frame on which something else wrote the camera. row: what it wrote.
function Diagnostics.rewrite(row)
    if not run then
        run = { frames = 0, quiet = 0 }
    end
    run.frames = run.frames + 1
    run.quiet = 0
    if run.frames <= ROWS_PER_RUN or run.frames % STILL_WRITING_FRAMES == 0 then
        Diagnostics.log("Camera write, frame " .. run.frames .. ": " .. row)
    end
end

-- A frame on which it didn't. describe: returns where that left things, for the end of a run.
function Diagnostics.noRewrite(describe)
    if not run then
        return
    end
    run.quiet = run.quiet + 1
    if run.quiet >= QUIET_FRAMES then
        Diagnostics.log("Camera writes stopped after " .. run.frames .. " frames: " .. describe())
        run = nil
    end
end

return Diagnostics
