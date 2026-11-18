-- GUI.lua
-- Main window (AceGUI-3.0) and minimap button.
--   /rw toggles the window. Tabs: Detections · History · Ignored · Settings.
-- Pure helpers (formatting, positions) are separated so tests can cover them;
-- everything touching AceGUI or frames is created lazily on first use.
-- Depends on: every module above it in the TOC.

local RW = RankWarden

RW.GUI = {}
local G = RW.GUI

G.TABS = {
    { value = "detections", text = "Detections" },
    { value = "history", text = "History" },
    { value = "ignored", text = "Ignored" },
    { value = "settings", text = "Settings" },
}
G.currentTab = "detections"
G.MINIMAP_RADIUS = 80
G.ICON = 136037

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4444off|r" end

--- One detection as a chat-coloured line.
function G.FormatRecord(rec)
    local U = RW.UI
    local how = rec.whispered and "|cff00ccffwhispered|r" or "|cff888888local|r"
    local nextText = U.NextText(rec, true)
    return ("|cff888888%s|r  %s  %s%s %s  %s  %s"):format(
        rec.time or "",
        U.ClassName(rec.name, rec.class),
        U.SpellIcon(rec.spellID),
        rec.spell or "?",
        U.Color("rank", "Rank " .. (rec.rank or 0)),
        nextText,
        how
    )
end

--- Status bar text for the window.
function G.StatusText()
    local p = RW.db.profile
    local mode = p.whisper and "whispering" or "local only"
    local blocked, reason = RW.Chat.ChatBlocked()
    local chat = blocked and (" · chat blocked (" .. reason .. ")") or ""
    local st = RW.Detector.stats
    return ("Detection %s · %s · lead: %s · casts seen: you %d, group %d, hidden %d%s"):format(
        OnOff(p.enabled),
        mode,
        RW.Sync.Lead(),
        st.own,
        st.others,
        RW.Detector.secretSkips,
        chat
    )
end

--- Minimap button offset for an angle in degrees.
function G.MinimapPosition(angle, radius)
    local rad = math.rad(angle or 0)
    radius = radius or G.MINIMAP_RADIUS
    return math.cos(rad) * radius, math.sin(rad) * radius
end

--- Angle (degrees) from the minimap centre to a cursor position.
function G.AngleFromCursor(cx, cy, mx, my)
    local atan2 = math.atan2 or math.atan -- Lua 5.1 (WoW) vs 5.3+ (tests)
    return math.deg(atan2(my - cy, mx - cx)) % 360
end

--- Newest-first copy of a list.
function G.Reversed(list)
    local out = {}
    for i = #list, 1, -1 do
        out[#out + 1] = list[i]
    end
    return out
end

--- Spell ID from a spell link or a plain number, or nil.
function G.ParseSpell(text)
    text = text or ""
    return tonumber(text:match("|Hspell:(%d+)") or text:match("^%s*(%d+)%s*$") or "")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Widget helpers (AceGUI)
-- ─────────────────────────────────────────────────────────────────────────────

local function AceGUI() return LibStub("AceGUI-3.0") end

local function Label(parent, text, width)
    local w = AceGUI():Create("Label")
    w:SetText(text)
    w:SetFontObject(GameFontHighlight)
    if width then
        w:SetRelativeWidth(width)
    else
        w:SetFullWidth(true)
    end
    parent:AddChild(w)
    return w
end

local function Button(parent, text, width, onClick)
    local w = AceGUI():Create("Button")
    w:SetText(text)
    w:SetRelativeWidth(width)
    w:SetCallback("OnClick", onClick)
    parent:AddChild(w)
    return w
end

local function Check(parent, text, key, width, after, desc)
    local w = AceGUI():Create("CheckBox")
    w:SetLabel(text)
    if desc then w:SetDescription(desc) end
    w:SetValue(RW.db.profile[key])
    w:SetRelativeWidth(width)
    w:SetCallback("OnValueChanged", function(_, _, v)
        RW.db.profile[key] = v
        if after then after() end
        G.UpdateStatus()
    end)
    parent:AddChild(w)
    return w
end

local function Heading(parent, text)
    local w = AceGUI():Create("Heading")
    w:SetText(text)
    w:SetFullWidth(true)
    parent:AddChild(w)
end

local function Scroll(parent)
    local holder = AceGUI():Create("SimpleGroup")
    holder:SetFullWidth(true)
    holder:SetFullHeight(true)
    holder:SetLayout("Fill")
    parent:AddChild(holder)
    local scroll = AceGUI():Create("ScrollFrame")
    scroll:SetLayout("List")
    holder:AddChild(scroll)
    return scroll
end

local function Row(parent)
    local row = AceGUI():Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")
    parent:AddChild(row)
    return row
end

local function SpellName(id) return RW.Ranks.SpellName(id) or ("spell " .. id) end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tabs
-- ─────────────────────────────────────────────────────────────────────────────

local U = RW.UI

local function Muted(text) return U.Color("muted", text) end

--- Grouped-by-player list with per-player and per-spell actions.
local function PlayerList(scroll, report)
    local groups = U.GroupByPlayer(report)
    if #groups == 0 then
        Label(
            scroll,
            Muted("Nothing yet this session.")
                .. "\n\n"
                .. Muted(
                    "Lower ranks cast by you or your group show up here and in the HUD. "
                        .. "Not seeing your group? Turn on the cast monitor below and ask someone to cast."
                )
        )
        return
    end
    local me = UnitName("player")
    for _, p in ipairs(groups) do
        local head = Row(scroll)
        local level = p.level and (" " .. Muted("level " .. p.level)) or ""
        local whispered = false
        for _, rec in ipairs(p.entries) do
            if rec.whispered then whispered = true end
        end
        Label(
            head,
            ("%s%s  %s%s"):format(
                U.ClassName(p.name, p.class),
                level,
                U.Color("count", #p.entries .. (#p.entries == 1 and " lower rank" or " lower ranks")),
                whispered and ("  " .. Muted("· whispered")) or ""
            ),
            0.52
        )
        if p.name ~= me then
            Button(head, whispered and "Whisper again" or "Whisper", 0.22, function() U.WhisperPlayer(p.name) end)
            Button(head, "Ignore player", 0.22, function() U.IgnorePlayer(p.name, p.guid) end)
        end
        for _, rec in ipairs(p.entries) do
            local line = Row(scroll)
            local new = U.IsNew(rec) and ("  " .. U.Color("new", "new")) or ""
            Label(
                line,
                ("      %s%s %s  %s%s"):format(
                    U.SpellIcon(rec.spellID, 16),
                    rec.spell or "?",
                    U.Color("rank", "Rank " .. (rec.rank or 0)),
                    U.NextText(rec, true),
                    new
                ),
                0.74
            )
            Button(line, "Ignore spell", 0.22, function() U.IgnoreSpell(rec) end)
        end
    end
end

local function HistoryRows(scroll, records)
    if #records == 0 then
        Label(scroll, Muted("No history yet. Detections are kept here between sessions."))
        return
    end
    for _, rec in ipairs(records) do
        Label(scroll, G.FormatRecord(rec))
    end
end

local REPORT_CHANNELS = { party = "Party", raid = "Raid", guild = "Guild", say = "Say", self = "Just me" }
local REPORT_ORDER = { "party", "raid", "guild", "say", "self" }

local DRAW = {}

function DRAW.detections(container)
    local _, _, summary = U.Summary(U.GroupByPlayer(RW.Session.report))

    local bar = Row(container)
    Label(bar, "|cffffd100" .. summary .. "|r", 0.4)
    Button(bar, "Whisper all", 0.19, function() U.WhisperAll() end)
    Button(bar, "Reset", 0.19, function() U.Reset() end)
    Button(bar, RW.HUD.IsShown() and "Hide HUD" or "Show HUD", 0.19, function()
        RW.HUD.Toggle()
        G.Refresh()
    end)

    local bar2 = Row(container)
    local channel = AceGUI():Create("Dropdown")
    channel:SetLabel("Report this session to")
    channel:SetList(REPORT_CHANNELS, REPORT_ORDER)
    channel:SetValue(G.reportChannel or "party")
    channel:SetRelativeWidth(0.3)
    channel:SetCallback("OnValueChanged", function(_, _, v) G.reportChannel = v end)
    bar2:AddChild(channel)
    Button(bar2, "Report", 0.15, function() RW.Slash.COMMANDS.report.fn(G.reportChannel or "party") end)
    local queued = #RW.Session.queue
    if queued > 0 then
        Button(bar2, ("Send %d queued"):format(queued), 0.2, function()
            RW.Notify.Flush()
            G.Refresh()
        end)
    end
    local watch = AceGUI():Create("CheckBox")
    watch:SetLabel("Cast monitor")
    watch:SetDescription("Print every cast from your group to chat, to check they're seen.")
    watch:SetValue(RW.Detector.watch)
    watch:SetRelativeWidth(0.33)
    watch:SetCallback("OnValueChanged", function(_, _, v) RW.Detector.watch = v end)
    bar2:AddChild(watch)

    PlayerList(Scroll(container), RW.Session.report)
end

function DRAW.history(container)
    local bar = Row(container)
    Label(bar, Muted(("Last %d detections, kept between sessions."):format(RW.Session.HISTORY_SIZE)), 0.7)
    Button(bar, "Clear history", 0.25, function()
        RW.db.profile.history = {}
        G.Refresh()
    end)
    local rows = {}
    for _, rec in ipairs(G.Reversed(RW.db.profile.history)) do
        rows[#rows + 1] = {
            time = (rec.day or "") .. " " .. (rec.time or ""),
            name = rec.name,
            class = rec.class,
            spell = rec.spell,
            spellID = rec.spellID,
            rank = rec.rank,
            nextLevel = rec.nextLevel,
            book = rec.book,
            whispered = rec.whispered,
        }
    end
    HistoryRows(Scroll(container), rows)
end

function DRAW.ignored(container)
    local scroll = Scroll(container)
    local p = RW.db.profile

    Heading(scroll, "Ignored spells (every rank, this session only)")
    local add = AceGUI():Create("EditBox")
    add:SetLabel("Add a spell: shift-click it from your spellbook, or type its ID")
    add:SetFullWidth(true)
    add:SetCallback("OnEnterPressed", function(w, _, text)
        local id = G.ParseSpell(text)
        if id then
            RW.Session.ignoredSpells[id] = true
            RW.Chat.Print("Ignoring every rank of " .. SpellName(id) .. " for this session.")
            G.Refresh()
        else
            RW.Chat.Warn("That isn't a spell link or ID.")
            w:SetText("")
        end
    end)
    scroll:AddChild(add)

    local any = false
    for id in pairs(RW.Session.ignoredSpells) do
        any = true
        local row = Row(scroll)
        Label(row, SpellName(id) .. " |cff888888(" .. id .. ")|r", 0.75)
        Button(row, "Remove", 0.2, function()
            RW.Session.ignoredSpells[id] = nil
            G.Refresh()
        end)
    end
    if not any then Label(scroll, "|cff888888None.|r") end

    Heading(scroll, "Commonly downranked spells")
    local master = Row(scroll)
    Check(master, "Ignore spells people downrank on purpose", "ignoreCommonDownranks", 1.0, G.Refresh)
    local grid = Row(scroll)
    for _, entry in ipairs(RW.Ranks.COMMON_DOWNRANKS) do
        local id = entry.id
        local w = AceGUI():Create("CheckBox")
        w:SetLabel(RW.Ranks.SpellName(id) or entry.label)
        w:SetValue(p.commonDownranks[id] ~= false)
        w:SetDisabled(not p.ignoreCommonDownranks)
        w:SetRelativeWidth(0.33)
        w:SetCallback("OnValueChanged", function(_, _, v)
            if v then
                p.commonDownranks[id] = nil
            else
                p.commonDownranks[id] = false
            end
        end)
        grid:AddChild(w)
    end

    Heading(scroll, "Ignored players")
    local tbar = Row(scroll)
    Button(tbar, "Ignore / unignore target", 0.4, function()
        RW.Slash.COMMANDS.ignore.fn("")
        G.Refresh()
    end)
    any = false
    for guid, name in pairs(p.ignored) do
        any = true
        local row = Row(scroll)
        Label(row, tostring(name), 0.75)
        Button(row, "Remove", 0.2, function()
            p.ignored[guid] = nil
            G.Refresh()
        end)
    end
    if not any then Label(scroll, "|cff888888None.|r") end
end

function DRAW.settings(container)
    container:SetLayout("Fill")
    LibStub("AceConfigDialog-3.0"):Open("RankWarden", container)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Window
-- ─────────────────────────────────────────────────────────────────────────────

local function SelectTab(tabs, value)
    G.currentTab = value
    tabs:ReleaseChildren()
    tabs:SetLayout("Flow")
    RW.Debug.SafeCall(DRAW[value] or DRAW.detections, tabs)
    G.UpdateStatus()
end

function G.UpdateStatus()
    if G.frame then G.frame:SetStatusText(G.StatusText()) end
end

function G.IsShown() return G.frame ~= nil end

function G.Open()
    if G.frame then return end
    local f = AceGUI():Create("Frame")
    f:SetTitle("RankWarden")
    f:SetWidth(700)
    f:SetHeight(520)
    -- AceGUI remembers size and position in this table between sessions.
    f:SetStatusTable(RW.db.profile.window)
    f:SetLayout("Flow")
    f:SetCallback("OnClose", function(widget)
        AceGUI():Release(widget)
        G.frame, G.tabs = nil, nil
    end)
    G.frame = f

    -- Close with Escape.
    _G.RankWardenMainFrame = f.frame
    local special = _G.UISpecialFrames
    if special then
        local present = false
        for _, n in ipairs(special) do
            if n == "RankWardenMainFrame" then present = true end
        end
        if not present then table.insert(special, "RankWardenMainFrame") end
    end

    local top = Row(f)
    Check(top, "Detection", "enabled", 0.24, nil, "Watch you, your party and raid for lower ranks.")
    Check(top, "Auto-whisper", "whisper", 0.24, nil, "Whisper players automatically. Off = only you see it.")
    Check(top, "Max level only", "onlyMaxLevel", 0.24, nil, "Only check casters at max level.")
    Check(top, "Book ranks", "bookRanks", 0.24, nil, "Mention ranks trainers don't sell (books, quests, drops).")

    local tabs = AceGUI():Create("TabGroup")
    tabs:SetFullWidth(true)
    tabs:SetFullHeight(true)
    tabs:SetTabs(G.TABS)
    tabs:SetCallback("OnGroupSelected", function(w, _, value) SelectTab(w, value) end)
    f:AddChild(tabs)
    G.tabs = tabs
    tabs:SelectTab(G.currentTab)
end

function G.Close()
    if G.frame then G.frame:Hide() end -- OnClose releases it
end

--- AceGUI frames aren't protected, so this works in combat too.
function G.Toggle()
    if G.IsShown() then
        G.Close()
    else
        G.Open()
    end
end

--- Redraws the open tab (no-op while the window is closed).
function G.Refresh()
    if not G.tabs then return end
    if G.currentTab == "settings" then
        G.UpdateStatus()
        return
    end
    SelectTab(G.tabs, G.currentTab)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Minimap button
-- ─────────────────────────────────────────────────────────────────────────────

function G.PlaceMinimapButton()
    local b = G.minimapButton
    if not b then return end
    local x, y = G.MinimapPosition(RW.db.profile.minimap.angle)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
    b:SetShown(not RW.db.profile.minimap.hide)
end

function G.CreateMinimapButton()
    if G.minimapButton or not Minimap or not CreateFrame then return end
    local b = CreateFrame("Button", "RankWardenMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(G.ICON)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            RW.db.profile.enabled = not RW.db.profile.enabled
            RW.Chat.Print("Detection: " .. OnOff(RW.db.profile.enabled))
            G.Refresh()
        else
            G.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = Minimap:GetCenter()
            RW.db.profile.minimap.angle = G.AngleFromCursor(cx, cy, mx / scale, my / scale)
            G.PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("RankWarden")
        GameTooltip:AddLine(G.StatusText(), 1, 1, 1, true)
        GameTooltip:AddLine("|cffffff00Left-click|r window · |cffffff00Right-click|r on/off · |cffffff00Drag|r move")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    G.minimapButton = b
    G.PlaceMinimapButton()
end
