-- Notify.lua
-- Outgoing notification queue. Whispers wait until neither you nor the
-- target is in combat, so nobody gets spammed mid-pull.
-- Depends on: RankWarden.lua (Core), Debug.lua, Chat.lua, Session.lua, Sync.lua

local RW = RankWarden

RW.Notify = {}
local N = RW.Notify

N.FLUSH_DELAY = 5 -- seconds after combat ends before whispering

local function CanSendNow()
    if InCombatLockdown and InCombatLockdown() then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    return true
end

--- Adds a notification and flushes immediately when safe.
--- @param entry table { target, message, ability, isWhisper }
function N.Enqueue(entry)
    local q = RW.Session.queue
    q[#q + 1] = entry
    if CanSendNow() then
        N.Flush()
    elseif entry.isWhisper then
        RW.Debug.Msg(("Queued whisper to %s: %s"):format(entry.target, entry.ability))
    end
end

--- Sends everything that can go out now; keeps the rest.
function N.Flush()
    if not CanSendNow() then return end

    local retry = {}
    local blocked, reason = RW.Chat.ChatBlocked()
    for _, e in ipairs(RW.Session.queue) do
        if e.isWhisper and blocked and reason == "realm" then
            -- This realm never lets addons whisper: fall back to local chat.
            if not N.warnedRealmBlock then
                N.warnedRealmBlock = true
                RW.Chat.Warn("This realm blocks addon whispers; showing notifications locally instead.")
            end
            RW.Chat.Print(e.target .. ": " .. e.message)
        elseif e.isWhisper and blocked then
            retry[#retry + 1] = e -- chat lockdown (instance/encounter): send later
        elseif e.isWhisper then
            if UnitAffectingCombat and UnitAffectingCombat(e.target) then
                retry[#retry + 1] = e
            else
                RW.Chat.Whisper(e.target, e.message)
            end
        else
            RW.Chat.Print(e.message)
        end
    end
    RW.Session.queue = retry
end

function N.FlushSoon()
    if C_Timer and C_Timer.After then
        C_Timer.After(N.FLUSH_DELAY, N.Flush)
    else
        N.Flush()
    end
end

function N.Clear()
    local n = #RW.Session.queue
    RW.Session.queue = {}
    return n
end
