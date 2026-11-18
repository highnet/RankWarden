-- UI.lua
-- Shared look and actions for the HUD and the main window:
-- class colours, spell icons, summaries, and the buttons' actions
-- (whisper now, ignore spell/player, link to chat, reset).
-- Depends on: RankWarden.lua (Core), Chat.lua, Messages.lua, Session.lua, Notify.lua

local RW = RankWarden

RW.UI = {}
local U = RW.UI

U.NEW_SECONDS = 20 -- detections this recent are highlighted
U.MAX_WHISPERS_PER_PLAYER = 3 -- manual "Whisper" sends at most this many lines

U.COLORS = {
    muted = "ff888888",
    rank = "ffaaaaaa",
    next = "ffffd100",
    book = "ffff9900",
    count = "ffff5555",
    new = "ff33ff99",
    good = "ff33ff99",
    bad = "ffff5555",
}

function U.Color(key, text) return "|c" .. (U.COLORS[key] or "ffffffff") .. tostring(text) .. "|r" end

local function Now() return (GetTime and GetTime()) or 0 end

-- ─────────────────────────────────────────────────────────────────────────────
-- Formatting
-- ─────────────────────────────────────────────────────────────────────────────

--- Player name in their class colour (white when the class is unknown).
function U.ClassName(name, class)
    name = name or "?"
    if class and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(class)
        if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(name) end
    end
    return "|cffffffff" .. name .. "|r"
end

--- Inline spell icon ("|T...|t "), or "" when unavailable.
function U.SpellIcon(spellID, size)
    if not spellID or not (C_Spell and C_Spell.GetSpellTexture) then return "" end
    local tex = C_Spell.GetSpellTexture(spellID)
    if not tex then return "" end
    size = size or 14
    return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t "):format(tostring(tex), size, size)
end

--- "next at 18" / "book/quest" / "".
function U.NextText(rec, long)
    if rec.book then
        return U.Color("book", long and "higher rank from a book, quest or drop" or "book/quest")
    elseif rec.nextLevel then
        return U.Color("next", (long and "next rank at level %d" or "next at %d"):format(rec.nextLevel))
    end
    return ""
end

function U.IsNew(rec) return rec.at ~= nil and Now() - rec.at < U.NEW_SECONDS end

--- Counts for a report: players, distinct lower ranks, and a summary line.
function U.Summary(groups)
    local ranks = 0
    for _, p in ipairs(groups) do
        ranks = ranks + #p.entries
    end
    local text
    if #groups == 0 then
        text = "No lower ranks yet"
    else
        text = ("%d %s · %d lower %s"):format(
            #groups,
            #groups == 1 and "player" or "players",
            ranks,
            ranks == 1 and "rank" or "ranks"
        )
    end
    return #groups, ranks, text
end

--- Groups detections by player, one entry per spell rank, players sorted by name.
--- @return table { { name, guid, class, level, entries = { rec, ... } }, ... }
function U.GroupByPlayer(report)
    local byName, order = {}, {}
    for _, rec in ipairs(report or {}) do
        local name = rec.name or "?"
        local player = byName[name]
        if not player then
            player = { name = name, entries = {}, seen = {} }
            byName[name] = player
            order[#order + 1] = player
        end
        player.guid = rec.guid or player.guid
        player.class = rec.class or player.class
        player.level = rec.level or player.level
        local key = tostring(rec.spellID or rec.spell) .. "#" .. tostring(rec.rank)
        if not player.seen[key] then
            player.seen[key] = true
            player.entries[#player.entries + 1] = rec
        end
    end
    table.sort(order, function(a, b) return a.name < b.name end)
    for _, p in ipairs(order) do
        p.seen = nil
    end
    return order
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Actions
-- ─────────────────────────────────────────────────────────────────────────────

local function RefreshAll()
    if RW.HUD and RW.HUD.Refresh then RW.HUD.Refresh() end
    if RW.GUI and RW.GUI.Refresh then RW.GUI.Refresh() end
end
U.RefreshAll = RefreshAll

--- Whisper one player about their lower ranks now (even with auto-whisper off).
--- @return number whispers queued
function U.WhisperPlayer(name)
    local profile = RW.db.profile
    local sent = 0
    for _, p in ipairs(U.GroupByPlayer(RW.Session.report)) do
        if p.name == name then
            for _, rec in ipairs(p.entries) do
                if sent >= U.MAX_WHISPERS_PER_PLAYER then break end
                local fields = { spell = rec.spell, rank = rec.rank, level = rec.nextLevel, name = name }
                RW.Notify.Enqueue({
                    target = name,
                    isWhisper = true,
                    ability = ("%s (Rank %d)"):format(tostring(rec.spell), rec.rank or 0),
                    message = RW.Messages.Build(rec.book and "WhisperBook" or "Whisper", fields, profile.flavor),
                })
                rec.whispered = true
                sent = sent + 1
            end
        end
    end
    if sent > 0 then
        local blocked = RW.Chat.ChatBlocked()
        RW.Chat.Print(
            ("Whispering %s (%d)%s."):format(name, sent, blocked and " — queued until chat is allowed" or "")
        )
    end
    RefreshAll()
    return sent
end

--- Whisper everyone in the current list (never yourself).
function U.WhisperAll()
    local me = UnitName("player")
    local total = 0
    for _, p in ipairs(U.GroupByPlayer(RW.Session.report)) do
        if p.name ~= me then total = total + U.WhisperPlayer(p.name) end
    end
    if total == 0 then RW.Chat.Print("Nobody to whisper.") end
    return total
end

--- Ignore every rank of a detection's spell and drop it from the list.
function U.IgnoreSpell(rec)
    if not rec.spellID then return end
    RW.db.profile.ignoredSpells[rec.spellID] = true
    local kept = {}
    for _, r in ipairs(RW.Session.report) do
        if not RW.Ranks.SameAbility(r.spellID or -1, rec.spellID) then kept[#kept + 1] = r end
    end
    RW.Session.report = kept
    RW.Chat.Print("Ignoring every rank of " .. tostring(rec.spell) .. ". Undo in /rw → Ignored.")
    RefreshAll()
end

--- Ignore a player and drop them from the list.
function U.IgnorePlayer(name, guid)
    if guid then RW.db.profile.ignored[guid] = name end
    local kept = {}
    for _, r in ipairs(RW.Session.report) do
        if r.name ~= name then kept[#kept + 1] = r end
    end
    RW.Session.report = kept
    RW.Chat.Print("Ignoring " .. tostring(name) .. ". Undo in /rw → Ignored.")
    RefreshAll()
end

--- Put a spell link into the chat box.
function U.LinkSpell(rec)
    if ChatEdit_InsertLink and rec.spell then ChatEdit_InsertLink(rec.spell) end
end

--- Reset: clear the list and forget who was notified, so new casts show again.
function U.Reset()
    local n = #RW.Session.report
    RW.Session.Reset()
    RW.db.profile.announced = {}
    RW.Chat.Print(("Reset — cleared %d detections."):format(n))
    RefreshAll()
end

--- Spell tooltip with action hints.
function U.ShowSpellTooltip(owner, rec, anchor)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if rec.spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(rec.spellID)
    else
        GameTooltip:AddLine(tostring(rec.spell))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Used: Rank %d · %s"):format(rec.rank or 0, U.NextText(rec, true)), 1, 1, 1, true)
    GameTooltip:AddLine(U.Color("muted", "Shift-click: link in chat · Right-click: ignore this spell"))
    GameTooltip:Show()
end

function U.ShowPlayerTooltip(owner, player, anchor)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:AddLine(U.ClassName(player.name, player.class))
    GameTooltip:AddLine(("%d lower %s"):format(#player.entries, #player.entries == 1 and "rank" or "ranks"), 1, 1, 1)
    GameTooltip:AddLine(U.Color("muted", "Click: whisper them now · Right-click: ignore player"))
    GameTooltip:Show()
end

function U.HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end
