-- tests/test_ranks.lua
-- Unit tests for Ranks.lua — chain building, rank checks, and ignore rules.

require("tests.bootstrap")

local RW = _G.RankWarden
local R = RW.Ranks

describe("Ranks", function()
    before_each(function()
        _G.__freshDB()
        _G.__useFixture()
    end)

    describe("Build", function()
        it("groups ranks of one ability by name, ordered by trainer level", function()
            local fb = RW.AbilityData[133]
            assert.are.equal(1, fb.Rank)
            assert.are.equal(4, RW.AbilityData[3140].Rank)
            assert.are.equal(fb.AbilityGroup, RW.AbilityData[3140].AbilityGroup)
        end)

        it("never merges same-named spells from different classes", function()
            -- Druid and Shaman both have a single-rank Cure Poison.
            assert.is_nil(RW.AbilityData[8946])
            assert.is_nil(RW.AbilityData[526])
        end)

        it("uses explicit groups for chains that change name", function()
            assert.are.equal(1, RW.AbilityData[5487].Rank)
            assert.are.equal(2, RW.AbilityData[9634].Rank)
            assert.are.equal(40, RW.AbilityData[9634].Level)
        end)

        it("drops vanilla abilities RankSentinel deliberately ignores", function()
            assert.is_nil(RW.AbilityData[3420])
            assert.is_nil(RW.AbilityData[3421])
        end)

        it("includes brand-new Forever abilities", function()
            assert.is_not_nil(RW.AbilityData[900001])
            assert.are.equal(2, RW.AbilityData[900002].Rank)
        end)

        it("orders by subtext rank when every member has one", function()
            RW.TrainerSpells = { MAGE = { [1] = 30, [2] = 10 } }
            RW.ExplicitGroups, RW.LegacyRanked, RW.LegacyExcluded = {}, {}, {}
            R.Build(function() return "Blink" end, function(id) return id end)
            assert.are.equal(1, RW.AbilityData[1].Rank)
            assert.are.equal(2, RW.AbilityData[2].Rank)
        end)

        it("counts spells whose names aren't loaded yet", function()
            RW.TrainerSpells = { MAGE = { [1] = 1, [2] = 2 } }
            RW.ExplicitGroups = {}
            local missing = R.Build(function() return nil end, function() return nil end)
            assert.are.equal(2, missing)
        end)

        it("builds the real Forever data without errors", function()
            local real = RW.__realData
            RW.TrainerSpells, RW.ExplicitGroups = real.TrainerSpells, real.ExplicitGroups
            RW.LegacyRanked, RW.LegacyExcluded = real.LegacyRanked, real.LegacyExcluded
            -- Name every spell by ID so nothing groups by name; explicit chains still build.
            R.Build(function(id) return "spell" .. id end, function() return nil end)
            assert.is_true(#RW.AbilityGroups > 30)
        end)
    end)

    describe("NextRank", function()
        it("returns the rank above", function()
            local id, data = R.NextRank(143)
            assert.are.equal(145, id)
            assert.are.equal(12, data.Level)
        end)

        it("returns nil at the top rank", function() assert.is_nil(R.NextRank(3140)) end)

        it("returns nil for untracked spells", function() assert.is_nil(R.NextRank(424242)) end)
    end)

    describe("WithinGrace", function()
        it("max-level casters get no grace", function() assert.is_false(R.WithinGrace(60, 60, 60)) end)
        it("gives low levels a few levels to train", function()
            assert.is_true(R.WithinGrace(16, 18, 60))
            assert.is_false(R.WithinGrace(14, 18, 60))
        end)
        it("mid levels get two levels", function()
            assert.is_true(R.WithinGrace(39, 40, 60))
            assert.is_false(R.WithinGrace(38, 40, 60))
        end)
        it("near max get one level", function()
            assert.is_true(R.WithinGrace(55, 55, 60))
            assert.is_false(R.WithinGrace(54, 55, 60))
        end)
    end)

    describe("Check", function()
        it("alerts on an outdated rank", function()
            local alert, data, nextLevel = R.Check(145, 40, 40, 60)
            assert.is_true(alert)
            assert.are.equal(3, data.Rank)
            assert.are.equal(18, nextLevel)
        end)

        it("does not alert on the top rank", function() assert.is_false((R.Check(3140, 40, 40, 60))) end)

        it("allows downranking on much lower targets", function() assert.is_false((R.Check(145, 40, 20, 60))) end)

        it("ignores unknown caster levels", function() assert.is_false((R.Check(145, 0, 0, 60))) end)

        it("skips when the next rank has no trainer level", function()
            RW.AbilityData[700002].Level = 0
            assert.is_false((R.Check(700001, 50, 0, 60)))
        end)
    end)

    describe("book / quest ranks", function()
        it("keeps a level-0 rank when its Rank text is known", function()
            assert.are.equal(3, RW.AbilityData[800003].Rank)
            assert.are.equal(0, RW.AbilityData[800003].Level)
        end)

        it("drops a level-0 spell with no Rank text instead of guessing its place", function()
            RW.TrainerSpells = { MAGE = { [1] = 10, [2] = 20, [3] = 0 } }
            RW.ExplicitGroups, RW.LegacyRanked, RW.LegacyExcluded = {}, {}, {}
            local missing = R.Build(function() return "Blink" end, function() return nil end)
            assert.is_nil(RW.AbilityData[3])
            assert.are.equal(2, RW.AbilityData[2].Rank)
            assert.are.equal(1, missing)
        end)

        it("drops level-0 spells when only some ranks have text", function()
            RW.TrainerSpells = { MAGE = { [1] = 10, [2] = 20, [3] = 0 } }
            RW.ExplicitGroups, RW.LegacyRanked, RW.LegacyExcluded = {}, {}, {}
            R.Build(function() return "Blink" end, function(id) return id == 3 and 3 or nil end)
            assert.is_nil(RW.AbilityData[3])
        end)

        it("flags the best trainer rank at max level when a book rank exists", function()
            local alert, data, nextLevel, kind = R.Check(800002, 60, 0, 60, true)
            assert.is_true(alert)
            assert.are.equal(2, data.Rank)
            assert.is_nil(nextLevel)
            assert.are.equal("book", kind)
        end)

        it("stays quiet below max level", function() assert.is_false((R.Check(800002, 59, 0, 60, true))) end)

        it("stays quiet when the option is off", function() assert.is_false((R.Check(800002, 60, 0, 60, false))) end)

        it("still reports outdated trainer ranks normally", function()
            local alert, _, nextLevel, kind = R.Check(800001, 60, 0, 60, true)
            assert.is_true(alert)
            assert.are.equal(50, nextLevel)
            assert.are.equal("trainer", kind)
        end)

        it("never treats a level-0 rank 1 (talent) as a book rank", function()
            RW.AbilityData[700002].Level = 0
            RW.AbilityData[700002].Rank = 1
            assert.is_false((R.Check(700001, 60, 0, 60, true)))
        end)
    end)

    describe("IsIgnoredSpell", function()
        it("ignores common downranks by default", function()
            assert.is_true(R.IsIgnoredSpell(205, RW.db.profile)) -- Frostbolt rank 2
        end)

        it("respects the master toggle", function()
            RW.db.profile.ignoreCommonDownranks = false
            assert.is_false(R.IsIgnoredSpell(205, RW.db.profile))
        end)

        it("respects per-spell toggles", function()
            RW.db.profile.commonDownranks[116] = false
            assert.is_false(R.IsIgnoredSpell(205, RW.db.profile))
        end)

        it("ignores every rank of a user-ignored spell", function()
            RW.db.profile.ignoredSpells[3140] = true
            assert.is_true(R.IsIgnoredSpell(133, RW.db.profile))
        end)

        it("does not ignore other spells", function() assert.is_false(R.IsIgnoredSpell(145, RW.db.profile)) end)
    end)

    describe("MaxLevel", function()
        it("falls back to 60 without the API", function()
            local real = _G.GetMaxPlayerLevel
            _G.GetMaxPlayerLevel = nil
            assert.are.equal(60, R.MaxLevel())
            _G.GetMaxPlayerLevel = real
        end)
    end)
end)
