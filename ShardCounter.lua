-- Wick's Demons and Things
-- ShardCounter.lua: small movable badge showing the warlock's soul shard count.
--   * Big OUTLINE number over the shard icon, brand chrome.
--   * Updates on BAG_UPDATE; tooltip shows total count.

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WD = WicksDemons
local D, R = WickCore.Dialect, WickCore.Restrict
local Chrome = WickCore.Chrome

WD.ShardCounter = {}
local SC = WD.ShardCounter

local C_BG          = { 0.051, 0.039, 0.078, 0.92 }
local C_BORDER      = { 0.220, 0.188, 0.345, 1 }
local C_GREEN       = { 0.310, 0.780, 0.471, 1 }
local C_TEXT_NORMAL = { 0.831, 0.784, 0.631, 1 }
local C_TEXT_DIM    = { 0.42, 0.35, 0.54, 1 }

local FRAME_W = 56
local FRAME_H = 56

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

-- ============================================================
-- Public API
-- ============================================================
function SC:Count()
    -- Bag items first (TBC and Forever both carry the shard item). Fall back
    -- to the soul-shard power type, which Forever declassified as a
    -- secondary resource, if the bag count is zero.
    local n = D.GetItemCount(WD.SHARD_ITEM_ID, false) or 0
    if n == 0 and UnitPower then
        local ok, p = pcall(UnitPower, "player", 7)
        if ok and type(p) == "number" and not R:IsSecret(p) then n = p end
    end
    return n
end

function SC:Refresh()
    if not self.frame or not self.text then return end
    local n = self:Count()
    self.text:SetText(tostring(n))
    -- Color by abundance: low = dim / red-tinted, healthy = cream, max = green
    if n == 0 then
        self.text:SetTextColor(0.85, 0.30, 0.30, 1)
    elseif n <= 3 then
        self.text:SetTextColor(C_TEXT_DIM[1] + 0.2, C_TEXT_DIM[2] + 0.2, C_TEXT_DIM[3] + 0.2, 1)
    elseif n >= 28 then
        -- Bag is a 32-slot soul bag; warn near cap
        self.text:SetTextColor(C_GREEN[1], C_GREEN[2], C_GREEN[3], 1)
    else
        self.text:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    end
end

-- ============================================================
-- Build
-- ============================================================
local function build()
    local cfg = WicksDemonsDB.shard

    local f = CreateFrame("Frame", "WicksDemonsShardCounter", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetSize(FRAME_W, FRAME_H)
    f:ClearAllPoints()
    f:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        -- A lock stops a nudge, not a deliberate move: shift overrides it.
        if not Chrome:DragAllowed(cfg.locked) then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint()
        cfg.point, cfg.x, cfg.y = p, x, y
    end)

    NewTexture(f, "BACKGROUND", C_BG):SetAllPoints(f)
    AddBorder(f)
    AddCornerAccents(f, 5, 2)

    -- Shard icon (faded background)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetVertexColor(1, 1, 1, 0.55)

    -- Big number, outlined
    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 22, "THICKOUTLINE")
    text:SetPoint("CENTER", 0, 0)
    text:SetTextColor(C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3], 1)
    text:SetText("0")

    -- "Shards" label
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\ARIALN.TTF", 9, "OUTLINE")
    lbl:SetPoint("BOTTOM", 0, 3)
    lbl:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3], 1)
    lbl:SetText("SHARDS")

    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Soul Shards", C_TEXT_NORMAL[1], C_TEXT_NORMAL[2], C_TEXT_NORMAL[3])
        GameTooltip:AddLine(("In bags: %d"):format(SC:Count()),
            C_GREEN[1], C_GREEN[2], C_GREEN[3])
        GameTooltip:AddLine("Drag to move", C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f, text, cfg
end

-- ============================================================
-- Lifecycle
-- ============================================================
function SC:Init()
    if self.initialized then return end
    if not WD.isWarlock then return end
    self.initialized = true

    local f, text, cfg = build()
    self.frame = f
    self.text  = text
    self.cfg   = cfg

    if cfg.hidden then f:Hide() else f:Show() end
    self:Refresh()
end

WD:On("LOGIN",      function() SC:Init() end)
WD:On("BAG_UPDATE", function() if SC.Refresh then SC:Refresh() end end)

function SC:Show()  if self.frame then self.frame:Show(); self.cfg.hidden = false end end
function SC:Hide()  if self.frame then self.frame:Hide(); self.cfg.hidden = true  end end
function SC:Toggle() if self.frame then if self.frame:IsShown() then self:Hide() else self:Show() end end end
function SC:ResetPosition()
    if not self.cfg or not self.frame then return end
    self.cfg.point = "CENTER"
    self.cfg.x = 0; self.cfg.y = 240
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 240)
    self.frame:Show()
    self.cfg.hidden = false
end
