-- Buff-o-Matic: version/API compatibility layer for the WoW Forever client (modern 12.x engine).
--
-- Forever facts this relies on (RESEARCH.md):
--   * C_UnitAuras / C_Spell / C_SpellBook / C_Item namespaces exist; the legacy globals
--     UnitAura, UnitBuff, GetSpellInfo, GetItemCount do NOT.
--   * "Secret values": in combat/encounters/instances many returns may be opaque. Tainted
--     code errors on comparison/arithmetic/boolean tests of a secret, so every value from
--     a restricted API is checked with issecretvalue() BEFORE it is compared or tested.
local _, ns = ...
local C = {}
ns.Compat = C

local _issecret = issecretvalue
function C.IsSecret(v)
    if _issecret then return _issecret(v) == true end
    return false
end

-- Call fn safely; secret or failed results become `default`.
function C.SafeBool(fn, default, ...)
    if not fn then return default end
    local ok, v = pcall(fn, ...)
    if not ok or C.IsSecret(v) then return default end
    if v == nil then return default end
    return v
end

function C.Interface()
    local _, _, _, toc = GetBuildInfo()
    return toc
end

function C.IsForever()
    local toc = C.Interface()
    if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then return true end
    return type(toc) == "number" and toc >= 16000 and toc < 20000
end

function C.InCombat()
    return InCombatLockdown()
end

function C.UnitGUID(unit)
    local ok, g = pcall(UnitGUID, unit)
    if not ok or C.IsSecret(g) then return nil end
    return g
end

function C.UnitName(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or C.IsSecret(name) or C.IsSecret(realm) or not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function C.UnitClass(unit)
    local ok, _, class = pcall(UnitClass, unit)
    if not ok or C.IsSecret(class) then return nil end
    return class
end

function C.UnitRole(unit)
    if not UnitGroupRolesAssigned then return "NONE" end
    local r = C.SafeBool(UnitGroupRolesAssigned, "NONE", unit)
    if r == "TANK" or r == "HEALER" or r == "DAMAGER" then return r end
    return "NONE"
end

function C.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n and not C.IsSecret(n) then return n end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name then return info.name end
    end
    return nil
end

function C.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and not C.IsSecret(t) then return t end
    end
    return 134400 -- question mark
end

function C.IsKnown(id)
    if IsPlayerSpell and C.SafeBool(IsPlayerSpell, false, id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C.SafeBool(C_SpellBook.IsSpellKnown, false, id) then return true end
    if IsSpellKnown and C.SafeBool(IsSpellKnown, false, id) then return true end
    return false
end

-- true / false / nil (nil = no range information; treated as "maybe")
function C.InRange(spellID, unit)
    if C.SafeBool(UnitIsUnit, false, unit, "player") then return true end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, v = pcall(C_Spell.IsSpellInRange, spellID, unit)
        if ok and not C.IsSecret(v) then return v end
    end
    return nil
end

-- usable, noMana  (nil when unknown)
function C.Usable(spellID)
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, spellID)
        if ok and not C.IsSecret(usable) and not C.IsSecret(noMana) then return usable, noMana end
    end
    return nil, nil
end

function C.ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID)
        if ok and not C.IsSecret(n) then return n or 0 end
    end
    return 0
end

function C.HasSecretRestrictions()
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local ok, v = pcall(C_Secrets.HasSecretRestrictions)
        if ok and not C.IsSecret(v) then return v end
    end
    return nil
end
