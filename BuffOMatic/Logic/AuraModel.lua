-- Buff-o-Matic: normalize raw aura entries into per-member blessing coverage. Pure.
--
-- Input entries (produced by Auras.lua from C_UnitAuras, after secret-value guards):
--   { spellId = number|nil, casterKind = "me"|"other"|"unknown", casterName = string|nil,
--     expirationTime = number|nil, duration = number|nil, unreadable = bool }
-- Output coverage:
--   { mine = auraOrNil, others = { [FAMILY] = aura }, unreadable = bool }
-- where aura = { family, rank, greater, casterKind, casterName, expirationTime, duration }
--
-- Normal and Greater spells of a family map to the SAME family key, so Greater coverage
-- counts as coverage of that family (they are one buff slot per caster on Forever/Classic).
local _, ns = ...
local A = {}
ns.AuraModel = A
local B = ns.Blessings

local function better(a, b)
    -- Prefer the entry with known, later expiration; then higher rank.
    if not a then return b end
    if not b then return a end
    local ea, eb = a.expirationTime or -1, b.expirationTime or -1
    if ea ~= eb then return (ea > eb) and a or b end
    return ((a.rank or 0) >= (b.rank or 0)) and a or b
end

function A.Build(entries)
    local cov = { mine = nil, others = {}, unreadable = false }
    for i = 1, #entries do
        local e = entries[i]
        if e.unreadable then
            cov.unreadable = true
        else
            local fam, info = B.FamilyOf(e.spellId)
            if fam then
                local aura = {
                    family = fam,
                    rank = info.rank,
                    greater = info.greater,
                    external = info.external,
                    casterKind = info.external and "other" or e.casterKind,
                    casterName = e.casterName,
                    expirationTime = e.expirationTime,
                    duration = e.duration,
                }
                if aura.casterKind == "me" then
                    cov.mine = better(cov.mine, aura)
                else
                    local prev = cov.others[fam]
                    -- An "unknown" caster must never be hidden behind a known one.
                    if prev and prev.casterKind == "unknown" then
                        -- keep unknown
                    elseif aura.casterKind == "unknown" then
                        cov.others[fam] = aura
                    else
                        cov.others[fam] = better(prev, aura)
                    end
                end
            end
        end
    end
    return cov
end

function A.Remaining(aura, now)
    if not aura or not aura.expirationTime then return nil end
    return aura.expirationTime - now
end
