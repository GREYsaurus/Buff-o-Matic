-- Buff-o-Matic: orchestration. Event-driven refresh, decision pass, scheduling, secure
-- preparation, cast tracking and alert state. One modest 1 s ticker drives timers/range.
local ADDON, ns = ...
local L, C, B = ns.L, ns.Compat, ns.Blessings
local E, S, CS, G, Pr, T = ns.Engine, ns.Scheduler, ns.CastState, ns.Greater, ns.Prepare, ns.Thresholds
local R, Au = ns.Roster, ns.Auras

ns.sched = S.NewState()
ns.cast = CS.New()
ns.decisions = {}
ns.blocks = {}
ns.prepared = nil
ns.alert = { active = false, last = 0 }
ns.enabled = false

---------------------------------------------------------------- spells
ns.spells = { known = {}, greaterKnown = {} }

function ns.ScanSpells()
    local known, gk = {}, {}
    for fam, f in pairs(B.FAMILIES) do
        for i = #f.single, 1, -1 do
            local id = f.single[i]
            if C.IsKnown(id) then known[fam] = { id = id, name = C.SpellName(id) } break end
        end
        for i = #f.greater, 1, -1 do
            local id = f.greater[i]
            if C.IsKnown(id) then gk[fam] = { id = id, name = C.SpellName(id) } break end
        end
    end
    ns.spells = { known = known, greaterKnown = gk }
end

function ns.FamilyName(fam)
    return L["FAM_" .. tostring(fam)]
end

---------------------------------------------------------------- castability
local function castability(m, spellID)
    local unit = m.unit
    if R.unitToGUID[unit] ~= m.guid or C.UnitGUID(unit) ~= m.guid then return false, "GONE" end
    if not C.SafeBool(UnitIsConnected, true, unit) then return false, "OFFLINE" end
    if C.SafeBool(UnitIsDeadOrGhost, false, unit) then return false, "DEAD" end
    if not m.isSelf then
        if not C.SafeBool(UnitIsVisible, true, unit) then return false, "NOT_VISIBLE" end
        if C.InRange(spellID, unit) == false then return false, "OUT_OF_RANGE" end
    end
    local usable, noMana = C.Usable(spellID)
    if noMana then return false, "NO_MANA_SELF" end
    if usable == false then return false, "UNUSABLE" end
    return true
end

---------------------------------------------------------------- refresh
local auraDirty = {}
local pendingTimer, pendingRoster = false, false

function ns.MarkAuraDirty(unit) auraDirty[unit] = true end

function ns.RequestRefresh(roster)
    if roster then pendingRoster = true end
    if pendingTimer then return end
    pendingTimer = true
    C_Timer.After(0.1, function()
        pendingTimer = false
        local r = pendingRoster
        pendingRoster = false
        ns.Refresh(r)
    end)
end

local function buildCtx(now)
    return {
        now = now, settings = ns.db, known = ns.spells.known,
        lastCast = ns.cast.lastCast, classRoleOverrides = ns.db.classRole,
    }
end

function ns.Refresh(rosterChanged)
    if not ns.enabled then return end
    local db, now = ns.db, GetTime()
    local inCombat = C.InCombat()

    if (rosterChanged or not next(R.members)) and inCombat and next(R.members) then
        -- Unit tokens may now point at different people and GUIDs may be secret: keep the
        -- old snapshot, flag it, and rebuild when combat ends.
        ns.rosterStale = true
        auraDirty = {}
    elseif rosterChanged or not next(R.members) then
        ns.rosterStale = false
        local valid = R.Rebuild()
        Au.Forget(valid)
        for _, m in pairs(R.members) do Au.Update(m.unit, m.guid) end
        auraDirty = {}
        CS.Prune(ns.cast, ns.sched, now, valid, db)
    elseif not ns.rosterStale then
        for unit in pairs(auraDirty) do
            local guid = R.unitToGUID[unit]
            if guid then Au.Update(unit, guid) end
        end
        auraDirty = {}
        local valid = {}
        for g in pairs(R.members) do valid[g] = true end
        CS.Prune(ns.cast, ns.sched, now, valid, db)
    end

    -- Expire a click that never produced a cast.
    CS.ExpireAttempt(ns.cast, ns.sched, now, db)

    -- Decisions for EVERY member (Greater safety needs excluded members too).
    local ctx = buildCtx(now)
    local decisions = {}
    for guid, m in pairs(R.members) do
        local cov = Au.cache[guid] or { others = {}, unreadable = true }
        m.mine, m.others, m.unreadable, m.stale = cov.mine, cov.others or {}, cov.unreadable, cov.stale
        decisions[guid] = E.Decide(m, ctx)
        -- Pending confirmation: my fresh aura of the cast family is visible.
        local p = ns.sched.pending[guid]
        if p and m.mine and m.mine.family == p.family then
            local rem = m.mine.expirationTime and (m.mine.expirationTime - now)
            local full = m.mine.duration or B.FullDuration(p.family, m.mine.greater)
            if rem == nil or rem >= T.Effective(full, db).refresh then CS.OnAuraConfirmed(ns.sched, guid, p.family) end
        end
    end
    ns.decisions = decisions

    -- Rotation order with castability.
    local order, blocks = {}, {}
    for _, m in ipairs(R.order) do
        local d = decisions[m.guid]
        local entry = { guid = m.guid, castable = false }
        if d and d.status == "CAST" then
            local sp = ns.spells.known[d.family]
            if sp then
                entry.castable, entry.block = castability(m, sp.id)
            else
                entry.block = "UNCASTABLE"
            end
            blocks[m.guid] = entry.block
        end
        order[#order + 1] = entry
    end
    ns.order, ns.blocks = order, blocks

    -- Prepare the secure button (never in combat).
    if not inCombat then
        local sel, d, blocked = S.Select(order, decisions, ns.sched, now)
        ns.lastBlocked = blocked
        for _, b in ipairs(blocked) do blocks[b.guid] = b.code end
        local action
        if sel then
            local m = R.members[sel.guid]
            local sp = ns.spells.known[d.family]
            action = { guid = m.guid, unit = m.unit, family = d.family, spellID = sp.id, spellName = sp.name, greater = false }
            ns.greaterWhy = nil
            if db.greaterMode then
                local gsp = ns.spells.greaterKnown[d.family]
                local usable = {}
                if gsp then
                    local u, noMana = C.Usable(gsp.id)
                    usable[d.family] = not noMana and u ~= false
                end
                local res, why = G.Evaluate(sel.guid, R.members, decisions, {
                    settings = db, greaterKnown = ns.spells.greaterKnown, greaterUsable = usable,
                    reagents = C.ItemCount(B.SYMBOL_OF_KINGS),
                })
                if res and gsp and C.InRange(gsp.id, m.unit) ~= false then
                    action.greater, action.spellID, action.spellName = true, gsp.id, gsp.name
                    action.affected, action.affectedCount = res.affected, #res.affected
                else
                    ns.greaterWhy = why
                end
            end
            if not action.spellName then action = nil end
        end
        local ok = Pr.Apply(ns.mainButton, action, { inCombat = C.InCombat })
        if ok then ns.prepared = action end
        if ns.UI then ns.UI.PrepareRows() end
    end

    ns.UpdateAlert(now)
    if ns.UI then ns.UI.Update() end
end

---------------------------------------------------------------- summary / alerts
-- Shortest remaining among MY assigned maintenance blessings only.
function ns.Summary(now)
    local sum = { missing = {}, uncertain = 0, others = {} }
    for _, m in ipairs(R.order) do
        local d = ns.decisions[m.guid]
        if d then
            if d.status == "CAST" and d.castKind == "MISSING" then sum.missing[#sum.missing + 1] = m end
            if d.status == "UNKNOWN" or d.timerUnknown then sum.uncertain = sum.uncertain + 1 end
            if d.assignedCoverage and d.remaining then
                local rem = m.mine.expirationTime - now
                if not sum.shortest or rem < sum.shortest.remaining then
                    sum.shortest = { remaining = rem, member = m, family = d.family, eff = d.eff }
                end
            end
        end
    end
    if sum.shortest then
        local eff = sum.shortest.eff
        local lc = ns.cast.lastCast[sum.shortest.member.guid]
        local inGrace = lc and lc.family == sum.shortest.family and (now - lc.time) < ns.db.graceSeconds
        sum.warn = (not inGrace) and T.ShouldWarn(sum.shortest.remaining, eff)
    end
    if ns.db.showOthers then
        for _, m in pairs(R.members) do
            for fam, o in pairs(m.others or {}) do
                if o.casterKind ~= "unknown" and o.expirationTime then
                    local rem = o.expirationTime - now
                    if rem < ns.db.othersExpiringThreshold then
                        sum.others[#sum.others + 1] = { member = m, family = fam, by = o.casterName, remaining = rem }
                    end
                end
            end
        end
        table.sort(sum.others, function(a, b) return a.remaining < b.remaining end)
    end
    return sum
end

function ns.UpdateAlert(now)
    local sum = ns.Summary(now)
    ns.summary = sum
    local db, al = ns.db, ns.alert
    if sum.warn then
        if not al.active then
            al.active = true
            if now - al.last >= db.soundInterval then
                al.last = now
                if db.sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
                if db.chatAlerts then
                    ns.Print(L.REBUFF_SOON .. ": " .. ns.FamilyName(sum.shortest.family) .. " → " ..
                        sum.shortest.member.name .. " " .. ns.FormatTime(sum.shortest.remaining))
                end
            end
        end
    else
        al.active = false -- re-arms after rebuffing
    end
end

---------------------------------------------------------------- click + cast events
function ns.OnMainPreClick(button)
    if C.InCombat() then return end
    local a = ns.prepared
    if a and not Pr.Validate(a, C.UnitGUID(a.unit)) then
        ns.Debug("prepared target moved; re-preparing")
        ns.Refresh(true)
        a = ns.prepared
    end
    if a then CS.OnClick(ns.cast, a, GetTime()) end
end

ns.OnPlayerUnit("UNIT_SPELLCAST_SENT", function(_, _, _, castGUID, spellID)
    if C.IsSecret(castGUID) or C.IsSecret(spellID) then return end
    if CS.OnSent(ns.cast, spellID, castGUID, GetTime()) then ns.Debug("sent", spellID) end
end)

ns.OnPlayerUnit("UNIT_SPELLCAST_SUCCEEDED", function(_, _, castGUID)
    if C.IsSecret(castGUID) then return end
    local a = CS.OnSucceeded(ns.cast, ns.sched, castGUID, GetTime(), ns.db)
    if a then
        S.OnSuccess(ns.sched, a.guid, ns.order or {})
        ns.Debug("success", a.family, a.guid)
        ns.RequestRefresh()
        C_Timer.After(ns.db.pendingTimeout + 0.2, function() ns.RequestRefresh() end)
    end
end)

local function onFail(_, _, castGUID)
    if C.IsSecret(castGUID) then return end
    local a = CS.OnFailed(ns.cast, ns.sched, castGUID, GetTime(), ns.db)
    if a then ns.Debug("failed", a.family, a.guid) ns.RequestRefresh() end
end
ns.OnPlayerUnit("UNIT_SPELLCAST_FAILED", onFail)
ns.OnPlayerUnit("UNIT_SPELLCAST_FAILED_QUIET", onFail)
ns.OnPlayerUnit("UNIT_SPELLCAST_INTERRUPTED", onFail)

---------------------------------------------------------------- lifecycle
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    BuffOMaticDB = ns.Settings.Merge(BuffOMaticDB)
    ns.db = BuffOMaticDB
end)

ns.On("PLAYER_LOGIN", function()
    if not ns.db then
        BuffOMaticDB = ns.Settings.Merge(BuffOMaticDB)
        ns.db = BuffOMaticDB
    end
    local class = C.UnitClass("player")
    if class ~= "PALADIN" then
        ns.Print(L.NOT_PALADIN)
        return
    end
    if not C.IsForever() then ns.Print(string.format(L.UNTESTED_CLIENT, tostring(C.Interface()))) end
    ns.enabled = true
    ns.ScanSpells()
    ns.UI.Create()
    ns.Refresh(true)
    C_Timer.NewTicker(1, function() ns.Refresh(false) end)
end)

local function full() ns.RequestRefresh(true) end
ns.On("PLAYER_ENTERING_WORLD", full)
ns.On("GROUP_ROSTER_UPDATE", full)
ns.On("PLAYER_ROLES_ASSIGNED", full)
ns.On("UNIT_CONNECTION", full)
ns.On("PLAYER_REGEN_ENABLED", function()
    if ns.UI and ns.enabled then ns.UI.Layout() end
    full()
end)
ns.On("PLAYER_REGEN_DISABLED", function()
    -- The secure state driver clears the button in combat; this is the insecure mirror.
    if ns.enabled and not InCombatLockdown() then
        Pr.Apply(ns.mainButton, nil, { inCombat = C.InCombat })
    end
    ns.prepared = nil
    if ns.UI and ns.enabled then ns.UI.Update() end
end)
ns.On("SPELLS_CHANGED", function() if ns.enabled then ns.ScanSpells() ns.RequestRefresh() end end)
ns.On("BAG_UPDATE_DELAYED", function() if ns.enabled then ns.RequestRefresh() end end)
ns.On("UNIT_AURA", function(_, unit)
    if not ns.enabled or C.IsSecret(unit) then return end
    if R.unitToGUID[unit] then
        ns.MarkAuraDirty(unit)
        ns.RequestRefresh()
    end
end)
