-- Session.lua
-- Per-login state: who has been told about what, the outgoing queue, and the report.
-- Depends on: RankWarden.lua (Core)

local RW = RankWarden

RW.Session = {}
local S = RW.Session

function S.Reset()
    S.groupsNotified = {} -- "guid-abilityGroup" → true  (one alert per ability per session)
    S.levelSeen = {} -- guid → first level seen this session
    S.queue = {} -- { target, message, ability, isWhisper }
    S.report = {} -- ordered list of { name, spell, rank }
end

S.Reset()

--- Spells ignored for this login session only (every rank). Not saved:
--- cleared on logout or /reload, and kept across the HUD's Reset.
S.ignoredSpells = {}

S.HISTORY_SIZE = 200 -- detections kept across sessions for the History tab

--- Records a detection for /rw report, the session list and the saved history.
--- @param rec table { name, spell, rank, nextLevel, whispered }
function S.Record(rec)
    rec.time = rec.time or (date and date("%H:%M") or "")
    rec.at = rec.at or (GetTime and GetTime() or 0) -- for the "new" highlight
    S.report[#S.report + 1] = rec

    local history = RW.db and RW.db.profile.history
    if history then
        history[#history + 1] = {
            name = rec.name,
            spell = rec.spell,
            rank = rec.rank,
            nextLevel = rec.nextLevel,
            level = rec.level,
            class = rec.class,
            spellID = rec.spellID,
            book = rec.book,
            whispered = rec.whispered,
            time = rec.time,
            day = date and date("%Y-%m-%d") or "",
        }
        while #history > S.HISTORY_SIZE do
            table.remove(history, 1)
        end
    end

    if RW.GUI and RW.GUI.Refresh then RW.GUI.Refresh() end
    if RW.HUD and RW.HUD.OnDetection and RW.db then RW.HUD.OnDetection() end
end
