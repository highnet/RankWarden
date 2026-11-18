-- tests/test_diag.lua
-- Unit tests for Diagnostics.lua — restriction tracking, secrecy census, the
-- copyable report and its window.

require("tests.bootstrap")

local RW = _G.RankWarden
local D = RW.Diag
local W = _G.__W

-- Fake Forever restriction / secrecy APIs.
local active = {}
local function useRestrictionAPI()
    _G.Enum = {
        AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
        SecrecyLevel = { NeverSecret = 0, AlwaysSecret = 1, ContextuallySecret = 2 },
    }
    local byValue = { [0] = "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
    _G.C_RestrictedActions = {
        IsAddOnRestrictionActive = function(value)
            if byValue[value] == "Chat" then error("boom") end -- pcall keeps the report alive
            return active[byValue[value]] == true
        end,
    }
end

local function clearRestrictionAPI()
    _G.Enum, _G.C_RestrictedActions, _G.C_Secrets = nil, nil, nil
    active = {}
end

describe("Diagnostics", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
        useRestrictionAPI()
    end)

    after_each(clearRestrictionAPI)

    it("ActiveRestrictions lists what's on, and is empty without the API", function()
        active.Combat, active.Map = true, true
        assert.are.same({ "Combat", "Map" }, D.ActiveRestrictions())
        clearRestrictionAPI()
        assert.are.same({}, D.ActiveRestrictions())
    end)

    it("ActiveRestrictions skips restriction types the client doesn't define", function()
        _G.Enum.AddOnRestrictionType = { Combat = 0 }
        active.Combat = true
        assert.are.same({ "Combat" }, D.ActiveRestrictions())
    end)

    it("counts hidden and visible casts by the restrictions active at the time", function()
        active.Combat = true
        D.OnCast("party1", true)
        D.OnCast("party1", true)
        D.OnCast("party1", false)
        active.Combat = false
        D.OnCast("party2", false)
        assert.are.equal(2, D.hiddenBy.Combat)
        assert.are.equal(1, D.visibleBy.Combat)
        assert.are.equal(1, D.visibleBy.none)
        assert.are.equal(4, #D.events)
    end)

    it("keeps only the most recent events", function()
        D.MAX_EVENTS = 3
        for _ = 1, 5 do
            D.OnCast("party1", true)
        end
        assert.are.equal(3, #D.events)
        D.MAX_EVENTS = 25
    end)

    it("the detector feeds every group cast in, never your own", function()
        RW.Detector.OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "party1", "c1", W.SECRET)
        RW.Detector.OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "party1", "c2", 424242)
        RW.Detector.OnSpellcast("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 424242)
        assert.are.equal(1, D.hiddenBy.none)
        assert.are.equal(1, D.visibleBy.none)
        assert.are.equal(2, #D.events)
    end)

    it("SecrecyCensus groups tracked spells by Forever's secrecy level", function()
        _G.C_Secrets = {
            GetSpellCastSecrecy = function(id)
                if id == 133 then return 0 end
                if id == 143 then return 1 end
                if id == 145 then error("boom") end
                if id == 3140 then return 7 end -- a level this client doesn't name
                return 2
            end,
        }
        local counts, total = D.SecrecyCensus()
        assert.are.equal(RW.Slash.Count(RW.AbilityData), total)
        assert.are.equal(1, counts.NeverSecret)
        assert.are.equal(1, counts.AlwaysSecret)
        assert.are.equal(1, counts.unknown)
        assert.are.equal(1, counts["7"])
    end)

    it("SecrecyCensus reports unknown without C_Secrets", function()
        local counts, total = D.SecrecyCensus()
        assert.are.equal(total, counts.unknown)
    end)

    it("Report is plain text with settings, counters, detections and events", function()
        _G.GetBuildInfo = function() return "1.60.1", "70888", "Nov 1 2026", 16001 end
        _G.C_Spell.GetSpellLink = function() return "|cff71d5ff|Hspell:145:0|h[Fireball (Rank 3)]|h|r" end
        active.Combat = true
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        RW.Session.report[1].whispered = true
        RW.Detector.Evaluate(800002, "Player-1-ZED", "Zed", 60)
        D.OnCast("party1", true)
        local report = D.Report()
        _G.GetBuildInfo = nil
        _G.C_Spell.GetSpellLink = function(id) return "[spell" .. id .. "]" end
        assert.is_truthy(report:find("RankWarden " .. RW.VERSION, 1, true))
        assert.is_truthy(report:find("build 70888", 1, true))
        assert.is_truthy(report:find("interface 16001", 1, true))
        assert.is_truthy(report:find("Group casts hidden, by active restriction: Combat 1", 1, true))
        assert.is_truthy(report:find("Restrictions active now: Combat", 1, true))
        assert.is_truthy(report:find("[Fireball (Rank 3)] (spell 145)", 1, true))
        assert.is_truthy(report:find(", whispered", 1, true))
        assert.is_truthy(report:find("book/quest", 1, true))
        assert.is_truthy(report:find("party1 HIDDEN (restrictions: Combat)", 1, true))
        assert.is_falsy(report:find("|c", 1, true)) -- no colour codes
    end)

    it("Report works with nothing recorded, solo, without GetBuildInfo", function()
        local report = D.Report()
        assert.is_truthy(report:find("Client ? (build ?)", 1, true))
        assert.is_truthy(report:find("Group casts hidden, by active restriction: -", 1, true))
        assert.is_truthy(report:find("  none yet", 1, true))
        W.inGroup = false
        assert.is_truthy(D.Report():find("Group: solo", 1, true))
        W.inRaid = true
        assert.is_truthy(D.Report():find("Group: raid", 1, true))
    end)

    it("Report notes when addon chat is blocked", function()
        W.chatLockdown = true
        assert.is_truthy(D.Report():find("Addon chat: blocked (lockdown)", 1, true))
    end)
end)

describe("Diagnostics window", function()
    local function find(kind, text)
        for _, w in ipairs(W.widgets) do
            if w.kind == kind then
                local t = w.props.SetText or w.props.SetLabel or ""
                if not text or tostring(t):find(text, 1, true) then return w end
            end
        end
    end

    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("/rw diag opens the report, selected and ready to copy", function()
        _G.SlashCmdList.RANKWARDEN("diag")
        assert.is_not_nil(D.frame)
        assert.is_truthy(D.box.props.SetText:find("diagnostics", 1, true))
        assert.is_true(D.box.focused)
        assert.is_true(D.box.highlighted)
    end)

    it("opening again refreshes instead of stacking windows", function()
        D.Show()
        local frame = D.frame
        D.OnCast("party1", true)
        D.Show()
        assert.are.equal(frame, D.frame)
        assert.is_truthy(D.box.props.SetText:find("HIDDEN", 1, true))
    end)

    it("buttons select, refresh and reset counters", function()
        D.Show()
        D.box.highlighted = false
        find("Button", "Select all"):Fire("OnClick")
        assert.is_true(D.box.highlighted)
        D.OnCast("party1", true)
        find("Button", "Refresh"):Fire("OnClick")
        assert.is_truthy(D.box.props.SetText:find("HIDDEN", 1, true))
        find("Button", "Reset counters"):Fire("OnClick")
        assert.are.equal(0, #D.events)
        assert.is_truthy(D.box.props.SetText:find("none yet", 1, true))
    end)

    it("closing releases the window; select/refresh are safe while closed", function()
        D.Show()
        D.frame:Hide()
        assert.is_nil(D.frame)
        D.SelectAll()
        D.Refresh()
    end)

    it("the main window has a Diagnostics button", function()
        RW.GUI.Open()
        find("Button", "Diagnostics"):Fire("OnClick")
        assert.is_not_nil(D.frame)
    end)
end)
