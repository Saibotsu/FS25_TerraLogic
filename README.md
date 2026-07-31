# TerraLogic brings a new level of realism to tillage and field work in Farming Simulator 25.

Instead of relying on artificial speed limits, TerraLogic evaluates the actual quality of your field work. Driving too fast can reduce work quality, increase wear, and ultimately affect your harvest yield. At the same time, draft forces, soil conditions, and stone impacts are simulated more realistically, making machine selection and working speed far more important.

The quality of every operation is stored directly on the worked soil. This allows different areas of the same field to have different quality values, which can individually influence the final harvest.

## Main features

Features:
- Removes the speed limit from most implements and replaces it with a realistic quality and wear system.
- Working speed directly affects the quality of field operations.
- Work quality is stored on the affected soil area in 4x4 meter sized chunks, allowing different parts of the same field to have different quality levels.
- Soil work quality directly influences the final harvest yield.
- More realistic implement damage caused by both visible and simulated underground stones, as well as speed and soil dependand abrasion.
- Vanilla surface stones can still be enabled or disabled independently.
- Reworked draft forces based on soil type and working conditions when using Precision Farming.
- Dynamic HUD showing the optimal speed range for balancing work quality, wear, and efficiency.
- Physical seeding dropouts at excessive working speeds, creating realistically unseeded areas (can be disabled for improved performance).
- Poorly plowed soil gradually recovers as crops grow.
- Server-controlled gameplay settings in multiplayer while HUD settings remain client-specific.
- Integration with Precision Farming and More Realistic. When using More Realistic, the preferred draft model can be selected in the mod settings.
- Compatible with Advanced Damage System, Realistic Harvesting, Moisture System, CoursePlay, AutoDrive, and many other mods.
- Multiplayer is tested and supported.

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
[`LICENSE`](LICENSE).
