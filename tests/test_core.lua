-- tests/test_core.lua
-- Unit tests for RankWarden.lua (start-up, events) and RankWarden_Options.lua (options panel).

require("tests.bootstrap")

local RW = _G.RankWarden
local W = _G.__W

describe("Core", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    it("OnInitialize creates the saved DB, builds ranks and registers the options panel", function()
        local timerCalls = 0
        _G.C_Timer = { After = function() timerCalls = timerCalls + 1 end }
        RW:OnInitialize()
        _G.C_Timer = nil
        assert.are.equal("RankWardenDB", W.dbName)
        assert.is_nil(RW.db.profile.ignoredSpells) -- old saved list is dropped
        assert.are.equal("RankWarden", W.optionsTable.app)
        assert.are.equal("RankWarden", W.blizOptions.name)
        assert.is_true(timerCalls > 0) -- real data has spell names "missing" in tests, so it retries
        assert.is_true(#W.printed > 0)
    end)

    it("BuildRanks stops retrying after a few attempts", function()
        local calls = 0
        _G.C_Timer = {
            After = function(_, fn)
                calls = calls + 1
                fn()
            end,
        }
        RW.BuildRanks()
        _G.C_Timer = nil
        assert.is_true(calls <= 4)
    end)

    it("OnEnable registers every event and its handlers work", function()
        RW:OnEnable()
        for _, event in ipairs({
            "UNIT_SPELLCAST_SUCCEEDED",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_ALIVE",
            "PLAYER_UNGHOST",
            "ZONE_CHANGED_NEW_AREA",
            "GROUP_ROSTER_UPDATE",
            "PLAYER_ENTERING_WORLD",
        }) do
            assert.is_function(W.events[event], event)
        end
        W.events.UNIT_SPELLCAST_SUCCEEDED("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-core", 145)
        assert.are.equal(1, #RW.Session.report)
        W.events.PLAYER_REGEN_ENABLED()
        W.events.GROUP_ROSTER_UPDATE()
        W.events.PLAYER_ENTERING_WORLD()
        W.commHandlers[RW.Sync.PREFIX](nil, "HELLO", "PARTY", "Zed")
        assert.is_true(RW.Sync.peers.Zed)
        RW:OnDisable()
    end)
end)

describe("Options panel", function()
    local O = RW.Options

    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    --- Calls every get/set/func/name/disabled/values callback in the options table.
    local function exercise(args)
        for key, opt in pairs(args) do
            if type(opt.name) == "function" then assert.is_string(opt.name()) end
            if type(opt.values) == "function" then assert.is_table(opt.values()) end
            if type(opt.disabled) == "function" then opt.disabled() end
            if opt.get then
                local v = opt.get()
                if opt.set then
                    if opt.type == "toggle" then
                        opt.set(nil, not v)
                        opt.set(nil, v)
                    else
                        opt.set(nil, v)
                    end
                end
            end
            if opt.func then opt.func() end
            if opt.args then exercise(opt.args) end
            assert.is_string(key)
        end
    end

    it("Setup adds a toggle for each commonly downranked spell", function()
        O.Setup()
        local d = O.TABLE.args.downranks.args
        for _, entry in ipairs(RW.Ranks.COMMON_DOWNRANKS) do
            assert.is_table(d["d" .. entry.id])
        end
    end)

    it("every option reads and writes its setting", function()
        O.Setup()
        exercise(O.TABLE.args)
        assert.are.equal("default", RW.db.profile.flavor)
    end)

    it("downrank toggles store false only when switched off", function()
        O.Setup()
        local opt = O.TABLE.args.downranks.args.d116
        opt.set(nil, false)
        assert.is_false(RW.db.profile.commonDownranks[116])
        opt.set(nil, true)
        assert.is_nil(RW.db.profile.commonDownranks[116])
    end)

    it("HUD scale applies to an open HUD", function()
        O.Setup()
        RW.HUD.Show()
        O.TABLE.args.hud.args.scale.set(nil, 1.2)
        assert.are.equal(1.2, RW.db.profile.hud.scale)
    end)

    it("Open uses Settings when available, otherwise the dialog, never in combat", function()
        O.Setup()
        local openedCategory
        _G.Settings = { OpenToCategory = function(id) openedCategory = id end }
        O.Open()
        assert.are.equal("RankWarden", openedCategory)
        _G.Settings = nil
        W.configOpened = nil
        O.Open()
        assert.are.equal("RankWarden", W.configOpened.app)
        W.inCombat = true
        W.configOpened = nil
        O.Open()
        assert.is_nil(W.configOpened)
    end)
end)
