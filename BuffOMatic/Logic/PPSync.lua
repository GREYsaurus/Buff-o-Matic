-- Buff-o-Matic: read-only PallyPower coordination. Pure (no WoW API calls).
--
-- PallyPower (prefix "PLPWR") broadcasts which paladin covers which class (Greater
-- assignments, which fall back to normal blessings on Forever) plus per-player overrides.
-- We only LISTEN: other paladins' plans become "planned supply" so Smart Bless picks a
-- different blessing; plans naming me become a default assignment (manual pins win).
--
-- Wire formats handled (fields separated by single spaces):
--   SELF <12 hex>@<9 class chars>     sender's own class row ('n' = none)
--   ASSIGN <pally> <classIdx> <blessingIdx>
--   MASSIGN <pally> <blessingIdx>      all classes
--   PASSIGN <pally>@<9 class chars>
--   NASSIGN <P> <classIdx> <T> <b>[@...]  per-player override, spaces in names sent as '_'
--   CLEAR [SKIP]                       leader: clear all; otherwise the sender's own plan
--   FREEASSIGN YES|NO ...              sender lets others assign them
-- Paladin names may contain spaces (Forever "First Last"); patterns are greedy from the
-- right, like PallyPower's own parser.
local _, ns = ...
local PP = {}
ns.PPSync = PP

PP.PREFIX = "PLPWR"

-- PallyPower class indices (vanilla/Forever table).
PP.CLASS_INDEX = {
    WARRIOR = 1, ROGUE = 2, PRIEST = 3, DRUID = 4, PALADIN = 5,
    HUNTER = 6, MAGE = 7, WARLOCK = 8, SHAMAN = 9,
}
-- PallyPower blessing indices -> our families (others don't exist on Forever).
PP.BLESSING_FAMILY = { [1] = "WISDOM", [2] = "MIGHT", [3] = "KINGS" }

function PP.New()
    return { class = {}, normal = {}, free = {} }
end

local function unwire(s) return (s:gsub("_", " ")) end

-- The paladin named in a message may differ from the sender; only leaders, or paladins
-- who opted into free assignment, may assign someone else (same rule as PallyPower).
local function allowed(st, pally, sender, isLeader)
    return pally == sender or isLeader or st.free[pally] == true
end

local function setClass(st, pally, idx, b)
    if not idx or idx < 1 or idx > 9 then return end
    st.class[pally] = st.class[pally] or {}
    st.class[pally][idx] = (b and b > 0) and b or nil
end

local function setRow(st, pally, row)
    st.class[pally] = {}
    for i = 1, math.min(#row, 9) do
        setClass(st, pally, i, tonumber(row:sub(i, i)))
    end
end

-- Returns true when the state changed in a way that matters.
-- norm (optional) maps a wire name to the roster's spelling (e.g. strips a realm suffix).
function PP.Parse(st, msg, sender, isLeader, norm)
    if type(msg) ~= "string" or type(sender) ~= "string" then return false end
    norm = norm or function(n) return n end
    sender = norm(sender)
    if msg == "REQ" then return false end

    local row = msg:match("^SELF %S*@(%S+)$")
    if row then setRow(st, sender, row) return true end

    local pally, rowP = msg:match("^PASSIGN (.+)@(%S+)$")
    if pally then
        pally = norm(pally)
        if not allowed(st, pally, sender, isLeader) then return false end
        setRow(st, pally, rowP)
        return true
    end

    local p2, ci, bi = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
    if p2 then
        p2 = norm(p2)
        if not allowed(st, p2, sender, isLeader) then return false end
        setClass(st, p2, tonumber(ci), tonumber(bi))
        return true
    end

    local p3, b3 = msg:match("^MASSIGN (.+) (%d+)$")
    if p3 then
        p3 = norm(p3)
        if not allowed(st, p3, sender, isLeader) then return false end
        for i = 1, 9 do setClass(st, p3, i, tonumber(b3)) end
        return true
    end

    local body = msg:match("^NASSIGN (.+)$")
    if body then
        local any = false
        for rec in body:gmatch("[^@]+") do
            local p, c, t, b = rec:match("^(%S+) (%d+) (%S+) (%d+)$")
            if p then
                p, t, b = norm(unwire(p)), norm(unwire(t)), tonumber(b)
                if allowed(st, p, sender, isLeader) then
                    st.normal[p] = st.normal[p] or {}
                    st.normal[p][t] = (b > 0) and b or nil
                    any = true
                end
            end
        end
        return any
    end

    if msg == "CLEAR" or msg == "CLEAR SKIP" then
        if isLeader then
            st.class, st.normal = {}, {}
        else
            st.class[sender], st.normal[sender] = nil, nil
        end
        return true
    end

    local free = msg:match("^FREEASSIGN (%a+)")
    if free then
        st.free[sender] = (free == "YES")
        return false
    end
    return false
end

function PP.Forget(st, pally)
    st.class[pally], st.normal[pally], st.free[pally] = nil, nil, nil
end

-- Family that `pally` plans to put on `targetName` (a member of `class`), or nil.
-- A per-player override (NASSIGN) wins over the class assignment.
function PP.PlannedFamily(st, pally, class, targetName)
    local n = st.normal[pally]
    if n and targetName and n[targetName] then return PP.BLESSING_FAMILY[n[targetName]] end
    local idx = PP.CLASS_INDEX[class or ""]
    local row = st.class[pally]
    local b = idx and row and row[idx]
    return b and PP.BLESSING_FAMILY[b] or nil
end

-- For one member: { [FAM] = paladinName } planned by OTHER paladins, and my own plan.
-- paladins = list of paladin names currently in the group (me excluded).
function PP.ForMember(st, member, myName, paladins)
    local planned
    for _, pally in ipairs(paladins) do
        local fam = PP.PlannedFamily(st, pally, member.class, member.name)
        if fam then
            planned = planned or {}
            if not planned[fam] then planned[fam] = pally end
        end
    end
    return planned, PP.PlannedFamily(st, myName, member.class, member.name)
end
