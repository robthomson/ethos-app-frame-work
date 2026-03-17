--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local protocols = {
    sport = {
        name = "sport",
        maxTxBufferSize = 6,
        maxRxBufferSize = 6,
        maxRetries = 10,
        timeout = 4.0,
        retryBackoff = 1.0,
        interMessageDelay = 0.05,
        mspInterval = 0.15,
        pollSliceSeconds = 0.006,
        pollSlicePolls = 4,
        maxQueueDepth = 20
    },
    crsf = {
        name = "crsf",
        maxTxBufferSize = 8,
        maxRxBufferSize = 58,
        maxRetries = 5,
        timeout = 2.0,
        retryBackoff = 0.5,
        interMessageDelay = 0.03,
        mspInterval = 0.15,
        pollSliceSeconds = 0.004,
        pollSlicePolls = 6,
        maxQueueDepth = 20
    }
}

function protocols.resolve(transportType)
    return protocols[transportType]
end

return protocols
