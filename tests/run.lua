-- Buff-o-Matic offline test suite for the pure decision / scheduler logic.
-- Runs under any Lua 5.1 (WoW's Lua version):   lua tests/run.lua
-- or via the bundled Python runner (embedded Lua 5.1):   python tests/run_tests.py
-- Optional global ROOT = path to repo root (default ".").

local ROOT = ROOT or "."
local ADDON = ROOT .. "/BuffOMatic/"
local ns = {}

local function load(rel)
    local f, err = loadfile(ADDON .. rel)
    if not f then error(err) end
    f("BuffOMatic", ns)
end
load("Data/Blessings.lua")
load("Data/Priorities.lua")
load("Settings.lua")
load("Logic/Thresholds.lua")
load("Logic/AuraModel.lua")
load("Logic/Engine.lua")
load("Logic/Scheduler.lua")
load("Logic/CastState.lua")
load("Logic/Greater.lua")
load("Logic/Prepare.lua")

local E, S, C, G, Pr, T, A, B = ns.Engine, ns.Scheduler, ns.CastState, ns.Greater, ns.Prepare, ns.Thresholds, ns.AuraModel, ns.Blessings

---------------------------------------------------------------- framework
local passed, failed, failures = 0, 0, {}
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else
        failed = failed + 1
        failures[#failures + 1] = name .. "\n      " .. tostring(err)
    end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function ok(v, msg) if not v then error(msg or "expected truthy", 2) end end

---------------------------------------------------------------- helpers
local NOW = 10000
local function settings(over)
    local s = ns.Settings.Fresh()
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end
local function ctx(over)
    local c = { now = NOW, settings = settings(), known = { KINGS = true, MIGHT = true, WISDOM = true }, lastCast = {} }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end
local function aura(fam, rem, kind, name, extra)
    local a = { family = fam, casterKind = kind or "me", casterName = name,
        expirationTime = rem and (NOW + rem) or nil, duration = 3600, rank = 1, greater = false }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
local function member(guid, class, role, extra)
    local m = { guid = guid, name = guid, class = class, role = role or "NONE", others = {} }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end
local function hasSkip(d, fam, code)
    for _, s in ipairs(d.skipped) do if s.family == fam and (not code or s.code == code) then return s end end
    return nil
end

---------------------------------------------------------------- 1-4 selection
test("01 best blessing missing -> choose it", function()
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER"), ctx())
    eq(d.status, "CAST"); eq(d.family, "MIGHT"); eq(d.castKind, "MISSING"); eq(d.reason.code, "BEST")
end)

test("02 best supplied by another paladin -> second best", function()
    local m = member("W", "WARRIOR", "DAMAGER", { others = { MIGHT = aura("MIGHT", 3000, "other", "Uther") } })
    local d = E.Decide(m, ctx())
    eq(d.family, "KINGS"); eq(d.reason.code, "FALLBACK")
    local sk = hasSkip(d, "MIGHT", "SUPPLIED_BY"); ok(sk, "skip reason recorded"); eq(sk.by, "Uther")
end)

test("03 best and second supplied -> third best", function()
    local m = member("P", "PALADIN", "DAMAGER", { others = {
        MIGHT = aura("MIGHT", 3000, "other", "Uther"), KINGS = aura("KINGS", 3000, "other", "Tirion") } })
    local d = E.Decide(m, ctx())
    eq(d.status, "CAST"); eq(d.family, "WISDOM")
end)

test("04 every useful family supplied -> skip", function()
    local m = member("R", "ROGUE", "DAMAGER", { others = {
        MIGHT = aura("MIGHT", 3000, "other", "A"), KINGS = aura("KINGS", 3000, "other", "B") } })
    local d = E.Decide(m, ctx())
    eq(d.status, "SKIP"); eq(d.reason.code, "NO_CANDIDATE")
    -- Wisdom is never a candidate for a rogue (no mana), even though nobody supplies it.
    ok(not hasSkip(d, "WISDOM") or hasSkip(d, "WISDOM", "NO_MANA"))
end)

---------------------------------------------------------------- 5-8 thresholds
test("05 my blessing at 9:59 -> refresh eligible", function()
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 599) }), ctx())
    eq(d.status, "CAST"); eq(d.castKind, "REFRESH"); eq(d.family, "MIGHT")
end)

test("06 my blessing at 10:00 -> not eligible", function()
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 600) }), ctx())
    eq(d.status, "HEALTHY")
end)

test("07 my blessing at 4:59 -> warning", function()
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 299) }), ctx())
    eq(d.warn, true)
end)

test("08 my blessing at 5:00 -> no under-five warning", function()
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 300) }), ctx())
    eq(d.warn, false)
    eq(T.ShouldWarn(300, T.Effective(3600, settings())), false)
    eq(T.NeedsRefresh(600, T.Effective(3600, settings())), false)
    eq(T.NeedsRefresh(599.9, T.Effective(3600, settings())), true)
end)

---------------------------------------------------------------- 9 short duration
test("09 short-duration blessings: no rebuff loop, no immediate warning", function()
    local s = settings()
    local eff = T.Effective(300, s)          -- a 5-minute blessing
    eq(eff.short, true); eq(eff.refresh, 60); eq(eff.warn, 30)
    local eff10 = T.Effective(600, s)        -- exactly 10 minutes -> short policy too
    eq(eff10.short, true); eq(eff10.refresh, 120)
    eq(T.Effective(3600, s).short, false)    -- Forever's real 60-minute blessings
    -- freshly applied 5-minute buff: healthy, no warning
    local fresh = aura("MIGHT", 300, "me", nil, { duration = 300 })
    local d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = fresh }), ctx())
    eq(d.status, "HEALTHY"); eq(d.warn, false)
    -- below 20% -> refresh, below 10% -> warn
    d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 59, "me", nil, { duration = 300 }) }), ctx())
    eq(d.status, "CAST")
    eq(d.warn, false)
    d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 29, "me", nil, { duration = 300 }) }), ctx())
    eq(d.warn, true)
    -- grace period: stale/odd short timer right after a successful cast is not refreshed
    local c = ctx({ lastCast = { W = { family = "MIGHT", time = NOW - 5 } } })
    d = E.Decide(member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", 10, "me", nil, { duration = 300 }) }), c)
    eq(d.status, "HEALTHY"); eq(d.warn, false)
end)

---------------------------------------------------------------- 10-11 other paladins
test("10 another paladin's expiring blessing is not overwritten", function()
    local m = member("W", "WARRIOR", "DAMAGER", { others = { MIGHT = aura("MIGHT", 120, "other", "Uther") } })
    local d = E.Decide(m, ctx())
    ok(d.family ~= "MIGHT", "must not take over Might"); eq(d.family, "KINGS")
    ok(hasSkip(d, "MIGHT", "SUPPLIED_BY_EXPIRING"), "expiring flagged")
end)

test("11 healthy fallback not refreshed because other's buff is expiring", function()
    local m = member("W", "WARRIOR", "DAMAGER", {
        mine = aura("KINGS", 3000), others = { MIGHT = aura("MIGHT", 100, "other", "Uther") } })
    local d = E.Decide(m, ctx())
    eq(d.status, "HEALTHY"); eq(d.family, "KINGS")
    -- and if the other paladin's Might disappears entirely, my healthy Kings is still kept (sticky)
    m.others = {}
    d = E.Decide(m, ctx())
    eq(d.status, "HEALTHY"); eq(d.family, "KINGS"); eq(d.reason.code, "KEEP_CURRENT")
end)

---------------------------------------------------------------- 12-13 roles
test("12 tank never receives automatic threat reduction", function()
    B.FAMILIES.TESTSALV = { single = { 999001 }, greater = {}, threatReducing = true, maintenance = true }
    B.Reindex()
    local c = ctx(); c.known.TESTSALV = true
    local tank = member("T", "WARRIOR", "TANK", { priorityOverride = { "TESTSALV", "KINGS" } })
    local d = E.Decide(tank, c)
    eq(d.family, "KINGS"); ok(hasSkip(d, "TESTSALV", "TANK_THREAT"))
    local dps = member("D", "WARRIOR", "DAMAGER", { priorityOverride = { "TESTSALV", "KINGS" } })
    eq(E.Decide(dps, c).family, "TESTSALV")
    B.FAMILIES.TESTSALV = nil; B.byID[999001] = nil
    -- no shipped default for any class lists a threat-reducing family
    for class, roles in pairs(ns.Priorities.DEFAULTS) do
        for role, list in pairs(roles) do
            for _, fam in ipairs(list) do ok(B.FAMILIES[fam] and not B.FAMILIES[fam].threatReducing, class .. role) end
        end
    end
end)

test("13 unknown role uses safe default and supports manual correction", function()
    local m = member("W", "WARRIOR", "NONE")
    eq(E.Decide(m, ctx()).family, "KINGS")        -- not assumed tank or dps
    m.role = "DAMAGER"                            -- manual role override applied by Roster
    eq(E.Decide(m, ctx()).family, "MIGHT")
    m.assigned = "KINGS"                          -- manual pin
    local d = E.Decide(m, ctx()); eq(d.family, "KINGS"); eq(d.reason.code, "ASSIGNED")
    m.assigned = nil; m.priorityOverride = { "KINGS", "MIGHT" }
    d = E.Decide(m, ctx()); eq(d.family, "KINGS"); eq(d.prioritySource, "PLAYER_OVERRIDE")
    -- class/role override table
    local c = ctx({ classRoleOverrides = { WARRIOR = { DAMAGER = { "KINGS" } } } })
    m.priorityOverride = nil
    eq(E.Decide(m, c).family, "KINGS")
    -- mana blessing filtered for non-mana class even when listed
    m.priorityOverride = { "WISDOM", "MIGHT" }
    d = E.Decide(m, ctx()); eq(d.family, "MIGHT"); ok(hasSkip(d, "WISDOM", "NO_MANA"))
end)

---------------------------------------------------------------- 14-17 casting / scheduling
local function castAll(guids)
    local dec = {}
    for _, g in ipairs(guids) do dec[g] = { status = "CAST", family = "KINGS" } end
    return dec
end
local function order(guids, uncastable)
    local o = {}
    for _, g in ipairs(guids) do
        o[#o + 1] = { guid = g, castable = not (uncastable and uncastable[g]), block = uncastable and uncastable[g] }
    end
    return o
end

test("14 failed cast does not advance the cursor", function()
    local sched, cs, s = S.NewState(), C.New(), settings()
    local o, dec = order({ "A", "B" }), castAll({ "A", "B" })
    local m = S.Select(o, dec, sched, NOW); eq(m.guid, "A")
    C.OnClick(cs, { guid = "A", family = "KINGS" }, NOW)
    ok(C.OnSent(cs, 20217, "cast-1", NOW))
    C.OnFailed(cs, sched, "cast-1", NOW, s)
    eq(sched.cursorGUID, nil)
    eq(S.Select(o, dec, sched, NOW).guid, "A", "still A after one failure")
    -- button press alone (no SENT) is not a success either
    C.OnClick(cs, { guid = "A", family = "KINGS" }, NOW)
    C.ExpireAttempt(cs, sched, NOW + 2, s)
    eq(sched.cursorGUID, nil)
    ok(sched.backoff.A, "second failure -> backoff")
    eq(S.Select(o, dec, sched, NOW + 2).guid, "B")
    -- interrupted cast (reported via OnFailed) behaves the same; success advances
    C.OnClick(cs, { guid = "B", family = "KINGS" }, NOW + 3)
    C.OnSent(cs, 20217, "cast-2", NOW + 3)
    local a = C.OnSucceeded(cs, sched, "cast-2", NOW + 3, s)
    ok(a); S.OnSuccess(sched, a.guid, o); eq(sched.cursorGUID, "B")
end)

test("15 unreachable members do not block everyone else", function()
    local sched = S.NewState()
    local guids = { "A", "B", "C" }
    local o = order(guids, { A = "OUT_OF_RANGE", B = "DEAD" })
    local m, _, blocked = S.Select(o, castAll(guids), sched, NOW)
    eq(m.guid, "C"); eq(#blocked, 2)
    -- everyone unreachable -> nil, bounded (single pass)
    o = order(guids, { A = "OUT_OF_RANGE", B = "DEAD", C = "OFFLINE" })
    m, _, blocked = S.Select(o, castAll(guids), sched, NOW)
    eq(m, nil); eq(#blocked, 3)
    -- backoff expires -> member becomes eligible again, fair order retained
    sched.backoff.A = NOW + 5
    o = order(guids)
    eq(S.Select(o, castAll(guids), sched, NOW).guid, "B")
    eq(S.Select(o, castAll(guids), sched, NOW + 6).guid, "A")
end)

test("16 party-slot changes never retarget a queued action to the wrong GUID", function()
    local action = { guid = "Player-1-AAA", unit = "party2", family = "KINGS", spellName = "Blessing of Kings" }
    ok(Pr.Validate(action, "Player-1-AAA"))
    ok(not Pr.Validate(action, "Player-1-BBB"), "slot now holds someone else")
    ok(not Pr.Validate(action, nil), "slot empty")
    -- cursor follows GUID, not slot: after a reorder, the next member is still the one after the last buffed GUID
    local sched = S.NewState()
    S.OnSuccess(sched, "B", order({ "A", "B", "C" }))
    local reordered = order({ "C", "B", "A" })
    eq(S.Select(reordered, castAll({ "A", "B", "C" }), sched, NOW).guid, "A")
    -- cursor member left the group: resume at its old position
    local left = order({ "A", "C", "D" })
    eq(S.Select(left, castAll({ "A", "C", "D" }), sched, NOW).guid, "D")
end)

test("17 aura propagation delay does not cause duplicate casts", function()
    local sched, cs, s = S.NewState(), C.New(), settings()
    local o, dec = order({ "A", "B" }), castAll({ "A", "B" })
    C.OnClick(cs, { guid = "A", family = "KINGS" }, NOW)
    C.OnSent(cs, 20217, "c1", NOW)
    local a = C.OnSucceeded(cs, sched, "c1", NOW, s)
    S.OnSuccess(sched, a.guid, o)
    -- aura not visible yet: A still decides CAST, but is pending -> B chosen, never A
    local sel = S.Select(o, dec, sched, NOW + 0.5); eq(sel.guid, "B")
    sched.cursorGUID = "B" -- even if the cursor wraps right back to A
    sel = S.Select(o, dec, sched, NOW + 0.5); eq(sel.guid, "B", "A pending -> skipped")
    -- aura confirmation clears pending
    ok(C.OnAuraConfirmed(sched, "A", "KINGS")); eq(sched.pending.A, nil)
    -- timeout path: prune after pendingTimeout reconciles
    sched.pending.B = { family = "KINGS", untilTime = NOW + 3 }
    C.Prune(cs, sched, NOW + 4, { A = true, B = true }, s); eq(sched.pending.B, nil)
    -- group change while pending: GUID left -> dropped
    sched.pending.A = { family = "KINGS", untilTime = NOW + 100 }
    C.Prune(cs, sched, NOW + 4, { B = true }, s); eq(sched.pending.A, nil)
    -- stale aura data within grace (old short timer) does not re-trigger a refresh
    local c = ctx({ lastCast = { A = { family = "KINGS", time = NOW - 1 } } })
    local d = E.Decide(member("A", "MAGE", "NONE", { mine = aura("KINGS", 5) }), c)
    eq(d.status, "HEALTHY")
end)

---------------------------------------------------------------- 18-19 greater
test("18 normal and Greater equivalents are one family (no duplicate coverage)", function()
    eq(B.FamilyOf(25916), "MIGHT"); eq(B.FamilyOf(25291), "MIGHT")
    eq(B.FamilyOf(25898), "KINGS"); eq(B.FamilyOf(25918), "WISDOM")
    local cov = A.Build({
        { spellId = 25916, casterKind = "other", casterName = "Uther", expirationTime = NOW + 3000, duration = 3600 },
        { spellId = 25898, casterKind = "me", expirationTime = NOW + 3000, duration = 3600 },
    })
    ok(cov.others.MIGHT and cov.others.MIGHT.greater); eq(cov.mine.family, "KINGS")
    local m = member("W", "WARRIOR", "DAMAGER", { mine = cov.mine, others = cov.others })
    local d = E.Decide(m, ctx())
    eq(d.status, "HEALTHY"); eq(d.family, "KINGS")
    -- Greater Might from another paladin blocks my single Might
    m.mine = nil
    eq(E.Decide(m, ctx()).family, "KINGS")
    -- unknown aura spell ids are ignored, unreadable ones flagged
    eq(A.Build({ { spellId = 12345, casterKind = "other" } }).others.MIGHT, nil)
    eq(A.Build({ { unreadable = true } }).unreadable, true)
end)

test("19 Greater Blessing side effects cannot overwrite protected assignments", function()
    local s = settings({ greaterMode = true })
    local gctx = { settings = s, greaterKnown = { MIGHT = true, KINGS = true }, reagents = 5 }
    local members = {
        W1 = member("W1", "WARRIOR", "DAMAGER"),
        W2 = member("W2", "WARRIOR", "DAMAGER"),
        M1 = member("M1", "MAGE", "NONE"),
    }
    local function decideAll()
        local out = {}
        for g, m in pairs(members) do out[g] = E.Decide(m, ctx()) end
        return out
    end
    local res = G.Evaluate("W1", members, decideAll(), gctx)
    ok(res, "all clear -> greater offered"); eq(res.family, "MIGHT"); eq(#res.affected, 2)
    -- protected manual assignment on another warrior
    members.W2.assigned = "KINGS"
    local r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(r, nil); eq(why, "PROTECTED_ASSIGNMENT")
    members.W2.assigned = nil
    -- another paladin's Might on W2 -> would overwrite
    members.W2.others = { MIGHT = aura("MIGHT", 3000, "other", "Uther") }
    r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(r, nil)
    ok(why == "WOULD_OVERWRITE_OTHER" or why == "MIXED_INTENT")
    members.W2.others = {}
    -- mixed roles: tank warrior intends Kings -> refuse
    members.W2.role = "TANK"
    r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(r, nil); eq(why, "MIXED_INTENT")
    members.W2.role = "DAMAGER"
    -- no reagent / disabled / excluded self
    gctx.reagents = 0; r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(why, "NO_REAGENT"); gctx.reagents = 5
    members.W2.excluded = true; r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(why, "AFFECTS_EXCLUDED")
    members.W2.excluded = nil
    s.greaterMode = false; r, why = G.Evaluate("W1", members, decideAll(), gctx); eq(why, "DISABLED")
end)

---------------------------------------------------------------- 20 combat
test("20 combat lockdown never causes protected attribute changes", function()
    local calls = 0
    local button = { SetAttribute = function() calls = calls + 1 end }
    local action = { guid = "A", unit = "party1", spellName = "Blessing of Kings" }
    local okApply, why = Pr.Apply(button, action, { inCombat = function() return true end })
    eq(okApply, false); eq(why, "COMBAT"); eq(calls, 0)
    okApply = Pr.Apply(button, nil, { inCombat = function() return true end })
    eq(okApply, false); eq(calls, 0)
    okApply = Pr.Apply(button, action, { inCombat = function() return false end })
    eq(okApply, true); eq(calls, 3)
end)

---------------------------------------------------------------- 21 uncertainty
test("21 unknown caster or remaining time -> conservative", function()
    local m = member("W", "WARRIOR", "DAMAGER", { others = { KINGS = aura("KINGS", 3000, "unknown") } })
    local d = E.Decide(m, ctx()); eq(d.status, "UNKNOWN"); eq(d.reason.code, "CASTER_UNKNOWN")
    m = member("W", "WARRIOR", "DAMAGER", { mine = aura("MIGHT", nil) })
    d = E.Decide(m, ctx()); eq(d.status, "HEALTHY"); eq(d.timerUnknown, true)
    m = member("W", "WARRIOR", "DAMAGER", { unreadable = true })
    d = E.Decide(m, ctx()); eq(d.status, "UNKNOWN")
    -- unknown caster is never hidden behind a known caster of the same family
    local cov = A.Build({
        { spellId = 20217, casterKind = "other", casterName = "X", expirationTime = NOW + 9, duration = 3600 },
        { spellId = 20217, casterKind = "unknown", expirationTime = NOW + 3000, duration = 3600 },
    })
    eq(cov.others.KINGS.casterKind, "unknown")
end)

---------------------------------------------------------------- 22 fairness
test("22 repeated clicks cycle fairly across eligible members", function()
    local sched, cs, s = S.NewState(), C.New(), settings()
    local guids = { "A", "B", "C", "D" }
    local o = order(guids)
    local seq = {}
    local t = NOW
    for i = 1, 8 do
        local dec = castAll(guids)           -- everyone keeps needing (worst case)
        sched.pending = {}                   -- ignore pending to test pure rotation
        local m = S.Select(o, dec, sched, t)
        C.OnClick(cs, { guid = m.guid, family = "KINGS" }, t)
        C.OnSent(cs, 20217, "c" .. i, t)
        local a = C.OnSucceeded(cs, sched, "c" .. i, t, s)
        S.OnSuccess(sched, a.guid, o)
        seq[#seq + 1] = m.guid
        t = t + 2
    end
    eq(table.concat(seq, ","), "A,B,C,D,A,B,C,D")
    -- the top-priority (first) player is not picked repeatedly when others still need
    sched = S.NewState(); S.OnSuccess(sched, "A", o)
    eq(S.Select(o, castAll(guids), sched, t).guid, "B")
    -- healthy members are skipped
    local dec = castAll(guids); dec.B = { status = "HEALTHY" }; dec.C = { status = "HEALTHY" }
    eq(S.Select(o, dec, sched, t).guid, "D")
    -- nobody needs -> nil ("Party buffed")
    local none = { A = { status = "HEALTHY" }, B = { status = "SKIP" }, C = { status = "HEALTHY" }, D = { status = "HEALTHY" } }
    eq(S.Select(o, none, sched, t), nil)
end)

---------------------------------------------------------------- extras
test("X1 my blessing replaced only when it is mine and not useful", function()
    -- user changes a mage's pin from Kings to Wisdom: replace my own Kings
    local m = member("M", "MAGE", "NONE", { mine = aura("KINGS", 3000), assigned = "WISDOM" })
    local d = E.Decide(m, ctx()); eq(d.status, "CAST"); eq(d.castKind, "REPLACE"); eq(d.replaces, "KINGS")
    -- but not within grace of my own cast
    local c = ctx({ lastCast = { M = { family = "KINGS", time = NOW - 2 } } })
    eq(E.Decide(m, c).status, "HEALTHY")
end)

test("X2 unknown spells: only known families selected", function()
    local c = ctx({ known = { MIGHT = true } })    -- low-level paladin: no Kings/Wisdom yet
    local d = E.Decide(member("M", "MAGE", "NONE"), c)
    eq(d.status, "SKIP"); ok(hasSkip(d, "KINGS", "NOT_KNOWN"))
    eq(E.Decide(member("W", "WARRIOR", "NONE"), c).family, "MIGHT")
end)

test("X3 settings merge is non-destructive", function()
    local db = ns.Settings.Merge({ refreshThreshold = 900, players = { Bob = { assigned = "KINGS" } } })
    eq(db.refreshThreshold, 900); eq(db.warnThreshold, 300); eq(db.players.Bob.assigned, "KINGS")
end)

---------------------------------------------------------------- report
print(string.format("Buff-o-Matic tests: %d passed, %d failed", passed, failed))
for _, f in ipairs(failures) do print("  FAIL " .. f) end
if failed > 0 then error("tests failed") end
