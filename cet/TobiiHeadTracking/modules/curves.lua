-- Turns a head pose into a camera offset using the per-axis settings.
--
-- Tobii axes (input): +x right, +y up, +z toward the user. Degrees and mm (cm once turned into
-- deltas). Rotation signs follow cyber-headtrack, a working Tobii ET5 mod: game yaw = +yaw,
-- pitch = +pitch, roll = -roll. x is not mirrored (that mod and opentrack negate it, but recordings
-- show turning your head left, which moves your eyes left, reads as -x), so side = +x.
-- Game axes (output): +x right, +y forward, +z up. Positive yaw = turn left, positive pitch = look up.
-- Degrees and metres.

local Curves = {}

-- delta is head movement away from center; axis is one entry of settings.rotation / settings.position.
-- Sensitivity sets how far you have to move to reach the limit; curve shapes the way there.
function Curves.shape(delta, axis)
    if not axis.enabled then
        return 0
    end
    local magnitude = math.abs(delta)
    if magnitude <= 0 then
        return 0
    end
    local limit = math.max(axis.limit, 0.001)
    local t = math.min(magnitude * axis.sensitivity / limit, 1)
    local out = (t ^ math.max(axis.curve, 0.1)) * limit
    if delta < 0 then
        out = -out
    end
    if axis.invert then
        out = -out
    end
    return out
end

local shape = Curves.shape

-- Head movement away from center: degrees, and cm for position. head and center are
-- { yaw, pitch, roll, x, y, z } in Tobii axes (mm for position).
function Curves.deltas(head, center)
    return {
        yaw = head.yaw - center.yaw,
        pitch = head.pitch - center.pitch,
        roll = head.roll - center.roll,
        x = (head.x - center.x) / 10,
        y = (head.y - center.y) / 10,
        z = (head.z - center.z) / 10,
    }
end

-- d: head movement from Curves.deltas, after correction and filtering. Returns the camera offset.
function Curves.apply(d, settings)
    local r, p = settings.rotation, settings.position
    return {
        yaw = shape(d.yaw, r.yaw),
        pitch = shape(d.pitch, r.pitch),
        roll = -shape(d.roll, r.roll),
        x = shape(d.x, p.x) / 100,
        y = -shape(d.z, p.z) / 100,
        z = shape(d.y, p.y) / 100,
    }
end

-- Smoothly limits v to +-limit: unchanged up to limit - blend, then easing off to exactly limit at
-- limit + blend (no kink at either end).
function Curves.softClamp(v, limit, blend)
    blend = math.min(blend, limit)
    local a, lo = math.abs(v), limit - blend
    if a <= lo then
        return v
    end
    local out = limit
    if a < limit + blend then
        out = a - (a - lo) * (a - lo) / (4 * blend)
    end
    return v < 0 and -out or out
end

Curves.zero = { yaw = 0, pitch = 0, roll = 0, x = 0, y = 0, z = 0 }

function Curves.lerp(a, b, t)
    local out = {}
    for k, v in pairs(a) do
        out[k] = v + (b[k] - v) * t
    end
    return out
end

function Curves.scale(offset, weight)
    return Curves.lerp(Curves.zero, offset, weight)
end

return Curves
