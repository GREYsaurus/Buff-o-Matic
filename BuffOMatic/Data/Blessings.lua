-- Buff-o-Matic: blessing-family definitions for WoW Forever (client 1.60.1, interface 16001).
-- Pure data + pure helpers: no WoW API calls here (loaded by the offline test runner).
--
-- Sources and verification status: see RESEARCH.md. Summary:
--   * Forever (launch, Nov 2026) has exactly three maintenance blessing families:
--     Might, Wisdom, Kings - each with a Greater (class-wide) version.
--   * Blessing of Light, Sanctuary, Salvation (and Forever beta's "Salvation"/"Mass
--     Salvation"/"Revoke") were removed before launch. They are deliberately NOT listed,
--     so the addon can never select them.
--   * Single and Greater blessings both last 60 minutes on Forever.
--   * Greater blessings consume Symbol of Kings (item 21177).
--   * Forever kept the Classic spell IDs (Wowhead Forever serves them with Forever data).
local _, ns = ...
local B = {}
ns.Blessings = B

B.CLIENT_LABEL = "WoW Forever 1.60.1"
B.SYMBOL_OF_KINGS = 21177
B.DEFAULT_DURATION = 3600

-- Stable family identifiers (never localized). Rank lists are ascending (rank 1 first).
B.FAMILIES = {
    KINGS = {
        single = { 20217 },            -- trained at 20 on Forever (no longer a talent)
        greater = { 25898 },           -- level 60
        singleDuration = 3600,
        greaterDuration = 3600,
        requiresMana = false,
        threatReducing = false,
        maintenance = true,
    },
    MIGHT = {
        single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, -- ranks 1-7
        greater = { 25782, 25916 },                                    -- ranks 1-2
        singleDuration = 3600,
        greaterDuration = 3600,
        requiresMana = false,
        threatReducing = false,
        maintenance = true,
    },
    WISDOM = {
        single = { 19742, 19850, 19852, 19853, 19854, 25290 },        -- ranks 1-6
        greater = { 25894, 25918 },                                    -- ranks 1-2
        singleDuration = 3600,
        greaterDuration = 3600,
        requiresMana = true,   -- mp5 is useless to rage/energy-only classes
        threatReducing = false,
        maintenance = true,
    },
}

-- Display order for UI lists.
B.ORDER = { "KINGS", "MIGHT", "WISDOM" }

-- Classes whose base resource is mana (druids keep a mana pool in forms).
B.MANA_CLASSES = {
    PALADIN = true, PRIEST = true, MAGE = true, WARLOCK = true,
    DRUID = true, HUNTER = true, SHAMAN = true,
}

-- Non-paladin effects that are mutually exclusive with / redundant to a family.
-- Empty by default: the only claims found (e.g. Forever campfire buffs not stacking with
-- Kings/Might) come from fan guides without spell IDs, so nothing is asserted here.
-- Format: [spellID] = "FAMILY". Such auras are treated as "supplied by another source".
B.EQUIVALENT_EFFECTS = {}

-- Reverse lookup: spellID -> { family, rank, greater }
B.byID = {}
local function index()
    for key, f in pairs(B.FAMILIES) do
        f.key = key
        for rank, id in ipairs(f.single) do B.byID[id] = { family = key, rank = rank, greater = false } end
        for rank, id in ipairs(f.greater) do B.byID[id] = { family = key, rank = rank, greater = true } end
    end
    for id, fam in pairs(B.EQUIVALENT_EFFECTS) do
        if not B.byID[id] then B.byID[id] = { family = fam, rank = 0, greater = false, external = true } end
    end
end
B.Reindex = index
index()

function B.FamilyOf(spellID)
    local e = spellID and B.byID[spellID]
    if e then return e.family, e end
    return nil
end

-- Natural full duration for a family (used when the aura does not report one).
function B.FullDuration(family, greater)
    local f = B.FAMILIES[family]
    if not f then return nil end
    if greater then return f.greaterDuration or B.DEFAULT_DURATION end
    return f.singleDuration or B.DEFAULT_DURATION
end
