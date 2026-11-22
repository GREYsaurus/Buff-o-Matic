-- Buff-o-Matic: cast-attempt state machine. Pure; events are fed in by CastTracker.lua.
--
-- Lifecycle of one physical click:
--   OnClick(prepared)        -> attempt recorded (NOT a success)
--   OnSent(spellID, castGUID) -> attempt bound to the castGUID if the spell's family matches
--   OnSucceeded(castGUID)    -> success: pending + grace for every affected GUID; caller
--                               advances the scheduler cursor
--   OnFailed(castGUID)       -> failure: no advance; repeated failures -> temporary backoff
--   ExpireAttempt            -> a click that never produced UNIT_SPELLCAST_SENT counts as a
--                               failure attempt (out of range, no mana, GCD, ...)
local _, ns = ...
local C = {}
ns.CastState = C
local B = ns.Blessings

function C.New()
    return { attempt = nil, casts = {}, failCount = {}, lastCast = {} }
end

function C.OnClick(s, prepared, now)
    if not prepared then return end
    s.attempt = {
        guid = prepared.guid, family = prepared.family, greater = prepared.greater,
        affected = prepared.affected or { prepared.guid }, time = now,
    }
end

function C.OnSent(s, spellID, castGUID, now)
    local a = s.attempt
    if not a or now - a.time > 2 then return false end
    local fam = B.FamilyOf(spellID)
    if fam ~= a.family then return false end
    s.casts[castGUID] = a
    s.attempt = nil
    return true
end

-- sched: scheduler state (pending/backoff live there so Select can see them)
function C.OnSucceeded(s, sched, castGUID, now, settings)
    local a = s.casts[castGUID]
    if not a then return nil end
    s.casts[castGUID] = nil
    for _, g in ipairs(a.affected) do
        sched.pending[g] = { family = a.family, untilTime = now + settings.pendingTimeout }
        s.lastCast[g] = { family = a.family, time = now }
        s.failCount[g] = nil
        sched.backoff[g] = nil
    end
    return a
end

local function fail(s, sched, guid, now, settings)
    s.failCount[guid] = (s.failCount[guid] or 0) + 1
    if s.failCount[guid] >= settings.failThreshold then
        sched.backoff[guid] = now + settings.backoffSeconds
        s.failCount[guid] = 0
    end
end

function C.OnFailed(s, sched, castGUID, now, settings)
    local a = s.casts[castGUID]
    if not a then return nil end
    s.casts[castGUID] = nil
    fail(s, sched, a.guid, now, settings)
    return a
end

function C.ExpireAttempt(s, sched, now, settings)
    local a = s.attempt
    if a and now - a.time > 1.0 then
        s.attempt = nil
        fail(s, sched, a.guid, now, settings)
        return a
    end
    return nil
end

-- Aura confirmation clears pending early.
function C.OnAuraConfirmed(sched, guid, family)
    local p = sched.pending[guid]
    if p and p.family == family then sched.pending[guid] = nil return true end
    return false
end

-- Drop expired entries and GUIDs that left the group.
function C.Prune(s, sched, now, validGUIDs, settings)
    for g, p in pairs(sched.pending) do
        if p.untilTime <= now or not validGUIDs[g] then sched.pending[g] = nil end
    end
    for g, t in pairs(sched.backoff) do
        if t <= now or not validGUIDs[g] then sched.backoff[g] = nil end
    end
    for g, lc in pairs(s.lastCast) do
        if not validGUIDs[g] or now - lc.time > math.max(settings.graceSeconds, 60) then s.lastCast[g] = nil end
    end
    for g in pairs(s.failCount) do
        if not validGUIDs[g] then s.failCount[g] = nil end
    end
    for cg, a in pairs(s.casts) do
        if now - a.time > 10 then s.casts[cg] = nil end
    end
end
