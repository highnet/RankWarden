# Changelog

New versions are published to CurseForge automatically when the version in
`RankWarden.toc` is bumped on `main`; the matching section below becomes the
release notes.

## 1.0.3

- **Cast monitor is quiet.** It prints one `[watch] <name>: casts are reaching RankWarden` line per group member, the first time their casts get through, instead of a line for every cast. Casts the game hides from addons (in combat, encounters, some instances, PvP) print nothing, since they can't be checked anyway.
- The monitor's checkbox, `/rw help` text and the empty Detections tab now describe it that way.

## 1.0.2

- **Rank shown once.** Forever's spell links already include the rank (`[Lightning Shield (Rank 3)]`), so RankWarden no longer adds a second "R3" / "(Rank 3)" in the HUD, the window, the history, `/rw report` or the whisper text. Plain links still get the rank added, in any client language.
- **Cast monitor no longer spams chat.** It prints one `[watch] <name>: casts are reaching RankWarden` line per group member, the first time their casts get through, instead of a line for every cast. Casts the game hides from addons (encounters, some instances, PvP) print nothing.
- Documentation: the README is reorganised (Detection, Whispers, Ignoring, HUD, Main window) and covers per-player whispers and ignores, the once-per-session whisper rule, the cast monitor default, and automatic releases.
- Tests now cover 100% of the addon's code, including start-up and the options panel, and CI enforces it.

## 1.0.1

- The cast monitor (`/rw watch`) is now on by default and remembered between sessions, so you can see straight away that your group's casts are reaching RankWarden.

## 1.0.0

First release for World of Warcraft: Forever (1.60.1).

- Detects party and raid members (and you) casting outdated spell ranks, using Forever's trainer data including new abilities and ranks.
- Lower-ranks HUD grouped by player, with a Whisper button per player and a Reset button.
- Each player is whispered about each spell at most once per session.
- Local only by default; whispers are optional and wait for combat and chat lockdown to end.
- Ignores commonly downranked spells (toggleable); right-click ignores a spell for that player for the session.
- Book, quest and drop rank notices at max level.
- Main window, history, options panel, minimap button.
