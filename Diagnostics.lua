-- Diagnostics.lua
-- Records what Forever hides from addons and builds a plain-text report that
-- can be copied out of the game (/rw diag): which addon restrictions were active
-- when other players' casts were hidden, how many casts got through in combat,
-- and how many tracked spells Forever marks never / always / contextually secret.
-- Depends on: RankWarden.lua (Core), Ranks.lua, Session.lua, Sync.lua, Chat.lua

local RW = RankWarden

RW.Diag = {}
local D = RW.Diag

-- Forever's addon restriction types (Enum.AddOnRestrictionType).
D.RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
D.MAX_EVENTS = 25 -- recent hidden/visible casts kept for the report

function D.Reset()
    D.hiddenBy = {} -- "Combat+Map" (or "none") → count of hidden casts
    D.visibleBy = {} -- same, for casts that got through
    D.events = {} -- recent { time, unit, hidden, restrictions }
end
D.Reset()

local function Now() return (date and date("%H:%M:%S")) or "" end

--- Names of the addon restrictions active right now.
function D.ActiveRestrictions()
    local api, enum = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
    local active = {}
    if not (api and api.IsAddOnRestrictionActive and enum) then return active end
    for _, name in ipairs(D.RESTRICTIONS) do
        local value = enum[name]
        if value ~= nil then
            local ok, on = pcall(api.IsAddOnRestrictionActive, value)
            if ok and on then active[#active + 1] = name end
        end
    end
    return active
end

local function Key(active) return #active > 0 and table.concat(active, "+") or "none" end

local function Remember(unit, hidden, active)
    local events = D.events
    events[#events + 1] = { time = Now(), unit = unit, hidden = hidden, restrictions = Key(active) }
    while #events > D.MAX_EVENTS do
        table.remove(events, 1)
    end
end

--- Called by the detector for every cast from another group member.
function D.OnCast(unit, hidden)
    local active = D.ActiveRestrictions()
    local key = Key(active)
    local bucket = hidden and D.hiddenBy or D.visibleBy
    bucket[key] = (bucket[key] or 0) + 1
    Remember(unit, hidden, active)
end

--- How many tracked spells Forever marks never / always / contextually secret as casts.
--- @return table counts by level name, number total
function D.SecrecyCensus()
    local counts, total = {}, 0
    local get = C_Secrets and C_Secrets.GetSpellCastSecrecy
    local names = {}
    for name, value in pairs((Enum and Enum.SecrecyLevel) or {}) do
        names[value] = name
    end
    for spellID in pairs(RW.AbilityData) do
        total = total + 1
        local level = "unknown"
        if get then
            local ok, value = pcall(get, spellID)
            if ok and value ~= nil then level = names[value] or tostring(value) end
        end
        counts[level] = (counts[level] or 0) + 1
    end
    return counts, total
end

local function Sorted(map)
    local keys = {}
    for k in pairs(map) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = ("%s %d"):format(k, map[k])
    end
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

--- The full plain-text report (no colour codes, so it pastes cleanly anywhere).
function D.Report()
    local p = RW.db.profile
    local lines = {}
    local function add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

    local version, build, _, interface = "?", "?", nil, "?"
    if GetBuildInfo then
        version, build, _, interface = GetBuildInfo()
    end
    add("RankWarden %s diagnostics, %s", RW.VERSION, (date and date("%Y-%m-%d %H:%M")) or "")
    add("Client %s (build %s), interface %s", tostring(version), tostring(build), tostring(interface))
    add("")
    add(
        "Settings: detection %s, auto-whisper %s, max-level only %s, book ranks %s, cast monitor %s",
        tostring(p.enabled),
        tostring(p.whisper),
        tostring(p.onlyMaxLevel),
        tostring(p.bookRanks),
        tostring(p.watch)
    )
    add(
        "Common downranks ignored: %s; session spell ignores: %d; per-player ignores: %d",
        tostring(p.ignoreCommonDownranks),
        RW.Slash.Count(RW.Session.ignoredSpells),
        RW.Slash.Count(RW.Session.ignoredPlayerSpells)
    )
    add("Rank chains: %d (tracked spell IDs: %d)", #RW.AbilityGroups, RW.Slash.Count(RW.AbilityData))
    add("")

    local st = RW.Detector.stats
    add("Casts seen this session: yours %d, group %d, hidden %d", st.own, st.others, RW.Detector.secretSkips)
    add("Group casts hidden, by active restriction: %s", Sorted(D.hiddenBy))
    add("Group casts visible, by active restriction: %s", Sorted(D.visibleBy))
    add("Restrictions active now: %s", Key(D.ActiveRestrictions()))
    local blocked, reason = RW.Chat.ChatBlocked()
    add("Addon chat: %s", blocked and ("blocked (" .. reason .. ")") or "allowed")
    local counts, total = D.SecrecyCensus()
    add("Tracked spells as casts (C_Secrets): %s of %d", Sorted(counts), total)
    add("")

    add(
        "Group: %s, lead %s, RankWarden peers %d",
        (IsInRaid and IsInRaid() and "raid") or (IsInGroup and IsInGroup() and "party") or "solo",
        RW.Sync.Lead(),
        RW.Slash.Count(RW.Sync.peers)
    )
    add("Detections this session: %d, queued whispers: %d", #RW.Session.report, #RW.Session.queue)
    for i = math.max(1, #RW.Session.report - 9), #RW.Session.report do
        local r = RW.Session.report[i]
        add(
            "  %s %s %s (spell %s) rank %s, next %s%s",
            r.time or "",
            tostring(r.name),
            (tostring(r.spell):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|[hr]", "")),
            tostring(r.spellID),
            tostring(r.rank),
            r.book and "book/quest" or tostring(r.nextLevel),
            r.whispered and ", whispered" or ""
        )
    end
    add("")
    add("Recent group casts (oldest first):")
    if #D.events == 0 then add("  none yet") end
    for _, e in ipairs(D.events) do
        add("  %s %s %s (restrictions: %s)", e.time, e.unit, e.hidden and "HIDDEN" or "visible", e.restrictions)
    end
    return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Copyable report window (/rw diag)
-- ─────────────────────────────────────────────────────────────────────────────

local function AceGUI() return LibStub("AceGUI-3.0") end

--- Selects the whole report so Ctrl+C copies it.
function D.SelectAll()
    if not D.box then return end
    D.box:SetFocus()
    D.box:HighlightText()
end

function D.Refresh()
    if not D.box then return end
    D.box:SetText(D.Report())
    D.SelectAll()
end

function D.Show()
    if D.frame then
        D.Refresh()
        return
    end
    local f = AceGUI():Create("Frame")
    f:SetTitle("RankWarden diagnostics")
    f:SetStatusText("Press Ctrl+C to copy the selected report, then paste it wherever you need it.")
    f:SetWidth(640)
    f:SetHeight(520)
    f:SetLayout("Flow")
    f:SetCallback("OnClose", function(widget)
        AceGUI():Release(widget)
        D.frame, D.box = nil, nil
    end)
    D.frame = f

    local hint = AceGUI():Create("Label")
    hint:SetText(
        "The report is already selected: press |cffffd100Ctrl+C|r to copy it. "
            .. "Use Select all if you clicked into the text."
    )
    hint:SetFullWidth(true)
    f:AddChild(hint)

    for _, b in ipairs({
        { "Select all", D.SelectAll },
        { "Refresh", D.Refresh },
        {
            "Reset counters",
            function()
                D.Reset()
                RW.Detector.ResetStats()
                D.Refresh()
            end,
        },
    }) do
        local button = AceGUI():Create("Button")
        button:SetText(b[1])
        button:SetRelativeWidth(0.32)
        button:SetCallback("OnClick", b[2])
        f:AddChild(button)
    end

    local box = AceGUI():Create("MultiLineEditBox")
    box:SetLabel("")
    box:DisableButton(true)
    box:SetFullWidth(true)
    box:SetNumLines(22)
    f:AddChild(box)
    D.box = box
    D.Refresh()
end
