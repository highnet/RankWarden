# Changelog

New versions are published to CurseForge automatically when the version in
`RankWarden.toc` is bumped on `main`; the matching section below becomes the
release notes.

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
