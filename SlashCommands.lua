-- SlashCommands.lua
-- Registers /rw (and /rankwarden) with a sub-command table.
-- Depends on: RankWarden.lua (Core), Debug.lua, Chat.lua, Messages.lua,
--             Session.lua, Sync.lua, Notify.lua

local RW = RankWarden

RW.Slash = {}
local SL = RW.Slash

local function P(msg) RW.Chat.Print(msg) end
local function W(msg) RW.Chat.Warn(msg) end

local function DBReady()
    if not RW.db then
        P("|cffff4444Addon not fully loaded yet — try again in a moment.|r")
        return false
    end
    return true
end

local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4444off|r" end

local function Toggle(key, label)
    return function()
        if not DBReady() then return end
        RW.db.profile[key] = not RW.db.profile[key]
        P(label .. ": " .. OnOff(RW.db.profile[key]))
    end
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local COMMANDS

local function PrintHelp()
    P("|cffffff00RankWarden " .. RW.VERSION .. "|r — commands:")
    local keys = {}
    for k in pairs(COMMANDS) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, name in ipairs(keys) do
        print(("  |cffffff00/rw %-9s|r  %s"):format(name, COMMANDS[name].desc))
    end
end

COMMANDS = {
    on = {
        desc = "Enable detection.",
        fn = function()
            if not DBReady() then return end
            RW.db.profile.enabled = true
            P("Detection: " .. OnOff(true))
        end,
    },
    off = {
        desc = "Disable detection.",
        fn = function()
            if not DBReady() then return end
            RW.db.profile.enabled = false
            P("Detection: " .. OnOff(false))
        end,
    },
    whisper = { desc = "Toggle whispering players (off = local chat only).", fn = Toggle("whisper", "Whispers") },
    maxlevel = { desc = "Toggle checking only max-level casters.", fn = Toggle("onlyMaxLevel", "Max-level only") },
    debug = { desc = "Toggle debug output (also re-alerts repeats).", fn = Toggle("debug", "Debug") },

    flavor = {
        desc = "[name]  List or set the notification wording.",
        fn = function(arg)
            if not DBReady() then return end
            if arg ~= "" and RW.Messages.IsFlavor(arg) then
                RW.db.profile.flavor = arg
                P("Flavor set to |cffffff00" .. arg .. "|r.")
                return
            end
            if arg ~= "" then W("Unknown flavor '" .. arg .. "'.") end
            P("Flavors (current: |cffffff00" .. RW.db.profile.flavor .. "|r):")
            local sample = { spell = "[Frostbolt]", rank = 3, level = 26, name = "Someone" }
            for _, name in ipairs(RW.Messages.FlavorNames()) do
                print("  |cffffff00" .. name .. "|r: " .. RW.Messages.Build("Whisper", sample, name))
            end
        end,
    },

    ignore = {
        desc = "Toggle ignoring your current target.",
        fn = function()
            if not DBReady() then return end
            local guid = UnitGUID("target")
            if not guid or not UnitIsPlayer("target") then
                W("Target a player first. Ignored: " .. Count(RW.db.profile.ignored))
                return
            end
            local name = UnitName("target")
            if RW.db.profile.ignored[guid] then
                RW.db.profile.ignored[guid] = nil
                P("No longer ignoring " .. name .. ".")
            else
                RW.db.profile.ignored[guid] = name
                P("Ignoring " .. name .. ".")
            end
        end,
    },

    downrank = {
        desc = "Toggle ignoring commonly downranked spells (heals, Frostbolt, ...).",
        fn = function()
            if not DBReady() then return end
            RW.db.profile.ignoreCommonDownranks = not RW.db.profile.ignoreCommonDownranks
            P("Ignore common downranks: " .. OnOff(RW.db.profile.ignoreCommonDownranks))
            for _, e in ipairs(RW.Ranks.COMMON_DOWNRANKS) do
                local on = RW.db.profile.commonDownranks[e.id] ~= false
                print(
                    ("  %s %s"):format(
                        on and "|cff00ff00[x]|r" or "|cffff4444[ ]|r",
                        RW.Ranks.SpellName(e.id) or e.label
                    )
                )
            end
        end,
    },

    allow = {
        desc = "<spell link|id>  Toggle ignoring every rank of a spell this session. No arg = list.",
        fn = function(arg, raw)
            if not DBReady() then return end
            local list = RW.Session.ignoredSpells
            local id = tonumber((raw or arg):match("|Hspell:(%d+)") or (raw or arg):match("^(%d+)$") or "")
            if not id then
                P("Ignored spells this session (any rank):")
                for sid in pairs(list) do
                    print("  " .. (RW.Ranks.SpellName(sid) or ("spell " .. sid)) .. " (" .. sid .. ")")
                end
                P("Usage: /rw allow <shift-click a spell>")
                return
            end
            local name = RW.Ranks.SpellName(id) or ("spell " .. id)
            if not RW.Ranks.Lookup(id) then W(name .. " isn't a tracked ranked ability.") end
            if list[id] then
                list[id] = nil
                P("Watching " .. name .. " again.")
            else
                list[id] = true
                P("Ignoring every rank of " .. name .. " for this session.")
            end
        end,
    },

    queue = {
        desc = "[clear|send]  Show, clear, or send queued whispers.",
        fn = function(arg)
            if arg == "clear" then
                P(("Cleared %d queued notifications."):format(RW.Notify.Clear()))
            elseif arg == "send" then
                RW.Notify.Flush()
            else
                P(("%d queued:"):format(#RW.Session.queue))
                for _, e in ipairs(RW.Session.queue) do
                    print("  " .. e.target .. " — " .. e.ability)
                end
            end
        end,
    },

    report = {
        desc = "[self|say|party|raid|guild]  Report this session's detections.",
        fn = function(arg)
            local channel = RW.Chat.REPORT_CHANNELS[arg ~= "" and arg or "self"]
            if not channel then
                W("Unknown channel '" .. arg .. "'.")
                return
            end
            local rows = RW.Session.report
            RW.Chat.Send(("RankWarden: %d outdated rank(s) this session."):format(#rows), channel)
            for _, r in ipairs(rows) do
                RW.Chat.Send(("%s — %s (Rank %d)"):format(r.name, r.spell, r.rank), channel)
            end
        end,
    },

    status = {
        desc = "Show settings, lead, and cache sizes.",
        fn = function()
            if not DBReady() then return end
            local p = RW.db.profile
            P(
                ("Detection %s · whispers %s · max-level only %s · flavor %s"):format(
                    OnOff(p.enabled),
                    OnOff(p.whisper),
                    OnOff(p.onlyMaxLevel),
                    p.flavor
                )
            )
            P(
                ("Lead: %s · announced %d · ignored players %d · ignored spells %d · queued %d"):format(
                    RW.Sync.Lead(),
                    Count(p.announced),
                    Count(p.ignored),
                    Count(RW.Session.ignoredSpells),
                    #RW.Session.queue
                )
            )
            P(
                ("Rank chains: %d · common downranks ignored: %s"):format(
                    #RW.AbilityGroups,
                    OnOff(p.ignoreCommonDownranks)
                )
            )
            local st = RW.Detector.stats
            P(
                ("Casts seen this session — yours: %d · group members: %d · hidden by the game: %d"):format(
                    st.own,
                    st.others,
                    RW.Detector.secretSkips
                )
            )
            local blocked, reason = RW.Chat.ChatBlocked()
            P("Addon chat: " .. (blocked and ("|cffff4444blocked (" .. reason .. ")|r") or "|cff00ff00allowed|r"))
        end,
    },

    clear = {
        desc = "Forget who has already been notified.",
        fn = function()
            if not DBReady() then return end
            local n = Count(RW.db.profile.announced)
            RW.db.profile.announced = {}
            RW.Session.Reset()
            P(("Cleared %d remembered notifications."):format(n))
        end,
    },

    reset = {
        desc = "Reset all settings to defaults.",
        fn = function()
            if not DBReady() then return end
            RW.db:ResetProfile()
            RW.Session.Reset()
            P("Settings reset.")
        end,
    },

    config = {
        desc = "Open the options panel.",
        fn = function()
            if RW.Options and RW.Options.Open then RW.Options.Open() end
        end,
    },

    help = { desc = "Show this list.", fn = function() PrintHelp() end },

    books = {
        desc = "Toggle mentioning ranks trainers don't sell (books, quests, drops).",
        fn = Toggle("bookRanks", "Book/quest rank notices"),
    },

    hud = { desc = "Toggle the lower-ranks HUD (grouped by player).", fn = function() RW.HUD.Toggle() end },

    hudlock = {
        desc = "Lock or unlock dragging the HUD.",
        fn = function()
            if not DBReady() then return end
            RW.db.profile.hud.locked = not RW.db.profile.hud.locked
            P("HUD locked: " .. OnOff(RW.db.profile.hud.locked))
        end,
    },

    hudreset = {
        desc = "Move the HUD back to its default spot.",
        fn = function()
            if not DBReady() then return end
            RW.HUD.ResetPosition()
            P("HUD position reset.")
        end,
    },

    watch = {
        desc = "Toggle printing every cast from your group (to check other players are seen).",
        fn = function()
            RW.db.profile.watch = not RW.db.profile.watch
            P(
                "Cast monitor: "
                    .. OnOff(RW.db.profile.watch)
                    .. (RW.db.profile.watch and "  — ask a group member to cast anything." or "")
            )
        end,
    },

    show = { desc = "Toggle the RankWarden window (same as plain /rw).", fn = function() RW.GUI.Toggle() end },

    minimap = {
        desc = "Show or hide the minimap button.",
        fn = function()
            if not DBReady() then return end
            local m = RW.db.profile.minimap
            m.hide = not m.hide
            if RW.GUI.PlaceMinimapButton then RW.GUI.PlaceMinimapButton() end
            P("Minimap button: " .. OnOff(not m.hide))
        end,
    },
}

SL.COMMANDS = COMMANDS

--- Dispatches "/rw <cmd> <arg>".
function SL.Handle(input)
    local cmd, raw = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    raw = raw or ""
    local arg = raw:lower()
    if cmd == "" then
        if RW.GUI and RW.GUI.Toggle then
            RW.Debug.SafeCall(RW.GUI.Toggle)
            return
        end
        cmd = "help"
    end

    local entry = COMMANDS[cmd]
    if not entry then
        W("Unknown command '" .. cmd .. "'.")
        PrintHelp()
        return
    end
    RW.Debug.SafeCall(entry.fn, arg, raw)
end

SLASH_RANKWARDEN1 = "/rw"
SLASH_RANKWARDEN2 = "/rankwarden"
SlashCmdList["RANKWARDEN"] = SL.Handle
