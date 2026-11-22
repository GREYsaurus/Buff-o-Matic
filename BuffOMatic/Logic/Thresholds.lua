-- Buff-o-Matic: refresh / warning thresholds, including the short-duration policy. Pure.
--
-- Default rules (requested):
--   refresh eligible  when remaining <  refreshThreshold (600 s)  -> 10:00 exactly is NOT eligible
--   "Rebuff soon"     when remaining <  warnThreshold    (300 s)  -> 5:00 exactly does NOT warn
--
-- Short-duration exception: if a blessing's FULL duration is <= refreshThreshold, the literal
-- rule would make a freshly applied buff immediately "due" (a rebuff loop). In that case:
--   refresh = min(refreshThreshold, full * shortRefreshPct)   (default 20%)
--   warn    = min(warnThreshold,    full * shortWarnPct)      (default 10%)
-- On WoW Forever every blessing lasts 60 min, so this branch is a safety net, not the norm.
local _, ns = ...
local T = {}
ns.Thresholds = T

function T.Effective(fullDuration, s)
    local refresh = s.refreshThreshold
    local warn = s.warnThreshold
    local short = false
    if fullDuration and fullDuration > 0 and fullDuration <= s.refreshThreshold then
        short = true
        refresh = math.min(refresh, fullDuration * s.shortRefreshPct)
        warn = math.min(warn, fullDuration * s.shortWarnPct)
    end
    return { refresh = refresh, warn = warn, short = short, full = fullDuration }
end

function T.NeedsRefresh(remaining, eff)
    return remaining ~= nil and remaining < eff.refresh
end

function T.ShouldWarn(remaining, eff)
    return remaining ~= nil and remaining < eff.warn
end
