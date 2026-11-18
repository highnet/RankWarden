-- Messages.lua
-- Notification wording ("flavors") and message building.
-- Depends on: RankWarden.lua (Core)

local RW = RankWarden

RW.Messages = {}
local M = RW.Messages

-- Each flavor: Whisper / Local templates.
--   {spell}  spell link or name     {rank}  rank used
--   {spellrank}  link + " (Rank N)", or just the link when it already names its rank
--   {spellshort} link + " RN", likewise
--   {level}  level the next rank unlocks at     {name}  caster name (Local only)
M.FLAVORS = {
    default = {
        Whisper = "{rt7} RankWarden: you used {spellrank} — a newer rank is available from level {level}. Your action bars or macros may be outdated.",
        Local = "{name} used {spellrank}; a newer rank unlocks at level {level}.",
        Self = "You used {spellrank}; a newer rank unlocks at level {level}.",
        WhisperBook = "{rt7} RankWarden: heads-up — you used {spellrank}; a higher rank exists, but trainers don't sell it (it comes from a book, quest or drop). You may not have it yet.",
        LocalBook = "{name} used {spellrank}; a higher rank exists from a book, quest or drop (not trainers).",
        SelfBook = "You used {spellrank}; a higher rank exists from a book, quest or drop — trainers don't sell it.",
    },
    short = {
        Whisper = "{rt7} {spellrank} is outdated (new rank at {level}).",
        Local = "{name}: {spellshort} (new at {level})",
        Self = "{spellshort} is outdated (new at {level})",
        WhisperBook = "{rt7} {spellshort}: a higher rank comes from a book/quest (not trainers).",
        LocalBook = "{name}: {spellshort} (higher rank from a book/quest)",
        SelfBook = "{spellshort}: higher rank from a book/quest",
    },
    friendly = {
        Whisper = "{rt1} Friendly reminder! You just cast {spellrank}. Your trainer has had a stronger rank since level {level} — worth a quick visit!",
        Local = "{name} could use a trainer visit: {spellrank}, next rank at {level}.",
        Self = "Trainer time! {spellrank} has a stronger rank since level {level}.",
        WhisperBook = "{rt1} Friendly heads-up! You cast {spellrank}, and a stronger rank exists, learned from a book, quest or drop rather than a trainer. Worth hunting down!",
        LocalBook = "{name} might want to hunt down a higher {spell} rank (book, quest or drop).",
        SelfBook = "A stronger rank than {spellrank} is out there — from a book, quest or drop.",
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
    local filled = template:gsub("{(%w+)}", function(key)
        local v = fields[key]
        if v == nil then return "{" .. key .. "}" end -- leave {rt7} etc. for the chat system
        return tostring(v)
    end)
    return filled
end

--- True when a spell link or name already names its rank, e.g. Forever's
--- "[Lightning Shield (Rank 3)]" (any language: "(Rang 3)", "(Rango 3)").
function M.HasRank(spell)
    if type(spell) ~= "string" then return false end
    return spell:find("%(%D-%d+%)%]") ~= nil or spell:find("%(%D-%d+%)%s*$") ~= nil
end

--- Spell plus its rank, without repeating a rank the link already shows.
--- @param short boolean|nil  "R3" instead of "(Rank 3)"
function M.WithRank(spell, rank, short)
    spell = spell or "?"
    if M.HasRank(spell) or not rank then return spell end
    return spell .. (short and (" R" .. rank) or (" (Rank " .. rank .. ")"))
end

--- Builds a notification.
--- @param kind string  "Whisper" | "Local" | "Self"
--- @param fields table { spell, rank, level, name }
--- @param flavor string|nil
function M.Build(kind, fields, flavor)
    local set = M.FLAVORS[flavor or "default"] or M.FLAVORS.default
    local template = set[kind] or M.FLAVORS.default[kind] or set.Local
    fields.spellrank = fields.spellrank or M.WithRank(fields.spell, fields.rank)
    fields.spellshort = fields.spellshort or M.WithRank(fields.spell, fields.rank, true)
    return M.Fill(template, fields)
end

--- Spell link (or name) for chat. Uses whichever API this client exposes.
function M.SpellLink(spellID)
    local link
    if C_Spell and C_Spell.GetSpellLink then -- Forever (the global was removed)
        link = C_Spell.GetSpellLink(spellID)
    elseif GetSpellLink then -- older clients
        link = GetSpellLink(spellID)
    end
    return link or ("spell " .. tostring(spellID))
end
