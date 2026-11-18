-- RankWarden_Options.lua
-- Registers the Options > AddOns config panel via AceConfig-3.0 +
-- AceConfigDialog-3.0.
-- Depends on: every module above it in the TOC.

local RW = RankWarden

RW.Options = {}
local O = RW.Options

local function Get(key)
    return function() return RW.db.profile[key] end
end
local function Set(key)
    return function(_, v) RW.db.profile[key] = v end
end

local function FlavorValues()
    local values = {}
    for _, name in ipairs(RW.Messages.FlavorNames()) do
        values[name] = name
    end
    return values
end

O.TABLE = {
    type = "group",
    name = "RankWarden",
    args = {
        intro = {
            order = 1,
            type = "description",
            fontSize = "medium",
            name = "Watches your group's combat log for outdated spell ranks and lets the caster know.\n",
        },
        enabled = {
            order = 10,
            type = "toggle",
            width = "full",
            name = "Enable detection",
            get = Get("enabled"),
            set = Set("enabled"),
        },
        whisper = {
            order = 11,
            type = "toggle",
            width = "full",
            name = "Whisper players",
            desc = "Off: notifications only appear in your own chat frame.",
            get = Get("whisper"),
            set = Set("whisper"),
        },
        bookRanks = {
            order = 13,
            type = "toggle",
            width = "full",
            name = "Mention ranks trainers don't sell (books, quests, drops)",
            desc = "At max level, let players know a higher rank exists even though it comes from a book, quest or drop and they may not have it.",
            get = Get("bookRanks"),
            set = Set("bookRanks"),
        },
        onlyMaxLevel = {
            order = 12,
            type = "toggle",
            width = "full",
            name = "Only check max-level casters",
            get = Get("onlyMaxLevel"),
            set = Set("onlyMaxLevel"),
        },
        flavor = {
            order = 20,
            type = "select",
            name = "Notification wording",
            values = FlavorValues,
            get = Get("flavor"),
            set = Set("flavor"),
        },
        preview = {
            order = 21,
            type = "description",
            width = "full",
            name = function()
                local sample = { spell = "[Frostbolt]", rank = 3, level = 26, name = "Someone" }
                return "|cff888888Preview:|r " .. RW.Messages.Build("Whisper", sample, RW.db.profile.flavor) .. "\n"
            end,
        },
        downranks = {
            order = 25,
            type = "group",
            inline = true,
            name = "Commonly downranked spells",
            args = {
                ignoreCommonDownranks = {
                    order = 1,
                    type = "toggle",
                    width = "full",
                    name = "Ignore spells people downrank on purpose",
                    desc = "Lower ranks of these are often used to save mana or for utility.",
                    get = Get("ignoreCommonDownranks"),
                    set = Set("ignoreCommonDownranks"),
                },
                -- per-spell toggles are filled in by O.Setup()
            },
        },
        ignoredSpellsInfo = {
            order = 26,
            type = "description",
            width = "full",
            name = "|cff888888Ignore any other spell with |cffffff00/rw allow|r |cff888888+ shift-click it in your spellbook (lasts until you log out).|r\n",
        },
        hud = {
            order = 27,
            type = "group",
            inline = true,
            name = "Lower-ranks HUD",
            args = {
                show = {
                    order = 1,
                    type = "execute",
                    name = "Toggle HUD",
                    func = function() RW.HUD.Toggle() end,
                },
                reset = {
                    order = 2,
                    type = "execute",
                    name = "Reset position",
                    func = function() RW.HUD.ResetPosition() end,
                },
                autoOpen = {
                    order = 3,
                    type = "toggle",
                    width = "full",
                    name = "Open automatically when a lower rank is seen",
                    get = function() return RW.db.profile.hud.autoOpen end,
                    set = function(_, v) RW.db.profile.hud.autoOpen = v end,
                },
                locked = {
                    order = 4,
                    type = "toggle",
                    name = "Lock position",
                    get = function() return RW.db.profile.hud.locked end,
                    set = function(_, v) RW.db.profile.hud.locked = v end,
                },
                scale = {
                    order = 5,
                    type = "range",
                    name = "Scale",
                    min = 0.6,
                    max = 1.6,
                    step = 0.05,
                    get = function() return RW.db.profile.hud.scale end,
                    set = function(_, v)
                        RW.db.profile.hud.scale = v
                        if RW.HUD.frame then RW.HUD.frame:SetScale(v) end
                    end,
                },
            },
        },
        debug = {
            order = 30,
            type = "toggle",
            width = "full",
            name = "Debug output",
            get = Get("debug"),
            set = Set("debug"),
        },
        clear = {
            order = 40,
            type = "execute",
            name = "Forget notified players",
            confirm = true,
            confirmText = "Forget everyone who has already been notified?",
            func = function() RW.Slash.COMMANDS.clear.fn("") end,
        },
        credits = {
            order = 100,
            type = "description",
            fontSize = "small",
            name = "\n|cffffd100Created by Sandy Klawz — EU PvE|r  |cff888888(c) 2026 highnet, MIT|r\n\n"
                .. "|cffffffffCredits|r\n"
                .. "|cff888888• RankSentinel (MIT, (c) 2021 Gogo1951; maintained by SabreValkyrn / Valkyrn Studios): "
                .. "the original idea and the curated low-rank ability list.\n"
                .. "   RankSentinel thanks Gogo (data curation, Gogo's revised ability list), Aevala and Fathom "
                .. "(ability data feedback) and Splendiferus (testing), and was inspired by RankWatch, "
                .. "GogoWatch and SpellSnob.\n"
                .. "• What's Training? by Sveng (MIT): Forever trainer spell data.\n"
                .. "• Libraries: Ace3 (Ace3 Development Team), LibStub, CallbackHandler-1.0, ChatThrottleLib (Mikk).|r",
        },
    },
}

local function AddDownrankToggles()
    local args = O.TABLE.args.downranks.args
    for i, entry in ipairs(RW.Ranks.COMMON_DOWNRANKS) do
        local id = entry.id
        args["d" .. id] = {
            order = 10 + i,
            type = "toggle",
            width = 1.1,
            name = function() return RW.Ranks.SpellName(id) or entry.label end,
            disabled = function() return not RW.db.profile.ignoreCommonDownranks end,
            get = function() return RW.db.profile.commonDownranks[id] ~= false end,
            set = function(_, v)
                if v then
                    RW.db.profile.commonDownranks[id] = nil
                else
                    RW.db.profile.commonDownranks[id] = false
                end
            end,
        }
    end
end

function O.Setup()
    AddDownrankToggles()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("RankWarden", O.TABLE)
    O.frame, O.categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("RankWarden", "RankWarden")
end

function O.Open()
    if InCombatLockdown() then
        RW.Chat.Warn("Can't open options in combat.")
        return
    end
    if Settings and Settings.OpenToCategory and O.categoryID then
        Settings.OpenToCategory(O.categoryID)
    else
        LibStub("AceConfigDialog-3.0"):Open("RankWarden")
    end
end
