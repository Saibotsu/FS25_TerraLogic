# TerraLogic

TerraLogic makes field work in Farming Simulator 25 more realistic by replacing many fixed working-speed limits with actual consequences.

You can drive faster than the speed shown in the shop, but doing so is not free. Poor work can affect crop growth and harvest yield, increase wear, require more power, or leave visible mistakes behind. A small amount of overspeed may save some time, while pushing a machine far beyond its intended speed usually creates more work than it saves.

Quality is saved separately across the field. If you work carefully in one area and rush through another, both areas can produce different results later. This makes tractor power, implement size, soil conditions, machine condition, and working speed much more important.

## Main features

- Removes the fixed speed limit from supported implements and lets you choose how fast you want to work.
- Poor work quality can affect crop growth and harvest yield.
- Different parts of the same field can have different work quality.
- Excessive speed can leave visible mistakes such as unseeded ground, standing grass, untreated weeds, or missed fertilizer.
- Implements wear faster when they are pushed too hard.
- Stones can damage implements, including stones hidden below the surface.
- Draft changes with the implement, working conditions, and soil type when Precision Farming is installed.
- A new dynamic HUD shows your current working speed, the recommended range, and work quality where available.
- Mowers, tedders, windrowers, stone pickers, sprayers, spreaders, weeders, and hoes are fully included.
- Mower mistakes do not create extra grass. Grass left standing only produces material when it is properly mown later.
- Weed sprayers can leave weeds standing when driven too fast.
- Fertilizer and lime spreaders can leave parts of the field untreated.
- Mechanical weeders and hoes may miss weeds. At extreme speeds, they can also damage crops and disturb the seedbed.
- Poor plowing work can recover slightly while the crop grows.
- Gameplay settings are controlled by the server in multiplayer, while HUD settings remain personal for each player.
- Supports Precision Farming and More Realistic, including a selectable draft model when More Realistic is installed.
- Designed to work alongside Advanced Damage System, Realistic Harvesting, Moisture System, CoursePlay, AutoDrive, and many other gameplay mods.
- Multiplayer is supported and tested.

Combines and regular crop harvesters are intentionally not changed. This avoids conflicts with mods that already handle harvesting losses and combine behavior, such as Realistic Harvesting.

## Work quality and mechanical consequences

TerraLogic uses two different types of consequences when you work too fast.

### Work quality

Work quality represents mistakes that are not immediately visible.

A field may look properly cultivated or seeded, but the implement may not have worked at the correct depth or placed the seed evenly. The crop can still grow, although its growth and final yield may suffer.

Examples include:

- uneven working depth while plowing or cultivating;
- seed placed at the wrong depth;
- poorly distributed fertilizer or lime; and
- incomplete or ineffective weed control.

Work quality is remembered until the crop is harvested or the previous work is replaced by another field operation.

### Mechanical consequences

Mechanical consequences are mistakes you can see directly on the field.

Depending on the machine, excessive speed can cause:

- unseeded patches behind a seeder;
- islands of uncut grass behind a mower;
- grass left untouched by a tedder or windrower;
- stones left behind by a stone picker;
- untreated areas behind fertilizer, lime, or herbicide equipment;
- weeds left standing behind weeders and hoes; or
- damaged crop and disturbed soil after extremely fast mechanical weeding.

The faster you drive, the more noticeable these mistakes become. Slight overspeed may still be worthwhile, but extreme speed will normally leave enough unfinished work that a second pass is required.

### Which machines use which system?

Some machines mainly affect the quality of the work:

- Plows (including subsoilers 
- Cultivators
- Rollers
- Mulchers

Other machines can reduce work quality and also leave visible mistakes:

- Seeders
- Direct drills
- Planters
- Fertilizer and herbicide sprayers
- Fertilizer and lime spreaders

Mowers, tedders, and windrowers use visible mechanical consequences instead of a separate work-quality penalty.

Stone pickers, weeders, and hoes also rely mainly on visible mechanical consequences, together with their normal wear and power requirements.

When both systems are used, they represent different problems. A missed area is visibly untreated, while a successfully worked area may still have poor quality. TerraLogic reduces the additional work-quality penalty while mechanical consequences are enabled so that the same mistake is not punished at full strength twice.

If mechanical consequences are disabled in the settings, machines that rely solely on them receive their normal shop speed limit again. Machines with work quality continue to use the full quality system.

## Precision Farming

TerraLogic works alongside Precision Farming and does not replace its nitrogen, pH, or soil systems.

Sprayers with pulse-width modulation can still adjust their application rate automatically. However, driving far beyond the advertised speed can leave increasingly large parts of the field untreated. This prevents the upgrade from allowing unlimited spraying speed without consequences.

The material inside the machine is handled separately. A sprayer filled with fertilizer records fertilizing quality, while the same sprayer filled with herbicide records weed-control quality.

## Installation

Place `FS25_TerraLogic.zip` in your Farming Simulator 25 `mods` folder and enable the mod for your savegame.

If you package the mod yourself, make sure that `modDesc.xml` is located directly at the root of the ZIP and not inside another folder.

## Source layout

- `TerraLogic.lua`: main vehicle and field-work logic
- `TerraLogicQualityManager.lua`: saved work quality and harvest effects
- `TerraLogicDropoutManager.lua`: visible mechanical-consequence patterns
- `TerraLogicImplementProfiles.lua`: supported implements and balancing values
- `TerraLogicMain.lua`: HUD, console commands, and mission setup
- `TerraLogicSettings.lua`: settings and multiplayer synchronization

## Copyright

Copyright © 2026 The Mod Workshop. All rights reserved. This repository is source-available for inspection; it is **not** an open-source license. See [`LICENSE`](LICENSE).
