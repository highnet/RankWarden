-- RankWarden.lua  (Core)
-- Creates the addon object via AceAddon-3.0 and mixes in AceConsole-3.0,
-- AceEvent-3.0 (event registration) and AceComm-3.0 (addon-to-addon sync).
-- Target: World of Warcraft: Forever (interface 16001, WOW_PROJECT_ID 18).
-- MUST be the first addon file in the TOC — all other modules reference RW.

local ADDON_VERSION = "1.0.0"

-- ─────────────────────────────────────────────────────────────────────────────
-- Addon object  (AceAddon calls OnInitialize / OnEnable automatically)
-- ─────────────────────────────────────────────────────────────────────────────
local RW = LibStub("AceAddon-3.0"):NewAddon("RankWarden", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0")

-- Expose globally so every module file can do:  local RW = RankWarden
RankWarden = RW

RW.VERSION = ADDON_VERSION
RW.NAME = "RankWarden"

-- ─────────────────────────────────────────────────────────────────────────────
-- AceDB profile defaults
-- ─────────────────────────────────────────────────────────────────────────────
RW.DB_DEFAULTS = {
    profile = {
        enabled = true,
        whisper = false, -- whisper group members (off by default: local chat only)
        onlyMaxLevel = false, -- only check casters at max level
        flavor = "default", -- notification wording, see Messages.lua
        debug = false,
        announced = {}, -- "guid-level-spellID" → true  (never repeat)
        ignored = {}, -- guid → name
        bookRanks = true, -- at max level, mention ranks trainers don't sell (books, quests, drops)
        ignoreCommonDownranks = true, -- skip heals & other spells people downrank on purpose
        commonDownranks = {}, -- rank-1 spellID → false to stop ignoring that one
        ignoredSpells = {}, -- spellID → true (any rank of that ability is skipped)
        history = {}, -- recent detections (Session.HISTORY_SIZE), newest last
        minimap = { hide = false, angle = 200 }, -- minimap button
        hud = {
            autoOpen = true,
            locked = false,
            shown = false,
            collapsed = false,
            scale = 1,
            point = { "RIGHT", "RIGHT", -60, 120 },
        },
        window = {}, -- main window size/position (AceGUI status table)
    },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- OnInitialize  —  called by AceAddon after SavedVariables are ready
-- ─────────────────────────────────────────────────────────────────────────────
function RW:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("RankWardenDB", RW.DB_DEFAULTS, true)

    RW.BuildRanks()

    if RW.Options and RW.Options.Setup then RW.Options.Setup() end

    if RW.GUI and RW.GUI.CreateMinimapButton then RW.Debug.SafeCall(RW.GUI.CreateMinimapButton) end
    if RW.HUD and RW.HUD.Restore then RW.Debug.SafeCall(RW.HUD.Restore) end

    RW.Chat.Print(
        "v" .. ADDON_VERSION .. " loaded.  |cffffff00/rw|r opens the window, |cffffff00/rw help|r lists commands."
    )
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BuildRanks  —  groups Forever's trainer spells into rank chains by name.
-- Some spell names may not be loaded at login; retry a few times.
-- ─────────────────────────────────────────────────────────────────────────────
local buildAttempts = 0
function RW.BuildRanks()
    buildAttempts = buildAttempts + 1
    local missing = RW.Ranks.Build()
    local groups = #RW.AbilityGroups
    RW.Debug.Msg(("Built %d rank chains (%d spell names not loaded yet)."):format(groups, missing))
    if missing > 0 and buildAttempts < 4 and C_Timer and C_Timer.After then C_Timer.After(5, RW.BuildRanks) end
    return groups, missing
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OnEnable  —  called by AceAddon once OnInitialize finishes
-- ─────────────────────────────────────────────────────────────────────────────
function RW:OnEnable()
    RW.Session.Reset()

    -- Forever has no combat log for addons: watch group members' casts instead.
    self:RegisterEvent(
        "UNIT_SPELLCAST_SUCCEEDED",
        function(event, unit, castGUID, spellID)
            RW.Debug.SafeCall(RW.Detector.OnSpellcast, event, unit, castGUID, spellID)
        end
    )

    -- Whispers queued during combat go out once it ends (or after a corpse run).
    local function flushSoon() RW.Notify.FlushSoon() end
    self:RegisterEvent("PLAYER_REGEN_ENABLED", flushSoon)
    self:RegisterEvent("PLAYER_ALIVE", flushSoon)
    self:RegisterEvent("PLAYER_UNGHOST", flushSoon)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", flushSoon) -- leaving a chat-restricted instance

    -- Coordinate with other RankWarden users so only one of us whispers.
    self:RegisterComm(
        RW.Sync.PREFIX,
        function(_, message, channel, sender) RW.Sync.OnComm(message, channel, sender) end
    )
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function() RW.Sync.Hello() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        RW.Sync.Hello()
        flushSoon()
    end)

    RW.Debug.Msg("Addon enabled — watching the combat log.")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- OnDisable
-- ─────────────────────────────────────────────────────────────────────────────
function RW:OnDisable() RW.Debug.Msg("Addon disabled.") end
