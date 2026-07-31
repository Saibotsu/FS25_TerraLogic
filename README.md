# TerraLogic

TerraLogic is a Farming Simulator 25 gameplay mod by **The Mod Workshop**. It
replaces hard implement speed limits with a field-work simulation in which
speed influences work quality, implement wear, draft and harvest results.

## Main features

- Persistent, area-based quality for soil preparation, sowing, fertilizing,
  liming, weed control and supported grass work.
- Yield effects based on the quality stored where the crop is harvested.
- Speed- and soil-dependent wear, draft and stone impacts.
- A compact speed/quality HUD and detailed developer diagnostics.
- Optional physical sowing dropouts.
- Precision Farming, More Realistic and multiplayer integration.

Combines and ordinary crop harvesters are intentionally excluded from the
implement simulation to avoid conflicts with dedicated harvesting mods.
Windrowers, tedders and belt rakes retain their standard game behavior because
the game does not expose a suitable quality or yield result for those passes.

## Installation

For normal gameplay, place the released `FS25_TerraLogic.zip` in the Farming
Simulator 25 `mods` directory and enable it for the savegame. Do not zip the
containing repository folder; `modDesc.xml` must be at the root of the mod ZIP.

## Source layout

- `TerraLogic.lua`: vehicle specialization and physical simulation
- `TerraLogicQualityManager.lua`: persistent cells, yield and synchronization
- `TerraLogicDropoutManager.lua`: deterministic dropout patterns
- `TerraLogicImplementProfiles.lua`: implement recognition and balance values
- `TerraLogicMain.lua`: mission lifecycle, HUD, console and debug tools
- `TerraLogicSettings.lua`: savegame, menu and multiplayer settings

## Copyright

Copyright © 2026 The Mod Workshop. All rights reserved. This repository is
source-available for inspection; it is **not** an open-source license. See
[`LICENSE`](LICENSE) and [`SOURCE-NOTICE.md`](SOURCE-NOTICE.md).
