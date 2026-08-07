--[[
    TerraLogicImplementProfiles.lua
    Central implement recognition and gameplay balance profiles.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-PROF-1.200147
]]

-- Central implement balance table. All values which vary by implement class
-- belong here so gameplay balancing never requires editing the simulation code.
TerraLogicImplementProfiles = {}
OverSpeedDamageImplementProfiles = TerraLogicImplementProfiles
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicImplementProfiles.SOURCE_FINGERPRINT = 1.200147

-- Central real-world baseline table. Entries without a simulation profile are
-- retained for future recognition work; they do not make an unsupported
-- vehicle eligible by themselves.
TerraLogicImplementProfiles.REAL_SPEED_KPH = {
    plow = 8,
    subsoiler = 8,
    cultivator = 10,
    shallowCultivator = 12,
    discHarrow = 12,
    powerHarrow = 7,
    weeder = 12,
    hoe = 15,
    rotaryHoe = 15,
    stonePicker = 8,
    potatoHarvester = 6,
    beetHarvester = 6,
    mulcher = 8,
    mower = 10,
    windrower = 10,
    tedder = 10,
    beltRake = 10,
    baler = 15,
    loaderWagon = 20,
    roller = 8,
    sowingMachine = 10,
    directDrill = 10,
    precisionPlanter = 8,
    fertilizerSpreader = 15,
    liquidSprayer = 12,
    manureSpreader = 10,
    slurryDistributor = 10,
    dribbleBar = 10,
    slurryInjector = 8,
    spader = 8
}
local REAL_SPEED = TerraLogicImplementProfiles.REAL_SPEED_KPH

-- Mod implements occasionally advertise a working speed below the realistic
-- class reference. In that case the XML/shop value remains the hard upper end
-- of the green range. A proportional gap produces a useful safe range without
-- ever allowing zero or negative reference speeds on unusually slow tools.
-- Returns a non-zero safe speed when a mod tool is slower than its class norm.
function TerraLogicImplementProfiles.getLowShopSafeSpeed(shopSpeed)
    local shop = math.max(tonumber(shopSpeed) or 0, 0)
    if shop <= 0 then return 0 end
    local gap = math.clamp(shop * 0.20, 1, 3)
    local minimum = math.min(1, shop * 0.50)
    return math.clamp(shop - gap, minimum, shop)
end

-- Fraction of the reference plough's sliding soil-abrasion exposure. Entries
-- without an active profile are retained for future recognition work only.
TerraLogicImplementProfiles.ABRASION_FACTOR = {
    plow = 1.00,
    subsoiler = 0.90,
    cultivator = 0.85,
    shallowCultivator = 0.75,
    discHarrow = 0.65,
    powerHarrow = 0.65,
    weeder = 0.25,
    hoe = 0.40,
    rotaryHoe = 0.40,
    stonePicker = 0.60,
    potatoHarvester = 0.55,
    beetHarvester = 0.50,
    -- Surface-wear implements scale their Vanilla damage directly and do not
    -- use mineral-soil abrasion.
    mulcher = 0.00,
    mower = 0.05,
    windrower = 0.05,
    tedder = 0.05,
    beltRake = 0.03,
    baler = 0.00,
    loaderWagon = 0.00,
    roller = 0.00,
    sowingMachine = 0.30,
    directDrill = 0.45,
    precisionPlanter = 0.25,
    fertilizerSpreader = 0.00,
    liquidSprayer = 0.00,
    manureSpreader = 0.00,
    slurryDistributor = 0.00,
    dribbleBar = 0.02,
    slurryInjector = 0.40,
    spader = 1.00
}
local ABRASION = TerraLogicImplementProfiles.ABRASION_FACTOR

-- Whole-yield balance of the stored gameplay categories. These are separated
-- from implement recognition: several implement classes can contribute to the
-- same category and soil preparation averages its distinct contributors.
TerraLogicImplementProfiles.WORK_QUALITY_CATEGORIES = {
    soil       = {weight = 1.10, maxPenalty = 0.45},
    seed       = {weight = 1.20, maxPenalty = 0.50},
    -- Bonus work stores only the relative loss of its positive contribution.
    -- These caps are conservative Vanilla fallbacks; active PF supplies a
    -- dynamic local N/pH gain instead.
    fertilizer = {weight = 0.225, maxPenalty = 0.184},
    lime       = {weight = 0.15,  maxPenalty = 0.131},
    herbicide  = {weight = 0.20,  maxPenalty = 0.167},
    roller     = {weight = 0.025, maxPenalty = 0.025}
}

-- Category B operations combine a visible physical miss with an invisible
-- quality loss on the part that was actually processed. At/below shop speed
-- the common 100 -> 95% curve remains unchanged. Above shop speed, enabled
-- physical dropouts retain only this share of the additional Work Quality
-- deterioration; disabling dropouts restores the complete quality curve.
-- Every Category B material uses the same switch. Physical misses remain the
-- visible effect; the quality ledger represents the invisible quality of the
-- successfully treated part of the WorkArea.
TerraLogicImplementProfiles.WORK_QUALITY_DROPOUT_COMPONENTS = {
    seed = true,
    fertilizer = true,
    lime = true,
    herbicide = true
}
-- Thirty percent makes roughly +1 km/h economically neutral for a typical
-- 12 km/h seeder once its visible misses are included; +2 km/h is already a
-- net loss. Category B therefore has a narrow tolerable margin without making
-- high-speed work profitable. However, due to work areas overlapping each
-- other and potentially reducing the expected dropout percentage, overspeed
-- share is coorected to 0.45
TerraLogicImplementProfiles.WORK_QUALITY_DROPOUT_OVERSPEED_SHARE = 0.45

-- Work Quality never represents the percentage of visibly processed ground.
-- It describes how well the successful part of an operation was performed.
-- Even at absurd speed a tool still does some useful work, so every stored
-- quality class approaches a plausible minimum instead of hitting an abrupt
-- zero. Class overrides keep different tools that write the same ledger
-- component (for example a drill and a planter) independently tuneable.
TerraLogicImplementProfiles.WORK_QUALITY_MINIMUMS = {
    componentFallback = {
        soilPlow = 0.25,
        soilCultivate = 0.30,
        seed = 0.15,
        fertilizer = 0.35,
        lime = 0.35,
        herbicide = 0.35,
        roller = 0.65,
        mulch = 0.50
    },
    byClass = {
        plow = {soilPlow = 0.25},
        subsoiler = {soilPlow = 0.25},
        cultivator = {soilCultivate = 0.30},
        shallowCultivator = {soilCultivate = 0.35},
        discHarrow = {soilCultivate = 0.30},
        powerHarrow = {soilCultivate = 0.30},
        spader = {soilCultivate = 0.25},

        -- A direct drill writes both seedbed and placement quality.
        directDrill = {soilCultivate = 0.30, seed = 0.12},
        sowingMachine = {seed = 0.15},
        precisionPlanter = {seed = 0.10},

        fertilizerSpreader = {fertilizer = 0.35, lime = 0.35},
        liquidSprayer = {
            fertilizer = 0.35,
            lime = 0.35,
            herbicide = 0.35
        },
        -- Broad organic distribution remains somewhat useful even when its
        -- pattern becomes very uneven. Applicators use the same conservative
        -- floor until their individual PF distribution can be distinguished.
        manureSpreader = {fertilizer = 0.40},
        slurrySpreader = {fertilizer = 0.40},
        slurryApplicator = {fertilizer = 0.40},

        weeder = {herbicide = 0.35},
        hoe = {herbicide = 0.35},
        roller = {roller = 0.65},
        mulcher = {mulch = 0.50}
    }
}

function TerraLogicImplementProfiles.getMinimumWorkQuality(classKey, component)
    local balance = TerraLogicImplementProfiles.WORK_QUALITY_MINIMUMS
    local classBalance = balance.byClass[classKey]
    local value = classBalance ~= nil and classBalance[component] or nil
    if value == nil then
        value = balance.componentFallback[component]
    end
    return value ~= nil and math.clamp(tonumber(value) or 0, 0, 0.99) or nil
end

-- Every class in this list relies on physical misses as part of its unlimited-
-- speed consequence. If the server disables physical dropouts, the original
-- XML/shop speed limit is restored. Category B still uses its full quality
-- curve if another mod or physics state nevertheless pushes it beyond that
-- limit. Utility dropout tools remain covered even though they are outside the
-- user's agronomic A/B/C quality groups.
TerraLogicImplementProfiles.DROPOUT_DEPENDENT_SPEED_CLASSES = {
    directDrill = true,
    sowingMachine = true,
    precisionPlanter = true,
    liquidSprayer = true,
    fertilizerSpreader = true,
    manureSpreader = true,
    slurrySpreader = true,
    slurryApplicator = true,
    baler = true,
    loaderWagon = true,
    mulcher = true,
    mower = true,
    windrower = true,
    tedder = true,
    stonePicker = true,
    weeder = true,
    hoe = true
}

-- Whole-harvest quality balance. `weight` controls how quickly bad work
-- quality becomes an actual relative yield loss; `maxPenalty` caps the loss
-- caused by that one operation. The source table also keeps currently
-- unsupported forage/harvest classes documented for later recognition.
TerraLogicImplementProfiles.YIELD_QUALITY = {
    plow =               {weight = 0.30, maxPenalty = 0.10},
    subsoiler =          {weight = 0.20, maxPenalty = 0.08},
    plowGroup =          {weight = 0.25, maxPenalty = 0.09},
    cultivator =         {weight = 0.40, maxPenalty = 0.12},
    shallowCultivator =  {weight = 0.30, maxPenalty = 0.08},
    discHarrow =         {weight = 0.40, maxPenalty = 0.10},
    powerHarrow =        {weight = 0.60, maxPenalty = 0.15},
    cultivationGroup =   {weight = 0.425, maxPenalty = 0.1125},
    roller =             {weight = 0.20, maxPenalty = 0.05},
    sowingMachine =      {weight = 0.90, maxPenalty = 0.30},
    directDrill =        {weight = 1.00, maxPenalty = 0.30},
    precisionPlanter =   {weight = 1.00, maxPenalty = 0.35},
    fertilizerSpreader = {weight = 0.70, maxPenalty = 0.20},
    -- Poor distribution leaves under-limed acidic patches. Liming affects
    -- nutrient availability and root development, but its response is slower
    -- and less direct than seed placement or fertilizer application.
    lime =                {weight = 0.50, maxPenalty = 0.12},
    liquidFertilizer =   {weight = 0.70, maxPenalty = 0.20},
    herbicideSprayer =   {weight = 0.60, maxPenalty = 0.15},
    manureBroadcaster =  {weight = 0.60, maxPenalty = 0.15},
    dribbleBar =         {weight = 0.70, maxPenalty = 0.18},
    trailingShoe =       {weight = 0.75, maxPenalty = 0.20},
    slurryInjector =     {weight = 0.80, maxPenalty = 0.22},
    -- FS25 exposes liquid fertilizer/manure applicators through one shared
    -- sprayer path. Herbicide is distinguishable by fill type and therefore
    -- retains its own row; the remaining five liquid rows are averaged here.
    liquidApplication =  {weight = 0.71, maxPenalty = 0.19},
    mulcher =            {weight = 0.15, maxPenalty = 0.05},
    mower =              {weight = 0.40, maxPenalty = 0.12},
    windrower =          {weight = 0.30, maxPenalty = 0.08},
    beltRake =           {weight = 0.35, maxPenalty = 0.08},
    tedder =             {weight = 0.20, maxPenalty = 0.05},
    potatoHarvester =    {weight = 0.90, maxPenalty = 0.30},
    beetHarvester =      {weight = 0.90, maxPenalty = 0.30},
    sugarBeetHarvester = {weight = 0.90, maxPenalty = 0.30},
    rootCropHarvester =  {weight = 0.90, maxPenalty = 0.30}
}
local YIELD_QUALITY = TerraLogicImplementProfiles.YIELD_QUALITY

-- Field guide for balancing:
-- work.optimalSpeedKph   realistic informational/class speed (nil = shop speed)
-- work.depthCm           descriptive/debug working depth
-- work.groundContactTool enables lowered/maxForce wear/contact detection
-- draft.enabled          allows every TerraLogic MaxForce addition for this class
-- draft.overspeedScale   scales only the shared overspeed curve's excess
-- wear.model             "soil" (default) or PF-independent "surface"
-- wear.abrasionFactor    class exposure to sliding mineral abrasion (0..1)
-- wear.safeSpeedRatio    optional forced Vanilla-wear point as shop fraction
-- wear.minimumShopFactor optional lower class/shop plausibility threshold
-- wear.maximumShopFactor optional upper class/shop plausibility threshold
--                        (nil = global hybrid resolver defaults)
-- impacts.depthFactor    scales random impact frequency per hectare
-- impacts.stoneProtection declares a typical mechanical stone-protection
--                        system for the class (trip leg, spring/reset or
--                        shear-bolt protection)
-- impacts.mediumDamageFactor reduces MEDIUM random-impact damage only;
--                        small/big impacts remain unchanged
-- stones.*               real stone-map contact/generation/hidden-risk factors
-- dropoutProfile         selects continuous work-quality patterns
-- impactDropoutProfile   selects impact-latched mechanical work gaps
--
-- Important: draft values are intentionally NOT derived from depth. GIANTS'
-- XML maxForce already contains the implement's nominal width/depth draft.
TerraLogicImplementProfiles.PROFILES = {
    plow = {
        name = "Plow",
        work = {optimalSpeedKph = REAL_SPEED.plow, depthCm = 30, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.plow},
        yield = YIELD_QUALITY.plowGroup,
        impacts = {depthFactor = 1.50, stoneProtection = true, mediumDamageFactor = 0.70},
        stones = {mode = "Deep generator", surface = 1.00, generated = 1.00, hidden = 0.45},
        dropoutProfile = nil,
        impactDropoutProfile = nil
    },
    subsoiler = {
        name = "Subsoiler",
        work = {optimalSpeedKph = REAL_SPEED.subsoiler, depthCm = 50, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.subsoiler},
        yield = YIELD_QUALITY.plowGroup,
        impacts = {depthFactor = 2.20, stoneProtection = true, mediumDamageFactor = 0.72},
        stones = {mode = "Deep generator", surface = 1.00, generated = 1.10, hidden = 0.45},
        dropoutProfile = nil
    },
    cultivator = {
        name = "Cultivator",
        work = {optimalSpeedKph = REAL_SPEED.cultivator, depthCm = 18, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.cultivator},
        yield = YIELD_QUALITY.cultivator,
        impacts = {depthFactor = 0.90, stoneProtection = true, mediumDamageFactor = 0.75},
        stones = {mode = "Cultivator", surface = 0.80, generated = 0.75, hidden = 0.60},
        dropoutProfile = nil
    },
    shallowCultivator = {
        name = "Shallow Cultivator",
        work = {optimalSpeedKph = REAL_SPEED.shallowCultivator, depthCm = 10, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.shallowCultivator},
        yield = YIELD_QUALITY.shallowCultivator,
        impacts = {depthFactor = 0.50, stoneProtection = true, mediumDamageFactor = 0.80},
        stones = {mode = "Shallow cultivator", surface = 0.45, generated = 0.35, hidden = 0.80},
        dropoutProfile = nil
    },
    discHarrow = {
        name = "Disc Harrow",
        work = {optimalSpeedKph = REAL_SPEED.discHarrow, depthCm = 12, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.discHarrow},
        yield = YIELD_QUALITY.discHarrow,
        impacts = {depthFactor = 0.60, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Disc harrow", surface = 0.50, generated = 0.35, hidden = 0.78},
        dropoutProfile = nil
    },
    powerHarrow = {
        name = "Power Harrow",
        work = {optimalSpeedKph = REAL_SPEED.powerHarrow, depthCm = 10, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.powerHarrow},
        yield = YIELD_QUALITY.powerHarrow,
        impacts = {depthFactor = 0.50, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Power harrow", surface = 0.45, generated = 0.30, hidden = 0.80},
        dropoutProfile = nil
    },
    spader = {
        name = "Spader",
        work = {optimalSpeedKph = REAL_SPEED.spader, depthCm = 30, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.spader},
        yield = YIELD_QUALITY.cultivationGroup,
        impacts = {depthFactor = 1.50, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Spader", surface = 0.90, generated = 0.90, hidden = 0.52},
        dropoutProfile = nil
    },
    directDrill = {
        name = "Direct Drill",
        work = {optimalSpeedKph = REAL_SPEED.directDrill, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.directDrill},
        yield = YIELD_QUALITY.directDrill,
        impacts = {depthFactor = 0.30, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Direct drill", surface = 0.35, generated = 0.20, hidden = 0.85},
        dropoutProfile = "seed"
    },
    sowingMachine = {
        name = "Sowing Machine",
        work = {optimalSpeedKph = REAL_SPEED.sowingMachine, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.sowingMachine},
        yield = YIELD_QUALITY.sowingMachine,
        impacts = {depthFactor = 0.30, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Sowing machine", surface = 0.25, generated = 0.15, hidden = 0.90},
        dropoutProfile = "seed"
    },
    precisionPlanter = {
        name = "Precision Planter",
        work = {optimalSpeedKph = REAL_SPEED.precisionPlanter, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.precisionPlanter},
        yield = YIELD_QUALITY.precisionPlanter,
        impacts = {depthFactor = 0.30, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Precision planter", surface = 0.25, generated = 0.15, hidden = 0.90},
        dropoutProfile = "seed"
    },
    roller = {
        name = "Field Roller",
        work = {optimalSpeedKph = REAL_SPEED.roller, depthCm = 2, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.roller},
        yield = YIELD_QUALITY.roller,
        impacts = {depthFactor = 0.15, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Surface roller", surface = 0.25, generated = 0.00, hidden = 0.90},
        dropoutProfile = nil
    },
    mulcher = {
        name = "Mulcher",
        work = {optimalSpeedKph = REAL_SPEED.mulcher, depthCm = 3, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.mulcher},
        yield = YIELD_QUALITY.mulcher,
        impacts = {depthFactor = 0.20, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Surface mulcher", surface = 0.35, generated = 0.00, hidden = 0.85},
        dropoutProfile = "mulcherPatch"
    },
    mower = {
        name = "Mower",
        work = {optimalSpeedKph = REAL_SPEED.mower, depthCm = 0, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.mower},
        yield = YIELD_QUALITY.mower,
        -- Mowers receive continuous surface wear, but never soil/stone impacts:
        -- they cut above the soil and must remain separate from harvesters.
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "mowerPatch"
    },
    windrower = {
        name = "Windrower",
        work = {optimalSpeedKph = REAL_SPEED.windrower, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.windrower},
        yield = YIELD_QUALITY.windrower,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "windrowerPatch"
    },
    tedder = {
        name = "Tedder",
        work = {optimalSpeedKph = REAL_SPEED.tedder, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.tedder},
        yield = YIELD_QUALITY.tedder,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "tedderPatch"
    },
    baler = {
        name = "Baler",
        work = {optimalSpeedKph = REAL_SPEED.baler, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.baler},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "balerPatch"
    },
    loaderWagon = {
        name = "Loader Wagon",
        work = {optimalSpeedKph = REAL_SPEED.loaderWagon, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.loaderWagon},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "loaderWagonPatch"
    },
    stonePicker = {
        name = "Stone Picker",
        work = {optimalSpeedKph = REAL_SPEED.stonePicker, depthCm = 5, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.stonePicker},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {depthFactor = 0.30, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = {mode = "Stone picker", surface = 0.10, generated = 0.00, hidden = 0.00},
        dropoutProfile = "stonePickerPatch"
    },
    weeder = {
        name = "Mechanical Weeder",
        work = {optimalSpeedKph = REAL_SPEED.weeder, depthCm = 2, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.15},
        wear = {abrasionFactor = ABRASION.weeder},
        yield = YIELD_QUALITY.herbicideSprayer,
        impacts = {depthFactor = 0.10, stoneProtection = true, mediumDamageFactor = 0.35},
        stones = {mode = "Shallow weeder", surface = 0.20, generated = 0.00, hidden = 0.25},
        dropoutProfile = "weederPatch"
    },
    hoe = {
        name = "Mechanical Hoe",
        work = {optimalSpeedKph = REAL_SPEED.hoe, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.30},
        wear = {abrasionFactor = ABRASION.hoe},
        yield = YIELD_QUALITY.herbicideSprayer,
        impacts = {depthFactor = 0.25, stoneProtection = true, mediumDamageFactor = 0.60},
        stones = {mode = "Mechanical hoe", surface = 0.30, generated = 0.00, hidden = 0.50},
        dropoutProfile = "hoePatch"
    },

    -- Application tools are represented here as well even though they do not
    -- participate in ground-contact wear or additional MaxForce draft.
    liquidSprayer = {
        name = "Liquid Sprayer",
        work = {optimalSpeedKph = REAL_SPEED.liquidSprayer, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.liquidSprayer},
        yield = YIELD_QUALITY.liquidApplication,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "liquidSprayer"
    },
    fertilizerSpreader = {
        name = "Fertilizer Spreader",
        work = {optimalSpeedKph = REAL_SPEED.fertilizerSpreader, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.fertilizerSpreader},
        yield = YIELD_QUALITY.fertilizerSpreader,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    manureSpreader = {
        name = "Manure Spreader",
        work = {optimalSpeedKph = REAL_SPEED.manureSpreader, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.manureSpreader},
        yield = YIELD_QUALITY.manureBroadcaster,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    slurrySpreader = {
        name = "Slurry Spreader",
        work = {optimalSpeedKph = REAL_SPEED.slurryDistributor, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.slurryDistributor},
        yield = YIELD_QUALITY.manureBroadcaster,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    slurryApplicator = {
        name = "Slurry Applicator",
        work = {optimalSpeedKph = REAL_SPEED.dribbleBar, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.dribbleBar},
        yield = YIELD_QUALITY.dribbleBar,
        impacts = {depthFactor = 0.00, stoneProtection = false, mediumDamageFactor = 1.00},
        stones = nil,
        dropoutProfile = "liquidSprayer"
    }
}

-- Returns a class profile without mutating the central balance table.
function TerraLogicImplementProfiles.get(key)
    return TerraLogicImplementProfiles.PROFILES[key]
end
