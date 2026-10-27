-- Applies the head offset to the player's first-person camera component.
--
-- The component's local transform sits on top of the body/look direction, so offsetting it turns the
-- view without moving the mouse look. The game sometimes rewrites that transform itself (aiming,
-- weapon swaps, getting into a vehicle, scenes, possibly every frame). Each frame we compare what's
-- there with what we wrote last: if it changed, the game's value becomes the new resting pose;
-- if not, we keep the old resting pose so the offset never stacks on itself.
--
-- Head turns go around a level "up" (the car's, or the world's) rather than the camera's own, which
-- tilts whenever the view is pitched. That up is measured from where the camera points each frame.

local Curves = require("modules/curves")

local Camera = {}

local EPSILON = 1e-4
local STATS_WINDOW = 300 -- frames per diagnostics window
local AXIS_SMOOTHING_SECONDS = 0.08
local MIN_AXIS_UP = 0.2 -- ignore readings tilted more than ~78 degrees; they can't be right
local TWIST_BLEND_DEGREES = 15 -- neck hands over to the spine across +-this around its limit
local HEADREST_RAMP_DEGREES = 35 -- degrees of twist over which the headrest lean builds up

local IDENTITY = { i = 0, j = 0, k = 0, r = 1 }
local UP = { x = 0, y = 0, z = 1 }

local base = { pos = { x = 0, y = 0, z = 0 }, rot = { i = 0, j = 0, k = 0, r = 1 } }
local written = { pos = { x = 0, y = 0, z = 0 }, rot = { i = 0, j = 0, k = 0, r = 1 } }
local applied = false
local reported = {}

-- Offset rotation the camera is showing right now (and the one before it), and the axis head turns
-- go around, in the camera's own frame without our offset.
local inEffect = IDENTITY
local previousEffect = IDENTITY
local turnAxis = UP
Camera.axisTilt = 0 -- degrees between that axis and the camera's own up, for the overlay

-- Which way leaning moves the camera (Settings leanFollowsView).
Camera.LEAN_TOWARD_SCREEN = 1
Camera.LEAN_FOLLOWS_TURN = 2
Camera.LEAN_FOLLOWS_TURN_AND_PITCH = 3

-- How often the game replaced our camera transform; shown in the overlay to tune the approach.
local stats = { frames = 0, rotation = 0, position = 0 }
Camera.lastWindow = nil
Camera.lastError = nil
local windowsLogged = 0

local function report(where, err)
    local message = where .. ": " .. tostring(err)
    Camera.lastError = message
    if not reported[where] then
        reported[where] = true
        print("[TobiiHeadTracking] " .. message)
    end
end

local function axisAngle(x, y, z, degrees)
    local half = math.rad(degrees) * 0.5
    local s = math.sin(half)
    return { i = x * s, j = y * s, k = z * s, r = math.cos(half) }
end

local function mul(a, b)
    return {
        i = a.r * b.i + a.i * b.r + a.j * b.k - a.k * b.j,
        j = a.r * b.j - a.i * b.k + a.j * b.r + a.k * b.i,
        k = a.r * b.k + a.i * b.j - a.j * b.i + a.k * b.r,
        r = a.r * b.r - a.i * b.i - a.j * b.j - a.k * b.k,
    }
end

local function conjugate(q)
    return { i = -q.i, j = -q.j, k = -q.k, r = q.r }
end

-- Rotates vector v by quaternion q.
local function rotate(q, v)
    local tx = 2 * (q.j * v.z - q.k * v.y)
    local ty = 2 * (q.k * v.x - q.i * v.z)
    local tz = 2 * (q.i * v.y - q.j * v.x)
    return {
        x = v.x + q.r * tx + (q.j * tz - q.k * ty),
        y = v.y + q.r * ty + (q.k * tx - q.i * tz),
        z = v.z + q.r * tz + (q.i * ty - q.j * tx),
    }
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

-- Game axes: x right, y forward, z up. Yaw about the turn axis (positive = left), pitch about x
-- (positive = up), roll about y.
local function offsetRotation(o, axis)
    local yaw = axisAngle(axis.x, axis.y, axis.z, o.yaw)
    local pitch = axisAngle(1, 0, 0, o.pitch)
    local roll = axisAngle(0, 1, 0, o.roll)
    return mul(mul(yaw, pitch), roll)
end

local function scaled(v, s)
    return { x = v.x * s, y = v.y * s, z = v.z * s }
end

-- How far the eyes move when the head turns by o (yaw degrees of it around the turn axis).
-- neck = {
--   eyes = where the eyes sit relative to the neck pivot ({ x, y = forward, z = up }, metres),
--   twist = nil, or { limit = degrees the neck turns before the spine twists the rest,
--                     spineBehind = metres from the neck pivot back to the spine's twist axis,
--                     lean = metres the body leans in per 45 degrees of twist,
--                     seated = true when the back is against a seat (cars): the twist can't push
--                              back into it, and leaning in means leaning forward in the car,
--                     headrest = nil, or (seated only) { door, middle = metres to lean sideways
--                                past the headrest when looking back toward the door / the middle of
--                                the car, seatSide = -1 left seat, 1 right seat, 0 unknown } },
-- }
-- Worked out in the camera's resting frame, returned in the frame its local position is in.
local function neckShift(o, yaw, neck)
    local eyes = neck.eyes
    local moved = rotate(o, eyes)
    local shift = { x = moved.x - eyes.x, y = moved.y - eyes.y, z = moved.z - eyes.z }

    local twist = neck.twist
    local torso = twist and (yaw - Curves.softClamp(yaw, twist.limit, TWIST_BLEND_DEGREES)) or 0
    if torso ~= 0 then
        -- Past the neck's range the spine twists the rest of the way, carrying the neck pivot around
        -- the spine's axis, and the body leans in the direction the torso now faces.
        local u = turnAxis
        local forward = { x = -u.y * u.x, y = 1 - u.y * u.y, z = -u.y * u.z } -- level forward
        forward = scaled(forward, 1 / math.sqrt(dot(forward, forward)))
        local spin = axisAngle(u.x, u.y, u.z, torso)
        local spine = scaled(forward, -twist.spineBehind)
        local swung = rotate(spin, spine)
        local swing = { x = spine.x - swung.x, y = spine.y - swung.y, z = spine.z - swung.z }
        local lean = scaled(forward, twist.lean * math.abs(torso) / 45)
        if twist.seated then
            local back = dot(swing, forward)
            if back < 0 then
                swing = { x = swing.x - forward.x * back, y = swing.y - forward.y * back, z = swing.z - forward.z * back }
            end
            local headrest = twist.headrest
            if headrest then
                -- Lean sideways past the headrest, further toward the middle of the car where the
                -- rear window is. Eases in as the twist builds.
                local looking = torso > 0 and -1 or 1 -- camera x: -1 = looking back left
                local amount = headrest.door
                if headrest.seatSide ~= 0 and looking ~= headrest.seatSide then
                    amount = headrest.middle
                end
                local t = math.min(math.abs(torso) / HEADREST_RAMP_DEGREES, 1)
                local side = scaled(cross(forward, u), looking * amount * t * t * (3 - 2 * t))
                lean = { x = lean.x + side.x, y = lean.y + side.y, z = lean.z + side.z }
            end
        else
            lean = rotate(spin, lean)
        end
        shift.x = shift.x + swing.x + lean.x
        shift.y = shift.y + swing.y + lean.y
        shift.z = shift.z + swing.z + lean.z
    end
    return rotate(base.rot, shift)
end

-- Lean (offset.x/y/z, in the frame the camera's local position is in) turned to follow where the
-- head is looking: follows = Camera.LEAN_TOWARD_SCREEN, LEAN_FOLLOWS_TURN or LEAN_FOLLOWS_TURN_AND_PITCH.
-- The turn happens in the camera's resting frame, so convert into it and back.
local function leanShift(offset, follows)
    local lean = { x = offset.x, y = offset.y, z = offset.z }
    if follows == Camera.LEAN_TOWARD_SCREEN then
        return lean
    end
    local view = axisAngle(turnAxis.x, turnAxis.y, turnAxis.z, offset.yaw)
    if follows == Camera.LEAN_FOLLOWS_TURN_AND_PITCH then
        view = mul(view, axisAngle(1, 0, 0, offset.pitch))
    end
    return rotate(base.rot, rotate(view, rotate(conjugate(base.rot), lean)))
end

-- The reference's up as seen from the camera without our offset. The camera system reports the view
-- as last drawn, offset included, so that offset is taken back out.
local function measureAxis(reference)
    local cameraSystem = Game.GetCameraSystem()
    local right = cameraSystem:GetActiveCameraRight()
    local forward = cameraSystem:GetActiveCameraForward()
    local up = cross(right, forward)
    local levelUp = rotate(reference, UP)
    local seen = { x = dot(levelUp, right), y = dot(levelUp, forward), z = dot(levelUp, up) }
    return rotate(inEffect, seen)
end

-- reference: orientation whose up head turns stay level with, or nil to turn around the camera's own.
local function updateAxis(reference, dt)
    if not reference then
        turnAxis = UP
        Camera.axisTilt = 0
        return
    end
    local ok, measured = pcall(measureAxis, reference)
    if not ok then
        report("Reading the camera direction", measured)
        return
    end
    local length = math.sqrt(dot(measured, measured))
    if length < 0.5 or measured.z / length < MIN_AXIS_UP then
        return
    end
    -- If the game reports the camera a frame late, the reading is off by however far the head moved
    -- in that frame, so trust it less while the head moves fast. The view's own tilt changes slowly.
    local t = 1
    if applied then
        local moved = math.deg(2 * math.acos(math.min(math.abs(
            inEffect.i * previousEffect.i + inEffect.j * previousEffect.j
            + inEffect.k * previousEffect.k + inEffect.r * previousEffect.r), 1)))
        t = (1 - math.exp(-dt / AXIS_SMOOTHING_SECONDS)) / (1 + moved)
    end
    local blended = {
        x = turnAxis.x + (measured.x / length - turnAxis.x) * t,
        y = turnAxis.y + (measured.y / length - turnAxis.y) * t,
        z = turnAxis.z + (measured.z / length - turnAxis.z) * t,
    }
    length = math.sqrt(dot(blended, blended))
    turnAxis = { x = blended.x / length, y = blended.y / length, z = blended.z / length }
    Camera.axisTilt = math.deg(math.acos(math.min(turnAxis.z, 1)))
end

local function sameRotation(q, w)
    local same = math.abs(q.i - w.i) < EPSILON and math.abs(q.j - w.j) < EPSILON
        and math.abs(q.k - w.k) < EPSILON and math.abs(q.r - w.r) < EPSILON
    if same then
        return true
    end
    -- q and -q are the same rotation.
    return math.abs(q.i + w.i) < EPSILON and math.abs(q.j + w.j) < EPSILON
        and math.abs(q.k + w.k) < EPSILON and math.abs(q.r + w.r) < EPSILON
end

-- Positions are stored in fixed point by the engine, so allow for rounding.
local function samePosition(p, w)
    return math.abs(p.x - w.x) < EPSILON and math.abs(p.y - w.y) < EPSILON and math.abs(p.z - w.z) < EPSILON
end

local function countFrame(rotationRewritten, positionRewritten)
    stats.frames = stats.frames + 1
    if rotationRewritten then
        stats.rotation = stats.rotation + 1
    end
    if positionRewritten then
        stats.position = stats.position + 1
    end
    if stats.frames >= STATS_WINDOW then
        Camera.lastWindow = { frames = stats.frames, rotation = stats.rotation, position = stats.position }
        if windowsLogged < 5 then
            windowsLogged = windowsLogged + 1
            print(string.format("[TobiiHeadTracking] Game rewrote camera rotation in %d/%d frames, position in %d/%d",
                stats.rotation, stats.frames, stats.position, stats.frames))
        end
        stats.frames, stats.rotation, stats.position = 0, 0, 0
    end
end

local function getCamera()
    local player = Game.GetPlayer()
    if not player then
        return nil
    end
    return player:GetFPPCameraComponent()
end

-- offset: { yaw, pitch, roll (degrees), x, y, z (metres) } in game axes. opts: see Camera.apply.
local function applyImpl(offset, dt, opts)
    local cam = getCamera()
    if not cam then
        return
    end

    updateAxis(opts.level, dt)

    local q = cam:GetLocalOrientation()
    local p = cam:GetLocalPosition()

    local rotationRewritten = not applied or not sameRotation(q, written.rot)
    local positionRewritten = not applied or not samePosition(p, written.pos)
    if applied then
        countFrame(rotationRewritten, positionRewritten)
    end
    if rotationRewritten then
        base.rot = { i = q.i, j = q.j, k = q.k, r = q.r }
    end
    if positionRewritten then
        base.pos = { x = p.x, y = p.y, z = p.z }
    end

    local o = offsetRotation(offset, turnAxis)
    local r = mul(base.rot, o)
    local lean = leanShift(offset, opts.leanFollows)
    local pos = { x = base.pos.x + lean.x, y = base.pos.y + lean.y, z = base.pos.z + lean.z }
    if opts.neck then
        local shift = neckShift(o, offset.yaw, opts.neck)
        pos.x, pos.y, pos.z = pos.x + shift.x, pos.y + shift.y, pos.z + shift.z
    end
    cam:SetLocalOrientation(Quaternion.new(r.i, r.j, r.k, r.r))
    cam:SetLocalPosition(Vector4.new(pos.x, pos.y, pos.z, 1))
    written.rot, written.pos = r, pos
    previousEffect, inEffect = inEffect, o
    applied = true
end

local function clearEffect()
    inEffect, previousEffect = IDENTITY, IDENTITY
end

-- opts: { level = reference for updateAxis, neck = see neckShift (nil = turn on the spot),
-- leanFollows = see leanShift }.
function Camera.apply(offset, dt, opts)
    local ok, err = pcall(applyImpl, offset, dt, opts)
    if not ok then
        applied = false
        clearEffect()
        report("Moving the camera", err)
    end
end

-- Put the resting pose back, unless the game has already replaced our value with its own.
local function releaseImpl()
    local cam = getCamera()
    if not cam then
        return
    end
    if sameRotation(cam:GetLocalOrientation(), written.rot) then
        cam:SetLocalOrientation(Quaternion.new(base.rot.i, base.rot.j, base.rot.k, base.rot.r))
    end
    if samePosition(cam:GetLocalPosition(), written.pos) then
        cam:SetLocalPosition(Vector4.new(base.pos.x, base.pos.y, base.pos.z, 1))
    end
end

function Camera.release()
    if not applied then
        return
    end
    applied = false
    clearEffect()
    local ok, err = pcall(releaseImpl)
    if not ok then
        report("Restoring the camera", err)
    end
end

-- After a load the old camera is gone; start over without writing anything back.
function Camera.forget()
    applied = false
    clearEffect()
end

return Camera
