# Contributing to RankWarden

Thanks for helping! This guide covers how RankWarden works on WoW: Forever, the development tooling, and how releases are published. For what the addon does, see the [README](README.md).

## How it works on Forever

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

## Diagnostics report (`/rw diag`)

Opens a plain-text report, already selected, so you can press **Ctrl+C** and paste it anywhere (a bug report, Discord, an AI assistant). It's also on the **Diagnostics** button in the main window. The report covers:

- Client version, build and interface, plus RankWarden's settings and ignore counts.
- Casts seen this session (yours, your group's, hidden), and **which addon restrictions were active** (Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat) whenever a group member's cast was hidden or got through. This shows exactly when Forever hides other players' casts.
- A **secrecy census**: how many tracked spells Forever marks `NeverSecret`, `AlwaysSecret` or `ContextuallySecret` as casts (`C_Secrets.GetSpellCastSecrecy`).
- **Your location** (zone, sub-zone, map ID, open world or instance type), and whether group casts are known to be hidden here.
- Addon chat state, group, lead, the last 10 detections, and the last 25 group casts with the restrictions active and where you were.

**Reset counters** starts a fresh measurement; **Refresh** updates the report.

## Testing in game

Auto-whisper is **on** by default. To try RankWarden without messaging anyone, run `/rw whisper` first to turn it off; notes then stay in your own chat. Then:

1. Cast a low rank of one of your own spells, e.g. Fireball Rank 1 at level 20+ (heals and Frostbolt are ignored by default). You'll see a local `You used ...` line, and the HUD pops open with your row. It has no Whisper button, because it's you.
2. In a group, the cast monitor is already on: each group member gets one `[watch] <name>: casts are reaching RankWarden` line once their casts get through. Their outdated casts appear in the HUD, each player with their own Whisper button.
3. `/rw status` shows the settings, how many rank chains were built, how many casts were seen (yours, your group's, hidden), and whether addon chat is allowed.
4. Happy with it? Run `/rw whisper` again to turn auto-whisper back on, or whisper people one at a time with their **Whisper** button. Turn the monitor off with `/rw watch` once you no longer need it.

## Full command list

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
