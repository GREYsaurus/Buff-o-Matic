-- Buff-o-Matic: default, editable blessing priorities for WoW Forever.
-- Pure data. Override in game with /bfm classprio, /bfm prio, /bfm assign (see README).
--
-- These are JUDGMENT CALLS, not verified mechanics. What is verified (RESEARCH.md):
--   Kings  = +10% all stats (Forever: trained at 20, 60 min)
--   Might  = +133 attack power at max rank (Forever value, 60 min)
--   Wisdom = 40 mana per 5 sec at max rank (Forever value, 60 min)
--   One blessing per paladin per target; different paladins' blessings stack.
--
-- Reasoning behind the defaults:
--   * Kings first whenever the role is unknown: it helps every class and role, so it is
--     the least likely to be a wrong guess.
--   * Physical damage roles (rogue, DPS warrior, ret/enhancement) put Might first,
--     following long-standing Classic convention. Kings is a close second; reasonable
--     players disagree, which is why this table is editable.
--   * Healers put Wisdom first (mana sustain), then Kings.
--   * Pure casters never get Might (attack power does nothing for their spells).
--   * Hunters: in Classic, Might adds melee AP only, not ranged AP. Unverified for
--     Forever, so Might is listed last for hunters.
--   * Tanks: Kings first (stamina/armor via stats), then Might for threat. Paladin tanks
--     also want Wisdom (mana-based tanking).
--   * Wisdom is filtered out automatically for classes without mana, even if listed.
--   * No Forever blessing reduces threat (Salvation was removed), so the "never give a
--     tank threat reduction" rule is enforced by the engine's threatReducing flag, ready
--     for any future family.
local _, ns = ...
local P = {}
ns.Priorities = P

P.ROLES = { "TANK", "HEALER", "DAMAGER", "NONE" }

-- [CLASS][ROLE] = ordered list. Missing roles fall back to NONE.
P.DEFAULTS = {
    WARRIOR = {
        TANK = { "KINGS", "MIGHT" },
        DAMAGER = { "MIGHT", "KINGS" },
        NONE = { "KINGS", "MIGHT" },   -- don't assume every warrior is a tank (or DPS)
    },
    ROGUE = {
        NONE = { "MIGHT", "KINGS" },
    },
    HUNTER = {
        NONE = { "KINGS", "WISDOM", "MIGHT" },
    },
    MAGE = {
        NONE = { "KINGS", "WISDOM" },
    },
    WARLOCK = {
        NONE = { "KINGS", "WISDOM" },
    },
    PRIEST = {
        HEALER = { "WISDOM", "KINGS" },
        NONE = { "KINGS", "WISDOM" },
    },
    DRUID = {
        TANK = { "KINGS", "MIGHT" },
        HEALER = { "WISDOM", "KINGS" },
        DAMAGER = { "KINGS", "MIGHT", "WISDOM" },  -- cat vs moonkin unknown: Kings is safe
        NONE = { "KINGS", "WISDOM", "MIGHT" },
    },
    PALADIN = {
        TANK = { "KINGS", "WISDOM", "MIGHT" },
        HEALER = { "WISDOM", "KINGS" },
        DAMAGER = { "MIGHT", "KINGS", "WISDOM" },
        NONE = { "KINGS", "WISDOM", "MIGHT" },
    },
    SHAMAN = {
        HEALER = { "WISDOM", "KINGS" },
        DAMAGER = { "KINGS", "MIGHT", "WISDOM" },
        NONE = { "KINGS", "WISDOM", "MIGHT" },
    },
}

P.FALLBACK = { "KINGS" }

local function copy(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

-- Resolve the ranked list for a class/role.
-- classRoleOverrides: optional { [CLASS] = { [ROLE] = list } } from saved settings.
-- Returns list, sourceCode ("CLASS_ROLE_OVERRIDE" | "DEFAULT" | "FALLBACK").
function P.Resolve(class, role, classRoleOverrides)
    role = role or "NONE"
    local o = classRoleOverrides and class and classRoleOverrides[class]
    if o then
        if o[role] and #o[role] > 0 then return copy(o[role]), "CLASS_ROLE_OVERRIDE" end
        if o.NONE and #o.NONE > 0 and not (P.DEFAULTS[class] and P.DEFAULTS[class][role]) then
            return copy(o.NONE), "CLASS_ROLE_OVERRIDE"
        end
    end
    local d = class and P.DEFAULTS[class]
    if d then
        if d[role] then return copy(d[role]), "DEFAULT" end
        if d.NONE then return copy(d.NONE), "DEFAULT" end
    end
    return copy(P.FALLBACK), "FALLBACK"
end
