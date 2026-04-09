--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local lcd = lcd
local abs = math.abs
local format = string.format

local LCD_W, LCD_H = lcd.getWindowSize()
local resolution = LCD_W .. "x" .. LCD_H

local supportedRadios = {
    ["784x406"] = {
        buttonWidth = 120,
        buttonHeight = 120,
        buttonPadding = 10,
        buttonWidthSmall = 105,
        buttonHeightSmall = 110,
        buttonPaddingSmall = 6,
        buttonsPerRow = 6,
        buttonsPerRowSmall = 7,
        inlinesize_mult = 1,
        linePaddingTop = 8,
        menuButtonWidth = 100,
        navbuttonHeight = 40,
        logGraphButtonsPerRow = 5,
        logGraphHeightOffset = -15,
        logGraphKeyHeight = 65,
        logGraphMenuOffset = 70,
        logGraphWidthPercentage = 0.77,
        logKeyFont = FONT_S,
        logKeyFontSmall = FONT_XS,
        logShowAvg = true,
        logSliderPaddingLeft = 42
    },
    ["472x288"] = {
        buttonWidth = 110,
        buttonHeight = 110,
        buttonPadding = 8,
        buttonWidthSmall = 89,
        buttonHeightSmall = 95,
        buttonPaddingSmall = 5,
        buttonsPerRow = 4,
        buttonsPerRowSmall = 5,
        inlinesize_mult = 1.28,
        linePaddingTop = 6,
        menuButtonWidth = 60,
        navbuttonHeight = 30,
        navButtonOffset = 47,
        logGraphButtonsPerRow = 4,
        logGraphHeightOffset = 10,
        logGraphKeyHeight = 45,
        logGraphMenuOffset = 55,
        logGraphWidthPercentage = 0.70,
        logKeyFont = FONT_XS,
        logKeyFontSmall = FONT_XXS,
        logShowAvg = false,
        logSliderPaddingLeft = 30
    },
    ["632x314"] = {
        buttonWidth = 118,
        buttonHeight = 120,
        buttonPadding = 7,
        buttonWidthSmall = 97,
        buttonHeightSmall = 115,
        buttonPaddingSmall = 8,
        buttonsPerRow = 5,
        buttonsPerRowSmall = 6,
        inlinesize_mult = 1.11,
        linePaddingTop = 6,
        menuButtonWidth = 80,
        navbuttonHeight = 35,
        navButtonOffset = 47,
        logGraphButtonsPerRow = 4,
        logGraphHeightOffset = 0,
        logGraphKeyHeight = 50,
        logGraphMenuOffset = 60,
        logGraphWidthPercentage = 0.74,
        logKeyFont = FONT_XXS,
        logKeyFontSmall = FONT_XXS,
        logShowAvg = false,
        logSliderPaddingLeft = 30
    }
}

local function findClosestResolution(width, height, radios)
    local chosenKey
    local bestDistance

    for resKey in pairs(radios) do
        local resWidth, resHeight = resKey:match("^(%d+)x(%d+)$")

        if resWidth and resHeight then
            local distance = abs(width - tonumber(resWidth)) + abs(height - tonumber(resHeight))

            if bestDistance == nil or distance < bestDistance then
                chosenKey = resKey
                bestDistance = distance
            end
        end
    end

    return chosenKey, bestDistance
end

local chosenResolution = resolution

if not supportedRadios[chosenResolution] then
    chosenResolution = findClosestResolution(LCD_W, LCD_H, supportedRadios)

    if chosenResolution then
        print(format("[app] %s not supported; using closest match %s", resolution, chosenResolution))
    end
end

local radio = assert(supportedRadios[chosenResolution], resolution .. " not supported")
radio.detectedResolution = resolution
radio.selectedResolution = chosenResolution

return radio
