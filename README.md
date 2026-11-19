# RankWarden

<img src="media/logo.png" alt="RankWarden" width="128" align="right">

A **RankSentinel-style rank checker for World of Warcraft: Forever.** RankWarden spots when you or your party and raid members cast an outdated spell rank, and lets them know.

**[Download on CurseForge](https://www.curseforge.com/wow/addons/rankwarden)** · [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/highnet/RankWarden/issues)

## Features

- **Catches outdated ranks** for you and your group, using Forever's own trainer data, including Forever's new abilities and ranks.
- **Lower-ranks HUD**: a small panel listing who used which outdated rank, with a **Whisper** button per player.
- **Whispers players once** per spell per session, after combat ends. You can turn auto-whisper off with `/rw whisper`.
- **Ignores spells people downrank on purpose** (heals, Frostbolt, Earth Shock, Moonfire, …). Right-click a spell in the HUD to ignore it for that player.
- **Book and quest ranks**: tells max-level players when a stronger rank exists that trainers don't sell.
- **Main window** (`/rw`) with history, ignore lists and settings, plus a minimap button.

## Where it works

WoW: Forever limits what addons can see and send:

- **Your own casts** are checked everywhere.
- **Group members' casts** are hidden from addons wherever Forever applies an addon restriction. That includes the **open world**, as well as dungeons, raids and PvP. RankWarden tells you when you're in such an area, both in chat and in the HUD.
- **Whispers** only work on realms that allow addon chat. Elsewhere, notes stay in your own chat and the Whisper buttons are disabled.

## Install

Install it with the CurseForge app, or copy the `RankWarden` folder into `World of Warcraft\_forever_\Interface\AddOns\`, then restart the game.

## Commands

| Command | What it does |
|---|---|
| `/rw` | Open the window |
| `/rw hud` | Show or hide the HUD |
| `/rw whisper` | Turn auto-whisper on or off |
| `/rw watch` | Turn the cast monitor on or off |
| `/rw diag` | Diagnostics report you can copy (useful for bug reports) |
| `/rw help` | List every command |

## Credits

Made by **Sandy Klawz** (EU PvE). Inspired by and built on [RankSentinel](https://github.com/valkyrnstudios/RankSentinel) (Gogo1951, SabreValkyrn, and their contributors Gogo, Aevala, Fathom and Splendiferus). Forever trainer data comes from [What's Training?](https://www.curseforge.com/wow/addons/whats-training) by Sveng. Uses Ace3.

MIT licensed. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Developers: see [CONTRIBUTING.md](CONTRIBUTING.md).
