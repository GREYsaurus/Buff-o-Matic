-- Buff-o-Matic: Greater Blessing safety evaluation. Pure.
--
-- A Greater Blessing hits EVERY member of the target's class in the group/raid. It is only
-- offered when that side effect is provably safe for every affected member:
--   * Greater mode enabled, Greater spell known, Symbol of Kings in bags, mana OK
--   * every same-class member has readable auras and the SAME intended family
--     (mixed roles/specs with different intents -> refuse)
--   * no same-class member has that family from another paladin (would overwrite)
--   * no same-class member is pinned to a different family (protected assignment)
--   * no same-class member is excluded (e.g. yourself with "include me" off)
--   * at least greaterMinTargets members actually need the cast
-- Otherwise the caller falls back to the single-target blessing.
local _, ns = ...
local G = {}
ns.Greater = G

-- members: [guid] = member (ALL group members incl. excluded ones, flagged .excluded)
-- ctx: { settings, greaterKnown = {[FAM]=true}, greaterUsable = {[FAM]=bool}, reagents = n }
function G.Evaluate(targetGuid, members, decisions, ctx)
    local s = ctx.settings
    if not s.greaterMode then return nil, "DISABLED" end
    local tm, td = members[targetGuid], decisions[targetGuid]
    if not tm or not td or td.status ~= "CAST" then return nil, "NOT_NEEDED" end
    local fam = td.family
    if not (ctx.greaterKnown and ctx.greaterKnown[fam]) then return nil, "GREATER_NOT_KNOWN" end
    if (ctx.reagents or 0) < 1 then return nil, "NO_REAGENT" end
    if ctx.greaterUsable and ctx.greaterUsable[fam] == false then return nil, "NO_MANA" end

    local guids = {}
    for guid in pairs(members) do guids[#guids + 1] = guid end
    table.sort(guids)

    local affected, needing = {}, 0
    for _, guid in ipairs(guids) do
        local m = members[guid]
        if m.class == tm.class then
            local d = decisions[guid]
            if m.excluded then return nil, "AFFECTS_EXCLUDED", m.name end
            if not d or d.status == "UNKNOWN" then return nil, "AFFECTS_UNKNOWN", m.name end
            if m.others and m.others[fam] then return nil, "WOULD_OVERWRITE_OTHER", m.name end
            if m.assigned and m.assigned ~= fam then return nil, "PROTECTED_ASSIGNMENT", m.name end
            if d.family ~= fam then return nil, "MIXED_INTENT", m.name end
            affected[#affected + 1] = guid
            if d.status == "CAST" then needing = needing + 1 end
        end
    end
    if needing < (s.greaterMinTargets or 2) then return nil, "TOO_FEW" end
    return { family = fam, affected = affected, needing = needing }
end
