-- Buff-o-Matic: deterministic, fair round-robin scheduler keyed by GUID. Pure.
--
-- order:  array of { guid, castable = bool, block = code|nil } in roster order
-- decisions: [guid] = decision (from Engine)
-- state:  { cursorGUID, cursorIndex, pending = {[guid]={family,untilTime}},
--           backoff = {[guid]=untilTime} }
--
-- Select scans the roster ONCE, starting just after the last successfully buffed GUID.
-- If that GUID left the group, it resumes from the cursor's last numeric position so
-- ordering stays fair. Uncastable members are skipped (not chosen, cursor untouched).
local _, ns = ...
local S = {}
ns.Scheduler = S

function S.NewState()
    return { cursorGUID = nil, cursorIndex = 0, pending = {}, backoff = {} }
end

local function startIndex(order, state)
    if state.cursorGUID then
        for i = 1, #order do
            if order[i].guid == state.cursorGUID then return i end
        end
    end
    local idx = state.cursorIndex or 0
    if idx > #order then idx = #order end
    return idx
end

-- Returns entry, decision, blocked  (blocked = list of {guid, code} skipped this scan)
function S.Select(order, decisions, state, now)
    local n = #order
    local blocked = {}
    if n == 0 then return nil, nil, blocked end
    local start = startIndex(order, state)
    for step = 1, n do
        local idx = ((start + step - 1) % n) + 1
        local m = order[idx]
        local d = decisions[m.guid]
        if d and d.status == "CAST" then
            local p = state.pending[m.guid]
            local bo = state.backoff[m.guid]
            if p and p.untilTime > now then
                blocked[#blocked + 1] = { guid = m.guid, code = "PENDING" }
            elseif bo and bo > now then
                blocked[#blocked + 1] = { guid = m.guid, code = "BACKOFF" }
            elseif not m.castable then
                blocked[#blocked + 1] = { guid = m.guid, code = m.block or "UNCASTABLE" }
            else
                return m, d, blocked
            end
        end
    end
    return nil, nil, blocked
end

-- Advance the cursor ONLY after a confirmed successful cast.
function S.OnSuccess(state, guid, order)
    state.cursorGUID = guid
    for i = 1, #order do
        if order[i].guid == guid then state.cursorIndex = i break end
    end
end
