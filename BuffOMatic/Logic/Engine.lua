-- Buff-o-Matic: pure blessing decision engine. No WoW API calls.
--
-- E.Decide(member, ctx) -> decision
--
-- member = {
--   guid, name, class, role ("TANK"|"HEALER"|"DAMAGER"|"NONE"),
--   mine = aura|nil,            -- MY blessing on them (one per paladin)
--   others = { [FAM] = aura },  -- blessings from other paladins / equivalent sources
--   unreadable = bool,          -- aura data restricted / secret
--   assigned = FAM|nil,         -- manual pinned assignment
--   priorityOverride = list|nil -- per-player ranked list
-- }
-- ctx = { now, settings, known = { [FAM]=true }, lastCast = { [guid] = {family,time} },
--         classRoleOverrides = table|nil }
--
-- decision = {
--   status = "CAST" | "HEALTHY" | "SKIP" | "UNKNOWN",
--   family, castKind = "MISSING"|"REFRESH"|"REPLACE", reason = {code=...},
--   skipped = { {family, code, by, remaining} }, remaining, warn, eff, timerUnknown,
--   assignedCoverage = bool  -- true when MY blessing is the intended one (counts for timers)
-- }
local _, ns = ...
local E = {}
ns.Engine = E
local B = ns.Blessings
local T = ns.Thresholds
local P = ns.Priorities
local A = ns.AuraModel

local function contains(list, v)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

-- automatic = true for engine-chosen blessings; manual pins may bypass the tank rule.
function E.IsUseful(family, member, automatic)
    local f = B.FAMILIES[family]
    if not f then return false, "UNKNOWN_FAMILY" end
    if f.maintenance == false then return false, "TACTICAL" end
    if f.requiresMana and not B.MANA_CLASSES[member.class or ""] then return false, "NO_MANA" end
    if f.threatReducing and member.role == "TANK" and automatic then return false, "TANK_THREAT" end
    return true
end

function E.RankedFamilies(member, ctx)
    if member.priorityOverride and #member.priorityOverride > 0 then
        local copy = {}
        for i = 1, #member.priorityOverride do copy[i] = member.priorityOverride[i] end
        return copy, "PLAYER_OVERRIDE"
    end
    return P.Resolve(member.class, member.role, ctx.classRoleOverrides)
end

function E.InGrace(guid, family, ctx)
    local lc = ctx.lastCast and ctx.lastCast[guid]
    return lc ~= nil and lc.family == family and (ctx.now - lc.time) < ctx.settings.graceSeconds
end

local function effFor(aura, family, s)
    local full = (aura and aura.duration) or B.FullDuration(family, aura and aura.greater)
    return T.Effective(full, s)
end

function E.Decide(member, ctx)
    local now, s = ctx.now, ctx.settings
    local d = { guid = member.guid, skipped = {} }

    -- Conservative: restricted aura data -> never guess.
    if member.unreadable then
        d.status, d.reason = "UNKNOWN", { code = "AURAS_UNREADABLE" }
        return d
    end
    local others = member.others or {}
    for fam, o in pairs(others) do
        if o.casterKind == "unknown" then
            d.status, d.reason = "UNKNOWN", { code = "CASTER_UNKNOWN", family = fam }
            return d
        end
    end

    local mine = member.mine
    local ranked, source = E.RankedFamilies(member, ctx)
    d.prioritySource = source

    -- Build candidates in priority order, recording why higher ones were skipped.
    local candidates = {}
    for _, fam in ipairs(ranked) do
        if B.FAMILIES[fam] then
            local ok, why = E.IsUseful(fam, member, true)
            if not ctx.known[fam] then
                d.skipped[#d.skipped + 1] = { family = fam, code = "NOT_KNOWN" }
            elseif not ok then
                d.skipped[#d.skipped + 1] = { family = fam, code = why }
            elseif others[fam] then
                local o = others[fam]
                local rem = A.Remaining(o, now)
                local expiring = rem ~= nil and rem < effFor(o, fam, s).refresh
                d.skipped[#d.skipped + 1] = {
                    family = fam, code = expiring and "SUPPLIED_BY_EXPIRING" or "SUPPLIED_BY",
                    by = o.casterName, external = o.external, remaining = rem,
                }
            else
                candidates[#candidates + 1] = fam
            end
        end
    end
    d.candidates = candidates

    local intended, code
    -- 1. Manual assignment (stable, never oscillates) unless another paladin covers it.
    if member.assigned then
        local a = member.assigned
        if B.FAMILIES[a] and ctx.known[a] and E.IsUseful(a, member, false) and not others[a] then
            intended, code = a, "ASSIGNED"
        else
            table.insert(d.skipped, 1, {
                family = a,
                code = others[a] and "ASSIGNED_SUPPLIED" or "ASSIGNED_UNAVAILABLE",
                by = others[a] and others[a].casterName,
            })
        end
    end

    -- 2. Sticky: keep my existing useful blessing while it is healthy. This is what stops
    --    me from swapping families when another paladin's buff expires or reappears.
    if not intended and s.sticky and mine and contains(candidates, mine.family) then
        local rem = A.Remaining(mine, now)
        local due = rem ~= nil and rem < effFor(mine, mine.family, s).refresh
            and not E.InGrace(member.guid, mine.family, ctx)
        if not due then intended, code = mine.family, "KEEP_CURRENT" end
    end

    -- 3. Best remaining candidate.
    if not intended and #candidates > 0 then
        intended = candidates[1]
        code = "BEST"
        for _, sk in ipairs(d.skipped) do
            if sk.code == "SUPPLIED_BY" or sk.code == "SUPPLIED_BY_EXPIRING" then code = "FALLBACK" break end
        end
    end

    if not intended then
        d.status, d.reason = "SKIP", { code = "NO_CANDIDATE" }
        if mine then d.mine = mine end
        return d
    end

    d.family = intended
    d.reason = { code = code }

    if mine and mine.family == intended then
        local eff = effFor(mine, intended, s)
        d.eff, d.assignedCoverage = eff, true
        local rem = A.Remaining(mine, now)
        if rem == nil then
            -- Unknown remaining time: neither "missing" nor "infinite". Do not cast.
            d.status, d.timerUnknown = "HEALTHY", true
            return d
        end
        d.remaining = rem
        if E.InGrace(member.guid, intended, ctx) then
            d.status, d.warn = "HEALTHY", false
            return d
        end
        d.warn = T.ShouldWarn(rem, eff)
        if T.NeedsRefresh(rem, eff) then
            d.status, d.castKind = "CAST", "REFRESH"
        else
            d.status = "HEALTHY"
        end
        return d
    end

    d.eff = T.Effective(B.FullDuration(intended, false), s)
    if mine then
        -- My single blessing slot holds another family; casting replaces my own buff only.
        if E.InGrace(member.guid, mine.family, ctx) then
            d.status, d.reason = "HEALTHY", { code = "RECENTLY_CAST" }
            d.mine = mine
            return d
        end
        d.status, d.castKind, d.replaces = "CAST", "REPLACE", mine.family
        return d
    end
    d.status, d.castKind = "CAST", "MISSING"
    return d
end
