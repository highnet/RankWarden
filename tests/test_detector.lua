-- tests/test_detector.lua
-- Unit tests for Detector.lua + Notify.lua — the cast → notification pipeline.

require("tests.bootstrap")

local RW = _G.RankWarden
local DT = RW.Detector
local W = _G.__W

local BUDDY = "Player-1-BUDDY"
local castN = 0

local function evaluate(spellID, guid, name, level, targetLevel)
    return DT.Evaluate(spellID, guid or BUDDY, name or "Buddy", level or 40, targetLevel)
end

--- Fires UNIT_SPELLCAST_SUCCEEDED with a fresh cast GUID.
local function spellcast(unit, spellID, castGUID)
    castN = castN + 1
    return DT.OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", unit, castGUID or ("Cast-" .. castN), spellID)
end

describe("Detector", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
        DT.ResetRecent()
        DT.secretSkips = 0
    end)

    describe("Evaluate", function()
        it("prints locally (no whisper) by default", function()
            local e = evaluate(145)
            assert.is_table(e)
            assert.is_false(e.isWhisper)
            assert.are.equal(0, #W.sent)
            assert.is_truthy(W.printed[#W.printed]:find("Buddy"))
        end)

        it("whispers when enabled and we are lead", function()
            RW.db.profile.whisper = true
            local e = evaluate(145)
            assert.is_true(e.isWhisper)
            assert.are.equal(1, #W.sent)
            assert.are.equal("WHISPER", W.sent[1].ch)
            assert.are.equal("Buddy", W.sent[1].target)
        end)

        it("prints locally instead of whispering when another user is lead", function()
            RW.db.profile.whisper = true
            RW.Sync.peers = { ["Aaron"] = true }
            local e = evaluate(145)
            assert.is_false(e.isWhisper)
            assert.are.equal(0, #W.sent)
        end)

        it("uses the self message for your own casts", function()
            local e = evaluate(145, "Player-1-ME", "Me")
            assert.is_false(e.isWhisper)
            assert.is_truthy(e.message:find("^You used"))
        end)

        it("notifies once per ability per session", function()
            assert.is_table(evaluate(145))
            assert.is_nil(evaluate(143))
        end)

        it("does not repeat across sessions at the same level", function()
            assert.is_table(evaluate(145))
            RW.Session.Reset()
            assert.is_nil(evaluate(145))
        end)

        it("debug mode re-alerts", function()
            RW.db.profile.debug = true
            assert.is_table(evaluate(145))
            assert.is_table(evaluate(145))
        end)

        it("ignores ignored players", function()
            RW.db.profile.ignored[BUDDY] = "Buddy"
            assert.is_nil(evaluate(145))
        end)

        it("ignores commonly downranked spells", function() assert.is_nil(evaluate(205)) end)

        it("ignores spells the user allowed", function()
            RW.Session.ignoredSpells[133] = true
            assert.is_nil(evaluate(145))
        end)

        it("respects max-level-only mode", function()
            RW.db.profile.onlyMaxLevel = true
            assert.is_nil(evaluate(145))
        end)

        it("skips players who leveled up this session", function()
            RW.Session.levelSeen[BUDDY] = 39
            assert.is_nil(evaluate(145))
        end)

        it("skips unknown levels", function() assert.is_nil(evaluate(145, nil, nil, 0)) end)

        it("does nothing when disabled", function()
            RW.db.profile.enabled = false
            assert.is_nil(evaluate(145))
        end)

        it("tells max-level players about book/quest ranks", function()
            local e = evaluate(800002, nil, nil, 60)
            assert.is_table(e)
            assert.is_truthy(e.message:find("book", 1, true))
            assert.is_true(RW.Session.report[1].book)
        end)

        it("whispers book/quest heads-ups too", function()
            RW.db.profile.whisper = true
            evaluate(800002, nil, nil, 60)
            assert.is_truthy(W.sent[1].msg:find("trainers don't sell it", 1, true))
        end)

        it("book notices can be turned off", function()
            RW.db.profile.bookRanks = false
            assert.is_nil(evaluate(800002, nil, nil, 60))
        end)

        it("per-player ignores only skip that player", function()
            RW.Session.ignoredPlayerSpells[RW.Session.PlayerSpellKey(BUDDY, 145)] = { name = "Buddy" }
            assert.is_nil(evaluate(145))
            assert.is_table(evaluate(145, "Player-1-ZED", "Zed"))
        end)

        it("never auto-whispers the same player about the same spell twice", function()
            RW.db.profile.whisper = true
            RW.db.profile.debug = true -- debug re-alerts, so the session guard is what stops it
            assert.is_true(evaluate(145).isWhisper)
            local second = evaluate(145)
            assert.is_false(second.isWhisper)
            assert.are.equal(1, #W.sent)
        end)

        it("auto-whisper and the manual button share the once-per-session rule", function()
            evaluate(145)
            RW.UI.WhisperPlayer("Buddy")
            assert.are.equal(1, #W.sent)
            RW.db.profile.whisper = true
            RW.db.profile.debug = true
            assert.is_false(evaluate(145).isWhisper)
            assert.are.equal(1, #W.sent)
            assert.is_false(RW.UI.HasUnsentWhisper(RW.UI.GroupByPlayer(RW.Session.report)[1]))
        end)

        it("records detections for the report", function()
            evaluate(145)
            assert.are.equal(1, #RW.Session.report)
            assert.are.equal(3, RW.Session.report[1].rank)
        end)
    end)

    describe("OnSpellcast (UNIT_SPELLCAST_SUCCEEDED)", function()
        it("handles party members", function() assert.is_table(spellcast("party1", 145)) end)

        it("handles raid members", function()
            W.units.raid2 = { guid = "Player-1-RAIDER", name = "Raider", level = 40 }
            assert.is_table(spellcast("raid2", 145))
        end)

        it("handles the player", function()
            local e = spellcast("player", 145)
            assert.is_truthy(e.message:find("^You used"))
        end)

        it("de-duplicates the same cast seen as raidN and partyN", function()
            W.units.raid2 = W.units.party1
            RW.db.profile.debug = true -- would otherwise be blocked by once-per-session
            assert.is_table(spellcast("raid2", 145, "Cast-X"))
            assert.is_nil(spellcast("party1", 145, "Cast-X"))
        end)

        it("ignores non-group units", function()
            W.units.target = W.units.party1
            W.units.partypet1 = { guid = "Pet-0-1", name = "Wolfy", level = 40 }
            assert.is_nil(spellcast("target", 145))
            assert.is_nil(spellcast("nameplate1", 145))
            assert.is_nil(spellcast("partypet1", 145))
        end)

        it("ignores non-player GUIDs", function()
            W.units.party1.guid = "Creature-0-1"
            assert.is_nil(spellcast("party1", 145))
        end)

        it("skips secret spell IDs", function()
            assert.is_nil(spellcast("party1", W.SECRET))
            assert.are.equal(1, DT.secretSkips)
        end)

        it("skips secret caster details", function()
            W.units.party1.name = W.SECRET
            assert.is_nil(spellcast("party1", 145))
            assert.are.equal(1, DT.secretSkips)
        end)

        it("treats a much lower caster target as a deliberate downrank", function()
            W.units.party1.targetLevel = 20
            assert.is_nil(spellcast("party1", 145))
        end)

        it("ignores secret target levels", function()
            W.units.party1.targetLevel = W.SECRET
            assert.is_table(spellcast("party1", 145))
        end)

        it("ignores battlegrounds", function()
            W.inBattleground = true
            assert.is_nil(spellcast("party1", 145))
        end)

        it("ignores untracked spells", function() assert.is_nil(spellcast("party1", 424242)) end)

        it("ignores charmed casters", function()
            local real = _G.UnitIsCharmed
            _G.UnitIsCharmed = function() return true end
            assert.is_nil(spellcast("party1", 145))
            _G.UnitIsCharmed = real
        end)

        it("forgets old cast GUIDs", function()
            DT.RECENT_CASTS = 2
            RW.db.profile.debug = true
            spellcast("party1", 145, "A")
            spellcast("party1", 145, "B")
            spellcast("party1", 145, "C")
            assert.is_table(spellcast("party1", 145, "A"))
            DT.RECENT_CASTS = 64
        end)

        it("counts your casts and group members' casts", function()
            spellcast("player", 424242)
            spellcast("party1", 424242)
            spellcast("party1", W.SECRET)
            assert.are.equal(1, DT.stats.own)
            assert.are.equal(2, DT.stats.others)
            assert.are.equal(1, DT.secretSkips)
        end)

        it("cast monitor prints other players' casts, tracked or not", function()
            RW.db.profile.watch = true
            spellcast("player", 145)
            spellcast("party1", 424242)
            spellcast("party1", 145)
            spellcast("party1", W.SECRET)
            local watchLines = {}
            for _, line in ipairs(W.printed) do
                if line:find("[watch]", 1, true) then watchLines[#watchLines + 1] = line end
            end
            assert.are.equal(3, #watchLines)
            assert.is_truthy(watchLines[1]:find("untracked", 1, true))
            assert.is_truthy(watchLines[2]:find("tracked, Rank 3", 1, true))
            assert.is_truthy(watchLines[3]:find("hidden by the game", 1, true))
        end)

        it("cast monitor shows hidden names", function()
            RW.db.profile.watch = true
            W.units.party1.name = W.SECRET
            spellcast("party1", 424242)
            assert.is_truthy(W.printed[#W.printed]:find("<hidden>", 1, true))
        end)

        it("IsGroupUnit", function()
            assert.is_true(DT.IsGroupUnit("party4"))
            assert.is_true(DT.IsGroupUnit("raid40"))
            assert.is_false(DT.IsGroupUnit("raidpet1"))
            assert.is_false(DT.IsGroupUnit(nil))
        end)
    end)

    describe("Notify queue", function()
        it("holds whispers during combat and sends them after", function()
            RW.db.profile.whisper = true
            W.inCombat = true
            evaluate(145)
            assert.are.equal(0, #W.sent)
            assert.are.equal(1, #RW.Session.queue)
            W.inCombat = false
            RW.Notify.Flush()
            assert.are.equal(1, #W.sent)
            assert.are.equal(0, #RW.Session.queue)
        end)

        it("keeps whispers for targets still in combat", function()
            RW.db.profile.whisper = true
            W.unitCombat["Buddy"] = true
            evaluate(145)
            assert.are.equal(0, #W.sent)
            assert.are.equal(1, #RW.Session.queue)
        end)

        it("holds whispers during chat messaging lockdown", function()
            RW.db.profile.whisper = true
            W.chatLockdown = true
            evaluate(145)
            assert.are.equal(0, #W.sent)
            assert.are.equal(1, #RW.Session.queue)
            W.chatLockdown = false
            RW.Notify.Flush()
            assert.are.equal(1, #W.sent)
        end)

        it("falls back to local chat when the realm blocks addon chat", function()
            RW.db.profile.whisper = true
            W.realmBlocked = true
            evaluate(145)
            assert.are.equal(0, #W.sent)
            assert.are.equal(0, #RW.Session.queue)
            local seen = false
            for _, line in ipairs(W.printed) do
                if line:find("blocks addon whispers", 1, true) then seen = true end
            end
            assert.is_true(seen)
        end)

        it("Clear empties the queue", function()
            W.inCombat = true
            evaluate(145)
            assert.are.equal(1, RW.Notify.Clear())
            assert.are.equal(0, #RW.Session.queue)
        end)

        it("FlushSoon flushes immediately without C_Timer", function()
            RW.db.profile.whisper = true
            W.inCombat = true
            evaluate(145)
            W.inCombat = false
            RW.Notify.FlushSoon()
            assert.are.equal(1, #W.sent)
        end)
    end)
end)
