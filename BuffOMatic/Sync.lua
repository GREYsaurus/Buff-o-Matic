-- Buff-o-Matic: event glue for PallyPower coordination (read-only) and the ready-check nudge.
local _, ns = ...
local L, C = ns.L, ns.Compat
local PP, R = ns.PPSync, ns.Roster

ns.pp = PP.New()

---------------------------------------------------------------- PallyPower (listen only)
local function registerPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, PP.PREFIX)
    end
end
registerPrefix()

-- Wire names may carry a "-Realm" suffix; map them onto the roster's spelling.
local function norm(name)
    if type(name) == "string" then
        for _, m in pairs(R.members) do
            if m.name == name then return name end
        end
        local base = name:match("^(.-)%-[^%-%s]+$")
        if base then
            for _, m in pairs(R.members) do
                if m.name == base then return base end
            end
        end
    end
    return name
end

local function isLeader(name)
    local m = R.FindByName(name)
    if not m or not m.unit then return false end
    return C.SafeBool(UnitIsGroupLeader, false, m.unit) or C.SafeBool(UnitIsGroupAssistant, false, m.unit)
end

ns.On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
    if not ns.enabled or not ns.db.pallyPowerSync then return end
    if C.IsSecret(prefix) or C.IsSecret(msg) or C.IsSecret(sender) or C.IsSecret(channel) then return end
    if prefix ~= PP.PREFIX then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" and channel ~= "WHISPER" then return end
    if Ambiguate then sender = Ambiguate(sender, "none") end
    if norm(sender) == C.UnitName("player") then return end
    if PP.Parse(ns.pp, msg, sender, isLeader(sender), norm) then
        ns.Debug("PallyPower", sender, msg)
        ns.RequestRefresh()
    end
end)

-- Ask PallyPower users to resend their plans (they answer by whisper). Throttled, never
-- in combat, and silently skipped if the client restricts addon messages.
local lastReq = -math.huge
function ns.RequestPallyPower(force)
    if not ns.enabled or not ns.db.pallyPowerSync then return end
    if not IsInGroup() or C.InCombat() then return end
    local now = GetTime()
    if not force and now - lastReq < 30 then return end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked == true then return end
    end
    lastReq = now
    local channel = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and IsInInstance()) and "INSTANCE_CHAT"
        or (IsInRaid() and "RAID") or "PARTY"
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PP.PREFIX, "REQ", channel)
    end
end

-- Other paladins currently in the group (names as the roster spells them).
local function otherPaladins()
    local list = {}
    for _, m in pairs(R.members) do
        if m.class == "PALADIN" and not m.isSelf then list[#list + 1] = m.name end
    end
    table.sort(list)
    return list
end

-- Called by ns.Refresh before decisions: annotate members with PallyPower plans.
function ns.ApplyPallyPower()
    local on = ns.db.pallyPowerSync
    local pals = on and otherPaladins() or {}
    local me = C.UnitName("player")
    for _, m in pairs(R.members) do
        if on then
            m.planned, m.ppAssigned = PP.ForMember(ns.pp, m, me, pals)
        else
            m.planned, m.ppAssigned = nil, nil
        end
    end
end

ns.On("GROUP_JOINED", function() C_Timer.After(3, function() ns.RequestPallyPower(true) end) end)
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(5, function() ns.RequestPallyPower() end) end)
ns.On("GROUP_LEFT", function() ns.pp = PP.New() end)

---------------------------------------------------------------- ready check nudge
function ns.ReadyCheckNudge()
    if not ns.enabled or not ns.db.readyCheck then return end
    local sum = ns.summary
    if not sum then return end
    local names = {}
    for _, m in ipairs(sum.missing or {}) do names[#names + 1] = m.name end
    local warn = sum.warn and sum.shortest
    if #names == 0 and not warn then return end
    if ns.db.sound then PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master") end
    if #names > 0 then
        ns.Print(string.format(L.READY_MISSING, table.concat(names, ", ")))
    end
    if warn then
        ns.Print(string.format(L.READY_EXPIRING, ns.FamilyName(warn.family), warn.member.name,
            ns.FormatTime(warn.remaining)))
    end
    if ns.UI and ns.UI.Flash then ns.UI.Flash() end
end

ns.On("READY_CHECK", function()
    -- Let a pending refresh land first so the summary is current.
    C_Timer.After(0.2, ns.ReadyCheckNudge)
end)
