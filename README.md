# RankWarden

A **World of Warcraft: Forever** addon that spots party and raid members casting an outdated spell rank, and lets them know.

> **Game Version:** WoW: Forever — Interface 16001 (patch 1.60.x)
> **Addon Version:** 1.0.0
> **SavedVariables:** `RankWardenDB`
> **Author:** Sandy Klawz — EU PvE

Inspired by [RankSentinel](https://www.curseforge.com/wow/addons/ranksentinel) (Classic / TBC), rebuilt for how Forever works.

---

## Features

- Watches **you, your party and your raid** for low-rank casts.
- Knows **Forever's own trainer data**, including Forever's new abilities and new ranks (1,493 trainable spells, 162 of them new in Forever).
- **Local only by default.** Notifications appear only in your chat frame until you turn whispers on with `/rw whisper`.
- **Ignores commonly downranked spells** (heals, Power Word: Shield, Frostbolt, Earth Shock, Moonfire, Arcane Explosion, ...). Each can be switched on or off, and you can ignore any other spell for the rest of your session with `/rw allow` (cleared when you log out or `/reload`).
- Gives players a few levels to visit their trainer before it says anything. It never repeats itself, and it skips casts on much lower targets (deliberate downranks).
- Whispers wait until neither of you is in combat. During Forever's chat lockdown in dungeons and raids they also wait until you leave.
- When several group members run RankWarden, only one of them (the "lead") whispers.
- **Book, quest and drop ranks**: at max level, if a higher rank exists but trainers don't sell it, the player gets a heads-up that it comes from a book, quest or drop, and that they may not have it yet. Toggle with `/rw books`.
- **Window** (`/rw` toggles it) with tabs for this session's detections, saved history, ignored spells and players, and settings. Detections are grouped by player, with **Whisper**, **Ignore player** and **Ignore spell** buttons on each row. It also has **Whisper all**, **Reset**, a report-to-channel picker, and a remembered window size and position. There's also a **minimap button**: left-click toggles the window, right-click turns detection on or off, drag to move it.
- **Lower-ranks HUD** (`/rw hud`): a small, movable panel listing this session's lower ranks, grouped by player.
  - Player names are in class colours, with their level and count. Each spell has its icon, rank, and where the next rank comes from. Fresh detections are marked **new**.
  - Each player row has its own **Whisper** button (a plain click never whispers). Right-click a player to ignore them. Hover a spell for its tooltip, shift-click to link it, or right-click to ignore it for this session.
  - Footer button: **Reset**, which clears the list and forgets who was notified.
  - It pops open on new detections (optional), collapses to its title bar, and can be locked and scaled. It remembers its position.
- **Cast monitor** (`/rw watch`) prints every cast from your group, so you can check that other players' casts reach the addon.
- Options panel under **Options → AddOns → RankWarden**.

### How it works on Forever

Forever's client runs on the modern (Midnight-era) addon API:

| Classic / RankSentinel | Forever | RankWarden |
|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | never fires for addons | `UNIT_SPELLCAST_SUCCEEDED` on `player`, `party1-4`, `raid1-40` (de-duplicated by cast GUID) |
| `GetSpellInfo`, `GetSpellLink`, `GetSpellSubtext` | removed | `C_Spell.*` |
| plain values | spell casts, names and GUIDs can be **secret** during encounters and PvP | secret values are skipped (`issecretvalue`); `/rw status` counts them |
| chat always allowed | chat messaging **lockdown** in instances; some realms block addon chat | whispers queue during lockdown, or fall back to local chat |
| realm names | `First Surname` names, no realms | peers are keyed by first name |
| destination of a spell | no combat log | the caster's target level is used to spot deliberate downranks |

Rank chains are built **in-game**. Spells are grouped by class and by their localized name, and ordered by their "Rank N" text or trainer level, so this works in every client language. Chains that change name (Bear Form → Dire Bear Form, Lacerate) come from explicit lists.

---

## Installation

Copy the `RankWarden` folder (or the zip from `.\run.ps1 export`) into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

Then restart the game.

## Testing it safely

Whispers are **off** until you enable them. To try it:

1. Cast a low rank of one of your own spells, e.g. Fireball Rank 1 at level 20+ (heals and Frostbolt are ignored by default). You'll see a local `You used ...` line.
2. In a group, other players' outdated casts show as local lines.
3. To confirm other players are seen, run `/rw watch` and ask a group member to cast anything. Each cast prints a `[watch]` line marked tracked, untracked or hidden by the game.
4. `/rw status` shows the settings, how many rank chains were built, any casts the game hid, and whether addon chat is allowed.
5. Happy with it? Run `/rw whisper` to start whispering.

## Commands

| Command | Does |
|---|---|
| `/rw` | Toggle the window |
| `/rw help` | List commands |
| `/rw hud` | Toggle the lower-ranks HUD |
| `/rw hudlock` / `/rw hudreset` | Lock the HUD in place / move it back to its default spot |
| `/rw watch` | Toggle the cast monitor (prints every group cast; on by default) |
| `/rw books` | Toggle book/quest/drop rank notices |
| `/rw minimap` | Show or hide the minimap button |
| `/rw on` / `/rw off` | Enable / disable detection |
| `/rw whisper` | Toggle whispering players (off = local only) |
| `/rw downrank` | Toggle ignoring commonly downranked spells, and list them |
| `/rw allow <spell>` | Toggle ignoring every rank of a spell for this session (shift-click it) |
| `/rw maxlevel` | Only check max-level casters |
| `/rw flavor [name]` | List or set the wording (`default`, `short`, `friendly`) |
| `/rw ignore` | Toggle ignoring your current target |
| `/rw queue [clear\|send]` | Show, clear or send queued whispers |
| `/rw report [self\|say\|party\|raid\|guild]` | Report this session's detections |
| `/rw status` | Settings, lead, caches, chat restrictions |
| `/rw clear` | Forget who has already been notified |
| `/rw reset` | Reset settings |
| `/rw config` | Open the options panel |
| `/rw debug` | Debug output (also re-alerts repeats) |

---

## Development

Tooling mirrors [RessurectionSayings](https://github.com/highnet/RessurectionSayings): luacheck, busted, luacov and a PowerShell task runner. StyLua handles formatting.

```powershell
.\run.ps1 lint       # luacheck
.\run.ps1 format     # stylua (writes)
.\run.ps1 fmtcheck   # stylua --check
.\run.ps1 test       # busted
.\run.ps1 coverage   # busted + luacov -> luacov.report.out
.\run.ps1 export     # ..\RankWarden.zip
.\run.ps1 all        # fmtcheck + lint + test
```

VS Code tasks for each are in `.vscode/tasks.json`.

Tools: `scoop install lua luarocks stylua`, then `luarocks install luacheck busted luacov`.

### Regenerating ability data

`AbilityData.lua` is generated from What's Training's Forever trainer tables:

```powershell
python tools/build_ability_data.py "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WhatsTraining"
```

Re-run it when Forever patches change trainers.

### Layout

| File | Role |
|---|---|
| `RankWarden.lua` | Core: AceAddon object, DB defaults, events |
| `Debug.lua` | SafeCall / debug output |
| `Chat.lua` | Local printing, sending, chat-restriction checks |
| `AbilityData.lua` | Generated Forever trainer data |
| `Ranks.lua` | Builds rank chains; rank and ignore logic |
| `Messages.lua` | Notification wording |
| `Session.lua` | Per-login state |
| `Sync.lua` | Lead election between RankWarden users |
| `Notify.lua` | Whisper queue |
| `Detector.lua` | `UNIT_SPELLCAST_SUCCEEDED` → notification |
| `SlashCommands.lua` | `/rw` |
| `RankWarden_Options.lua` | Options panel |
| `UI.lua` | Shared colours, icons, and actions (whisper, ignore, reset) |
| `HUD.lua` | Lower-ranks HUD (grouped by player) |
| `GUI.lua` | Main window, minimap button |

## Releasing

`.github/workflows/release.yml` packages the addon with the [BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it to CurseForge whenever a `v*` tag is pushed:

```bash
git tag v1.0.0
```

```bash
git push origin v1.0.0
```

One-time setup:
- Create the project on CurseForge.
- Add `## X-Curse-Project-ID: <id>` to `RankWarden.toc`.
- Add a CurseForge API token as the repository secret `CF_API_KEY`.

`ci.yml` runs StyLua, luacheck and busted on every push.

## License

MIT, see [`LICENSE`](LICENSE). Third-party notices are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Credits

- **Sandy Klawz** (EU PvE): author. RankWarden is Copyright (c) 2026 highnet, MIT.
- **[RankSentinel](https://github.com/valkyrnstudios/RankSentinel)** (MIT, Copyright (c) 2021 Gogo1951, maintained by SabreValkyrn / Valkyrn Studios; see `LICENSE.RankSentinel`): the original idea and the curated list of abilities where a low rank is a mistake. RankSentinel's own credits:
  - **Gogo**: collaboration and data curation ([Gogo's revised ability list](https://docs.google.com/spreadsheets/d/1jtx1WyfChzACzh0WBWANtrqkRtS3D-zPWqs3eOnyVvY/edit?usp=sharing)).
  - **Aevala** and **Fathom**: ability data feedback.
  - **Splendiferus**: testing and feedback.
  - RankSentinel was itself inspired by **[RankWatch](https://www.curseforge.com/wow/addons/rankwatch)**, and succeeds **GogoWatch** and **SpellSnob**.
- **[What's Training?](https://www.curseforge.com/wow/addons/whats-training)** by Sveng (MIT): Forever trainer spell data.
- **Libraries:** [Ace3](https://github.com/WoWUIDev/Ace3) (AceAddon, AceEvent, AceConsole, AceComm, AceDB, AceGUI, AceConfig) by the Ace3 Development Team, [LibStub](https://www.wowace.com/projects/libstub), [CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler) and [ChatThrottleLib](https://www.wowace.com/projects/chatthrottlelib) (Mikk).
- **Forever API research:** [ForeverPlusPlus notes](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md) (xIGBClutchIx), [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (Thunderz96), and the [Forever UI source mirror](https://github.com/Gethe/wow-ui-source/tree/forever) (Gethe).

Full license texts and versions are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
