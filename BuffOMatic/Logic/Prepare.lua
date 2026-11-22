-- Buff-o-Matic: secure-button attribute application. Pure apart from the injected button/api,
-- so combat-lockdown behaviour is unit-testable.
--
-- Rules enforced here:
--   * Never touch protected attributes while api.inCombat() is true.
--   * The action shown in the UI is exactly the action last applied (ns.prepared).
--   * A prepared action is bound to a GUID; Validate() rejects it if the unit token
--     now points at someone else (party slot reorder, leave/join).
local _, ns = ...
local Pr = {}
ns.Prepare = Pr

-- action = { guid, unit, family, spellName, spellID, greater, affected } or nil
function Pr.Apply(button, action, api)
    if api.inCombat() then return false, "COMBAT" end
    if action then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", action.spellName)
        button:SetAttribute("unit", action.unit)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("spell", nil)
        button:SetAttribute("unit", nil)
    end
    return true
end

function Pr.Validate(action, guidForUnit)
    return action ~= nil and guidForUnit ~= nil and guidForUnit == action.guid
end
