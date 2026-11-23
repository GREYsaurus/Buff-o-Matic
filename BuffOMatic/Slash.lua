-- Buff-o-Matic: slash commands (/bfm, /buffomatic).
local _, ns = ...
local L, C, B, P = ns.L, ns.Compat, ns.Blessings, ns.Priorities
local R = ns.Roster

local function p(msg) ns.Print(msg) end

local FAMILY_ALIASES = { kings = "KINGS", bok = "KINGS", might = "MIGHT", bom = "MIGHT", wisdom = "WISDOM", wis = "WISDOM", bow = "WISDOM" }
local ROLE_ALIASES = { tank = "TANK", healer = "HEALER", heal = "HEALER", dps = "DAMAGER", damage = "DAMAGER", damager = "DAMAGER", none = "NONE", unknown = "NONE" }

local function parseFamilies(s)
    local out = {}
    for tok in s:gmatch("[^,%s]+") do
        local f = FAMILY_ALIASES[tok:lower()]
        if not f then return nil, tok end
        out[#out + 1] = f
    end
    return out
end

local function onoff(v, current)
    if v == "on" or v == "1" or v == "true" then return true end
    if v == "off" or v == "0" or v == "false" then return false end
    return not current
end

-- "<name with spaces> <last>" -> name, last
local function splitLast(rest)
    local name, last = rest:match("^(.-)%s+(%S+)$")
    return name, last
end

local function resolveName(name)
    local lower = name:lower()
    if lower == "me" or lower == "self" or lower == "myself" then return C.UnitName("player") or name end
    local m = R.FindByName(name)
    return m and m.name or name
end

local function changed()
    ns.RequestRefresh(true)
end

local HELP = {
    "/bfm show | hide | lock | unlock | scale <0.5-2>",
    "/bfm self on|off  - include yourself in the rotation",
    "/bfm raid on|off  - rotate through the whole raid (default: your subgroup)",
    "/bfm greater on|off  - allow safe Greater Blessings (needs Symbol of Kings)",
    "/bfm sticky on|off  - keep your healthy existing blessing (default on)",
    "/bfm refresh <min> | warn <min> | grace <sec>",
    "/bfm shortpct <0-1> | shortwarnpct <0-1>  - short-duration policy",
    "/bfm assign <name> <kings|might|wisdom|auto>",
    "/bfm role <name|me> <tank|healer|dps|auto>  (or right-click a row)",
    "/bfm prio <name> <kings,might,...|auto>",
    "/bfm classprio <CLASS> <TANK|HEALER|DAMAGER|NONE> <list|default>",
    "/bfm exclude <name> on|off",
    "/bfm sound on|off | chat on|off | others on|off | members on|off | buttons on|off",
    "/bfm table  - print effective priority tables",
    "/bfm reset  - reset position and rotation state | resetall confirm - all settings",
    "/bfm debug on|off | diag",
}

local function diag()
    local _, build, _, toc = GetBuildInfo()
    p(string.format("client build %s, interface %s, project %s, Forever=%s", tostring(build), tostring(toc),
        tostring(WOW_PROJECT_ID), tostring(C.IsForever())))
    p(string.format("APIs: C_UnitAuras=%s issecretvalue=%s secretRestrictions=%s combat=%s",
        tostring(C_UnitAuras ~= nil), tostring(issecretvalue ~= nil), tostring(C.HasSecretRestrictions()), tostring(C.InCombat())))
    local known = {}
    for _, f in ipairs(B.ORDER) do
        local k, g = ns.spells.known[f], ns.spells.greaterKnown[f]
        known[#known + 1] = f .. "=" .. (k and k.id or "-") .. "/" .. (g and g.id or "-")
    end
    p("known (single/greater): " .. table.concat(known, " ") .. "  Symbol of Kings: " .. C.ItemCount(B.SYMBOL_OF_KINGS))
    local db = ns.db
    p(string.format("thresholds: refresh<%ds warn<%ds shortPct=%.2f/%.2f grace=%ds sticky=%s greater=%s self=%s",
        db.refreshThreshold, db.warnThreshold, db.shortRefreshPct, db.shortWarnPct, db.graceSeconds,
        tostring(db.sticky), tostring(db.greaterMode), tostring(db.includeSelf)))
    local a = ns.prepared
    p("prepared: " .. (a and (a.family .. " -> " .. tostring(R.members[a.guid] and R.members[a.guid].name) ..
        " (" .. a.unit .. (a.greater and ", greater" or "") .. ")") or "none") ..
        "  button type=" .. tostring(ns.mainButton and ns.mainButton:GetAttribute("type")) ..
        " cursor=" .. tostring(ns.sched.cursorGUID and R.members[ns.sched.cursorGUID] and R.members[ns.sched.cursorGUID].name))
    for _, m in pairs(R.members) do
        local d = ns.decisions[m.guid]
        local mine = m.mine and (m.mine.family .. " " .. ns.FormatTime(m.mine.expirationTime and (m.mine.expirationTime - GetTime()))) or "-"
        local others = {}
        for f, o in pairs(m.others or {}) do others[#others + 1] = f .. "(" .. tostring(o.casterName or o.casterKind) .. ")" end
        p(string.format("  %s [%s %s%s] %s %s | mine=%s others=%s block=%s%s", m.name, tostring(m.class), tostring(m.role),
            m.excluded and " excl" or "", d and d.status or "?", d and tostring(d.family) or "", mine,
            table.concat(others, ","), tostring(ns.blocks[m.guid]), m.unreadable and " UNREADABLE" or ""))
    end
end

local function printTables()
    for class, roles in pairs(P.DEFAULTS) do
        for _, role in ipairs(P.ROLES) do
            if roles[role] or (ns.db.classRole[class] and ns.db.classRole[class][role]) then
                local list, src = P.Resolve(class, role, ns.db.classRole)
                p(string.format("%s %s: %s (%s)", class, role, table.concat(list, " > "), src))
            end
        end
    end
end

local function handler(msg)
    if not ns.db then return end
    local db = ns.db
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if not ns.enabled and cmd ~= "" and cmd ~= "help" then p(L.NOT_PALADIN) return end

    if cmd == "" or cmd == "help" then
        for _, line in ipairs(HELP) do p(line) end
    elseif cmd == "show" then ns.UI.SetShown(true)
    elseif cmd == "hide" then ns.UI.SetShown(false)
    elseif cmd == "lock" then db.locked = true p("locked")
    elseif cmd == "unlock" then db.locked = false p("unlocked (drag the window)")
    elseif cmd == "scale" then
        local v = tonumber(rest)
        if v and v >= 0.5 and v <= 2 then
            db.scale = v
            ns.RunOOC("scale", function() ns.UI.frame:SetScale(v) end)
        end
    elseif cmd == "self" then db.includeSelf = onoff(rest, db.includeSelf) p("include self: " .. tostring(db.includeSelf)) changed()
    elseif cmd == "raid" then db.raid = onoff(rest, db.raid) p("whole raid: " .. tostring(db.raid)) changed()
    elseif cmd == "greater" then db.greaterMode = onoff(rest, db.greaterMode) p("greater mode: " .. tostring(db.greaterMode)) changed()
    elseif cmd == "sticky" then db.sticky = onoff(rest, db.sticky) p("sticky: " .. tostring(db.sticky)) changed()
    elseif cmd == "sound" then db.sound = onoff(rest, db.sound) p("sound: " .. tostring(db.sound))
    elseif cmd == "chat" then db.chatAlerts = onoff(rest, db.chatAlerts) p("chat alerts: " .. tostring(db.chatAlerts))
    elseif cmd == "others" then db.showOthers = onoff(rest, db.showOthers) changed()
    elseif cmd == "members" then db.showMembers = onoff(rest, db.showMembers) ns.UI.Layout() changed()
    elseif cmd == "buttons" then db.memberButtons = onoff(rest, db.memberButtons) p("member buttons: " .. tostring(db.memberButtons)) changed()
    elseif cmd == "refresh" or cmd == "warn" then
        local v = tonumber(rest)
        if not v or v <= 0 then p("usage: /bfm " .. cmd .. " <minutes>") return end
        db[cmd == "refresh" and "refreshThreshold" or "warnThreshold"] = math.floor(v * 60 + 0.5)
        p(cmd .. " threshold: " .. ns.FormatTime(v * 60)) changed()
    elseif cmd == "grace" then
        local v = tonumber(rest)
        if v and v >= 0 then db.graceSeconds = v p("grace: " .. v .. "s") changed() end
    elseif cmd == "shortpct" or cmd == "shortwarnpct" then
        local v = tonumber(rest)
        if v and v > 0 and v < 1 then db[cmd == "shortpct" and "shortRefreshPct" or "shortWarnPct"] = v p(cmd .. " = " .. v) changed() end
    elseif cmd == "assign" or cmd == "role" or cmd == "prio" or cmd == "exclude" then
        local name, val = splitLast(rest)
        if not name or name == "" then p("usage: /bfm " .. cmd .. " <name> <value>") return end
        name = resolveName(name)
        local pl = ns.Settings.Player(name, true)
        val = val:lower()
        if cmd == "assign" then
            if val == "auto" or val == "none" then pl.assigned = nil
            else
                local f = FAMILY_ALIASES[val]
                if not f then p("unknown blessing: " .. val) return end
                pl.assigned = f
            end
            p(name .. " assigned: " .. tostring(pl.assigned or "auto"))
        elseif cmd == "role" then
            if val == "auto" then pl.role = nil
            else
                local r = ROLE_ALIASES[val]
                if not r then p("unknown role: " .. val) return end
                pl.role = r
            end
            p(name .. " role: " .. tostring(pl.role or "auto"))
        elseif cmd == "prio" then
            if val == "auto" then pl.priority = nil
            else
                local list, bad = parseFamilies(val)
                if not list then p("unknown blessing: " .. bad) return end
                pl.priority = list
            end
            p(name .. " priority: " .. (pl.priority and table.concat(pl.priority, " > ") or "auto"))
        else
            pl.exclude = onoff(val, pl.exclude)
            p(name .. " excluded: " .. tostring(pl.exclude))
        end
        changed()
    elseif cmd == "classprio" then
        local class, role, list = rest:match("^(%S+)%s+(%S+)%s*(.*)$")
        if not class then p("usage: /bfm classprio <CLASS> <ROLE> <kings,might,...|default>") return end
        class, role = class:upper(), role:upper()
        if role == "DPS" then role = "DAMAGER" end
        db.classRole[class] = db.classRole[class] or {}
        if list == "" or list:lower() == "default" then
            db.classRole[class][role] = nil
        else
            local fams, bad = parseFamilies(list)
            if not fams then p("unknown blessing: " .. bad) return end
            db.classRole[class][role] = fams
        end
        p(class .. " " .. role .. ": " .. table.concat((P.Resolve(class, role, db.classRole)), " > "))
        changed()
    elseif cmd == "table" then printTables()
    elseif cmd == "reset" then
        ns.UI.ResetPosition()
        ns.sched = ns.Scheduler.NewState()
        ns.cast = ns.CastState.New()
        p("position and rotation state reset") changed()
    elseif cmd == "resetall" then
        if rest ~= "confirm" then p("type /bfm resetall confirm to reset ALL settings and assignments") return end
        BuffOMaticDB = ns.Settings.Fresh()
        ns.db = BuffOMaticDB
        ns.UI.ResetPosition()
        p("all settings reset") changed()
    elseif cmd == "debug" then db.debug = onoff(rest, db.debug) p("debug: " .. tostring(db.debug))
    elseif cmd == "diag" then diag()
    else
        p("unknown command; /bfm help")
    end
end

SLASH_BUFFOMATIC1 = "/bfm"
SLASH_BUFFOMATIC2 = "/buffomatic"
SlashCmdList.BUFFOMATIC = handler
