-- CET overlay window: the tracker's status and the controls a player needs without the game menu,
-- with the live numbers for chasing a bug under a Diagnostics section that starts closed.

local Overlay = {}

local pathBuffer = nil

local function row(label, a, b, c, fmt)
    ImGui.Text(string.format("%-10s " .. fmt .. "  " .. fmt .. "  " .. fmt, label, a, b, c))
end

-- live: { status, version, active, reason, weight, head, offset, axisTilt, ... } from init.lua
function Overlay.draw(Settings, live, actions, hasMenu)
    local s = Settings.values

    if not ImGui.Begin("Tobii Head Tracking", ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.End()
        return
    end

    ImGui.Text("Tracker: " .. (live.status or "?"))
    if live.version then
        ImGui.SameLine()
        ImGui.TextDisabled("v" .. live.version)
    end
    if live.active then
        ImGui.Text(string.format("Camera: active (%.0f%%)", live.weight * 100))
    else
        ImGui.Text("Camera: off - " .. (live.reason or ""))
    end
    if live.error then
        ImGui.TextColored(1, 0.4, 0.4, 1, live.error)
    end

    ImGui.Separator()

    local enabled, changed = ImGui.Checkbox("Head tracking", s.enabled)
    if changed then
        actions.setEnabled(enabled)
    end
    ImGui.SameLine()
    if ImGui.Button("Recenter") then
        actions.recenter()
    end

    local cal = live.calibration
    if cal then
        if cal.leadIn then
            ImGui.TextColored(1, 0.85, 0.3, 1,
                string.format("Head-turn calibration starts in %.0f s: look at the screen center", math.ceil(cal.leadIn)))
        else
            ImGui.TextColored(1, 0.85, 0.3, 1,
                string.format("Slowly turn your head fully left and right: %.0f s left (reached %.0f to %.0f deg)",
                    math.ceil(cal.left), cal.minYaw, cal.maxYaw))
        end
        if ImGui.Button("Cancel calibration") then
            actions.cancelCalibration()
        end
    else
        if ImGui.Button("Calibrate head turns") then
            actions.calibrateTurns()
        end
        ImGui.SameLine()
        if live.calibratedReach then
            ImGui.TextDisabled(string.format("Calibrated %.0f to %.0f deg, correction %.0f%%",
                live.calibratedReach[1], live.calibratedReach[2], s.turnCorrection * 100))
        else
            ImGui.TextDisabled("Not calibrated: the view may rise or dip as you turn")
        end
    end

    ImGui.Separator()

    if pathBuffer == nil then
        pathBuffer = s.runtimePath
    end
    ImGui.Text("Tobii runtime folder or DLL (blank = default):")
    ImGui.PushItemWidth(360)
    pathBuffer = ImGui.InputText("##runtimePath", pathBuffer, 512)
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("Apply") then
        actions.setRuntimePath(pathBuffer)
    end

    local showAlways
    showAlways, changed = ImGui.Checkbox("Keep this window open with CET closed", s.showOverlay)
    if changed then
        s.showOverlay = showAlways
        Settings.save()
    end

    if hasMenu then
        ImGui.TextDisabled("All other options: Settings > Mods > Head Tracking")
    else
        ImGui.TextDisabled("Install Native Settings for the in-game options, or edit settings.json.")
    end
    ImGui.TextDisabled("Hotkeys: CET > Bindings")

    if ImGui.CollapsingHeader("Diagnostics") then
        if live.head then
            local h, c = live.head, s.center
            ImGui.Text("                yaw     pitch    roll")
            row("Head", h.yaw, h.pitch, h.roll, "%7.2f")
            row("Center", c.yaw, c.pitch, c.roll, "%7.2f")
            ImGui.Text("                  x        y        z  (mm)")
            row("Head", h.x, h.y, h.z, "%7.1f")
            row("Center", c.x, c.y, c.z, "%7.1f")
        end
        if live.offset then
            local o = live.offset
            ImGui.Text("Camera offset")
            row("Turn", o.yaw, o.pitch, o.roll, "%7.2f")
            row("Move cm", o.x * 100, o.y * 100, o.z * 100, "%7.1f")
        end
        if live.active and s.turnAxis ~= 3 then
            ImGui.Text(string.format("View tilt kept out of head turns: %.1f deg", live.axisTilt or 0))
        end
        if live.rewrites then
            local r = live.rewrites
            ImGui.Text(string.format("Game rewrote camera: rotation %d/%d frames, position %d/%d",
                r.rotation, r.frames, r.position, r.frames))
        end
    end

    ImGui.End()
end

return Overlay
