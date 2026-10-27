-- Jitter filter: heavy smoothing that is never allowed to fall far behind your head.
--
-- Each axis eases toward your head over the settle time, which irons out tracker jitter, but it may
-- never trail your head by more than the axis's jitter size: past that it's carried along at exactly
-- your head's speed. So it never jumps or overshoots (a threshold that holds and then catches up
-- does), and real movement comes through with very little delay.

local Jitter = {}

local ROTATION = { "yaw", "pitch", "roll" }
local POSITION = { "x", "y", "z" }

local channels = {}

local function filter(key, value, size, settleSeconds, dt)
    local out = channels[key]
    if out == nil or size <= 0 then
        channels[key] = value
        return value
    end
    if value - out > size then
        out = value - size
    elseif out - value > size then
        out = value + size
    end
    if settleSeconds > 0 then
        out = out + (value - out) * (1 - math.exp(-dt / settleSeconds))
    end
    channels[key] = out
    return out
end

-- d: head movement from center (Curves.deltas). Returns the filtered values.
function Jitter.apply(d, s, dt)
    local settle = s.smoothing.settleSeconds
    local out = {}
    for _, k in ipairs(ROTATION) do
        out[k] = filter(k, d[k], s.rotation[k].jitter, settle, dt)
    end
    for _, k in ipairs(POSITION) do
        out[k] = filter(k, d[k], s.position[k].jitter, settle, dt)
    end
    return out
end

-- Start fresh, e.g. after the head was lost.
function Jitter.reset()
    channels = {}
end

return Jitter
