-- HUD.lua
-- Compact, movable on-screen list of lower ranks this session, grouped by player.
--   Header:  icon · "Lower ranks N" · [–/+ collapse] [window] [x]
--   Player rows (class coloured): [Whisper] button = whisper that player now,
--                                 right-click = ignore player
--   Spell rows (icon + rank + next): hover = spell tooltip, shift-click = link,
--                                    right-click = ignore spell
--   Footer:  [Reset] · "2 players · 3 lower ranks"
-- Pops open on new detections (optional). /rw hud · /rw hudlock · /rw hudreset
-- Depends on: RankWarden.lua (Core), Session.lua, UI.lua, Chat.lua

local RW = RankWarden

RW.HUD = {}
local H = RW.HUD
local U = RW.UI

H.WIDTH = 290
H.ROW_HEIGHT = 16
H.HEADER_HEIGHT = 24
H.FOOTER_HEIGHT = 22
H.MAX_ROWS = 22
H.PADDING = 6

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure helpers
-- ─────────────────────────────────────────────────────────────────────────────

H.GroupByPlayer = function(report) return U.GroupByPlayer(report) end

--- Text of one spell row.
function H.FormatEntry(rec)
    local new = U.IsNew(rec) and (" " .. U.Color("new", "new")) or ""
    return ("%s%s  %s%s"):format(U.SpellIcon(rec.spellID), U.SpellWithRank(rec, true), U.NextText(rec), new)
end

--- Text of one player row.
function H.FormatPlayer(p)
    local level = p.level and (" " .. U.Color("muted", "(" .. p.level .. ")")) or ""
    local mark = H.HasWhispered(p) and ("  " .. U.Color("muted", "whispered")) or ""
    return ("%s%s  %s%s"):format(U.ClassName(p.name, p.class), level, U.Color("count", #p.entries), mark)
end

--- True when this player has been whispered this session.
function H.HasWhispered(p)
    for _, rec in ipairs(p.entries) do
        if rec.whispered then return true end
    end
    return false
end

--- Rows for the HUD: { kind = "player"|"spell"|"more"|"empty", text, player, rec }.
function H.BuildRows(report, maxRows)
    maxRows = maxRows or H.MAX_ROWS
    local rows, total = {}, 0
    for _, p in ipairs(U.GroupByPlayer(report)) do
        total = total + #p.entries
        rows[#rows + 1] = { kind = "player", text = H.FormatPlayer(p), player = p }
        for _, rec in ipairs(p.entries) do
            rows[#rows + 1] = { kind = "spell", text = "   " .. H.FormatEntry(rec), rec = rec, player = p }
        end
    end
    if #rows > maxRows then
        local hidden = #rows - (maxRows - 1)
        for i = #rows, maxRows, -1 do
            rows[i] = nil
        end
        rows[#rows + 1] =
            { kind = "more", text = U.Color("muted", ("… %d more — open the window (/rw)"):format(hidden)) }
    end
    if #rows == 0 then
        rows[1] = { kind = "empty", text = U.Color("muted", "No lower ranks seen yet. They'll appear here.") }
    end
    return rows, total
end

--- Just the row texts (kept for callers that only need text).
function H.BuildLines(report, maxRows)
    local rows, total = H.BuildRows(report, maxRows)
    local lines = {}
    for i, r in ipairs(rows) do
        lines[i] = r.text
    end
    return lines, total
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame
-- ─────────────────────────────────────────────────────────────────────────────

local function Settings() return RW.db.profile.hud end

local function SavePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    Settings().point = { point, relPoint, x, y }
end

local function ApplyPosition(frame)
    local p = Settings().point
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function Hint(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

--- Small text button for the footer.
local function TextButton(parent, label, width, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 18)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) Hint(self, tooltip) end)
    b:SetScript("OnLeave", U.HideTooltip)
    return b
end

local function IconButton(parent, texture, tooltip, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(16, 16)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) Hint(self, tooltip) end)
    b:SetScript("OnLeave", U.HideTooltip)
    return b
end

function H.Create()
    if H.frame or not CreateFrame then return H.frame end

    local f = CreateFrame("Frame", "RankWardenHUD", UIParent, "BackdropTemplate")
    f:SetSize(H.WIDTH, 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
        f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    end
    f:SetScript("OnDragStart", function(self)
        if not Settings().locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)

    -- Header
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("TOPLEFT", H.PADDING + 2, -H.PADDING - 1)
    icon:SetTexture(RW.GUI and RW.GUI.ICON or 136037)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    title:SetText("Lower ranks")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() H.Hide() end)
    f.close = close

    f.windowButton = IconButton(
        f,
        "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Open the RankWarden window",
        function() RW.GUI.Toggle() end
    )
    f.windowButton:SetPoint("RIGHT", close, "LEFT", -1, 0)

    f.collapseButton = IconButton(
        f,
        "Interface\\Buttons\\UI-MinusButton-Up",
        "Collapse / expand",
        function() H.SetCollapsed(not Settings().collapsed) end
    )
    f.collapseButton:SetPoint("RIGHT", f.windowButton, "LEFT", -3, 0)

    -- Footer
    f.reset = TextButton(
        f,
        "Reset",
        64,
        "Clear the list and forget who was notified, so new casts show again.",
        function() U.Reset() end
    )
    f.reset:SetPoint("BOTTOMLEFT", H.PADDING, H.PADDING - 1)

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.summary:SetPoint("BOTTOMRIGHT", -H.PADDING - 2, H.PADDING + 3)
    f.summary:SetJustifyH("RIGHT")

    f.rows = {}
    H.frame = f
    ApplyPosition(f)
    f:SetScale(Settings().scale or 1)
    f:Hide()
    return f
end

local function OnRowEnter(self)
    local row = self.row
    if not row then return end
    if row.kind == "spell" then
        U.ShowSpellTooltip(self, row.rec, "ANCHOR_LEFT")
    elseif row.kind == "player" then
        U.ShowPlayerTooltip(self, row.player, "ANCHOR_LEFT")
    elseif row.kind == "warning" then
        Hint(self, RW.Diag.LimitText() .. " Forever hides other players' casts from addons in restricted areas.")
    end
end

local function OnRowClick(self, button)
    local row = self.row
    if not row then return end
    if row.kind == "spell" then
        if button == "RightButton" then
            U.IgnoreSpell(row.rec)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            U.LinkSpell(row.rec)
        end
    elseif row.kind == "player" then
        -- Whispering is only ever the row's own button, never a stray click.
        if button == "RightButton" then U.IgnorePlayer(row.player.name, row.player.guid) end
    elseif row.kind == "more" then
        RW.GUI.Open()
    end
end

local function RowButton(f, i)
    local b = f.rows[i]
    if not b then
        b = CreateFrame("Button", nil, f)
        b:SetHeight(H.ROW_HEIGHT)
        b:SetPoint("TOPLEFT", H.PADDING, -(H.HEADER_HEIGHT + (i - 1) * H.ROW_HEIGHT))
        b:SetPoint("RIGHT", f, "RIGHT", -H.PADDING, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 2, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetScript("OnEnter", OnRowEnter)
        b:SetScript("OnLeave", U.HideTooltip)
        b:SetScript("OnClick", OnRowClick)

        -- Per-player whisper button (shown on player rows only).
        local w = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        w:SetSize(58, 14)
        w:SetPoint("RIGHT", b, "RIGHT", 0, 0)
        w:SetText("Whisper")
        w:SetScript("OnClick", function(self)
            local row = self:GetParent().row
            if row and row.player then U.WhisperPlayer(row.player.name) end
        end)
        w:SetScript("OnEnter", function(self)
            local row = self:GetParent().row
            if not (row and row.player) then return end
            if U.WhisperAllowed() then
                Hint(self, "Whisper " .. row.player.name .. " about their lower ranks now.")
            else
                Hint(self, U.REALM_BLOCKED)
            end
        end)
        w:SetScript("OnLeave", U.HideTooltip)
        b.whisper = w
        f.rows[i] = b
    end
    return b
end

--- Redraws the list (cheap; called on every detection).
function H.Refresh()
    local f = H.frame
    if not f then return end
    local collapsed = Settings().collapsed
    local rows, total = H.BuildRows(RW.Session.report)
    local _, _, summary = U.Summary(U.GroupByPlayer(RW.Session.report))

    f.title:SetText("Lower ranks " .. (total > 0 and U.Color("count", total) or ""))
    f.summary:SetText(summary)
    f.collapseButton:SetNormalTexture(
        collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up"
    )

    -- Where Forever hides group casts, say so on top (with the full reason on hover).
    local why = RW.Diag and RW.Diag.HiddenHere()
    if why then table.insert(rows, 1, { kind = "warning", text = U.Color("book", RW.Diag.LIMIT_SHORT:format(why)) }) end

    local shown = collapsed and 0 or #rows
    for i = 1, shown do
        local b = RowButton(f, i)
        b.row = rows[i]
        b.text:SetText(rows[i].text)
        local canWhisper = rows[i].kind == "player" and rows[i].player.name ~= UnitName("player")
        b.whisper:SetShown(canWhisper)
        -- Each player hears about each spell once per session: "Sent" once nothing is left to say.
        local unsent = canWhisper and U.HasUnsentWhisper(rows[i].player)
        local allowed = U.WhisperAllowed()
        b.whisper:SetText(not allowed and "Blocked" or unsent and "Whisper" or "Sent")
        b.whisper:SetEnabled((allowed and unsent) and true or false)
        b.text:SetPoint("RIGHT", canWhisper and -62 or -2, 0)
        b:Show()
    end
    for i = shown + 1, #f.rows do
        f.rows[i].row = nil
        f.rows[i]:Hide()
    end

    local hasPlayers = total > 0
    f.reset:SetShown(not collapsed and hasPlayers)
    f.summary:SetShown(not collapsed)

    if collapsed then
        f:SetHeight(H.HEADER_HEIGHT + 4)
    else
        f:SetHeight(H.HEADER_HEIGHT + shown * H.ROW_HEIGHT + H.FOOTER_HEIGHT + H.PADDING)
    end
end

function H.SetCollapsed(v)
    Settings().collapsed = v and true or false
    H.Refresh()
end

function H.IsShown() return H.frame ~= nil and H.frame:IsShown() end

function H.Show()
    H.Create()
    if not H.frame then return end
    H.Refresh()
    H.frame:Show()
    Settings().shown = true
end

function H.Hide()
    if H.frame then H.frame:Hide() end
    Settings().shown = false
end

function H.Toggle()
    if H.IsShown() then
        H.Hide()
    else
        H.Show()
    end
end

--- Called by Session.Record: refresh, and pop open (and expand) on new detections.
function H.OnDetection()
    if Settings().autoOpen then
        Settings().collapsed = false
        if not H.IsShown() then
            H.Show()
            return
        end
    end
    H.Refresh()
end

--- Restores the HUD after login if it was open last time.
function H.Restore()
    if Settings().shown then H.Show() end
end

function H.ResetPosition()
    Settings().point = { "RIGHT", "RIGHT", -60, 120 }
    if H.frame then ApplyPosition(H.frame) end
end
