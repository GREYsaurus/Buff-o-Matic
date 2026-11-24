-- Buff-o-Matic: options panel (Settings > AddOns), minimap button and addon-compartment entry.
-- Nothing here touches secure frames except through RunOOC (scale), so it is combat-safe.
local _, ns = ...
local L = ns.L
local O = {}
ns.Options = O

local ICON = "Interface\\AddOns\\BuffOMatic\\Media\\icon"

local function changed() ns.RequestRefresh(true) end

-- key -> side effect after the value changes
local EFFECTS = {
    showMembers = function() ns.UI.Layout() changed() end,
    showOthers = changed, includeSelf = changed, sticky = changed, raid = changed,
    greaterMode = changed, memberButtons = changed, glow = changed,
    pallyPowerSync = function() changed() if ns.db.pallyPowerSync then ns.RequestPallyPower(true) end end,
}

---------------------------------------------------------------- widgets
local function header(parent, text, y)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetText(text)
    return y - 22
end

local function checkbox(parent, label, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 20, y)
    local text = cb.Text or cb.text
    if type(text) ~= "table" then text = nil end
    if not text then
        text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    text:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Refresh = function() cb:SetChecked(get() and true or false) end
    O.widgets[#O.widgets + 1] = cb
    return y - 26
end

local function number(parent, label, y, get, set)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", 26, y - 4)
    fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(60, 20)
    eb:SetPoint("TOPLEFT", 300, y)
    eb:SetAutoFocus(false)
    local function commit(self)
        local v = tonumber(self:GetText())
        if v then set(v) end
        self.Refresh()
        self:ClearFocus()
    end
    eb:SetScript("OnEnterPressed", commit)
    eb:SetScript("OnEditFocusLost", commit)
    eb:SetScript("OnEscapePressed", function(self) self.Refresh() self:ClearFocus() end)
    eb.Refresh = function() eb:SetText(tostring(get())) eb:SetCursorPosition(0) end
    O.widgets[#O.widgets + 1] = eb
    return y - 26
end

local function opt(key)
    return function() return ns.db[key] end, function(v)
        ns.db[key] = v
        if EFFECTS[key] then EFFECTS[key]() end
    end
end

local function round(v, step) return math.floor(v / step + 0.5) * step end

---------------------------------------------------------------- panel
function O.Build()
    if O.panel then return O.panel end
    O.widgets = {}
    local panel = CreateFrame("Frame")
    panel.name = L.TITLE
    O.panel = panel

    -- Scrollable content so the panel fits small screens / big UI scales.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    local p = CreateFrame("Frame", nil, scroll)
    p:SetSize(600, 760)
    scroll:SetScrollChild(p)

    local logo = p:CreateTexture(nil, "ARTWORK")
    logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", 16, -12)
    logo:SetTexture(ICON)
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -2)
    title:SetText(L.TITLE .. "  |cff9d9d9d" .. tostring(ns.VERSION) .. "|r")
    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(L.OPT_SUBTITLE)

    local y = -66
    y = header(p, L.OPT_ROTATION, y)
    for _, k in ipairs({ "includeSelf", "sticky", "raid", "greaterMode" }) do y = checkbox(p, L["OPT_" .. k], y, opt(k)) end

    y = header(p, L.OPT_TIMING, y - 6)
    y = number(p, L.OPT_refresh, y, function() return round(ns.db.refreshThreshold / 60, 0.5) end,
        function(v) if v > 0 and v <= 60 then ns.db.refreshThreshold = math.floor(v * 60 + 0.5) changed() end end)
    y = number(p, L.OPT_warn, y, function() return round(ns.db.warnThreshold / 60, 0.5) end,
        function(v) if v > 0 and v <= 60 then ns.db.warnThreshold = math.floor(v * 60 + 0.5) changed() end end)
    y = number(p, L.OPT_grace, y, function() return ns.db.graceSeconds end,
        function(v) if v >= 0 and v <= 300 then ns.db.graceSeconds = v changed() end end)

    y = header(p, L.OPT_ALERTS, y - 6)
    for _, k in ipairs({ "glow", "sound", "chatAlerts", "readyCheck" }) do y = checkbox(p, L["OPT_" .. k], y, opt(k)) end

    y = header(p, L.OPT_DISPLAY, y - 6)
    y = checkbox(p, L.OPT_shown, y, function() return not ns.db.hidden end, function(v) ns.UI.SetShown(v) end)
    for _, k in ipairs({ "locked", "showMembers", "showOthers", "memberButtons" }) do y = checkbox(p, L["OPT_" .. k], y, opt(k)) end
    y = checkbox(p, L.OPT_minimap, y, function() return not ns.db.minimap.hide end,
        function(v) ns.db.minimap.hide = not v O.UpdateMinimap() end)
    y = number(p, L.OPT_scale, y, function() return ns.db.scale or 1 end, function(v)
        if v >= 0.5 and v <= 2 then
            ns.db.scale = v
            ns.RunOOC("scale", function() ns.UI.frame:SetScale(v) end)
        end
    end)

    y = header(p, L.OPT_COORD, y - 6)
    y = checkbox(p, L.OPT_pallyPowerSync, y, opt("pallyPowerSync"))

    local kb = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    kb:SetPoint("TOPLEFT", 20, y - 10)
    kb:SetText(L.OPT_KEYBIND)

    panel:SetScript("OnShow", O.Refresh)
    return panel
end

function O.Refresh()
    for _, w in ipairs(O.widgets or {}) do w.Refresh() end
end

function O.Register()
    local panel = O.Build()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, L.TITLE)
        if ok and cat then
            pcall(Settings.RegisterAddOnCategory, cat)
            O.category = cat
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end

function O.Open()
    if not O.panel then O.Register() end
    if Settings and Settings.OpenToCategory and O.category then
        local id = O.category.GetID and O.category:GetID() or O.category.ID
        if pcall(Settings.OpenToCategory, id) then return end
    end
    if InterfaceOptionsFrame_OpenToCategory then
        if pcall(InterfaceOptionsFrame_OpenToCategory, O.panel) then return end
    end
    ns.Print(L.OPT_UNAVAILABLE)
end

---------------------------------------------------------------- minimap button (lib-free)
local function tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.TITLE)
    GameTooltip:AddLine(L.MM_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.MM_RIGHT, 1, 1, 1)
    if owner == O.minimap then GameTooltip:AddLine(L.MM_DRAG, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function onClick(button)
    if button == "RightButton" then O.Open() else ns.UI.Toggle() end
end

local function placeMinimap()
    local b = O.minimap
    if not b or not Minimap then return end
    local a = math.rad(ns.db.minimap.angle or 200)
    local r = (Minimap:GetWidth() or 140) / 2 + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function O.CreateMinimap()
    if O.minimap or not Minimap then return end
    local b = CreateFrame("Button", "BuffOMaticMinimapButton", Minimap)
    O.minimap = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ICON)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, button) onClick(button) end)
    b:SetScript("OnEnter", tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            placeMinimap()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    placeMinimap()
    O.UpdateMinimap()
end

function O.UpdateMinimap()
    if O.minimap then O.minimap:SetShown(not ns.db.minimap.hide) end
end

---------------------------------------------------------------- addon compartment (TOC hooks)
function BuffOMatic_OnAddonCompartmentClick(_, button)
    if not ns.enabled then ns.Print(L.NOT_PALADIN) return end
    onClick(button)
end
function BuffOMatic_OnAddonCompartmentEnter(_, frame)
    if frame then tooltip(frame) end
end
function BuffOMatic_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

ns.On("PLAYER_LOGIN", function()
    if not ns.enabled then return end
    O.Register()
    O.CreateMinimap()
end)
