-- Buff-o-Matic: saved settings defaults and access. Defaults table is pure (used by tests).
local _, ns = ...
local St = {}
ns.Settings = St

St.SCHEMA = 1

St.DEFAULTS = {
    schema = 1,
    -- rotation
    includeSelf = true,
    raid = false,                 -- party is the core; raid scanning is optional
    sticky = true,                -- keep my healthy existing blessing (no oscillation)
    -- timing (seconds)
    refreshThreshold = 600,       -- refresh when remaining < 10:00
    warnThreshold = 300,          -- "Rebuff soon" when shortest < 5:00
    shortRefreshPct = 0.20,       -- short-duration policy (full duration <= refreshThreshold)
    shortWarnPct = 0.10,
    graceSeconds = 30,            -- after a successful cast, never refresh that buff
    pendingTimeout = 3,           -- wait this long for the aura to appear
    backoffSeconds = 10,          -- skip a repeatedly failing target this long
    failThreshold = 2,
    othersExpiringThreshold = 600,
    -- greater
    greaterMode = false,
    greaterMinTargets = 2,
    -- alerts / UI
    sound = true,
    soundInterval = 60,
    chatAlerts = false,
    showOthers = true,
    showMembers = true,
    memberButtons = false,        -- secure per-member buttons (manual, also usable in combat)
    glow = true,                  -- pulse the window while a blessing is missing or due
    readyCheck = true,            -- sound + chat + flash on a ready check when blessings are missing
    pallyPowerSync = true,        -- read other paladins' PallyPower assignments
    minimap = { hide = false, angle = 200 },
    locked = false,
    scale = 1,
    point = nil,
    debug = false,
    -- user data
    players = {},                 -- [name] = { assigned=FAM, role=ROLE, priority={...}, exclude=bool }
    classRole = {},               -- [CLASS] = { [ROLE] = {...} }
}

local function deepcopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepcopy(x) end
    return t
end
St.DeepCopy = deepcopy

function St.Fresh()
    return deepcopy(St.DEFAULTS)
end

-- Fill missing keys (non-destructive), used on load.
function St.Merge(db)
    db = type(db) == "table" and db or {}
    for k, v in pairs(St.DEFAULTS) do
        if db[k] == nil then db[k] = deepcopy(v) end
    end
    db.schema = St.SCHEMA
    return db
end

function St.Get()
    return ns.db or St.DEFAULTS
end

function St.Player(name, create)
    local db = ns.db
    if not db or not name then return nil end
    local p = db.players[name]
    if not p and create then p = {} db.players[name] = p end
    return p
end
