-- tests/test_hud.lua
-- Unit tests for HUD.lua (lower ranks grouped by player) and the minimap button.

require("tests.bootstrap")

local RW = _G.RankWarden
local H = RW.HUD

local function rec(name, spell, rank, extra)
    local r = { name = name, spell = spell, rank = rank, nextLevel = 18, level = 40 }
    for k, v in pairs(extra or {}) do
        r[k] = v
    end
    return r
end

local function visibleRows()
    local out = {}
    for _, b in ipairs(H.frame.rows) do
        if b.shown then out[#out + 1] = b end
    end
    return out
end

local function visibleLines()
    local out = {}
    for _, b in ipairs(visibleRows()) do
        out[#out + 1] = b.text.text
    end
    return out
end

local function detectBuddy() RW.Detector.Evaluate(145, "Player-1-BUDDY", "Buddy", 40, 0, "MAGE") end

describe("HUD helpers", function()
    it("groups by player, sorted, one entry per spell rank", function()
        local groups = H.GroupByPlayer({
            rec("Zed", "[Fireball]", 3),
            rec("Amy", "[Heal]", 1),
            rec("Zed", "[Frostbolt]", 2),
            rec("Zed", "[Fireball]", 3), -- repeat (debug mode) is collapsed
        })
        assert.are.equal(2, #groups)
        assert.are.equal("Amy", groups[1].name)
        assert.are.equal("Zed", groups[2].name)
        assert.are.equal(2, #groups[2].entries)
        assert.are.equal(40, groups[2].level)
    end)

    it("formats trainer and book entries", function()
        assert.is_truthy(H.FormatEntry(rec("A", "[Fireball]", 3)):find("next at 18", 1, true))
        assert.is_truthy(H.FormatEntry(rec("A", "[Fireball]", 3, { book = true })):find("book/quest", 1, true))
        assert.is_truthy(H.FormatEntry({ rank = 1 }):find("R1", 1, true))
    end)

    it("shows spell icons and marks new entries", function()
        _G.__W.time = 100
        local line = H.FormatEntry(rec("A", "[Fireball]", 3, { spellID = 145, at = 95 }))
        assert.is_truthy(line:find("|T136000", 1, true))
        assert.is_truthy(line:find("new", 1, true))
        _G.__W.time = 1000
        assert.is_falsy(H.FormatEntry(rec("A", "[Fireball]", 3, { at = 95 })):find("new", 1, true))
    end)

    it("colours player names by class and marks whispered players", function()
        local p = H.GroupByPlayer({ rec("Zed", "[Fireball]", 3, { class = "MAGE", whispered = true }) })[1]
        local line = H.FormatPlayer(p)
        assert.is_truthy(line:find("|cffabcdefZed", 1, true))
        assert.is_truthy(line:find("whispered", 1, true))
    end)

    it("builds player rows then spell rows", function()
        local rows, total = H.BuildRows({ rec("Zed", "[Fireball]", 3), rec("Zed", "[Frostbolt]", 2) })
        assert.are.equal(3, #rows)
        assert.are.equal(2, total)
        assert.are.equal("player", rows[1].kind)
        assert.are.equal("spell", rows[2].kind)
        assert.is_truthy(rows[1].text:find("(40)", 1, true))
        local lines = H.BuildLines({ rec("Zed", "[Fireball]", 3) })
        assert.is_truthy(lines[2]:find("Fireball", 1, true))
    end)

    it("caps long lists with a more row", function()
        local report = {}
        for i = 1, 30 do
            report[i] = rec("P" .. i, "[Spell]", 1)
        end
        local rows = H.BuildRows(report, 10)
        assert.are.equal(10, #rows)
        assert.are.equal("more", rows[10].kind)
    end)

    it("shows an empty state", function()
        local rows, total = H.BuildRows({})
        assert.are.equal(0, total)
        assert.are.equal("empty", rows[1].kind)
    end)
end)

describe("HUD frame", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("toggles and remembers whether it was open", function()
        H.Toggle()
        assert.is_true(H.IsShown())
        assert.is_true(RW.db.profile.hud.shown)
        H.Toggle()
        assert.is_false(H.IsShown())
        assert.is_false(RW.db.profile.hud.shown)
    end)

    it("pops open on a detection and lists the player and spell", function()
        assert.is_false(H.IsShown())
        detectBuddy()
        assert.is_true(H.IsShown())
        local lines = visibleLines()
        assert.is_truthy(lines[1]:find("Buddy", 1, true))
        assert.is_truthy(lines[2]:find("R3", 1, true))
        assert.is_truthy(H.frame.title.text:find("1", 1, true))
        assert.is_truthy(H.frame.summary.text:find("1 player", 1, true))
        assert.is_nil(rawget(H.frame, "whisperAll")) -- whispering is per player only
        assert.is_true(H.frame.reset.shown)
    end)

    it("hides Reset when the list is empty", function()
        H.Show()
        assert.is_false(H.frame.reset.shown)
    end)

    it("stays closed when auto-open is off", function()
        RW.db.profile.hud.autoOpen = false
        detectBuddy()
        assert.is_false(H.IsShown())
    end)

    it("collapses to the header and expands again on a new detection", function()
        detectBuddy()
        H.frame.collapseButton.scripts.OnClick()
        assert.is_true(RW.db.profile.hud.collapsed)
        assert.are.equal(0, #visibleRows())
        RW.db.profile.debug = true
        detectBuddy()
        assert.is_false(RW.db.profile.hud.collapsed)
        assert.is_true(#visibleRows() > 0)
    end)

    it("player row: its own Whisper button whispers that player only", function()
        detectBuddy()
        RW.Detector.Evaluate(145, "Player-1-ZED", "Zed", 40)
        local rows = visibleRows()
        local buddy = rows[1]
        assert.is_true(buddy.whisper.shown)
        assert.are.equal("Whisper", buddy.whisper.text)
        buddy.whisper.scripts.OnEnter(buddy.whisper)
        buddy.whisper.scripts.OnClick(buddy.whisper)
        assert.are.equal(1, #_G.__W.sent)
        assert.are.equal("Buddy", _G.__W.sent[1].target)
        assert.are.equal("Sent", visibleRows()[1].whisper.text)
        -- a second click sends nothing new
        local again = visibleRows()[1]
        again.whisper.scripts.OnClick(again.whisper)
        assert.are.equal(1, #_G.__W.sent)
    end)

    it("player row: a plain click never whispers; right-click ignores", function()
        detectBuddy()
        local playerRow = visibleRows()[1]
        playerRow.scripts.OnClick(playerRow, "LeftButton")
        assert.are.equal(0, #_G.__W.sent)
        playerRow.scripts.OnEnter(playerRow)
        playerRow.scripts.OnClick(playerRow, "RightButton")
        assert.are.equal("Buddy", RW.db.profile.ignored["Player-1-BUDDY"])
        assert.are.equal(0, #RW.Session.report)
    end)

    it("no Whisper button on spell rows or your own row", function()
        detectBuddy()
        assert.is_false(visibleRows()[2].whisper.shown)
        RW.Session.report = {}
        RW.Detector.Evaluate(145, "Player-1-ME", "Me", 40)
        assert.is_false(visibleRows()[1].whisper.shown)
    end)

    it("Whisper button does nothing without a player row", function()
        detectBuddy()
        local b = visibleRows()[1]
        b.row = false -- fake frames return stubs for missing keys
        b.whisper.scripts.OnClick(b.whisper)
        b.whisper.scripts.OnEnter(b.whisper)
        assert.are.equal(0, #_G.__W.sent)
    end)

    it("spell row: tooltip, shift-click links, right-click ignores", function()
        detectBuddy()
        local spellRow = visibleRows()[2]
        spellRow.scripts.OnEnter(spellRow)
        spellRow.scripts.OnClick(spellRow, "LeftButton") -- plain click does nothing
        assert.is_nil(_G.__W.linked)
        _G.__W.shift = true
        spellRow.scripts.OnClick(spellRow, "LeftButton")
        assert.are.equal("[spell145]", _G.__W.linked)
        spellRow.scripts.OnClick(spellRow, "RightButton")
        assert.is_not_nil(RW.Session.ignoredPlayerSpells["Player-1-BUDDY|" .. RW.AbilityData[145].AbilityGroup])
        assert.is_nil(next(RW.Session.ignoredSpells)) -- not a global ignore
        assert.are.equal(0, #RW.Session.report)
    end)

    it("more row opens the window", function()
        RW.HUD.MAX_ROWS = 2
        detectBuddy()
        RW.Detector.Evaluate(145, "Player-1-ZED", "Zed", 40)
        local rows = visibleRows()
        rows[#rows].scripts.OnClick(rows[#rows], "LeftButton")
        assert.is_true(RW.GUI.IsShown())
        RW.HUD.MAX_ROWS = 22
    end)

    it("footer: Reset", function()
        detectBuddy()
        H.frame.reset.scripts.OnEnter(H.frame.reset)
        H.frame.reset.scripts.OnClick()
        assert.are.equal(0, #RW.Session.report)
        assert.is_nil(next(RW.db.profile.announced))
    end)

    it("header buttons: window and close", function()
        H.Show()
        H.frame.windowButton.scripts.OnClick()
        assert.is_true(RW.GUI.IsShown())
        H.frame.windowButton.scripts.OnEnter(H.frame.windowButton)
        H.frame.close.scripts.OnClick()
        assert.is_false(H.IsShown())
    end)

    it("hides surplus rows after the list shrinks", function()
        detectBuddy()
        RW.Session.report = {}
        H.Refresh()
        assert.are.equal(1, #visibleRows())
    end)

    it("restores after login only if it was open", function()
        H.Restore()
        assert.is_nil(H.frame)
        RW.db.profile.hud.shown = true
        H.Restore()
        assert.is_true(H.IsShown())
    end)

    it("drags unless locked and saves its position", function()
        H.Show()
        local f = H.frame
        local moved = false
        f.StartMoving = function() moved = true end
        f.scripts.OnDragStart(f)
        assert.is_true(moved)
        f:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 10, -20)
        f.scripts.OnDragStop(f)
        assert.are.equal("TOPLEFT", RW.db.profile.hud.point[1])
        moved = false
        RW.db.profile.hud.locked = true
        f.scripts.OnDragStart(f)
        assert.is_false(moved)
    end)

    it("ResetPosition restores the default spot", function()
        H.Show()
        RW.db.profile.hud.point = { "TOP", "TOP", 0, 0 }
        H.ResetPosition()
        assert.are.equal("RIGHT", RW.db.profile.hud.point[1])
    end)

    it("slash commands toggle, lock and reset", function()
        _G.SlashCmdList.RANKWARDEN("hud")
        assert.is_true(H.IsShown())
        _G.SlashCmdList.RANKWARDEN("hudlock")
        assert.is_true(RW.db.profile.hud.locked)
        _G.SlashCmdList.RANKWARDEN("hudreset")
        assert.are.equal("RIGHT", RW.db.profile.hud.point[1])
    end)

    it("Refresh without a frame is a no-op", function()
        H.Refresh()
        assert.is_nil(H.frame)
    end)
end)

describe("Minimap button", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("is created once and placed on the minimap", function()
        RW.GUI.CreateMinimapButton()
        local b = RW.GUI.minimapButton
        assert.is_not_nil(b)
        assert.is_true(b.shown)
        RW.GUI.CreateMinimapButton()
        assert.are.equal(b, RW.GUI.minimapButton)
    end)

    it("left-click toggles the window, right-click toggles detection", function()
        RW.GUI.CreateMinimapButton()
        local b = RW.GUI.minimapButton
        b.scripts.OnClick(b, "LeftButton")
        assert.is_true(RW.GUI.IsShown())
        b.scripts.OnClick(b, "RightButton")
        assert.is_false(RW.db.profile.enabled)
        RW.GUI.Close()
    end)

    it("drags around the minimap edge", function()
        RW.GUI.CreateMinimapButton()
        local b = RW.GUI.minimapButton
        b.scripts.OnDragStart(b)
        b.scripts.OnUpdate()
        assert.are.equal(90, math.floor(RW.db.profile.minimap.angle + 0.5))
        b.scripts.OnDragStop(b)
    end)

    it("shows a tooltip", function()
        RW.GUI.CreateMinimapButton()
        local b = RW.GUI.minimapButton
        b.scripts.OnEnter(b)
        b.scripts.OnLeave(b)
    end)

    it("can be hidden", function()
        RW.GUI.CreateMinimapButton()
        RW.db.profile.minimap.hide = true
        RW.GUI.PlaceMinimapButton()
        assert.is_false(RW.GUI.minimapButton.shown)
    end)
end)
