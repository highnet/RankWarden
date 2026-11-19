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

describe("Location and hidden-area warning", function()
    local function warnings()
        local n = 0
        for _, line in ipairs(W.printed) do
            if line:find("Group casts are hidden here", 1, true) then n = n + 1 end
        end
        return n
    end

    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
        useRestrictionAPI()
        D.warnedPlaces = {}
        _G.GetRealZoneText = function() return "Elwynn Forest" end
        _G.GetSubZoneText = function() return "Goldshire" end
        _G.C_Map = { GetBestMapForUnit = function() return 1429 end }
        _G.IsInInstance = function() return false, "none" end
    end)

    after_each(function()
        clearRestrictionAPI()
        _G.GetRealZoneText, _G.GetSubZoneText, _G.C_Map, _G.IsInInstance = nil, nil, nil, nil
    end)

    it("describes where you are", function()
        assert.are.equal("Elwynn Forest / Goldshire (map 1429, open world)", D.LocationText())
        _G.IsInInstance = function() return true, "party" end
        _G.GetSubZoneText = function() return "" end
        assert.are.equal("Elwynn Forest (map 1429, party)", D.LocationText())
        _G.IsInInstance = function() return true, nil end
        assert.are.equal("Elwynn Forest (map 1429, instance)", D.LocationText())
    end)

    it("falls back to GetZoneText and '?' on clients without those APIs", function()
        _G.GetRealZoneText, _G.GetSubZoneText, _G.C_Map, _G.IsInInstance = nil, nil, nil, nil
        _G.GetZoneText = function() return "" end
        assert.are.equal("? (map ?, open world)", D.LocationText())
        _G.GetZoneText = nil
        assert.are.equal("? (map ?, open world)", D.LocationText())
    end)

    it("the report and each recorded cast include the location", function()
        D.OnCast("party2", true)
        local report = D.Report()
        assert.is_truthy(report:find("Location now: Elwynn Forest / Goldshire (map 1429, open world)", 1, true))
        assert.is_truthy(report:find("party2 HIDDEN (restrictions: none) at Elwynn Forest", 1, true))
        assert.is_truthy(report:find("Group casts here: hidden (none)", 1, true))
    end)

    it("an active Map restriction alone means group casts are hidden here", function()
        assert.is_nil(D.HiddenHere())
        assert.is_truthy(D.Report():find("Group casts here: not known to be hidden", 1, true))
        active.Combat = true
        assert.is_nil(D.HiddenHere()) -- combat alone isn't proven to hide casts
        active.Map = true
        assert.are.equal("Map", D.HiddenHere())
        assert.is_truthy(D.LimitText():find("(Map restriction)", 1, true))
    end)

    it("warns once per place when you arrive, and again in a new place", function()
        active.Map = true
        D.CheckLocation()
        D.CheckLocation()
        assert.are.equal(1, warnings())
        _G.C_Map.GetBestMapForUnit = function() return 1433 end
        D.CheckLocation()
        assert.are.equal(2, warnings())
    end)

    it("a hidden cast proves the place is restricted, even with no restriction reported", function()
        D.OnCast("party2", false)
        assert.are.equal(0, warnings())
        D.OnCast("party2", true)
        assert.are.equal(1, warnings())
        assert.are.equal("none", D.HiddenHere())
    end)

    it("the HUD shows a warning line on top while here, with an explanation on hover", function()
        active.Map = true
        RW.HUD.Show()
        local first
        for _, b in ipairs(RW.HUD.frame.rows) do
            if b.shown then
                first = b
                break
            end
        end
        assert.are.equal("warning", first.row.kind)
        assert.is_truthy(first.text.text:find("Group casts hidden here (Map)", 1, true))
        first.scripts.OnEnter(first)
        first.scripts.OnClick(first, "LeftButton") -- does nothing
    end)

    it("zone changes and logging in check the location", function()
        active.Map = true
        RW:OnEnable()
        W.events.ZONE_CHANGED_NEW_AREA()
        assert.are.equal(1, warnings())
        D.warnedPlaces = {}
        W.events.PLAYER_ENTERING_WORLD()
        assert.are.equal(2, warnings())
    end)
end)

describe("Realm blocks addon chat", function()
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
        W.realmBlocked = true
    end)

    it("WhisperAllowed is false only for a realm-wide block, not a lockdown", function()
        assert.is_false(RW.UI.WhisperAllowed())
        W.realmBlocked = false
        W.chatLockdown = true
        assert.is_true(RW.UI.WhisperAllowed())
    end)

    it("the Whisper button refuses and explains instead of queuing", function()
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        assert.are.equal(0, RW.UI.WhisperPlayer("Buddy"))
        assert.are.equal(0, #RW.Session.queue)
        assert.is_true(RW.UI.HasUnsentWhisper(RW.UI.GroupByPlayer(RW.Session.report)[1]))
    end)

    it("HUD Whisper buttons read Blocked, are disabled, and explain on hover", function()
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        local row = RW.HUD.frame.rows[1]
        assert.are.equal("Blocked", row.whisper.text)
        row.whisper.scripts.OnEnter(row.whisper)
    end)

    it("the window disables whisper buttons and says why", function()
        RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40)
        RW.GUI.Open()
        assert.is_not_nil(find("Label", "can't whisper"))
        assert.is_true(find("Button", "Can't whisper").props.SetDisabled)
        assert.is_true(find("Button", "Whisper all").props.SetDisabled)
    end)

    it("/rw whisper warns when turning auto-whisper on", function()
        RW.db.profile.whisper = false -- auto-whisper is on by default
        _G.SlashCmdList.RANKWARDEN("whisper")
        local seen = false
        for _, line in ipairs(W.printed) do
            if line:find("can't whisper", 1, true) then seen = true end
        end
        assert.is_true(seen)
    end)
end)
