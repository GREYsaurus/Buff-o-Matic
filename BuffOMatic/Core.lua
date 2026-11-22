-- Buff-o-Matic: namespace, event dispatch, out-of-combat queue, printing.
local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "1.0.0"

local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok and ns.db and ns.db.debug then print("|cffff4040Buff-o-Matic error|r", event, err) end
    end
end)

-- Unit events for the player (spellcast tracking) on their own frame.
local unitFrame = CreateFrame("Frame")
local unitHandlers = {}
function ns.OnPlayerUnit(event, fn)
    unitHandlers[event] = fn
    unitFrame:RegisterUnitEvent(event, "player")
end
unitFrame:SetScript("OnEvent", function(_, event, ...)
    local fn = unitHandlers[event]
    if fn then
        local ok, err = pcall(fn, event, ...)
        if not ok and ns.db and ns.db.debug then print("|cffff4040Buff-o-Matic error|r", event, err) end
    end
end)

-- Protected work (frame layout/show/hide/attributes) is deferred until combat ends.
local oocQueue, oocOrder = {}, {}
function ns.RunOOC(key, fn)
    if InCombatLockdown() then
        if not oocQueue[key] then oocOrder[#oocOrder + 1] = key end
        oocQueue[key] = fn
        return false
    end
    fn()
    return true
end
ns.On("PLAYER_REGEN_ENABLED", function()
    local order = oocOrder
    oocOrder = {}
    for _, key in ipairs(order) do
        local fn = oocQueue[key]
        oocQueue[key] = nil
        if fn then fn() end
    end
end)

function ns.Print(msg)
    print("|cffffd100Buff-o-Matic|r: " .. tostring(msg))
end

function ns.Debug(...)
    if ns.db and ns.db.debug then print("|cff888888BoM|r", ...) end
end

function ns.FormatTime(sec)
    if sec == nil then return "?" end
    if sec < 0 then sec = 0 end
    sec = math.floor(sec)
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end
