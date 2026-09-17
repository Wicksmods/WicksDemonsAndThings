-- Wick's Demons and Things
-- PetBar.lua: secure-action strip for pet summons + Demonology pet utility.
--   * Summon Imp / Voidwalker / Succubus / Felhunter — always shown if known.
--   * Summon Felguard / Soul Link / Sacrifice — Demonology-talented; filtered.
--   * Active-pet glow: highlights the summon button matching the current pet
--     (matched via UnitCreatureFamily("pet")).

local ADDON, ns = ...
local WD = WicksDemons
local D, R = WickCore.Dialect, WickCore.Restrict

WD.PetBar = {}
local PB = WD.PetBar

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local ICON_SIZE = 32
local ICON_GAP  = 3
local PADDING   = 5

-- ============================================================
-- Tracked pet actions
-- ============================================================
-- `family` = matched against UnitCreatureFamily("pet") for active-pet glow.
local PETS = {
    { spell = "Summon Imp",         short = "Imp",  family = "Imp",
      label = "Summon Imp" },
    { spell = "Summon Voidwalker",  short = "VW",   family = "Voidwalker",
      label = "Summon Voidwalker" },
    { spell = "Summon Succubus",    short = "Suc",  family = "Succubus",
      label = "Summon Succubus" },
    { spell = "Summon Felhunter",   short = "FH",   family = "Felhunter",
      label = "Summon Felhunter" },
    { spell = "Summon Felguard",    short = "FG",   family = "Felguard",
      label = "Summon Felguard" },
    { spell = "Soul Link",          short = "SL",   aura = "Soul Link",
      label = "Soul Link (toggle)" },
    { spell = "Sacrifice",          short = "Sac",
      label = "Sacrifice (consume pet for shield)" },
}

-- ============================================================
-- Brand chrome helpers
-- ============================================================
local function NewTexture(parent, layer, c)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if c then t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    return t
end

local function AddBorder(frame, c)
    c = c or C_BORDER
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT",    "TOPRIGHT",    nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT",    "BOTTOMLEFT",  1,   nil)
    edge("TOPRIGHT",   "BOTTOMRIGHT", 1,   nil)
end

local function AddCornerAccents(frame, arm, thick)
    arm = arm or 6
    thick = thick or 2
    local g = C_GREEN
    local function brk(anchor)
        local h = frame:CreateTexture(nil, "OVERLAY")
        h:SetColorTexture(g[1], g[2], g[3], 1)
        h:SetPoint(anchor); h:SetSize(arm, thick)
        local v = frame:CreateTexture(nil, "OVERLAY")
        v:SetColorTexture(g[1], g[2], g[3], 1)
        v:SetPoint(anchor); v:SetSize(thick, arm)
    end
    brk("TOPLEFT"); brk("TOPRIGHT"); brk("BOTTOMLEFT"); brk("BOTTOMRIGHT")
end

local function spellKnown(name)
    if not name or name == "" then return false end
    local info = D.GetSpellInfo(name)
    if not info then return false end
    if info.spellID and D.IsSpellKnown(info.spellID) then return true end
    -- Legacy clients: a cooldown query answers for spells the player knows.
    local cd = D.GetSpellCooldown(name)
    return cd ~= nil and cd.start ~= nil
end

-- Guarded: nil while auras are unreadable (any combat on Forever).
local function findAura(unit, name)
    if not unit or unit == "" then return nil end
    if unit ~= "player" and not UnitExists(unit) then return nil end
    local aura = D.GetAuraBySpellName(unit, name, "HELPFUL")
    if not aura then return nil end
    return aura.name, aura.applications or 0, aura.expirationTime or 0, aura.duration or 0
end

-- Cooldown values are secret in combat on Forever. Feed them to the widget
-- unconditionally and only decide "is it on cooldown" when they are plain.
local function applyCooldown(cdFrame, start, dur)
    if start == nil or dur == nil then cdFrame:Hide() return false end
    if R:IsSecret(start) or R:IsSecret(dur) then
        pcall(cdFrame.SetCooldown, cdFrame, start, dur); cdFrame:Show()
        return nil
    end
    if start > 0 and dur > 1.5 then
        cdFrame:SetCooldown(start, dur); cdFrame:Show()
        return true
    end
    cdFrame:Hide()
    return false
end


-- ============================================================
-- Bar construction
-- ============================================================
local function buildHost(count)
    local cfg = WicksDemonsDB.pet
    local barW = PADDING * 2 + math.max(1, count) * ICON_SIZE + math.max(0, count - 1) * ICON_GAP
    local barH = PADDING * 2 + ICON_SIZE

    local host = CreateFrame("Frame", "WicksDemonsPetBar", UIParent)
    host:SetFrameStrata("MEDIUM")
    host:SetFrameLevel(10)
    host:SetSize(barW, barH)
    host:ClearAllPoints()
    host:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    host:SetMovable(true)
    host:EnableMouse(true)
    host:SetClampedToScreen(true)
    host:RegisterForDrag("LeftButton")
    host:SetScript("OnDragStart", function(self)
        if cfg.locked then return end
        self:StartMoving()
    end)
    host:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        cfg.point, cfg.x, cfg.y = p, x, y
    end)

    NewTexture(host, "BACKGROUND", C_BG):SetAllPoints(host)
    AddBorder(host)
    AddCornerAccents(host)

    return host, cfg
end

-- Forward drags from a child button to the host frame, so the user can
-- grab the bar from anywhere (not only the 5px padding edge). Secure
-- buttons consume mouse-up via RegisterForClicks, which would otherwise
-- swallow the host's OnDragStop and leave the bar stuck to the cursor.
local function attachDragForward(button, host, cfg)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if cfg.locked then return end
        host:StartMoving()
    end)
    button:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        local p, _, _, x, y = host:GetPoint()
        cfg.point, cfg.x, cfg.y = p, x, y
    end)
end

local function buildButton(host, entry, index, cfg)
    local b = CreateFrame("Button", nil, host, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:SetPoint("TOPLEFT", host, "TOPLEFT",
        PADDING + (index - 1) * (ICON_SIZE + ICON_GAP), -PADDING)
    attachDragForward(b, host, cfg)
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", entry.spell)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local tex = GetSpellTexture and GetSpellTexture(entry.spell)
    if tex then icon:SetTexture(tex) else icon:SetColorTexture(0.1, 0.1, 0.15, 1) end
    b._icon = icon

    -- 1px frame
    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.85)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)

    -- Cooldown spiral (Fel Domination, etc.)
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(b)
    cd:SetDrawEdge(false)
    cd:SetSwipeColor(0, 0, 0, 0.7)
    b._cd = cd

    -- Active-pet / active-aura glow
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetColorTexture(C_GREEN[1], C_GREEN[2], C_GREEN[3], 0.45)
    glow:SetAllPoints(b)
    glow:Hide()
    b._glow = glow

    -- Tooltip
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(entry.label or entry.spell,
            C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        if entry.family then
            GameTooltip:AddLine("Pet summon", C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return b
end

-- ============================================================
-- Refresh
-- ============================================================
function PB:Refresh()
    if not self.icons then return end
    -- Skip the per-entry pet-family + aura + CD scan when the bar isn't on screen.
    if not self.host or not self.host:IsShown() then return end
    local petFamily = UnitExists("pet") and UnitCreatureFamily and UnitCreatureFamily("pet") or nil

    for _, e in ipairs(self.entries) do
        local b = self.icons[e]
        if b then
            local now = GetTime()
            local active = false

            if e.family and petFamily == e.family then
                active = true
            elseif e.aura and findAura("player", e.aura) then
                active = true
            end

            -- Cooldown
            local cd = D.GetSpellCooldown(e.spell)
            local onCD = applyCooldown(b._cd, cd and cd.start, cd and cd.duration)
            if onCD then
                if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                b._icon:SetVertexColor(0.45, 0.45, 0.45)
                b._glow:Hide()
            else
                if active then
                    b._glow:Show()
                    if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                    b._icon:SetVertexColor(1, 1, 1)
                else
                    b._glow:Hide()
                    if b._icon.SetDesaturated then b._icon:SetDesaturated(false) end
                    b._icon:SetVertexColor(1, 1, 1)
                end
            end
        end
    end
end

-- ============================================================
-- Init / lifecycle
-- ============================================================
function PB:Init()
    if self.initialized then return end
    if not WD.isWarlock then return end
    self.initialized = true

    -- Filter to known spells (talent-gated entries auto-disappear).
    local visible = {}
    for _, e in ipairs(PETS) do
        if spellKnown(e.spell) then table.insert(visible, e) end
    end
    self.entries = visible

    if #visible == 0 then return end

    local host, cfg = buildHost(#visible)
    self.host = host
    self.cfg  = cfg

    self.icons = {}
    for i, e in ipairs(visible) do
        self.icons[e] = buildButton(host, e, i, cfg)
    end

    if cfg.hidden then host:Hide() else host:Show() end

    if not self.poll then
        local f = CreateFrame("Frame")
        self.poll = f
        local accum = 0
        f:SetScript("OnUpdate", function(_, elapsed)
            accum = accum + elapsed
            if accum < 0.25 then return end
            accum = 0
            PB:Refresh()
        end)
    end

    self:Refresh()
end

function PB:Rebuild()
    if InCombatLockdown() then
        self._rebuildPending = true
        return
    end
    if not self.host then return self:Init() end

    if self.icons then
        for _, b in pairs(self.icons) do
            b:Hide(); b:ClearAllPoints(); b:SetParent(nil)
        end
    end
    self.icons = {}

    local visible = {}
    for _, e in ipairs(PETS) do
        if spellKnown(e.spell) then table.insert(visible, e) end
    end
    self.entries = visible

    local count = #visible
    local barW = PADDING * 2 + math.max(1, count) * ICON_SIZE + math.max(0, count - 1) * ICON_GAP
    self.host:SetWidth(barW)

    for i, e in ipairs(visible) do
        self.icons[e] = buildButton(self.host, e, i, self.cfg)
    end

    if not (self.cfg and self.cfg.hidden) then self.host:Show() end
    self:Refresh()
end

WD:On("COMBAT_END", function()
    if WD.PetBar and WD.PetBar._rebuildPending then
        WD.PetBar._rebuildPending = false
        WD.PetBar:Rebuild()
    end
end)

WD:On("UNIT_PET",              function() if PB.Refresh then PB:Refresh() end end)
WD:On("PLAYER_TALENT_UPDATE",  function() if PB.Rebuild then PB:Rebuild() end end)
WD:On("CHARACTER_POINTS_CHANGED", function() if PB.Rebuild then PB:Rebuild() end end)
WD:On("SPELLS_CHANGED",        function() if PB.Rebuild then PB:Rebuild() end end)
WD:On("LOGIN",                 function() PB:Init() end)

function PB:Show()  if self.host then self.host:Show(); self.cfg.hidden = false; self:Refresh() end end
function PB:Hide()  if self.host then self.host:Hide(); self.cfg.hidden = true  end end
function PB:Toggle() if self.host then if self.host:IsShown() then self:Hide() else self:Show() end end end
function PB:ResetPosition()
    if not self.cfg or not self.host then return end
    self.cfg.point = "CENTER"
    self.cfg.x = 180; self.cfg.y = 200
    self.host:ClearAllPoints()
    self.host:SetPoint("CENTER", UIParent, "CENTER", 180, 200)
    self.host:Show()
    self.cfg.hidden = false
end
