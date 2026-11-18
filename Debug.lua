-- Debug.lua
-- Error handling, xpcall-based safe calls, and conditional debug output.
-- Depends on: RankWarden.lua (Core)

local RW = RankWarden

RW.Debug = {}
local D = RW.Debug

local ERR_PREFIX = "|cffff4444[RW Error]|r"
local DBG_PREFIX = "|cffffff00[RW Debug]|r"
local STACK_LINES = 12 -- max lines of stack trace to display

local function DebugOn() return RW.db and RW.db.profile and RW.db.profile.debug end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal error handler  (passed to xpcall)
-- ─────────────────────────────────────────────────────────────────────────────
local function OnError(err)
    local msg = tostring(err)
    print(ERR_PREFIX .. " " .. msg)

    if DebugOn() then
        print(DBG_PREFIX .. " Stack trace:")
        for line in debugstack(2, STACK_LINES, 3):gmatch("[^\n]+") do
            if line:match("%S") then print("   " .. line) end
        end
    else
        print(ERR_PREFIX .. " Use |cffffff00/rw debug|r to see the full stack trace next time.")
    end

    return msg
end

--- Wraps fn in xpcall; prints errors automatically.
--- @return boolean ok, any resultOrError
function D.SafeCall(fn, ...)
    if type(fn) ~= "function" then
        print(ERR_PREFIX .. " SafeCall: expected function, got " .. type(fn))
        return false, nil
    end
    return xpcall(fn, OnError, ...)
end

--- Prints only while /rw debug is on.
function D.Msg(msg)
    if DebugOn() then print(DBG_PREFIX .. " " .. tostring(msg)) end
end

--- Fires OnError (and returns false) when condition is falsy.
function D.Assert(condition, msg)
    if not condition then
        OnError(msg or "Assertion failed")
        return false
    end
    return true
end
