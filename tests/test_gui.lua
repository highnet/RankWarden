-- tests/test_gui.lua
-- Unit tests for GUI.lua — pure helpers plus the window against a fake AceGUI.

require("tests.bootstrap")

local RW = _G.RankWarden
local G = RW.GUI
local W = _G.__W

--- Finds created widgets of a kind whose props/text match.
local function find(kind, text)
    for _, w in ipairs(W.widgets) do
        if w.kind == kind then
            local t = w.props.SetText or w.props.SetLabel or ""
            if not text or tostring(t):find(text, 1, true) then return w end
        end
    end
end

local function click(text) find("Button", text):Fire("OnClick") end

local function detect() RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40) end

describe("GUI helpers", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("FormatRecord shows name, spell, rank, next level and mode", function()
        local line = G.FormatRecord({ time = "12:00", name = "Buddy", spell = "[Fireball]", rank = 3, nextLevel = 18 })
        assert.is_truthy(line:find("Buddy", 1, true))
        assert.is_truthy(line:find("Rank 3", 1, true))
        assert.is_truthy(line:find("18", 1, true))
        assert.is_truthy(line:find("local", 1, true))
        assert.is_truthy(G.FormatRecord({ whispered = true }):find("whispered", 1, true))
        assert.is_truthy(G.FormatRecord({ book = true }):find("book", 1, true))
    end)

    it("StatusText reflects settings and chat state", function()
        assert.is_truthy(G.StatusText():find("local only", 1, true))
        RW.db.profile.whisper = true
        W.chatLockdown = true
        local s = G.StatusText()
        assert.is_truthy(s:find("whispering", 1, true))
        assert.is_truthy(s:find("chat blocked (lockdown)", 1, true))
    end)

    it("MinimapPosition and AngleFromCursor round-trip", function()
        local x, y = G.MinimapPosition(90, 80)
        assert.is_true(math.abs(x) < 1e-9)
        assert.are.equal(80, math.floor(y + 0.5))
        assert.are.equal(90, math.floor(G.AngleFromCursor(0, 0, x, y) + 0.5))
    end)

    it("Reversed returns newest first", function() assert.are.same({ 3, 2, 1 }, G.Reversed({ 1, 2, 3 })) end)

    it("ParseSpell reads links and IDs", function()
        assert.are.equal(145, G.ParseSpell("|cff71d5ff|Hspell:145:0|h[Fireball]|h|r"))
        assert.are.equal(145, G.ParseSpell(" 145 "))
        assert.is_nil(G.ParseSpell("fireball"))
    end)
end)

describe("GUI window", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
        G.currentTab = "detections"
    end)

    it("opens, closes, and registers for Escape", function()
        G.Toggle()
        assert.is_true(G.IsShown())
        assert.are.equal("RankWardenMainFrame", _G.UISpecialFrames[1])
        G.Toggle()
        assert.is_false(G.IsShown())
        G.Open()
        G.Open() -- second open is a no-op
        assert.are.equal(1, #_G.UISpecialFrames)
    end)

    it("detections tab groups by player with a summary", function()
        detect()
        G.Open()
        assert.is_not_nil(find("Label", "Buddy"))
        assert.is_not_nil(find("Label", "1 player"))
        assert.is_not_nil(find("Label", "Rank 3"))
    end)

    it("per-player Whisper and Ignore player buttons", function()
        detect()
        G.Open()
        click("Whisper")
        assert.are.equal("WHISPER", W.sent[1].ch)
        assert.is_not_nil(find("Button", "Whispered"))
        click("Ignore player")
        assert.are.equal("Buddy", RW.db.profile.ignored["Player-1-BUDDY"])
    end)

    it("per-spell Ignore spell button ignores it for that player only", function()
        detect()
        G.Open()
        click("Ignore spell")
        assert.is_nil(next(RW.Session.ignoredSpells))
        assert.are.equal(0, #RW.Session.report)
        -- another player casting the same spell is still reported
        assert.is_table(RW.Detector.Evaluate(145, "Player-1-ZED", "Zed", 40))
    end)

    it("ignored tab lists and removes per-player ignores", function()
        detect()
        RW.UI.IgnoreSpell(RW.Session.report[1])
        G.Open()
        G.tabs:SelectTab("ignored")
        assert.is_not_nil(find("Label", "Buddy"))
        click("Remove")
        assert.is_nil(next(RW.Session.ignoredPlayerSpells))
    end)

    it("your own row has no whisper buttons", function()
        RW.Detector.Evaluate(145, "Player-1-ME", "Me", 40)
        G.Open()
        assert.is_nil(find("Button", "Ignore player"))
    end)

    it("Whisper all, Reset and HUD buttons", function()
        detect()
        G.Open()
        click("Whisper all")
        assert.are.equal(1, #W.sent)
        assert.is_true(RW.HUD.IsShown()) -- the detection popped it open
        click("Hide HUD")
        assert.is_false(RW.HUD.IsShown())
        click("Show HUD")
        assert.is_true(RW.HUD.IsShown())
        click("Reset")
        assert.are.equal(0, #RW.Session.report)
    end)

    it("Whisper all with nobody listed says so", function()
        G.Open()
        click("Whisper all")
        assert.are.equal(0, #W.sent)
    end)

    it("remembers window size and position", function()
        G.Open()
        assert.are.equal(RW.db.profile.window, G.frame.props.SetStatusTable)
    end)

    it("detections tab shows an empty state", function()
        G.Open()
        assert.is_not_nil(find("Label", "Nothing yet"))
    end)

    it("report goes to the chosen channel", function()
        detect()
        G.Open()
        click("Report")
        assert.are.equal("PARTY", W.sent[1].ch)
        find("Dropdown"):Fire("OnValueChanged", "raid")
        click("Report")
        assert.are.equal("RAID", W.sent[#W.sent].ch)
        G.reportChannel = nil
    end)

    it("shows a send button only when whispers are queued", function()
        RW.db.profile.whisper = true
        W.inCombat = true
        detect()
        G.Open()
        W.inCombat = false
        click("Send 1 queued")
        assert.are.equal(1, #W.sent)
    end)

    it("cast monitor checkbox toggles watching", function()
        G.Open()
        find("CheckBox", "Cast monitor"):Fire("OnValueChanged", true)
        assert.is_true(RW.Detector.watch)
    end)

    it("top checkboxes change settings", function()
        G.Open()
        find("CheckBox", "Auto-whisper"):Fire("OnValueChanged", true)
        assert.is_true(RW.db.profile.whisper)
    end)

    it("refreshes live when something is detected", function()
        G.Open()
        W.widgets = {}
        detect()
        assert.is_not_nil(find("Label", "Buddy"))
    end)

    it("history tab lists and clears saved detections", function()
        detect()
        G.Open()
        G.tabs:SelectTab("history")
        assert.is_not_nil(find("Label", "Buddy"))
        click("Clear history")
        assert.are.equal(0, #RW.db.profile.history)
        assert.is_not_nil(find("Label", "No history"))
    end)

    it("history is capped", function()
        RW.Session.HISTORY_SIZE = 2
        RW.db.profile.debug = true
        detect()
        detect()
        detect()
        assert.are.equal(2, #RW.db.profile.history)
        RW.Session.HISTORY_SIZE = 200
    end)

    it("ignored tab shows an empty per-player list", function()
        G.Open()
        G.tabs:SelectTab("ignored")
        assert.is_not_nil(find("Label", "Right-click a spell in the HUD"))
    end)

    it("ignored tab adds and removes spells", function()
        G.Open()
        G.tabs:SelectTab("ignored")
        local box = find("EditBox")
        box:Fire("OnEnterPressed", "|Hspell:145:0|h[Fireball]|h")
        assert.is_true(RW.Session.ignoredSpells[145])
        click("Remove")
        assert.is_nil(RW.Session.ignoredSpells[145])
        find("EditBox"):Fire("OnEnterPressed", "nope")
    end)

    it("ignored tab toggles common downranks", function()
        G.Open()
        G.tabs:SelectTab("ignored")
        find("CheckBox", "Frostbolt"):Fire("OnValueChanged", false)
        assert.is_false(RW.db.profile.commonDownranks[116])
        find("CheckBox", "Frostbolt"):Fire("OnValueChanged", true)
        assert.is_nil(RW.db.profile.commonDownranks[116])
        find("CheckBox", "Ignore spells people downrank"):Fire("OnValueChanged", false)
        assert.is_false(RW.db.profile.ignoreCommonDownranks)
    end)

    it("ignored tab manages ignored players", function()
        RW.db.profile.ignored["Player-1-X"] = "Xan"
        G.Open()
        G.tabs:SelectTab("ignored")
        assert.is_not_nil(find("Label", "Xan"))
        click("Remove")
        assert.is_nil(RW.db.profile.ignored["Player-1-X"])
        click("Ignore / unignore target")
    end)

    it("settings tab embeds the options panel", function()
        G.Open()
        G.tabs:SelectTab("settings")
        assert.are.equal("RankWarden", W.configOpened.app)
        G.Refresh() -- settings tab only refreshes the status bar
    end)

    it("Refresh is a no-op while closed", function()
        G.Refresh()
        assert.is_false(G.IsShown())
    end)
end)
