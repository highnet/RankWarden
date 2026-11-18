-- Detector.lua
-- Spots group members casting an outdated rank and hands a notification to Notify.
--
-- WoW: Forever has no combat log for addons (COMBAT_LOG_EVENT_UNFILTERED never
-- fires, CombatLogGetCurrentEventInfo is gone), so this listens to
-- UNIT_SPELLCAST_SUCCEEDED for "player", "party1-4" and "raid1-40" instead.
-- Its payload is secret while unit spellcasts are restricted (encounters, PvP),
-- and unit names/GUIDs can be secret too: anything secret is skipped silently.
--
-- Depends on: RankWarden.lua (Core), Debug.lua, Ranks.lua, Messages.lua,
--             Session.lua, Sync.lua, Notify.lua

local RW = RankWarden

RW.Detector = {}
local DT = RW.Detector

DT.RECENT_CASTS = 64 -- castGUIDs remembered for de-duplication
DT.secretSkips = 0 -- casts skipped because the game hid their details

local recent, recentOrder = {}, {}

--- True when the game hid this value from addons.
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end
DT.Secret = Secret

--- Only real group members: no pets, nameplates, target/focus duplicates.
function DT.IsGroupUnit(unit)
    if type(unit) ~= "string" then return false end
    return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

--- In a raid the same cast arrives for raidN and partyN: keep the first.
local function SeenCast(castGUID)
    if castGUID == nil or Secret(castGUID) then return false end
    if recent[castGUID] then return true end
    recent[castGUID] = true
    recentOrder[#recentOrder + 1] = castGUID
    if #recentOrder > DT.RECENT_CASTS then recent[table.remove(recentOrder, 1)] = nil end
    return false
end

function DT.ResetRecent()
    recent, recentOrder = {}, {}
end

--- Core decision, independent of the event source so tests can call it directly.
--- @param spellID number
--- @param guid string       caster GUID
--- @param name string       caster name (whisper target)
--- @param casterLevel number
--- @param targetLevel number|nil
--- @param class string|nil   class file token ("MAGE"), for colouring
--- @return table|nil notification entry that was enqueued
function DT.Evaluate(spellID, guid, name, casterLevel, targetLevel, class)
    local profile = RW.db.profile
    if not profile.enabled then return nil end
    if not RW.Ranks.Lookup(spellID) then return nil end
    if RW.Ranks.IsIgnoredSpell(spellID, profile, guid) then return nil end
    if not guid or not name or profile.ignored[guid] then return nil end

    local maxLevel = RW.Ranks.MaxLevel()
    if type(casterLevel) ~= "number" or casterLevel <= 0 then return nil end
    if profile.onlyMaxLevel and casterLevel < maxLevel then return nil end

    local data = RW.Ranks.Lookup(spellID)
    local groupKey = guid .. "-" .. data.AbilityGroup
    if RW.Session.groupsNotified[groupKey] and not profile.debug then return nil end

    local alert, _, nextLevel, kind = RW.Ranks.Check(spellID, casterLevel, targetLevel, maxLevel, profile.bookRanks)
    if not alert then return nil end

    -- Leveled up mid-session? Give them time to reach a trainer.
    local seen = RW.Session.levelSeen[guid]
    if not seen then
        RW.Session.levelSeen[guid] = casterLevel
    elseif casterLevel > seen then
        return nil
    end

    local announceKey = ("%s-%d-%d"):format(guid, casterLevel, spellID)
    if profile.announced[announceKey] and not profile.debug then return nil end

    local link = RW.Messages.SpellLink(spellID)
    local fields = { spell = link, rank = data.Rank, level = nextLevel, name = name }
    local ability = RW.Messages.WithRank(link, data.Rank)
    local isSelf = guid == UnitGUID("player")

    -- "Book" kinds: the next rank isn't sold by trainers, so it's a heads-up.
    local suffix = kind == "book" and "Book" or ""
    local entry = { target = name, isWhisper = false, ability = ability }
    -- Auto-whisper only as the group's lead, and only once per player and spell per session.
    local whisperKey = RW.Session.PlayerSpellKey(name, spellID)
    local autoWhisper = profile.whisper and RW.Sync.IsLead() and not RW.Session.whisperedTo[whisperKey]
    if isSelf then
        entry.message = RW.Messages.Build("Self" .. suffix, fields, profile.flavor)
    elseif autoWhisper then
        RW.Session.whisperedTo[whisperKey] = true
        entry.isWhisper = true
        entry.message = RW.Messages.Build("Whisper" .. suffix, fields, profile.flavor)
    else
        entry.message = RW.Messages.Build("Local" .. suffix, fields, profile.flavor)
    end

    RW.Session.groupsNotified[groupKey] = true
    profile.announced[announceKey] = true
    RW.Session.Record({
        name = name,
        guid = guid,
        class = class,
        spellID = spellID,
        spell = link,
        rank = data.Rank,
        nextLevel = nextLevel,
        level = casterLevel,
        book = kind == "book",
        whispered = entry.isWhisper,
    })
    RW.Notify.Enqueue(entry)
    return entry
end

--- Reads caster details from a unit token; nil when anything is hidden or off-limits.
local function ReadCaster(unit)
    if not UnitExists(unit) then return nil end
    if UnitIsCharmed(unit) or UnitIsPossessed(unit) then return nil end
    if UnitIsUnit(unit, "player") and not HasFullControl() then return nil end

    local guid, name, level = UnitGUID(unit), UnitName(unit), UnitLevel(unit)
    local _, class = UnitClass(unit)
    if Secret(class) then class = nil end
    if Secret(guid) or Secret(name) or Secret(level) then return nil end
    if type(guid) ~= "string" or guid:sub(1, 7) ~= "Player-" then return nil end

    -- The caster's target is our best guess at the spell's target (no combat log).
    local targetUnit = unit .. "target"
    local targetLevel = 0
    if UnitExists(targetUnit) then
        local lvl = UnitLevel(targetUnit)
        if not Secret(lvl) then targetLevel = lvl or 0 end
    end
    return guid, name, level, targetLevel, class
end

-- Cast monitor (/rw watch): proves whether Forever delivers other players' casts.
-- One line per player, repeated only when that changes (visible ↔ hidden), so it
-- never spams chat.
DT.stats = { own = 0, others = 0 }
DT.watchState = {} -- player → true once announced

function DT.ResetStats()
    DT.stats = { own = 0, others = 0 }
    DT.secretSkips = 0
    DT.watchState = {}
end

local WATCH_LINE = "|cffffff00[watch]|r %s: |cff00ff00casts are reaching RankWarden|r"

--- Announces, once per player, that their casts get through. Casts the game
--- hides (encounters, instances, PvP) print nothing: they can't be checked anyway.
local function Watch(unit, spellID)
    if not RW.db.profile.watch or unit == "player" or Secret(spellID) then return end
    local who = UnitName(unit)
    if Secret(who) or not who then who = unit end
    if DT.watchState[who] then return end
    DT.watchState[who] = true
    RW.Chat.Print(WATCH_LINE:format(who))
end

--- UNIT_SPELLCAST_SUCCEEDED handler.
function DT.OnSpellcast(_, unit, castGUID, spellID)
    if not RW.db or not RW.db.profile.enabled then return end
    if not DT.IsGroupUnit(unit) then return end
    if SeenCast(castGUID) then return end -- raidN + partyN duplicates

    if unit == "player" then
        DT.stats.own = DT.stats.own + 1
    else
        DT.stats.others = DT.stats.others + 1
        RW.Diag.OnCast(unit, Secret(spellID) or Secret(castGUID))
    end
    Watch(unit, spellID)

    if Secret(spellID) or Secret(castGUID) then
        DT.secretSkips = DT.secretSkips + 1
        return
    end
    if not RW.Ranks.Lookup(spellID) then return end -- cheap exit for the vast majority
    if UnitInBattleground("player") then return end

    local guid, name, level, targetLevel, class = ReadCaster(unit)
    if not guid then
        DT.secretSkips = DT.secretSkips + 1
        return
    end
    return DT.Evaluate(spellID, guid, name, level, targetLevel, class)
end
