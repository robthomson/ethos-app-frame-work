return {
    title = "Diagnostics",
    subtitle = "System / Tools / Diagnostics",
    items = {
        {id = "rfstatus", title = "RF Status", subtitle = "RF and background health", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/rfstatus.lua"},
        {id = "sensors", title = "Sensors", subtitle = "Sensor validation and repair", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/sensors.lua", offline = true},
        {id = "info", title = "Info", subtitle = "Device information", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/info.lua", offline = true},
        {id = "fblstatus", title = "FBL Status", subtitle = "Flight controller status", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/fblstatus.lua"},
        {id = "fblsensors", title = "FBL Sensors", subtitle = "Flight controller sensor view", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/fblsensors.lua"}
    }
}
