-- Sync.lua
-- Lets several RankWarden users in one group agree on a single "lead",
-- so a player gets one whisper instead of one per addon user.
-- Lead = alphabetically first RankWarden user currently in the group.
-- Depends on: RankWarden.lua (Core), Debug.lua

local RW = RankWarden

RW.Sync = {}
local Y = RW.Sync

Y.PREFIX = "RANKWARDEN"
Y.HELLO_COOLDOWN = 5 -- seconds between HELLO broadcasts
Y.peers = {} -- name → true
Y.lastHello = -math.huge

local function Now() return (GetTime and GetTime()) or os.time() end

local function PlayerName() return (UnitName and UnitName("player")) or "?" end

local function InGroupWith(name)
    if not (UnitInParty and UnitInRaid) then return true end
    return UnitInParty(name) or UnitInRaid(name) ~= nil
end

local function GroupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

--- Pure election: smallest name among self + peers still in group.
--- @param selfName string
--- @param peers table name → true
--- @param inGroupFn function(name) → boolean
function Y.ElectLead(selfName, peers, inGroupFn)
    local lead = selfName
    for name in pairs(peers) do
        if name ~= selfName and inGroupFn(name) and name < lead then lead = name end
    end
    return lead
end

function Y.Lead() return Y.ElectLead(PlayerName(), Y.peers, InGroupWith) end

function Y.IsLead() return Y.Lead() == PlayerName() end

--- Announces ourselves to the group (throttled).
function Y.Hello(force)
    local channel = GroupChannel()
    if not channel then
        Y.peers = {}
        return
    end
    if UnitInBattleground and UnitInBattleground("player") then return end
    if not force and Now() - Y.lastHello < Y.HELLO_COOLDOWN then return end
    if RW.Chat.ChatBlocked() then return end -- addon comms can be locked down in instances
    Y.lastHello = Now()
    pcall(RW.SendCommMessage, RW, Y.PREFIX, "HELLO", channel)
end

--- AceComm handler.
function Y.OnComm(message, channel, sender)
    if not sender then return end
    if RW.Detector.Secret(sender) then return end
    -- Forever names look like "First Surname" or "First-Surname" (no realms);
    -- key peers by first name so both spellings match UnitName().
    local name = sender:match("^([^%-%s]+)") or sender
    if name == PlayerName() then return end

    local isNew = not Y.peers[name]
    Y.peers[name] = true
    RW.Debug.Msg(("Sync %s from %s (lead: %s)"):format(message, name, Y.Lead()))

    -- Answer a newcomer's HELLO so they learn about us too.
    if message == "HELLO" and isNew then
        local ch = GroupChannel()
        if ch and not RW.Chat.ChatBlocked() then pcall(RW.SendCommMessage, RW, Y.PREFIX, "ACK", ch) end
    end
end
