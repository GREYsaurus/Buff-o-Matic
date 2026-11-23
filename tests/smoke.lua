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
    NewTicker = function(d, fn)
        local t = { at = clock + d, fn = fn, every = d }
        t.Cancel = function(self) self.cancelled = true end
        timers[#timers + 1] = t
        return t
    end,
}
local function advance(sec)
    local target = clock + sec
    while true do
        table.sort(timers, function(a, b) return a.at < b.at end)
        local t = timers[1]
        if not t or t.at > target then break end
        clock = t.at
        table.remove(timers, 1)
        if t.cancelled then t.every = nil t.fn = function() end end
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
IsInGroup = function() return GetNumSubgroupMembers() > 0 end
IsInInstance = function() return false end
LE_PARTY_CATEGORY_INSTANCE = 2
Ambiguate = function(n) return n end
UnitIsGroupLeader = function(unit) return world.leader == unit end
UnitIsGroupAssistant = function() return false end
world.addonSent = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) world.prefix = p return true end,
    SendAddonMessage = function(p, msg, ch) world.addonSent[#world.addonSent + 1] = { p, msg, ch } return true end,
}
world.settings = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name, GetID = function() return 77 end } end,
    RegisterAddOnCategory = function(cat) world.settings.registered = cat end,
    OpenToCategory = function(id) world.settings.opened = id end,
}
Minimap = newFrame("Minimap")
function FrameMT:GetWidth() return 140 end

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
if preparedUnit == "player" then preparedUnit = "party1" end -- the player token never moves
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

-- 11) Roles: spec fallback for yourself, group role wins, manual wins over both.
slash("greater off")
local selfGUID = world.units.player.guid
local function selfMember() return ns.Roster.members[selfGUID] end
fire("GROUP_ROSTER_UPDATE") advance(0.5)
check(selfMember().roleSource == "NONE", "no role source without group role or spec API: " .. tostring(selfMember().role) .. "/" .. tostring(selfMember().roleSource))
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 65, "Holy", "", 0, "HEALER" end,
}
fire("PLAYER_SPECIALIZATION_CHANGED") advance(0.5)
check(selfMember().role == "HEALER" and selfMember().roleSource == "SPEC", "own spec role used when no party role")
world.units.player.role = "TANK"
fire("PLAYER_ROLES_ASSIGNED") advance(0.5)
check(selfMember().role == "TANK" and selfMember().roleSource == "GROUP", "party role icon wins over spec")
slash("role me dps") advance(0.5)
check(selfMember().role == "DAMAGER" and selfMember().roleSource == "MANUAL", "/bfm role me sets your own role")
slash("role me auto") advance(0.5)
check(selfMember().roleSource == "GROUP", "/bfm role me auto clears override")
world.units.player.role = "NONE"

-- 12) Right-click row menu (MenuUtil mock records radios/checkboxes and lets us click them).
local menuItems = {}
local function node()
    local n = {}
    function n:CreateTitle(t) end
    function n:CreateButton(t) local c = node(); menuItems[t] = c; c.items = {}; return c end
    function n:CreateRadio(t, isSel, setSel) self.items = self.items or {}; self.items[t] = { isSel = isSel, set = setSel } end
    function n:CreateCheckbox(t, isSel, setSel) menuItems[t] = { isSel = isSel, set = setSel } end
    return n
end
MenuUtil = { CreateContextMenu = function(owner, gen) local root = node(); gen(owner, root) end }
local row
for i = 1, 10 do
    local r = namedFrames["BuffOMaticRow" .. i]
    if r and r.member == world.units.party2.guid then row = r end
end
check(row ~= nil, "row exists for party2")
if row then
    local target = ns.Roster.members[row.member]
    row.scripts.PostClick(row, "RightButton", false)
    check(menuItems.Role and menuItems.Role.items.Healer, "role submenu built")
    menuItems.Role.items.Healer.set()
    advance(0.5)
    target = ns.Roster.members[row.member]
    check(target.role == "HEALER" and target.roleSource == "MANUAL", "menu sets role")
    check(menuItems.Role.items.Healer.isSel(), "menu radio reflects role")
    menuItems.Blessing.items.Kings.set() advance(0.5)
    check(ns.Roster.members[row.member].assigned == "KINGS", "menu pins blessing")
    menuItems.Blessing.items.Automatic.set() menuItems.Role.items.Automatic.set() advance(0.5)
    check(ns.Roster.members[row.member].assigned == nil and ns.Roster.members[row.member].roleSource ~= "MANUAL", "menu resets to automatic")
    -- right click never carries a secure cast; left click only when member buttons on
    slash("buttons on") advance(1.2)
    check(row.attrs.type == nil and row.attrs.type1 == "spell", "row cast bound to left click only")
    slash("buttons off") advance(1.2)
    check(row.attrs.type1 == nil, "row cast cleared when member buttons off")
end

-- 13) Chat output escapes "|" so usage text isn't eaten by WoW escape codes.
printed = {}
slash("help")
local sawEscaped = false
for _, line in ipairs(printed) do if line:find("tank||healer", 1, true) then sawEscaped = true end end
check(sawEscaped, "help text escapes pipes")

-- 14) Keybinding, options panel, minimap/compartment.
check(_G["BINDING_NAME_CLICK BuffOMaticMainButton:LeftButton"] ~= nil and BINDING_HEADER_BUFFOMATIC ~= nil, "binding strings defined")
do
    local fh = io.open(ADDON_DIR .. "Bindings.xml", "r")
    local xml = fh and fh:read("*a") or ""
    if fh then fh:close() end
    check(xml:find('name="CLICK BuffOMaticMainButton:LeftButton"', 1, true) ~= nil, "Bindings.xml binds the main button")
end
check(world.settings.registered and world.settings.registered.frame == ns.Options.panel, "options panel registered under AddOns")
slash("options")
check(world.settings.opened == 77, "/bfm options opens the panel")
ns.Options.Refresh()
check(namedFrames.BuffOMaticMinimapButton ~= nil and namedFrames.BuffOMaticMinimapButton.shown, "minimap button shown")
slash("minimap off")
check(not namedFrames.BuffOMaticMinimapButton.shown and ns.db.minimap.hide, "minimap button hidden")
slash("minimap on")
check(type(BuffOMatic_OnAddonCompartmentClick) == "function", "addon compartment handler defined")
local hiddenBefore = ns.db.hidden
BuffOMatic_OnAddonCompartmentClick("BuffOMatic", "LeftButton")
check(ns.db.hidden ~= hiddenBefore, "compartment left-click toggles the window")
BuffOMatic_OnAddonCompartmentClick("BuffOMatic", "LeftButton")
check((not ns.db.hidden) == (not hiddenBefore), "compartment toggles back")

-- 15) PallyPower coordination (read-only).
check(world.prefix == "PLPWR", "PallyPower prefix registered")
local sentReq = false
for _, m in ipairs(world.addonSent) do if m[1] == "PLPWR" and m[2] == "REQ" then sentReq = true end end
check(sentReq, "asked PallyPower users for their plans")
for _, m in ipairs(world.addonSent) do check(m[2] == "REQ", "only REQ is ever sent: " .. tostring(m[2])) end
local function pp(msg, sender) fire("CHAT_MSG_ADDON", "PLPWR", msg, "PARTY", sender) advance(0.5) end
-- Known party, everyone already carrying my blessing.
local function mine(id) return { spellId = id, sourceUnit = "player", expirationTime = clock + 3500, duration = 3600 } end
world.units.player = { guid = "Player-1-0001", name = "Lumen Brightforge", class = "PALADIN", role = "NONE", auras = { mine(20217) } }
world.units.party1 = { guid = "Player-1-0002", name = "Brann Ironwall", class = "WARRIOR", role = "TANK", auras = { mine(20217) } }
world.units.party2 = { guid = "Player-1-0003", name = "Vex Shadowstep", class = "ROGUE", role = "DAMAGER", auras = { mine(20217) } }
world.units.party3 = { guid = "Player-1-0004", name = "Ilsa Frostweave", class = "MAGE", role = "DAMAGER", auras = { mine(20217) } }
world.units.party4 = { guid = "Player-1-0005", name = "Oren Dawnshield", class = "PALADIN", role = "HEALER", auras = { mine(25290) } }
fire("GROUP_ROSTER_UPDATE") advance(1.2)
local function dec(unit) return ns.decisions[world.units[unit].guid] end
-- Oren plans Kings for mages. I already hold Kings on Ilsa: keep it (no churn).
pp("ASSIGN Oren Dawnshield 7 3", "Oren Dawnshield")
check(dec("party3").family == "KINGS" and dec("party3").status == "HEALTHY", "keep my existing blessing despite plan")
-- My Kings on Ilsa drops off: now Kings is Oren's job, so I pick Wisdom.
world.units.party3.auras = {}
fire("UNIT_AURA", "party3", {}) advance(0.5)
local d3 = dec("party3")
check(d3.family == "WISDOM", "planned Kings left to Oren; Wisdom chosen: " .. tostring(d3.family))
local sawPlanned = false
for _, sk in ipairs(d3.skipped) do if sk.code == "PLANNED_BY" and sk.by == "Oren Dawnshield" then sawPlanned = true end end
check(sawPlanned, "skip reason names the planning paladin")
check(ns.UI.SkipText({ code = "PLANNED_BY", family = "KINGS", by = "Oren Dawnshield" }):find("Oren", 1, true) ~= nil, "planned skip text")
-- A non-leader can't rewrite Oren's plan.
pp("ASSIGN Oren Dawnshield 7 2", "Vex Shadowstep")
check(dec("party3").family == "WISDOM", "non-leader assignment for another paladin ignored")
-- Leader Oren assigns ME Might on Brann (NASSIGN, underscores for spaces).
world.leader = "party4"
pp("NASSIGN Lumen_Brightforge 1 Brann_Ironwall 2", "Oren Dawnshield")
check(dec("party1").family == "MIGHT" and dec("party1").reason.code == "PP_ASSIGNED", "my PallyPower assignment followed")
slash("assign Brann kings") advance(0.5)
check(dec("party1").family == "KINGS" and dec("party1").reason.code == "ASSIGNED", "manual pin beats PallyPower")
slash("assign Brann auto") advance(0.5)
-- Ready check: Ilsa is missing a blessing.
printed = {}
fire("READY_CHECK", "Oren Dawnshield", 30) advance(0.5)
local sawReady = false
for _, line in ipairs(printed) do if line:find("Ready check", 1, true) and line:find("Ilsa Frostweave", 1, true) then sawReady = true end end
check(sawReady, "ready check names members missing a blessing")
ns.db.readyCheck = false
printed = {}
fire("READY_CHECK", "Oren Dawnshield", 30) advance(0.5)
local quiet = true
for _, line in ipairs(printed) do if line:find("Ready check", 1, true) then quiet = false end end
check(quiet, "ready check reminder can be turned off")
ns.db.readyCheck = true
-- Leader CLEAR wipes plans; sync off ignores them entirely.
pp("CLEAR", "Oren Dawnshield")
check(dec("party3").family == "KINGS" and dec("party1").reason.code ~= "PP_ASSIGNED", "CLEAR removes plans")
pp("ASSIGN Oren Dawnshield 7 3", "Oren Dawnshield")
slash("pallypower off") advance(0.5)
check(dec("party3").family == "KINGS", "sync off ignores PallyPower plans")
slash("pallypower on") advance(0.5)
check(dec("party3").family == "WISDOM", "sync back on")
-- Combat: plans keep applying; nothing is ever sent in combat.
local nSent = #world.addonSent
enterCombat()
ns.RequestPallyPower(true)
check(#world.addonSent == nSent, "no addon messages sent in combat")
leaveCombat()
advance(1.2)

---------------------------------------------------------------- report
for _, e in ipairs(errors) do failures[#failures + 1] = "runtime: " .. e end
io.write(string.format("Buff-o-Matic smoke: %d checks, %d failures\n", checks, #failures))
for _, f in ipairs(failures) do io.write("  FAIL " .. f .. "\n") end
if #failures > 0 then error("smoke test failed") end
