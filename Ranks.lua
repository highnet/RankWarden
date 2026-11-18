-- Ranks.lua
-- Rank logic: builds Forever's rank chains in-game, then answers
-- "is this cast a lower rank than the caster could be using?"
-- No combat-log or chat code lives here, so it is fully unit-testable.
-- Depends on: RankWarden.lua (Core), AbilityData.lua

local RW = RankWarden

RW.Ranks = {}
local R = RW.Ranks

R.DEFAULT_MAX_LEVEL = 60 -- Forever is capped at 60
R.DOWNRANK_GAP = 8 -- target this many levels below caster = deliberate downrank

-- Built by R.Build():
RW.AbilityData = {} -- spellID → { Rank, Level, AbilityGroup }
RW.AbilityGroups = {} -- groupIndex → { spellID, ... } in rank order

-- ─────────────────────────────────────────────────────────────────────────────
-- Commonly downranked abilities (rank-1 spell IDs). Any rank of these is
-- skipped while the matching toggle is on. Keyed by ID so it works in every
-- client language; the label is only a fallback for the options panel.
-- ─────────────────────────────────────────────────────────────────────────────
R.COMMON_DOWNRANKS = {
    { id = 2050, label = "Lesser Heal" },
    { id = 2054, label = "Heal" },
    { id = 2060, label = "Greater Heal" },
    { id = 2061, label = "Flash Heal" },
    { id = 139, label = "Renew" },
    { id = 596, label = "Prayer of Healing" },
    { id = 17, label = "Power Word: Shield" },
    { id = 331, label = "Healing Wave" },
    { id = 8004, label = "Lesser Healing Wave" },
    { id = 1064, label = "Chain Heal" },
    { id = 403, label = "Lightning Bolt" },
    { id = 8042, label = "Earth Shock" },
    { id = 5185, label = "Healing Touch" },
    { id = 8936, label = "Regrowth" },
    { id = 774, label = "Rejuvenation" },
    { id = 8921, label = "Moonfire" },
    { id = 635, label = "Holy Light" },
    { id = 19750, label = "Flash of Light" },
    { id = 116, label = "Frostbolt" },
    { id = 1449, label = "Arcane Explosion" },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Client helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Returns the max player level, falling back to Forever's cap.
function R.MaxLevel()
    local ok, lvl = pcall(function() return GetMaxPlayerLevel and GetMaxPlayerLevel() end)
    if ok and type(lvl) == "number" and lvl > 0 then return lvl end
    return R.DEFAULT_MAX_LEVEL
end

--- Localized spell name, or nil if the client hasn't loaded it.
function R.SpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if not info and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellID) end
        return info and info.name
    end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
    return nil
end

--- Rank number from the spell's subtext ("Rank 3", "Rang 3", ...), or nil.
function R.SpellRank(spellID)
    local sub
    if C_Spell and C_Spell.GetSpellSubtext then
        sub = C_Spell.GetSpellSubtext(spellID)
    elseif GetSpellSubtext then
        sub = GetSpellSubtext(spellID)
    end
    local n = sub and sub:match("(%d+)")
    return n and tonumber(n) or nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build
-- ─────────────────────────────────────────────────────────────────────────────

--- Decides whether a chain is tracked: anything RankSentinel tracked stays in,
--- vanilla abilities RankSentinel skipped stay out, brand-new Forever ones are in.
local function Tracked(ids)
    local legacyRanked, legacyExcluded = RW.LegacyRanked or {}, RW.LegacyExcluded or {}
    local excluded = false
    for _, id in ipairs(ids) do
        if legacyRanked[id] then return true end
        if legacyExcluded[id] then excluded = true end
    end
    return not excluded
end

local function AddGroup(ranked)
    if #ranked < 2 then return end
    local ids = {}
    for i, e in ipairs(ranked) do
        ids[i] = e.id
    end
    if not Tracked(ids) then return end
    local index = #RW.AbilityGroups + 1
    RW.AbilityGroups[index] = ids
    for _, e in ipairs(ranked) do
        RW.AbilityData[e.id] = { Rank = e.rank, Level = e.level, AbilityGroup = index }
    end
end

--- Builds RW.AbilityData / RW.AbilityGroups from RW.TrainerSpells.
--- Ranks of one ability share a name within a class; RW.ExplicitGroups covers
--- chains that change name (Bear Form → Dire Bear Form).
--- @param nameFn function|nil  spellID → name (tests); defaults to R.SpellName
--- @param rankFn function|nil  spellID → rank number or nil; defaults to R.SpellRank
--- @return number missing  spell IDs whose name wasn't available yet
function R.Build(nameFn, rankFn)
    nameFn, rankFn = nameFn or R.SpellName, rankFn or R.SpellRank
    RW.AbilityData, RW.AbilityGroups = {}, {}
    local trainer = RW.TrainerSpells or {}
    local assigned, missing = {}, 0

    for _, group in ipairs(RW.ExplicitGroups or {}) do
        local levels = trainer[group.class] or {}
        local ranked = {}
        for _, pair in ipairs(group) do
            local id, rank = pair[1], pair[2]
            ranked[#ranked + 1] = { id = id, rank = rank, level = levels[id] or 0 }
            assigned[id] = true
        end
        AddGroup(ranked)
    end

    for class, spells in pairs(trainer) do
        local byName = {}
        for id, level in pairs(spells) do
            if not assigned[id] then
                local name = nameFn(id)
                if name then
                    local key = class .. ":" .. name
                    byName[key] = byName[key] or {}
                    local list = byName[key]
                    list[#list + 1] = { id = id, level = level, rank = rankFn(id) }
                else
                    missing = missing + 1
                end
            end
        end

        for _, raw in pairs(byName) do
            -- A level-0 spell (talent, book, quest) without "Rank N" text has no
            -- knowable position: it could be rank 1 (talent) or the top (book).
            -- Leave it out rather than guess; Build is retried once text loads.
            local list, allRanked = {}, true
            for _, e in ipairs(raw) do
                if e.level <= 0 and not e.rank then
                    if #raw > 1 then missing = missing + 1 end
                else
                    list[#list + 1] = e
                    if not e.rank then allRanked = false end
                end
            end
            if not allRanked then
                -- Ordering falls back to trainer level, where level 0 has no place.
                local kept = {}
                for _, e in ipairs(list) do
                    if e.level > 0 then
                        kept[#kept + 1] = e
                    elseif #raw > 1 then
                        missing = missing + 1
                    end
                end
                list = kept
            end
            table.sort(list, function(a, b)
                if allRanked and a.rank ~= b.rank then return a.rank < b.rank end
                if a.level ~= b.level then return a.level < b.level end
                return a.id < b.id
            end)
            for i, e in ipairs(list) do
                if not allRanked then e.rank = i end
            end
            AddGroup(list)
        end
    end

    return missing
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lookups
-- ─────────────────────────────────────────────────────────────────────────────

--- Returns the ability entry for spellID, or nil if it isn't a ranked ability we track.
function R.Lookup(spellID) return RW.AbilityData[spellID] end

--- Returns nextSpellID, nextData for the rank right above spellID, or nil.
function R.NextRank(spellID)
    local data = RW.AbilityData[spellID]
    if not data then return nil end
    for _, id in ipairs(RW.AbilityGroups[data.AbilityGroup] or {}) do
        local other = RW.AbilityData[id]
        if other and other.Rank == data.Rank + 1 then return id, other end
    end
    return nil
end

--- True when spellID shares a rank chain with anyID.
function R.SameAbility(spellID, anyID)
    local a, b = RW.AbilityData[spellID], RW.AbilityData[anyID]
    if spellID == anyID then return true end
    return a ~= nil and b ~= nil and a.AbilityGroup == b.AbilityGroup
end

--- True when the profile says to skip this ability (common downrank or user-ignored).
--- @param profile table  RW.db.profile
--- @param player string|nil  caster GUID or name, for per-player ignores
function R.IsIgnoredSpell(spellID, profile, player)
    if profile.ignoreCommonDownranks then
        for _, entry in ipairs(R.COMMON_DOWNRANKS) do
            if profile.commonDownranks[entry.id] ~= false and R.SameAbility(spellID, entry.id) then return true end
        end
    end
    for id in pairs(RW.Session.ignoredSpells) do
        if R.SameAbility(spellID, id) then return true end
    end
    if player and RW.Session.ignoredPlayerSpells[RW.Session.PlayerSpellKey(player, spellID)] then return true end
    return false
end

--- Grace window: players get a few levels to visit a trainer before we nag.
--- Returns true when a rank learned at nextRankLevel is still "too new" to flag.
function R.WithinGrace(nextRankLevel, casterLevel, maxLevel)
    maxLevel = maxLevel or R.MaxLevel()
    if casterLevel >= maxLevel or casterLevel < 10 then
        return nextRankLevel > casterLevel
    elseif casterLevel < 20 then
        return nextRankLevel + 3 > casterLevel
    elseif casterLevel < maxLevel - 10 then
        return nextRankLevel + 2 > casterLevel
    end
    return nextRankLevel + 1 > casterLevel
end

--- Decides whether a cast deserves a notification.
--- @param spellID number
--- @param casterLevel number
--- @param targetLevel number|nil  0/nil when unknown
--- @param maxLevel number|nil
--- @param bookRanks boolean|nil  also flag ranks above the trainer's best (books, quests, drops)
--- @return boolean alert, table|nil data, number|nil nextRankLevel, string|nil kind "trainer"|"book"
function R.Check(spellID, casterLevel, targetLevel, maxLevel, bookRanks)
    local data = RW.AbilityData[spellID]
    if not data then return false end
    if type(casterLevel) ~= "number" or casterLevel <= 0 then return false end
    maxLevel = maxLevel or R.MaxLevel()

    -- Downranking on a much lower target (e.g. buffing a lowbie) is fine.
    targetLevel = targetLevel or 0
    if targetLevel >= 1 and targetLevel < casterLevel - R.DOWNRANK_GAP then return false, data end

    local _, nextData = R.NextRank(spellID)
    if not nextData or not nextData.Level then return false, data end

    -- Level 0 = no trainer sells it: a book, quest or drop. The player may simply
    -- not have it, so it's a heads-up rather than a mistake, and only at max level
    -- (where those books and quests live).
    if nextData.Level <= 0 then
        if bookRanks and nextData.Rank > 1 and casterLevel >= maxLevel then return true, data, nil, "book" end
        return false, data
    end

    if R.WithinGrace(nextData.Level, casterLevel, maxLevel) then return false, data, nextData.Level end

    return true, data, nextData.Level, "trainer"
end
