-- Buff-o-Matic integration smoke test: loads every file listed in the .toc inside a mocked
-- WoW API, then simulates a party session (login, clicks, secure casts, aura events, combat
-- lockdown, slot reorder, range failures). Mock fidelity is limited: it proves the addon's
-- own Lua runs and behaves as designed, NOT that the real client APIs behave like the mock.
local ROOT = ROOT or "."
local ADDON_DIR = ROOT .. "/BuffOMatic/"

---------------------------------------------------------------- world state
local clock = 1000
local inCombat = false
local errors, printed = {}, {}
local world = {
    units = {},          -- [token] = { guid, name, class, role, connected, dead, inRange, auras = {} }
    known = {},          -- [spellID] = true
    reagents = 0,
}
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local SPELL_NAMES = {
    [20217] = "Blessing of Kings", [25898] = "Greater Blessing of Kings",
    [25291] = "Blessing of Might", [25916] = "Greater Blessing of Might",
    [25290] = "Blessing of Wisdom", [25918] = "Greater Blessing of Wisdom",
}
for _, id in ipairs({ 19740, 19834, 19835, 19836, 19837, 19838 }) do SPELL_NAMES[id] = "Blessing of Might" end
for _, id in ipairs({ 19742, 19850, 19852, 19853, 19854 }) do SPELL_NAMES[id] = "Blessing of Wisdom" end
local NAME_TO_ID = { ["Blessing of Kings"] = 20217, ["Blessing of Might"] = 25291, ["Blessing of Wisdom"] = 25290,
    ["Greater Blessing of Kings"] = 25898, ["Greater Blessing of Might"] = 25916, ["Greater Blessing of Wisdom"] = 25918 }

---------------------------------------------------------------- frames
local eventFrames = {}    -- [event] = { frame, ... }
local unitEventFrames = {}
local namedFrames = {}
local timers = {}

local function noop() end
local FrameMT = {}
FrameMT.__index = function(t, k)
    local v = rawget(FrameMT, k)
    if v then return v end
    return noop
end
function FrameMT:SetScript(name, fn) self.scripts[name] = fn end
function FrameMT:GetScript(name) return self.scripts[name] end
function FrameMT:RegisterEvent(e)
    eventFrames[e] = eventFrames[e] or {}
    table.insert(eventFrames[e], self)
end
function FrameMT:RegisterUnitEvent(e)
    unitEventFrames[e] = unitEventFrames[e] or {}
    table.insert(unitEventFrames[e], self)
end
function FrameMT:SetAttribute(k, v)
    if self.secure and inCombat and not self.inSnippet then
        error("ADDON_ACTION_BLOCKED: SetAttribute(" .. tostring(k) .. ") on protected frame in combat")
    end
    self.attrs[k] = v
end
function FrameMT:GetAttribute(k) return self.attrs[k] end
function FrameMT:Show() self.shown = true end
function FrameMT:Hide() self.shown = false end
function FrameMT:SetShown(v) self.shown = v and true or false end
function FrameMT:IsShown() return self.shown end
function FrameMT:SetText(t) self.text = t end
function FrameMT:GetText() return self.text end
function FrameMT:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
local function newFrame(name, template)
    local f = setmetatable({ scripts = {}, attrs = {}, shown = true, name = name,
        secure = template and template:find("Secure") ~= nil }, FrameMT)
    if name then namedFrames[name] = f; _G[name] = f end
    return f
end
function FrameMT:CreateTexture() return newFrame() end
function FrameMT:CreateFontString() return newFrame() end

CreateFrame = function(_, name, _, template) return newFrame(name, template) end
UIParent = newFrame("UIParent")
GameTooltip = newFrame("GameTooltip")

local stateDrivers = {}
RegisterStateDriver = function(frame, state, cond) stateDrivers[#stateDrivers + 1] = { frame = frame, state = state } end

local function fire(event, ...)
    for _, f in ipairs(eventFrames[event] or {}) do
        local fn = f.scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end
local function fireUnit(event, ...)
    for _, f in ipairs(unitEventFrames[event] or {}) do
        local fn = f.scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

C_Timer = {
    After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end,
    NewTicker = function(d, fn) local t = { at = clock + d, fn = fn, every = d }; timers[#timers + 1] = t; return t end,
}
local function advance(sec)
    local target = clock + sec
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = timers[1]
        if not t or t.at > target then break end
        clock = t.at
        table.remove(timers, 1)
        if t.every then t.at = clock + t.every; timers[#timers + 1] = t end
        t.fn()
    end
    clock = target
end

---------------------------------------------------------------- API mocks
GetTime = function() return clock end
GetBuildInfo = function() return "1.60.1", "71037", "Nov 2026", 16001 end
WOW_PROJECT_ID = 18
WOW_PROJECT_CAMELOT = 18
InCombatLockdown = function() return inCombat end
issecretvalue = function(v) return v == SECRET end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local line = table.concat(parts, " ")
    printed[#printed + 1] = line
    if line:find("error") then errors[#errors + 1] = line end
end
PlaySound = function() world.sounds = (world.sounds or 0) + 1 end
SOUNDKIT = { RAID_WARNING = 8959 }
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
SlashCmdList = {}

local function U(unit) return world.units[unit] end
UnitGUID = function(unit) local u = U(unit) return u and u.guid end
UnitName = function(unit)
    local u = U(unit)
    if not u then return nil end
    local first, last = u.name:match("^(%S+) (%S+)$")   -- Forever returns surname as 2nd value
    if first then return first, last end
    return u.name, nil
end
UnitClass = function(unit) local u = U(unit) return u and u.class, u and u.class end
UnitIsUnit = function(a, b)
    local ua, ub = U(a), U(b)
    return ua ~= nil and ub ~= nil and ua.guid == ub.guid
end
UnitExists = function(unit) return U(unit) ~= nil end
UnitIsPlayer = function(unit) return U(unit) ~= nil end
UnitIsConnected = function(unit) local u = U(unit) return u and u.connected ~= false end
UnitIsDeadOrGhost = function(unit) local u = U(unit) return u and u.dead or false end
UnitIsVisible = function(unit) return U(unit) ~= nil end
UnitGroupRolesAssigned = function(unit) local u = U(unit) return u and u.role or "NONE" end
IsInRaid = function() return false end
GetNumSubgroupMembers = function()
    local n = 0
    for i = 1, 4 do if world.units["party" .. i] then n = i end end
    return n
end
GetNumGroupMembers = function() return GetNumSubgroupMembers() + 1 end
IsPlayerSpell = function(id) return world.known[id] == true end

C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i, filter)
        local u = U(unit)
        if not u then return nil end
        if u.secretAuras then return SECRET end
        local a = u.auras[i]
        if not a then return nil end
        return { spellId = a.spellId, sourceUnit = a.sourceUnit, expirationTime = a.expirationTime,
            duration = a.duration, isFromPlayerOrPlayerPet = a.sourceUnit == "player" }
    end,
}
C_Spell = {
    GetSpellName = function(id) return SPELL_NAMES[id] end,
    GetSpellTexture = function() return 135995 end,
    IsSpellInRange = function(_, unit) local u = U(unit) if not u then return nil end return u.inRange ~= false end,
    IsSpellUsable = function(id) return world.known[id] == true, world.oom == true end,
}
C_Item = { GetItemCount = function() return world.reagents end }

---------------------------------------------------------------- casting simulation
local castSeq = 0
local function applyAura(unit, spellId, delay)
    local function doIt()
        local u = U(unit)
        local fam = nil
        -- remove my existing blessing (one per paladin) and same-family buffs
        local keep = {}
        for _, a in ipairs(u.auras) do
            local sameCasterBlessing = a.sourceUnit == "player"
            if not sameCasterBlessing then keep[#keep + 1] = a end
        end
        keep[#keep + 1] = { spellId = spellId, sourceUnit = "player", expirationTime = clock + 3600, duration = 3600 }
        u.auras = keep
        fire("UNIT_AURA", unit, {})
    end
    if delay and delay > 0 then C_Timer.After(delay, doIt) else doIt() end
end

-- Simulates the secure handler: PreClick, then the attributes decide the cast.
local function click(button, opts)
    opts = opts or {}
    local pre = button.scripts.PreClick
    if pre then pre(button, "LeftButton", false) end
    local t, spell, unit = button.attrs.type, button.attrs.spell, button.attrs.unit
    world.lastCast = nil
    if t ~= "spell" or not spell or not unit then return "noaction" end
    local id = NAME_TO_ID[spell]
    castSeq = castSeq + 1
    local castGUID = "Cast-" .. castSeq
    local u = U(unit)
    if not u or u.inRange == false or world.oom then
        fireUnit("UNIT_SPELLCAST_FAILED", "player", castGUID, id)
        return "failed"
    end
    fireUnit("UNIT_SPELLCAST_SENT", "player", u.name, castGUID, id)
    if opts.interrupt then
        fireUnit("UNIT_SPELLCAST_INTERRUPTED", "player", castGUID, id)
        return "interrupted"
    end
    fireUnit("UNIT_SPELLCAST_SUCCEEDED", "player", castGUID, id)
    world.lastCast = { unit = unit, name = u.name, spell = spell }
    applyAura(unit, id, opts.auraDelay)
    return "cast", u.name, spell
end

local function enterCombat()
    fire("PLAYER_REGEN_DISABLED")
    inCombat = true
    for _, sd in ipairs(stateDrivers) do   -- emulate the secure _onstate snippet
        sd.frame.inSnippet = true
        sd.frame:SetAttribute("type", nil); sd.frame:SetAttribute("spell", nil); sd.frame:SetAttribute("unit", nil)
        sd.frame.inSnippet = false
    end
end
local function leaveCombat()
    inCombat = false
    fire("PLAYER_REGEN_ENABLED")
end

---------------------------------------------------------------- load addon
local ns = {}
local toc = io.open(ADDON_DIR .. "BuffOMatic.toc"):read("*a")
for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%.lua$") then
        local path = ADDON_DIR .. line:gsub("\\", "/")
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        chunk("BuffOMatic", ns)
    end
end

---------------------------------------------------------------- assertions
local checks, failures = 0, {}
local function check(cond, msg)
    checks = checks + 1
    if not cond then failures[#failures + 1] = msg end
end

---------------------------------------------------------------- scenario
for _, id in ipairs({ 20217, 19740, 19834, 19835, 19836, 19837, 19838, 25291, 19742, 19850, 19852, 19853, 19854, 25290 }) do
    world.known[id] = true
end
world.units.player = { guid = "Player-1-0001", name = "Lumen Brightforge", class = "PALADIN", role = "NONE", auras = {} }
world.units.party1 = { guid = "Player-1-0002", name = "Brann Ironwall", class = "WARRIOR", role = "TANK", auras = {} }
world.units.party2 = { guid = "Player-1-0003", name = "Vex Shadowstep", class = "ROGUE", role = "DAMAGER", auras = {
    { spellId = 25291, sourceUnit = "party4", expirationTime = clock + 3000, duration = 3600 } } }
world.units.party3 = { guid = "Player-1-0004", name = "Ilsa Frostweave", class = "MAGE", role = "DAMAGER", auras = {} }
world.units.party4 = { guid = "Player-1-0005", name = "Oren Dawnshield", class = "PALADIN", role = "HEALER", auras = {} }

BuffOMaticDB = { debug = true }
fire("ADDON_LOADED", "BuffOMatic")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")
advance(0.5)

local btn = namedFrames.BuffOMaticMainButton
check(btn ~= nil, "main button created")
check(btn.attrs.useOnKeyDown == false, "useOnKeyDown disabled")
check(#stateDrivers == 1, "combat state driver registered")

-- 1) Five clicks buff five people in roster order, each the right blessing.
local expected = {
    { "Lumen Brightforge", "Blessing of Kings" },       -- paladin, unknown role -> Kings
    { "Brann Ironwall", "Blessing of Kings" },          -- tank -> Kings
    { "Vex Shadowstep", "Blessing of Kings" },          -- rogue: Might supplied by Oren -> Kings
    { "Ilsa Frostweave", "Blessing of Kings" },         -- mage -> Kings
    { "Oren Dawnshield", "Blessing of Wisdom" },        -- holy paladin -> Wisdom
}
for i, exp in ipairs(expected) do
    local shown = ns.UI.nextText.text or ""
    local r, name, spell = click(btn)
    check(r == "cast", "click " .. i .. " cast (" .. tostring(r) .. ")")
    check(name == exp[1] and spell == exp[2], string.format("click %d: expected %s/%s got %s/%s", i, exp[1], exp[2], tostring(name), tostring(spell)))
    check(shown:find(exp[1], 1, true) ~= nil, "UI showed the bound target before click " .. i .. ": " .. shown)
    advance(1.2)
end
check((ns.UI.nextText.text or ""):find("Party buffed", 1, true) ~= nil, "party buffed message: " .. tostring(ns.UI.nextText.text))
check(click(btn) == "noaction", "click with nothing to do casts nothing")
check(ns.summary.shortest ~= nil and not ns.summary.warn, "shortest timer tracked, no warning")

-- 2) Timers: at exactly 10:00 nothing is due; just under -> due; warning under 5:00 with sound once.
advance(3600 - 600 - 6) -- earliest buff (cast at ~t0) now has ~10:00 left
local d = ns.decisions["Player-1-0001"]
check(d.status == "HEALTHY", "about 10:00 left is not due: " .. tostring(d.status) .. " " .. tostring(d.remaining))
advance(3)
check(ns.decisions["Player-1-0001"].status == "CAST", "under 10:00 -> refresh due")
advance(300)
check(ns.summary.warn == true, "rebuff soon warning under 5:00")
check((world.sounds or 0) == 1, "sound played once on crossing: " .. tostring(world.sounds))
advance(30)
check((world.sounds or 0) == 1, "sound rate-limited")

-- 3) Refresh cycle: rebuff everyone, warning clears.
for i = 1, 5 do click(btn) advance(1.2) end
check(not ns.summary.warn, "warning reset after rebuffing")

-- 4) Combat: no protected changes, smart button inert, UI says so.
advance(3600 - 590) -- everyone due again
enterCombat()
advance(2)          -- ticker refreshes in combat must not touch attributes (mock errors if they do)
check(btn.attrs.type == nil, "button inert in combat")
check(click(btn) == "noaction", "click in combat does nothing")
check((ns.UI.nextText.text or ""):find("out of combat", 1, true) ~= nil, "combat message shown")
fire("GROUP_ROSTER_UPDATE")  -- roster change in combat: deferred
advance(1)
check(ns.rosterStale == true, "roster change in combat flagged stale")
leaveCombat()
advance(1)
check(ns.rosterStale == false, "roster rebuilt after combat")
check(btn.attrs.type == "spell", "button re-prepared after combat")

-- 5) Party slot reorder after preparation: the click must follow the GUID, not the slot.
local preparedName = ns.Roster.members[ns.prepared.guid].name
local preparedUnit = ns.prepared.unit
local other = preparedUnit == "party1" and "party2" or "party1"
world.units[preparedUnit], world.units[other] = world.units[other], world.units[preparedUnit]
local r, name = click(btn)
check(r == "cast", "cast after reorder")
check(name ~= nil, "someone was buffed after reorder")
-- the cast target must be a member that actually needed a buff, under its real GUID
local castUnitGUID
for tok, u in pairs(world.units) do if u.name == name then castUnitGUID = u.guid end end
check(castUnitGUID ~= nil, "cast target resolved to a real member")
advance(1.2)

-- 6) Out-of-range member does not block others; failure does not advance cursor.
for _, u in pairs(world.units) do u.auras = {} end
for tok, u in pairs(world.units) do fire("UNIT_AURA", tok, {}) end
fire("GROUP_ROSTER_UPDATE")
advance(1)
local target = ns.prepared and ns.prepared.unit
check(target ~= nil, "something prepared after wipe")
world.units[target].inRange = false
advance(1.1)
check(ns.prepared and ns.prepared.unit ~= target, "out-of-range member skipped by preparation")
world.units[target].inRange = nil

-- 7) Interrupt + aura delay: no advance on interrupt; delayed aura does not double-cast.
advance(1.1)
local cursorBefore = ns.sched.cursorGUID
local tgt = ns.prepared.guid
click(btn, { interrupt = true })
advance(0.2)
check(ns.sched.cursorGUID == cursorBefore, "interrupted cast did not advance cursor")
local r2, n2 = click(btn, { auraDelay = 1.5 })
check(r2 == "cast", "cast with delayed aura")
advance(0.3)
check(ns.prepared == nil or ns.prepared.guid ~= tgt, "pending target not re-prepared while aura propagates")
advance(2)

-- 8) Secret auras out of combat (e.g. restricted instance) -> conservative UNKNOWN, no cast prepared for them.
world.units.party3.secretAuras = true
fire("UNIT_AURA", "party3", {})
advance(0.5)
check(ns.decisions["Player-1-0004"].status == "UNKNOWN", "secret auras -> UNKNOWN")
check(not ns.prepared or ns.prepared.guid ~= "Player-1-0004", "never prepared for unreadable member")
world.units.party3.secretAuras = nil

-- 9) Slash commands run without errors.
local slash = SlashCmdList.BUFFOMATIC
for _, c in ipairs({ "help", "diag", "table", "assign Vex Shadowstep might", "role Ilsa Frostweave healer",
    "prio Brann Ironwall kings,might", "classprio WARRIOR DAMAGER kings,might", "classprio WARRIOR DAMAGER default",
    "greater on", "greater off", "self off", "self on", "refresh 12", "refresh 10", "warn 5", "buttons on", "buttons off",
    "exclude Oren Dawnshield on", "exclude Oren Dawnshield off", "reset", "debug on" }) do
    local ok, err = pcall(slash, c)
    check(ok, "slash " .. c .. ": " .. tostring(err))
    advance(0.2)
end

-- 10) Greater mode with reagents: two warriors, safe -> Greater offered for the class.
world.known[25916] = true; world.known[25898] = true
fire("SPELLS_CHANGED")
world.reagents = 10
world.units.party3 = { guid = "Player-1-0006", name = "Durn Axebreaker", class = "WARRIOR", role = "DAMAGER", auras = {} }
for _, u in pairs(world.units) do if u.name == "Brann Ironwall" then u.role = "DAMAGER" end end
for tok, u in pairs(world.units) do u.auras = {} end
slash("prio Brann Ironwall auto")
slash("greater on")
fire("GROUP_ROSTER_UPDATE")
advance(1)
local foundGreater = false
for i = 1, 6 do
    if ns.prepared and ns.prepared.greater then foundGreater = true break end
    click(btn) advance(1.2)
end
check(foundGreater, "greater blessing offered for two same-intent warriors; why=" .. tostring(ns.greaterWhy) .. " prepared=" .. tostring(ns.prepared and ns.prepared.family) .. " " .. tostring(ns.prepared and ns.prepared.unit))

---------------------------------------------------------------- report
for _, e in ipairs(errors) do failures[#failures + 1] = "runtime: " .. e end
io.write(string.format("Buff-o-Matic smoke: %d checks, %d failures\n", checks, #failures))
for _, f in ipairs(failures) do io.write("  FAIL " .. f .. "\n") end
if #failures > 0 then error("smoke test failed") end
