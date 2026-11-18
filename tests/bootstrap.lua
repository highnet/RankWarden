-- tests/bootstrap.lua
-- Stubs every WoW global the addon touches, then loads the addon modules once.
-- Imported by each spec file with require("tests.bootstrap").
-- The _G.__RW_BOOTSTRAPPED guard ensures modules are only loaded a single time
-- even when multiple spec files require this file.

if _G.__RW_BOOTSTRAPPED then return end
_G.__RW_BOOTSTRAPPED = true

-- ─────────────────────────────────────────────────────────────────────────────
-- WoW API stubs  (tests override these per case; W holds the mutable world)
-- ─────────────────────────────────────────────────────────────────────────────
local W = {}
_G.__W = W

function _G.__resetWorld()
    W.printed = {}
    W.sent = {}
    W.comms = {}
    W.inCombat = false
    W.dead = false
    W.inBattleground = false
    W.inGroup = true
    W.inRaid = false
    W.levels = { ["Me"] = 40, ["Buddy"] = 40, ["Lowbie"] = 10 }
    W.unitCombat = {}
    W.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    W.units = {
        player = { guid = "Player-1-ME", name = "Me", level = 40 },
        party1 = { guid = "Player-1-BUDDY", name = "Buddy", level = 40, class = "MAGE" },
        raid2 = nil,
    }
    W.chatLockdown = false
    W.widgets = {}
    W.realmBlocked = false
    W.target = nil
end
_G.__resetWorld()

_G.unpack = _G.unpack or table.unpack -- WoW (Lua 5.1) global; Lua 5.2+ moved it
_G.debugstack = function() return "stub stacktrace\nline 2\nline 3" end
_G.print = function(msg) table.insert(W.printed, tostring(msg)) end
_G.SendChatMessage = function(msg, ch, _, target) table.insert(W.sent, { msg = msg, ch = ch, target = target }) end

_G.bit = {
    band = function(a, b)
        local r, bitv = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + bitv end
            a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
        end
        return r
    end,
}

_G.UnitName = function(unit)
    if unit == "target" then return W.target and W.target.name end
    local u = W.units[unit]
    if u then return u.name end
    return unit
end
_G.UnitGUID = function(unit)
    if unit == "target" then return W.target and W.target.guid end
    local u = W.units[unit]
    return u and u.guid
end
_G.UnitClass = function(unit)
    local u = W.units[unit]
    if not u then return nil end
    return u.class, u.class
end
_G.UnitIsPlayer = function(unit) return unit == "target" and W.target ~= nil end
_G.UnitLevel = function(unit)
    local base = unit:match("^(.-)target$")
    if base and base ~= "" and W.units[base] then return W.units[base].targetLevel end
    local u = W.units[unit]
    if u then return u.level end
    return W.levels[unit] or 0
end
_G.UnitIsEnemy = function() return false end
_G.UnitIsCharmed = function() return false end
_G.UnitIsPossessed = function() return false end
_G.UnitIsDeadOrGhost = function() return W.dead end
_G.UnitAffectingCombat = function(name) return W.unitCombat[name] or false end
_G.UnitInBattleground = function() return W.inBattleground and 1 or nil end
_G.UnitInParty = function() return true end
_G.UnitInRaid = function() return nil end
_G.HasFullControl = function() return true end
_G.InCombatLockdown = function() return W.inCombat end
_G.IsInGroup = function() return W.inGroup end
_G.IsInRaid = function() return W.inRaid end
_G.GetMaxPlayerLevel = function() return 60 end
_G.GetTime = function() return W.time or 0 end
_G.C_Spell = {
    GetSpellLink = function(id) return "[spell" .. id .. "]" end,
    GetSpellTexture = function(id) return id ~= 424242 and 136000 or nil end,
}
_G.C_ClassColor = {
    GetClassColor = function(class)
        if class == "NOCOLOR" then return nil end
        return { WrapTextInColorCode = function(_, text) return "|cffabcdef" .. text .. "|r" end }
    end,
}
_G.IsShiftKeyDown = function() return W.shift end
_G.ChatEdit_InsertLink = function(link) W.linked = link end
_G.C_ChatInfo = {
    SendChatMessage = function(...) return _G.SendChatMessage(...) end,
    InChatMessagingLockdown = function() return W.chatLockdown end,
    AreOutgoingAddonChatMessagesRestricted = function() return W.realmBlocked end,
}
-- Units: W.units[token] = { guid, name, level, targetLevel }
_G.UnitExists = function(unit)
    if unit:match("target$") and unit ~= "target" then
        local u = W.units[unit:gsub("target$", "")]
        return u ~= nil and u.targetLevel ~= nil
    end
    return W.units[unit] ~= nil
end
_G.UnitIsUnit = function(a, b) return W.units[a] ~= nil and W.units[a] == W.units[b] end
_G.issecretvalue = function(v) return v == W.SECRET end
_G.SlashCmdList = {}

-- Fake AceGUI: every widget accepts any method; a few behave like the real thing
-- so the window code (GUI.lua) can be exercised headlessly.
local FakeWidget = {}
local function NewWidget(kind)
    local w = { kind = kind, children = {}, callbacks = {}, props = {} }
    return setmetatable(w, FakeWidget)
end
FakeWidget.__index = function(_, key)
    if FakeWidget.methods[key] then return FakeWidget.methods[key] end
    return function(self, value) self.props[key] = value end -- SetText, SetLabel, ...
end
FakeWidget.methods = {
    AddChild = function(self, child) table.insert(self.children, child) end,
    ReleaseChildren = function(self) self.children = {} end,
    SetCallback = function(self, name, fn) self.callbacks[name] = fn end,
    Fire = function(self, name, ...)
        if self.callbacks[name] then self.callbacks[name](self, name, ...) end
    end,
    SelectTab = function(self, value) self:Fire("OnGroupSelected", value) end,
    Hide = function(self) self:Fire("OnClose") end,
}
W.widgets = {}
local FakeAceGUI = {
    Create = function(_, kind)
        local w = NewWidget(kind)
        w.frame = {}
        table.insert(W.widgets, w)
        return w
    end,
    Release = function() end,
}
local FakeConfigDialog =
    { Open = function(_, app, container) W.configOpened = { app = app, container = container } end }

_G.LibStub = function(name)
    if name == "AceGUI-3.0" then return FakeAceGUI end
    if name == "AceConfigDialog-3.0" then return FakeConfigDialog end
    return { NewAddon = function() return {} end }
end
_G.UISpecialFrames = {}
-- Fake frames for HUD.lua / the minimap button: any method works; a few keep state.
local FakeFrame = {}
FakeFrame.methods = {
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetShown = function(self, v) self.shown = v and true or false end,
    SetScript = function(self, name, fn) self.scripts[name] = fn end,
    GetScript = function(self, name) return self.scripts[name] end,
    SetPoint = function(self, ...) self.point = { ... } end,
    GetPoint = function(self)
        local p = self.point or {}
        return p[1], p[2], p[3] and "CENTER" or nil, p[4] or 0, p[5] or 0
    end,
    SetText = function(self, t) self.text = t end,
    GetText = function(self) return self.text end,
    SetHeight = function(self, h) self.height = h end,
    CreateFontString = function(self) return _G.CreateFrame("FontString", nil, self) end,
    CreateTexture = function(self) return _G.CreateFrame("Texture", nil, self) end,
    GetEffectiveScale = function() return 1 end,
    GetParent = function(self) return self.parent end,
    GetCenter = function() return 0, 0 end,
}
FakeFrame.__index = function(_, key)
    return FakeFrame.methods[key] or function() end
end
_G.CreateFrame = function(kind, name, parent)
    local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, shown = true }, FakeFrame)
    if name then _G[name] = f end
    return f
end
_G.UIParent = _G.CreateFrame("Frame")
_G.Minimap = _G.CreateFrame("Frame")
_G.GameTooltip = _G.CreateFrame("GameTooltip")
_G.GetCursorPosition = function() return 0, 80 end
_G.date = os.date

-- ─────────────────────────────────────────────────────────────────────────────
-- Load addon modules (TOC order). Must be run from the addon root directory.
-- ─────────────────────────────────────────────────────────────────────────────
dofile("RankWarden.lua")
local RW = _G.RankWarden

function RW:SendCommMessage(prefix, msg, channel, target)
    table.insert(W.comms, { prefix = prefix, msg = msg, channel = channel, target = target })
end

dofile("Debug.lua")
dofile("Chat.lua")
dofile("AbilityData.lua")
dofile("Ranks.lua")
dofile("Messages.lua")
dofile("Session.lua")
dofile("Sync.lua")
dofile("Notify.lua")
dofile("Detector.lua")
dofile("SlashCommands.lua")
dofile("UI.lua")
dofile("HUD.lua")
dofile("GUI.lua")

-- Keep the real generated data around; fixtures replace it per test.
RW.__realData = {
    TrainerSpells = RW.TrainerSpells,
    ExplicitGroups = RW.ExplicitGroups,
    LegacyRanked = RW.LegacyRanked,
    LegacyExcluded = RW.LegacyExcluded,
}

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do
        c[k] = deepcopy(v)
    end
    return c
end

--- Call in before_each to reset DB + session + world state between tests.
function _G.__freshDB()
    RW.db = deepcopy(RW.DB_DEFAULTS)
    RW.db.ResetProfile = function(self) self.profile = deepcopy(RW.DB_DEFAULTS.profile) end
    RW.Session.Reset()
    RW.Session.ignoredSpells = {}
    RW.Session.ignoredPlayerSpells = {}
    RW.Session.whisperedTo = {}
    RW.Sync.peers = {}
    RW.Detector.ResetStats()
    if RW.GUI.frame then RW.GUI.Close() end
    RW.HUD.frame = nil
    RW.GUI.minimapButton = nil
    _G.__resetWorld()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Fixture: a tiny Forever-like dataset with known names and ranks.
-- ─────────────────────────────────────────────────────────────────────────────
_G.__FIXTURE_NAMES = {
    [133] = "Fireball",
    [143] = "Fireball",
    [145] = "Fireball",
    [3140] = "Fireball",
    [116] = "Frostbolt",
    [205] = "Frostbolt",
    [837] = "Frostbolt",
    [8946] = "Cure Poison",
    [526] = "Cure Poison",
    [5487] = "Bear Form",
    [9634] = "Dire Bear Form",
    [3420] = "Crippling Poison",
    [3421] = "Crippling Poison",
    [900001] = "Starfall",
    [900002] = "Starfall",
    [700001] = "Frost Nova",
    [700002] = "Frost Nova",
    [800001] = "Shadow Bolt",
    [800002] = "Shadow Bolt",
    [800003] = "Shadow Bolt",
}

-- "Rank N" text: only Shadow Bolt and Frost Nova have it (the rest order by trainer level).
_G.__FIXTURE_RANKS = { [800001] = 1, [800002] = 2, [800003] = 3, [700001] = 1, [700002] = 2 }

function _G.__useFixture()
    RW.TrainerSpells = {
        MAGE = {
            [133] = 1,
            [143] = 6,
            [145] = 12,
            [3140] = 18,
            [116] = 4,
            [205] = 8,
            [837] = 14,
            [700001] = 0,
            [700002] = 30,
        },
        DRUID = { [8946] = 14, [5487] = 10, [9634] = 40, [900001] = 20, [900002] = 30 },
        SHAMAN = { [526] = 16 },
        ROGUE = { [3420] = 20, [3421] = 50 },
        WARLOCK = { [800001] = 1, [800002] = 50, [800003] = 0 }, -- rank 3 comes from a book
    }
    RW.ExplicitGroups = { { class = "DRUID", { 5487, 1 }, { 9634, 2 } } }
    RW.LegacyRanked = { [133] = true, [143] = true, [116] = true, [5487] = true }
    RW.LegacyExcluded = { [3420] = true, [3421] = true, [8946] = true, [526] = true }
    return RW.Ranks.Build(
        function(id) return _G.__FIXTURE_NAMES[id] end,
        function(id) return _G.__FIXTURE_RANKS[id] end
    )
end

_G.__freshDB()
