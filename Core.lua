-- Wick's Demons and Things
-- Core.lua: WickCore addon object, saved variables, event dispatch, slash command.
--
-- Forever build. The cooldown and proc tracker is gone with Midnight rules.
-- What remains is the warlock's loadout: the soul bar (stones, shards, the
-- create spells), the pet bar with Incubus as its own summon, the shard
-- counter, and through WickCore the talent layer, pre-pull checklist and
-- racials.

local ADDON, ns = ...

local Core = WickCore
assert(Core, "Wick's Demons and Things requires WickCore. Enable the WickCore addon.")
local D, R = Core.Dialect, Core.Restrict

local BAR = function(x, y) return { point = "CENTER", x = x, y = y, hidden = false, locked = false } end
local PROFILE_DEFAULTS = {
    soul   = BAR(-180, 200),
    pet    = BAR(180, 200),
    cd     = BAR(0, 156),      -- kept for the UI lock/reset loops; no module behind it on Forever
    shard  = BAR(0, 240),
    ui     = { point = "CENTER", x = 0, y = 0 },
    kitWindow = {},
}

local A = Core:NewAddon("WicksDemonsAndThings", {
    title    = "Wick's Demons and Things",
    version  = "1.0.0",
    savedVar = "WicksDemonsSaved",
    defaults = { profile = PROFILE_DEFAULTS, char = {}, global = {} },
})

WicksDemons = WicksDemons or {}
local WD = WicksDemons
ns.WD = WD
WD.A = A
WD.ADDON = ADDON

-- Runtime aliases to the WickCore profile and character tables. The module
-- files address these names; they are not saved variables of their own.
WicksDemonsDB     = WicksDemonsDB     or {}
WicksDemonsCharDB = WicksDemonsCharDB or {}

local _, playerClass = UnitClass("player")
WD.playerClass = playerClass
WD.isWarlock   = (playerClass == "WARLOCK")
WD.SHARD_ITEM_ID = 6265

WD._listeners = {}
function WD:On(event, fn)
    self._listeners[event] = self._listeners[event] or {}
    table.insert(self._listeners[event], fn)
end
function WD:Emit(event, ...)
    local list = self._listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
    end
end

-- Spec through the trait system where it exists, the talent tabs elsewhere.
local WARLOCK_SPEC_BY_TAB = { "affliction", "demonology", "destruction" }
function WD:GetActiveSpec()
    if not self.isWarlock then return nil end
    if Core.Talents:IsAvailable() then
        local s = Core.Talents:Summary()
        if s and s.spent and #s.spent >= 3 then
            local best, bestPts = nil, -1
            for i, c in ipairs(s.spent) do
                if (c.spent or 0) > bestPts then best, bestPts = i, c.spent or 0 end
            end
            return bestPts > 0 and WARLOCK_SPEC_BY_TAB[best] or nil
        end
        return nil
    end
    if not GetNumTalentTabs or not GetTalentTabInfo then return nil end
    local ok, result = pcall(function()
        local maxIdx, maxPts = 0, -1
        for i = 1, GetNumTalentTabs() or 0 do
            local _, _, points = GetTalentTabInfo(i)
            if (points or 0) > maxPts then maxPts, maxIdx = points or 0, i end
        end
        return maxPts > 0 and WARLOCK_SPEC_BY_TAB[maxIdx] or nil
    end)
    return ok and result or nil
end

-- ============================================================
-- Lifecycle
-- ============================================================
function A:OnInitialize()
    WicksDemonsDB     = self.db.profile
    WicksDemonsCharDB = self.db.char
    WD.db = self.db
    self.db:On("OnProfileChanged", function()
        WicksDemonsDB = self.db.profile
        WD:Emit("PLAYER_TALENT_UPDATE")
    end)

    Core.Kit:New(self, {
        racials = true,
        checklist = {
            { label = "Demon armor",     aura = { "Demon Armor", "Demon Skin", "Fel Armor" }, cast = "Demon Skin" },
            { label = "Shadow Ward known", check = function() return D.IsSpellKnown(6229) or nil end },
            { label = "Healthstone",     item = 5512, min = 1, cast = "Create Healthstone" },
            { label = "Soulstone",       item = 5232, min = 1, cast = "Create Soulstone" },
            { label = "Soul shards",     item = 6265, min = 5 },
            { label = "Demon out",       check = function() return UnitExists("pet") and true or false end },
        },
    })
end

function A:OnEnable()
    if not WD.isWarlock then
        self:Print("loaded (non-warlock: viewer mode).")
    else
        self:Print("loaded. /wdt for options, /wdt kit for talents and checklist.")
    end
    WD:Emit("LOGIN")

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then self.kit:Toggle()
            elseif WD.UI then WD.UI:Toggle() end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Demons and Things"))
            tt:AddLine("Left-click: options   Right-click: talents and checklist", 0.5, 0.5, 0.5)
        end,
    })

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local y = O:Heading(page, "Wick's Demons and Things", 0)
        y = O:Note(page, "Bars are configured in the panel (/wdt). Talents, checklist and racials live in the kit (/wdt kit).", y)
        y = O:Button(page, "Open panel", function() if WD.UI then WD.UI:Toggle() end end, y, 100)
        y = O:Button(page, "Open kit", function() addon.kit:Toggle() end, y, 100)
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

-- ============================================================
-- Game events
-- ============================================================
local f = CreateFrame("Frame")
WD.eventFrame = f
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                     "BAG_UPDATE", "UNIT_PET", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
                     "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        WD.inCombat = true
        WD:Emit("COMBAT_START")
    elseif event == "PLAYER_REGEN_ENABLED" then
        WD.inCombat = false
        WD:Emit("COMBAT_END")
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        WD:Emit("PLAYER_TALENT_UPDATE")
    end
    WD:Emit(event, ...)
end)

-- ============================================================
-- Keybinding labels
-- ============================================================
BINDING_HEADER_WICKSDEMONS = "Wick's Demons and Things"
BINDING_NAME_WICKSDEMONS_TOGGLE_SOUL  = "Toggle soul bar"
BINDING_NAME_WICKSDEMONS_TOGGLE_PET   = "Toggle pet bar"
BINDING_NAME_WICKSDEMONS_TOGGLE_SHARD = "Toggle shard counter"
BINDING_NAME_WICKSDEMONS_TOGGLE_KIT   = "Toggle talents and checklist"

-- ============================================================
-- Slash command
-- ============================================================
A:RegisterSlash(function(_, input)
    input = (input or ""):lower()
    local function toggle(mod) if mod and mod.Toggle then mod:Toggle() end end
    local function reset(mod) if mod and mod.ResetPosition then mod:ResetPosition() end end

    if input == "" then if WD.UI then WD.UI:Toggle() end return end
    if input == "kit" or input == "talents" or input == "checklist" then A.kit:Toggle() return end
    if input == "help" or input == "?" then
        A:Print("commands")
        print("  /wdt             open options panel")
        print("  /wdt kit         talents, pre-pull checklist, racials")
        print("  /wdt soul        toggle soul bar")
        print("  /wdt pet         toggle pet bar")
        print("  /wdt shard       toggle shard counter")
        print("  /wdt lock|unlock lock or unlock all bars")
        print("  /wdt reset       reset all bar positions")
        print("  /wdt status      print diagnostic info")
        return
    end
    if input == "soul"  then toggle(WD.SoulBar)      return end
    if input == "pet"   then toggle(WD.PetBar)       return end
    if input == "shard" then toggle(WD.ShardCounter) return end
    if input == "lock" or input == "unlock" then
        for _, key in ipairs({ "soul", "pet", "cd", "shard" }) do
            WicksDemonsDB[key] = WicksDemonsDB[key] or {}
            WicksDemonsDB[key].locked = (input == "lock")
        end
        A:Print("bars " .. input .. "ed.")
        return
    end
    if input == "reset" then
        reset(WD.SoulBar); reset(WD.PetBar); reset(WD.ShardCounter)
        A:Print("positions reset.")
        return
    end
    if input == "status" then
        A:Print(("warlock: %s   spec: %s"):format(tostring(WD.isWarlock), tostring(WD:GetActiveSpec() or "(unknown)")))
        for _, key in ipairs({ "soul", "pet", "shard" }) do
            local cfg = WicksDemonsDB[key] or {}
            print(("  %s: hidden=%s locked=%s point=%s x=%d y=%d"):format(key, tostring(cfg.hidden), tostring(cfg.locked), cfg.point or "?", cfg.x or 0, cfg.y or 0))
        end
        if WD.ShardCounter and WD.ShardCounter.Count then print(("  shards: %d"):format(WD.ShardCounter:Count())) end
        A:Print("restrictions: " .. R:Summary())
        return
    end
    A:Print("unknown command. Try /wdt help")
end, "/wdt", "/wicksdemons")
