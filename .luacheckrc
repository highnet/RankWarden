-- .luacheckrc
-- luacheck configuration for RankWarden (WoW: Forever, interface 16001).
-- Run: luacheck .

std = "lua51"

max_line_length = false

-- These globals are WRITTEN by the addon.
globals = {
    "RankWarden",
    "SlashCmdList",
    "SLASH_RANKWARDEN1",
    "SLASH_RANKWARDEN2",
}

-- WoW API / library globals that are read but never assigned by the addon.
read_globals = {
    "LibStub",
    "bit",
    "C_Spell",
    "C_Timer",
    "Settings",

    "C_ChatInfo",
    "issecretvalue",

    -- Unit API
    "UnitName",
    "UnitGUID",
    "UnitLevel",
    "UnitIsPlayer",
    "UnitExists",
    "UnitIsUnit",
    "UnitIsEnemy",
    "UnitIsCharmed",
    "UnitIsPossessed",
    "UnitIsDeadOrGhost",
    "UnitAffectingCombat",
    "UnitInBattleground",
    "UnitInParty",
    "UnitInRaid",
    "HasFullControl",
    "InCombatLockdown",
    "IsInGroup",
    "IsInRaid",
    "GetMaxPlayerLevel",
    "GetTime",

    -- Spell API
    "GetSpellInfo",      -- removed on Forever; kept as a fallback only
    "GetSpellLink",      -- removed on Forever; kept as a fallback only
    "GetSpellSubtext",   -- removed on Forever; kept as a fallback only

    -- Chat
    "SendChatMessage",

    -- Frames / UI
    "CreateFrame",
    "Minimap",
    "UIParent",
    "GameTooltip",
    "GameFontHighlight",
    "GetCursorPosition",
    "IsShiftKeyDown",
    "ChatEdit_InsertLink",
    "UnitClass",
    "C_ClassColor",
    "date",

    "debugstack",
    "print",
    "unpack",
}

ignore = {
    "212", -- unused argument — common in WoW event handlers
}

exclude_files = {
    "Libs/**",
    "tests/**",
    "AbilityData.lua", -- generated data table
    "tools/**",
    ".luarocks/**",    -- CI installs tools into the workspace
    ".lua/**",        -- vendored source data
}
