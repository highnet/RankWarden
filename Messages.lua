-- Messages.lua
-- Notification wording ("flavors") and message building.
-- Depends on: RankWarden.lua (Core)

local RW = RankWarden

RW.Messages = {}
local M = RW.Messages

-- Each flavor: Whisper / Local templates.
--   {spell}  spell link or name     {rank}  rank used
--   {level}  level the next rank unlocks at     {name}  caster name (Local only)
M.FLAVORS = {
    default = {
        Whisper = "{rt7} RankWarden: you used {spell} (Rank {rank}) — a newer rank is available from level {level}. Your action bars or macros may be outdated.",
        Local = "{name} used {spell} (Rank {rank}); a newer rank unlocks at level {level}.",
        Self = "You used {spell} (Rank {rank}); a newer rank unlocks at level {level}.",
        WhisperBook = "{rt7} RankWarden: heads-up — {spell} has a higher rank than Rank {rank}, but trainers don't sell it (it comes from a book, quest or drop). You may not have it yet.",
        LocalBook = "{name} used {spell} (Rank {rank}); a higher rank exists from a book, quest or drop (not trainers).",
        SelfBook = "You used {spell} (Rank {rank}); a higher rank exists from a book, quest or drop — trainers don't sell it.",
    },
    short = {
        Whisper = "{rt7} {spell} Rank {rank} is outdated (new rank at {level}).",
        Local = "{name}: {spell} R{rank} (new at {level})",
        Self = "{spell} R{rank} is outdated (new at {level})",
        WhisperBook = "{rt7} {spell} R{rank}: a higher rank comes from a book/quest (not trainers).",
        LocalBook = "{name}: {spell} R{rank} (higher rank from a book/quest)",
        SelfBook = "{spell} R{rank}: higher rank from a book/quest",
    },
    friendly = {
        Whisper = "{rt1} Friendly reminder! You just cast {spell} (Rank {rank}). Your trainer has had a stronger rank since level {level} — worth a quick visit!",
        Local = "{name} could use a trainer visit: {spell} (Rank {rank}), next rank at {level}.",
        Self = "Trainer time! {spell} (Rank {rank}) has a stronger rank since level {level}.",
        WhisperBook = "{rt1} Friendly heads-up! There's a stronger {spell} than Rank {rank}, but it's learned from a book, quest or drop rather than a trainer. Worth hunting down!",
        LocalBook = "{name} might want to hunt down a higher {spell} rank (book, quest or drop).",
        SelfBook = "A stronger {spell} than Rank {rank} is out there — from a book, quest or drop.",
    },
}

--- Sorted list of flavor names.
function M.FlavorNames()
    local names = {}
    for k in pairs(M.FLAVORS) do
        names[#names + 1] = k
    end
    table.sort(names)
    return names
end

function M.IsFlavor(name) return M.FLAVORS[name] ~= nil end

--- Fills {placeholders} in template.
function M.Fill(template, fields)
    return (
        template:gsub("{(%w+)}", function(key)
            local v = fields[key]
            if v == nil then return "{" .. key .. "}" end -- leave {rt7} etc. for the chat system
            return tostring(v)
        end)
    )
end

--- Builds a notification.
--- @param kind string  "Whisper" | "Local" | "Self"
--- @param fields table { spell, rank, level, name }
--- @param flavor string|nil
function M.Build(kind, fields, flavor)
    local set = M.FLAVORS[flavor or "default"] or M.FLAVORS.default
    local template = set[kind] or M.FLAVORS.default[kind] or set.Local
    return M.Fill(template, fields)
end

--- Spell link (or name) for chat. Uses whichever API this client exposes.
function M.SpellLink(spellID)
    local link
    if GetSpellLink then
        link = GetSpellLink(spellID)
    elseif C_Spell and C_Spell.GetSpellLink then
        link = C_Spell.GetSpellLink(spellID)
    end
    return link or ("spell " .. tostring(spellID))
end
