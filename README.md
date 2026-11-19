# RankWarden

A **RankSentinel-style rank checker for World of Warcraft: Forever**: it spots party and raid members casting an outdated spell rank, and lets them know.

<img src="media/logo.png" alt="RankWarden dragon-eye logo" width="128">

> **Game Version:** WoW: Forever — Interface 16001 (patch 1.60.x)
> **Addon Version:** 1.3.0
> **SavedVariables:** `RankWardenDB`
> **Author:** Sandy Klawz — EU PvE

Inspired by [RankSentinel](https://www.curseforge.com/wow/addons/ranksentinel) (Classic / TBC), rebuilt for how Forever works.

---

## Where it works

WoW: Forever restricts what addons can see and send. These are the limits measured with `/rw diag` on patch 1.60.1 (build 70959):

| | Where it works | Where it doesn't |
|---|---|---|
| **Your own casts** | Everywhere | — |
| **Group members' casts** | Only where Forever applies no addon restriction | Wherever the **Map** restriction is active, **including the open world**, plus encounters, keystone dungeons and PvP matches. Forever hides other players' casts from addons there, and every tracked spell is "contextually secret", so none are exempt. |
| **Whispers** | Realms that allow addon chat | Realms that block addon chat. On these, addons can't send any chat messages, so notes stay in your own chat. |

RankWarden tells you when you hit these limits:
- **Restricted areas:** a chat warning once per area ("Group casts are hidden here (Map restriction): only your own spells can be checked") and an orange line at the top of the HUD.
- **Blocked whispers:** the Whisper buttons show **Blocked** / **Can't whisper**, are disabled, and explain why on hover.

`/rw diag` shows the current state, including your location and the restrictions active for each recent group cast. Paste it into an issue if you find somewhere that behaves differently.

---

## Features

### Detection

- Watches **you, your party and your raid** for low-rank casts.
- Knows **Forever's own trainer data**, including Forever's new abilities and new ranks (1,493 trainable spells, 162 of them new in Forever).
- Gives players a few levels to reach their trainer before it says anything, and skips casts on much lower targets (deliberate downranks).
- **Book, quest and drop ranks**: at max level, if a higher rank exists but trainers don't sell it, the player gets a heads-up that it comes from a book, quest or drop, and that they may not have it yet. Toggle with `/rw books`.
- **Ignores commonly downranked spells** (heals, Power Word: Shield, Frostbolt, Earth Shock, Moonfire, Arcane Explosion, ...). Each one can be switched on or off.
- **Cast monitor** (`/rw watch`, **on by default**) prints one `[watch] <name>: casts are reaching RankWarden` line per group member, the first time their casts get through, so you know they're being checked. Casts the game hides from addons (encounters, some instances, PvP) print nothing, since they can't be checked anyway.

### Whispers

- **Auto-whisper is on by default** (turn it off with `/rw whisper` to keep notes in your own chat). You can also whisper someone with their **Whisper** button.
- **Each player is whispered about each spell at most once per login session**, whether automatically or with the button. Once everything listed for a player has been sent, their button greys out ("Sent" in the HUD, "Whispered" in the window). This survives the HUD's Reset.
- Whispers wait until neither of you is in combat. During Forever's chat lockdown in dungeons and raids, they wait until you leave.
- When several group members run RankWarden, only one of them (the "lead") auto-whispers.
- You never get a Whisper button for yourself: your own lower ranks are just a local note to you.

### Ignoring

| What | How | How long |
|---|---|---|
| One spell for **one player** | Right-click the spell in the HUD, or **Ignore spell** in the window | This login session |
| Every rank of a spell for **everyone** | `/rw allow <spell>` (shift-click it) | This login session |
| A player | Right-click their name in the HUD, **Ignore player** in the window, or `/rw ignore` on your target | Saved |
| Commonly downranked spells | `/rw downrank`, or the checkboxes under Ignored / Settings | Saved |

Session ignores are cleared when you log out or `/reload`. You can see and remove all of them in `/rw` → **Ignored**.

### Lower-ranks HUD (`/rw hud`)

A small, movable panel listing this session's lower ranks, grouped by player:

```
Lower ranks 2                          [–] [≡] [x]
Buddy (40)  2                        [ Whisper ]
   [Fireball] R3  next at 18
   [Lightning Shield (Rank 3)]  next at 32  new
[Reset]                     1 player · 2 lower ranks
```

- Player names are in class colours, with their level and count. Each spell has its icon, its rank, and where the next rank comes from. Fresh detections are marked **new**.
- Forever's spell links already name the rank (`[Lightning Shield (Rank 3)]`), so the rank is only added when a link doesn't show it. This applies to the HUD, the window, the report and the whisper text.
- Each player row has its own **Whisper** button; a plain click on a row never whispers anyone. Right-click a player to ignore them. Hover a spell for its tooltip, shift-click it to link it in chat, or right-click it to ignore it for that player.
- **Reset** clears the list and forgets who was notified, so new casts show again. Ignores and the once-per-session whisper rule stay.
- It pops open on new detections (optional), collapses to its title bar, and can be locked and scaled. It remembers its position.

### Main window (`/rw`)

- **Detections** tab, grouped by player:
  - **Whisper**, **Ignore player** and **Ignore spell** buttons on each row.
  - **Whisper all** (each player still hears about each spell only once), **Reset**, and **Show/Hide HUD**.
  - A report-to-channel picker, and the cast monitor checkbox.
- **History** tab: the last 200 detections, kept between sessions.
- **Ignored** tab: session spell ignores, per-player spell ignores, commonly downranked spells, and ignored players.
- **Settings** tab: the full options panel, also under **Options → AddOns → RankWarden**.
- The window remembers its size and position.
- **Minimap button**: left-click toggles the window, right-click turns detection on or off, drag to move it.

### Diagnostics (`/rw diag`)

Opens a plain-text report, already selected, so you can press **Ctrl+C** and paste it anywhere (a bug report, Discord, an AI assistant). It's also on the **Diagnostics** button in the main window. The report covers:

- Client version, build and interface, plus RankWarden's settings and ignore counts.
- Casts seen this session (yours, your group's, hidden), and **which addon restrictions were active** (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat) whenever a group member's cast was hidden or got through. This shows exactly when Forever hides other players' casts.
- A **secrecy census**: how many tracked spells Forever marks `NeverSecret`, `AlwaysSecret` or `ContextuallySecret` as casts (`C_Secrets.GetSpellCastSecrecy`).
- **Your location** (zone, sub-zone, map ID, open world or instance type), and whether group casts are known to be hidden here.
- Addon chat state, group, lead, the last 10 detections, and the last 25 group casts with the restrictions active and where you were.

**Reset counters** starts a fresh measurement; **Refresh** updates the report.

### How it works on Forever

Forever's client runs on the modern (Midnight-era) addon API:

| Classic / RankSentinel | Forever | RankWarden |
|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | never fires for addons | `UNIT_SPELLCAST_SUCCEEDED` on `player`, `party1-4`, `raid1-40` (de-duplicated by cast GUID) |
| `GetSpellInfo`, `GetSpellLink`, `GetSpellSubtext` | removed | `C_Spell.*` |
| plain values | other players' casts, names and GUIDs become **secret** while an addon restriction is active (combat, encounters, PvP, restricted maps) | secret values are skipped (`issecretvalue`); `/rw diag` shows which restriction hid them |
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

Auto-whisper is **on** by default. To try RankWarden without messaging anyone, run `/rw whisper` first to turn it off; notes then stay in your own chat. Then:

1. Cast a low rank of one of your own spells, e.g. Fireball Rank 1 at level 20+ (heals and Frostbolt are ignored by default). You'll see a local `You used ...` line, and the HUD pops open with your row. It has no Whisper button, because it's you.
2. In a group, the cast monitor is already on: each group member gets one `[watch] <name>: casts are reaching RankWarden` line once their casts get through. Their outdated casts appear in the HUD, each player with their own Whisper button.
3. `/rw status` shows the settings, how many rank chains were built, how many casts were seen (yours, your group's, hidden), and whether addon chat is allowed.
4. Happy with it? Run `/rw whisper` again to turn auto-whisper back on, or whisper people one at a time with their **Whisper** button. Turn the monitor off with `/rw watch` once you no longer need it.

## Commands

| Command | Does |
|---|---|
| `/rw` | Toggle the window |
| `/rw help` | List commands |
| `/rw hud` | Toggle the lower-ranks HUD |
| `/rw hudlock` / `/rw hudreset` | Lock the HUD in place / move it back to its default spot |
| `/rw diag` | Open the diagnostics report (pre-selected, Ctrl+C to copy) |
| `/rw watch` | Toggle the cast monitor (one line per group member whose casts get through; on by default, remembered) |
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
| `/rw clear` | Forget who has already been notified (like the HUD's Reset) |
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

CI (`.github/workflows/ci.yml`) runs the same checks on **Lua 5.1**, the Lua version WoW runs, on every push. Coverage is **100%** of the addon's own code (everything except the generated `AbilityData.lua` and the libraries in `Libs/`), and CI fails if it drops.

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
| `Messages.lua` | Notification wording; shows a spell's rank once, even when the link already names it |
| `Session.lua` | Per-login state: detections, queue, session and per-player ignores, who was whispered |
| `Sync.lua` | Lead election between RankWarden users |
| `Notify.lua` | Whisper queue |
| `Detector.lua` | `UNIT_SPELLCAST_SUCCEEDED` → notification |
| `SlashCommands.lua` | `/rw` |
| `RankWarden_Options.lua` | Options panel |
| `Diagnostics.lua` | Hidden-cast tracking by restriction, secrecy census, copyable report window |
| `UI.lua` | Shared colours, icons, and actions (whisper, ignore, reset) |
| `HUD.lua` | Lower-ranks HUD (grouped by player) |
| `GUI.lua` | Main window, minimap button |

## Releasing

New versions go to CurseForge automatically:

1. Bump `## Version` in `RankWarden.toc` and `ADDON_VERSION` in `RankWarden.lua` (a test checks they match).
2. Add a `## <version>` section to [`CHANGELOG.md`](CHANGELOG.md); it becomes the release notes.
3. Push to `main`.

Once CI passes, [`release.yml`](.github/workflows/release.yml) runs [`tools/release.py`](tools/release.py). It builds the zip, uploads it to CurseForge for game version 1.60.1, then tags `v<version>` and creates a GitHub release with the zip attached. Pushes that don't change the version publish nothing.

One-time setup: create a CurseForge API token (CurseForge → your account → API tokens) and save it as a repository secret:

```bash
gh secret set CF_API_KEY --repo highnet/RankWarden
```

`python tools/release.py` with `DRY_RUN=1` builds the zip locally without uploading. The CurseForge game version comes from `CF_GAME_VERSION` in `release.yml` (currently `1.60.1`); change it when Forever's patch number changes.

Version history is in [`CHANGELOG.md`](CHANGELOG.md).

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
