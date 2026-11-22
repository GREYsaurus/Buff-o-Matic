-- Buff-o-Matic: secure action buttons.
--
-- Main "Smart Bless" button:
--   * SecureActionButtonTemplate with type="spell", spell=<name>, unit=<token>. The game
--     executes the cast; addon Lua never casts.
--   * Attributes are written only out of combat (Prepare.Apply refuses in combat).
--   * A secure state driver clears type/spell/unit the moment combat starts, so a stale
--     prepared action can never fire in combat (aura data is secret there anyway).
--   * PreClick (out of combat only) re-validates that the unit token still belongs to the
--     prepared GUID and re-prepares if the party reordered. It never runs in combat.
--   * useOnKeyDown=false + "LeftButtonUp": exactly one secure action per physical click
--     (the modern client's ActionButtonUseKeyDown CVar would otherwise act on key down).
local _, ns = ...
local SB = {}
ns.SecureButton = SB

local COMBAT_SNIPPET = [[
    if newstate == "combat" then
        self:SetAttribute("type", nil)
        self:SetAttribute("spell", nil)
        self:SetAttribute("unit", nil)
    end
]]

function SB.CreateMain(parent)
    local b = CreateFrame("Button", "BuffOMaticMainButton", parent, "SecureActionButtonTemplate, SecureHandlerStateTemplate")
    b:SetSize(40, 40)
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("_onstate-bomcombat", COMBAT_SNIPPET)
    RegisterStateDriver(b, "bomcombat", "[combat] combat; nocombat")
    b:SetScript("PreClick", function(self) ns.OnMainPreClick(self) end)
    ns.mainButton = b
    return b
end

-- Optional per-member manual buttons (setting "memberButtons"). Prepared out of combat with
-- that member's intended blessing; they keep working in combat as plain manual buttons
-- bound to a unit token (no smart selection in combat).
function SB.CreateRow(parent, i)
    local b = CreateFrame("Button", "BuffOMaticRow" .. i, parent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    return b
end

function SB.SetRowAction(b, unit, spellName)
    if InCombatLockdown() then return false end
    if unit and spellName then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", spellName)
        b:SetAttribute("unit", unit)
    else
        b:SetAttribute("type", nil)
        b:SetAttribute("spell", nil)
        b:SetAttribute("unit", nil)
    end
    return true
end
