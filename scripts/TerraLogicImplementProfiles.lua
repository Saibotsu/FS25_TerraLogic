--[[
    TerraLogicImplementProfiles.lua
    Central implement recognition and gameplay balance profiles.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-PROF-1.200191
]]

-- Central implement balance table. All values which vary by implement class
-- belong here so gameplay balancing never requires editing the simulation code.
TerraLogicImplementProfiles = {}
OverSpeedDamageImplementProfiles = TerraLogicImplementProfiles
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicImplementProfiles.SOURCE_FINGERPRINT = 1.200191

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
    precisionDirectDrill = 8,
    fertilizerSpreader = 15,
    liquidSprayer = 12,
    manureSpreader = 10,
    slurryDistributor = 10,
    dribbleBar = 10,
    slurryInjector = 8,
    spader = 8
}
local REAL_SPEED = TerraLogicImplementProfiles.REAL_SPEED_KPH

-- The XML/shop speed describes the upper regular working range of the exact
-- implement, including mod implements and modern high-speed designs. The
-- agronomic optimum is derived from it instead of forcing every tool in a
-- broad class onto one historic absolute speed.
TerraLogicImplementProfiles.OPTIMAL_SPEED_FACTOR = {
    plow=0.80, subsoiler=0.78, cultivator=0.85,
    shallowCultivator=0.88, discHarrow=0.88, powerHarrow=0.76,
    spader=0.76, roller=0.82,
    sowingMachine=0.86, directDrill=0.90,
    precisionPlanter=0.86, precisionDirectDrill=0.88,
    slurryInjector=0.90
}

function TerraLogicImplementProfiles.getOptimalSpeed(shopSpeed, classKey,
        implementClass)
    local shop = math.max(tonumber(shopSpeed) or 0, 0)
    if shop <= 0 then return 0, 1, "invalid shop speed" end
    local work = implementClass ~= nil and implementClass.work or nil
    local factor = work ~= nil and tonumber(work.optimalSpeedFactor)
        or TerraLogicImplementProfiles.OPTIMAL_SPEED_FACTOR[classKey]
    if factor == nil then
        local absolute = work ~= nil and tonumber(work.optimalSpeedKph) or nil
        if absolute ~= nil and absolute > 0 then
            local optimum = math.min(shop, absolute)
            return optimum, optimum / shop, "legacy absolute class speed"
        end
        return shop, 1, "shop speed"
    end
    factor = math.clamp(factor, 0.70, 0.95)
    return shop * factor, factor, "shop-derived class factor"
end

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
    precisionDirectDrill = 0.35,
    fertilizerSpreader = 0.00,
    liquidSprayer = 0.00,
    manureSpreader = 0.00,
    slurryDistributor = 0.00,
    dribbleBar = 0.02,
    slurryInjector = 0.40,
    spader = 1.00
}
local ABRASION = TerraLogicImplementProfiles.ABRASION_FACTOR

-- Additional drawbar resistance caused by TerraLogic's persistent soil state.
-- Values are maximum force shares, not horsepower percentages.  FS25 applies
-- maxForce as a linear kN cap, but traction, gear selection and the engine
-- curve can make even a small force change feel much larger at the tractor.
-- Each class therefore reacts only to the states its working elements meet.
-- The runtime subtracts the default-state stress, so an XML maxForce remains
-- the nominal baseline instead of receiving an unconditional surcharge.
TerraLogicImplementProfiles.SOIL_DRAFT_RESPONSE = {
    plow              = {surface=0.025, deep=0.045, coarse=0.010, rough=0.005},
    subsoiler         = {surface=0.005, deep=0.075},
    cultivator        = {surface=0.045, deep=0.010, coarse=0.035, rough=0.015},
    shallowCultivator = {surface=0.035, coarse=0.035, rough=0.020},
    discHarrow        = {surface=0.030, coarse=0.035, rough=0.020},
    powerHarrow       = {surface=0.020, coarse=0.045, rough=0.020},
    spader            = {surface=0.030, deep=0.030, coarse=0.025, rough=0.015},
    directDrill       = {surface=0.050, coarse=0.020, rough=0.030},
    sowingMachine     = {surface=0.030, coarse=0.035, rough=0.035},
    precisionPlanter  = {surface=0.035, coarse=0.025, rough=0.040},
    precisionDirectDrill={surface=0.045, coarse=0.022, rough=0.040},
    slurryInjector    = {surface=0.018, coarse=0.008, rough=0.010},
    -- A roller sinks and climbs more in a loose, cloddy seedbed.  This inverse
    -- surface response is intentionally separate from compacted-soil stress.
    roller            = {looseSurface=0.035, coarse=0.020, rough=0.020},
    stonePicker       = {surface=0.020, coarse=0.030, rough=0.020},
    weeder            = {surface=0.015, coarse=0.010, rough=0.015},
    hoe               = {surface=0.025, coarse=0.015, rough=0.020}
}

-- A worn edge both needs a little more force and moves the soil less
-- effectively.  Disc tools receive a smaller force rise because wear often
-- makes them run shallower; seed tools express most wear through placement
-- quality rather than a large persistent soil change.  Non-contact and
-- application tools deliberately have no entry.
TerraLogicImplementProfiles.WEAR_RESPONSE = {
    plow              = {draftMax=0.060, soilEffectLoss=0.25},
    subsoiler         = {draftMax=0.070, soilEffectLoss=0.30},
    cultivator        = {draftMax=0.050, soilEffectLoss=0.22},
    shallowCultivator = {draftMax=0.040, soilEffectLoss=0.18},
    discHarrow        = {draftMax=0.025, soilEffectLoss=0.18},
    powerHarrow       = {draftMax=0.040, soilEffectLoss=0.20},
    spader            = {draftMax=0.050, soilEffectLoss=0.25},
    directDrill       = {draftMax=0.050, soilEffectLoss=0.10},
    sowingMachine     = {draftMax=0.035, soilEffectLoss=0.06},
    precisionPlanter  = {draftMax=0.035, soilEffectLoss=0.06},
    precisionDirectDrill={draftMax=0.045, soilEffectLoss=0.08},
    slurryInjector    = {draftMax=0.025, soilEffectLoss=0.10},
    roller            = {draftMax=0.010, soilEffectLoss=0.03},
    stonePicker       = {draftMax=0.030, soilEffectLoss=0.08},
    mulcher           = {draftMax=0.000, soilEffectLoss=0.10},
    weeder            = {draftMax=0.020, soilEffectLoss=0.12},
    hoe               = {draftMax=0.030, soilEffectLoss=0.15}
}

function TerraLogicImplementProfiles.getSoilDraftResponse(key)
    return TerraLogicImplementProfiles.SOIL_DRAFT_RESPONSE[key]
end

function TerraLogicImplementProfiles.getWearResponse(key)
    return TerraLogicImplementProfiles.WEAR_RESPONSE[key]
end

-- Mechanical load is deliberately narrower than the general ground-contact
-- profile. Draft tools, including opener- and coulter-based seeders, can be
-- evaluated from the force which GIANTS/MR really applies. Hybrid tools expose
-- only their drawbar/frame share; no unknown PTO torque is invented. Every
-- omitted class is quality/wear-only.
TerraLogicImplementProfiles.LOAD_RESPONSE = {
    plow              = {model="draft", upperRatio=1.30},
    subsoiler         = {model="draft", upperRatio=1.30},
    cultivator        = {model="draft", upperRatio=1.30},
    shallowCultivator = {model="draft", upperRatio=1.30},
    discHarrow        = {model="draft", upperRatio=1.30},
    powerHarrow       = {model="hybrid", upperRatio=1.35},
    spader            = {model="hybrid", upperRatio=1.35},
    sowingMachine     = {model="draft", upperRatio=1.35},
    precisionPlanter  = {model="draft", upperRatio=1.35},
    directDrill       = {model="draft", upperRatio=1.40},
    precisionDirectDrill={model="draft", upperRatio=1.40},
    slurryInjector   = {model="draft", upperRatio=1.40}
}

-- Exact model overrides are used only where a documented upper tractor range
-- is available.  They alter the normalized upper threshold, never the force
-- produced by the game.  Pattern matching also works for DLC/mod paths.
TerraLogicImplementProfiles.LOAD_OVERRIDES = {
    {pattern="koralin", upperRatio=420 / 320,
        source="LEMKEN 294-420 hp"},
    {pattern="tiger8mt", upperRatio=600 / 440,
        source="HORSCH 375-600 hp"},
    {pattern="swifterdisc", upperRatio=650 / 580,
        source="BEDNAR 500-650 hp"},
    {pattern="kator", upperRatio=430 / 350,
        source="BEDNAR 280-430 hp"},
    {pattern="k%-extreme", upperRatio=500 / 350,
        source="ALPEGO 200-500 hp"}
}

function TerraLogicImplementProfiles.getLoadResponse(key, configFileName)
    local base = TerraLogicImplementProfiles.LOAD_RESPONSE[key]
    if base == nil then
        return {model="none", upperRatio=math.huge,
            warningRatio=math.huge, source="not a structural draft class"}
    end
    local result = {
        model = base.model,
        upperRatio = tonumber(base.upperRatio) or 1.30,
        warningRatio = tonumber(base.warningRatio) or 1.00,
        source = "class estimate"
    }
    local path = string.lower(tostring(configFileName or ""))
    for _, override in ipairs(TerraLogicImplementProfiles.LOAD_OVERRIDES) do
        if string.find(path, override.pattern) ~= nil then
            result.upperRatio = tonumber(override.upperRatio) or result.upperRatio
            -- The HUD's 100-percent mark always means nominal mechanical load.
            -- Manufacturer data changes only the structural upper limit, so
            -- every implement communicates increasing wear consistently.
            result.warningRatio = tonumber(override.warningRatio)
                or result.warningRatio
            result.source = override.source or "manufacturer range"
            break
        end
    end
    return result
end

-- Whole-yield balance of the stored gameplay categories. These are separated
-- from implement recognition: several implement classes can contribute to the
-- same category and soil preparation averages its distinct contributors.
TerraLogicImplementProfiles.WORK_QUALITY_CATEGORIES = {
    -- Legacy cap retained for save compatibility and live quality curves.
    -- Soil Work Quality itself is yield-neutral; current root-zone state owns
    -- the only direct soil-to-harvest consequence.
    soil       = {weight = 1.10, maxPenalty = 0.45},
    -- Physical seed gaps already remove plants. The remaining invisible
    -- placement/emergence correction on successfully seeded ground is capped
    -- conservatively to avoid charging establishment twice.
    seed       = {weight = 0.90, maxPenalty = 0.18},
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
-- the speed component remains at 100 percent. Above shop speed, enabled
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
        precisionDirectDrill = {soilCultivate = 0.30, seed = 0.10},

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
        slurryInjector = {fertilizer = 0.40},

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
    precisionDirectDrill = true,
    liquidSprayer = true,
    fertilizerSpreader = true,
    manureSpreader = true,
    slurrySpreader = true,
    slurryApplicator = true,
    slurryInjector = true,
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
    sowingMachine =      {weight = 0.80, maxPenalty = 0.15},
    directDrill =        {weight = 0.80, maxPenalty = 0.15},
    precisionPlanter =   {weight = 0.90, maxPenalty = 0.18},
    precisionDirectDrill={weight = 0.90, maxPenalty = 0.18},
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
-- wear.abrasionFactor    retained legacy metadata only; runtime mineral
--                        abrasion is derived from work.depthCm
-- wear.safeSpeedRatio    optional forced Vanilla-wear point as shop fraction
-- wear.minimumShopFactor optional lower class/shop plausibility threshold
-- wear.maximumShopFactor optional upper class/shop plausibility threshold
--                        (nil = global hybrid resolver defaults)
-- Hidden-impact frequency is derived only from work.depthCm: the configured
-- tier rates apply at 30 cm and scale linearly per worked hectare.
-- impacts.underground    enables depth-based hidden stone contacts
-- impacts.vanilla        enables contacts with visible Vanilla stones
-- impacts.workSpeed      lets travel speed determine impact energy
-- impacts.rotation       supplies a common rotating-part energy floor
-- Stone sensitivity classes were retired. Stone size, speed, depth and
-- rotation remain the observable impact causes for every supported tool.
-- impacts.overspeedOnly  suppresses all stone damage at/below shop speed
-- stones.*               visible stone-map contact metadata
-- dropoutProfile         selects continuous work-quality patterns
-- impactDropoutProfile   selects impact-latched mechanical work gaps
-- engagement.*           continuously reduces useful ground engagement only
--                        at deliberately extreme speed. startRatio uses the
--                        realistic class speed; failedRatio reaches the
--                        configured residual effect. draftFloor retains
--                        unavoidable drawbar/shock loading, while
--                        abrasionFloor retains intermittent physical contact.
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
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Plow", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.40, failedRatio=2.50, minimum=0.10,
            draftFloor=0.65, abrasionFloor=0.35},
        dropoutProfile = nil,
        impactDropoutProfile = nil
    },
    subsoiler = {
        name = "Subsoiler",
        work = {optimalSpeedKph = REAL_SPEED.subsoiler, depthCm = 50, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.subsoiler},
        yield = YIELD_QUALITY.plowGroup,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Subsoiler", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.45, failedRatio=2.50, minimum=0.14,
            draftFloor=0.65, abrasionFloor=0.35},
        dropoutProfile = nil
    },
    cultivator = {
        name = "Cultivator",
        work = {optimalSpeedKph = REAL_SPEED.cultivator, depthCm = 18, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.cultivator},
        yield = YIELD_QUALITY.cultivator,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Cultivator", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.50, failedRatio=2.50, minimum=0.20,
            draftFloor=0.50, abrasionFloor=0.25},
        dropoutProfile = nil
    },
    shallowCultivator = {
        name = "Shallow Cultivator",
        work = {optimalSpeedKph = REAL_SPEED.shallowCultivator, depthCm = 10, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.shallowCultivator},
        yield = YIELD_QUALITY.shallowCultivator,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Shallow cultivator", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.55, failedRatio=2.50, minimum=0.24,
            draftFloor=0.42, abrasionFloor=0.20},
        dropoutProfile = nil
    },
    discHarrow = {
        name = "Disc Harrow",
        work = {optimalSpeedKph = REAL_SPEED.discHarrow, depthCm = 12, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.discHarrow},
        yield = YIELD_QUALITY.discHarrow,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Disc harrow", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.60, failedRatio=2.50, minimum=0.25,
            draftFloor=0.35, abrasionFloor=0.15},
        dropoutProfile = nil
    },
    powerHarrow = {
        name = "Power Harrow",
        work = {optimalSpeedKph = REAL_SPEED.powerHarrow, depthCm = 10, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.powerHarrow},
        yield = YIELD_QUALITY.powerHarrow,
        impacts = {underground = true, vanilla = true, workSpeed = false, rotation = true},
        stones = {mode = "Power harrow", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.35, failedRatio=2.25, minimum=0.15,
            draftFloor=0.30, abrasionFloor=0.25},
        dropoutProfile = nil
    },
    spader = {
        name = "Spader",
        work = {optimalSpeedKph = REAL_SPEED.spader, depthCm = 30, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.spader},
        yield = YIELD_QUALITY.cultivationGroup,
        impacts = {underground = true, vanilla = true, workSpeed = false, rotation = true},
        stones = {mode = "Spader", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.35, failedRatio=2.25, minimum=0.14,
            draftFloor=0.36, abrasionFloor=0.28},
        dropoutProfile = nil
    },
    directDrill = {
        name = "Direct Drill",
        work = {optimalSpeedFactor = 0.90, depthCm = 5,
            groundContactTool = true, shopSpeedQuality = 0.98,
            seedOverspeedMinimum=0.25, seedOverspeedExponent=1.25,
            seedFailedRatio=2.00},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.directDrill},
        yield = YIELD_QUALITY.directDrill,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Direct drill", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.35, failedRatio=2.35, minimum=0.18,
            draftFloor=0.30, abrasionFloor=0.20},
        dropoutProfile = "seed"
    },
    precisionDirectDrill = {
        name = "Precision Direct Planter",
        work = {optimalSpeedFactor = 0.88, depthCm = 5,
            groundContactTool = true, shopSpeedQuality = 0.97,
            seedOverspeedMinimum=0.18, seedOverspeedExponent=1.25,
            seedFailedRatio=2.00},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.precisionDirectDrill},
        yield = YIELD_QUALITY.precisionDirectDrill,
        impacts = {underground = true, vanilla = true, workSpeed = true,
            rotation = false},
        stones = {mode = "Precision direct planter", surface = 1.00,
            generated = 0.00},
        engagement = {startRatio=1.45, failedRatio=2.30, minimum=0.15,
            draftFloor=0.30, abrasionFloor=0.19},
        dropoutProfile = "seed"
    },
    sowingMachine = {
        name = "Sowing Machine",
        work = {optimalSpeedFactor = 0.86, depthCm = 5,
            groundContactTool = true, shopSpeedQuality = 0.97,
            seedOverspeedMinimum=0.20, seedOverspeedExponent=1.25,
            seedFailedRatio=2.00},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.sowingMachine},
        yield = YIELD_QUALITY.sowingMachine,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Sowing machine", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.30, failedRatio=2.25, minimum=0.15,
            draftFloor=0.28, abrasionFloor=0.18},
        dropoutProfile = "seed"
    },
    precisionPlanter = {
        name = "Precision Planter",
        work = {optimalSpeedFactor = 0.86, depthCm = 5,
            groundContactTool = true, shopSpeedQuality = 0.96,
            seedOverspeedMinimum=0.15, seedOverspeedExponent=1.25,
            seedFailedRatio=2.00},
        draft = {enabled = true, overspeedScale = 1.00},
        wear = {abrasionFactor = ABRASION.precisionPlanter},
        yield = YIELD_QUALITY.precisionPlanter,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Precision planter", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.25, failedRatio=2.15, minimum=0.12,
            draftFloor=0.28, abrasionFloor=0.18},
        dropoutProfile = "seed"
    },
    roller = {
        name = "Field Roller",
        work = {optimalSpeedKph = REAL_SPEED.roller, depthCm = 2,
            groundContactTool = true,
            -- A field roller is a passive soil tool. GIANTS may still press
            -- stones and alter the surface while returning no successful
            -- ROLLER area when the field does not carry the post-sowing
            -- "needs rolling" state. TerraLogic therefore admits physical
            -- soil contact independently from the agronomic roller ledger.
            contactPassPolicy = "passiveSoilContact"},
        -- Soil state and wear may add a very small rolling resistance, while
        -- overspeed itself still adds no artificial drawbar force.
        draft = {enabled = true, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.roller},
        yield = YIELD_QUALITY.roller,
        impacts = {underground = false, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Surface roller", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.60, failedRatio=2.50, minimum=0.30,
            draftFloor=0.20, abrasionFloor=0.10},
        dropoutProfile = nil
    },
    mulcher = {
        name = "Mulcher",
        work = {optimalSpeedKph = REAL_SPEED.mulcher, depthCm = 3, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.mulcher},
        yield = YIELD_QUALITY.mulcher,
        -- A trapped stone still loads the rotor and housing. Device-specific
        -- protection/sensitivity classes are deliberately not inferred.
        impacts = {underground = true, vanilla = true, workSpeed = false, rotation = true},
        engagement = {startRatio=1.40, failedRatio=2.30, minimum=0.20,
            draftFloor=0.20, abrasionFloor=0.22},
        stones = {mode = "Surface mulcher", surface = 1.00, generated = 0.00},
        dropoutProfile = "mulcherPatch"
    },
    mower = {
        name = "Mower",
        work = {optimalSpeedKph = REAL_SPEED.mower, depthCm = 0, groundContactTool = true},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.mower},
        yield = YIELD_QUALITY.mower,
        impacts = {underground = false, vanilla = true, workSpeed = false, rotation = true},
        engagement = {startRatio=1.45, failedRatio=2.35, minimum=0.22,
            draftFloor=0.20, abrasionFloor=0.25},
        stones = {mode = "Mower", surface = 1.00, generated = 0.00},
        dropoutProfile = "mowerPatch"
    },
    windrower = {
        name = "Windrower",
        work = {optimalSpeedKph = REAL_SPEED.windrower, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.windrower},
        yield = YIELD_QUALITY.windrower,
        impacts = {underground = false, vanilla = true, workSpeed = true, rotation = true},
        stones = {mode = "Windrower", surface = 1.00, generated = 0.00},
        dropoutProfile = "windrowerPatch"
    },
    tedder = {
        name = "Tedder",
        work = {optimalSpeedKph = REAL_SPEED.tedder, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.tedder},
        yield = YIELD_QUALITY.tedder,
        impacts = {underground = false, vanilla = true, workSpeed = true, rotation = true},
        stones = {mode = "Tedder", surface = 1.00, generated = 0.00},
        dropoutProfile = "tedderPatch"
    },
    baler = {
        name = "Baler",
        work = {optimalSpeedKph = REAL_SPEED.baler, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.baler},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {underground = false, vanilla = true, workSpeed = true, rotation = true},
        stones = {mode = "Baler pickup", surface = 1.00, generated = 0.00},
        dropoutProfile = "balerPatch"
    },
    loaderWagon = {
        name = "Loader Wagon",
        work = {optimalSpeedKph = REAL_SPEED.loaderWagon, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {model = "surface", abrasionFactor = ABRASION.loaderWagon},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {underground = false, vanilla = true, workSpeed = true, rotation = true},
        stones = {mode = "Loader wagon pickup", surface = 1.00, generated = 0.00},
        dropoutProfile = "loaderWagonPatch"
    },
    stonePicker = {
        name = "Stone Picker",
        work = {optimalSpeedKph = REAL_SPEED.stonePicker, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.stonePicker},
        yield = {weight = 0.00, maxPenalty = 0.00},
        impacts = {underground = true, vanilla = true, workSpeed = false, rotation = true, overspeedOnly = true},
        stones = {mode = "Stone picker", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.35, failedRatio=2.25, minimum=0.18,
            draftFloor=0.25, abrasionFloor=0.22},
        dropoutProfile = "stonePickerPatch"
    },
    weeder = {
        name = "Mechanical Weeder",
        work = {optimalSpeedKph = REAL_SPEED.weeder, depthCm = 2, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.15},
        wear = {abrasionFactor = ABRASION.weeder},
        yield = YIELD_QUALITY.herbicideSprayer,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Shallow weeder", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.40, failedRatio=2.30, minimum=0.22,
            draftFloor=0.25, abrasionFloor=0.18},
        dropoutProfile = "weederPatch"
    },
    hoe = {
        name = "Mechanical Hoe",
        work = {optimalSpeedKph = REAL_SPEED.hoe, depthCm = 5, groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.30},
        wear = {abrasionFactor = ABRASION.hoe},
        yield = YIELD_QUALITY.herbicideSprayer,
        impacts = {underground = true, vanilla = true, workSpeed = true, rotation = false},
        stones = {mode = "Mechanical hoe", surface = 1.00, generated = 0.00},
        engagement = {startRatio=1.35, failedRatio=2.25, minimum=0.20,
            draftFloor=0.28, abrasionFloor=0.20},
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
        impacts = {underground = false, vanilla = false, workSpeed = false, rotation = false},
        stones = nil,
        dropoutProfile = "liquidSprayer"
    },
    fertilizerSpreader = {
        name = "Fertilizer Spreader",
        work = {optimalSpeedKph = REAL_SPEED.fertilizerSpreader, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.fertilizerSpreader},
        yield = YIELD_QUALITY.fertilizerSpreader,
        impacts = {underground = false, vanilla = false, workSpeed = false, rotation = false},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    manureSpreader = {
        name = "Manure Spreader",
        work = {optimalSpeedKph = REAL_SPEED.manureSpreader, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.manureSpreader},
        yield = YIELD_QUALITY.manureBroadcaster,
        impacts = {underground = false, vanilla = false, workSpeed = false, rotation = false},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    slurrySpreader = {
        name = "Slurry Spreader",
        work = {optimalSpeedKph = REAL_SPEED.slurryDistributor, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.slurryDistributor},
        yield = YIELD_QUALITY.manureBroadcaster,
        impacts = {underground = false, vanilla = false, workSpeed = false, rotation = false},
        stones = nil,
        dropoutProfile = "fertilizerSpreader"
    },
    slurryApplicator = {
        name = "Slurry Applicator",
        work = {optimalSpeedKph = REAL_SPEED.dribbleBar, depthCm = 0, groundContactTool = false},
        draft = {enabled = false, overspeedScale = 0.00},
        wear = {abrasionFactor = ABRASION.dribbleBar},
        yield = YIELD_QUALITY.dribbleBar,
        impacts = {underground = false, vanilla = false, workSpeed = false, rotation = false},
        stones = nil,
        dropoutProfile = "liquidSprayer"
    },
    slurryInjector = {
        name = "Slurry Disc Injector",
        work = {optimalSpeedFactor = 0.90, depthCm = 5,
            groundContactTool = true},
        draft = {enabled = true, overspeedScale = 0.35},
        wear = {abrasionFactor = ABRASION.slurryInjector},
        yield = YIELD_QUALITY.slurryInjector,
        impacts = {underground = true, vanilla = true,
            workSpeed = true, rotation = false},
        stones = {mode = "Slurry disc injector", surface = 0.35,
            generated = 0.00},
        engagement = {startRatio=1.55, failedRatio=2.50, minimum=0.28,
            draftFloor=0.30, abrasionFloor=0.16},
        dropoutProfile = "liquidSprayer"
    }
}

-- Returns a class profile without mutating the central balance table.
function TerraLogicImplementProfiles.get(key)
    return TerraLogicImplementProfiles.PROFILES[key]
end

function TerraLogicImplementProfiles.getEngagement(key)
    local profile = TerraLogicImplementProfiles.PROFILES[key]
    return profile ~= nil and profile.engagement or nil
end
