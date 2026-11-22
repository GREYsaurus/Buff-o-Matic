-- Buff-o-Matic: group roster (GUID-keyed), roles and manual assignments.
-- Pets are never included. In a raid, all members are tracked (Greater Blessing safety
-- needs the whole raid), but the click rotation is limited to your subgroup unless the
-- "raid" option is on.
local _, ns = ...
local R = {}
ns.Roster = R
local C = ns.Compat

R.members = {}      -- [guid] = member
R.order = {}        -- rotation order: array of members (roster order)
R.unitToGUID = {}   -- [unit] = guid

local function units()
    local list = {}
    if IsInRaid() then
        local n = GetNumGroupMembers()
        local mySub
        local subs = {}
        for i = 1, n do
            local ok, _, _, sub = pcall(GetRaidRosterInfo, i)
            if ok and not C.IsSecret(sub) then subs[i] = sub end
            if C.SafeBool(UnitIsUnit, false, "raid" .. i, "player") then mySub = subs[i] end
        end
        for i = 1, n do list[#list + 1] = { unit = "raid" .. i, inRotation = ns.db.raid or subs[i] == mySub } end
    else
        list[1] = { unit = "player", inRotation = true }
        for i = 1, GetNumSubgroupMembers() do list[#list + 1] = { unit = "party" .. i, inRotation = true } end
    end
    return list
end

function R.Rebuild()
    local db = ns.db
    local members, order, unitToGUID = {}, {}, {}
    for _, u in ipairs(units()) do
        local unit = u.unit
        local guid = C.UnitGUID(unit)
        if guid and not members[guid] and C.SafeBool(UnitIsPlayer, false, unit) then
            local name = C.UnitName(unit) or "?"
            local isSelf = C.SafeBool(UnitIsUnit, false, unit, "player")
            local p = db.players[name] or {}
            local m = {
                guid = guid, unit = unit, name = name, isSelf = isSelf,
                class = C.UnitClass(unit),
                assigned = p.assigned,
                priorityOverride = p.priority,
                excluded = (isSelf and not db.includeSelf) or p.exclude or false,
            }
            if p.role then m.role, m.roleManual = p.role, true else m.role = C.UnitRole(unit) end
            members[guid] = m
            unitToGUID[unit] = guid
            if u.inRotation and not m.excluded then order[#order + 1] = m end
        end
    end
    R.members, R.order, R.unitToGUID = members, order, unitToGUID
    local valid = {}
    for g in pairs(members) do valid[g] = true end
    return valid
end

function R.FindByName(name)
    if not name then return nil end
    local lname = name:lower()
    for _, m in pairs(R.members) do
        if m.name:lower() == lname then return m end
    end
    for _, m in pairs(R.members) do
        if m.name:lower():find(lname, 1, true) == 1 then return m end
    end
    return nil
end
