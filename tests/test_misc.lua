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
