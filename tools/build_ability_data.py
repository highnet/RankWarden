"""Builds AbilityData.lua for WoW: Forever.

Sources
-------
* WhatsTraining's Forever ("Camelot") trainer tables — every trainable spell ID
  and the level it unlocks at, including Forever's new abilities and ranks.
  WhatsTraining is MIT licensed (c) Sveng.
* WhatsTraining's Vanilla tables — to know which spells existed before Forever.
* RankSentinel's Classic list (tools/RankSentinel_Classic.lua, MIT (c) SabreValkyrn,
  from Gogo's revised ability list) — the hand-curated set of vanilla abilities
  where a low rank is a mistake. Vanilla abilities RankSentinel left out
  (poisons, legit downrank spells, ...) stay excluded; brand-new Forever
  abilities are included.

Spell names and "Rank N" text aren't in these files, so the addon groups ranks
in-game by spell name (see Ranks.Build). This script only emits IDs and levels.

Usage (from the addon root):
    python tools/build_ability_data.py [path/to/WhatsTraining]
"""

import os
import re
import sys
from datetime import date

DEFAULT_WT = r"C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WhatsTraining"

CLASSES = ["Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"]

LEVEL_RE = re.compile(r"\[(\d+)\]\s*=\s*\{")
ENTRY_RE = re.compile(r"\{\s*id\s*=\s*(\d+)([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}")
REQ_RE = re.compile(r"requiredIds\s*=\s*\{([^}]*)\}")
TALENT_RE = re.compile(r"requiredTalentId\s*=\s*(\d+)")
LOCAL_LIST_RE = re.compile(r"^local\s+(\w+)\s*=\s*\{([\d,\s]*)\}(.*)$", re.M)
BLOCK_COMMENT_RE = re.compile(r"--\[\[.*?\]\]", re.S)


def ints(text):
    return [int(x) for x in re.findall(r"\d+", text)]


def override_items(src, lists, path):
    """Yields (ids, comment) for each entry of class.overriddenGroups (named or inline)."""
    start = src.find("class.overriddenGroups")
    if start < 0:
        return
    i = src.index("{", start) + 1
    depth, body_end = 1, i
    while depth:
        depth += {"{": 1, "}": -1}.get(src[body_end], 0)
        body_end += 1
    body = re.sub(r"--[^\n]*", "", src[i:body_end - 1])
    for m in re.finditer(r"\{([\d,\s]*)\}|([A-Za-z_]\w*)", body):
        if m.group(1) is not None:
            yield ints(m.group(1)), ""
        elif m.group(2) in lists:
            yield lists[m.group(2)]
        else:
            print(f"warning: {os.path.basename(path)}: group '{m.group(2)}' not parsed")


def parse_class(path):
    """Returns (levels {id: level}, prereqs set, explicit groups [[(id, rank)]])."""
    src = BLOCK_COMMENT_RE.sub("", open(path, encoding="utf-8").read())
    levels, prereqs = {}, set()

    body = src[src.index("spellsByLevel"):]
    # Walk level markers; each entry belongs to the most recent marker before it.
    markers = [(m.start(), int(m.group(1))) for m in LEVEL_RE.finditer(body)]
    for m in ENTRY_RE.finditer(body):
        level = 0
        for pos, lvl in markers:
            if pos > m.start():
                break
            level = lvl
        sid = int(m.group(1))
        rest = m.group(2)
        if "faction" in rest and sid in levels:
            continue
        levels[sid] = min(level, levels.get(sid, level))
        req = REQ_RE.search(rest)
        if req:
            prereqs.update(ints(req.group(1)))
        tal = TALENT_RE.search(rest)
        if tal:
            prereqs.add(int(tal.group(1)))

    groups = []
    lists = {m.group(1): (ints(m.group(2)), m.group(3)) for m in LOCAL_LIST_RE.finditer(src)}
    for ids, comment in override_items(src, lists, path):
        # e.g. Lacerate: "Both rank 1 IDs, then ranks 2-5"
        shared_first = "both rank 1" in comment.lower()
        ranked, rank = [], 0
        for i, sid in enumerate(ids):
            if not (shared_first and i == 1):
                rank += 1
            ranked.append((sid, rank))
        groups.append(ranked)
    return levels, prereqs, groups


def parse_quest_classes(path):
    """Returns {CLASS: {id: min level}} for quest-taught class spells."""
    out = {}
    if not os.path.exists(path):
        return out
    src = open(path, encoding="utf-8").read()
    for cm in re.finditer(r"^\s{4}([A-Z]+)\s*=\s*\{(.*?)^\s{4}\},?", src, re.S | re.M):
        spells = out.setdefault(cm.group(1), {})
        for m in re.finditer(r"\[(\d+)\]\s*=\s*\{(.*?)\n\s*\},", cm.group(2), re.S):
            lvls = [int(x) for x in re.findall(r"level\s*=\s*(\d+)", m.group(2))]
            if lvls:
                spells[int(m.group(1))] = min(lvls)
    return out


def parse_ranksentinel(path):
    src = open(path, encoding="utf-8").read()
    data = src[src.index("AbilityData"):src.index("AbilityGroups")]
    return {int(x) for x in re.findall(r"\[(\d+)\]\s*=", data)}


def lua_set(name, ids):
    lines = [f"RW.{name} = {{"]
    ids = sorted(ids)
    for i in range(0, len(ids), 10):
        lines.append("    " + " ".join(f"[{x}] = true," for x in ids[i:i + 10]))
    lines.append("}")
    return "\n".join(lines)


def main():
    wt = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_WT
    if not os.path.isfile("RankWarden.toc"):
        sys.exit("Run from the addon root.")

    by_class, groups = {}, []
    vanilla_ids = set()
    quest = parse_quest_classes(os.path.join(wt, "Classes", "Camelot", "QuestSpells.lua"))
    for cls in CLASSES:
        lv, pr, gr = parse_class(os.path.join(wt, "Classes", "Camelot", cls + ".lua"))
        levels = dict(lv)
        for sid, lvl in quest.get(cls.upper(), {}).items():
            levels.setdefault(sid, lvl)
        # Talent / quest prerequisites without a trainer level: 0 ("not trained").
        for sid in pr:
            levels.setdefault(sid, 0)
        for g in gr:
            for sid, _ in g:
                levels.setdefault(sid, 0)
        by_class[cls.upper()] = levels
        groups += [(cls.upper(), g) for g in gr]

        vlv, vpr, _ = parse_class(os.path.join(wt, "Classes", "Vanilla", cls + ".lua"))
        vanilla_ids |= set(vlv) | vpr
    for spells in parse_quest_classes(os.path.join(wt, "Classes", "Vanilla", "QuestSpells.lua")).values():
        vanilla_ids |= set(spells)
    all_ids = set().union(*by_class.values())

    legacy_ranked = parse_ranksentinel("tools/RankSentinel_Classic.lua")
    legacy_excluded = vanilla_ids - legacy_ranked

    out = [
        f"-- AbilityData.lua  (GENERATED by tools/build_ability_data.py on {date.today()} — do not edit)",
        "-- Forever trainer spells and levels from WhatsTraining (MIT, (c) Sveng).",
        "-- Legacy include/exclude sets from RankSentinel (MIT, (c) SabreValkyrn) / Gogo's list.",
        "-- Ranks are grouped in-game by spell name: see Ranks.Build().",
        "-- Depends on: RankWarden.lua (Core)",
        "",
        "local RW = RankWarden",
        "",
        "-- CLASS → { spellID → level the trainer teaches it (0 = talent/quest/other) }",
        "RW.TrainerSpells = {",
    ]
    for cls in sorted(by_class):
        out.append(f"    {cls} = {{")
        for sid in sorted(by_class[cls]):
            out.append(f"        [{sid}] = {by_class[cls][sid]},")
        out.append("    },")
    out.append("}")
    out.append("")
    out.append("-- Rank chains whose ranks change name (e.g. Bear Form → Dire Bear Form).")
    out.append("-- { class = CLASS, { id, rank }, ... }")
    out.append("RW.ExplicitGroups = {")
    for cls, g in groups:
        out.append(f'    {{ class = "{cls}", ' + ", ".join(f"{{ {sid}, {rank} }}" for sid, rank in g) + " },")
    out.append("}")
    out.append("")
    out.append("-- Vanilla abilities RankSentinel flags when cast at a low rank.")
    out.append(lua_set("LegacyRanked", legacy_ranked))
    out.append("")
    out.append("-- Vanilla abilities RankSentinel deliberately ignores (legit downranks, poisons, ...).")
    out.append(lua_set("LegacyExcluded", legacy_excluded))
    out.append("")

    with open("AbilityData.lua", "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

    new_ids = all_ids - vanilla_ids - legacy_ranked
    print(f"Trainer spells: {len(all_ids)}  explicit groups: {len(groups)}  "
          f"legacy ranked: {len(legacy_ranked)}  legacy excluded: {len(legacy_excluded)}  "
          f"new in Forever: {len(new_ids)}")


if __name__ == "__main__":
    main()
