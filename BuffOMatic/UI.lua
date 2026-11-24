-- Buff-o-Matic: compact movable window, status text, member rows, tooltips.
-- Layout/show/hide/move of this window (it contains secure buttons) is protected, so it only
-- happens out of combat; in combat only text is updated.
local _, ns = ...
local UI = {}
ns.UI = UI
local L, C, B, T = ns.L, ns.Compat, ns.Blessings, ns.Thresholds
local R = ns.Roster

local WIDTH, ROW_H, MAX_ROWS = 270, 16, 10
local ICON = "Interface\\AddOns\\BuffOMatic\\Media\\icon"

local COLORS = {
    gold = "|cffffd100", green = "|cff40ff40", orange = "|cffff9900", red = "|cffff4040",
    grey = "|cff9d9d9d", white = "|cffffffff", blue = "|cff66bbff",
}

local function classColor(class)
    local c = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
    if c and c.GenerateHexColor then return "|c" .. c:GenerateHexColor() end
    local rc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if rc and rc.colorStr then return "|c" .. rc.colorStr end
    return COLORS.white
end

local function fam(f) return ns.FamilyName(f) end

---------------------------------------------------------------- reason formatting
function UI.ReasonText(d)
    if not d or not d.reason then return "" end
    local code = d.reason.code
    if code == "BEST" then
        return string.format(L.R_BEST, L["PSRC_" .. (d.prioritySource or "DEFAULT")])
    elseif code == "CASTER_UNKNOWN" then
        return string.format(L.R_CASTER_UNKNOWN, fam(d.reason.family))
    end
    return L["R_" .. code]
end

function UI.SkipText(sk)
    local by = sk.by or (sk.external and L.UNKNOWN_SOURCE) or L.UNKNOWN_PALADIN
    if sk.code == "SUPPLIED_BY" then return string.format(L.S_SUPPLIED_BY, fam(sk.family), by)
    elseif sk.code == "SUPPLIED_BY_EXPIRING" then
        return string.format(L.S_SUPPLIED_BY_EXPIRING, fam(sk.family), by, ns.FormatTime(sk.remaining))
    elseif sk.code == "ASSIGNED_SUPPLIED" then return string.format(L.S_ASSIGNED_SUPPLIED, fam(sk.family), by)
    elseif sk.code == "PLANNED_BY" then return string.format(L.S_PLANNED_BY, fam(sk.family), by)
    end
    return string.format(L["S_" .. sk.code], fam(sk.family))
end

function UI.BlockText(code) return L["B_" .. tostring(code)] end

local function thresholdText(eff)
    if not eff then return "" end
    if eff.short then
        return string.format(L.SHORT_POLICY, ns.FormatTime(eff.full), ns.FormatTime(eff.refresh), ns.FormatTime(eff.warn))
    end
    return string.format(L.THRESHOLDS, ns.FormatTime(eff.refresh), ns.FormatTime(eff.warn))
end

---------------------------------------------------------------- tooltips
local function memberTooltip(owner, m)
    if not m then return end
    local d = ns.decisions[m.guid]
    local now = GetTime()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(classColor(m.class) .. m.name .. "|r")
    GameTooltip:AddDoubleLine(L.TT_ROLE, (L["ROLE_" .. (m.role or "NONE")]) .. L["RSRC_" .. (m.roleSource or "NONE")], 1, 0.82, 0, 1, 1, 1)
    if m.excluded then GameTooltip:AddLine(L.ST_EXCLUDED, 0.6, 0.6, 0.6) end
    if d then
        if d.family then
            GameTooltip:AddDoubleLine(L.TT_INTENDED, fam(d.family), 1, 0.82, 0, 1, 1, 1)
        end
        local rt = UI.ReasonText(d)
        if rt ~= "" then GameTooltip:AddLine(rt, 0.8, 0.8, 0.8, true) end
        for _, sk in ipairs(d.skipped or {}) do
            GameTooltip:AddLine("- " .. UI.SkipText(sk), 0.7, 0.7, 0.7, true)
        end
        if d.eff then GameTooltip:AddLine(thresholdText(d.eff), 0.5, 0.7, 1, true) end
    end
    if m.mine then
        local rem = m.mine.expirationTime and (m.mine.expirationTime - now)
        GameTooltip:AddDoubleLine(L.TT_MINE, fam(m.mine.family) .. (m.mine.greater and (" (" .. L.TT_GREATER .. ")") or "") ..
            " " .. (rem and ns.FormatTime(rem) or L.TT_TIMER_UNKNOWN), 1, 0.82, 0, 1, 1, 1)
    end
    for f, o in pairs(m.others or {}) do
        local rem = o.expirationTime and (o.expirationTime - now)
        local by = o.casterKind == "unknown" and "?" or (o.casterName or (o.external and L.UNKNOWN_SOURCE) or L.UNKNOWN_PALADIN)
        GameTooltip:AddDoubleLine(L.TT_OTHERS, fam(f) .. " — " .. by .. " " .. (rem and ns.FormatTime(rem) or L.TT_TIMER_UNKNOWN), 1, 0.82, 0, 0.8, 0.8, 0.8)
    end
    local blk = ns.blocks[m.guid]
    if blk then GameTooltip:AddDoubleLine(L.TT_CAST, UI.BlockText(blk), 1, 0.82, 0, 1, 0.4, 0.4) end
    if m.stale then GameTooltip:AddLine(L.ROSTER_STALE, 1, 0.6, 0) end
    GameTooltip:AddLine(L.TT_HINT, 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function mainTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.SMART_BLESS)
    local a = ns.prepared
    if C.InCombat() then
        GameTooltip:AddLine(L.COMBAT_DISABLED, 1, 0.6, 0, true)
    elseif a then
        local m = R.members[a.guid]
        GameTooltip:AddLine(string.format(L.NEXT_FMT, a.spellName or fam(a.family), m and m.name or "?"), 1, 1, 1)
        local d = ns.decisions[a.guid]
        if d then
            GameTooltip:AddLine(UI.ReasonText(d), 0.8, 0.8, 0.8, true)
            for _, sk in ipairs(d.skipped or {}) do GameTooltip:AddLine("- " .. UI.SkipText(sk), 0.7, 0.7, 0.7, true) end
            if d.eff then GameTooltip:AddLine(thresholdText(d.eff), 0.5, 0.7, 1, true) end
        end
    else
        GameTooltip:AddLine(L.PARTY_BUFFED, 0.4, 1, 0.4)
    end
    if ns.greaterWhy and ns.db.greaterMode then
        local why = (tostring(L["G_" .. ns.greaterWhy]):gsub("%%s", "?"))
        GameTooltip:AddLine(L.TT_GREATER .. ": " .. why, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(L.TT_MAIN_HINT, 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

---------------------------------------------------------------- attention glow
-- A pulsing border around the window plus an action-button style glow on Smart Bless,
-- shown while someone is missing your blessing or one is due for a refresh. Purely
-- cosmetic textures (no secure attributes), so it is safe to toggle at any time.
local function pulse(region, from, to, dur)
    if not region.CreateAnimationGroup then return nil end
    local ag = region:CreateAnimationGroup()
    if not ag or not ag.CreateAnimation then return nil end
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(dur)
    if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
    return ag
end

function UI.CreateGlow(f, btn)
    local g = CreateFrame("Frame", nil, f, "BackdropTemplate")
    g:SetPoint("TOPLEFT", -4, 4)
    g:SetPoint("BOTTOMRIGHT", 4, -4)
    g:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    if g.SetBackdrop then
        g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
    end
    g:Hide()
    g.anim = pulse(g, 1, 0.15, 0.6)
    UI.glow = g

    local bg = btn:CreateTexture(nil, "OVERLAY")
    bg:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    bg:SetBlendMode("ADD")
    bg:SetPoint("CENTER")
    bg:SetSize(72, 72)
    bg:Hide()
    bg.anim = pulse(bg, 1, 0.3, 0.6)
    UI.buttonGlow = bg
end

local function setPulse(region, on)
    if not region then return end
    if on then
        if not region:IsShown() then
            region:Show()
            if type(region.anim) == "table" then region.anim:Play() end
        end
    elseif region:IsShown() then
        if type(region.anim) == "table" then region.anim:Stop() end
        region:Hide()
    end
end

-- urgent = someone is missing a blessing (red); otherwise a refresh is due (gold).
function UI.UpdateGlow(sum)
    if not UI.glow then return end
    local missing = #(sum.missing or {}) > 0
    local due = ns.prepared ~= nil or sum.warn
    local on = ns.db.glow and not C.InCombat() and (missing or due)
    if on and UI.glow.SetBackdropBorderColor then
        if missing then UI.glow:SetBackdropBorderColor(1, 0.2, 0.1, 1)
        else UI.glow:SetBackdropBorderColor(1, 0.8, 0.1, 1) end
        if missing then UI.buttonGlow:SetVertexColor(1, 0.35, 0.2) else UI.buttonGlow:SetVertexColor(1, 0.85, 0.3) end
    end
    UI.glowing = on and true or false
    setPulse(UI.glow, on)
    setPulse(UI.buttonGlow, on and ns.prepared ~= nil)
end

---------------------------------------------------------------- creation
function UI.Create()
    if UI.frame then return end
    local db = ns.db
    local f = CreateFrame("Frame", "BuffOMaticFrame", UIParent, "BackdropTemplate")
    UI.frame = f
    f:SetSize(WIDTH, 120)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.1, 0.85)
        f:SetBackdropBorderColor(0.85, 0.7, 0.2, 0.9)
    end
    f:SetScript("OnDragStart", function(self)
        if not ns.db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.db.point = { p, rp, x, y }
    end)

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(18, 18)
    logo:SetPoint("TOPLEFT", 8, -6)
    logo:SetTexture(ICON)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", logo, "RIGHT", 4, 0)
    title:SetText(L.TITLE)

    local btn = ns.SecureButton.CreateMain(f)
    btn:SetPoint("TOPLEFT", 8, -28)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON)
    btn.icon = icon
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    btn:SetScript("OnEnter", mainTooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local nextText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nextText:SetPoint("TOPLEFT", btn, "TOPRIGHT", 8, -1)
    nextText:SetWidth(WIDTH - 66)
    nextText:SetJustifyH("LEFT")
    nextText:SetWordWrap(false)
    UI.nextText = nextText

    local reason = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reason:SetPoint("TOPLEFT", nextText, "BOTTOMLEFT", 0, -3)
    reason:SetWidth(WIDTH - 66)
    reason:SetJustifyH("LEFT")
    reason:SetJustifyV("TOP")
    reason:SetHeight(24)
    UI.reason = reason

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -6)
    status:SetWidth(WIDTH - 16)
    status:SetJustifyH("LEFT")
    UI.status = status

    local others = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    others:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -2)
    others:SetWidth(WIDTH - 16)
    others:SetJustifyH("LEFT")
    UI.others = others

    UI.CreateGlow(f, btn)

    UI.rows = {}
    for i = 1, MAX_ROWS do
        local row = ns.SecureButton.CreateRow(f, i)
        row:SetSize(WIDTH - 16, ROW_H)
        local hlr = row:CreateTexture(nil, "HIGHLIGHT")
        hlr:SetAllPoints()
        hlr:SetColorTexture(1, 1, 1, 0.08)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 2, 0)
        row.name:SetWidth(120)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.fam = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.fam:SetPoint("LEFT", 124, 0)
        row.fam:SetWidth(60)
        row.fam:SetJustifyH("LEFT")
        row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.timer:SetPoint("RIGHT", -2, 0)
        row.timer:SetWidth(70)
        row.timer:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function(self) memberTooltip(self, self.member and R.members[self.member]) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        UI.rows[i] = row
    end
    UI.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    f:SetScale(db.scale or 1)
    f:ClearAllPoints()
    if db.point then
        f:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
    if db.hidden then f:Hide() end
    UI.Layout()
end

-- Protected: rows show/hide, frame height. Out of combat only.
function UI.Layout()
    if not UI.frame then return end
    ns.RunOOC("layout", function()
        local f = UI.frame
        local othersLines = UI.othersLines or 0
        local y = -28 - 40 - 6 - 14 - (othersLines > 0 and (othersLines * 12 + 4) or 0)
        UI.others:SetShown(othersLines > 0)
        local shown = 0
        local list = R.order
        if ns.db.showMembers then
            for i = 1, MAX_ROWS do
                local row = UI.rows[i]
                local m = list[i]
                if m then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y - (i - 1) * ROW_H)
                    row:Show()
                    shown = i
                else
                    row:Hide()
                end
            end
        else
            for i = 1, MAX_ROWS do UI.rows[i]:Hide() end
        end
        local extra = #list - MAX_ROWS
        UI.more:ClearAllPoints()
        if ns.db.showMembers and extra > 0 then
            UI.more:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y - shown * ROW_H)
            UI.more:SetText("+" .. extra)
            UI.more:Show()
        else
            UI.more:Hide()
        end
        local h = -y + shown * ROW_H + ((extra > 0 and ns.db.showMembers) and 14 or 0) + 8
        f:SetHeight(h)
        UI.layoutCount, UI.layoutOthers = shown, othersLines
    end)
end

-- Bind row secure actions to members (out of combat only).
function UI.PrepareRows()
    if not UI.rows or InCombatLockdown() then return end
    for i = 1, MAX_ROWS do
        local row, m = UI.rows[i], R.order[i]
        row.member = m and m.guid or nil
        local spell
        if m and ns.db.memberButtons then
            local d = ns.decisions[m.guid]
            local sp = d and d.family and ns.spells.known[d.family]
            spell = sp and sp.name
        end
        ns.SecureButton.SetRowAction(row, m and m.unit, spell)
    end
    local want = math.min(#R.order, MAX_ROWS)
    if want ~= UI.layoutCount then UI.Layout() end
end

---------------------------------------------------------------- update (text only)
function UI.Update()
    if not UI.frame then return end
    local now = GetTime()
    local sum = ns.summary or { missing = {}, others = {}, uncertain = 0 }
    local a = ns.prepared

    -- Next action: exactly what is bound to the button.
    if C.InCombat() then
        UI.nextText:SetText(COLORS.orange .. L.COMBAT_DISABLED .. "|r")
        UI.reason:SetText("")
        ns.mainButton.icon:SetTexture(ICON)
        ns.mainButton.icon:SetDesaturated(true)
    elseif a then
        local m = R.members[a.guid]
        local who = m and (classColor(m.class) .. m.name .. "|r") or "?"
        if a.greater then
            UI.nextText:SetText(string.format(L.GREATER_FMT, COLORS.gold .. fam(a.family) .. "|r", who, a.affectedCount or 0))
        else
            UI.nextText:SetText(string.format(L.NEXT_FMT, COLORS.gold .. fam(a.family) .. "|r", who))
        end
        local d = ns.decisions[a.guid]
        local txt = UI.ReasonText(d)
        if d and d.skipped and d.skipped[1] and (d.reason.code == "FALLBACK" or d.reason.code == "ASSIGNED" or d.reason.code == "PP_ASSIGNED") then
            for _, sk in ipairs(d.skipped) do
                if sk.code:find("SUPPLIED") or sk.code == "PLANNED_BY" then txt = UI.SkipText(sk) break end
            end
        end
        UI.reason:SetText(txt)
        ns.mainButton.icon:SetTexture(C.SpellIcon(a.spellID))
        ns.mainButton.icon:SetDesaturated(false)
    else
        local anyBlocked = ns.lastBlocked and #ns.lastBlocked > 0
        if anyBlocked then
            local b = ns.lastBlocked[1]
            local m = R.members[b.guid]
            UI.nextText:SetText(COLORS.grey .. L.WAITING .. "|r")
            UI.reason:SetText((m and m.name or "?") .. ": " .. tostring(UI.BlockText(b.code)))
        else
            UI.nextText:SetText(COLORS.green .. L.PARTY_BUFFED .. "|r")
            UI.reason:SetText("")
        end
        ns.mainButton.icon:SetTexture(ICON)
        ns.mainButton.icon:SetDesaturated(anyBlocked and true or false)
    end

    UI.UpdateGlow(sum)

    -- Status: missing state is separate from the timer, never hidden behind it.
    local parts = {}
    if #sum.missing > 0 then
        local names = {}
        for i = 1, math.min(3, #sum.missing) do names[i] = sum.missing[i].name end
        parts[#parts + 1] = COLORS.red .. L.MISSING_BLESSING .. ": " .. #sum.missing .. "|r " .. COLORS.grey .. "(" .. table.concat(names, ", ") .. ")|r"
    end
    if sum.shortest then
        local s = sum.shortest
        local label = s.member.name .. " " .. fam(s.family) .. " " .. ns.FormatTime(s.remaining)
        if sum.warn then
            parts[#parts + 1] = COLORS.orange .. L.REBUFF_SOON .. ":|r " .. label
        else
            parts[#parts + 1] = COLORS.green .. L.SHORTEST .. ":|r " .. label
        end
        if s.eff and s.eff.short then
            parts[#parts + 1] = COLORS.blue .. thresholdText(s.eff) .. "|r"
        end
    end
    if sum.uncertain > 0 then parts[#parts + 1] = COLORS.grey .. string.format(L.UNCERTAIN, sum.uncertain) .. "|r" end
    if ns.rosterStale then parts[#parts + 1] = COLORS.orange .. L.ROSTER_STALE .. "|r" end
    UI.status:SetText(table.concat(parts, "\n"))
    local statusLines = #parts

    -- Optional view of other paladins' expiring blessings.
    local olines = {}
    if ns.db.showOthers and #sum.others > 0 then
        olines[1] = COLORS.gold .. L.OTHERS_HEADER .. "|r"
        for i = 1, math.min(3, #sum.others) do
            local o = sum.others[i]
            olines[#olines + 1] = "  " .. fam(o.family) .. " — " .. o.member.name .. " (" .. (o.by or L.UNKNOWN_PALADIN) .. ") " .. ns.FormatTime(o.remaining)
        end
    end
    UI.others:SetText(table.concat(olines, "\n"))
    local wantLines = #olines + math.max(0, statusLines - 1)
    if wantLines ~= (UI.othersLines or 0) then
        UI.othersLines = wantLines
        UI.Layout()
    end

    -- Rows.
    for i = 1, MAX_ROWS do
        local row = UI.rows[i]
        local m = row.member and R.members[row.member]
        if m then
            local d = ns.decisions[m.guid]
            row.name:SetText(classColor(m.class) .. m.name .. "|r")
            local famText, timer = "", ""
            if d then
                famText = d.family and fam(d.family) or ""
                if d.status == "CAST" then
                    if d.castKind == "MISSING" then timer = COLORS.red .. L.ST_MISSING .. "|r"
                    elseif d.castKind == "REPLACE" then timer = COLORS.gold .. "> " .. fam(d.family) .. "|r"
                    else timer = COLORS.orange .. ns.FormatTime(m.mine and m.mine.expirationTime and (m.mine.expirationTime - now)) .. "|r" end
                    local blk = ns.blocks[m.guid]
                    if blk then timer = COLORS.grey .. UI.BlockText(blk) .. "|r" end
                elseif d.status == "HEALTHY" then
                    local rem = m.mine and m.mine.expirationTime and (m.mine.expirationTime - now)
                    local col = d.warn and COLORS.orange or COLORS.green
                    timer = col .. (rem and ns.FormatTime(rem) or L.ST_UNKNOWN) .. "|r"
                elseif d.status == "SKIP" then
                    timer = COLORS.grey .. L.ST_COVERED .. "|r"
                else
                    timer = COLORS.grey .. L.ST_UNKNOWN .. "|r"
                end
            end
            row.fam:SetText(famText)
            row.timer:SetText(timer)
        end
    end
end

---------------------------------------------------------------- right-click menu
-- Uses the modern MenuUtil API (present in the 12.x engine Forever runs on). Settings
-- changes are plain saved-variable writes, so this is safe in combat too; protected
-- re-preparation happens on the next out-of-combat refresh.
function UI.OpenMemberMenu(row)
    local m = row.member and R.members[row.member]
    if not m then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then ns.Print(L.MENU_UNAVAILABLE) return end
    local name = m.name
    local function opt(key)
        local pl = ns.db.players[name]
        return pl and pl[key]
    end
    local ok, err = pcall(MenuUtil.CreateContextMenu, row, function(_, root)
        root:CreateTitle(name)
        local roleMenu = root:CreateButton(L.MENU_ROLE)
        for _, r in ipairs({ { false, L.MENU_AUTO }, { "TANK", L.ROLE_TANK }, { "HEALER", L.ROLE_HEALER }, { "DAMAGER", L.ROLE_DAMAGER } }) do
            roleMenu:CreateRadio(r[2],
                function() return (opt("role") or false) == r[1] end,
                function() ns.SetPlayerOption(name, "role", r[1] or nil) end)
        end
        local famMenu = root:CreateButton(L.MENU_BLESSING)
        famMenu:CreateRadio(L.MENU_AUTO,
            function() return opt("assigned") == nil end,
            function() ns.SetPlayerOption(name, "assigned", nil) end)
        for _, f in ipairs(B.ORDER) do
            famMenu:CreateRadio(fam(f),
                function() return opt("assigned") == f end,
                function() ns.SetPlayerOption(name, "assigned", f) end)
        end
        root:CreateCheckbox(L.MENU_EXCLUDE,
            function() return opt("exclude") == true end,
            function() ns.SetPlayerOption(name, "exclude", not opt("exclude") or nil) end)
    end)
    if not ok then ns.Debug("menu error", err) ns.Print(L.MENU_UNAVAILABLE) end
end

function UI.SetShown(show)
    if not UI.frame then return end
    ns.db.hidden = not show
    ns.RunOOC("visibility", function() UI.frame:SetShown(show) end)
end

function UI.ResetPosition()
    ns.db.point = nil
    ns.RunOOC("position", function()
        UI.frame:ClearAllPoints()
        UI.frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end)
end

function UI.Toggle()
    if not UI.frame then return end
    UI.SetShown(ns.db.hidden == true)
end

-- Ready-check attention: pulse the border for a few seconds (cosmetic, combat-safe).
function UI.Flash()
    local f = UI.frame
    if not f or not f.SetBackdropBorderColor then return end
    if UI.flashTicker then UI.flashTicker:Cancel() end
    if ns.db.hidden then UI.SetShown(true) end
    local n = 0
    local ticker
    ticker = C_Timer.NewTicker(0.25, function()
        n = n + 1
        if n >= 16 then
            f:SetBackdropBorderColor(0.85, 0.7, 0.2, 0.9)
            ticker:Cancel()
            if UI.flashTicker == ticker then UI.flashTicker = nil end
        elseif n % 2 == 1 then
            f:SetBackdropBorderColor(1, 0.25, 0.1, 1)
        else
            f:SetBackdropBorderColor(1, 0.9, 0.3, 1)
        end
    end)
    UI.flashTicker = ticker
end
