-- Head-turn correction. When you turn your head the tracker also reports some pitch, roll and
-- position change (your eyes swing around your neck, and your face looks different from the side),
-- so the view rises or dips and slides as you look around. Calibration records how much of each
-- comes with every yaw angle; that much is then taken off, so only deliberate movement comes through.

local Turns = {}

local FROM, TO, STEP = -60, 60, 2.5 -- yaw bins, degrees from center
local CHANNELS = { "pitch", "roll", "x", "y", "z" }
local MIN_SAMPLES = 3 -- per bin
local MIN_REACH = 10  -- degrees each way a calibration has to cover

Turns.LEAD_IN_SECONDS = 5 -- time to close the menu and settle
Turns.RECORD_SECONDS = 15

local BINS = math.floor((TO - FROM) / STEP + 0.5) + 1

local session = nil

-- One channel's table at this yaw; values past either end hold the end value.
local function lookup(values, from, step, yaw)
    local n = #values
    local pos = (yaw - from) / step + 1
    if pos <= 1 then
        return values[1]
    end
    if pos >= n then
        return values[n]
    end
    local i = math.floor(pos)
    return values[i] + (values[i + 1] - values[i]) * (pos - i)
end

function Turns.isCalibrated(s)
    local c = s.turnCalibration
    return type(c) == "table" and type(c.step) == "number" and type(c.pitch) == "table" and #c.pitch > 1
end

-- d: head movement from center (Curves.deltas). Returns it with the turn side effects taken off.
function Turns.correct(d, s)
    if s.turnCorrection <= 0 or not Turns.isCalibrated(s) then
        return d
    end
    local c = s.turnCalibration
    local out = { yaw = d.yaw }
    for _, k in ipairs(CHANNELS) do
        out[k] = d[k] - lookup(c[k], c.from, c.step, d.yaw) * s.turnCorrection
    end
    return out
end

-- Calibration ------------------------------------------------------------------------------------

function Turns.start()
    session = { elapsed = -Turns.LEAD_IN_SECONDS, sums = {}, counts = {}, minYaw = 0, maxYaw = 0 }
end

function Turns.cancel()
    session = nil
end

-- nil when not calibrating, else { leadIn = seconds to start | nil, left = seconds left, minYaw, maxYaw }.
function Turns.progress()
    if not session then
        return nil
    end
    if session.elapsed < 0 then
        return { leadIn = -session.elapsed, left = Turns.RECORD_SECONDS, minYaw = 0, maxYaw = 0 }
    end
    return { left = Turns.RECORD_SECONDS - session.elapsed, minYaw = session.minYaw, maxYaw = session.maxYaw }
end

-- Average each bin, fill holes between covered bins, hold the ends, smooth lightly, and zero it at
-- center so Recenter stays in charge of where straight ahead is.
local function build()
    local lo, hi
    for i = 1, BINS do
        if (session.counts[i] or 0) >= MIN_SAMPLES then
            lo = lo or i
            hi = i
        end
    end
    if not lo or FROM + (lo - 1) * STEP > -MIN_REACH or FROM + (hi - 1) * STEP < MIN_REACH then
        return nil, string.format("Calibration didn't reach far enough: turn your head at least %d degrees each way", MIN_REACH)
    end

    local result = { from = FROM, step = STEP, reach = { FROM + (lo - 1) * STEP, FROM + (hi - 1) * STEP } }
    for _, k in ipairs(CHANNELS) do
        local raw = {}
        local last = nil
        for i = lo, hi do
            local count = session.counts[i] or 0
            if count >= MIN_SAMPLES then
                raw[i] = session.sums[i][k] / count
                for j = (last or i) + 1, i - 1 do
                    raw[j] = raw[last] + (raw[i] - raw[last]) * (j - last) / (i - last)
                end
                last = i
            end
        end
        local values = {}
        for i = 1, BINS do
            local c = math.min(math.max(i, lo), hi)
            values[i] = (raw[math.max(c - 1, lo)] + 2 * raw[c] + raw[math.min(c + 1, hi)]) / 4
        end
        local zero = lookup(values, FROM, STEP, 0)
        for i = 1, BINS do
            values[i] = values[i] - zero
        end
        result[k] = values
    end
    return result, string.format("Head turns calibrated from %.0f to %.0f degrees", result.reach[1], result.reach[2])
end

-- Call every frame with the head movement from center (nil if the head isn't seen). Returns nil
-- while idle or recording; when recording ends, returns the new table (or nil) and a message.
function Turns.update(d, dt)
    if not session then
        return nil
    end
    session.elapsed = session.elapsed + dt
    if session.elapsed < 0 then
        return nil
    end
    if d then
        local bin = math.floor((d.yaw - FROM) / STEP + 0.5) + 1
        if bin >= 1 and bin <= BINS then
            local sum = session.sums[bin]
            if not sum then
                sum = { pitch = 0, roll = 0, x = 0, y = 0, z = 0 }
                session.sums[bin] = sum
            end
            for _, k in ipairs(CHANNELS) do
                sum[k] = sum[k] + d[k]
            end
            session.counts[bin] = (session.counts[bin] or 0) + 1
            session.minYaw = math.min(session.minYaw, d.yaw)
            session.maxYaw = math.max(session.maxYaw, d.yaw)
        end
    end
    if session.elapsed < Turns.RECORD_SECONDS then
        return nil
    end
    local result, message = build()
    session = nil
    return result, message
end

return Turns
