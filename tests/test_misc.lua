-- tests/test_misc.lua
-- Unit tests for Messages.lua, Sync.lua, Chat.lua, Debug.lua and SlashCommands.lua.

require("tests.bootstrap")

local RW = _G.RankWarden
local W = _G.__W

local function printedContains(text)
    for _, line in ipairs(W.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

describe("Messages", function()
    local M = RW.Messages
    local fields = { spell = "[Fireball]", rank = 3, level = 18, name = "Buddy" }

    it("fills placeholders", function() assert.are.equal("a 3 b", M.Fill("a {rank} b", fields)) end)

    it(
        "leaves unknown placeholders such as raid icons alone",
        function() assert.are.equal("{rt7} 3", M.Fill("{rt7} {rank}", fields)) end
    )

    it("builds every flavor and kind", function()
        for _, flavor in ipairs(M.FlavorNames()) do
            for _, kind in ipairs({ "Whisper", "Local", "Self", "WhisperBook", "LocalBook", "SelfBook" }) do
                local msg = M.Build(kind, fields, flavor)
                assert.is_truthy(msg:find("Fireball", 1, true))
                assert.is_falsy(msg:find("{spell}", 1, true))
            end
        end
    end)

    it(
        "falls back to the default flavor",
        function() assert.are.equal(M.Build("Local", fields, "default"), M.Build("Local", fields, "nope")) end
    )

    it("IsFlavor", function()
        assert.is_true(M.IsFlavor("short"))
        assert.is_false(M.IsFlavor("nope"))
    end)

    it("SpellLink falls back to the ID", function()
        local real = _G.C_Spell.GetSpellLink
        _G.C_Spell.GetSpellLink = nil
        assert.are.equal("spell 5", M.SpellLink(5))
        _G.C_Spell.GetSpellLink = real
    end)
end)

describe("Sync", function()
    local Y = RW.Sync

    before_each(function() _G.__freshDB() end)

    it("elects the alphabetically first user in the group", function()
        local inGroup = function(n) return n ~= "Absent" end
        assert.are.equal("Me", Y.ElectLead("Me", {}, inGroup))
        assert.are.equal("Bob", Y.ElectLead("Me", { Bob = true, Zed = true }, inGroup))
        assert.are.equal("Me", Y.ElectLead("Me", { Absent = true }, inGroup))
    end)

    it("records peers and answers a new HELLO", function()
        Y.OnComm("HELLO", "PARTY", "Bob-Realm")
        assert.is_true(Y.peers.Bob)
        assert.are.equal("ACK", W.comms[#W.comms].msg)
        assert.are.equal("Bob", Y.Lead())
    end)

    it("ignores its own messages", function()
        Y.OnComm("HELLO", "PARTY", "Me")
        assert.is_nil(Y.peers.Me)
    end)

    it("Hello broadcasts to the group and throttles", function()
        Y.lastHello = -math.huge
        W.time = 100
        Y.Hello()
        Y.Hello()
        assert.are.equal(1, #W.comms)
        assert.are.equal("PARTY", W.comms[1].channel)
    end)

    it("Hello forgets peers when solo", function()
        Y.peers = { Bob = true }
        W.inGroup = false
        Y.Hello()
        assert.is_nil(Y.peers.Bob)
    end)
end)

describe("Chat", function()
    before_each(function() _G.__freshDB() end)

    it("Send to SELF prints locally", function()
        RW.Chat.Send("hi", "SELF")
        assert.is_true(printedContains("hi"))
        assert.are.equal(0, #W.sent)
    end)

    it("Send reports API errors", function()
        local real = _G.SendChatMessage
        _G.SendChatMessage = function() error("boom") end
        assert.is_false(RW.Chat.Send("hi", "SAY"))
        _G.SendChatMessage = real
        assert.is_true(printedContains("boom"))
    end)

    it("Send rejects empty messages", function() assert.is_false(RW.Chat.Send("", "SAY")) end)
end)

describe("Debug", function()
    before_each(function() _G.__freshDB() end)

    it("SafeCall catches errors", function()
        local ok = RW.Debug.SafeCall(function() error("bad") end)
        assert.is_false(ok)
        assert.is_true(printedContains("bad"))
    end)

    it("SafeCall shows a stack trace in debug mode", function()
        RW.db.profile.debug = true
        RW.Debug.SafeCall(function() error("bad") end)
        assert.is_true(printedContains("Stack trace"))
    end)

    it("SafeCall rejects non-functions", function() assert.is_false((RW.Debug.SafeCall(42))) end)

    it("Msg only prints in debug mode", function()
        RW.Debug.Msg("quiet")
        assert.is_false(printedContains("quiet"))
        RW.db.profile.debug = true
        RW.Debug.Msg("loud")
        assert.is_true(printedContains("loud"))
    end)

    it("Assert", function()
        assert.is_true(RW.Debug.Assert(true))
        assert.is_false(RW.Debug.Assert(false, "nope"))
    end)
end)

describe("SlashCommands", function()
    local run = function(s) _G.SlashCmdList.RANKWARDEN(s) end

    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("registers /rw", function() assert.are.equal("/rw", _G.SLASH_RANKWARDEN1) end)

    it("help lists commands", function()
        run("help")
        assert.is_true(printedContains("/rw downrank"))
    end)

    it("plain /rw toggles the window", function()
        run("")
        assert.is_true(RW.GUI.IsShown())
        run("")
        assert.is_false(RW.GUI.IsShown())
        run("show")
        assert.is_true(RW.GUI.IsShown())
    end)

    it("watch toggles the cast monitor", function()
        assert.is_true(RW.db.profile.watch) -- on by default
        run("watch")
        assert.is_false(RW.db.profile.watch)
        assert.is_true(printedContains("Cast monitor"))
    end)

    it("minimap toggles the button setting", function()
        run("minimap")
        assert.is_true(RW.db.profile.minimap.hide)
    end)

    it("unknown commands warn", function()
        run("nope")
        assert.is_true(printedContains("Unknown command"))
    end)

    it("on / off", function()
        run("off")
        assert.is_false(RW.db.profile.enabled)
        run("on")
        assert.is_true(RW.db.profile.enabled)
    end)

    it("whisper, maxlevel, debug and downrank toggle", function()
        run("whisper")
        assert.is_true(RW.db.profile.whisper)
        run("maxlevel")
        assert.is_true(RW.db.profile.onlyMaxLevel)
        run("debug")
        assert.is_true(RW.db.profile.debug)
        run("downrank")
        assert.is_false(RW.db.profile.ignoreCommonDownranks)
        run("books")
        assert.is_false(RW.db.profile.bookRanks)
    end)

    it("flavor sets and lists", function()
        run("flavor short")
        assert.are.equal("short", RW.db.profile.flavor)
        run("flavor nope")
        assert.is_true(printedContains("Unknown flavor"))
    end)

    it("ignored spells live for the session, not in saved settings", function()
        run("allow 145")
        assert.is_true(RW.Session.ignoredSpells[145])
        assert.is_nil(RW.db.profile.ignoredSpells)
        RW.Session.whisperedTo["Buddy|1"] = true
        RW.UI.Reset() -- the HUD's Reset keeps session ignores and who was whispered
        assert.is_true(RW.Session.ignoredSpells[145])
        assert.is_true(RW.Session.whisperedTo["Buddy|1"])
    end)

    it("allow toggles a spell from a link", function()
        run("allow |cff71d5ff|Hspell:145:0|h[Fireball]|h|r")
        assert.is_true(RW.Session.ignoredSpells[145])
        run("allow 145")
        assert.is_nil(RW.Session.ignoredSpells[145])
        run("allow")
        assert.is_true(printedContains("Usage"))
    end)

    it("ignore needs a player target", function()
        run("ignore")
        assert.is_true(printedContains("Target a player"))
        W.target = { name = "Buddy", guid = "Player-1-BUDDY" }
        run("ignore")
        assert.are.equal("Buddy", RW.db.profile.ignored["Player-1-BUDDY"])
        run("ignore")
        assert.is_nil(RW.db.profile.ignored["Player-1-BUDDY"])
    end)

    it("queue shows, sends and clears", function()
        W.inCombat = true
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        run("queue")
        assert.is_true(printedContains("1 queued"))
        run("queue clear")
        assert.are.equal(0, #RW.Session.queue)
        run("queue send")
    end)

    it("report goes to the chosen channel", function()
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        run("report party")
        assert.are.equal("PARTY", W.sent[1].ch)
        run("report bogus")
        assert.is_true(printedContains("Unknown channel"))
    end)

    it("status, clear and reset", function()
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        run("status")
        assert.is_true(printedContains("Rank chains"))
        assert.is_true(printedContains("group members"))
        run("clear")
        assert.is_nil(next(RW.db.profile.announced))
        RW.db.profile.flavor = "short"
        run("reset")
        assert.are.equal("default", RW.db.profile.flavor)
    end)
end)

describe("Version", function()
    it("TOC and RankWarden.lua agree (the release workflow relies on it)", function()
        local toc = io.open("RankWarden.toc"):read("*a")
        assert.are.equal(_G.RankWarden.VERSION, toc:match("## Version:%s*(%S+)"))
    end)

    it("CHANGELOG.md has a section for the current version", function()
        local log = io.open("CHANGELOG.md"):read("*a")
        assert.is_truthy(log:find("## " .. _G.RankWarden.VERSION, 1, true))
    end)
end)

describe("Duplicate rank (Forever links already name the rank)", function()
    local M = RW.Messages
    local FOREVER = "|cff71d5ff|Hspell:8134:0|h[Lightning Shield (Rank 3)]|h|r"

    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("HasRank spots ranked links in any language, not plain ones", function()
        assert.is_true(M.HasRank(FOREVER))
        assert.is_true(M.HasRank("[Blitzschlagschild (Rang 3)]"))
        assert.is_true(M.HasRank("Lightning Shield (Rank 3)"))
        assert.is_false(M.HasRank("[Fireball]"))
        assert.is_false(M.HasRank("[Fireball (Arcane)]"))
        assert.is_false(M.HasRank(nil))
    end)

    it("WithRank only adds the rank when the link lacks it", function()
        assert.are.equal(FOREVER, M.WithRank(FOREVER, 3))
        assert.are.equal("[Fireball] (Rank 3)", M.WithRank("[Fireball]", 3))
        assert.are.equal("[Fireball] R3", M.WithRank("[Fireball]", 3, true))
        assert.are.equal("[Fireball]", M.WithRank("[Fireball]", nil))
    end)

    it("messages never repeat the rank", function()
        for _, flavor in ipairs(M.FlavorNames()) do
            for _, kind in ipairs({ "Whisper", "Local", "Self", "WhisperBook", "LocalBook", "SelfBook" }) do
                local msg = M.Build(kind, { spell = FOREVER, rank = 3, level = 32, name = "Zed" }, flavor)
                local _, ranks = msg:gsub("Rank 3", "")
                assert.is_true(ranks <= 1, flavor .. "/" .. kind .. ": " .. msg)
                assert.is_falsy(msg:find("R3", 1, true), flavor .. "/" .. kind .. ": " .. msg)
                assert.is_falsy(msg:find("{", 1, true) and msg:find("{spell", 1, true))
            end
        end
    end)

    it("HUD, window rows and history show the rank once", function()
        local rec = { name = "Sandy", spell = FOREVER, rank = 3, nextLevel = 32 }
        local hud = RW.HUD.FormatEntry(rec)
        assert.is_falsy(hud:find("R3", 1, true))
        assert.is_truthy(hud:find("Rank 3)", 1, true))
        local window = RW.GUI.FormatRecord(rec)
        local _, count = window:gsub("Rank 3", "")
        assert.are.equal(1, count)
        -- plain links still get the rank added
        assert.is_truthy(RW.HUD.FormatEntry({ spell = "[Fireball]", rank = 3 }):find("R3", 1, true))
    end)

    it("report lines and whisper entries show the rank once", function()
        local real = _G.C_Spell.GetSpellLink
        _G.C_Spell.GetSpellLink = function() return FOREVER end
        local e = RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        _G.C_Spell.GetSpellLink = real
        assert.are.equal(FOREVER, e.ability)
        local _, count = e.message:gsub("Rank 3", "")
        assert.are.equal(1, count)
        _G.SlashCmdList.RANKWARDEN("report party")
        local _, n = __W.sent[#__W.sent].msg:gsub("Rank 3", "")
        assert.are.equal(1, n)
    end)
end)

describe("API fallbacks and edge cases", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("SpellLink uses the old global on clients without C_Spell.GetSpellLink", function()
        local real = _G.C_Spell.GetSpellLink
        _G.C_Spell.GetSpellLink = nil
        _G.GetSpellLink = function(id) return "[old" .. id .. "]" end
        assert.are.equal("[old5]", RW.Messages.SpellLink(5))
        _G.GetSpellLink = nil
        _G.C_Spell.GetSpellLink = real
    end)

    it("FlushSoon waits with C_Timer when it exists", function()
        local delayed
        _G.C_Timer = {
            After = function(seconds, fn)
                delayed = seconds
                fn()
            end,
        }
        RW.db.profile.whisper = true
        __W.inCombat = true
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        __W.inCombat = false
        RW.Notify.FlushSoon()
        _G.C_Timer = nil
        assert.are.equal(RW.Notify.FLUSH_DELAY, delayed)
        assert.are.equal(1, #__W.sent)
    end)

    it("SpellName reads C_Spell.GetSpellInfo and requests unloaded spells", function()
        local requested
        _G.C_Spell.GetSpellInfo = function(id) return id == 1 and { name = "Blink" } or nil end
        _G.C_Spell.RequestLoadSpellData = function(id) requested = id end
        assert.are.equal("Blink", RW.Ranks.SpellName(1))
        assert.is_nil(RW.Ranks.SpellName(2))
        assert.are.equal(2, requested)
        _G.C_Spell.GetSpellInfo, _G.C_Spell.RequestLoadSpellData = nil, nil
    end)

    it("SpellName falls back to the old global, then to nil", function()
        _G.GetSpellInfo = function() return "Old Blink" end
        assert.are.equal("Old Blink", RW.Ranks.SpellName(1))
        _G.GetSpellInfo = nil
        assert.is_nil(RW.Ranks.SpellName(1))
    end)

    it("SpellRank reads the rank text from C_Spell or the old global", function()
        _G.C_Spell.GetSpellSubtext = function() return "Rank 4" end
        assert.are.equal(4, RW.Ranks.SpellRank(1))
        _G.C_Spell.GetSpellSubtext = nil
        _G.GetSpellSubtext = function() return "Rang 2" end
        assert.are.equal(2, RW.Ranks.SpellRank(1))
        _G.GetSpellSubtext = function() return "Racial" end
        assert.is_nil(RW.Ranks.SpellRank(1))
        _G.GetSpellSubtext = nil
        assert.is_nil(RW.Ranks.SpellRank(1))
    end)

    it("ranks with the same trainer level are ordered by spell ID", function()
        RW.TrainerSpells = { MAGE = { [20] = 10, [10] = 10 } }
        RW.ExplicitGroups, RW.LegacyRanked, RW.LegacyExcluded = {}, {}, {}
        RW.Ranks.Build(function() return "Blink" end, function() return nil end)
        assert.are.equal(1, RW.AbilityData[10].Rank)
        assert.are.equal(2, RW.AbilityData[20].Rank)
    end)

    it("slash commands wait until the database is ready", function()
        local db = RW.db
        RW.db = nil
        _G.SlashCmdList.RANKWARDEN("on")
        RW.db = db
        local seen = false
        for _, line in ipairs(__W.printed) do
            if line:find("not fully loaded", 1, true) then seen = true end
        end
        assert.is_true(seen)
    end)

    it("/rw allow lists session ignores by name", function()
        RW.Session.ignoredSpells[145] = true
        _G.SlashCmdList.RANKWARDEN("allow")
        local listed = false
        for _, line in ipairs(__W.printed) do
            if line:find("(145)", 1, true) then listed = true end
        end
        assert.is_true(listed)
    end)

    it("/rw config opens the options panel", function()
        local opened = false
        local real = RW.Options
        RW.Options = { Open = function() opened = true end }
        _G.SlashCmdList.RANKWARDEN("config")
        RW.Options = real
        assert.is_true(opened)
    end)

    it("plain /rw shows help when the window isn't available", function()
        local real = RW.GUI.Toggle
        RW.GUI.Toggle = nil
        _G.SlashCmdList.RANKWARDEN("")
        RW.GUI.Toggle = real
        local seen = false
        for _, line in ipairs(__W.printed) do
            if line:find("commands", 1, true) then seen = true end
        end
        assert.is_true(seen)
    end)

    it("spell tooltips work without a spell ID, and hide cleanly", function()
        local lines = {}
        local tip = _G.GameTooltip
        _G.GameTooltip = setmetatable({ AddLine = function(_, t) lines[#lines + 1] = t end }, {
            __index = function()
                return function() end
            end,
        })
        RW.UI.ShowSpellTooltip({}, { spell = "[Fireball]", rank = 2 })
        RW.UI.HideTooltip()
        _G.GameTooltip = nil
        RW.UI.ShowSpellTooltip({}, { spell = "[Fireball]" })
        RW.UI.ShowPlayerTooltip({}, { name = "A", entries = {} })
        RW.UI.HideTooltip()
        _G.GameTooltip = tip
        assert.are.equal("[Fireball]", lines[1])
    end)
end)
