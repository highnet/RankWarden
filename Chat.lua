-- Chat.lua
-- Local print helpers plus outgoing whispers and session reports.
-- Depends on: RankWarden.lua (Core), Debug.lua

local RW = RankWarden

RW.Chat = {}
local C = RW.Chat

local CLR_ADDON = "|cff00ccff"
local CLR_RESET = "|r"
local CLR_WARN = "|cffffff00"
local CLR_ERR = "|cffff4444"
local TAG = CLR_ADDON .. "[RW]" .. CLR_RESET .. " "

-- ─────────────────────────────────────────────────────────────────────────────
-- Local print helpers  (never visible to other players)
-- ─────────────────────────────────────────────────────────────────────────────
function C.Print(msg) print(TAG .. tostring(msg)) end
function C.Printf(fmt, ...) C.Print(fmt:format(...)) end
function C.Warn(msg) C.Print(CLR_WARN .. tostring(msg) .. CLR_RESET) end
function C.Error(msg) C.Print(CLR_ERR .. tostring(msg) .. CLR_RESET) end

-- ─────────────────────────────────────────────────────────────────────────────
-- Outgoing chat
-- ─────────────────────────────────────────────────────────────────────────────

--- Channels /rw report accepts. "SELF" prints locally.
C.REPORT_CHANNELS = { self = "SELF", say = "SAY", party = "PARTY", raid = "RAID", guild = "GUILD" }

--- Forever (Midnight-era client) can block addon chat: in "chat messaging
--- lockdown" (dungeons, raids, encounters, PvP) and, per realm, entirely.
--- @return boolean blocked, string|nil reason
function C.ChatBlocked()
    local info = C_ChatInfo
    if info and info.AreOutgoingAddonChatMessagesRestricted and info.AreOutgoingAddonChatMessagesRestricted() then
        return true, "realm"
    end
    if info and info.InChatMessagingLockdown and info.InChatMessagingLockdown() then return true, "lockdown" end
    return false
end

--- Forever ships both C_ChatInfo.SendChatMessage and the global; prefer the namespace.
local function RawSend(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return send(msg, channel, nil, target)
end

--- Sends a message, wrapping Blizzard's API in pcall.
--- @return boolean ok
function C.Send(msg, channel, target)
    if type(msg) ~= "string" or msg == "" then return false end
    if channel == "SELF" then
        C.Print(msg)
        return true
    end
    local ok, err = pcall(RawSend, msg, channel, target)
    if not ok then
        C.Error(("Could not send [%s%s]: %s"):format(channel, target and (" " .. target) or "", tostring(err)))
    end
    return ok
end

--- Whispers `target`.
function C.Whisper(target, msg) return C.Send(msg, "WHISPER", target) end
