# TerraLogic

TerraLogic turns the fields of Farming Simulator 25 into a persistent, living soil system. Instead of treating every field as one uniform surface, it remembers what happened at each location. Repeated tire tracks, headlands, carefully prepared seedbeds and poorly worked patches can therefore develop differently even when they belong to the same field.

Machinery and soil influence one another. Every supported operation changes the physical condition of the ground according to the implement, its working depth, its speed, its condition, the weather and the soil beneath it. The resulting soil then affects the next machine through draft, ground contact, Work Quality, wear and physical missed areas. Ploughing can leave loose but rough ground, for example; a seeder following immediately may have to slow down, while a suitable seedbed pass can improve placement at the cost of another trip across the field.

The soil continues to develop after the machinery has left. Moisture and temperature move through different depths, frost and thaw can loosen firm structures, living roots support recovery, crop rotation improves biological stability and intensive tillage can disturb it. Reduced tillage and direct drilling can build a more resilient soil over several years, but they do not magically remove existing compaction.

TerraLogic is not built around one mandatory machinery sequence. Its purpose is to make the condition of the soil matter, give different implements a meaningful role and let careful management improve both field performance and yield.

## Contents

- [Main features](#main-features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Controls](#controls)
- [How the soil simulation works](#how-the-soil-simulation-works)
- [The five soil maps](#the-five-soil-maps)
- [Field Analysis](#field-analysis)
- [Vehicle traffic, tires and compaction](#vehicle-traffic-tires-and-compaction)
- [Choosing a tillage implement](#choosing-a-tillage-implement)
- [Seeding, placement quality and rolling](#seeding-placement-quality-and-rolling)
- [Work Quality and physical missed areas](#work-quality-and-physical-missed-areas)
- [Working speed and the work HUD](#working-speed-and-the-work-hud)
- [Draft and tractor power](#draft-and-tractor-power)
- [Wear, overload and stone damage](#wear-overload-and-stone-damage)
- [Moisture, temperature and frost](#moisture-temperature-and-frost)
- [Resilience and natural recovery](#resilience-and-natural-recovery)
- [Yield](#yield)
- [Settings and tutorial](#settings-and-tutorial)
- [Precision Farming, multiplayer and other mods](#precision-farming-multiplayer-and-other-mods)
- [Troubleshooting](#troubleshooting)
- [Source layout](#source-layout)
- [Copyright](#copyright)

## Main features

- Five persistent, spatially resolved soil conditions: surface compaction, deep compaction, tilth, evenness and resilience.
- Fine soil maps that can show individual tire tracks, headland damage and local differences within one field.
- Dynamic soil effects for ploughs, subsoilers, cultivators, shallow cultivators, disc harrows, power harrows, spaders, rollers, seeders, direct drills, planters and many other supported tools.
- Soil responses based on implement type, working depth, current speed, soil condition, moisture, frost and machine wear.
- Dynamic wheel and axle loads calculated from the vehicle, fuel, ballast, attached equipment and current fill level.
- Ground contact pressure derived from wheel load and tire footprint rather than confused with tire inflation pressure.
- Meaningful differences between standard tires, wide tires, care tires, dual wheels and tracks.
- A complete soil-temperature and soil-moisture model with delayed responses at different depths.
- Crop water supply evaluated throughout the growth cycle rather than only on harvest day.
- Long-term soil recovery through living roots, varied rotations, cover crops, perennial cover, suitable moisture, warmth and frost-thaw cycles.
- Reduced tillage and direct-drilling systems that can build resilience when traffic and existing compaction are managed well.
- Stored Work Quality, Sowing Quality and physically plausible missed areas.
- A continuous TerraLogic yield factor from 60% to 110%, applied after the base game and Precision Farming have calculated their normal result.
- Dynamic draft, abrasion, mechanical overload, structural damage and visible or underground stone impacts.
- A compact work HUD with speed guidance, Work Quality, mechanical load, wear and contextual warnings.
- Five Field Analysis pages for soil overview, work and yield, weather, operation planning and recommendations.
- A small optional tutorial for important gameplay situations.
- Multiplayer support with server-authoritative soil and personal display settings.

## Installation

1. Download the official `FS25_TerraLogic.zip` release.
2. Place the ZIP in your Farming Simulator 25 `mods` folder.
3. Enable TerraLogic when loading or creating a savegame.

Precision Farming is optional. When it is installed, TerraLogic uses its soil types to create different moisture, draft, traffic and recovery behaviour. Without Precision Farming, the complete simulation remains available with a balanced generic soil profile.

If you package the mod yourself, `modDesc.xml` must be located directly at the root of the ZIP and not inside another folder.

Official versions are released through ModHub and the [TerraLogic GitHub repository](https://github.com/Saibotsu/FS25_TerraLogic). Files from other download sites may be outdated, modified or incomplete.

## Quick start

You do not need to understand every number before beginning. Start with one simple routine.

### 1. Inspect the field

Stand on the field and open TerraLogic Field Analysis from the ESC menu. Begin with **Overview**, **Weather and Effects** and **Recommendations**.

Look for the largest relevant problem:

- Is only one traffic lane compacted?
- Is most of the seedbed rough or cloddy?
- Is the surface too wet for traffic?
- Is the deeper layer genuinely compacted?
- Is the field already suitable for the intended operation?

A small local problem rarely justifies another pass over the entire field.

### 2. Choose a tool for that problem

A subsoiler is intended for deep compaction. A cultivator works the upper soil and prepares a seedbed. A shallow cultivator or harrow can refine and level without the full disturbance of deep tillage. If the ground is already supportive, even and biologically stable, a direct drill may avoid an unnecessary pass.

### 3. Work and react

Begin near the green range in the TerraLogic work HUD. If Work Quality falls or a warning reports wet, dry, frozen, cloddy or uneven soil, slow down and see whether the result improves. Mechanical load and wear describe risks to the implement rather than the quality of the crop operation.

### 4. Check the result

After the pass, inspect the relevant soil map. Later, use **Work and Yield** to see what was stored for the crop cycle.

> **Gameplay example:** A correctly ploughed field is loose but normally coarse and uneven. Direct seeding is possible if you slow down enough to maintain opener contact, but placement quality may remain limited. A suitable cultivator or power harrow costs another operation but creates a more even seedbed and permits better placement at normal speed. On an already even stubble field, a suitable direct drill can be the better option without that extra pass.

## Controls

All controls can be changed in Farming Simulator 25's normal key-binding menu and assigned to a controller.

| Action | Default keyboard binding |
| --- | --- |
| Cycle forward through the TerraLogic soil maps | `ALT` + `T` |
| Cycle backward through the soil maps | `ALT` + `SHIFT` + `T` |
| Show surface compaction directly | `CTRL` + `ALT` + `1` |
| Show deep compaction directly | `CTRL` + `ALT` + `2` |
| Show tilth directly | `CTRL` + `ALT` + `3` |
| Show evenness directly | `CTRL` + `ALT` + `4` |
| Show resilience directly | `CTRL` + `ALT` + `5` |

Pressing the direct shortcut for the currently active map disables that map again.

## How the soil simulation works

TerraLogic stores local soil values instead of one score for the whole field. A tire can change one narrow lane while the ground beside it remains untouched. Different working widths, overlapping passes, turning on the headland and repeatedly using the same lanes therefore have visible consequences.

Normal map fields receive suitable starting presets with light natural variation. Newly created saves and first installations also initialize fields already owned by the player once, so their starting soil matches their crop and field state. Unowned NPC fields continue to receive simulated presets until they are bought. Real changes on player fields and active mission fields are preserved.

Areas created with a plough's **Create Fields** function receive TerraLogic soil data as they become fields. They can then appear on the soil maps and be included in local analysis.

The five states are related, but none of them replaces the others. A field can be loose but uneven, level but over-refined, or compacted while still biologically resilient. This is why TerraLogic does not reduce the simulation to a single soil-quality percentage.

## The five soil maps

### Surface compaction

Surface compaction describes the worked upper layer. It is driven mainly by ground contact pressure, moisture, wheel slip and repeated traffic.

- `0%` means loose, uncompacted topsoil.
- `100%` means extremely strong surface compaction.
- Lower is better.

Cultivators and other suitable shallow tools can relieve moderate surface compaction. Heavy or wet traffic can recreate it quickly.

### Deep compaction

Deep compaction describes stress in the subsoil and root zone. Axle load matters more here than tire pressure alone. Ordinary shallow tools and rollers cannot repair it.

- `0%` means very loose subsoil.
- `100%` means extremely strong deep compaction.
- Lower is better.

Deep damage accumulates slowly under ordinary traffic but remains for a long time. A subsoiler is the main mechanical response when a large enough area is affected. Roots and natural processes improve it gradually but deliberately do not replace deep loosening after severe damage.

### Tilth

Tilth describes the size and condition of soil aggregates.

- Values near `0%` represent coarse clods.
- Values near the middle represent a useful crumb structure.
- Values near `100%` represent excessively fine, smeared or pulverized soil.

Higher is not always better. Implements break aggregates down more easily than they rebuild them. Repeated refining passes can therefore overwork a seedbed that was already suitable.

### Evenness

Evenness describes how level and consistent the surface is.

- Higher is better.
- Ploughing and deep repair usually leave rougher ground.
- Cultivators, disc harrows, power harrows and rollers can level it.

Seed openers, hoes, pickups and other ground-following tools depend on reliable contact. Unevenness first lowers their safe speed and quality. Physical missed areas appear only when the tool can no longer follow the surface at the driven speed.

### Resilience

Resilience represents long-term biological structure and the soil's ability to resist traffic and recover.

- Higher is better.
- Living roots, varied crop rotations, cover crops, perennial cover and undisturbed years improve it.
- Strong or repeated soil disturbance can reduce it.

High resilience reduces future compaction damage. It does not instantly remove compaction that already exists.

### Reading colours correctly

The maps and local field HUD use detailed gradients to show the measured value. Field Analysis uses green, yellow, orange and red text to rate the likely gameplay consequence. A map colour and an analysis warning therefore do not always change at exactly the same numerical point.

With an active map, the field-information HUD at the lower right shows all five values directly beneath the player. Outside a valid TerraLogic soil area, it displays dashes instead of invented local values.

## Field Analysis

Open the ESC menu and select the TerraLogic icon. Stand on the field you want to inspect. Field Analysis is divided into five pages.

### Overview

Overview gives a field-wide assessment of the five soil states. It averages only areas for which TerraLogic has valid soil data.

Area shares matter. A field average of 20% surface compaction may mean that the entire field is slightly compacted, or that two tire lanes are severely compacted while the rest is healthy. Use the minimap to find the location behind the average.

### Work and Yield

This page combines recorded field operations with the resulting yield potential.

- A dash means that the operation has not been recorded in the current crop cycle. It is neither good nor bad.
- Sowing, fertilizing, liming, weed control, rolling and mulching are evaluated with their recorded coverage.
- Yield losses are shown with a minus sign.
- Root-zone, water and fieldwork effects remain separate so the main cause is visible.
- The final TerraLogic potential is a multiplier applied after the base game or Precision Farming has calculated its normal yield.

### Weather and Effects

This page shows current surface and deeper temperature, moisture, precipitation and their consequences for traffic and the intended work.

Its text also explains what can help. Waiting for drainage may protect a wet seedbed, slowing down can improve tool contact, and rolling after sowing can recover only the correctable portion of poor seed-to-soil contact.

### Planner

Choose an implement class and model on the left. TerraLogic automatically selects the currently attached supported implement where possible.

The Planner estimates:

- a sensible speed range;
- Work Quality and physical missed-area risk;
- changes to all relevant soil states;
- additional draft under the current conditions;
- vehicle mass, implement mass and complete combination mass;
- highest axle load and ground contact pressure; and
- resulting compaction risk.

Vehicle information remains available while seated even when the vehicle is not standing on a field. Soil results require valid TerraLogic soil beneath the selected location.

The forecast uses the same soil, weather and implement calculations as real work. It cannot predict extra headland turns, overlap, wheel slip or future repeated passes.

### Recommendations

Recommendations are grouped by timing:

- **Current advice** helps before or during the intended operation.
- **Next operation** suggests a useful correction during the following pass.
- **Long term** covers traffic planning, crop rotation, cover crops and resilience over several seasons.

These recommendations are not a mandatory task list. Always check whether enough of the field is affected to justify the cost and traffic of another full-width operation.

## Vehicle traffic, tires and compaction

Every tire and track can affect the soil, including those on combines, trailers and transport vehicles. TerraLogic uses the wheel loads reported by the game's physics rather than assigning one fixed weight to a vehicle.

The load therefore changes with:

- fuel and ballast;
- grain, seed, fertilizer, slurry or other fill;
- front and rear attachments;
- mounted, semi-mounted and trailed equipment;
- support wheels and hitch load transfer; and
- dynamic weight transfer while driving.

A full combine can leave a different track from the same combine with an empty grain tank.

### Wheel load, axle load and contact pressure

**Wheel load** is the weight actually carried by one wheel. **Axle load** combines the wheels belonging to one physical axle.

- Ground contact pressure mainly affects the upper soil.
- Axle load is the stronger driver of deep stress.
- Total combination weight is useful for comparison, but it does not describe where that weight reaches the ground.

The displayed ground contact pressure is not tire inflation pressure. TerraLogic estimates the pressure transferred to the soil from wheel load, tire width, tire diameter and effective footprint.

### Tire choice

Wide tires, suitably loaded dual wheels and tracks distribute load across a larger area and usually reduce surface pressure. Care tires protect the crop but their small footprint can be harder on the soil. A wider track gauge changes where the pressure zones overlap; it does not divide the axle load by itself.

Tires can also affect tilth and evenness. Suitable pressure on slightly coarse ground may settle clods, while high pressure on dry ground can over-refine the surface. Wet traffic can smear or rut it, and excessive wheel slip shears aggregates and leaves a rougher track.

### Practical traffic management

- Avoid unnecessary passes and overlap.
- Use the lightest suitable vehicle and sensible ballast.
- Unload heavy harvest and transport vehicles before they become unnecessarily heavy.
- Wait for a drier surface when the schedule allows.
- Reuse planned lanes when concentrating damage is preferable to compacting new soil.
- Remember that repeated traffic accumulates even when one pass looks harmless.

## Choosing a tillage implement

TerraLogic does not make every tillage tool a different-looking version of the same reset button.

| Implement | Main purpose | Important consequence |
| --- | --- | --- |
| Plough | Strong topsoil loosening and inversion | Leaves coarse, uneven ground and disturbs resilience |
| Subsoiler | Repair of deep compaction | Disturbs the surface and is not a finished seedbed |
| Cultivator | Moderate topsoil loosening, mixing and levelling | More disturbance than a shallow finishing tool |
| Shallow cultivator | Gentle levelling and refinement | Less effective against strong compaction |
| Disc harrow | Shallow mixing, refinement and levelling | Repeated passes can make soil too fine |
| Power harrow | Strong seedbed refinement and levelling | Can overwork an already fine seedbed |
| Spader | Strong mixing and loosening without full mouldboard inversion | Provides limited deeper relief but still disturbs the soil |
| Roller | Levelling and seed-to-soil contact | Firms the surface and can add compaction, especially when wet |

### Working conditions matter

Wet soil can smear and lose structure. Very dry soil resists penetration. Frozen soil increases draft and sharply limits the penetration and quality of ground-working tools.

### Overspeed does not preserve full soil effect

At excessive speed, a ground tool gradually loses effective engagement. Loosening, levelling and other intended effects weaken rather than continuing indefinitely. At absurd speed, the pass approaches a failed operation: draft plateaus and the persistent soil effect becomes very small instead of rewarding a player for pulling a tiny implement at extreme speed.

This transition is smooth. There is no single speed at which a perfect result suddenly becomes worthless.

### Example operation chains

**Plough → seed:** Possible, but the rough seedbed can reduce placement quality. Slowing down can prevent contact-related missed areas, though it cannot make the seedbed itself ideal.

**Plough → cultivator or harrow → seed:** Costs another pass and adds traffic, but normally produces a more even, suitably crumbled seedbed for conventional and precision seeding.

**Cultivator → seed:** A suitable sequence when only moderate upper-soil work is needed.

**Harvest → direct drill:** A valid reduced-tillage system when compaction, evenness, moisture and residue conditions remain suitable.

No sequence stays ideal forever. Traffic, crop choice, weather and accumulated compaction determine when a corrective operation becomes worthwhile.

## Seeding, placement quality and rolling

Successful establishment requires suitable tilth, an even surface and reliable opener contact. TerraLogic separates the quality of placed seed from physical areas where no seed was placed.

### Conventional seeders

Conventional seeders expect a prepared seedbed. They can level very rough ground slightly, but they are not substitutes for dedicated seedbed preparation.

### Precision planters

Precision planters react more strongly to unevenness and unsuitable tilth because individual seed spacing and depth must remain consistent. They can still work on imperfect ground, but may require lower speed.

### Direct drills

Direct drills tolerate residue and rougher surfaces better and avoid full-width tillage. They protect long-term recovery by reducing disturbance, but they do not remove serious compaction. Their own levelling effect is appropriate to their construction rather than equivalent to a full cultivator pass.

### Placement quality and missed areas

Slowing down can completely prevent missed areas caused by poor ground following. It does not automatically restore every part of Sowing Quality: unsuitable tilth, poor moisture, frost, wear and an intrinsically rough seedbed can still produce less consistent depth, contact or emergence.

Physical missed seed remains visible and can only be corrected by reseeding. It is not deducted a second time as an additional TerraLogic yield penalty because no crop exists there in the first place.

### Rolling after sowing

A suitable field roller can improve seed-to-soil contact and recover part of the Sowing Quality lost to loose, coarse or rough contact conditions. It cannot:

- replace missing seed;
- repair an overspeed placement error;
- remove damage caused by implement wear; or
- replace proper seedbed preparation where the ground is fundamentally unsuitable.

Rolling also firms the surface. Wet or repeated rolling can create more compaction than the recovered placement quality is worth.

## Work Quality and physical missed areas

Work Quality represents how consistently a successful pass performed its intended job. TerraLogic stores it locally, so careful and rushed parts of the same field can remain different until the relevant crop cycle is completed or the operation is replaced.

Recorded categories include sowing, fertilizing, liming, weed control, rolling and mulching where applicable.

### Physical missed areas

Where the real working mechanism allows it, a machine can leave material or ground untreated rather than receiving only a lower score.

Examples include:

- unseeded patches behind a seeder;
- untreated strips behind application equipment;
- weeds left standing behind a weeder or hoe;
- swath material left behind by a pickup; and
- crop or residue missed by suitable surface-following tools.

Tillage implements do not receive artificial random holes. At extreme speed, their ground engagement and soil effect collapse smoothly instead.

Physical missed areas are part of the core simulation and cannot be disabled. This keeps the same implement behaviour and balancing in every savegame.

## Working speed and the work HUD

When manually driving supported machinery, TerraLogic can remove the rigid working-speed limit and replace it with physical consequences. AI helpers and unsupported machines retain their normal limits for compatibility.

The shop speed remains an important design reference, but it is not guaranteed to be the ideal speed under every condition. TerraLogic derives a realistic range from the implement and then adjusts quality, soil effect, draft and damage continuously.

### Reading the HUD

The compact work HUD shows:

- the nominal speed range;
- current Work Quality or Sowing Quality;
- mechanical load where the implement has meaningful ground-engaging draft;
- current wear information; and
- the most relevant contextual warning.

A dash means the recognized implement is ready but is not currently processing field or material. Implements without meaningful mechanical draft, such as a tedder or an electronically governed carrier module, can correctly show no mechanical-load value while still receiving Work Quality and soil effects.

The green range describes the implement's intended operating range. It is not a promise that wet, frozen, worn or unsuitable soil will produce a good result.

### Dynamic display behaviour

The default **Dynamic** mode shows the HUD whenever a supported implement is ready. It remains visible in the inefficient blue and excessive red speed zones. After three stable seconds in the green range, it fades away. Cruise-control changes and warnings show it again.

Warnings use a priority queue instead of interrupting one another. Each message remains readable for the selected duration before the next appears. The default is five seconds, and the local setting can be adjusted from one to ten seconds. A new urgent warning receives the next slot without cutting off the text currently being read.

## Draft and tractor power

The base game already uses implement width, working depth and nominal power requirement. TerraLogic adds the live influence of:

- soil type;
- surface and deep compaction;
- tilth;
- moisture;
- frost;
- implement condition;
- effective ground engagement; and
- actual working speed.

The result is not a simple horsepower gate. A powerful tractor may maintain more speed, but it still has to transfer the required force through the soil and implement. Poor conditions can prevent the combination from reaching shop speed even when the tractor's advertised horsepower appears sufficient.

TerraLogic therefore does not present a misleading required-horsepower value in the Planner. Additional draft describes how current soil changes the implement's normal requirement, not an exact tractor recommendation.

At extreme speed, ground engagement falls and draft eventually plateaus. Non-ground-engaging trailers do not receive invented tillage draft, although their weight and wheels still affect traction and compaction.

## Wear, overload and stone damage

TerraLogic keeps the base game's ordinary operating wear and adds causes tied to the actual work.

### Abrasion

For ground-engaging draft tools, abrasion depends on the force actually applied by the game, distance travelled, working depth and soil abrasiveness. Sandy soils can be especially abrasive. A worn implement loses Work Quality and soil effect and may require slightly more draft.

### Mechanical overload and structural damage

Mechanical load compares the measured load with the implement's usable design range. Damage follows a continuous curve:

- ordinary load mainly produces normal wear and abrasion;
- increasing overload progressively raises wear;
- severe overload adds structural damage; and
- there is no single threshold where a safe tool suddenly becomes destroyed.

A powerful tractor can therefore damage a smaller implement by forcing it to maintain an unrealistic operating condition. TerraLogic does not invent PTO load for tools whose power demand is not represented as draft.

### Visible stones

Visible field stones use the base game's stone layer. Stone size, coverage, working speed, ground following and exposed implement parts determine the chance and severity of contact. A stone picker reduces this surface risk by removing visible stones.

### Underground stones

Not every damaging stone is visible. TerraLogic simulates occasional underground contacts for penetrating tools. Working depth and displaced soil volume influence frequency, while soil type, speed and tool movement influence severity.

An underground-impact warning is named explicitly so the player does not have to wonder why a clean-looking field caused damage.

Rotating powered parts retain impact energy even at moderate travel speed. Power harrows, spaders, mulchers and pickups can therefore respond differently from passive tines and shares.

At 100% damage, the implement is broken and must be repaired before it can work correctly.

## Moisture, temperature and frost

TerraLogic creates a delayed soil climate from rain, snow, evaporation and air temperature.

### Different depths respond at different speeds

The surface responds comparatively quickly to weather. Moisture and temperature in the root zone and deeper soil follow more slowly. A brief shower can make the surface vulnerable to traffic while water is still moving into the root zone. A warm afternoon can thaw the surface while deeper soil remains frozen.

### Moisture affects machinery and soil

- Wet soil compacts and deforms more easily.
- Tillage can smear rather than crumble it.
- Seed openers may lose consistent penetration and placement.
- Very dry soil resists penetration and can require more draft.
- Soil type changes drainage, storage and recovery when Precision Farming is active.

Stored soil moisture alone does not reduce chemical herbicide quality. Rain falling during foliar spraying can wash herbicide off before absorption and can leave weed control less effective.

### Frost

Frozen soil increases draft and limits penetration and Work Quality. Cold conditions slow biological recovery. A genuine freeze-thaw transition can create a small one-time loosening pulse through frost action, especially when enough water was present in the soil. Remaining frozen does not repeatedly grant free recovery.

### Water during crop growth

Root-zone water is evaluated across the growth cycle. A dry or waterlogged period contributes only for the growth stages in which it occurred; it does not replace the complete history with the weather on harvest day.

Weather-related yield effects are deliberately limited because rain is not fully under player control and map climates vary. The yield portion can be disabled, while moisture still affects traffic, draft and Work Quality.

## Resilience and natural recovery

TerraLogic separates physical recovery from resilience.

**Physical recovery** slowly changes compaction, tilth and evenness through roots, wetting and drying, temperature, settling and frost-thaw processes.

**Resilience** describes the biological continuity and structural stability that make future traffic less damaging.

### Living roots and rotation

Living crops support recovery. Alternating crop groups with different rooting depths works better than repeatedly growing the same crop or the same root pattern. Legumes and deep-rooting oilseeds contribute more to deeper recovery than ordinary cereals. Cover crops add living roots between cash crops, and multi-year grass, clover or alfalfa can be especially valuable when left undisturbed.

Dead or withered plants no longer count as living cover.

### Tillage and disturbance

Ploughs, subsoilers and cultivators can solve immediate physical problems, but they interrupt biological continuity according to their working depth and intensity. Shallow tools disturb less than deep inversion. Rolling and mulching do not reset recovery in the same way.

A successful mulch pass leaves useful residue and provides a small one-time resilience contribution. Repeatedly mulching the same place cannot create unlimited improvement.

### Conventional tillage versus direct drilling

A conventional sequence can repair current compaction and create a reliable seedbed, but requires more passes and repeatedly disturbs the soil.

A direct-drilling system reduces full-width disturbance and can build resilience over several years. It still uses machinery, however, and therefore still creates compaction in its wheel tracks. If axle loads are controlled, traffic is limited and crop rotation supports recovery, resilience can increasingly protect the field. If the same heavy lanes are repeatedly overloaded, direct drilling alone will not repair them.

This creates a long-term choice rather than a universal winner:

- conventional tools offer faster mechanical correction;
- reduced tillage protects biological development and avoids traffic;
- occasional targeted loosening remains useful where deep damage is real; and
- unnecessary full-field repair can do more harm than a small local problem.

### Development-speed setting

Resilience development offers **Realistic (1x)**, **4x** and **Normal (8x)**. This setting accelerates the long-term biological system for careers of different lengths. Strong tillage losses are scaled as well so faster development does not become free resilience.

Natural physical compaction recovery remains deliberately slow and is not turned into instant repair by the faster resilience setting.

## Yield

The base game and Precision Farming calculate their complete normal yield first. TerraLogic then applies one continuous factor based on soil, water, recorded fieldwork and resilience.

- Around `100%` preserves the result already calculated by the game.
- Excellent management can reach `110%` of that result.
- Several severe TerraLogic problems can reduce the factor toward `60%`.
- Physically missing plants remain outside this floor because no crop exists in those places.

TerraLogic does not reset or replace fertilizing, lime, weeds, crop bonuses or the Precision Farming environmental system.

### Root-zone losses

Surface and deep compaction use separate continuous curves. Deep compaction can cause the larger loss and is harder to repair. Soil condition is sampled during growth, so compaction created during later field traffic contributes only to the relevant part of the crop cycle.

### Work-related losses

Poor Sowing Quality and supported application qualities contribute to the fieldwork portion. Small mistakes have a small effect; clearly unsuitable speed, condition or soil matters more. Physical missed areas are not deducted again.

### Rewarding good management

The upper 10% is not a separate bonus that erases penalties. It is the top of the same continuous TerraLogic factor. Poor soil, water stress or careless fieldwork moves the field down that scale; consistently healthy soil and high-quality work unlock the upper range.

## Settings and tutorial

TerraLogic settings are located in the normal game settings menu.

### Default settings for a new installation

| Setting | Default |
| --- | --- |
| Tutorial | On |
| Work HUD | Dynamic |
| Warning display duration | 5 seconds |
| Soil-map minimap zoom | 4x |
| Resilience development | Normal (8x) |
| Soil moisture affects yield | On |
| Visible stone damage | Extended TerraLogic damage |
| Stone-impact warnings | On |

### Local settings

These affect only the current player:

- tutorial on/off and tutorial reset;
- work-HUD mode;
- warning duration from one to ten seconds; and
- minimap zoom.

Turning the work HUD off also hides TerraLogic warnings. Work Quality and recognized implement count remain fixed parts of the HUD rather than separate switches.

The tutorial shows important situations once and can be reset without changing soil, field or crop data.

### Shared gameplay settings

These are controlled by the server or server administrator in multiplayer:

- resilience-development speed;
- moisture influence on yield;
- visible-stone damage model; and
- draft provider when More Realistic is installed.

Stone-impact warnings control notification only. Disabling them does not disable damage.

Soil states, Work Quality, recognized combination implements and physical missed areas are core mechanics and have no off switch.

Existing settings are retained after an update. New defaults do not overwrite a configured savegame or local profile.

## Precision Farming, multiplayer and other mods

### Precision Farming

Precision Farming is optional and remains responsible for its own nitrogen, pH, soil sampling and environmental-score systems.

When active, TerraLogic uses loamy sand, sandy loam, loam and silty clay to vary:

- moisture storage and drainage;
- traffic sensitivity;
- draft and penetration;
- abrasiveness; and
- natural recovery.

Activating a TerraLogic map temporarily replaces only Precision Farming's coloured map overlay so the two displays do not overlap. Precision Farming itself remains active.

### More Realistic

When More Realistic is installed, the settings let the server choose which mod provides draft.

- **More Realistic** leaves its live draft calculation in control.
- **TerraLogic** uses the soil, moisture, frost, wear and speed model described here and compensates the known More Realistic multiplier so the systems are not stacked.

### Combination implements

TerraLogic recognizes machinery through its game functions rather than a fixed list of vehicle names. Separate modules in a combination can therefore be processed in sequence. A cultivator followed by a seeder, or a slurry applicator combined with tillage equipment, uses the same shared soil model as the equivalent separate operations.

Electronically governed carrier systems may keep their own speed limit while TerraLogic still calculates soil effect and Work Quality for the attached module.

Unusual DLC or third-party machines that expose several real functions through only one inseparable work area may need a dedicated compatibility profile. Their ordinary vehicle traffic still affects the soil.

### Multiplayer

The server is authoritative for soil changes, field data and shared gameplay settings. Every player therefore receives the same soil result.

Map selection, HUD mode, warning duration, minimap zoom, handbook use and tutorial progress remain personal.

Soil-map updates are transferred incrementally to nearby clients. Recently changed ground may need a short moment to fill a widely zoomed-out minimap, while the local simulation remains server-authoritative.

### Other gameplay mods

TerraLogic is designed to coexist with CoursePlay, AutoDrive and other vehicle-control mods. AI and unsupported machinery retain normal speed limits where removing them would risk compatibility.

Special harvesting or physics mods may modify the same machinery or yield paths. When reporting a conflict, include the exact machine, map, active mods, operation and a TerraLogic audit log where possible.

## Troubleshooting

### Surface compaction is high

Check whether the problem is local or field-wide. Avoid additional wet or repeated traffic. A cultivator can relieve moderate upper compaction; shallow tools provide less relief, while ploughing is a stronger but more disruptive choice.

### Deep compaction is high

Reduce axle loads and repeated lanes first. Use a subsoiler where the affected area justifies deep repair. A shallow cultivator, harrow or roller cannot remove deep compaction, and natural recovery is intentionally slow.

### Sowing Quality is low

Check surface compaction, tilth, evenness, moisture, frost, speed and implement wear. Prepare only the property that is unsuitable. A roller can rescue part of a contact-related loss after sowing, but cannot recreate missing seed or correct wear and overspeed errors.

### Physical missed areas appear at shop speed

Shop speed assumes suitable conditions. Check evenness, tilth, moisture, frost and implement condition. Slow down and see whether the ground-contact risk disappears. If the seedbed is genuinely unsuitable, use the appropriate preparation rather than repeatedly crossing it with unrelated tools.

### Draft is unexpectedly high

Compare soil type, moisture, temperature, compaction, tilth, speed and implement condition in Field Analysis. More horsepower may keep the tool moving but does not remove the cause. If More Realistic is installed, confirm which mod currently controls draft.

### Damage is unexpectedly high

Check mechanical load, working speed, soil abrasiveness, implement condition and visible or underground stone warnings. Structural overload and stone impacts are separate causes.

### Yield estimate is low

Open **Work and Yield** and separate root development, water supply and recorded fieldwork. Then use Overview and the maps to find where the largest loss occurs. Do not make a full-field repair for a problem limited to a few wheel tracks.

### No soil values are shown

Stand on a valid field or player-created TerraLogic soil area. Outside such an area, dashes are intentional. New areas created with a plough receive data as the game recognizes them as field ground.

### Precision Farming colours disappear

Disable the active TerraLogic map by cycling to Off or pressing its direct shortcut again. Only the Precision Farming overlay was hidden; its gameplay remains active.

## Source layout

- `scripts/TerraLogic.lua` — specialization setup and shared integration.
- `scripts/TerraLogicMain.lua` — mission lifecycle, work HUD, console commands and diagnostic logging.
- `scripts/TerraLogicSoilManager.lua` — persistent soil maps, tillage effects, traffic integration, recovery and yield-facing soil state.
- `scripts/TerraLogicWheelCompactionManager.lua` — wheel loads, axle grouping, tire footprints and traffic compaction.
- `scripts/TerraLogicSoilMoistureManager.lua` — surface and root-zone moisture.
- `scripts/TerraLogicSoilTemperatureManager.lua` — soil temperatures, frost history and thaw pulses.
- `scripts/TerraLogicSoilProfiles.lua` — soil-type responses and shared balancing profiles.
- `scripts/TerraLogicImplementProfiles.lua` — implement classes, working behaviour and soil targets.
- `scripts/TerraLogicQualityManager.lua` — stored Work Quality, growth-cycle sampling and yield integration.
- `scripts/TerraLogicDropoutManager.lua` — physical missed areas for supported operations.
- `scripts/TerraLogicGrassGapManager.lua` — persistent grass gaps and regrowth handling.
- `scripts/TerraLogicFieldAnalysis.lua` — field sampling, Planner forecasts and recommendations.
- `scripts/TerraLogicTutorialManager.lua` — contextual tutorial state.
- `scripts/TerraLogicSettings.lua` — local settings, shared settings and multiplayer synchronization.
- `scripts/TerraLogicAuditManager.lua` — structured diagnostic panels used by CSV tests.
- `gui/` — Field Analysis and shared GUI profiles.
- `translations/` — German and English localization.

## Copyright

Copyright © 2026 The Mod Workshop. All rights reserved.

This repository is source-available for inspection; it is **not** released under an open-source license. See [`LICENSE`](LICENSE) for the applicable terms.
