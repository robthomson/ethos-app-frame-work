--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

local MSP_ATTITUDE = 108
local BASE_VIEW_PITCH_R = math.rad(-90)
local BASE_VIEW_YAW_R = math.rad(90)
local CAMERA_DIST = 7.0
local CAMERA_NEAR_EPS = 0.25

local MAG_ALIGN_CHOICES = {
    {"@i18n(app.modules.alignment.mag_default)@", 0},
    {"@i18n(app.modules.alignment.mag_cw_0)@", 1},
    {"@i18n(app.modules.alignment.mag_cw_90)@", 2},
    {"@i18n(app.modules.alignment.mag_cw_180)@", 3},
    {"@i18n(app.modules.alignment.mag_cw_270)@", 4},
    {"@i18n(app.modules.alignment.mag_cw_0_flip)@", 5},
    {"@i18n(app.modules.alignment.mag_cw_90_flip)@", 6},
    {"@i18n(app.modules.alignment.mag_cw_180_flip)@", 7},
    {"@i18n(app.modules.alignment.mag_cw_270_flip)@", 8},
    {"@i18n(app.modules.alignment.mag_custom)@", 9}
}

local BasePage = MspPage.create({
    title = "@i18n(app.modules.alignment.name)@",
    eepromWrite = true,
    reboot = true,
    help = {
        "@i18n(app.modules.alignment.help_p1)@",
        "@i18n(app.modules.alignment.help_p2)@",
        "@i18n(app.modules.alignment.help_p3)@"
    },
    navButtons = {
        tool = true
    },
    api = {
        {name = "BOARD_ALIGNMENT_CONFIG", rebuildOnWrite = true},
        {name = "SENSOR_ALIGNMENT", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.alignment.roll)@", apikey = "roll_degrees"},
            {t = "@i18n(app.modules.alignment.pitch)@", apikey = "pitch_degrees"},
            {t = "@i18n(app.modules.alignment.yaw)@", apikey = "yaw_degrees"},
            {
                t = "@i18n(app.modules.alignment.mag)@",
                api = "SENSOR_ALIGNMENT",
                apikey = "mag_alignment",
                type = 1,
                values = MAG_ALIGN_CHOICES
            }
        }
    }
})

local baseOpen = BasePage.open

local function measureTextWidth(text)
    local value = tostring(text or "")

    if lcd and lcd.font and FONT_STD then
        lcd.font(FONT_STD)
    end

    if lcd and lcd.getTextSize then
        return select(1, lcd.getTextSize(value)) or 0
    end

    return #value * 8
end

local function findField(node, apikey)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.apikey == apikey then
            return field
        end
    end

    return nil
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function openDialog(spec)
    if not (form and form.openDialog) then
        return false
    end

    form.openDialog(spec)
    return true
end

local function openConfirmDialog(title, message, onConfirm)
    return openDialog({
        width = nil,
        title = title,
        message = message,
        buttons = {
            {
                label = "@i18n(app.btn_ok_long)@",
                action = function()
                    if type(onConfirm) == "function" then
                        onConfirm()
                    end
                    return true
                end
            },
            {
                label = "@i18n(app.btn_cancel)@",
                action = function()
                    return true
                end
            }
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
end

local function applyControlHelp(control, field)
    if control and control.help and field and field.help then
        pcall(control.help, control, field.help)
    end
end

local function buildNumberControl(line, pos, field)
    local minValue = tonumber(field.min) or -180
    local maxValue = tonumber(field.max) or 360
    local control = form.addNumberField(line, pos, minValue, maxValue,
        function()
            return field.value
        end,
        function(newValue)
            field.value = tonumber(newValue) or 0
        end)

    if control and control.suffix and (field.unit or field.suffix) then
        pcall(control.suffix, control, field.unit or field.suffix)
    end

    applyControlHelp(control, field)
    field.control = control
    return control
end

local function buildChoiceControl(line, pos, field)
    local control = form.addChoiceField(line, pos, field.values or {},
        function()
            return field.value
        end,
        function(newValue)
            field.value = tonumber(newValue) or 0
        end)

    applyControlHelp(control, field)
    field.control = control
    return control
end

local function buildCompactForm(node, app)
    local rollField = findField(node, "roll_degrees")
    local pitchField = findField(node, "pitch_degrees")
    local yawField = findField(node, "yaw_degrees")
    local magField = findField(node, "mag_alignment")
    local line
    local rowY
    local rowH
    local screenW
    local leftPad
    local rightPad
    local gap
    local fieldX
    local fieldW
    local slotW
    local labels
    local labelWidths
    local slotX
    local boxWidth
    local magWidth

    if not (rollField and pitchField and yawField and magField) then
        return false
    end

    line = form.addLine("")
    rowY = app.radio.linePaddingTop or 0
    rowH = app.radio.navbuttonHeight or 30
    screenW = app:_windowSize()
    leftPad = 2
    rightPad = 6
    gap = 4
    fieldX = leftPad
    fieldW = screenW - leftPad - rightPad
    slotW = math.floor((fieldW - (gap * 3)) / 4)

    labels = {
        tostring(rollField.t or ""),
        tostring(pitchField.t or ""),
        tostring(yawField.t or ""),
        tostring(magField.t or "")
    }
    labelWidths = {
        measureTextWidth(labels[1] .. " "),
        measureTextWidth(labels[2] .. " "),
        measureTextWidth(labels[3] .. " "),
        measureTextWidth(labels[4] .. " ")
    }

    slotX = {
        fieldX,
        fieldX + slotW + gap,
        fieldX + ((slotW + gap) * 2),
        fieldX + ((slotW + gap) * 3)
    }

    boxWidth = {
        math.max(46, slotW - labelWidths[1] - 2),
        math.max(46, slotW - labelWidths[2] - 2),
        math.max(46, slotW - labelWidths[3] - 2)
    }
    magWidth = math.max(72, slotW - labelWidths[4] - 2)

    form.addStaticText(line, {x = slotX[1], y = rowY, w = labelWidths[1], h = rowH}, labels[1])
    buildNumberControl(line, {x = slotX[1] + labelWidths[1] + 2, y = rowY, w = boxWidth[1], h = rowH}, rollField)

    form.addStaticText(line, {x = slotX[2], y = rowY, w = labelWidths[2], h = rowH}, labels[2])
    buildNumberControl(line, {x = slotX[2] + labelWidths[2] + 2, y = rowY, w = boxWidth[2], h = rowH}, pitchField)

    form.addStaticText(line, {x = slotX[3], y = rowY, w = labelWidths[3], h = rowH}, labels[3])
    buildNumberControl(line, {x = slotX[3] + labelWidths[3] + 2, y = rowY, w = boxWidth[3], h = rowH}, yawField)

    form.addStaticText(line, {x = slotX[4], y = rowY, w = labelWidths[4], h = rowH}, labels[4])
    buildChoiceControl(line, {x = slotX[4] + labelWidths[4] + 2, y = rowY, w = magWidth, h = rowH}, magField)

    if node.state.resetDirtyAfterBuild == true and node.app and node.app.setPageDirty then
        node.state.resetDirtyAfterBuild = false
        node.app:setPageDirty(false)
    end

    return true
end

local function writeS16(buf, value)
    local n = math.floor(tonumber(value) or 0)

    if n < -32768 then
        n = -32768
    elseif n > 32767 then
        n = 32767
    end

    if n < 0 then
        n = n + 65536
    end

    buf[#buf + 1] = n % 256
    buf[#buf + 1] = math.floor(n / 256)
end

local function readS16(buf, index)
    local lo = tonumber(buf[index] or 0) or 0
    local hi = tonumber(buf[index + 1] or 0) or 0
    local value = lo + (hi * 256)

    if value > 32767 then
        value = value - 65536
    end

    return value
end

local function currentOffsets(node)
    local rollField = findField(node, "roll_degrees")
    local pitchField = findField(node, "pitch_degrees")
    local yawField = findField(node, "yaw_degrees")

    return {
        roll = tonumber(rollField and rollField.value) or 0,
        pitch = tonumber(pitchField and pitchField.value) or 0,
        yaw = tonumber(yawField and yawField.value) or 0
    }
end

local function recenterYawView(node)
    local view = node.state.alignmentView
    local offsets = currentOffsets(node)

    view.viewYawOffset = (tonumber(view.live.yaw) or 0) + offsets.yaw
    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
end

local function buildSimulatedAttitudeResponse(view, now)
    local t0 = view.simStartAt or 0
    local t = math.max(0, (now or os.clock()) - t0)
    local rollDeg = 25.0 * math.sin(t * 1.25)
    local pitchDeg = 18.0 * math.sin((t * 0.90) + 0.9)
    local yawDeg = 90.0 * math.sin((t * 0.42) + 0.2)
    local buf = {}

    writeS16(buf, math.floor((rollDeg * 10.0) + 0.5))
    writeS16(buf, math.floor((pitchDeg * 10.0) + 0.5))
    writeS16(buf, math.floor(yawDeg + 0.5))
    return buf
end

local function rotatePoint(x, y, z, pitchR, yawR, rollR)
    local cbp = math.cos(BASE_VIEW_PITCH_R)
    local sbp = math.sin(BASE_VIEW_PITCH_R)
    local px = x
    local py = y * cbp - z * sbp
    local pz = y * sbp + z * cbp

    local cby = math.cos(BASE_VIEW_YAW_R)
    local sby = math.sin(BASE_VIEW_YAW_R)
    local bx = px * cby + pz * sby
    local by = py
    local bz = -px * sby + pz * cby

    local cz = math.cos(rollR)
    local sz = math.sin(rollR)
    local cx = math.cos(pitchR)
    local sx = math.sin(pitchR)
    local cy = math.cos(yawR)
    local sy = math.sin(yawR)

    local x1 = bx * cz - by * sz
    local y1 = bx * sz + by * cz
    local z1 = bz

    local x2 = x1
    local y2 = y1 * cx - z1 * sx
    local z2 = y1 * sx + z1 * cx

    return x2 * cy + z2 * sy, y2, -x2 * sy + z2 * cy
end

local function projectPoint(px, py, pz, cx, cy, scale)
    local denom = CAMERA_DIST - pz

    if denom <= CAMERA_NEAR_EPS then
        return nil, nil
    end

    local f = CAMERA_DIST / denom
    return cx + (px * f * scale), cy - (py * f * scale)
end

local function drawLine3D(a, b, cx, cy, scale, pitchR, yawR, rollR, color)
    local ax, ay, az = rotatePoint(a[1], a[2], a[3], pitchR, yawR, rollR)
    local bx, by, bz = rotatePoint(b[1], b[2], b[3], pitchR, yawR, rollR)
    local x1
    local y1
    local x2
    local y2

    if (CAMERA_DIST - az) <= CAMERA_NEAR_EPS or (CAMERA_DIST - bz) <= CAMERA_NEAR_EPS then
        return
    end

    x1, y1 = projectPoint(ax, ay, az, cx, cy, scale)
    x2, y2 = projectPoint(bx, by, bz, cx, cy, scale)
    if x1 == nil or x2 == nil then
        return
    end

    if lcd and lcd.color then
        lcd.color(color)
    end
    lcd.drawLine(x1, y1, x2, y2)
end

local function drawFilledTriangle3D(a, b, c, cx, cy, scale, pitchR, yawR, rollR, color)
    local ax, ay, az = rotatePoint(a[1], a[2], a[3], pitchR, yawR, rollR)
    local bx, by, bz = rotatePoint(b[1], b[2], b[3], pitchR, yawR, rollR)
    local cx3, cy3, cz3 = rotatePoint(c[1], c[2], c[3], pitchR, yawR, rollR)
    local x1
    local y1
    local x2
    local y2
    local x3
    local y3

    if (CAMERA_DIST - az) <= CAMERA_NEAR_EPS or (CAMERA_DIST - bz) <= CAMERA_NEAR_EPS or (CAMERA_DIST - cz3) <= CAMERA_NEAR_EPS then
        return
    end

    x1, y1 = projectPoint(ax, ay, az, cx, cy, scale)
    x2, y2 = projectPoint(bx, by, bz, cx, cy, scale)
    x3, y3 = projectPoint(cx3, cy3, cz3, cx, cy, scale)
    if x1 == nil or x2 == nil or x3 == nil then
        return
    end

    if lcd and lcd.color then
        lcd.color(color)
    end
    lcd.drawFilledTriangle(x1, y1, x2, y2, x3, y3)
end

local function collectTriangle3D(list, a, b, c, cx, cy, scale, pitchR, yawR, rollR, color)
    local ax, ay, az = rotatePoint(a[1], a[2], a[3], pitchR, yawR, rollR)
    local bx, by, bz = rotatePoint(b[1], b[2], b[3], pitchR, yawR, rollR)
    local cx3, cy3, cz3 = rotatePoint(c[1], c[2], c[3], pitchR, yawR, rollR)
    local x1
    local y1
    local x2
    local y2
    local x3
    local y3

    if (CAMERA_DIST - az) <= CAMERA_NEAR_EPS or (CAMERA_DIST - bz) <= CAMERA_NEAR_EPS or (CAMERA_DIST - cz3) <= CAMERA_NEAR_EPS then
        return
    end

    x1, y1 = projectPoint(ax, ay, az, cx, cy, scale)
    x2, y2 = projectPoint(bx, by, bz, cx, cy, scale)
    x3, y3 = projectPoint(cx3, cy3, cz3, cx, cy, scale)
    if x1 == nil or x2 == nil or x3 == nil then
        return
    end

    list[#list + 1] = {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2, x3 = x3, y3 = y3,
        z = (az + bz + cz3) / 3,
        color = color
    }
end

local function drawTriangleList(list)
    if #list == 0 then
        return
    end

    table.sort(list, function(a, b)
        return a.z < b.z
    end)

    for _, triangle in ipairs(list) do
        if lcd and lcd.color then
            lcd.color(triangle.color)
        end
        lcd.drawFilledTriangle(triangle.x1, triangle.y1, triangle.x2, triangle.y2, triangle.x3, triangle.y3)
    end
end

local function paintAlignmentView(node)
    local view = node.state.alignmentView
    local offsets = currentOffsets(node)
    local lcdW
    local lcdH
    local panelY
    local panelH
    local infoW
    local drawX
    local drawY
    local drawW
    local drawH
    local cx
    local cy
    local scale
    local pitchR
    local yawR
    local rollR
    local isDark
    local bg
    local grid
    local mainColor
    local accent
    local disc
    local bodyLight
    local bodyMid
    local bodyDark
    local liveText
    local offsText
    local nose
    local tail
    local lf
    local rf
    local lb
    local rb
    local top
    local podAftTop
    local podAftBot
    local podAftL
    local podAftR
    local mast
    local finU
    local finD
    local boomSL
    local boomSR
    local boomSU
    local boomSD
    local boomEL
    local boomER
    local boomEU
    local boomED
    local skidL1
    local skidL2
    local skidL3
    local skidL4
    local skidL5
    local skidR1
    local skidR2
    local skidR3
    local skidR4
    local skidR5
    local strutLFTop
    local strutLFBot
    local strutLBTop
    local strutLBBot
    local strutRFTop
    local strutRFBot
    local strutRBTop
    local strutRBBot
    local rotorA
    local rotorB
    local rotorC
    local rotorD
    local fuselage

    if not (lcd and lcd.getWindowSize and form and form.height) then
        return
    end

    lcdW, lcdH = lcd.getWindowSize()
    panelY = math.floor(form.height() + 2)
    panelH = lcdH - panelY - 2
    if panelH < 70 then
        return
    end

    isDark = lcd.darkMode and lcd.darkMode()
    bg = isDark and lcd.RGB(18, 18, 18) or lcd.RGB(245, 245, 245)
    grid = isDark and lcd.GREY(80) or lcd.GREY(180)
    mainColor = isDark and lcd.RGB(245, 245, 245) or lcd.RGB(20, 20, 20)
    accent = isDark and lcd.RGB(255, 210, 90) or lcd.RGB(0, 110, 235)
    disc = isDark and lcd.RGB(150, 150, 150) or lcd.RGB(150, 150, 150)
    bodyLight = isDark and lcd.RGB(220, 220, 220) or lcd.RGB(180, 180, 180)
    bodyMid = isDark and lcd.RGB(180, 180, 180) or lcd.RGB(145, 145, 145)
    bodyDark = isDark and lcd.RGB(140, 140, 140) or lcd.RGB(112, 112, 112)

    lcd.color(bg)
    lcd.drawFilledRectangle(4, panelY, lcdW - 8, panelH)
    lcd.color(grid)
    lcd.drawRectangle(4, panelY, lcdW - 8, panelH)

    infoW = math.max(150, math.floor((lcdW - 8) * 0.38))
    drawX = 4 + infoW + 8
    drawY = panelY + 6
    drawW = lcdW - drawX - 8
    drawH = panelH - 12

    lcd.drawLine(drawX - 4, panelY + 1, drawX - 4, panelY + panelH - 2)

    liveText = string.format("@i18n(app.modules.alignment.live_fmt)@", view.live.roll, view.live.pitch, view.live.yaw)
    offsText = string.format("@i18n(app.modules.alignment.offset_fmt)@", offsets.roll, offsets.pitch, offsets.yaw, tonumber(findField(node, "mag_alignment") and findField(node, "mag_alignment").value) or 0)

    if lcd.font then
        lcd.font(FONT_XS)
    end
    lcd.color(mainColor)
    lcd.drawText(12, panelY + 8, liveText, LEFT)
    lcd.drawText(12, panelY + 28, offsText, LEFT)
    lcd.drawText(12, panelY + 48, string.format("@i18n(app.modules.alignment.view_yaw_fmt)@", view.viewYawOffset), LEFT)

    cx = drawX + math.floor(drawW * 0.5)
    cy = drawY + math.floor(drawH * 0.63)
    scale = math.max(8, math.min(drawW, drawH) * 0.20)

    pitchR = math.rad(-(view.live.pitch + offsets.pitch))
    yawR = math.rad(-((view.live.yaw + offsets.yaw) - view.viewYawOffset))
    rollR = math.rad(-(view.live.roll + offsets.roll))

    nose = {2.35, 0.0, -0.02}
    tail = {-2.65, 0.0, 0.03}
    lf = {1.10, -0.62, 0.02}
    rf = {1.10, 0.62, 0.02}
    lb = {-0.55, -0.46, 0.05}
    rb = {-0.55, 0.46, 0.05}
    top = {0.05, 0.0, 0.84}
    podAftTop = {-0.66, 0.0, 0.56}
    podAftBot = {-0.66, 0.0, -0.12}
    podAftL = {-0.66, -0.30, 0.14}
    podAftR = {-0.66, 0.30, 0.14}
    mast = {0.0, 0.0, 1.02}
    finU = {-2.25, 0.0, 0.45}
    finD = {-2.25, 0.0, -0.18}
    boomSL = {-0.88, -0.10, 0.11}
    boomSR = {-0.88, 0.10, 0.11}
    boomSU = {-0.88, 0.0, 0.18}
    boomSD = {-0.88, 0.0, 0.06}
    boomEL = {-2.35, -0.06, 0.08}
    boomER = {-2.35, 0.06, 0.08}
    boomEU = {-2.35, 0.0, 0.12}
    boomED = {-2.35, 0.0, 0.05}

    skidL1 = {1.12, -0.66, -0.69}
    skidL2 = {0.76, -0.66, -0.64}
    skidL3 = {0.00, -0.66, -0.62}
    skidL4 = {-0.96, -0.66, -0.63}
    skidL5 = {-1.24, -0.66, -0.67}
    skidR1 = {1.12, 0.66, -0.69}
    skidR2 = {0.76, 0.66, -0.64}
    skidR3 = {0.00, 0.66, -0.62}
    skidR4 = {-0.96, 0.66, -0.63}
    skidR5 = {-1.24, 0.66, -0.67}

    strutLFTop = {0.52, -0.50, -0.12}
    strutLFBot = {0.48, -0.66, -0.63}
    strutLBTop = {-0.52, -0.44, -0.10}
    strutLBBot = {-0.58, -0.66, -0.63}
    strutRFTop = {0.52, 0.50, -0.12}
    strutRFBot = {0.48, 0.66, -0.63}
    strutRBTop = {-0.52, 0.44, -0.10}
    strutRBBot = {-0.58, 0.66, -0.63}

    rotorA = {0.0, -1.9, 1.02}
    rotorB = {0.0, 1.9, 1.02}
    rotorC = {-1.9, 0.0, 1.02}
    rotorD = {1.9, 0.0, 1.02}

    fuselage = {}
    collectTriangle3D(fuselage, nose, lf, top, cx, cy, scale, pitchR, yawR, rollR, bodyLight)
    collectTriangle3D(fuselage, nose, top, rf, cx, cy, scale, pitchR, yawR, rollR, bodyLight)
    collectTriangle3D(fuselage, lf, lb, top, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, rf, top, rb, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, lb, podAftTop, top, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, rb, top, podAftTop, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, lf, lb, rb, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, lf, rb, rf, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, lb, podAftL, podAftTop, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, rb, podAftTop, podAftR, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, lb, podAftBot, podAftL, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, rb, podAftR, podAftBot, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, boomSU, boomSL, boomEU, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, boomSL, boomEL, boomEU, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, boomSU, boomEU, boomSR, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, boomSR, boomEU, boomER, cx, cy, scale, pitchR, yawR, rollR, bodyMid)
    collectTriangle3D(fuselage, boomSL, boomSD, boomEL, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, boomSD, boomED, boomEL, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, boomSD, boomSR, boomED, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    collectTriangle3D(fuselage, boomSR, boomER, boomED, cx, cy, scale, pitchR, yawR, rollR, bodyDark)
    drawTriangleList(fuselage)

    drawLine3D(rotorA, rotorB, cx, cy, scale, pitchR, yawR, rollR, disc)
    drawLine3D(rotorC, rotorD, cx, cy, scale, pitchR, yawR, rollR, disc)
    drawLine3D(top, mast, cx, cy, scale, pitchR, yawR, rollR, disc)

    drawFilledTriangle3D(nose, lf, rf, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(nose, lf, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(nose, rf, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(lf, lb, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(rf, rb, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(lb, tail, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(rb, tail, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(top, nose, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(boomSU, boomEU, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(boomSL, boomEL, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(boomSR, boomER, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(boomSD, boomED, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(boomSU, boomSL, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(boomSL, boomSD, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(boomSD, boomSR, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(boomSR, boomSU, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(finU, finD, cx, cy, scale, pitchR, yawR, rollR, accent)
    drawLine3D(skidL1, skidL2, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidL2, skidL3, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidL3, skidL4, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidL4, skidL5, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidR1, skidR2, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidR2, skidR3, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidR3, skidR4, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(skidR4, skidR5, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLFTop, strutLFBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLBTop, strutLBBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutRFTop, strutRFBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutRBTop, strutRBBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLFBot, strutRFBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLBBot, strutRBBot, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLFTop, strutRFTop, cx, cy, scale, pitchR, yawR, rollR, mainColor)
    drawLine3D(strutLBTop, strutRBTop, cx, cy, scale, pitchR, yawR, rollR, mainColor)
end

local function requestAttitude(node)
    local view = node.state.alignmentView
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local now = os.clock()

    if view.pendingAttitude == true or not (mspTask and mspTask.queueCommand) then
        return false
    end

    view.pendingAttitude = true
    view.pendingAt = now

    return mspTask:queueCommand(MSP_ATTITUDE, {}, {
        timeout = 1.0,
        simulatorResponse = (system and system.getVersion and system.getVersion().simulation == true) and buildSimulatedAttitudeResponse(view, now) or {},
        onReply = function(_, buf)
            if not nodeIsOpen(node) then
                return
            end

            view.live.roll = (readS16(buf, 1) or 0) / 10.0
            view.live.pitch = (readS16(buf, 3) or 0) / 10.0
            view.live.yaw = tonumber(readS16(buf, 5)) or 0
            view.pendingAttitude = false

            if view.autoRecenterPending == true then
                recenterYawView(node)
                view.autoRecenterPending = false
            end
        end,
        onError = function()
            if not nodeIsOpen(node) then
                return
            end
            view.pendingAttitude = false
        end
    })
end

function BasePage:open(ctx)
    local node = baseOpen(self, ctx)
    local baseBuildForm = node.buildForm
    local baseWakeup = node.wakeup

    node.state.alignmentView = {
        live = {roll = 0, pitch = 0, yaw = 0},
        viewYawOffset = 0,
        lastAttitudeAt = 0,
        invalidateAt = 0,
        attitudeSamplePeriod = 0.08,
        pendingAttitude = false,
        pendingAt = 0,
        pendingTimeout = 1.0,
        pollingEnabled = false,
        autoRecenterPending = true,
        simStartAt = os.clock()
    }

    function node:buildForm(app)
        self.app = app

        if self.state.error or self.state.loaded ~= true then
            return baseBuildForm(self, app)
        end

        if buildCompactForm(self, app) ~= true then
            return baseBuildForm(self, app)
        end
    end

    function node:onToolMenu()
        return openConfirmDialog(
            "@i18n(app.modules.alignment.name)@",
            "@i18n(app.modules.alignment.msg_reset_tail_view)@",
            function()
                recenterYawView(node)
            end
        )
    end

    function node:wakeup(app)
        local view = self.state.alignmentView
        local now = os.clock()
        local session
        local mspTask

        if baseWakeup then
            baseWakeup(self, app)
        end

        if self.state.loaded ~= true or self.state.loading == true or self.state.saving == true or self.state.error then
            return
        end

        session = self.app and self.app.framework and self.app.framework.session or nil
        if system and system.getVersion and system.getVersion().simulation ~= true and session and session.get and session:get("telemetryState", false) ~= true then
            return
        end

        if self.app and self.app.isLoaderActive and self.app:isLoaderActive() == true then
            return
        end

        mspTask = self.app and self.app.framework and self.app.framework.getTask and self.app.framework:getTask("msp") or nil
        if not (mspTask and mspTask.mspQueue and mspTask.mspQueue.isProcessed) then
            return
        end

        if view.pendingAttitude == true and (now - view.pendingAt) > view.pendingTimeout then
            view.pendingAttitude = false
        end

        if (now - view.lastAttitudeAt) >= view.attitudeSamplePeriod and mspTask.mspQueue:isProcessed() == true then
            view.lastAttitudeAt = now
            requestAttitude(self)
        end

        if (now - view.invalidateAt) >= 0.08 then
            view.invalidateAt = now
            lcd.invalidate()
        end
    end

    function node:paint()
        if self.state.loaded ~= true or self.state.error ~= nil then
            return
        end

        paintAlignmentView(self)
    end

    return node
end

return BasePage
