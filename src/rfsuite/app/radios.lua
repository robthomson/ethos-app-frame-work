--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local lcd = lcd

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
        navbuttonHeight = 40
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
        navbuttonHeight = 30
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
        navbuttonHeight = 35
    }
}

return assert(supportedRadios[resolution], resolution .. " not supported")
