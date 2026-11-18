# Third-party notices and credits

RankWarden is Copyright (c) 2026 highnet (MIT, see [`LICENSE`](LICENSE)). It includes, or is derived from, the
following works. Thank you to everyone listed here.

## RankSentinel (MIT)

<https://github.com/valkyrnstudios/RankSentinel> · <https://www.curseforge.com/wow/addons/ranksentinel>

RankSentinel is the addon RankWarden is modelled on: the idea of watching your group for low-rank casts and telling
the caster, the grace-level rules, and the curated list of vanilla abilities where a low rank is a mistake
(`tools/RankSentinel_Classic.lua`, used to build `AbilityData.lua`).

- Copyright (c) 2021 Gogo1951; maintained by SabreValkyrn / Valkyrn Studios. Full license text:
  [`LICENSE.RankSentinel`](LICENSE.RankSentinel).
- RankSentinel's own credits:
  - **Gogo**: addon collaboration and data curation
    ([Gogo's revised ability list](https://docs.google.com/spreadsheets/d/1jtx1WyfChzACzh0WBWANtrqkRtS3D-zPWqs3eOnyVvY/edit?usp=sharing)).
  - **Aevala** and **Fathom**: ability data feedback.
  - **Splendiferus**: testing and feedback.
- RankSentinel was itself inspired by the legacy addon [RankWatch](https://www.curseforge.com/wow/addons/rankwatch),
  and is a spiritual successor to the GogoWatch and SpellSnob addons.

## What's Training? (MIT)

<https://www.curseforge.com/wow/addons/whats-training>

WoW: Forever trainer spell IDs and levels (`Classes/Camelot`), used by `tools/build_ability_data.py` to generate
`AbilityData.lua`. Copyright (c) 2019 Sveng.

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright
> notice and this permission notice shall be included in all copies or substantial portions of the Software.
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

## Embedded libraries (`Libs/`)

Unmodified copies.

| Library | Version | License |
|---|---|---|
| [LibStub](https://www.wowace.com/projects/libstub) | 2 | Public domain |
| [CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler) | 8 | BSD |
| [AceAddon-3.0](https://github.com/WoWUIDev/Ace3) | 13 | BSD (Ace3) |
| AceEvent-3.0 | 4 | BSD (Ace3) |
| AceConsole-3.0 | 7 | BSD (Ace3) |
| AceComm-3.0 | 14 | BSD (Ace3) |
| [ChatThrottleLib](https://www.wowace.com/projects/chatthrottlelib) (bundled with AceComm) | — | Public domain (Mikk) |
| AceDB-3.0 | 33 | BSD (Ace3) |
| AceGUI-3.0 (with widgets) | 41 | BSD (Ace3) |
| AceConfig-3.0 / AceConfigRegistry / AceConfigCmd / AceConfigDialog | 3 / 22 / 14 / 92 | BSD (Ace3) |

Ace3: Copyright (c) 2007, Ace3 Development Team. Redistribution and use in source and binary forms, with or without
modification, are permitted provided the copyright notice, conditions and disclaimer are retained.

## Research

The Forever API findings behind RankWarden came from the
[ForeverPlusPlus API notes](https://github.com/xIGBClutchIx/ForeverPlusPlus/blob/main/docs/forever-api.md) (xIGBClutchIx),
[forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (Thunderz96), and the
[Forever UI source mirror](https://github.com/Gethe/wow-ui-source/tree/forever) (Gethe).
