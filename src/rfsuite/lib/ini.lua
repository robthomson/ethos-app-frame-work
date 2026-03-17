--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = {}

function ini.load_file_as_string(path)
    local file = io.open(path, "rb")
    local content
    local chunk

    if not file then
        return nil, "Cannot open file: " .. tostring(path)
    end

    content = ""
    repeat
        chunk = io.read(file, "L")
        if chunk then
            content = content .. chunk
        end
    until not chunk

    io.close(file)

    return content
end

function ini.load_ini_file(fileName)
    local content
    local data = {}
    local section = nil

    assert(type(fileName) == "string", 'Parameter "fileName" must be a string.')

    content = ini.load_file_as_string(fileName)
    if not content then
        return nil
    end

    for line in string.gmatch(content, "[^\r\n]+") do
        local param
        local value

        line = line:match("^%s*(.-)%s*$")

        if line ~= "" and line:sub(1, 1) ~= ";" then
            if line:match("^%[.+%]$") then
                section = line:match("^%[(.+)%]$")
                if section then
                    section = section:match("^%s*(.-)%s*$")
                    section = tonumber(section) or section
                    data[section] = data[section] or {}
                end
            else
                param, value = line:match("^([%w_]+)%s-=%s-(.*)$")
                if param and value and section then
                    param = tonumber(param) or param

                    if value == "true" then
                        value = true
                    elseif value == "false" then
                        value = false
                    elseif tonumber(value) then
                        value = tonumber(value)
                    end

                    data[section][param] = value
                end
            end
        end
    end

    return data
end

function ini.save_ini_file(fileName, data)
    local file
    local ok, err

    assert(type(fileName) == "string", 'Parameter "fileName" must be a string.')
    assert(type(data) == "table", 'Parameter "data" must be a table.')

    file, err = io.open(fileName, "w")
    if not file then
        return false, err
    end

    for section, params in pairs(data) do
        file:write("[" .. tostring(section) .. "]\n")
        for key, value in pairs(params) do
            if type(value) == "boolean" then
                value = value and "true" or "false"
            end
            file:write(string.format("%s=%s\n", tostring(key), tostring(value)))
        end
        file:write("\n")
    end

    ok, err = file:close()
    if ok == false then
        return false, err
    end

    return true
end

function ini.merge_ini_tables(master, slave)
    local merged = {}

    assert(type(master) == "table", "master must be a table")
    assert(type(slave) == "table", "slave must be a table")

    for section, slaveSection in pairs(slave) do
        merged[section] = {}
        for key, value in pairs(slaveSection) do
            merged[section][key] = value
        end
        if master[section] then
            for key, value in pairs(master[section]) do
                merged[section][key] = value
            end
        end
    end

    for section, masterSection in pairs(master) do
        if not merged[section] then
            merged[section] = {}
            for key, value in pairs(masterSection) do
                merged[section][key] = value
            end
        end
    end

    return merged
end

function ini.ini_tables_equal(a, b)
    for section, bValues in pairs(b) do
        local aValues = a[section] or {}
        for key in pairs(bValues) do
            if aValues[key] == nil then
                return false
            end
        end
    end

    return true
end

function ini.getvalue(data, section, key)
    if data and section and key and data[section] and data[section][key] ~= nil then
        return data[section][key]
    end

    return nil
end

function ini.section_exists(data, section)
    return data and data[section] ~= nil
end

function ini.setvalue(data, section, key, value)
    if not data then
        return
    end

    data[section] = data[section] or {}
    data[section][key] = value
end

return ini
