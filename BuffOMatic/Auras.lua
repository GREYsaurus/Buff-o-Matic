-- Buff-o-Matic: reads group members' helpful auras via C_UnitAuras and normalizes them
-- (AuraModel). Results are cached per GUID and only re-read on UNIT_AURA / roster changes.
local _, ns = ...
local Au = {}
ns.Auras = Au
local C, B, AM = ns.Compat, ns.Blessings, ns.AuraModel

Au.cache = {}   -- [guid] = coverage (from AuraModel.Build) + .readAt, .stale

local MAX_AURAS = 64

-- Returns entries or nil, reason
function Au.ReadEntries(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil, "NO_API" end
    local entries = {}
    for i = 1, MAX_AURAS do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then return nil, "BLOCKED" end
        if C.IsSecret(a) then
            entries[#entries + 1] = { unreadable = true }
        elseif not a then
            break
        else
            local sid = a.spellId
            if C.IsSecret(sid) then
                entries[#entries + 1] = { unreadable = true }
            elseif sid and B.byID[sid] then
                local e = { spellId = sid }
                local src = a.sourceUnit
                if C.IsSecret(src) then
                    e.casterKind = "unknown"
                elseif src == nil then
                    local fromMe = a.isFromPlayerOrPlayerPet
                    if not C.IsSecret(fromMe) and fromMe == true then
                        e.casterKind = "me"
                    else
                        e.casterKind = "other" -- caster not in a referencable unit (outside group)
                    end
                elseif C.SafeBool(UnitIsUnit, false, src, "player") then
                    e.casterKind = "me"
                else
                    e.casterKind = "other"
                    e.casterName = C.UnitName(src)
                end
                local exp, dur = a.expirationTime, a.duration
                if not C.IsSecret(exp) and not C.IsSecret(dur) then
                    if exp and exp > 0 then e.expirationTime = exp end
                    if dur and dur > 0 then e.duration = dur end
                end
                entries[#entries + 1] = e
            end
        end
    end
    return entries
end

-- Read + cache. In combat a failed/secret read keeps the previous snapshot (marked stale)
-- instead of pretending the buffs vanished.
function Au.Update(unit, guid)
    if not guid then return end
    local entries, why = Au.ReadEntries(unit)
    local cov
    if entries then cov = AM.Build(entries) end
    local prev = Au.cache[guid]
    if (not cov or cov.unreadable) and prev and C.InCombat() then
        prev.stale = true
        return
    end
    if not cov then cov = { others = {}, unreadable = true, reason = why } end
    cov.readAt = GetTime()
    Au.cache[guid] = cov
end

function Au.Forget(validGUIDs)
    for g in pairs(Au.cache) do
        if not validGUIDs[g] then Au.cache[g] = nil end
    end
end
