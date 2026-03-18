--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")
local utils = require("lib.utils")

local audio = {}

local function baseDir()
    return tostring((framework.config and framework.config.baseDir) or "rfsuite")
end

local function preferencesDir()
    return tostring((framework.config and framework.config.preferences) or "rfsuite.user")
end

local function currentVoiceFolder()
    local voice

    if not system or type(system.getAudioVoice) ~= "function" then
        return "en/default"
    end

    voice = tostring(system.getAudioVoice() or "")
    voice = voice:gsub("SD:", "")
    voice = voice:gsub("RADIO:", "")
    voice = voice:gsub("AUDIO:", "")
    voice = voice:gsub("VOICE[1-4]:", "")
    voice = voice:gsub("audio/", "")

    if voice:sub(1, 1) == "/" then
        voice = voice:sub(2)
    end

    if voice == "" then
        return "en/default"
    end

    return voice
end

function audio.resolvePackageFile(pkg, file)
    local packageName = tostring(pkg or "")
    local fileName = tostring(file or "")
    local voiceFolder = currentVoiceFolder()
    local candidates
    local index

    if packageName == "" or fileName == "" then
        return nil
    end

    candidates = {
        "SCRIPTS:/" .. preferencesDir() .. "/audio/user/" .. packageName .. "/" .. fileName,
        "SCRIPTS:/" .. baseDir() .. "/audio/" .. voiceFolder .. "/" .. packageName .. "/" .. fileName,
        "SCRIPTS:/" .. baseDir() .. "/audio/en/default/" .. packageName .. "/" .. fileName
    }

    for index = 1, #candidates do
        if utils.file_exists(candidates[index]) then
            return candidates[index]
        end
    end

    return nil
end

function audio.resolvePackageFiles(pkg, files)
    local resolved = {}
    local missing = {}
    local index
    local path

    if type(files) ~= "table" then
        return resolved, missing
    end

    for index = 1, #files do
        path = audio.resolvePackageFile(pkg, files[index])
        if path then
            resolved[#resolved + 1] = path
        else
            missing[#missing + 1] = tostring(files[index])
        end
    end

    return resolved, missing
end

function audio.resolveModelAnnouncementFile(name)
    local craftName = tostring(name or "")
    local candidates
    local index

    if craftName == "" then
        return nil
    end

    candidates = {
        "audio/" .. craftName .. ".wav",
        "audio/" .. string.gsub(craftName, " ", "_") .. ".wav"
    }

    for index = 1, #candidates do
        if utils.file_exists(candidates[index]) then
            return candidates[index]
        end
    end

    return nil
end

function audio.playResolved(path)
    if not path or not system or type(system.playFile) ~= "function" then
        return false
    end

    pcall(system.playFile, path)
    return true
end

function audio.playFile(pkg, file)
    return audio.playResolved(audio.resolvePackageFile(pkg, file))
end

function audio.playFileCommon(file)
    return audio.playResolved("audio/" .. tostring(file or ""))
end

function audio.playNumber(value, unit, decimals)
    if not system or type(system.playNumber) ~= "function" or value == nil then
        return false
    end

    pcall(system.playNumber, value, unit, decimals)
    return true
end

function audio.playHaptic(duration, pause, flags)
    if not system or type(system.playHaptic) ~= "function" then
        return false
    end

    pcall(system.playHaptic, duration or 15, pause or 0, flags or 0)
    return true
end

return audio
