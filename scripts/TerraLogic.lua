--[[
    TerraLogic.lua
    Core vehicle specialization, work-area integration, wear and draft model.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-CORE-1.200060
]]

TerraLogic = {}
OverSpeedDamage = TerraLogic
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogic.SOURCE_FINGERPRINT = 1.200060

-- The two modules are loaded by modDesc before this specialization. Keep these
-- aliases for older debug/console code, but never define per-class values here.
TerraLogic.IMPLEMENT_CLASSES = TerraLogicImplementProfiles.PROFILES
TerraLogic.SEED_QUALITY = TerraLogicDropoutManager:getProfile("seed")
TerraLogic.APPLICATION_QUALITY = TerraLogicDropoutManager:getProfile("liquidSprayer")
TerraLogic.ROLLER_QUALITY = TerraLogicDropoutManager:getProfile("roller")

-- One central gameplay switch for every density-map/work-area dropout. New
-- implement-specific physical patterns must use this helper so the server
-- option automatically covers them as well.
local function getArePhysicalDropoutsEnabled()
    return TerraLogicSettings == nil
        or TerraLogicSettings:getPhysicalDropoutsEnabled()
end

-- Continuous speed wear uses the realistic class speed only when the XML shop
-- speed lies inside a plausible factor window. Unusually fast/slow implements
-- fall back to 80% of their own shop speed, preserving mod compatibility. The
-- shop speed gives a 1.0 speed-curve value and the protected realistic speed
-- gives 0.5. A cubic Hermite bridge keeps value and slope continuous. Above
-- shop speed, soil tools retain the old realistic-speed cubic excess shifted
-- down to the neutral shop point. Surface-wear tools use an exact speed-ratio
-- cube, which becomes a squared wear increase per hectare.
TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT = 0.80
TerraLogic.WEAR_CLASS_SHOP_FACTOR_MIN = 1.05
TerraLogic.WEAR_CLASS_SHOP_FACTOR_MAX = 1.40
TerraLogic.WEAR_AT_SHOP_SPEED = 1.00
TerraLogic.WEAR_AT_REAL_SPEED = 0.50
TerraLogic.WEAR_MINIMUM = 0.20
TerraLogic.WEAR_BELOW_SAFE_EXPONENT = 1.50
TerraLogic.WEAR_ABOVE_SHOP_EXPONENT = 3.00
TerraLogic.WEAR_MAX = 24.00
TerraLogic.WEAR_REFERENCE_DURATION_MINUTES = 480.00
-- Vanilla reaches its complete operating-hour ageing contribution after only
-- about 50 hours on the common 600-period lifetime. Stretch that ramp so an
-- existing long-running save does not suddenly receive almost maximum damage.
-- The maximum remains Vanilla's x5 combined age/usage factor; only its onset
-- is made more realistic and this constant is ready for a future options UI.
TerraLogic.AGE_USAGE_MINIMUM_FULL_HOURS = 100.00
TerraLogic.WEAR_ABRASIVE_SHARE = 0.60
TerraLogic.WEAR_CUSTOM_RATE_WARNING_MIN = 0.25
TerraLogic.WEAR_CUSTOM_RATE_WARNING_MAX = 4.00

-- One shared overspeed curve for every soil-engaging implement. Base maxForce
-- already represents width, depth and nominal draft; applying another
-- depth-shaped curve here would count those properties twice. Individual
-- profiles only enable/disable this curve and may scale its excess term.
TerraLogic.DRAFT_SPEED_STRENGTH_FALLBACK = 0.35
TerraLogic.DRAFT_SPEED_EXPONENT_FALLBACK = 1.00
TerraLogic.DRAFT_MAX_FALLBACK = 1.50

-- Random impacts are area-based and split into three independently tunable
-- severity tiers. At/below XML rated speed every tier only uses its small
-- touch component. Excess kinetic energy (speedRatio^2 - 1) becomes the
-- dominant damage source above rated speed. This stays independent of FPS.
TerraLogic.IMPACT_SPIKES_ENABLED = true
TerraLogic.IMPACT_RANDOM_MIN_FACTOR = 0.60
TerraLogic.IMPACT_RANDOM_MEAN_FACTOR =
    (1 + TerraLogic.IMPACT_RANDOM_MIN_FACTOR) * 0.5
-- Compress small excess-energy impacts while making the curve increasingly
-- steep at extreme overspeed. At 12/14/15/20 km/h this turns raw excess
-- energy into approximately 0/0.054/0.105/0.593 instead of
-- 0/0.361/0.563/1.778. Touch damage at and below shop speed is unchanged.
TerraLogic.IMPACT_EXCESS_ENERGY_SCALE = 0.25
TerraLogic.IMPACT_EXCESS_ENERGY_EXPONENT = 1.50
TerraLogic.IMPACT_TIERS = {
    -- 100 micro contacts/ha create gradual soil-particle wear. Medium and
    -- big streams are independent and deliberately much rarer.
    small =   {eventsPerHa = 100.00, touchDamage = 0.00001, excessDamage = 0.0005, maxDamage = 0.010},
    medium =  {eventsPerHa =   6.00, touchDamage = 0.00050, excessDamage = 0.0250, maxDamage = 0.200},
    big =     {eventsPerHa =   0.45, touchDamage = 0.00300, excessDamage = 0.5000, maxDamage = 0.850}
}
TerraLogic.IMPACT_BASE_EVENTS_PER_HA = 0
for _, tier in pairs(TerraLogic.IMPACT_TIERS) do
    TerraLogic.IMPACT_BASE_EVENTS_PER_HA =
        TerraLogic.IMPACT_BASE_EVENTS_PER_HA + tier.eventsPerHa
end
for _, tier in pairs(TerraLogic.IMPACT_TIERS) do
    tier.probability = tier.eventsPerHa / TerraLogic.IMPACT_BASE_EVENTS_PER_HA
end

-- Vanilla stone-map interaction. All rates are damage fractions per weighted
-- stone hectare (stone-map area multiplied by stone level 1..3). Detection is
-- tied to each real WorkArea processing call, not the render loop. This is
-- intentionally unthrottled so no generated strip is missed; only the debug
-- aggregation is limited to one update per second.
TerraLogic.STONE_INTERACTION_ENABLED = true
TerraLogic.STONE_SCAN_INTERVAL_MS = 0
TerraLogic.STONE_SURFACE_DAMAGE_PER_WEIGHTED_HA = 0.0125
TerraLogic.STONE_GENERATED_DAMAGE_PER_WEIGHTED_HA = 0.0350
TerraLogic.STONE_DAMAGE_MAX_PER_SCAN = 0.05

-- These specializations already multiply their normal work wear from the
-- visible Vanilla stone state. TerraLogic must never add its own surface damage on
-- top. The extended setting only fills the gaps for ground tools Vanilla did
-- not cover. The abstract impact model for hidden stones remains separate.
TerraLogic.VANILLA_VISIBLE_STONE_CLASSES = {
    sowingMachine = true,
    directDrill = true,
    precisionPlanter = true,
    weeder = true,
    mulcher = true,
    mower = true,
    hoe = true
}

-- Explicit runtime audit of classes whose real processing path writes work
-- quality. A profile row alone must never unlock working speed: documented
-- future classes and zero-yield utilities may not have the matching hook yet.
-- Surface forage tools are deliberately absent and use their physical-dropout
-- gate in getSpeedLimit, so disabling that option restores their shop limit.
TerraLogic.SPEED_UNLOCK_CONSEQUENCE_CLASSES = {
    plow = true,
    subsoiler = true,
    cultivator = true,
    shallowCultivator = true,
    discHarrow = true,
    powerHarrow = true,
    spader = true,
    directDrill = true,
    sowingMachine = true,
    precisionPlanter = true,
    roller = true,
    mulcher = true,
    weeder = true,
    hoe = true,
    liquidSprayer = true,
    fertilizerSpreader = true,
    manureSpreader = true,
    slurrySpreader = true,
    slurryApplicator = true
}

-- When Vanilla stones are active, actual stone-map contacts replace part of
-- the abstract hidden-impact risk. If stones are disabled/unavailable the old
-- random-impact frequency remains at 100 percent as a complete fallback.
TerraLogic.STONE_TOOL_PROFILES = {}
for profileKey, implementProfile in pairs(TerraLogic.IMPLEMENT_CLASSES) do
    if implementProfile.stones ~= nil then
        TerraLogic.STONE_TOOL_PROFILES[profileKey] = implementProfile.stones
    end
end

-- Worn ground tools require progressively more draft. The curve begins
-- gently, steepens towards heavy wear and reaches its default x1.30 cap at
-- 75 percent damage. Further damage does not increase this penalty.
TerraLogic.DAMAGE_MAX_FORCE_INCREASE = 0.30
TerraLogic.DAMAGE_RESISTANCE_FULL_AT = 0.75
TerraLogic.DAMAGE_RESISTANCE_EXPONENT = 1.60
TerraLogic.SOIL_UPDATE_INTERVAL_MS = 1000
TerraLogic.TELEMETRY_INTERVAL_MS = 1000

TerraLogic.SOIL_DATA = {
    [1] = {name = "Loamy Sand", resistance = 0.925, abrasion = 1.30, impactFrequency = 0.60, impactSeverity = 0.85},
    [2] = {name = "Sandy Loam", resistance = 1.00, abrasion = 1.15, impactFrequency = 0.80, impactSeverity = 1.00},
    [3] = {name = "Loam", resistance = 1.10, abrasion = 1.00, impactFrequency = 1.00, impactSeverity = 1.20},
    [4] = {name = "Silty Clay", resistance = 1.225, abrasion = 0.95, impactFrequency = 1.30, impactSeverity = 1.45}
}

-- Core balance and wear calculations ---------------------------------------

-- Reads a temporary developer multiplier without changing profile defaults.
local function getRuntimeBalanceMultiplier(name)
    if TerraLogicMain ~= nil and TerraLogicMain.getBalanceMultiplier ~= nil then
        return TerraLogicMain:getBalanceMultiplier(name)
    end
    return 1
end

function TerraLogic:getDamageResistanceMultiplier(damage)
    local fullAt = math.max(TerraLogic.DAMAGE_RESISTANCE_FULL_AT, 0.01)
    local progression = math.clamp((tonumber(damage) or 0) / fullAt, 0, 1)
    local curvedIncrease = TerraLogic.DAMAGE_MAX_FORCE_INCREASE
        * progression ^ TerraLogic.DAMAGE_RESISTANCE_EXPONENT
    return 1 + curvedIncrease * getRuntimeBalanceMultiplier("damageResistance")
end

-- Resolves a protected realistic speed for unusually configured mod implements.
function TerraLogic.resolveWearSafeSpeed(ratedSpeed, implementClass)
    local rated = tonumber(ratedSpeed) or 0
    if rated <= 0 then
        return 0, TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT,
            "shop fallback (invalid rated speed)", nil, true
    end

    local work = implementClass ~= nil and implementClass.work or nil
    local wear = implementClass ~= nil and implementClass.wear or nil
    local classRealSpeed = work ~= nil and tonumber(work.optimalSpeedKph) or nil
    local profileRatio = wear ~= nil and tonumber(wear.safeSpeedRatio) or nil
    if profileRatio ~= nil and profileRatio > 0 then
        local ratio = math.clamp(profileRatio, 0.10, 0.99)
        return rated * ratio, ratio, "profile ratio override", nil, false
    end

    local minimumFactor = wear ~= nil
        and tonumber(wear.minimumShopFactor)
        or TerraLogic.WEAR_CLASS_SHOP_FACTOR_MIN
    local maximumFactor = wear ~= nil
        and tonumber(wear.maximumShopFactor)
        or TerraLogic.WEAR_CLASS_SHOP_FACTOR_MAX
    local shopToClassFactor = classRealSpeed ~= nil and classRealSpeed > 0
        and rated / classRealSpeed or nil
    if classRealSpeed ~= nil and classRealSpeed > 0
        and rated < classRealSpeed then
        local safeSpeed = TerraLogicImplementProfiles
            .getLowShopSafeSpeed(rated)
        return safeSpeed, safeSpeed / rated,
            "adaptive low-shop safe speed", shopToClassFactor, true
    end
    if shopToClassFactor ~= nil
        and shopToClassFactor >= minimumFactor
        and shopToClassFactor <= maximumFactor then
        return classRealSpeed, classRealSpeed / rated,
            "class realistic speed", shopToClassFactor, false
    end

    local fallbackRatio = TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT
    return rated * fallbackRatio, fallbackRatio,
        "80% shop fallback", shopToClassFactor, true
end

local function getScaledImpactExcessEnergy(excessImpactEnergy)
    return TerraLogic.IMPACT_EXCESS_ENERGY_SCALE
        * math.max(tonumber(excessImpactEnergy) or 0, 0)
            ^ TerraLogic.IMPACT_EXCESS_ENERGY_EXPONENT
end

local function getImpactTierMaximumDamage(tier, impactEnergy, excessImpactEnergy, severityFactor)
    local touchScale = math.clamp(tonumber(impactEnergy) or 0, 0, 1)
    local scaledExcessEnergy = getScaledImpactExcessEnergy(excessImpactEnergy)
    local damage = (tier.touchDamage * touchScale
        + tier.excessDamage * scaledExcessEnergy)
        * (tonumber(severityFactor) or 1)
        * getRuntimeBalanceMultiplier("randomDamage")
    return math.min(math.max(damage, 0), tier.maxDamage)
end

local function getEffectiveAbrasionMultiplier(spec)
    if spec.wearModel == "surface" then
        -- Bearings, rotating parts and surface contact retain the unchanged
        -- Vanilla/XML damage as their neutral base; PF mineral soil does not
        -- amplify or reduce this wear model.
        return 1, 1
    end
    local soilFactor = math.max(tonumber(spec.abrasionMultiplier) or 1, 0)
    local implementFactor = math.clamp(
        tonumber(spec.implementAbrasionFactor) or 0,
        0,
        1
    )
    local abrasiveLoad = implementFactor * soilFactor
    local baselineMultiplier = math.max(
        1 + TerraLogic.WEAR_ABRASIVE_SHARE * (abrasiveLoad - 1),
        0
    )
    return baselineMultiplier, abrasiveLoad
end

local function getReferenceWearRate()
    local wearFactor = Wearable ~= nil
        and tonumber(Wearable.WEAR_FACTOR) or 1
    return wearFactor
        / (TerraLogic.WEAR_REFERENCE_DURATION_MINUTES * 60 * 1000)
end

local function getWearPolicy()
    local policy = TerraLogicMain ~= nil
        and tostring(TerraLogicMain.wearPolicy or "normalize")
        or "normalize"
    if policy ~= "respect" and policy ~= "forceVanilla" then
        return "normalize"
    end
    return policy
end

local function getVanillaAgeUsageFactor(vehicle)
    local lifetime = tonumber(vehicle.lifetime) or 0
    if lifetime == 0 then
        return 1
    end
    local age = tonumber(vehicle.age) or 0
    local operatingHours = (tonumber(vehicle.operatingTime) or 0) / 3600000
    local lifetimeOperatingRatio = EconomyManager ~= nil
        and tonumber(EconomyManager.LIFETIME_OPERATINGTIME_RATIO) or 0.08333
    local maximumMultiplier = EconomyManager ~= nil
        and tonumber(EconomyManager.MAX_DAILYUPKEEP_MULTIPLIER) or 4
    local ageMultiplier = 0.15 * math.min(age / lifetime, 1)
    local operatingTimeMultiplier = 0.85 * math.min(
        operatingHours / math.max(lifetime * lifetimeOperatingRatio, 0.0001),
        1
    )
    return 1 + maximumMultiplier * (ageMultiplier + operatingTimeMultiplier)
end

function TerraLogic.getAdjustedAgeUsageFullHours(vehicle)
    local lifetime = tonumber(vehicle ~= nil and vehicle.lifetime) or 0
    local lifetimeOperatingRatio = EconomyManager ~= nil
        and tonumber(EconomyManager.LIFETIME_OPERATINGTIME_RATIO) or 0.08333
    return math.max(
        lifetime * lifetimeOperatingRatio,
        TerraLogic.AGE_USAGE_MINIMUM_FULL_HOURS
    )
end

function TerraLogic.getAdjustedAgeUsageFactor(vehicle)
    local lifetime = tonumber(vehicle ~= nil and vehicle.lifetime) or 0
    if lifetime == 0 then return 1 end
    local age = tonumber(vehicle.age) or 0
    local operatingHours = (tonumber(vehicle.operatingTime) or 0) / 3600000
    local fullHours = TerraLogic.getAdjustedAgeUsageFullHours(vehicle)
    local maximumMultiplier = EconomyManager ~= nil
        and tonumber(EconomyManager.MAX_DAILYUPKEEP_MULTIPLIER) or 4
    local ageMultiplier = 0.15 * math.min(age / lifetime, 1)
    local operatingTimeMultiplier = 0.85 * math.min(
        operatingHours / math.max(fullHours, 0.0001), 1)
    return 1 + maximumMultiplier
        * (ageMultiplier + operatingTimeMultiplier)
end

-- Specialization registration ---------------------------------------------

-- Limits TerraLogic to supported wearable implements and forage surface tools.
function TerraLogic.prerequisitesPresent(specializations)
    local wearable = SpecializationUtil.hasSpecialization(Wearable, specializations)
    local attachable = SpecializationUtil.hasSpecialization(Attachable, specializations)
    local mower = Mower ~= nil
        and SpecializationUtil.hasSpecialization(Mower, specializations)
    local windrower = Windrower ~= nil
        and SpecializationUtil.hasSpecialization(Windrower, specializations)
    local tedder = Tedder ~= nil
        and SpecializationUtil.hasSpecialization(Tedder, specializations)
    local baler = Baler ~= nil
        and SpecializationUtil.hasSpecialization(Baler, specializations)
    local forageWagon = ForageWagon ~= nil
        and SpecializationUtil.hasSpecialization(ForageWagon, specializations)
    local function has(specialization)
        return specialization ~= nil
            and SpecializationUtil.hasSpecialization(
                specialization, specializations)
    end
    local supportedAttachedTool = has(Plow) or has(Cultivator)
        or has(SowingMachine) or has(Sprayer) or has(Roller)
        or has(Mulcher) or has(Weeder) or has(StonePicker)
        or mower or windrower or tedder or baler or forageWagon
    return wearable
        and ((attachable and supportedAttachedTool)
            or mower or windrower or tedder or baler or forageWagon)
end

function TerraLogic.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", TerraLogic)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", TerraLogic)
    if WorkArea ~= nil
        and SpecializationUtil.hasSpecialization(
            WorkArea, vehicleType.specializations
        ) then
        SpecializationUtil.registerEventListener(
            vehicleType, "onStartWorkAreaProcessing", TerraLogic
        )
        SpecializationUtil.registerEventListener(
            vehicleType, "onEndWorkAreaProcessing", TerraLogic
        )
    end
end

function TerraLogic.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getDamageResistanceMultiplier", TerraLogic.getDamageResistanceMultiplier)
    SpecializationUtil.registerFunction(vehicleType, "getWorkingSpeedRatio", TerraLogic.getWorkingSpeedRatio)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedGroundToolType", TerraLogic.getOverSpeedGroundToolType)
    SpecializationUtil.registerFunction(vehicleType, "updateOverSpeedImplementClass", TerraLogic.updateOverSpeedImplementClass)
    SpecializationUtil.registerFunction(vehicleType, "getIsOverSpeedWorkAreaProcessing", TerraLogic.getIsOverSpeedWorkAreaProcessing)
    SpecializationUtil.registerFunction(vehicleType, "getIsOverSpeedGroundContactActive", TerraLogic.getIsOverSpeedGroundContactActive)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedWorkingWidth", TerraLogic.getOverSpeedWorkingWidth)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedDebugData", TerraLogic.getOverSpeedDebugData)
    SpecializationUtil.registerFunction(vehicleType, "updateOverSpeedSoilData", TerraLogic.updateOverSpeedSoilData)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedSoilSamplePosition", TerraLogic.getOverSpeedSoilSamplePosition)
    SpecializationUtil.registerFunction(vehicleType, "getRawPrecisionFarmingSoilType", TerraLogic.getRawPrecisionFarmingSoilType)
    SpecializationUtil.registerFunction(vehicleType, "updateOverSpeedResistance", TerraLogic.updateOverSpeedResistance)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedBalanceFactors", TerraLogic.getOverSpeedBalanceFactors)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedWearMultiplier", TerraLogic.getOverSpeedWearMultiplier)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedDraftMultiplier", TerraLogic.getOverSpeedDraftMultiplier)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedImpactRisk", TerraLogic.getOverSpeedImpactRisk)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedStoneToolProfile", TerraLogic.getOverSpeedStoneToolProfile)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedStoneMapContext", TerraLogic.getOverSpeedStoneMapContext)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedStoneAreaState", TerraLogic.getOverSpeedStoneAreaState)
    SpecializationUtil.registerFunction(vehicleType, "processOverSpeedStoneArea", TerraLogic.processOverSpeedStoneArea)
    SpecializationUtil.registerFunction(vehicleType, "processImpactDropoutArea", TerraLogic.processImpactDropoutArea)
    SpecializationUtil.registerFunction(vehicleType, "processSurfacePatchDropoutArea", TerraLogic.processSurfacePatchDropoutArea)
    SpecializationUtil.registerFunction(vehicleType, "updateOverSpeedPlowEffects", TerraLogic.updateOverSpeedPlowEffects)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedSeedQuality", TerraLogic.getOverSpeedSeedQuality)
    SpecializationUtil.registerFunction(vehicleType, "prepareOverSpeedSeedQualityArea", TerraLogic.prepareOverSpeedSeedQualityArea)
    SpecializationUtil.registerFunction(vehicleType, "applyOverSpeedSeedQualityArea", TerraLogic.applyOverSpeedSeedQualityArea)
    SpecializationUtil.registerFunction(vehicleType, "applyOverSpeedRollerQualityArea", TerraLogic.applyOverSpeedRollerQualityArea)
    SpecializationUtil.registerFunction(vehicleType, "getOverSpeedApplicationQuality", TerraLogic.getOverSpeedApplicationQuality)
    SpecializationUtil.registerFunction(vehicleType, "getIsOverSpeedApplicationActive", TerraLogic.getIsOverSpeedApplicationActive)
    SpecializationUtil.registerFunction(vehicleType, "refreshOverSpeedWorkAreaProcessingFunctions", TerraLogic.refreshOverSpeedWorkAreaProcessingFunctions)
end

function TerraLogic:getOverSpeedWearMultiplier(currentSpeed)
    local spec = self.spec_terraLogic
    local speed = math.max(tonumber(currentSpeed) or 0, 0)
    local rated = tonumber(spec.ratedSpeed) or 0
    local realistic = tonumber(spec.safeSpeed) or tonumber(spec.optimalSpeed) or rated

    if rated <= 0 or realistic <= 0 then
        return 1
    end
    realistic = math.clamp(realistic, rated * 0.1, rated)
    local realRatio = realistic / rated
    local shopRatio = speed / rated

    if speed <= realistic then
        local t = math.clamp(speed / realistic, 0, 1)
        return TerraLogic.WEAR_MINIMUM
            + (TerraLogic.WEAR_AT_REAL_SPEED
                - TerraLogic.WEAR_MINIMUM)
                * t ^ TerraLogic.WEAR_BELOW_SAFE_EXPONENT
    end

    -- Retaining the former (shop/real)^3 excess strength gives a typical
    -- 12/15 km/h implement x3.68 at 20 km/h, while x0.5 and x1 remain exact.
    local cubicStrength = spec.wearModel == "surface" and 1
        or (rated / realistic) ^ TerraLogic.WEAR_ABOVE_SHOP_EXPONENT
    local shopSlope = cubicStrength
        * TerraLogic.WEAR_ABOVE_SHOP_EXPONENT
    if speed <= rated then
        local span = math.max(1 - realRatio, 0.0001)
        local t = math.clamp((shopRatio - realRatio) / span, 0, 1)
        local t2, t3 = t * t, t * t * t
        local realSlope = (TerraLogic.WEAR_AT_REAL_SPEED
            - TerraLogic.WEAR_MINIMUM)
            * TerraLogic.WEAR_BELOW_SAFE_EXPONENT / realRatio
        return (2 * t3 - 3 * t2 + 1)
                * TerraLogic.WEAR_AT_REAL_SPEED
            + (t3 - 2 * t2 + t) * span * realSlope
            + (-2 * t3 + 3 * t2) * TerraLogic.WEAR_AT_SHOP_SPEED
            + (t3 - t2) * span * shopSlope
    end

    return math.min(
        TerraLogic.WEAR_AT_SHOP_SPEED
            + cubicStrength * (shopRatio
                ^ TerraLogic.WEAR_ABOVE_SHOP_EXPONENT - 1),
        TerraLogic.WEAR_MAX
    )
end

function TerraLogic:getOverSpeedBalanceFactors(speedRatio)
    local ratio = math.max(tonumber(speedRatio) or 0, 0)
    local spec = self.spec_terraLogic
    local recommended = tonumber(spec.optimalSpeed) or 0
    local speed = ratio * recommended

    return self:getOverSpeedDraftMultiplier(speed),
        self:getOverSpeedWearMultiplier(speed)
end

function TerraLogic:getOverSpeedDraftMultiplier(currentSpeed)
    local spec = self.spec_terraLogic
    if spec.additionalDraftEnabled ~= true then
        return 1
    end
    local speed = math.max(tonumber(currentSpeed) or 0, 0)
    local recommended = tonumber(spec.optimalSpeed) or 0
    local rated = tonumber(spec.ratedSpeed) or recommended

    local rawDraft = 1
    if rated > 0 and speed > rated then
        local speedRatio = speed / rated
        local strength = TerraLogic.DRAFT_SPEED_STRENGTH_FALLBACK
            * math.max(tonumber(spec.additionalDraftScale) or 1, 0)
        local exponent = TerraLogic.DRAFT_SPEED_EXPONENT_FALLBACK
        local maximum = TerraLogic.DRAFT_MAX_FALLBACK
        rawDraft = math.min(
            1 + strength * (speedRatio ^ exponent - 1),
            maximum
        )
    end

    local draftScale = getRuntimeBalanceMultiplier("draft")
    if TerraLogicMain ~= nil and TerraLogicMain.draftEnabled == false then
        draftScale = 0
    end
    return 1 + (rawDraft - 1) * draftScale
end

function TerraLogic:getOverSpeedImpactRisk(currentSpeed)
    local spec = self.spec_terraLogic
    local rated = tonumber(spec.ratedSpeed) or 0
    local speed = tonumber(currentSpeed) or 0
    if not TerraLogic.IMPACT_SPIKES_ENABLED
        or (TerraLogicMain ~= nil and TerraLogicMain.randomImpactsEnabled == false)
        or rated <= 0 then
        return 0, 0, 0, 0, 0, 0, 0
    end

    local speedRatio = speed / rated
    local impactEnergy = speedRatio * speedRatio
    local excessImpactEnergy = math.max(impactEnergy - 1, 0)
    local scaledExcessImpactEnergy =
        getScaledImpactExcessEnergy(excessImpactEnergy)
    local frequencyFactor = tonumber(spec.impactFrequencyFactor) or 1
    local severityFactor = tonumber(spec.impactSeverityFactor) or 1
    local depthFactor = tonumber(spec.impactDepthFactor) or 1
    local hiddenImpactFactor = tonumber(spec.hiddenImpactFactor) or 1
    local eventsPerHa = TerraLogic.IMPACT_BASE_EVENTS_PER_HA
        * frequencyFactor * depthFactor * hiddenImpactFactor
        * getRuntimeBalanceMultiplier("randomFrequency")
    local smallDamage = getImpactTierMaximumDamage(
        TerraLogic.IMPACT_TIERS.small, impactEnergy, excessImpactEnergy, severityFactor)
    local mediumDamage = getImpactTierMaximumDamage(
        TerraLogic.IMPACT_TIERS.medium, impactEnergy, excessImpactEnergy, severityFactor)
    local mediumDamageFactor = math.clamp(
        tonumber(spec.impactMediumDamageFactor) or 1,
        0,
        1
    )
    mediumDamage = math.max(
        mediumDamage * mediumDamageFactor,
        smallDamage * 1.35
    )
    local bigDamage = getImpactTierMaximumDamage(
        TerraLogic.IMPACT_TIERS.big, impactEnergy, excessImpactEnergy, severityFactor)
    return eventsPerHa, impactEnergy, excessImpactEnergy,
        scaledExcessImpactEnergy,
        smallDamage, mediumDamage, bigDamage
end

function TerraLogic.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", TerraLogic.getSpeedLimit)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", TerraLogic.updateDamageAmount)
    if Plow ~= nil and SpecializationUtil.hasSpecialization(Plow, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processPlowArea", TerraLogic.processPlowArea)
    end
    if Cultivator ~= nil and SpecializationUtil.hasSpecialization(Cultivator, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processCultivatorArea", TerraLogic.processCultivatorArea)
    end
    if SowingMachine ~= nil and SpecializationUtil.hasSpecialization(SowingMachine, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processSowingMachineArea", TerraLogic.processSowingMachineArea)
    end
    if Sprayer ~= nil and SpecializationUtil.hasSpecialization(Sprayer, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processSprayerArea", TerraLogic.processSprayerArea)
    end
    if Roller ~= nil and SpecializationUtil.hasSpecialization(Roller, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processRollerArea", TerraLogic.processRollerArea)
    end
    if Mulcher ~= nil and SpecializationUtil.hasSpecialization(Mulcher, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processMulcherArea", TerraLogic.processMulcherArea)
    end
    if Weeder ~= nil and SpecializationUtil.hasSpecialization(Weeder, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processWeederArea", TerraLogic.processWeederArea)
    end
    if StonePicker ~= nil and SpecializationUtil.hasSpecialization(StonePicker, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processStonePickerArea", TerraLogic.processStonePickerArea)
    end
    if Mower ~= nil and SpecializationUtil.hasSpecialization(Mower, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processMowerArea", TerraLogic.processMowerArea)
    end
    if Windrower ~= nil and SpecializationUtil.hasSpecialization(Windrower, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processWindrowerArea", TerraLogic.processWindrowerArea)
    end
    if Tedder ~= nil and SpecializationUtil.hasSpecialization(Tedder, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processTedderArea", TerraLogic.processTedderArea)
    end
    if Baler ~= nil and SpecializationUtil.hasSpecialization(Baler, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processBalerArea", TerraLogic.processBalerArea)
    end
    if ForageWagon ~= nil and SpecializationUtil.hasSpecialization(ForageWagon, vehicleType.specializations) then
        SpecializationUtil.registerOverwrittenFunction(vehicleType, "processForageWagonArea", TerraLogic.processForageWagonArea)
    end
end

-- Initializes per-vehicle runtime state without writing savegame data.
function TerraLogic:onLoad(savegame)
    local ratedSpeed = tonumber(self.speedLimit)

    local implementClassKey, implementClass = self:getOverSpeedGroundToolType()
    local optimalSpeed = ratedSpeed
    local classOptimalSpeed = implementClass ~= nil and implementClass.work ~= nil
        and tonumber(implementClass.work.optimalSpeedKph) or nil
    if classOptimalSpeed ~= nil and ratedSpeed ~= nil then
        optimalSpeed = math.min(ratedSpeed, classOptimalSpeed)
    end
    local safeSpeed, safeSpeedRatio, safeSpeedSource,
        shopToClassSpeedFactor, safeSpeedFallback =
        TerraLogic.resolveWearSafeSpeed(ratedSpeed, implementClass)

    self.spec_terraLogic = {
        ratedSpeed = ratedSpeed ~= nil and ratedSpeed > 0 and ratedSpeed < math.huge and ratedSpeed or nil,
        optimalSpeed = optimalSpeed ~= nil and optimalSpeed > 0 and optimalSpeed < math.huge and optimalSpeed or nil,
        implementClassKey = implementClassKey,
        storeCategory = "unknown",
        storeCategoryResolved = false,
        workDepthCm = implementClass ~= nil and implementClass.work ~= nil
            and implementClass.work.depthCm or 0,
        impactDepthFactor = implementClass ~= nil and implementClass.impacts ~= nil
            and implementClass.impacts.depthFactor or 1,
        impactStoneProtection = implementClass ~= nil
            and implementClass.impacts ~= nil
            and implementClass.impacts.stoneProtection == true,
        impactMediumDamageFactor = implementClass ~= nil
            and implementClass.impacts ~= nil
            and implementClass.impacts.stoneProtection == true
            and implementClass.impacts.mediumDamageFactor or 1,
        additionalDraftEnabled = implementClass ~= nil and implementClass.draft ~= nil
            and implementClass.draft.enabled == true,
        additionalDraftScale = implementClass ~= nil and implementClass.draft ~= nil
            and implementClass.draft.overspeedScale or 0,
        implementAbrasionFactor = implementClass ~= nil and implementClass.wear ~= nil
            and implementClass.wear.abrasionFactor or 0,
        wearModel = implementClass ~= nil and implementClass.wear ~= nil
            and implementClass.wear.model or "soil",
        yieldWeight = implementClass ~= nil and implementClass.yield ~= nil
            and implementClass.yield.weight or 0,
        maxYieldPenalty = implementClass ~= nil and implementClass.yield ~= nil
            and implementClass.yield.maxPenalty or 0,
        safeSpeed = safeSpeed,
        safeSpeedRatio = safeSpeedRatio,
        safeSpeedSource = safeSpeedSource,
        shopToClassSpeedFactor = shopToClassSpeedFactor,
        safeSpeedFallback = safeSpeedFallback,
        isMowerTool = self.spec_mower ~= nil,
        isSurfaceForageTool = self.spec_mower ~= nil
            or self.spec_windrower ~= nil or self.spec_tedder ~= nil
            or self.spec_baler ~= nil or self.spec_forageWagon ~= nil,
        dropoutProfile = implementClass ~= nil and implementClass.dropoutProfile or nil,
        impactDropoutProfile = implementClass ~= nil
            and implementClass.impactDropoutProfile or nil,
        actualWorkDirtyFlag = self:getNextDirtyFlag(),
        actualWorkActive = false,
        lastActualWorkTime = nil,
        lastActualWorkProfile = nil,
        qualityWorkActive = false,
        lastQualityWorkTime = nil,
        soilUpdateTimer = 0,
        soilTypeIndex = 0,
        soilName = "Vanilla / unknown",
        pfActive = false,
        pfMode = "auto",
        pfSource = "not checked",
        resistanceMultiplier = 1,
        abrasionMultiplier = 1,
        impactFrequencyFactor = 1,
        impactSeverityFactor = 1,
        impactSoilSource = "Neutral fallback",
        resistanceSource = "Vanilla",
        abrasionSource = "Vanilla",
        baseMaxForce = nil,
        lastAppliedMaxForce = nil,
        telemetryElapsedMs = 0,
        telemetryDistanceM = 0,
        telemetryVanillaDamage = 0,
        telemetryCurrentDamage = 0,
        telemetryContinuousDamage = 0,
        telemetryActiveMs = 0,
        telemetrySpeedMultiplierTime = 0,
        telemetryTotalMultiplierTime = 0,
        telemetryDraftMultiplierTime = 0,
        damageRatePerMs = 0,
        vanillaDamagePerHectare = nil,
        currentDamagePerHectare = nil,
        continuousDamagePerHectare = nil,
        speedDamageMultiplier = 1,
        totalDamageMultiplier = 1,
        speedDraftMultiplier = 1,
        impactRiskEventsPerHa = 0,
        impactRiskEventsPerKm = 0,
        impactEnergy = 0,
        excessImpactEnergy = 0,
        scaledExcessImpactEnergy = 0,
        expectedRandomImpactDamagePerHectare = 0,
        randomImpactDamagePerHectareLastSecond = nil,
        stoneDamagePerHectareLastSecond = nil,
        impactCount = 0,
        impactSmallCount = 0,
        impactMediumCount = 0,
        impactBigCount = 0,
        lastImpactTier = "none",
        lastImpactDamage = nil,
        lastImpactGameTime = nil,
        randomImpactDamageWindow = 0,
        wearRateWarningLogged = false,
        randomImpactDamageLastSecond = 0,
        stoneSystemActive = false,
        stoneSystemStatus = "not checked",
        stoneToolMode = "Not supported",
        stoneSurfaceFactor = 0,
        stoneGenerationFactor = 0,
        hiddenImpactFactor = 1,
        stoneModifier = nil,
        stoneFilter = nil,
        stoneMapId = nil,
        stoneWorkAreaScanTimes = {},
        stoneScanCountWindow = 0,
        stoneSurfaceDamageWindow = 0,
        stoneGeneratedDamageWindow = 0,
        stoneGeneratedWeightedHaWindow = 0,
        stoneExistingWeightedHaWindow = 0,
        stoneDamageLastSecond = 0,
        stoneSurfaceDamageLastSecond = 0,
        stoneGeneratedDamageLastSecond = 0,
        stoneGeneratedWeightedHaLastSecond = 0,
        stoneExistingWeightedHaLastSecond = 0,
        stoneScansLastSecond = 0,
        stoneExistingLevel = 0,
        stoneExistingCoverage = 0,
        stoneGeneratedLevelDelta = 0,
        stoneGeneratedWeightedHaLastScan = 0,
        lastStoneEventSource = "none",
        lastStoneEventDamage = nil,
        lastStoneEventGameTime = nil,
        telemetryWorking = false,
        lastModEnabled = true,
        workingWidth = nil,
        seedQuality = 1,
        seedWorkQuality = 1,
        seedYieldPenalty = 0,
        seedQualityHealth = 1,
        seedQualityDamagePenalty = 0,
        seedQualitySpeedPenalty = 0,
        seedQualityThresholdSpeed = optimalSpeed or ratedSpeed or 0,
        seedQualityThresholdShift = 0,
        seedQualityStatus = self.spec_sowingMachine ~= nil and "ready" or "not a sowing machine",
        seedQualityFruit = "none",
        seedQualityFailedPixels = 0,
        seedQualityProtectedLanes = 0,
        seedQualityPatternLanes = 0,
        seedQualityPatternMode = "inactive",
        seedQualityLaneCap = 0,
        seedQualityFullWidthChance = 0,
        seedQualitySpeedRatio = 0,
        seedQualityHookActive = false,
        seedQualityHookLogged = false,
        seedQualityDensityHookActive = false,
        seedQualityDensityHookLogged = false,
        seedQualityDensityCalls = 0,
        seedQualityPostClearPixels = 0,
        seedQualityPostClearLogged = false,
        seedQualityLatch = nil,
        seedQualityWorkAreaDepthM = 0,
        seedQualityEffectiveLaneWidthM = 0,
        seedQualityHoldDistanceM = 0,
        seedQualityHoldRemainingM = 0,
        seedQualityMissedFraction = 0,
        seedQualityLatchReused = false,
        seedQualityModifier = nil,
        seedQualityFilter = nil,
        seedQualityMapId = nil,
        applicationQuality = 1,
        applicationQualityHealth = 1,
        applicationQualityDamagePenalty = 0,
        applicationQualitySpeedPenalty = 0,
        applicationQualityThresholdSpeed = ratedSpeed or 0,
        applicationQualityThresholdShift = 0,
        applicationQualityStatus = self.spec_sprayer ~= nil and "ready" or "not a sprayer/spreader",
        applicationQualityFillType = "unknown",
        applicationQualityProfile = implementClass ~= nil and implementClass.dropoutProfile or "none",
        applicationQualityPatternMode = "inactive",
        applicationQualitySkippedLanes = 0,
        applicationQualityProcessedLanes = 0,
        qualityPatternNodes = nil,
        impactDropoutState = nil,
        impactDropoutStatus = "inactive",
        impactDropoutFailedLanes = 0,
        impactDropoutTotalLanes = 0,
        impactDropoutTriggerCount = 0,
        impactDropoutMediumCount = 0,
        impactDropoutBigCount = 0,
        impactDropoutThrowCount = 0,
        impactDropoutThrowEventsPerHa = 0,
        impactDropoutThrowEventsPer100m = 0,
        plowThrowEventAccumulator = 0,
        plowIrregularPendingEvents = 0,
        plowIrregularEventCount = 0,
        plowIrregularLastPassEvents = 0,
        plowIrregularLastPixels = 0,
        plowIrregularLastGameplayFailures = 0,
        plowIrregularLastTwoPixelEvents = 0,
        plowSurfaceDiagnosticLogCount = 0,
        plowSurfaceDiagnosticAttemptCount = 0,
        plowSurfaceCandidateSequence = 0,
        plowSurfacePlacementSequence = 0,
        pendingPlowStoneImpact = nil,
        impactDropoutFailedNormalized = nil,
        plowVisualEffectBindings = nil,
        plowVisualEffectBindingAttempted = false,
        plowVisualEffectStatus = self.spec_plow ~= nil and "not bound" or "not a plow",
        plowDropoutHookActive = false,
        plowDropoutHookLogged = false,
        plowDropoutAppliedLogged = false,
        plowVisualTwistedFraction = 0,
        plowVisualMaximumDeviationSteps = 0,
        plowVisualScatteredPixels = 0,
        plowVisualScatteredCells = 0,
        plowDensityTerrainSizeM = 0,
        plowDensityDetailMapSize = 0,
        plowDensityPixelSizeM = 0.5,
        plowDensityLinearScale = 1,
        plowDropoutResolutionFactor = 1,
        plowDensityResolutionSource = "not sampled",
        plowQualityLatch = nil,
        plowQualityProtectionMode = "inactive",
        plowQualityProtectionHoldM = 0,
        plowWorldStableFailureFraction = 0,
        plowMixedCultivatedPixels = 0,
        plowMixedTwistedPixels = 0,
        plowQualityLevelModifier = nil,
        plowQualityLevelMapId = nil,
        pendingPlowQualityWorkAreas = {},
        impactDropoutMissedAreaHa = 0,
        impactDropoutMissedDistanceM = 0,
        rollerQualityFailure = 0,
        rollerQualityStatus = self.spec_roller ~= nil and "ready" or "not a roller",
        rollerQualityFailedPixels = 0,
        rollerLevelModifier = nil,
        rollerLevelMapId = nil,
        workAreaFunctionsRefreshed = false
    }

    -- Preserve the old public specialization field for third-party scripts.
    -- Both names point to the exact same runtime table.
    self.spec_overSpeedDamage = self.spec_terraLogic

    self.spec_terraLogic.isGroundTool = implementClass ~= nil
        and implementClass.work ~= nil
        and implementClass.work.groundContactTool == true
    self.spec_terraLogic.isApplicationTool = self.spec_sprayer ~= nil
    self.spec_terraLogic.groundToolType = implementClass ~= nil
        and implementClass.name or "Not ground-engaging"
    self:updateOverSpeedImplementClass()
    self:refreshOverSpeedWorkAreaProcessingFunctions()
end

function TerraLogic:refreshOverSpeedWorkAreaProcessingFunctions()
    local spec = self.spec_terraLogic
    local workAreaSpec = self.spec_workArea
    if spec == nil or workAreaSpec == nil or workAreaSpec.workAreas == nil then
        return false
    end

    local supportedFunctions = {
        processPlowArea = self.spec_plow ~= nil,
        processCultivatorArea = self.spec_cultivator ~= nil,
        processSowingMachineArea = self.spec_sowingMachine ~= nil,
        processSprayerArea = self.spec_sprayer ~= nil,
        processRollerArea = self.spec_roller ~= nil,
        processMulcherArea = self.spec_mulcher ~= nil,
        processWeederArea = self.spec_weeder ~= nil,
        processStonePickerArea = self.spec_stonePicker ~= nil,
        processBalerArea = self.spec_baler ~= nil,
        processForageWagonArea = self.spec_forageWagon ~= nil
    }
    local rebound = 0
    for _, workArea in ipairs(workAreaSpec.workAreas) do
        local functionName = workArea.functionName
        if supportedFunctions[functionName] == true then
            local currentFunction = self[functionName]
            if currentFunction ~= nil then
                workArea.processingFunction = currentFunction
                rebound = rebound + 1
            end
        end
    end

    spec.workAreaFunctionsRefreshed = true
    spec.workAreaFunctionsRebound = rebound
    if rebound > 0 then
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Rebound %d TerraLogic WorkArea function(s): vehicle=%s",
            rebound, self.getName ~= nil and self:getName() or "implement"
        )
    end
    return true
end

-- Visible stone handling ---------------------------------------------------

-- Returns the stone-contact profile for the recognized implement class.
function TerraLogic:getOverSpeedStoneToolProfile()
    local spec = self.spec_terraLogic
    local key = spec ~= nil and spec.implementClassKey or nil
    return TerraLogic.STONE_TOOL_PROFILES[key], key
end

function TerraLogic:getOverSpeedStoneMapContext()
    local spec = self.spec_terraLogic
    local mission = g_currentMission
    local profile = self:getOverSpeedStoneToolProfile()

    spec.stoneToolMode = profile ~= nil and profile.mode or "Not supported"
    spec.stoneSurfaceFactor = profile ~= nil
        and profile.surface * getRuntimeBalanceMultiplier("stoneSurface") or 0
    spec.stoneGenerationFactor = profile ~= nil
        and profile.generated * getRuntimeBalanceMultiplier("stoneGenerated") or 0
    spec.hiddenImpactFactor = 1
    spec.stoneSystemActive = false

    if not TerraLogic.STONE_INTERACTION_ENABLED then
        spec.stoneSystemStatus = "TerraLogic stone interaction disabled"
        return nil
    end
    if mission == nil or mission.stoneSystem == nil then
        spec.stoneSystemStatus = "Vanilla stone system unavailable"
        return nil
    end
    if mission.missionInfo ~= nil and mission.missionInfo.stonesEnabled == false then
        spec.stoneSystemStatus = "Vanilla stones disabled"
        return nil
    end
    if mission.stoneSystem.getMapHasStones ~= nil
        and not mission.stoneSystem:getMapHasStones() then
        spec.stoneSystemStatus = "Map has no stone layer"
        return nil
    end
    if profile == nil then
        spec.stoneSystemStatus = "Tool has no stone profile"
        return nil
    end

    local mapId, firstChannel, numChannels = mission.stoneSystem:getDensityMapData()
    if mapId == nil or mapId == 0 then
        spec.stoneSystemStatus = "Stone density map unavailable"
        return nil
    end

    -- Keep the hidden-impact share stable when only real stone damage is
    -- switched off for an A/B test. This makes tlStones independent from
    -- tlImpacts instead of silently increasing abstract impacts.
    spec.hiddenImpactFactor = (profile.hidden or 1)
        * getRuntimeBalanceMultiplier("stoneHidden")
    spec.stoneSystemActive = true
    if TerraLogicMain ~= nil and TerraLogicMain.stoneImpactsEnabled == false then
        spec.stoneSystemStatus = "Map active; damage disabled by tlStones"
        return nil
    end

    local visibleStoneModel = TerraLogicSettings ~= nil
        and TerraLogicSettings:getVisibleStoneDamageModel() or "terraLogic"
    local vanillaHandlesVisibleStones =
        TerraLogic.VANILLA_VISIBLE_STONE_CLASSES[
            spec.implementClassKey] == true
    if visibleStoneModel ~= "terraLogic" or vanillaHandlesVisibleStones then
        spec.visibleStoneDamageModel = visibleStoneModel
        spec.visibleStoneDamageSource = vanillaHandlesVisibleStones
            and "Vanilla (not duplicated)" or "Vanilla device list"
        spec.stoneSystemStatus = spec.visibleStoneDamageSource
        return nil
    end

    if spec.stoneModifier == nil or spec.stoneMapId ~= mapId then
        spec.stoneModifier = DensityMapModifier.new(mapId, firstChannel, numChannels, g_terrainNode)
        spec.stoneFilter = DensityMapFilter.new(spec.stoneModifier)
        spec.stoneFilter:setValueCompareParams(DensityValueCompareType.GREATER, 0)
        spec.stoneMapId = mapId
    end

    spec.stoneSystemStatus = "Active"
    return spec.stoneModifier, spec.stoneFilter, profile
end

function TerraLogic:getOverSpeedStoneAreaState(workArea)
    local modifier, filter = self:getOverSpeedStoneMapContext()
    if modifier == nil or filter == nil or workArea == nil
        or workArea.start == nil or workArea.width == nil or workArea.height == nil then
        return nil
    end

    -- Density-map WorkAreas only consume X/Z. Some vehicle WorkArea nodes do
    -- not expose a usable Y return value here, so never perform Y arithmetic.
    local xs, _, zs = getWorldTranslation(workArea.start)
    local xw, _, zw = getWorldTranslation(workArea.width)
    local xh, _, zh = getWorldTranslation(workArea.height)
    modifier:setParallelogramWorldCoords(
        xs, zs, xw, zw, xh, zh, DensityCoordType.POINT_POINT_POINT
    )
    -- The Vanilla map uses 2/3/4 for visible small/medium/large stones. States
    -- 1/5/6 are internal cleared/regrowth states and must not count as visible
    -- contacts. Normalize the visible states to weights 1/2/3.
    local weightedPixels, stonePixels, totalPixels = 0, 0, 0
    for stoneState = 2, 4 do
        filter:setValueCompareParams(DensityValueCompareType.EQUAL, stoneState)
        local _, matchingPixels, sampledPixels = modifier:executeGet(filter)
        matchingPixels = tonumber(matchingPixels) or 0
        weightedPixels = weightedPixels
            + matchingPixels * (stoneState - 1)
        stonePixels = stonePixels + matchingPixels
        totalPixels = math.max(totalPixels, tonumber(sampledPixels) or 0)
    end
    return {
        weightedPixels = tonumber(weightedPixels) or 0,
        stonePixels = tonumber(stonePixels) or 0,
        totalPixels = tonumber(totalPixels) or 0,
        width = math.sqrt((xw - xs) * (xw - xs) + (zw - zs) * (zw - zs))
    }
end

function TerraLogic:processOverSpeedStoneArea(superFunc, workArea, dt)
    local spec = self.spec_terraLogic
    local now = g_currentMission ~= nil and g_currentMission.time or 0
    local lastScan = spec.stoneWorkAreaScanTimes[workArea]
    local elapsedMs = lastScan ~= nil and math.max(now - lastScan, 0) or dt
    local modEnabled = TerraLogicMain == nil or TerraLogicMain.enabled ~= false
    local scanDue = self.isServer and modEnabled
        and self:getIsOverSpeedGroundContactActive()
        and (lastScan == nil or elapsedMs >= TerraLogic.STONE_SCAN_INTERVAL_MS)

    local before = nil
    if scanDue then
        before = self:getOverSpeedStoneAreaState(workArea)
        if before ~= nil then
            spec.stoneWorkAreaScanTimes[workArea] = now
        end
    end

    local realArea, area, processedAreas = superFunc(self, workArea, dt)

    if before == nil then
        return realArea, area, processedAreas
    end

    local after = self:getOverSpeedStoneAreaState(workArea)
    if after == nil then
        return realArea, area, processedAreas
    end

    local profile = self:getOverSpeedStoneToolProfile()
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local rated = tonumber(spec.ratedSpeed) or 0
    if profile == nil or speed <= 0.5 or rated <= 0 then
        return realArea, area, processedAreas
    end

    local speedEnergy = (speed / rated) ^ 2
    local severity = tonumber(spec.impactSeverityFactor) or 1
    local elapsedSeconds = math.max(elapsedMs, dt) / 1000
    local travelledAreaHa = speed / 3.6 * elapsedSeconds
        * math.max(before.width, 0) / 10000
    local existingDensity = before.totalPixels > 0
        and before.weightedPixels / before.totalPixels or 0
    local existingCoverage = before.totalPixels > 0
        and before.stonePixels / before.totalPixels or 0
    local existingWeightedHa = travelledAreaHa * existingDensity

    local generatedWeightedPixels = math.max(
        after.weightedPixels - before.weightedPixels, 0
    )
    local generatedWeightedHa = 0
    if generatedWeightedPixels > 0 and g_currentMission.getFruitPixelsToSqm ~= nil then
        generatedWeightedHa = MathUtil.areaToHa(
            generatedWeightedPixels,
            g_currentMission:getFruitPixelsToSqm()
        )
    end

    local visibleStoneModel = TerraLogicSettings ~= nil
        and TerraLogicSettings:getVisibleStoneDamageModel() or "terraLogic"
    local classKey = spec.implementClassKey
    local vanillaHandlesVisibleStones =
        TerraLogic.VANILLA_VISIBLE_STONE_CLASSES[classKey] == true
    local useExtendedVisibleDamage = visibleStoneModel == "terraLogic"
        and not vanillaHandlesVisibleStones
    local surfaceDamage = existingWeightedHa
        * TerraLogic.STONE_SURFACE_DAMAGE_PER_WEIGHTED_HA
        * (useExtendedVisibleDamage and (spec.stoneSurfaceFactor or 0) or 0)
        * severity * speedEnergy
    local generatedDamage = generatedWeightedHa
        * TerraLogic.STONE_GENERATED_DAMAGE_PER_WEIGHTED_HA
        * (useExtendedVisibleDamage and (spec.stoneGenerationFactor or 0) or 0)
        * severity * speedEnergy
    local rawStoneDamage = math.max(surfaceDamage + generatedDamage, 0)
    local stoneDamage = math.min(rawStoneDamage, TerraLogic.STONE_DAMAGE_MAX_PER_SCAN)
    if rawStoneDamage > stoneDamage and rawStoneDamage > 0 then
        local capScale = stoneDamage / rawStoneDamage
        surfaceDamage = surfaceDamage * capScale
        generatedDamage = generatedDamage * capScale
    end

    spec.stoneExistingLevel = before.stonePixels > 0
        and before.weightedPixels / before.stonePixels or 0
    spec.stoneExistingCoverage = existingCoverage
    spec.stoneGeneratedLevelDelta = generatedWeightedPixels
    spec.stoneGeneratedWeightedHaLastScan = generatedWeightedHa
    spec.visibleStoneDamageModel = visibleStoneModel
    spec.visibleStoneDamageSource = vanillaHandlesVisibleStones
        and "Vanilla (not duplicated)"
        or (useExtendedVisibleDamage and "TerraLogic extended" or "No visible damage")
    spec.stoneScanCountWindow = (spec.stoneScanCountWindow or 0) + 1
    spec.stoneExistingWeightedHaWindow = (spec.stoneExistingWeightedHaWindow or 0)
        + existingWeightedHa
    spec.stoneGeneratedWeightedHaWindow = (spec.stoneGeneratedWeightedHaWindow or 0)
        + generatedWeightedHa
    spec.stoneSurfaceDamageWindow = (spec.stoneSurfaceDamageWindow or 0) + surfaceDamage
    spec.stoneGeneratedDamageWindow = (spec.stoneGeneratedDamageWindow or 0) + generatedDamage

    if stoneDamage > 0 and self.addDamageAmount ~= nil then
        self:addDamageAmount(stoneDamage)
        spec.telemetryCurrentDamage = (spec.telemetryCurrentDamage or 0) + stoneDamage
        local balanceTest = spec.balanceTest
        if balanceTest ~= nil and balanceTest.active == true then
            balanceTest.stoneSurfaceDamage = (balanceTest.stoneSurfaceDamage or 0)
                + surfaceDamage
            balanceTest.stoneGeneratedDamage = (balanceTest.stoneGeneratedDamage or 0)
                + generatedDamage
        end
        spec.lastStoneEventSource = generatedDamage > surfaceDamage
            and "generated" or (generatedDamage > 0 and "surface + generated" or "surface")
        spec.lastStoneEventDamage = stoneDamage
        spec.lastStoneEventGameTime = now
    end

    return realArea, area, processedAreas
end

-- Runs Vanilla cultivation first, then records quality only for changed ground.
function TerraLogic:processCultivatorArea(superFunc, workArea, dt)
    local realArea, area = self:processOverSpeedStoneArea(superFunc, workArea, dt)
    -- A direct drill's cultivating work area is part of the same agronomic
    -- seeding pass. Direct-drill seed quality already represents this result,
    -- so recording cultivating quality here would charge it twice.
    if self.spec_sowingMachine ~= nil
        and self.spec_sowingMachine.useDirectPlanting == true then
        self.spec_terraLogic.integratedCultivatingQualitySkipped = true
        return realArea, area
    end
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local quality, yieldPenalty = TerraLogicQualityManager:getWorkQualityModel(
        self, speed, "soilCultivate")
    local balance = TerraLogic.getWorkQualityBalance(self, "soilCultivate")
    TerraLogicQualityManager:recordWorkArea(
        workArea, "soilCultivate", quality, realArea,
        balance.weight, balance.maxPenalty, self, yieldPenalty)
    return realArea, area
end

-- Physical dropout geometry ------------------------------------------------

-- Samples a deterministic pattern so server and clients see stable gaps.
local function getQualityPatternValue(x, z, laneIndex, salt, patternLength)
    return TerraLogicDropoutManager:getPatternValue(
        x, z, laneIndex, salt, patternLength
    )
end

local function getWorkAreaPatternGeometry(
        workArea, laneWidth, maximumLanes, laneWidthIsMinimum)
    if workArea == nil or workArea.start == nil
        or workArea.width == nil or workArea.height == nil then
        return nil
    end

    local xs, _, zs = getWorldTranslation(workArea.start)
    local xw, _, zw = getWorldTranslation(workArea.width)
    local xh, _, zh = getWorldTranslation(workArea.height)
    local widthX, widthZ = xw - xs, zw - zs
    local heightX, heightZ = xh - xs, zh - zs
    local widthM = math.sqrt(widthX * widthX + widthZ * widthZ)
    if widthM < 0.05 then
        return nil
    end

    local rawLaneCount = widthM / math.max(tonumber(laneWidth) or 0.75, 0.25)
    local lanes = math.clamp(
        laneWidthIsMinimum and math.floor(rawLaneCount) or math.ceil(rawLaneCount),
        1,
        math.max(tonumber(maximumLanes) or 1, 1)
    )
    return {
        xs = xs, ys = 0, zs = zs,
        widthX = widthX, widthY = 0, widthZ = widthZ,
        heightX = heightX, heightY = 0, heightZ = heightZ,
        lanes = lanes
    }
end

local function getDensityCallPatternGeometry(
        startX, startZ, widthX, widthZ, heightX, heightZ,
        laneWidth, maximumLanes, laneWidthIsMinimum)
    startX, startZ = tonumber(startX), tonumber(startZ)
    widthX, widthZ = tonumber(widthX), tonumber(widthZ)
    heightX, heightZ = tonumber(heightX), tonumber(heightZ)
    if startX == nil or startZ == nil or widthX == nil or widthZ == nil
        or heightX == nil or heightZ == nil then
        return nil
    end

    local widthVectorX, widthVectorZ = widthX - startX, widthZ - startZ
    local heightVectorX, heightVectorZ = heightX - startX, heightZ - startZ
    local widthM = math.sqrt(widthVectorX * widthVectorX + widthVectorZ * widthVectorZ)
    if widthM < 0.05 then
        return nil
    end

    return {
        xs = startX, ys = 0, zs = startZ,
        widthX = widthVectorX, widthY = 0, widthZ = widthVectorZ,
        heightX = heightVectorX, heightY = 0, heightZ = heightVectorZ,
        lanes = math.clamp(
            laneWidthIsMinimum
                and math.floor(widthM / math.max(tonumber(laneWidth) or 0.75, 0.25))
                or math.ceil(widthM / math.max(tonumber(laneWidth) or 0.75, 0.25)),
            1,
            math.max(tonumber(maximumLanes) or 1, 1)
        )
    }
end

local function getPatternLaneRange(geometry, firstLaneIndex, lastLaneIndex)
    local u0 = (firstLaneIndex - 1) / geometry.lanes
    local u1 = (lastLaneIndex or firstLaneIndex) / geometry.lanes
    local startX = geometry.xs + geometry.widthX * u0
    local startY = geometry.ys + geometry.widthY * u0
    local startZ = geometry.zs + geometry.widthZ * u0
    local widthX = geometry.xs + geometry.widthX * u1
    local widthY = geometry.ys + geometry.widthY * u1
    local widthZ = geometry.zs + geometry.widthZ * u1
    local heightX = startX + geometry.heightX
    local heightY = startY + geometry.heightY
    local heightZ = startZ + geometry.heightZ
    return {
        startX = startX, startY = startY, startZ = startZ,
        widthX = widthX, widthY = widthY, widthZ = widthZ,
        heightX = heightX, heightY = heightY, heightZ = heightZ,
        centerX = (startX + widthX + heightX) / 3,
        centerZ = (startZ + widthZ + heightZ) / 3
    }
end

local function getPatternLane(geometry, laneIndex)
    return getPatternLaneRange(geometry, laneIndex, laneIndex)
end

local function getPatternGridCell(
        geometry, firstLaneIndex, lastLaneIndex, rowIndex, rowCount)
    local u0 = (firstLaneIndex - 1) / geometry.lanes
    local u1 = (lastLaneIndex or firstLaneIndex) / geometry.lanes
    local v0 = (rowIndex - 1) / rowCount
    local v1 = rowIndex / rowCount
    local startX = geometry.xs + geometry.widthX * u0
        + geometry.heightX * v0
    local startY = geometry.ys + geometry.widthY * u0
        + geometry.heightY * v0
    local startZ = geometry.zs + geometry.widthZ * u0
        + geometry.heightZ * v0
    local widthX = geometry.xs + geometry.widthX * u1
        + geometry.heightX * v0
    local widthY = geometry.ys + geometry.widthY * u1
        + geometry.heightY * v0
    local widthZ = geometry.zs + geometry.widthZ * u1
        + geometry.heightZ * v0
    local heightX = geometry.xs + geometry.widthX * u0
        + geometry.heightX * v1
    local heightY = geometry.ys + geometry.widthY * u0
        + geometry.heightY * v1
    local heightZ = geometry.zs + geometry.widthZ * u0
        + geometry.heightZ * v1
    return {
        startX = startX, startY = startY, startZ = startZ,
        widthX = widthX, widthY = widthY, widthZ = widthZ,
        heightX = heightX, heightY = heightY, heightZ = heightZ,
        centerX = (startX + widthX + heightX) / 3,
        centerZ = (startZ + widthZ + heightZ) / 3
    }
end

local function getPatternNormalizedRange(geometry, u0, u1)
    u0 = math.clamp(tonumber(u0) or 0, 0, 1)
    u1 = math.clamp(tonumber(u1) or 1, 0, 1)
    if u1 <= u0 + 0.0001 then
        return nil
    end
    local startX = geometry.xs + geometry.widthX * u0
    local startY = geometry.ys + geometry.widthY * u0
    local startZ = geometry.zs + geometry.widthZ * u0
    local widthX = geometry.xs + geometry.widthX * u1
    local widthY = geometry.ys + geometry.widthY * u1
    local widthZ = geometry.zs + geometry.widthZ * u1
    local heightX = startX + geometry.heightX
    local heightY = startY + geometry.heightY
    local heightZ = startZ + geometry.heightZ
    return {
        startX = startX, startY = startY, startZ = startZ,
        widthX = widthX, widthY = widthY, widthZ = widthZ,
        heightX = heightX, heightY = heightY, heightZ = heightZ,
        centerX = (startX + widthX + heightX) / 3,
        centerZ = (startZ + widthZ + heightZ) / 3
    }
end

local function expandPatternLaneWorld(lane, paddingM)
    local padding = math.max(tonumber(paddingM) or 0, 0)
    if lane == nil or padding <= 0 then
        return lane
    end
    local lateralX = lane.widthX - lane.startX
    local lateralZ = lane.widthZ - lane.startZ
    local longitudinalX = lane.heightX - lane.startX
    local longitudinalZ = lane.heightZ - lane.startZ
    local lateralLength = math.sqrt(lateralX * lateralX + lateralZ * lateralZ)
    local longitudinalLength = math.sqrt(
        longitudinalX * longitudinalX + longitudinalZ * longitudinalZ
    )
    if lateralLength < 0.001 or longitudinalLength < 0.001 then
        return lane
    end
    local lateralPadX = lateralX / lateralLength * padding
    local lateralPadZ = lateralZ / lateralLength * padding
    local longitudinalPadX = longitudinalX / longitudinalLength * padding
    local longitudinalPadZ = longitudinalZ / longitudinalLength * padding
    return {
        startX = lane.startX - lateralPadX - longitudinalPadX,
        startY = lane.startY,
        startZ = lane.startZ - lateralPadZ - longitudinalPadZ,
        widthX = lane.widthX + lateralPadX - longitudinalPadX,
        widthY = lane.widthY,
        widthZ = lane.widthZ + lateralPadZ - longitudinalPadZ,
        heightX = lane.heightX - lateralPadX + longitudinalPadX,
        heightY = lane.heightY,
        heightZ = lane.heightZ - lateralPadZ + longitudinalPadZ
    }
end

local function getPatternSubArea(lane, u0, u1, v0, v1)
    local lateralX = lane.widthX - lane.startX
    local lateralY = (lane.widthY or lane.startY) - lane.startY
    local lateralZ = lane.widthZ - lane.startZ
    local longitudinalX = lane.heightX - lane.startX
    local longitudinalY = (lane.heightY or lane.startY) - lane.startY
    local longitudinalZ = lane.heightZ - lane.startZ
    local startX = lane.startX + lateralX * u0 + longitudinalX * v0
    local startY = lane.startY + lateralY * u0 + longitudinalY * v0
    local startZ = lane.startZ + lateralZ * u0 + longitudinalZ * v0
    local widthX = lane.startX + lateralX * u1 + longitudinalX * v0
    local widthY = lane.startY + lateralY * u1 + longitudinalY * v0
    local widthZ = lane.startZ + lateralZ * u1 + longitudinalZ * v0
    local heightX = lane.startX + lateralX * u0 + longitudinalX * v1
    local heightY = lane.startY + lateralY * u0 + longitudinalY * v1
    local heightZ = lane.startZ + lateralZ * u0 + longitudinalZ * v1
    return {
        startX = startX, startY = startY, startZ = startZ,
        widthX = widthX, widthY = widthY, widthZ = widthZ,
        heightX = heightX, heightY = heightY, heightZ = heightZ,
        centerX = (startX + widthX + heightX) / 3,
        centerZ = (startZ + widthZ + heightZ) / 3
    }
end

local function getTerrainDetailMetrics(referencePixelSizeM)
    local mission = g_currentMission
    local reference = math.max(tonumber(referencePixelSizeM) or 0.5, 0.05)
    local terrainSize = mission ~= nil
        and tonumber(mission.terrainSize) or tonumber(g_terrainSize) or 0
    local detailMapSize = mission ~= nil
        and tonumber(mission.terrainDetailMapSize) or 0
    local pixelSize = reference
    local source = "reference fallback"
    if terrainSize > 0 and detailMapSize > 0 then
        pixelSize = terrainSize / detailMapSize
        source = "mission terrain/detail ratio"
    end
    pixelSize = math.max(pixelSize, 0.05)
    return {
        terrainSizeM = terrainSize,
        detailMapSize = detailMapSize,
        pixelSizeM = pixelSize,
        referencePixelSizeM = reference,
        linearScale = pixelSize / reference,
        source = source
    }
end

local function getPlowDropoutResolutionFactor(cfg, metrics)
    if cfg == nil or metrics == nil then
        return 1
    end
    local reference = math.max(
        tonumber(cfg.referenceDensityPixelSizeM) or 0.5,
        0.05
    )
    local pixelSize = math.max(tonumber(metrics.pixelSizeM) or reference, 0.05)
    local trigger = cfg.triggers ~= nil and cfg.triggers.overspeedThrow or nil
    local width = math.max(tonumber(cfg.minimumPostPassWidthM) or 0.5, 0.05)
    local minimumLength = trigger ~= nil
        and math.max(tonumber(trigger.minimumDistanceM) or 0, 0) or 0
    local maximumLength = trigger ~= nil
        and math.max(tonumber(trigger.maximumDistanceM) or minimumLength, minimumLength)
        or minimumLength
    local averageLength = math.max((minimumLength + maximumLength) * 0.5, 0.05)
    local referenceArea = math.max(width, reference)
        * math.max(averageLength, reference)
    local rasterArea = math.max(width, pixelSize)
        * math.max(averageLength, pixelSize)
    return math.clamp(
        referenceArea / math.max(rasterArea, 0.0025),
        0.05,
        1
    )
end

-- Legacy note: experimental plough-surface scattering is currently not called.
-- It remains here as isolated reference code for the earlier visual prototype;
-- gameplay quality uses the active lane and impact paths below.
local function applyPlowSurfaceScatter(
        vehicle, area, params, scatter, fraction, saltOffset, densityMetrics,
        deferredCandidates, deferredCoverage, gameplayFailureFraction,
        gameplayRestorePlowLevel)
    local mission = g_currentMission
    local scatterFraction = math.clamp(tonumber(fraction) or 0, 0, 1)
    if vehicle == nil or area == nil or params == nil or scatter == nil
        or mission == nil or mission.fieldGroundSystem == nil
        or scatterFraction <= 0 then
        return 0, 0, {}
    end

    -- WorkArea pattern geometry stores an origin plus width/height vectors,
    -- while an already selected lane stores three absolute world points.
    -- Normalize both inputs to the latter before doing any arithmetic.
    if area.startX == nil then
        area = getPatternNormalizedRange(area, 0, 1)
    end
    if area == nil
        or tonumber(area.startX) == nil or tonumber(area.startZ) == nil
        or tonumber(area.widthX) == nil or tonumber(area.widthZ) == nil
        or tonumber(area.heightX) == nil or tonumber(area.heightZ) == nil then
        return 0, 0, {}
    end

    local lateralX = area.widthX - area.startX
    local lateralZ = area.widthZ - area.startZ
    local longitudinalX = area.heightX - area.startX
    local longitudinalZ = area.heightZ - area.startZ
    local widthM = math.sqrt(lateralX * lateralX + lateralZ * lateralZ)
    local lengthM = math.sqrt(
        longitudinalX * longitudinalX + longitudinalZ * longitudinalZ
    )
    if widthM < 0.01 or lengthM < 0.01 then
        return 0, 0, {}
    end
    densityMetrics = densityMetrics or getTerrainDetailMetrics(
        scatter.referenceDensityPixelSizeM
    )
    local densityPixelSize = math.max(
        tonumber(densityMetrics.pixelSizeM) or 0.5,
        0.05
    )
    local patchRasterPixels = math.max(
        tonumber(scatter.cellWidthDensityPixels) or 1,
        1
    ) * math.max(
        tonumber(scatter.cellLengthDensityPixels) or 1,
        1
    )
    -- scatterFraction describes desired final surface coverage. A selected
    -- 1x2 candidate changes two raster pixels, so using that fraction directly
    -- as its probability nearly doubles coverage and lets overlapping spots
    -- collapse into a cultivated carpet. Convert coverage to the independent
    -- candidate probability which produces it after patch expansion.
    local candidateSelectionFraction = 1
        - math.max(1 - scatterFraction, 0) ^ (1 / patchRasterPixels)
    local gameplayCoverageFraction = math.clamp(
        tonumber(gameplayFailureFraction) or 0,
        0,
        scatterFraction
    )
    local gameplaySelectionFraction = 1
        - math.max(1 - gameplayCoverageFraction, 0)
            ^ (1 / patchRasterPixels)
    -- Never create several random sub-cells inside one physical density-map
    -- pixel. On a 4x map with an unscaled detail map that would otherwise turn
    -- several independent chances into one oversized, almost guaranteed hit.
    local cellWidth = math.max(
        tonumber(scatter.cellWidthM) or 0.85,
        densityPixelSize
            * math.max(tonumber(scatter.cellWidthDensityPixels) or 1, 1)
    )
    local cellLength = math.max(
        tonumber(scatter.cellLengthM) or 1,
        densityPixelSize
            * math.max(tonumber(scatter.cellLengthDensityPixels) or 1, 1)
    )
    local normalizedSaltOffset = math.floor(tonumber(saltOffset) or 0)
    local changedPixels = 0
    local selectedCells = 0
    local selectedAreas = {}
    local visitedDensityPixels = {}
    local stratificationCache = {}
    local determinant = lateralX * longitudinalZ
        - lateralZ * longitudinalX
    if math.abs(determinant) < 0.0001 then
        return 0, 0, {}
    end
    local fourthX = area.widthX + area.heightX - area.startX
    local fourthZ = area.widthZ + area.heightZ - area.startZ
    local terrainHalf = densityMetrics.terrainSizeM * 0.5
    local minimumWorldX = math.min(
        area.startX, area.widthX, area.heightX, fourthX
    )
    local maximumWorldX = math.max(
        area.startX, area.widthX, area.heightX, fourthX
    )
    local minimumWorldZ = math.min(
        area.startZ, area.widthZ, area.heightZ, fourthZ
    )
    local maximumWorldZ = math.max(
        area.startZ, area.widthZ, area.heightZ, fourthZ
    )
    local minimumPixelX = math.floor(
        (minimumWorldX + terrainHalf) / densityPixelSize
    )
    local maximumPixelX = math.floor(
        (maximumWorldX + terrainHalf) / densityPixelSize
    )
    local minimumPixelZ = math.floor(
        (minimumWorldZ + terrainHalf) / densityPixelSize
    )
    local maximumPixelZ = math.floor(
        (maximumWorldZ + terrainHalf) / densityPixelSize
    )
    local halfCellU = math.min(cellWidth / math.max(widthM, 0.01) * 0.5, 0.5)
    local halfCellV = math.min(cellLength / math.max(lengthM, 0.01) * 0.5, 0.5)
    local rasterMarginU = math.min(
        densityPixelSize / math.max(widthM, 0.01) * 0.5,
        0.5
    )
    local rasterMarginV = math.min(
        densityPixelSize / math.max(lengthM, 0.01) * 0.5,
        0.5
    )
    local coverageRadius = math.max(
        math.ceil(
            math.max(cellWidth, cellLength)
                / math.max(densityPixelSize * 2, 0.1)
        ),
        math.ceil(
            tonumber(scatter.trailingCommitGuardDensityPixels) or 1
        )
    )
    for densityPixelX = minimumPixelX, maximumPixelX do
        local worldX = (densityPixelX + 0.5) * densityPixelSize
            - terrainHalf
        for densityPixelZ = minimumPixelZ, maximumPixelZ do
            local worldZ = (densityPixelZ + 0.5) * densityPixelSize
                - terrainHalf
            local deltaX = worldX - area.startX
            local deltaZ = worldZ - area.startZ
            local u = (deltaX * longitudinalZ
                - deltaZ * longitudinalX) / determinant
            local v = (lateralX * deltaZ
                - lateralZ * deltaX) / determinant
            if u >= -rasterMarginU and u <= 1 + rasterMarginU
                and v >= -rasterMarginV and v <= 1 + rasterMarginV then
            local patchU = math.clamp(u, 0, 1)
            local patchV = math.clamp(v, 0, 1)
            local densityPixelKey = string.format(
                "%d:%d", densityPixelX, densityPixelZ
            )
            if deferredCoverage ~= nil then
                -- Include a small raster guard around every sampled cell.
                -- A 1x2 visual patch spans more than its centre pixel, and a
                -- following staggered WorkArea may still overwrite its edge.
                -- The guard delays the commit until the old cell is safely
                -- behind the complete multi-part plow footprint.
                for offsetX = -coverageRadius, coverageRadius do
                    for offsetZ = -coverageRadius, coverageRadius do
                        deferredCoverage[string.format(
                            "%d:%d",
                            densityPixelX + offsetX,
                            densityPixelZ + offsetZ
                        )] = true
                    end
                end
            end
            local pattern = TerraLogicDropoutManager:getStratifiedPatternValue(
                densityPixelX,
                densityPixelZ,
                (tonumber(scatter.patternSalt) or 0) + normalizedSaltOffset,
                scatter.visualStratificationSize,
                stratificationCache
            )
            -- Stratified world-stable 1x2 cells form evenly spaced isolated
            -- blemishes at low coverage. As speed raises the target coverage,
            -- neighbouring ranks fill and finally become broad surface noise.
            local selected = visitedDensityPixels[densityPixelKey] == nil
                and pattern < candidateSelectionFraction
            if selected then
                visitedDensityPixels[densityPixelKey] = true
                -- Selection is anchored to the map raster, not the diagonal
                -- WorkArea subdivision. The written 1x2-raster patch remains
                -- aligned with travel but its centre is distributed uniformly
                -- over world pixels, preventing repeated diagonal chains.
                local patchU0 = math.clamp(
                    patchU - halfCellU,
                    0,
                    math.max(1 - halfCellU * 2, 0)
                )
                local patchV0 = math.clamp(
                    patchV - halfCellV,
                    0,
                    math.max(1 - halfCellV * 2, 0)
                )
                local writeArea = getPatternSubArea(
                    area,
                    patchU0,
                    math.min(patchU0 + halfCellU * 2, 1),
                    patchV0,
                    math.min(patchV0 + halfCellV * 2, 1)
                )
                if deferredCandidates ~= nil then
                    -- Multi-part plows can have several overlapping WorkAreas.
                    -- Do not alternate Vanilla plow and TerraLogic cultivated writes
                    -- while a density cell is still underneath any of them.
                    -- onEndWorkAreaProcessing commits the cell only after it
                    -- has left the union of all current WorkAreas.
                    if deferredCandidates[densityPixelKey] == nil then
                        selectedCells = selectedCells + 1
                    end
                    local existingCandidate =
                        deferredCandidates[densityPixelKey]
                    local isGameplayFailure = pattern
                        < math.min(
                            gameplaySelectionFraction,
                            candidateSelectionFraction
                        )
                    deferredCandidates[densityPixelKey] = {
                        area = writeArea,
                        limitToField = params.limitToField,
                        limitFruitDestructionToField =
                            params.limitFruitDestructionToField,
                        angle = params.angle,
                        restorePlowLevel =
                            (existingCandidate ~= nil
                                and existingCandidate.restorePlowLevel ~= nil)
                                and existingCandidate.restorePlowLevel
                                or (isGameplayFailure
                                    and gameplayRestorePlowLevel or nil),
                        isGameplayFailure =
                            (existingCandidate ~= nil
                                and existingCandidate.isGameplayFailure == true)
                                or isGameplayFailure
                    }
                else
                    local cultivated = FSDensityMapUtil.updateCultivatorArea(
                        writeArea.startX, writeArea.startZ,
                        writeArea.widthX, writeArea.widthZ,
                        writeArea.heightX, writeArea.heightZ,
                        not params.limitToField,
                        params.limitFruitDestructionToField,
                        params.angle,
                        nil,
                        false,
                        true
                    )
                    changedPixels = changedPixels
                        + (tonumber(cultivated) or 0)
                    selectedCells = selectedCells + 1
                    selectedAreas[#selectedAreas + 1] = writeArea
                end
            end
            end
        end
    end
    return changedPixels, selectedCells, selectedAreas
end

local function getPlowLevelMapContext(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    local mission = g_currentMission
    if spec == nil or mission == nil or mission.fieldGroundSystem == nil
        or FieldDensityMap == nil or FieldDensityMap.PLOW_LEVEL == nil then
        return nil
    end
    local mapId, firstChannel, numChannels =
        mission.fieldGroundSystem:getDensityMapData(FieldDensityMap.PLOW_LEVEL)
    if mapId == nil or mapId == 0 then
        return nil
    end
    if spec.plowQualityLevelModifier == nil
        or spec.plowQualityLevelMapId ~= mapId then
        spec.plowQualityLevelModifier = DensityMapModifier.new(
            mapId, firstChannel, numChannels, g_terrainNode
        )
        spec.plowQualityLevelFilter = DensityMapFilter.new(
            spec.plowQualityLevelModifier
        )
        spec.plowQualityLevelMapId = mapId
    end
    return spec.plowQualityLevelModifier,
        spec.plowQualityLevelFilter,
        mapId,
        firstChannel,
        numChannels
end

-- Legacy note: deferred scatter candidates belong to the inactive prototype
-- above. Keeping this helper is harmless, but it must not be mistaken for an
-- active gameplay or savegame path.
local function commitDeferredPlowSurfaceCandidates(
        vehicle, candidates, stillCovered, paddingM)
    if vehicle == nil or not vehicle.isServer or candidates == nil then
        return 0, 0, 0
    end
    local mission = g_currentMission
    local successfulPlowLevel = FieldDensityMap ~= nil
        and FieldDensityMap.PLOW_LEVEL ~= nil
        and mission ~= nil
        and mission.fieldGroundSystem ~= nil
        and mission.fieldGroundSystem:getMaxValue(FieldDensityMap.PLOW_LEVEL)
        or nil
    local plowLevelModifier = successfulPlowLevel ~= nil
        and getPlowLevelMapContext(vehicle) or nil
    local changedPixels, committedCells, gameplayFailureCells = 0, 0, 0
    for densityPixelKey, candidate in pairs(candidates) do
        if stillCovered == nil or stillCovered[densityPixelKey] == nil then
            local area = candidate.area
            if area ~= nil then
                local cultivated = FSDensityMapUtil.updateCultivatorArea(
                    area.startX, area.startZ,
                    area.widthX, area.widthZ,
                    area.heightX, area.heightZ,
                    not candidate.limitToField,
                    candidate.limitFruitDestructionToField,
                    candidate.angle,
                    nil,
                    false,
                    true
                )
                changedPixels = changedPixels + (tonumber(cultivated) or 0)
                committedCells = committedCells + 1
                if candidate.isGameplayFailure == true then
                    gameplayFailureCells = gameplayFailureCells + 1
                end
                if plowLevelModifier ~= nil then
                    local protectedArea = expandPatternLaneWorld(
                        area,
                        math.max(tonumber(paddingM) or 0, 0)
                    )
                    plowLevelModifier:setParallelogramWorldCoords(
                        protectedArea.startX, protectedArea.startZ,
                        protectedArea.widthX, protectedArea.widthZ,
                        protectedArea.heightX, protectedArea.heightZ,
                        DensityCoordType.POINT_POINT_POINT
                    )
                    local targetPlowLevel = candidate.isGameplayFailure
                        and tonumber(candidate.restorePlowLevel)
                        or successfulPlowLevel
                    if targetPlowLevel ~= nil then
                        plowLevelModifier:executeSet(targetPlowLevel)
                    end
                end
            end
        end
    end
    return changedPixels, committedCells, gameplayFailureCells
end

-- Preserve the state that existed before Vanilla processes the plow. A failed
-- pass must not create a new plowing requirement on a field that did not need
-- plowing, and it must not clear an existing requirement either.
local function samplePreviousPlowLevel(vehicle, workArea, forwardOffsetM)
    if workArea == nil or workArea.start == nil or workArea.width == nil
        or workArea.height == nil then
        return nil, "invalid work area"
    end
    local modifier, filter =
        getPlowLevelMapContext(vehicle)
    if modifier == nil then
        return nil, "plow map unavailable"
    end

    local xs, _, zs = getWorldTranslation(workArea.start)
    local xw, _, zw = getWorldTranslation(workArea.width)
    local xh, _, zh = getWorldTranslation(workArea.height)
    local appliedForwardOffset = 0
    local requestedForwardOffset = math.max(
        tonumber(forwardOffsetM) or 0,
        0
    )
    local directionNode = vehicle.spec_plow ~= nil
        and vehicle.spec_plow.directionNode or nil
    if requestedForwardOffset > 0 and directionNode ~= nil then
        local dx, _, dz = localDirectionToWorld(directionNode, 0, 0, 1)
        local directionLength = math.sqrt(dx * dx + dz * dz)
        if directionLength > 0.001 then
            local shiftX = dx / directionLength * requestedForwardOffset
            local shiftZ = dz / directionLength * requestedForwardOffset
            xs, zs = xs + shiftX, zs + shiftZ
            xw, zw = xw + shiftX, zw + shiftZ
            xh, zh = xh + shiftX, zh + shiftZ
            appliedForwardOffset = requestedForwardOffset
        end
    end
    modifier:setParallelogramWorldCoords(
        xs, zs, xw, zw, xh, zh,
        DensityCoordType.POINT_POINT_POINT
    )
    local maximumValue = g_currentMission.fieldGroundSystem:getMaxValue(
        FieldDensityMap.PLOW_LEVEL
    )
    local bestValue, bestPixels = nil, -1
    for value = 0, math.max(tonumber(maximumValue) or 0, 0) do
        filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
        local _, matchingPixels = modifier:executeGet(filter)
        matchingPixels = tonumber(matchingPixels) or 0
        if matchingPixels > bestPixels then
            bestValue, bestPixels = value, matchingPixels
        end
    end
    return bestValue, appliedForwardOffset > 0
        and string.format("forward area majority +%.1fm", appliedForwardOffset)
        or "area majority"
end

-- WorkArea raises this event before any individual processingFunction runs.
-- Snapshotting here prevents a front/rear WorkArea on a multi-part plow from
-- reading a PLOW_LEVEL that another part of the same plow has already reset.
function TerraLogic:onStartWorkAreaProcessing(dt, workAreas)
    local spec = self.spec_terraLogic
    if spec == nil or self.spec_plow == nil or not self.isServer then
        return
    end
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local isLowered = self.getIsLowered == nil or self:getIsLowered()
    -- Reading PLOW_LEVEL is only required for a queued stone or overspeed
    -- patch. The old pass-wide cache scanned every plow WorkArea continuously;
    -- this event-gated snapshot leaves ordinary plowing untouched.
    local needsPlowLevelSnapshot = spec.pendingPlowStoneImpact ~= nil
        or (spec.plowIrregularPendingEvents or 0) > 0
    if speed <= 0.5 or not isLowered
        or not needsPlowLevelSnapshot then
        spec.plowQualityPassSnapshots = nil
        spec.plowQualityPrePassSnapshots = {}
        return
    end
    spec.plowQualityPrePassSnapshots = {}
    for _, workArea in ipairs(workAreas or {}) do
        if workArea.functionName == "processPlowArea"
            and spec.plowQualityPrePassSnapshots[workArea] == nil then
            local level, source = samplePreviousPlowLevel(
                self, workArea
            )
            spec.plowQualityPrePassSnapshots[workArea] = {
                level = level,
                source = source
            }
        end
    end
end

local function getConfiguredWorkWidth(vehicle)
    local spec = vehicle.spec_terraLogic
    if spec ~= nil and spec.configuredWorkWidthResolved == true then
        return spec.configuredWorkWidthM
    end

    local configuredWidth = nil
    if vehicle.xmlFile ~= nil then
        local configurationId = vehicle.configurations ~= nil
            and tonumber(vehicle.configurations["workArea"]) or 1
        local key = string.format(
            "vehicle.workAreas.workAreaConfigurations.workAreaConfiguration(%d)",
            math.max((configurationId or 1) - 1, 0)
        )
        configuredWidth = tonumber(vehicle.xmlFile:getValue(key .. "#workingWidth"))
        -- There is no registered vehicle XML schema path at
        -- vehicle.workAreas#workingWidth. If the optional configuration value
        -- is absent, combined geometry already derives a safe width from the
        -- actual WorkArea nodes and store data.
    end
    if spec ~= nil then
        spec.configuredWorkWidthM = configuredWidth
        spec.configuredWorkWidthResolved = true
    end
    return configuredWidth
end

-- Builds one lateral coordinate system across every actual ploughing WorkArea.
-- Many large plows consist of staggered front/rear areas. Segmenting each one
-- independently lets their overlap repair the intended dropout; global
-- corridors make every area skip the same physical strip.
local function getCombinedPlowPatternGeometry(vehicle, cfg)
    local workAreas = vehicle.spec_workArea ~= nil
        and vehicle.spec_workArea.workAreas or nil
    if workAreas == nil then
        return nil
    end

    local reference = nil
    for _, candidate in ipairs(workAreas) do
        if candidate.functionName == "processPlowArea"
            and candidate.start ~= nil and candidate.width ~= nil
            and candidate.height ~= nil then
            reference = candidate
            break
        end
    end
    if reference == nil then
        return nil
    end

    local rsx, _, rsz = getWorldTranslation(reference.start)
    local rwx, _, rwz = getWorldTranslation(reference.width)
    local axisX, axisZ = rwx - rsx, rwz - rsz
    local axisLength = math.sqrt(axisX * axisX + axisZ * axisZ)
    if axisLength < 0.05 then
        return nil
    end
    axisX, axisZ = axisX / axisLength, axisZ / axisLength

    local minimumProjection, maximumProjection = math.huge, -math.huge
    local minimumLongitudinal, maximumLongitudinal = math.huge, -math.huge
    local longitudinalX, longitudinalZ = -axisZ, axisX
    local function includeLateralPoint(x, z)
        local lateral = x * axisX + z * axisZ
        minimumProjection = math.min(minimumProjection, lateral)
        maximumProjection = math.max(maximumProjection, lateral)
    end
    local function includeLongitudinalPoint(x, z)
        local longitudinal = x * longitudinalX + z * longitudinalZ
        minimumLongitudinal = math.min(minimumLongitudinal, longitudinal)
        maximumLongitudinal = math.max(maximumLongitudinal, longitudinal)
    end

    local areaCount = 0
    local declaredWorkWidthM = 0
    for _, candidate in ipairs(workAreas) do
        if candidate.functionName == "processPlowArea"
            and candidate.start ~= nil and candidate.width ~= nil
            and candidate.height ~= nil then
            local sx, _, sz = getWorldTranslation(candidate.start)
            local wx, _, wz = getWorldTranslation(candidate.width)
            local hx, _, hz = getWorldTranslation(candidate.height)
            -- Only start->width defines lateral working width. The height node
            -- may be several metres diagonally behind it; including that
            -- lateral offset invented lanes outside the real leading edge and
            -- made almost only the outermost dropout rows visible.
            includeLateralPoint(sx, sz)
            includeLateralPoint(wx, wz)
            includeLongitudinalPoint(sx, sz)
            includeLongitudinalPoint(wx, wz)
            includeLongitudinalPoint(hx, hz)
            includeLongitudinalPoint(wx + hx - sx, wz + hz - sz)
            declaredWorkWidthM = math.max(
                declaredWorkWidthM,
                math.max(tonumber(candidate.workWidth) or 0, 0)
            )
            areaCount = areaCount + 1
        end
    end

    local widthM = maximumProjection - minimumProjection
    if areaCount == 0 or widthM < 0.05 then
        return nil
    end
    local segmentWidth = math.max(tonumber(cfg.segmentWidthM) or 0.75, 0.25)
    local configuredWorkWidthM = getConfiguredWorkWidth(vehicle)
    local patternWidthM = configuredWorkWidthM ~= nil
        and configuredWorkWidthM > 0 and configuredWorkWidthM
        or math.max(widthM, declaredWorkWidthM)
    return {
        lanes = math.clamp(
            math.floor(patternWidthM / segmentWidth + 0.5),
            1,
            math.max(tonumber(cfg.maximumPatternLanes) or 1, 1)
        ),
        axisX = axisX,
        axisZ = axisZ,
        minimumProjection = minimumProjection,
        maximumProjection = maximumProjection,
        widthM = widthM,
        patternWidthM = patternWidthM,
        declaredWorkWidthM = declaredWorkWidthM,
        configuredWorkWidthM = configuredWorkWidthM,
        depthM = maximumLongitudinal - minimumLongitudinal,
        areaCount = areaCount
    }
end

local function getSuccessfulGlobalPlowRanges(localGeometry, globalGeometry, failedIndexes)
    local startProjection = localGeometry.xs * globalGeometry.axisX
        + localGeometry.zs * globalGeometry.axisZ
    local widthProjection = (localGeometry.xs + localGeometry.widthX)
        * globalGeometry.axisX
        + (localGeometry.zs + localGeometry.widthZ) * globalGeometry.axisZ
    local projectionSpan = widthProjection - startProjection
    if math.abs(projectionSpan) < 0.01 then
        return nil
    end

    local failedRanges = {}
    local globalSpan = globalGeometry.maximumProjection
        - globalGeometry.minimumProjection
    for laneIndex = 1, globalGeometry.lanes do
        if failedIndexes[laneIndex] then
            local p0 = globalGeometry.minimumProjection
                + globalSpan * ((laneIndex - 1) / globalGeometry.lanes)
            local p1 = globalGeometry.minimumProjection
                + globalSpan * (laneIndex / globalGeometry.lanes)
            local u0 = (p0 - startProjection) / projectionSpan
            local u1 = (p1 - startProjection) / projectionSpan
            if u1 < u0 then
                u0, u1 = u1, u0
            end
            u0, u1 = math.max(u0, 0), math.min(u1, 1)
            if u1 > u0 + 0.0001 then
                failedRanges[#failedRanges + 1] = {u0 = u0, u1 = u1}
            end
        end
    end
    table.sort(failedRanges, function(a, b) return a.u0 < b.u0 end)

    local merged = {}
    for _, range in ipairs(failedRanges) do
        local last = merged[#merged]
        if last ~= nil and range.u0 <= last.u1 + 0.0001 then
            last.u1 = math.max(last.u1, range.u1)
        else
            merged[#merged + 1] = {u0 = range.u0, u1 = range.u1}
        end
    end

    local successful = {}
    local cursor = 0
    for _, range in ipairs(merged) do
        if range.u0 > cursor + 0.0001 then
            successful[#successful + 1] = {u0 = cursor, u1 = range.u0}
        end
        cursor = math.max(cursor, range.u1)
    end
    if cursor < 1 - 0.0001 then
        successful[#successful + 1] = {u0 = cursor, u1 = 1}
    end
    return successful, merged
end

local function getQualityPatternWorkArea(spec, vehicle, lane)
    if spec.qualityPatternNodes == nil then
        spec.qualityPatternNodes = {
            start = createTransformGroup("terraLogicQualityStart"),
            width = createTransformGroup("terraLogicQualityWidth"),
            height = createTransformGroup("terraLogicQualityHeight")
        }
        if vehicle.rootNode ~= nil then
            link(vehicle.rootNode, spec.qualityPatternNodes.start)
            link(vehicle.rootNode, spec.qualityPatternNodes.width)
            link(vehicle.rootNode, spec.qualityPatternNodes.height)
        end
    end
    setWorldTranslation(spec.qualityPatternNodes.start,
        lane.startX, lane.startY, lane.startZ)
    setWorldTranslation(spec.qualityPatternNodes.width,
        lane.widthX, lane.widthY, lane.widthZ)
    setWorldTranslation(spec.qualityPatternNodes.height,
        lane.heightX, lane.heightY, lane.heightZ)

    return spec.qualityPatternNodes
end

local function copyWorkAreaWithPatternNodes(workArea, nodes)
    local laneWorkArea = {}
    for key, value in pairs(workArea) do
        laneWorkArea[key] = value
    end
    laneWorkArea.start = nodes.start
    laneWorkArea.width = nodes.width
    laneWorkArea.height = nodes.height
    return laneWorkArea
end

-- Applies speed-driven, world-stable surface islands before Vanilla touches
-- fruit or windrow density. Only successful lateral runs invoke the original
-- specialization. Mutable WorkArea buffers are carried between those calls so
-- mower, windrower, tedder, sprayer, weeder and pickup bookkeeping stays
-- equivalent to one full pass; balers and loader wagons accumulate their
-- collected volume in specialization-wide params. Deep spinner WorkAreas may
-- opt into a bounded longitudinal grid so their misses form cells instead of
-- diagonal lanes.
function TerraLogic:processSurfacePatchDropoutArea(
        superFunc, workArea, dt, profileName)
    local spec = self.spec_terraLogic
    local cfg = TerraLogicDropoutManager:getProfile(profileName)
    local modEnabled = TerraLogicMain == nil
        or TerraLogicMain.enabled ~= false
    local function markActualWork(realArea, pickedUpLiters)
        local actualWorkAmount = cfg ~= nil
            and cfg.actualWorkRequiresPickup == true
            and (tonumber(pickedUpLiters) or 0)
            or (tonumber(realArea) or 0)
        if spec ~= nil and actualWorkAmount > 0 then
            spec.lastActualWorkTime = g_currentMission ~= nil
                and (g_currentMission.time or 0) or 0
            spec.lastActualWorkProfile = profileName
            if self.isServer and spec.actualWorkActive ~= true then
                spec.actualWorkActive = true
                self:raiseDirtyFlags(spec.actualWorkDirtyFlag)
            end
        end
    end
    local function processWholeArea()
        local realArea, totalArea = superFunc(self, workArea, dt)
        markActualWork(realArea, workArea.lastPickUpLiters)
        return realArea, totalArea, {{
            workArea = workArea,
            realArea = tonumber(realArea) or 0,
            totalArea = tonumber(totalArea) or 0
        }}
    end
    if spec == nil or cfg == nil or cfg.enabled ~= true
        or not self.isServer or not modEnabled
        or not getArePhysicalDropoutsEnabled() then
        return processWholeArea()
    end

    local speed = self.getLastSpeed ~= nil
        and math.abs(tonumber(self:getLastSpeed(true)) or 0) or 0
    local rated = math.max(tonumber(spec.ratedSpeed) or 0, 0)
    local failureFraction =
        TerraLogicDropoutManager:getSurfacePatchFailureFraction(
            profileName, speed, rated
        )
    if failureFraction <= 0 then
        spec.surfacePatchDropoutStatus = "below shop speed"
        spec.surfacePatchDropoutFailedLanes = 0
        return processWholeArea()
    end

    local geometry = getWorkAreaPatternGeometry(
        workArea,
        cfg.patternLaneWidthM or 0.75,
        cfg.maximumPatternLanes or 32,
        true
    )
    if geometry == nil then
        spec.surfacePatchDropoutStatus = "invalid work area"
        return processWholeArea()
    end

    -- Remove the lateral part of the triangular height vector to recover the
    -- WorkArea's forward/depth axis. Spinner-spreader profiles use it to keep
    -- elongated misses stable through their heavily overlapping deep throw.
    local widthLength = math.sqrt(
        geometry.widthX * geometry.widthX
            + geometry.widthZ * geometry.widthZ)
    local lateralX = geometry.widthX / math.max(widthLength, 0.001)
    local lateralZ = geometry.widthZ / math.max(widthLength, 0.001)
    local heightLateral = geometry.heightX * lateralX
        + geometry.heightZ * lateralZ
    local longitudinalX = geometry.heightX - lateralX * heightLateral
    local longitudinalZ = geometry.heightZ - lateralZ * heightLateral
    local longitudinalLength = math.sqrt(
        longitudinalX * longitudinalX
            + longitudinalZ * longitudinalZ)
    local rowCount = 1
    if cfg.useLongitudinalPatternGrid == true then
        rowCount = math.clamp(
            math.ceil(longitudinalLength
                / math.max(tonumber(cfg.patternRowLengthM) or 3, 0.5)),
            1,
            math.max(tonumber(cfg.maximumPatternRows) or 8, 1)
        )
    end
    if longitudinalLength <= 0.001 then
        longitudinalX, longitudinalZ = -lateralZ, lateralX
    else
        longitudinalX = longitudinalX / longitudinalLength
        longitudinalZ = longitudinalZ / longitudinalLength
    end
    local failedIndexesByRow, failedCount = {}, 0
    for rowIndex = 1, rowCount do
        local lanes = {}
        for laneIndex = 1, geometry.lanes do
            lanes[laneIndex] = rowCount > 1
                and getPatternGridCell(
                    geometry, laneIndex, laneIndex, rowIndex, rowCount)
                or getPatternLane(geometry, laneIndex)
        end
        local failedIndexes, rowFailedCount =
            TerraLogicDropoutManager:getSurfacePatchFailedLanes(
                profileName, lanes, failureFraction,
                longitudinalX, longitudinalZ
            )
        failedIndexesByRow[rowIndex] = failedIndexes
        failedCount = failedCount + rowFailedCount
    end
    local totalCells = geometry.lanes * rowCount
    spec.surfacePatchDropoutProfile = profileName
    spec.surfacePatchDropoutTargetFraction = failureFraction
    spec.surfacePatchDropoutFailedLanes = failedCount
    spec.surfacePatchDropoutTotalLanes = totalCells
    if failedCount == 0 then
        spec.surfacePatchDropoutStatus = "no island in current pass"
        return processWholeArea()
    end

    local realAreaSum, totalAreaSum = 0, 0
    local pickupSum, pickUpSum, pickedUpSum, droppedSum = 0, 0, 0, 0
    local pickupParticlesActive = false
    local processedRuns, processedAreas = 0, {}
    local carryFields = {
        "litersToDrop", "lastValidPickupFillType", "lastDropFillType",
        "lineOffset", "lastLineOffset"
    }

    local function processSuccessfulRun(rowIndex, runStart, runEnd)
        if runStart == nil then return end
        local lane = rowCount > 1
            and getPatternGridCell(
                geometry, runStart, runEnd, rowIndex, rowCount)
            or getPatternLaneRange(geometry, runStart, runEnd)
        local nodes = getQualityPatternWorkArea(spec, self, lane)
        local laneWorkArea = copyWorkAreaWithPatternNodes(workArea, nodes)
        local realArea, totalArea = superFunc(self, laneWorkArea, dt)
        processedAreas[#processedAreas + 1] = {
            workArea = laneWorkArea,
            lane = lane,
            realArea = tonumber(realArea) or 0,
            totalArea = tonumber(totalArea) or 0
        }
        realAreaSum = realAreaSum + (tonumber(realArea) or 0)
        totalAreaSum = totalAreaSum + (tonumber(totalArea) or 0)
        pickupSum = pickupSum
            + (tonumber(laneWorkArea.lastPickupLiters) or 0)
        pickUpSum = pickUpSum
            + (tonumber(laneWorkArea.lastPickUpLiters) or 0)
        pickupParticlesActive = pickupParticlesActive
            or laneWorkArea.pickupParticlesActive == true
        pickedUpSum = pickedUpSum
            + (tonumber(laneWorkArea.pickedUpLiters) or 0)
        droppedSum = droppedSum
            + (tonumber(laneWorkArea.lastDroppedLiters) or 0)
        for _, fieldName in ipairs(carryFields) do
            if laneWorkArea[fieldName] ~= nil then
                workArea[fieldName] = laneWorkArea[fieldName]
            end
        end
        -- Keep the most recent values while the next run executes; some
        -- Vanilla branches use them to select the compatible windrow type.
        workArea.lastPickupLiters = laneWorkArea.lastPickupLiters
        workArea.lastDroppedLiters = laneWorkArea.lastDroppedLiters
        processedRuns = processedRuns + 1
    end

    for rowIndex = 1, rowCount do
        local failedIndexes = failedIndexesByRow[rowIndex]
        local runStart = nil
        for laneIndex = 1, geometry.lanes do
            if failedIndexes[laneIndex] then
                processSuccessfulRun(rowIndex, runStart, laneIndex - 1)
                runStart = nil
            else
                runStart = runStart or laneIndex
            end
        end
        processSuccessfulRun(rowIndex, runStart, geometry.lanes)
    end

    workArea.lastPickupLiters = pickupSum
    workArea.lastPickUpLiters = pickUpSum
    workArea.pickupParticlesActive = pickupParticlesActive
    workArea.pickedUpLiters = pickedUpSum
    workArea.lastDroppedLiters = droppedSum
    spec.surfacePatchDropoutStatus = string.format(
        "islands skipped %d/%d cells in %d run(s)",
        failedCount, totalCells, processedRuns
    )
    if spec.surfacePatchDropoutLogged ~= true then
        spec.surfacePatchDropoutLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Surface patch dropout active: vehicle=%s profile=%s target=%.3f failed=%d/%d runs=%d speed=%.2f shop=%.2f",
            self.getName ~= nil and self:getName() or tostring(self.configFileName),
            profileName,
            failureFraction,
            failedCount,
            totalCells,
            processedRuns,
            speed,
            rated
        )
    end
    markActualWork(realAreaSum, pickUpSum)
    return realAreaSum, totalAreaSum, processedAreas
end

-- Executes an additional action only on the selected islands of a surface
-- profile. Unlike processSurfacePatchDropoutArea, selected lanes are the
-- affected result rather than the skipped result. This keeps destructive
-- secondary failures independent from the primary work-dropout adapter.
local function applySurfacePatchActionArea(
        vehicle, workArea, profileName, actionFunc)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    local cfg = TerraLogicDropoutManager:getProfile(profileName)
    local modEnabled = TerraLogicMain == nil
        or TerraLogicMain.enabled ~= false
    if spec == nil or cfg == nil or cfg.enabled ~= true
        or not vehicle.isServer or not modEnabled
        or not getArePhysicalDropoutsEnabled()
        or actionFunc == nil then
        return 0, 0
    end

    local speed = vehicle.getLastSpeed ~= nil
        and math.abs(tonumber(vehicle:getLastSpeed(true)) or 0) or 0
    local rated = math.max(tonumber(spec.ratedSpeed) or 0, 0)
    local affectedFraction =
        TerraLogicDropoutManager:getSurfacePatchFailureFraction(
            profileName, speed, rated)
    spec.surfaceDamageProfile = profileName
    spec.surfaceDamageTargetFraction = affectedFraction
    spec.surfaceDamageChangedPixels = 0
    if affectedFraction <= 0 then
        spec.surfaceDamageStatus = "below destructive overspeed"
        spec.surfaceDamageIslandLanes = 0
        return 0, 0
    end

    local geometry = getWorkAreaPatternGeometry(
        workArea,
        cfg.patternLaneWidthM or 0.40,
        cfg.maximumPatternLanes or 32,
        true
    )
    if geometry == nil then
        spec.surfaceDamageStatus = "invalid work area"
        return 0, 0
    end
    local lanes = {}
    for laneIndex = 1, geometry.lanes do
        lanes[laneIndex] = getPatternLane(geometry, laneIndex)
    end
    local affectedIndexes, affectedCount =
        TerraLogicDropoutManager:getSurfacePatchFailedLanes(
            profileName, lanes, affectedFraction)
    spec.surfaceDamageIslandLanes = affectedCount
    spec.surfaceDamageTotalLanes = geometry.lanes
    if affectedCount == 0 then
        spec.surfaceDamageStatus = "no destructive island in current pass"
        return 0, 0
    end

    local changedPixels, actionRuns = 0, 0
    local runStart = nil
    local function processAffectedRun(runEnd)
        if runStart == nil then return end
        local lane = getPatternLaneRange(geometry, runStart, runEnd)
        changedPixels = changedPixels
            + math.max(tonumber(actionFunc(vehicle, lane, workArea)) or 0, 0)
        actionRuns = actionRuns + 1
        runStart = nil
    end
    for laneIndex = 1, geometry.lanes do
        if affectedIndexes[laneIndex] then
            runStart = runStart or laneIndex
        else
            processAffectedRun(laneIndex - 1)
        end
    end
    processAffectedRun(geometry.lanes)
    spec.surfaceDamageChangedPixels = changedPixels
    spec.surfaceDamageStatus = string.format(
        "crop damage %d/%d lanes in %d run(s)",
        affectedCount, geometry.lanes, actionRuns)
    if changedPixels > 0 and spec.surfaceDamageLogged ~= true then
        spec.surfaceDamageLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Destructive weed-tool dropout active: vehicle=%s profile=%s target=%.3f lanes=%d/%d changed=%d speed=%.2f shop=%.2f",
            vehicle.getName ~= nil and vehicle:getName()
                or tostring(vehicle.configFileName),
            profileName,
            affectedFraction,
            affectedCount,
            geometry.lanes,
            changedPixels,
            speed,
            rated
        )
    end
    return changedPixels, affectedCount
end

local function getSurfaceDamageGroundAngle(lane)
    local mission = g_currentMission
    if lane == nil or mission == nil or mission.fieldGroundSystem == nil
        or FSDensityMapUtil == nil
        or FSDensityMapUtil.convertToDensityMapAngle == nil then
        return 0
    end
    local dx = lane.heightX - lane.startX
    local dz = lane.heightZ - lane.startZ
    if math.abs(dx) + math.abs(dz) < 0.0001 then
        return 0
    end
    return FSDensityMapUtil.convertToDensityMapAngle(
        MathUtil.getYRotationFromDirection(dx, dz),
        mission.fieldGroundSystem:getGroundAngleMaxValue()
    )
end

local function getSurfaceDamageFruitType(lane)
    if lane == nil or FSDensityMapUtil == nil
        or FSDensityMapUtil.getFruitTypeIndexAtWorldPos == nil then
        return nil
    end
    -- Require an actual standing crop before changing the ground. Several
    -- nearby samples make narrow row crops reliable without scanning every
    -- fruit type or density pixel.
    local points = {
        {lane.centerX, lane.centerZ},
        {(lane.startX + lane.widthX) * 0.5,
            (lane.startZ + lane.widthZ) * 0.5},
        {(lane.startX + lane.heightX) * 0.5,
            (lane.startZ + lane.heightZ) * 0.5},
        {(lane.widthX + lane.heightX) * 0.5,
            (lane.widthZ + lane.heightZ) * 0.5}
    }
    for _, point in ipairs(points) do
        local fruitTypeIndex = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(
            point[1], point[2])
        if fruitTypeIndex ~= nil
            and (FruitType == nil or FruitType.UNKNOWN == nil
                or fruitTypeIndex ~= FruitType.UNKNOWN) then
            return fruitTypeIndex
        end
    end
    return nil
end

local function applyWeederCropDamage(vehicle, workArea, profileName)
    return applySurfacePatchActionArea(
        vehicle, workArea, profileName,
        function(tool, lane, sourceWorkArea)
            if getSurfaceDamageFruitType(lane) == nil then
                return 0
            end
            local changed = FSDensityMapUtil.updateCultivatorArea(
                lane.startX, lane.startZ,
                lane.widthX, lane.widthZ,
                lane.heightX, lane.heightZ,
                false,
                true,
                getSurfaceDamageGroundAngle(lane),
                nil,
                false,
                true
            )
            changed = math.max(tonumber(changed) or 0, 0)
            if changed > 0 and TerraLogicQualityManager ~= nil
                and TerraLogicQualityManager.invalidateSoilDamageWorkArea
                    ~= nil then
                local nodes = getQualityPatternWorkArea(
                    tool.spec_terraLogic, tool, lane)
                local damageWorkArea = copyWorkAreaWithPatternNodes(
                    sourceWorkArea, nodes)
                TerraLogicQualityManager:invalidateSoilDamageWorkArea(
                    damageWorkArea, tool)
            end
            return changed
        end
    )
end

-- Converts processed surface-patch runs into per-geometry ledger writes while
-- preserving the exact successful-area total reported by Vanilla/PF.
local function getDropoutLedgerAreas(
        processedAreas, fallbackWorkArea, successfulArea)
    local entries = processedAreas
    if entries == nil then
        entries = {{workArea = fallbackWorkArea, realArea = 0, totalArea = 0}}
    elseif #entries == 0 then
        -- A physical dropout pass can legitimately reject every generated
        -- run. Never turn that into a full-width quality-ledger stamp.
        return entries
    end
    local targetArea = math.max(tonumber(successfulArea) or 0, 0)
    local weightSum = 0
    for _, entry in ipairs(entries) do
        entry.terraLogicWeight = math.max(
            tonumber(entry.realArea) or 0,
            tonumber(entry.totalArea) or 0,
            0
        )
        weightSum = weightSum + entry.terraLogicWeight
    end
    for _, entry in ipairs(entries) do
        if targetArea <= 0 then
            entry.terraLogicSuccessfulArea = 0
        elseif weightSum > 0 then
            entry.terraLogicSuccessfulArea = targetArea
                * entry.terraLogicWeight / weightSum
        else
            entry.terraLogicSuccessfulArea = targetArea / #entries
        end
    end
    return entries
end

local function getDropoutLedgerWorkArea(vehicle, entry)
    if entry ~= nil and entry.lane ~= nil
        and vehicle ~= nil and vehicle.spec_terraLogic ~= nil then
        -- Surface runs reuse one lightweight node triplet during Vanilla
        -- processing. Restore the saved geometry immediately before each
        -- delayed quality-ledger write so every run stamps its own cells.
        local nodes = getQualityPatternWorkArea(
            vehicle.spec_terraLogic, vehicle, entry.lane)
        entry.workArea.start = nodes.start
        entry.workArea.width = nodes.width
        entry.workArea.height = nodes.height
    end
    return entry ~= nil and entry.workArea or nil
end

function TerraLogic:processMowerArea(superFunc, workArea, dt)
    return self:processSurfacePatchDropoutArea(
        superFunc, workArea, dt, "mowerPatch"
    )
end

function TerraLogic:processWindrowerArea(superFunc, workArea, dt)
    return self:processSurfacePatchDropoutArea(
        superFunc, workArea, dt, "windrowerPatch"
    )
end

function TerraLogic:processTedderArea(superFunc, workArea, dt)
    return self:processSurfacePatchDropoutArea(
        superFunc, workArea, dt, "tedderPatch"
    )
end

function TerraLogic:processBalerArea(superFunc, workArea, dt)
    local lastFillEffectType = nil
    local function processPickupArea(vehicle, area, deltaTime)
        local pickedUpLiters, totalLiters = superFunc(vehicle, area, deltaTime)
        local balerSpec = vehicle.spec_baler
        if balerSpec ~= nil and FillType ~= nil
            and balerSpec.fillEffectType ~= nil
            and balerSpec.fillEffectType ~= FillType.UNKNOWN then
            lastFillEffectType = balerSpec.fillEffectType
        end
        return pickedUpLiters, totalLiters
    end
    local pickedUpLiters, totalLiters = self:processSurfacePatchDropoutArea(
        processPickupArea, workArea, dt, "balerPatch"
    )
    if lastFillEffectType ~= nil and self.spec_baler ~= nil then
        self.spec_baler.fillEffectType = lastFillEffectType
    end
    -- FS25 returns picked and total pickup liters. Preserve both values after
    -- segmentation; the specialization-wide accumulator remains Vanilla's
    -- sole source for bale fill, so repeated cleanup passes cannot duplicate.
    return pickedUpLiters, totalLiters
end

function TerraLogic:processForageWagonArea(superFunc, workArea, dt)
    return self:processSurfacePatchDropoutArea(
        superFunc, workArea, dt, "loaderWagonPatch"
    )
end

-- Mechanical impact failures use the same WorkArea segmentation as seed and
-- application quality, but they are driven by a latched event state rather
-- than a continuously sampled quality value. Keeping this adapter generic
-- means cultivator tines and future application patterns only need a profile
-- plus a specialization wrapper, not another geometry implementation.
function TerraLogic:processImpactDropoutArea(
        superFunc, workArea, dt, profileName)
    local spec = self.spec_terraLogic
    local cfg = TerraLogicDropoutManager:getProfile(profileName)
    local state = spec ~= nil and spec.impactDropoutState or nil
    local modEnabled = TerraLogicMain == nil
        or TerraLogicMain.enabled ~= false
    if not modEnabled or not getArePhysicalDropoutsEnabled() or cfg == nil then
        if spec ~= nil then
            spec.impactDropoutFailedNormalized = nil
        end
        return superFunc(self, workArea, dt)
    end

    local localGeometry = getWorkAreaPatternGeometry(
        workArea,
        cfg.segmentWidthM or 0.75,
        cfg.maximumPatternLanes or 24,
        true
    )
    if localGeometry == nil then
        return superFunc(self, workArea, dt)
    end

    local geometry = localGeometry
    if cfg.useCombinedPlowWidth == true then
        geometry = getCombinedPlowPatternGeometry(self, cfg) or localGeometry
    end

    local failedLanes, failedIndexes =
        TerraLogicDropoutManager:getImpactFailedLanes(
            profileName, state, geometry
        )
    spec.impactDropoutFailedLanes = #failedLanes
    spec.impactDropoutTotalLanes = geometry.lanes
    spec.impactDropoutFailedNormalized = {}
    for _, failedLaneIndex in ipairs(failedLanes) do
        spec.impactDropoutFailedNormalized[#spec.impactDropoutFailedNormalized + 1] =
            (failedLaneIndex - 0.5) / math.max(geometry.lanes, 1)
    end
    if #failedLanes == 0 then
        spec.impactDropoutFailedNormalized = nil
        return superFunc(self, workArea, dt)
    end
    if profileName == "plowImpact" and spec.plowDropoutAppliedLogged ~= true then
        spec.plowDropoutAppliedLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Plow dropout applied: vehicle=%s tier=%s failed=%d/%d WorkAreas=%d",
            self.getName ~= nil and self:getName() or tostring(self.configFileName),
            tostring(state.lastTier or "unknown"),
            #failedLanes,
            geometry.lanes,
            geometry.areaCount or 1
        )
    end

    local realAreaSum, totalAreaSum = 0, 0
    if geometry.axisX ~= nil then
        local successfulRanges = getSuccessfulGlobalPlowRanges(
            localGeometry, geometry, failedIndexes
        )
        if successfulRanges ~= nil then
            for _, range in ipairs(successfulRanges) do
                local lane = getPatternNormalizedRange(
                    localGeometry, range.u0, range.u1
                )
                if lane ~= nil then
                    local nodes = getQualityPatternWorkArea(spec, self, lane)
                    local laneWorkArea = copyWorkAreaWithPatternNodes(workArea, nodes)
                    local realArea, totalArea = superFunc(self, laneWorkArea, dt)
                    realAreaSum = realAreaSum + (tonumber(realArea) or 0)
                    totalAreaSum = totalAreaSum + (tonumber(totalArea) or 0)
                end
            end
            spec.impactDropoutStatus = string.format(
                "%s: %d/%d global share corridors (%d WorkAreas)",
                state.lastTier or "impact",
                #failedLanes,
                geometry.lanes,
                geometry.areaCount or 1
            )
            return realAreaSum, totalAreaSum
        end
    end

    local runStart = nil
    local function processSuccessfulRun(runEnd)
        if runStart == nil then
            return
        end
        local lane = getPatternLaneRange(geometry, runStart, runEnd)
        local nodes = getQualityPatternWorkArea(spec, self, lane)
        local laneWorkArea = copyWorkAreaWithPatternNodes(workArea, nodes)
        local realArea, totalArea = superFunc(self, laneWorkArea, dt)
        realAreaSum = realAreaSum + (tonumber(realArea) or 0)
        totalAreaSum = totalAreaSum + (tonumber(totalArea) or 0)
        runStart = nil
    end

    for laneIndex = 1, geometry.lanes do
        if failedIndexes[laneIndex] then
            processSuccessfulRun(laneIndex - 1)
        else
            runStart = runStart or laneIndex
        end
    end
    processSuccessfulRun(geometry.lanes)
    spec.impactDropoutStatus = string.format(
        "%s: %d/%d segments tripped",
        state.lastTier or "impact",
        #failedLanes,
        geometry.lanes
    )
    return realAreaSum, totalAreaSum
end

local function getIsOverSpeedPlowEffectAllowed(binding)
    local spec = binding ~= nil and binding.spec or nil
    if spec == nil
        or (TerraLogicMain ~= nil and TerraLogicMain.enabled == false)
        or not getArePhysicalDropoutsEnabled() then
        return true
    end
    local failures = spec.impactDropoutFailedNormalized
    if failures == nil or #failures == 0 then
        return true
    end
    local effectPosition = (binding.index - 0.5) / math.max(binding.count, 1)
    local halfShare = 0.55 / math.max(binding.count, 1)
    for _, failedPosition in ipairs(failures) do
        if math.abs(effectPosition - failedPosition) <= halfShare then
            return false
        end
    end
    return true
end

-- Plows such as the Juwel expose one PlowMotionPathEffect per physical share.
-- Bind a start restriction to each of those effects and stop only the effect
-- matching a failed density-map row. Unsupported mod plows simply keep their
-- original visuals; no effect table is modified or replaced.
function TerraLogic:updateOverSpeedPlowEffects()
    local spec = self.spec_terraLogic
    if spec == nil or self.spec_plow == nil or not self.isClient then
        return
    end

    if spec.plowVisualEffectBindingAttempted ~= true then
        local workParticles = self.spec_workParticles
        if workParticles == nil or workParticles.effects == nil then
            spec.plowVisualEffectStatus = "no WorkParticles effects"
            spec.plowVisualEffectBindingAttempted = true
            return
        end
        if PlowMotionPathEffect == nil then
            spec.plowVisualEffectStatus = "PlowMotionPathEffect unavailable"
            spec.plowVisualEffectBindingAttempted = true
            return
        end

        local bindings = {}
        local dropoutCfg = TerraLogicDropoutManager:getProfile(
            spec.impactDropoutProfile
        )
        local combinedGeometry = dropoutCfg ~= nil
            and getCombinedPlowPatternGeometry(self, dropoutCfg) or nil
        local estimatedShareCount = combinedGeometry ~= nil and math.max(
            math.floor(
                combinedGeometry.widthM
                    / math.max(tonumber(dropoutCfg.segmentWidthM) or 0.5, 0.25)
                + 0.5
            ),
            1
        ) or nil
        for _, effectGroup in ipairs(workParticles.effects) do
            local plowEffects = {}
            for _, effectObject in ipairs(effectGroup.effect or {}) do
                if effectObject ~= nil and effectObject.isa ~= nil
                    and effectObject:isa(PlowMotionPathEffect) then
                    plowEffects[#plowEffects + 1] = effectObject
                end
            end
            -- Configurable plows may load the extension's extra effect even
            -- while that share is hidden. Limit bindings to the share count
            -- implied by the active WorkArea width (e.g. Juwel 4 vs 4+1).
            local count = estimatedShareCount ~= nil
                and math.min(#plowEffects, estimatedShareCount)
                or #plowEffects
            for index = 1, count do
                local effectObject = plowEffects[index]
                local binding = {
                    spec = spec,
                    effect = effectObject,
                    index = index,
                    count = count
                }
                if effectObject.addStartRestriction ~= nil then
                    effectObject:addStartRestriction(
                        getIsOverSpeedPlowEffectAllowed,
                        binding
                    )
                    bindings[#bindings + 1] = binding
                end
            end
        end
        spec.plowVisualEffectBindings = bindings
        spec.plowVisualEffectBindingAttempted = true
        spec.plowVisualEffectStatus = #bindings > 0
            and string.format("%d per-share motion effects bound", #bindings)
            or "no per-share motion effects found"
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Plow visual binding: vehicle=%s status=%s",
            self.getName ~= nil and self:getName() or tostring(self.configFileName),
            spec.plowVisualEffectStatus
        )
    end

    for _, binding in ipairs(spec.plowVisualEffectBindings or {}) do
        if not getIsOverSpeedPlowEffectAllowed(binding)
            and binding.effect.isRunning ~= nil
            and binding.effect:isRunning()
            and binding.effect.stop ~= nil then
            binding.effect:stop()
        end
    end
end

-- Plow quality uses a deferred post-pass, like the proven seed dropout path.
-- Vanilla first performs every overlapping diagonal plow write. World-raster
-- noise cells are retained until they lie safely behind the guarded union of
-- all shares and WorkAreas, then downgraded exactly once. Mechanical stone
-- events may still affect a complete physical share corridor.
function TerraLogic:applyOverSpeedPlowQualityArea(
        workArea, previousPlowLevel, previousPlowLevelSource,
        deferredVisualCandidates, deferredVisualCoverage)
    local spec = self.spec_terraLogic
    local profileName = spec ~= nil and spec.impactDropoutProfile or nil
    local cfg = profileName ~= nil
        and TerraLogicDropoutManager:getProfile(profileName) or nil
    local state = spec ~= nil and spec.impactDropoutState or nil
    local modEnabled = TerraLogicMain == nil
        or TerraLogicMain.enabled ~= false
    -- Visual furrow quality is continuous and must not depend on a currently
    -- active stone/throw dropout. The old state==nil guard accidentally made
    -- twisted textures appear only while a mechanical event was latched.
    if not modEnabled or cfg == nil then
        if spec ~= nil then
            spec.impactDropoutFailedNormalized = nil
        end
        return 0
    end

    local localGeometry = getWorkAreaPatternGeometry(
        workArea,
        cfg.segmentWidthM or 0.5,
        cfg.maximumPatternLanes or 48,
        true
    )
    if localGeometry == nil then
        return 0
    end
    local params = self.spec_plow ~= nil
        and self.spec_plow.workAreaParameters or nil
    local mission = g_currentMission
    local angleCount = mission ~= nil and mission.fieldGroundSystem ~= nil
        and math.max(
            math.floor(
                tonumber(mission.fieldGroundSystem:getGroundAngleMaxValue()) or 0
            ) + 1,
            1
        ) or 1
    local currentSpeed = math.abs(self:getLastSpeed(true) or 0)
    local plowTextureQuality =
        TerraLogicDropoutManager:getPlowTextureQuality(
            profileName,
            currentSpeed,
            spec.optimalSpeed or spec.ratedSpeed,
            spec.ratedSpeed,
            angleCount
        )
    local densityMetrics = getTerrainDetailMetrics(
        cfg.referenceDensityPixelSizeM
    )
    spec.plowDensityTerrainSizeM = densityMetrics.terrainSizeM
    spec.plowDensityDetailMapSize = densityMetrics.detailMapSize
    spec.plowDensityPixelSizeM = densityMetrics.pixelSizeM
    spec.plowDensityLinearScale = densityMetrics.linearScale
    spec.plowDensityResolutionSource = densityMetrics.source
    spec.plowDropoutResolutionFactor = getPlowDropoutResolutionFactor(
        cfg,
        densityMetrics
    )
    local restorePlowLevel = tonumber(previousPlowLevel)
    if restorePlowLevel == nil and mission ~= nil
        and mission.fieldGroundSystem ~= nil then
        local maximumValue = mission.fieldGroundSystem:getMaxValue(
            FieldDensityMap.PLOW_LEVEL
        )
        restorePlowLevel = mission.missionInfo ~= nil
            and mission.missionInfo.plowingRequiredEnabled == true
            and 0 or maximumValue
        previousPlowLevelSource = "setting fallback"
        if spec.plowQualitySnapshotFallbackLogged ~= true then
            spec.plowQualitySnapshotFallbackLogged = true
            Logging.warning(
                "[FS25_TerraLogic] Could not sample previous PLOW_LEVEL for %s; using %s fallback level %s",
                self.getName ~= nil and self:getName()
                    or tostring(self.configFileName),
                mission.missionInfo ~= nil
                    and tostring(mission.missionInfo.plowingRequiredEnabled)
                    or "unknown",
                tostring(restorePlowLevel)
            )
        end
    end
    previousPlowLevel = restorePlowLevel
    local plowLevelModifier = self.isServer and getPlowLevelMapContext(self)
        or nil
    local successfulPlowLevel = FieldDensityMap ~= nil
        and FieldDensityMap.PLOW_LEVEL ~= nil
        and mission ~= nil
        and mission.fieldGroundSystem ~= nil
        and mission.fieldGroundSystem:getMaxValue(FieldDensityMap.PLOW_LEVEL)
        or nil
    local plowLevelPaddingM = math.max(
        tonumber(cfg.plowLevelRasterPaddingFallbackM) or 0.25,
        densityMetrics.pixelSizeM * 0.20
    )
    local ratedSpeed = math.max(tonumber(spec.ratedSpeed) or 0, 0)
    -- Continuous density-raster noise is intentionally disabled. Overspeed
    -- quality now arrives as sparse distance-triggered CULTIVATED patches
    -- in onEndWorkAreaProcessing. This function retains only the established
    -- medium/big stone-impact rendering path.
    local worldStableFailureFraction = 0
    spec.plowWorldStableFailureFraction = worldStableFailureFraction
    local visualPixels, visualCells, visualAreas = 0, 0, {}
    if plowLevelModifier ~= nil and successfulPlowLevel ~= nil then
        for _, visualArea in ipairs(visualAreas) do
            local protectedArea = expandPatternLaneWorld(
                visualArea,
                plowLevelPaddingM
            )
            plowLevelModifier:setParallelogramWorldCoords(
                protectedArea.startX, protectedArea.startZ,
                protectedArea.widthX, protectedArea.widthZ,
                protectedArea.heightX, protectedArea.heightZ,
                DensityCoordType.POINT_POINT_POINT
            )
            -- This is only a surface-quality blemish. The plow did pass this
            -- cell, so it must be marked as successfully plowed even when the
            -- pre-pass field required plowing. Only genuine dropouts below
            -- restore the sampled pre-pass PLOW_LEVEL.
            plowLevelModifier:executeSet(successfulPlowLevel)
        end
    end
    spec.plowVisualTwistedFraction = 0
    spec.plowVisualMaximumDeviationSteps =
        plowTextureQuality.maximumDeviationSteps
    spec.plowVisualScatteredPixels = visualPixels
    spec.plowVisualScatteredCells = visualCells
    -- Mechanical medium/big stone impacts retain their physical share-lane
    -- behaviour. General overspeed quality no longer enters this lane/raster
    -- path and therefore cannot multiply WorkArea writes every frame.
    local geometry = localGeometry
    if worldStableFailureFraction > 0 then
        spec.plowQualityLatch = nil
        spec.plowQualityProtectionMode = "deferred density-raster subset"
        spec.plowQualityProtectionHoldM = 0
    else
        spec.plowQualityLatch = nil
        spec.plowQualityProtectionMode = "inactive"
        spec.plowQualityProtectionHoldM = 0
    end

    local failedIndexes = {}
    local visualImpactIndexes = {}
    if state ~= nil then
        local impactFailedLanes =
            TerraLogicDropoutManager:getImpactFailedLanes(
                profileName, state, geometry
            )
        for _, laneIndex in ipairs(impactFailedLanes) do
            if plowTextureQuality.gameplayDropoutsAllowed then
                failedIndexes[laneIndex] = true
            else
                visualImpactIndexes[laneIndex] = true
            end
        end
    end

    -- Below/equal to shop speed, a stone may still disturb the surface, but
    -- it must not create a gameplay-level Needs Plowing gap. Render the
    -- cultivated-looking impact spot and explicitly preserve successful
    -- plowing. Above shop speed the same latched lanes join failedIndexes and
    -- restore the sampled pre-pass PLOW_LEVEL in the normal failure pass.
    local visualImpactPixels = 0
    local visualImpactLaneCount = 0
    if self.isServer and next(visualImpactIndexes) ~= nil then
        for laneIndex = 1, geometry.lanes do
            if visualImpactIndexes[laneIndex] then
                visualImpactLaneCount = visualImpactLaneCount + 1
                local lane = getPatternLane(geometry, laneIndex)
                if lane ~= nil and params ~= nil then
                    local changed = FSDensityMapUtil.updateCultivatorArea(
                        lane.startX, lane.startZ,
                        lane.widthX, lane.widthZ,
                        lane.heightX, lane.heightZ,
                        not params.limitToField,
                        params.limitFruitDestructionToField,
                        params.angle,
                        nil,
                        false,
                        true
                    )
                    visualImpactPixels = visualImpactPixels
                        + (tonumber(changed) or 0)
                    if plowLevelModifier ~= nil
                        and successfulPlowLevel ~= nil then
                        local protectedLane = expandPatternLaneWorld(
                            lane,
                            plowLevelPaddingM
                        )
                        plowLevelModifier:setParallelogramWorldCoords(
                            protectedLane.startX, protectedLane.startZ,
                            protectedLane.widthX, protectedLane.widthZ,
                            protectedLane.heightX, protectedLane.heightZ,
                            DensityCoordType.POINT_POINT_POINT
                        )
                        plowLevelModifier:executeSet(successfulPlowLevel)
                    end
                end
            end
        end
    end
    spec.impactVisualOnlyLanes = visualImpactLaneCount
    spec.impactVisualOnlyPixels = visualImpactPixels
    spec.plowVisualScatteredPixels =
        (spec.plowVisualScatteredPixels or 0) + visualImpactPixels
    local failedLanes = {}
    for laneIndex = 1, geometry.lanes do
        if failedIndexes[laneIndex] then
            failedLanes[#failedLanes + 1] = laneIndex
        end
    end
    spec.impactDropoutFailedLanes = #failedLanes
    spec.impactDropoutTotalLanes = geometry.lanes
    spec.plowMixedCultivatedPixels = 0
    spec.plowMixedTwistedPixels = 0
    spec.impactDropoutFailedNormalized = {}
    for _, failedLaneIndex in ipairs(failedLanes) do
        spec.impactDropoutFailedNormalized[#spec.impactDropoutFailedNormalized + 1] =
            (failedLaneIndex - 0.5) / math.max(geometry.lanes, 1)
    end
    if #failedLanes == 0 then
        spec.impactDropoutFailedNormalized = nil
        spec.impactDropoutStatus = worldStableFailureFraction > 0
            and string.format(
                "deferred raster failures: %.2f%% gameplay subset of %.2f%% noise",
                worldStableFailureFraction * 100,
                plowTextureQuality.twistedFraction * 100
            ) or (visualImpactLaneCount > 0
                and string.format(
                    "stone visual only below shop: %d rows, %d px; plow level kept",
                    visualImpactLaneCount,
                    visualImpactPixels
                ) or "inactive / repair allowed")
        return visualImpactPixels
    end

    local failedRanges = {}
    for laneIndex = 1, geometry.lanes do
        if failedIndexes[laneIndex] then
            failedRanges[#failedRanges + 1] = {
                u0 = (laneIndex - 1) / geometry.lanes,
                u1 = laneIndex / geometry.lanes
            }
        end
    end

    local changedPixels = 0
    local scatteredPlowPixels = 0
    if self.isServer then
        for _, range in ipairs(failedRanges) do
            local localWidthM = math.sqrt(
                localGeometry.widthX * localGeometry.widthX
                    + localGeometry.widthZ * localGeometry.widthZ
            )
            local minimumRangeU = math.min(
                math.max(
                    tonumber(cfg.minimumPostPassWidthM) or 0.85,
                    densityMetrics.pixelSizeM
                )
                    / math.max(localWidthM, 0.01),
                1
            )
            local rangeCenter = (range.u0 + range.u1) * 0.5
            local expandedU0 = math.max(
                math.min(range.u0, rangeCenter - minimumRangeU * 0.5),
                0
            )
            local expandedU1 = math.min(
                math.max(range.u1, rangeCenter + minimumRangeU * 0.5),
                1
            )
            local lane = getPatternNormalizedRange(
                localGeometry,
                expandedU0,
                expandedU1
            )
            if lane ~= nil and params ~= nil then
                local changed = FSDensityMapUtil.updateCultivatorArea(
                    lane.startX, lane.startZ,
                    lane.widthX, lane.widthZ,
                    lane.heightX, lane.heightZ,
                    not params.limitToField,
                    params.limitFruitDestructionToField,
                    params.angle,
                    nil,
                    false,
                    true
                )
                changedPixels = changedPixels + (tonumber(changed) or 0)

                -- Restore the visually successful v59 mixture: the failed
                -- corridor first becomes cultivated, then deterministic cells
                -- are written back as PLOWED with speed-dependent angles.
                local scatter = cfg.plowTextureScatter
                if scatter ~= nil and scatter.enabled == true then
                    local lengthX = lane.heightX - lane.startX
                    local lengthZ = lane.heightZ - lane.startZ
                    local lengthM = math.sqrt(
                        lengthX * lengthX + lengthZ * lengthZ
                    )
                    local cellLength = math.max(
                        tonumber(scatter.cellLengthM) or 1,
                        densityMetrics.pixelSizeM
                    )
                    local cellCount = math.max(
                        math.ceil(lengthM / cellLength),
                        1
                    )
                    local maximumDeviationSteps = math.max(
                        tonumber(plowTextureQuality.maximumDeviationSteps) or 0,
                        1
                    )
                    local baseAngle = math.floor(
                        (tonumber(params.angle) or 0) + 0.5
                    ) % angleCount
                    local plowFraction = math.clamp(
                        tonumber(scatter.randomPlowFraction) or 0.40,
                        0,
                        1
                    )
                    for cellIndex = 1, cellCount do
                        local v0 = (cellIndex - 1) / cellCount
                        local v1 = cellIndex / cellCount
                        local cell = getPatternSubArea(lane, 0, 1, v0, v1)
                        local pattern =
                            TerraLogicDropoutManager:getPatternValue(
                                cell.centerX,
                                cell.centerZ,
                                cellIndex,
                                (tonumber(scatter.patternSalt) or 0) + 50000,
                                cellLength
                            )
                        if pattern < plowFraction then
                            local anglePattern =
                                TerraLogicDropoutManager:getPatternValue(
                                    cell.centerX,
                                    cell.centerZ,
                                    cellIndex,
                                    (tonumber(scatter.angleSalt) or 0) + 50000,
                                    cellLength
                                )
                            local signedAngle = anglePattern * 2 - 1
                            local angleOffset = math.min(
                                math.floor(
                                    math.abs(signedAngle)
                                        * maximumDeviationSteps
                                ) + 1,
                                maximumDeviationSteps
                            )
                            if signedAngle < 0 then
                                angleOffset = -angleOffset
                            end
                            local randomAngle = (baseAngle + angleOffset)
                                % angleCount
                            local plowed = FSDensityMapUtil.updatePlowArea(
                                cell.startX, cell.startZ,
                                cell.widthX, cell.widthZ,
                                cell.heightX, cell.heightZ,
                                not params.limitToField,
                                params.limitFruitDestructionToField,
                                randomAngle,
                                false,
                                true
                            )
                            scatteredPlowPixels = scatteredPlowPixels
                                + (tonumber(plowed) or 0)
                        end
                    end
                end
                if plowLevelModifier ~= nil then
                    local plowLevelLane = expandPatternLaneWorld(
                        lane,
                        plowLevelPaddingM
                    )
                    plowLevelModifier:setParallelogramWorldCoords(
                        plowLevelLane.startX, plowLevelLane.startZ,
                        plowLevelLane.widthX, plowLevelLane.widthZ,
                        plowLevelLane.heightX, plowLevelLane.heightZ,
                        DensityCoordType.POINT_POINT_POINT
                    )
                    plowLevelModifier:executeSet(restorePlowLevel)
                end
            end
        end
    end

    spec.impactDropoutStatus = string.format(
        "protected mix: %.2f%% target, %d/%d rows, cultivated=%d px, twistedPlow=%d px, restore=%s",
        worldStableFailureFraction * 100,
        #failedLanes,
        geometry.lanes,
        changedPixels,
        scatteredPlowPixels,
        tostring(previousPlowLevel)
    )
    spec.plowMixedCultivatedPixels = changedPixels
    spec.plowMixedTwistedPixels = scatteredPlowPixels
    if spec.plowDropoutAppliedLogged ~= true then
        spec.plowDropoutAppliedLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Plow protected mixed post-pass: vehicle=%s source=%s targetFraction=%.4f failed=%d/%d cultivatedPixels=%d twistedPlowPixels=%d angleSteps=%d geometryWidth=%.2f densityPixel=%.3f plowPadding=%.3f previousPlowLevel=%s snapshot=%s",
            self.getName ~= nil and self:getName() or tostring(self.configFileName),
            tostring(state ~= nil and state.lastTier or "world-stable overspeed"),
            worldStableFailureFraction,
            #failedLanes,
            geometry.lanes,
            changedPixels,
            scatteredPlowPixels,
            plowTextureQuality.maximumDeviationSteps,
            geometry.widthM or 0,
            densityMetrics.pixelSizeM,
            plowLevelPaddingM,
            tostring(previousPlowLevel),
            tostring(previousPlowLevelSource or "unknown")
        )
    end
    return changedPixels + scatteredPlowPixels
end

function TerraLogic:processPlowArea(superFunc, workArea, dt)
    local realArea, totalArea = self:processOverSpeedStoneArea(superFunc, workArea, dt)
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local quality, yieldPenalty = TerraLogicQualityManager:getWorkQualityModel(
        self, speed, "soilPlow")
    local spec = self.spec_terraLogic
    local balance = TerraLogic.getWorkQualityBalance(self, "soilPlow")
    TerraLogicQualityManager:recordWorkArea(
        workArea, "soilPlow", quality, realArea,
        balance.weight, balance.maxPenalty, self, yieldPenalty)
    return realArea, totalArea
end

local function applyPendingIrregularPlowEvents(vehicle, pending, profile)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    local cfg = profile ~= nil and profile.overspeedThrow or nil
    local pendingEvents = spec ~= nil
        and math.max(math.floor(spec.plowIrregularPendingEvents or 0), 0) or 0
    if vehicle == nil or not vehicle.isServer or spec == nil or cfg == nil
        or pendingEvents <= 0 or pending == nil or #pending == 0 then
        if spec ~= nil then
            spec.plowIrregularLastPassEvents = 0
            spec.plowIrregularLastPixels = 0
            spec.plowIrregularLastTwoPixelEvents = 0
        end
        return 0, 0
    end

    local densityMetrics = getTerrainDetailMetrics(
        profile.referenceDensityPixelSizeM
    )
    local rasterPixelM = math.max(
        tonumber(densityMetrics.pixelSizeM) or 0.5,
        0.05
    )
    local candidates = {}
    local totalWeight = 0
    for _, queued in ipairs(pending) do
        local geometry = getWorkAreaPatternGeometry(
            queued.workArea,
            profile.segmentWidthM or 0.5,
            profile.maximumPatternLanes or 48,
            true
        )
        if geometry ~= nil then
            local widthM = math.sqrt(
                geometry.widthX * geometry.widthX
                    + geometry.widthZ * geometry.widthZ
            )
            local lengthM = math.sqrt(
                geometry.heightX * geometry.heightX
                    + geometry.heightZ * geometry.heightZ
            )
            if widthM > 0.05 and lengthM > 0.02 then
                local weight = widthM * math.max(lengthM, rasterPixelM)
                totalWeight = totalWeight + weight
                candidates[#candidates + 1] = {
                    queued = queued,
                    geometry = geometry,
                    widthM = widthM,
                    lengthM = lengthM,
                    cumulativeWeight = totalWeight
                }
            end
        end
    end
    if #candidates == 0 or totalWeight <= 0 then
        spec.plowIrregularLastPassEvents = 0
        spec.plowIrregularLastPixels = 0
        return 0, 0
    end

    local params = vehicle.spec_plow ~= nil
        and vehicle.spec_plow.workAreaParameters or nil
    local currentSpeed = math.abs(vehicle:getLastSpeed(true) or 0)
    local ratedSpeed = math.max(tonumber(spec.ratedSpeed) or currentSpeed, 0.1)
    local eventLimit = math.max(
        math.floor(tonumber(cfg.maximumEventsPerWorkAreaPass) or 2),
        1
    )
    local eventCount = math.min(pendingEvents, eventLimit)
    local writtenEvents, changedPixels, twoPixelEvents = 0, 0, 0
    local plowLevelModifier = getPlowLevelMapContext(vehicle)
    local patchDensityPixels = math.max(
        math.floor(tonumber(cfg.patchDensityPixels) or 2),
        2
    )
    local terrainHalf = math.max(
        tonumber(densityMetrics.terrainSizeM) or 0,
        0
    ) * 0.5

    for _ = 1, eventCount do
        local placementSequence = (spec.plowSurfacePlacementSequence or 0) + 1
        spec.plowSurfacePlacementSequence = placementSequence
        local lateralSalt = tonumber(cfg.lateralSalt) or 41777
        local roll = TerraLogicDropoutManager:getPatternValue(
            placementSequence,
            0,
            0,
            lateralSalt + 101,
            1
        ) * totalWeight
        local selected = candidates[#candidates]
        for _, candidate in ipairs(candidates) do
            if roll <= candidate.cumulativeWeight then
                selected = candidate
                break
            end
        end
        if params ~= nil then
            -- Cycle through lateral bands before repeating one. A small
            -- deterministic offset inside the selected band avoids visible
            -- straight lanes while preventing random clustering on one side.
            local marginU = math.min(
                rasterPixelM * 1.5 / math.max(selected.widthM, rasterPixelM),
                0.45
            )
            local marginV = math.min(
                rasterPixelM * 1.5 / math.max(selected.lengthM, rasterPixelM),
                0.45
            )
            local lateralBandCount = math.clamp(
                math.floor(
                    selected.widthM / math.max(
                        tonumber(cfg.lateralBandWidthM) or 2,
                        rasterPixelM
                    )
                ),
                1,
                math.max(
                    math.floor(tonumber(cfg.maximumLateralBands) or 8),
                    1
                )
            )
            local lateralBandIndex = (placementSequence - 1) % lateralBandCount
            local lateralJitter = TerraLogicDropoutManager:getPatternValue(
                placementSequence,
                0,
                0,
                lateralSalt + 211,
                1
            )
            local rawU = (lateralBandIndex + lateralJitter) / lateralBandCount
            local u = math.clamp(rawU, marginU, 1 - marginU)
            local vPattern = TerraLogicDropoutManager:getPatternValue(
                placementSequence,
                0,
                0,
                lateralSalt + 307,
                1
            )
            local v = marginV + vPattern * math.max(1 - marginV * 2, 0)
            local centerX = selected.geometry.xs
                + selected.geometry.widthX * u
                + selected.geometry.heightX * v
            local centerZ = selected.geometry.zs
                + selected.geometry.widthZ * u
                + selected.geometry.heightZ * v
            local pixelX = math.floor(
                (centerX + terrainHalf) / rasterPixelM
            )
            local pixelZ = math.floor(
                (centerZ + terrainHalf) / rasterPixelM
            )
            local extendX = TerraLogicDropoutManager:getPatternValue(
                placementSequence,
                0,
                0,
                lateralSalt + 401,
                1
            ) < 0.5
            local pixelsX = extendX and patchDensityPixels or 1
            local pixelsZ = not extendX and patchDensityPixels or 1
            local startX = pixelX * rasterPixelM - terrainHalf
            local startZ = pixelZ * rasterPixelM - terrainHalf
            local patch = {
                startX = startX,
                startZ = startZ,
                widthX = startX + pixelsX * rasterPixelM,
                widthZ = startZ,
                heightX = startX,
                heightZ = startZ + pixelsZ * rasterPixelM
            }
            local changed = FSDensityMapUtil.updateCultivatorArea(
                patch.startX, patch.startZ,
                patch.widthX, patch.widthZ,
                patch.heightX, patch.heightZ,
                not params.limitToField,
                params.limitFruitDestructionToField,
                params.angle,
                nil,
                nil,
                true
            )
            changedPixels = changedPixels + (tonumber(changed) or 0)
            -- A cultivator surface write alone can remain hidden below the
            -- successful PLOW_LEVEL written by Vanilla. Restore the sampled
            -- pre-pass level on the exact same tiny raster patch so this is a
            -- genuine missed spot, without inventing a new plowing requirement.
            local restorePlowLevel = tonumber(
                selected.queued.previousPlowLevel
            )
            if plowLevelModifier ~= nil and restorePlowLevel ~= nil then
                plowLevelModifier:setParallelogramWorldCoords(
                    patch.startX, patch.startZ,
                    patch.widthX, patch.widthZ,
                    patch.heightX, patch.heightZ,
                    DensityCoordType.POINT_POINT_POINT
                )
                plowLevelModifier:executeSet(restorePlowLevel)
            end
            writtenEvents = writtenEvents + 1
            twoPixelEvents = twoPixelEvents + 1
        end
    end

    spec.plowIrregularPendingEvents = math.max(pendingEvents - eventCount, 0)
    spec.plowIrregularEventCount =
        (spec.plowIrregularEventCount or 0) + writtenEvents
    spec.impactDropoutThrowCount =
        (spec.impactDropoutThrowCount or 0) + writtenEvents
    spec.plowIrregularLastPassEvents = writtenEvents
    spec.plowIrregularLastPixels = changedPixels
    spec.plowIrregularLastGameplayFailures = writtenEvents
    spec.plowIrregularLastTwoPixelEvents = twoPixelEvents
    spec.plowDensityTerrainSizeM = densityMetrics.terrainSizeM
    spec.plowDensityDetailMapSize = densityMetrics.detailMapSize
    spec.plowDensityPixelSizeM = densityMetrics.pixelSizeM
    spec.plowDensityLinearScale = densityMetrics.linearScale
    spec.plowDensityResolutionSource = densityMetrics.source
    if writtenEvents > 0 then
        spec.plowSurfaceDiagnosticAttemptCount =
            (spec.plowSurfaceDiagnosticAttemptCount or 0) + writtenEvents
        local diagnosticLogCount = spec.plowSurfaceDiagnosticLogCount or 0
        if diagnosticLogCount < 20
            or spec.plowSurfaceDiagnosticAttemptCount % 50 < writtenEvents then
            spec.plowSurfaceDiagnosticLogCount = diagnosticLogCount + 1
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] Plow surface test: vehicle=%s speed=%.1f rated=%.1f events=%d changedPixels=%d rasterPixel=%.3fm pendingBefore=%d workAreas=%d",
                vehicle.getName ~= nil and vehicle:getName()
                    or tostring(vehicle.configFileName),
                currentSpeed,
                ratedSpeed,
                writtenEvents,
                changedPixels,
                rasterPixelM,
                pendingEvents,
                #pending
            )
        end
        spec.impactDropoutStatus = string.format(
            "overspeed surface: %d patch(es), %d extended, %d px",
            writtenEvents,
            twoPixelEvents,
            changedPixels
        )
    end
    return changedPixels, writtenEvents
end

local function applyPendingPlowStoneImpact(vehicle, pending, profile)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    local impact = spec ~= nil and spec.pendingPlowStoneImpact or nil
    if vehicle == nil or not vehicle.isServer or impact == nil
        or pending == nil or #pending == 0 then
        return 0
    end

    local candidates = {}
    local totalWidthM = 0
    for _, queued in ipairs(pending) do
        local geometry = getWorkAreaPatternGeometry(
            queued.workArea,
            profile ~= nil and profile.segmentWidthM or 0.5,
            profile ~= nil and profile.maximumPatternLanes or 48,
            true
        )
        if geometry ~= nil then
            local widthM = math.sqrt(
                geometry.widthX * geometry.widthX
                    + geometry.widthZ * geometry.widthZ
            )
            totalWidthM = totalWidthM + math.max(widthM, 0.01)
            candidates[#candidates + 1] = {
                queued = queued,
                geometry = geometry,
                cumulativeWidthM = totalWidthM
            }
        end
    end
    if #candidates == 0 then
        return 0
    end

    -- Weight WorkAreas by width so the patch position is uniform across the
    -- complete implement rather than biased toward narrow sub-WorkAreas.
    local widthRoll = math.random() * totalWidthM
    local selected = candidates[#candidates]
    for _, candidate in ipairs(candidates) do
        if widthRoll <= candidate.cumulativeWidthM then
            selected = candidate
            break
        end
    end
    local geometry = selected.geometry
    local densityMetrics = getTerrainDetailMetrics(
        profile ~= nil and profile.referenceDensityPixelSizeM or 0.5
    )
    local pixelM = math.max(tonumber(densityMetrics.pixelSizeM) or 0.5, 0.1)
    local swapAxes = math.random() < 0.5
    local patchWidthM = pixelM * (swapAxes and 2 or 1)
    local patchLengthM = pixelM * (swapAxes and 1 or 2)
    local centerX = geometry.xs + geometry.widthX * math.random()
        + geometry.heightX * math.random()
    local centerZ = geometry.zs + geometry.widthZ * math.random()
        + geometry.heightZ * math.random()
    local forwardX, _, forwardZ = localDirectionToWorld(
        vehicle.rootNode,
        0,
        0,
        1
    )
    local forwardLength = math.sqrt(
        forwardX * forwardX + forwardZ * forwardZ
    )
    if forwardLength < 0.001 then
        forwardX, forwardZ, forwardLength = 0, 1, 1
    end
    forwardX, forwardZ = forwardX / forwardLength,
        forwardZ / forwardLength
    local lateralX, lateralZ = -forwardZ, forwardX
    local startX = centerX - lateralX * patchWidthM * 0.5
        - forwardX * patchLengthM * 0.5
    local startZ = centerZ - lateralZ * patchWidthM * 0.5
        - forwardZ * patchLengthM * 0.5
    local widthX = startX + lateralX * patchWidthM
    local widthZ = startZ + lateralZ * patchWidthM
    local heightX = startX + forwardX * patchLengthM
    local heightZ = startZ + forwardZ * patchLengthM
    local params = vehicle.spec_plow ~= nil
        and vehicle.spec_plow.workAreaParameters or nil
    if params == nil then
        return 0
    end

    local changed = FSDensityMapUtil.updateCultivatorArea(
        startX, startZ,
        widthX, widthZ,
        heightX, heightZ,
        not params.limitToField,
        params.limitFruitDestructionToField,
        params.angle,
        nil,
        false,
        true
    )
    local restoreLevel = tonumber(selected.queued.previousPlowLevel)
    local plowLevelModifier = getPlowLevelMapContext(vehicle)
    if plowLevelModifier ~= nil and restoreLevel ~= nil then
        plowLevelModifier:setParallelogramWorldCoords(
            startX, startZ,
            widthX, widthZ,
            heightX, heightZ,
            DensityCoordType.POINT_POINT_POINT
        )
        plowLevelModifier:executeSet(restoreLevel)
    end
    spec.pendingPlowStoneImpact = nil
    spec.impactDropoutStatus = string.format(
        "%s stone patch: %dx%d density pixels, previous plow level %s",
        tostring(impact.tier or "impact"),
        swapAxes and 2 or 1,
        swapAxes and 1 or 2,
        tostring(restoreLevel)
    )
    spec.impactVisualOnlyPixels = tonumber(changed) or 0
    return tonumber(changed) or 0
end

-- Raised by WorkArea only after every normal area, including plowShare, has
-- finished. TerraLogic must be the final density writer for an internal failed row.
function TerraLogic:onEndWorkAreaProcessing(dt, hasProcessed)
    local spec = self.spec_terraLogic
    if spec == nil or self.spec_plow == nil then
        return
    end
    do
        -- The former visual plough jitter/cultivator-patch experiment is retired.
        -- Work quality is now represented exclusively by the sparse quality ledger.
        spec.pendingPlowQualityWorkAreas = {}
        spec.pendingPlowStoneImpact = nil
        spec.plowIrregularPendingEvents = 0
        spec.plowThrowEventAccumulator = 0
        spec.plowVisualCommitMode = "disabled; quality ledger active"
        return
    end
    -- Kept below for the moment as reference for older savegames/debug data.
    -- It is intentionally unreachable and can be removed in a later cleanup.
    -- luacheck: ignore
    local pending = spec.pendingPlowQualityWorkAreas or {}
    spec.pendingPlowQualityWorkAreas = {}
    if hasProcessed == false and #pending == 0 then
        spec.plowDeferredVisualCandidates = {}
        spec.plowIrregularLastPassEvents = 0
        spec.plowIrregularLastPixels = 0
        spec.plowIrregularLastTwoPixelEvents = 0
        spec.plowVisualScatteredPixels = 0
        spec.plowVisualScatteredCells = 0
        spec.plowRasterGameplayFailureCells = 0
        spec.plowVisualDeferredPendingCells = 0
        spec.plowVisualCommitMode = "event stream inactive"
        return
    end
    local profile = spec.impactDropoutProfile ~= nil
        and TerraLogicDropoutManager:getProfile(
            spec.impactDropoutProfile
        ) or nil
    local surfacePixels, surfaceEvents = applyPendingIrregularPlowEvents(
        self, pending, profile
    )
    local stonePixels = applyPendingPlowStoneImpact(self, pending, profile)
    spec.plowDeferredVisualCandidates = {}
    spec.plowVisualScatteredPixels = surfacePixels + stonePixels
    spec.plowVisualScatteredCells = surfaceEvents
        + (stonePixels > 0 and 1 or 0)
    spec.plowRasterGameplayFailureCells = surfaceEvents
        + (stonePixels > 0 and 1 or 0)
    spec.plowVisualDeferredPendingCells = 0
    spec.plowVisualCommitMode = string.format(
        "surface post-pass: %d event(s) / %d px; stone %d px; %d WorkAreas",
        surfaceEvents,
        surfacePixels,
        stonePixels,
        #pending
    )
    spec.plowVisualDistributionMode =
        "1m distance lattice, stratified random 1x2 cultivator misses"
end

local function setModifierToPatternLane(modifier, lane)
    modifier:setParallelogramWorldCoords(
        lane.startX, lane.startZ,
        lane.widthX, lane.widthZ,
        lane.heightX, lane.heightZ,
        DensityCoordType.POINT_POINT_POINT
    )
end

local function getFreshFruitDensityContext(spec, fruitTypeDesc, freshRawState)
    if fruitTypeDesc == nil or fruitTypeDesc.terrainDataPlaneId == nil then
        return nil, nil
    end

    local mapId = fruitTypeDesc.terrainDataPlaneId
    if spec.seedQualityModifier == nil or spec.seedQualityMapId ~= mapId then
        spec.seedQualityModifier = DensityMapModifier.new(
            mapId,
            fruitTypeDesc.startStateChannel,
            fruitTypeDesc.numStateChannels,
            g_terrainNode
        )
        spec.seedQualityFilter = DensityMapFilter.new(spec.seedQualityModifier)
        spec.seedQualityFilter:setValueCompareParams(
            DensityValueCompareType.EQUAL,
            freshRawState
        )
        spec.seedQualityMapId = mapId
    end
    return spec.seedQualityModifier, spec.seedQualityFilter, mapId
end

-- Vanilla's changedArea is operation-wide. A partially valid work area can
-- therefore report success and used to stamp every four-metre TerraLogic cell,
-- including already seeded ground. Snapshot the selected crop's freshly
-- seeded state per touched cell and only admit cells whose density actually
-- increased during this exact pass.
local function getFreshSeedCellMetrics(vehicle, cells, fruitTypeDesc)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    if spec == nil or cells == nil or fruitTypeDesc == nil then return nil end
    local modifier, filter = getFreshFruitDensityContext(
        spec, fruitTypeDesc, TerraLogic.SEED_QUALITY.freshRawState)
    if modifier == nil or filter == nil then return nil end
    local metrics = {}
    local size = TerraLogicQualityManager.CELL_SIZE
    for _, position in ipairs(cells) do
        local x, z = position.ix * size, position.iz * size
        modifier:setParallelogramWorldCoords(
            x, z, x + size, z, x, z + size,
            DensityCoordType.POINT_POINT_POINT)
        local ok, density = pcall(modifier.executeGet, modifier, filter)
        if not ok then return nil end
        metrics[tostring(position.ix) .. ":" .. tostring(position.iz)] =
            tonumber(density) or 0
    end
    return metrics
end

-- Fruit types share one density map. Clearing only the growth-state channels
-- leaves the type index behind, allowing state 0 to grow again later. Mode 2
-- explicitly clears that type index for the filtered pixels as well.
local function clearFreshFruitPixels(modifier, filter, mapId)
    if setDensityNewTypeIndexMode == nil or mapId == nil then
        return 0, "type-index API unavailable"
    end

    local modeOk = pcall(setDensityNewTypeIndexMode, mapId, 2)
    if not modeOk then
        return 0, "could not enable type-index clear"
    end

    local executeOk, _, changedPixels = pcall(modifier.executeSet, modifier, 0, filter)
    -- Never leave the shared fruit map in destructive type-index mode.
    pcall(setDensityNewTypeIndexMode, mapId, 0)
    if not executeOk then
        return 0, "density write failed"
    end
    return tonumber(changedPixels) or 0, nil
end

local function clearFruitPixelsAllStates(modifier, mapId)
    if modifier == nil or setDensityNewTypeIndexMode == nil or mapId == nil then
        return 0, "fruit clear API unavailable"
    end
    local modeOk = pcall(setDensityNewTypeIndexMode, mapId, 2)
    if not modeOk then
        return 0, "could not enable complete fruit clear"
    end
    local executeOk, _, changedPixels = pcall(modifier.executeSet, modifier, 0)
    pcall(setDensityNewTypeIndexMode, mapId, 0)
    if not executeOk then
        return 0, "complete fruit clear failed"
    end
    return tonumber(changedPixels) or 0, nil
end

function TerraLogic:getOverSpeedSeedQuality(currentSpeed)
    local spec = self.spec_terraLogic
    local damage = self.getDamageAmount ~= nil
        and math.clamp(tonumber(self:getDamageAmount()) or 0, 0, 1) or 0
    return TerraLogicDropoutManager:getQualityFromThreshold(
        spec, "seed", currentSpeed, damage
    )
end

function TerraLogic:prepareOverSpeedSeedQualityArea(workArea)
    local spec = self.spec_terraLogic
    local cfg = TerraLogic.SEED_QUALITY
    local sowingSpec = self.spec_sowingMachine
    local params = sowingSpec ~= nil and sowingSpec.workAreaParameters or nil
    local fruitTypeIndex = params ~= nil and params.seedsFruitType or nil
    local isPerennialGrass = FruitType ~= nil and FruitType.GRASS ~= nil
        and fruitTypeIndex == FruitType.GRASS
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local thresholdQuality, damagePenalty, speedPenalty, health,
        thresholdSpeed, thresholdShift =
        self:getOverSpeedSeedQuality(speed)

    -- Stored agronomic quality follows the shared shop-speed economy curve.
    -- Physical missing-plant patterns remain the direct/visual part of that
    -- target loss and still begin only above advertised shop speed.
    local workQuality, yieldPenalty, workEconomy =
        TerraLogicQualityManager:getWorkQualityModel(
            self, speed, "seed", nil, not isPerennialGrass)
    local seedBalance = TerraLogic.getWorkQualityBalance(self, "seed")
    local physicalDropoutsEnabled = getArePhysicalDropoutsEnabled()
    local physicalDropoutPenalty = physicalDropoutsEnabled
        and TerraLogicQualityManager:calculateYieldPenalty(
            math.max(tonumber(thresholdQuality) or 1, 0),
            seedBalance.weight,
            seedBalance.maxPenalty
        ) or 0
    local quality = 1 - physicalDropoutPenalty

    spec.seedQuality = quality
    spec.seedWorkQuality = workQuality
    spec.seedYieldPenalty = yieldPenalty
    spec.seedQualityEconomy = workEconomy
    spec.seedQualityHealth = health
    spec.seedQualityDamagePenalty = damagePenalty
    spec.seedQualitySpeedPenalty = speedPenalty
    spec.seedQualityThresholdSpeed = thresholdSpeed
    spec.seedQualityThresholdShift = thresholdShift
    spec.seedQualityFailedPixels = 0
    spec.seedQualityProtectedLanes = 0
    spec.seedQualityPatternLanes = 0
    spec.seedQualityPatternMode = "inactive"
    spec.seedQualityLaneCap = 0
    spec.seedQualityFullWidthChance = 0
    spec.seedQualitySpeedRatio = thresholdSpeed > 0 and speed / thresholdSpeed or 0
    if fruitTypeIndex == nil or fruitTypeIndex == FruitType.UNKNOWN then
        spec.seedQualityFruit = "none"
    end

    if not physicalDropoutsEnabled then
        spec.seedQualityStatus = "physical dropouts disabled"
        spec.seedQualityPatternMode = "disabled"
        spec.seedQualityLatch = nil
        return nil
    end

    if not cfg.enabled
        or not self.isServer
        or (TerraLogicMain ~= nil and TerraLogicMain.enabled == false)
        or fruitTypeIndex == nil or fruitTypeIndex == FruitType.UNKNOWN then
        spec.seedQualityStatus = fruitTypeIndex == nil and "no selected seed" or "inactive"
        spec.seedQualityLatch = nil
        return nil
    end

    local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitTypeDesc == nil then
        spec.seedQualityStatus = "selected fruit unavailable"
        spec.seedQualityLatch = nil
        return nil
    end

    spec.seedQualityFruit = fruitTypeDesc.name or tostring(fruitTypeIndex)
    -- Empty physical dropout pixels never spread laterally in the game's fruit
    -- density map and would therefore make a perennial grass defect permanent.
    -- Grass keeps the complete modeled seed penalty in the quality ledger and
    -- lets each later cut halve it; annual crops retain physical dropouts.
    if isPerennialGrass then
        spec.seedQuality = 1
        spec.seedQualityStatus = "perennial grass quality ledger"
        spec.seedQualityPatternMode = "perennial recovery"
        spec.seedQualityLatch = nil
        return nil
    end
    if quality >= 0.9999 then
        spec.seedQualityStatus = "perfect"
        spec.seedQualityPatternMode = "perfect"
        spec.seedQualityLatch = nil
        spec.seedQualityWorkAreaDepthM = 0
        spec.seedQualityEffectiveLaneWidthM = 0
        spec.seedQualityHoldDistanceM = 0
        spec.seedQualityHoldRemainingM = 0
        spec.seedQualityMissedFraction = 0
        spec.seedQualityLatchReused = false
        return nil
    end

    local geometry = getWorkAreaPatternGeometry(
        workArea,
        math.max(cfg.patternLaneWidthM or 0.75, cfg.minimumVisibleLaneWidthM or 0),
        cfg.maximumPatternLanes,
        true
    )
    if geometry == nil then
        spec.seedQualityStatus = "invalid work area"
        return nil
    end

    local lanes = {}
    for laneIndex = 1, geometry.lanes do
        lanes[#lanes + 1] = getPatternLane(geometry, laneIndex)
    end
    local failedLanes, selection = TerraLogicDropoutManager:selectFailedLanes(
        "seed", lanes, geometry, quality, spec.seedQualitySpeedRatio, fruitTypeIndex
    )

    spec.seedQualityPatternLanes = #failedLanes
    spec.seedQualityPatternMode = selection.mode
    spec.seedQualityLaneCap = selection.laneCap
    spec.seedQualityFullWidthChance = selection.fullWidthChance
    spec.seedQualityStatus = #failedLanes > 0 and "pattern active" or "no dropout in current cell"
    return {
        geometry = geometry,
        failedLanes = failedLanes,
        fruitTypeIndex = fruitTypeIndex
    }
end

function TerraLogic:applyOverSpeedSeedQualityArea(context, realArea)
    local spec = self.spec_terraLogic
    if context == nil or (tonumber(realArea) or 0) <= 0 then
        return
    end

    local failedPixels = 0
    local clearError = nil
    for _, lane in ipairs(context.failedLanes) do
        -- The world-stable pattern makes adjacent processing-tick overlaps
        -- resolve to the same intended dropout. A former whole-lane overlap
        -- guard protected almost every later tick after seeing just one old
        -- pixel, which effectively restored a fully seeded field.
        setModifierToPatternLane(context.modifier, lane)
        local changedPixels, laneError = clearFreshFruitPixels(
            context.modifier, context.freshFilter, context.mapId
        )
        failedPixels = failedPixels + changedPixels
        clearError = clearError or laneError
    end
    spec.seedQualityFailedPixels = failedPixels
    spec.seedQualityProtectedLanes = 0
    if clearError ~= nil then
        spec.seedQualityStatus = clearError
    elseif failedPixels > 0 then
        spec.seedQualityStatus = string.format("pattern removed %d pixels", failedPixels)
    end
end

local function getRollerLevelModifier(spec)
    local mission = g_currentMission
    if mission == nil or mission.fieldGroundSystem == nil
        or FieldDensityMap == nil or FieldDensityMap.ROLLER_LEVEL == nil then
        return nil
    end
    local mapId, firstChannel, numChannels =
        mission.fieldGroundSystem:getDensityMapData(FieldDensityMap.ROLLER_LEVEL)
    if mapId == nil or mapId == 0 then
        return nil
    end
    if spec.rollerLevelModifier == nil or spec.rollerLevelMapId ~= mapId then
        spec.rollerLevelModifier = DensityMapModifier.new(
            mapId, firstChannel, numChannels, g_terrainNode
        )
        spec.rollerLevelMapId = mapId
    end
    return spec.rollerLevelModifier
end

function TerraLogic:applyOverSpeedRollerQualityArea(workArea, realArea)
    local spec = self.spec_terraLogic
    local cfg = TerraLogic.ROLLER_QUALITY
    local rollerSpec = self.spec_roller
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local rated = tonumber(spec.ratedSpeed) or 0
    spec.rollerQualityFailedPixels = 0
    spec.rollerQualityFailure = 0

    if not getArePhysicalDropoutsEnabled() then
        spec.rollerQualityStatus = "physical dropouts disabled"
        return
    end

    if not cfg.enabled or not self.isServer
        or (TerraLogicMain ~= nil and TerraLogicMain.enabled == false)
        or rollerSpec == nil or rollerSpec.isSoilRoller ~= true
        or rated <= 0 or speed <= rated or (tonumber(realArea) or 0) <= 0 then
        spec.rollerQualityStatus = rollerSpec ~= nil and rollerSpec.isSoilRoller == true
            and "below shop speed / no changed soil" or "not a soil roller"
        return
    end

    local referenceExcess = 0.5
    local failureFraction = cfg.failureAtOnePointFiveRated
        * ((speed / rated - 1) / referenceExcess) ^ cfg.overspeedExponent
    failureFraction = math.clamp(failureFraction, 0, cfg.maximumFailureFraction)
    spec.rollerQualityFailure = failureFraction

    local geometry = getWorkAreaPatternGeometry(
        workArea, cfg.patternLaneWidthM, cfg.maximumPatternLanes
    )
    local rollerModifier = getRollerLevelModifier(spec)
    if geometry == nil or rollerModifier == nil then
        spec.rollerQualityStatus = "density map unavailable"
        return
    end

    local failedLanes = {}
    for laneIndex = 1, geometry.lanes do
        local lane = getPatternLane(geometry, laneIndex)
        local patternValue = getQualityPatternValue(
            lane.centerX, lane.centerZ, laneIndex, 4242, cfg.patternLengthM
        )
        if patternValue >= 1 - failureFraction then
            failedLanes[#failedLanes + 1] = lane
        end
    end
    if #failedLanes == 0 then
        spec.rollerQualityStatus = "no rollback in current cell"
        return
    end

    local failedPixels = 0
    for _, fruitTypeDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        local isGrass = (FruitType.GRASS ~= nil and fruitTypeDesc.index == FruitType.GRASS)
            or (FruitType.MEADOW ~= nil and fruitTypeDesc.index == FruitType.MEADOW)
        if fruitTypeDesc.allowsSeeding == true
            and fruitTypeDesc.terrainDataPlaneId ~= nil and not isGrass then
            local fruitModifier, freshFilter, fruitMapId = getFreshFruitDensityContext(
                spec, fruitTypeDesc, cfg.freshRawState
            )
            for _, lane in ipairs(failedLanes) do
                setModifierToPatternLane(fruitModifier, lane)
                local changedPixels = clearFreshFruitPixels(
                    fruitModifier, freshFilter, fruitMapId
                )
                if changedPixels > 0 then
                    failedPixels = failedPixels + changedPixels
                    -- ROLLER_LEVEL=1 is Vanilla's "needs rolling" state.
                    -- Only the exact failed patch is reverted; every other
                    -- ground, spray, weed and Precision Farming layer stays.
                    setModifierToPatternLane(rollerModifier, lane)
                    rollerModifier:executeSet(1)
                end
            end
        end
    end

    spec.rollerQualityFailedPixels = failedPixels
    spec.rollerQualityStatus = failedPixels > 0
        and string.format("rollback removed %d pixels", failedPixels)
        or "no rollback in current cell"
end

function TerraLogic:getOverSpeedApplicationQuality(currentSpeed)
    local spec = self.spec_terraLogic
    local profileName = spec.dropoutProfile == "fertilizerSpreader"
        and "fertilizerSpreader" or "liquidSprayer"
    local damage = self.getDamageAmount ~= nil
        and math.clamp(tonumber(self:getDamageAmount()) or 0, 0, 1) or 0
    return TerraLogicDropoutManager:getQualityFromThreshold(
        spec, profileName, currentSpeed, damage
    )
end

function TerraLogic:getIsOverSpeedApplicationActive()
    if self.spec_sprayer == nil then
        return false
    end
    if self.getIsTurnedOn ~= nil then
        return self:getIsTurnedOn() == true
    end
    return false
end

local PF_N_YIELD_POINTS = {
    {-200, 0.00}, {-180, 0.01}, {-160, 0.05}, {-140, 0.14},
    {-120, 0.26}, {-100, 0.40}, {-80, 0.58}, {-60, 0.70},
    {-40, 0.82}, {-20, 0.90}, {-10, 0.95}, {0, 1.00},
    {20, 0.98}, {40, 0.96}, {60, 0.92}, {80, 0.89},
    {100, 0.85}, {120, 0.82}, {140, 0.79}
}
local PF_PH_YIELD_POINTS = {
    {-20, 0.00}, {-8, 0.00}, {-7, 0.20}, {-6, 0.40},
    {-5, 0.60}, {-4, 0.80}, {-3, 0.90}, {-2, 0.95},
    {-1, 0.975}, {0, 1.00}, {1, 0.975}, {2, 0.95},
    {3, 0.925}, {5, 0.875}, {6, 0.80}, {7, 0.60},
    {8, 0.40}, {9, 0.20}, {10, 0.00}, {20, 0.00}
}

local function interpolatePFYield(points, value)
    value = tonumber(value)
    if value == nil then return nil end
    if value <= points[1][1] then return points[1][2] end
    for index = 2, #points do
        local upper = points[index]
        if value <= upper[1] then
            local lower = points[index - 1]
            local span = math.max(upper[1] - lower[1], 0.0001)
            local t = (value - lower[1]) / span
            return lower[2] + (upper[2] - lower[2]) * t
        end
    end
    return points[#points][2]
end

local function getPrecisionFarmingSprayerSpec(vehicle)
    local terraLogicSpec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    if terraLogicSpec == nil then return nil end
    if terraLogicSpec.pfSprayerSpecResolved == true then
        return terraLogicSpec.pfSprayerSpec
    end
    terraLogicSpec.pfSprayerSpecResolved = true

    -- Resolve the owning PF specialization first. PrecisionFarmingStatistic
    -- also exposes nitrogenMap/pHMap and therefore must not be selected as an
    -- ExtendedSprayer merely because its table key contains "precision".
    local pfEnvironment = FS25_precisionFarming
    local extendedSprayer = pfEnvironment ~= nil
        and pfEnvironment.ExtendedSprayer or nil
    local tableName = extendedSprayer ~= nil
        and extendedSprayer.SPEC_TABLE_NAME or nil
    if type(tableName) == "string"
        and type(vehicle[tableName]) == "table" then
        terraLogicSpec.pfSprayerSpec = vehicle[tableName]
        terraLogicSpec.pfSprayerSpecSource = tableName
        return terraLogicSpec.pfSprayerSpec
    end

    -- Compatibility fallback for a renamed PF environment: the automatic
    -- rate field belongs to ExtendedSprayer, unlike the shared statistic spec.
    for key, value in pairs(vehicle) do
        if type(key) == "string" and type(value) == "table"
            and (value.nitrogenMap ~= nil or value.pHMap ~= nil)
            and value.sprayAmountAutoMode ~= nil then
            terraLogicSpec.pfSprayerSpec = value
            terraLogicSpec.pfSprayerSpecSource = key .. " (field fallback)"
            break
        end
    end
    terraLogicSpec.pfSprayerSpecSource =
        terraLogicSpec.pfSprayerSpecSource or "not found"
    return terraLogicSpec.pfSprayerSpec
end

local function getAveragePFLevel(workArea, levelName, targetName)
    if workArea == nil then return nil, nil end
    local sum, targetSum, count = 0, 0, 0
    for _, section in ipairs(workArea.subSectionData or {}) do
        local level, target = tonumber(section[levelName]), tonumber(section[targetName])
        if level ~= nil and target ~= nil then
            sum, targetSum, count = sum + level, targetSum + target, count + 1
        end
    end
    if count > 0 then return sum / count, targetSum / count end
    return tonumber(workArea[levelName]), tonumber(workArea[targetName])
end

local function getSprayerApplicationFillType(vehicle)
    local sprayerSpec = vehicle ~= nil and vehicle.spec_sprayer or nil
    local params = sprayerSpec ~= nil and sprayerSpec.workAreaParameters or nil
    local fillTypeIndex = params ~= nil
        and (params.sprayFillType or params.fillType or params.fillTypeIndex)
        or nil
    local unknown = FillType ~= nil and FillType.UNKNOWN or nil
    local function isUsable(value)
        return value ~= nil and (unknown == nil or value ~= unknown)
    end

    local fillUnitIndex = params ~= nil
        and (params.sprayFillUnitIndex or params.fillUnitIndex) or nil
    fillUnitIndex = fillUnitIndex
        or (sprayerSpec ~= nil and sprayerSpec.fillUnitIndex) or 1
    local source = params ~= nil and params.sprayVehicle or nil
    local function tryCandidate(candidate)
        if not isUsable(fillTypeIndex) and candidate ~= nil
            and candidate.getFillUnitLastValidFillType ~= nil then
            local ok, value = pcall(
                candidate.getFillUnitLastValidFillType,
                candidate,
                fillUnitIndex
            )
            if ok and isUsable(value) then
                fillTypeIndex = value
                source = candidate
            end
        end
    end
    tryCandidate(source)
    if vehicle ~= source then tryCandidate(vehicle) end
    if source == nil then source = vehicle end
    return fillTypeIndex, source, fillUnitIndex
end

local function getApplicationComponent(fillTypeIndex, fillTypeDesc)
    local fillName = string.lower(tostring(
        fillTypeDesc ~= nil and (fillTypeDesc.name or fillTypeDesc.title) or ""))
    local isHerbicide = (FillType ~= nil and FillType.HERBICIDE ~= nil
            and fillTypeIndex == FillType.HERBICIDE)
        or string.find(fillName, "herbicide", 1, true) ~= nil
    local isLime = (FillType ~= nil and FillType.LIME ~= nil
            and fillTypeIndex == FillType.LIME)
        or string.find(fillName, "lime", 1, true) ~= nil
    return isHerbicide and "herbicide"
        or (isLime and "lime" or "fertilizer")
end

-- Resolves the currently selected material independently from the machine
-- category, allowing one sprayer to switch its HUD and quality behavior
-- immediately between herbicide, liquid fertilizer and lime.
function TerraLogic.getApplicationComponentForVehicle(vehicle)
    if vehicle == nil or vehicle.spec_sprayer == nil then return nil end
    local fillTypeIndex = getSprayerApplicationFillType(vehicle)
    local fillTypeDesc = fillTypeIndex ~= nil and g_fillTypeManager ~= nil
        and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    return getApplicationComponent(fillTypeIndex, fillTypeDesc)
end

local function getApplicationPhysicalDropoutProfile(vehicle, component)
    if component == "herbicide" then return "herbicidePatch" end
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    if spec ~= nil and spec.implementClassKey == "manureSpreader" then
        return "manureSpreaderPatch"
    end
    if spec ~= nil and spec.implementClassKey == "slurrySpreader" then
        return "slurrySpreaderPatch"
    end
    local isSpinnerSpreader = spec ~= nil
        and (spec.implementClassKey == "fertilizerSpreader"
            or spec.dropoutProfile == "fertilizerSpreader")
    if isSpinnerSpreader then
        return component == "lime"
            and "limeSpreaderPatch" or "fertilizerSpreaderPatch"
    end
    return component == "lime"
        and "liquidLimePatch" or "liquidFertilizerPatch"
end

local function wasApplicationQualityRecordedThisFrame(
        spec, workArea, component)
    local now = g_currentMission ~= nil and g_currentMission.time or 0
    return spec ~= nil
        and spec.lastApplicationQualityRecordTime == now
        and spec.lastApplicationQualityRecordWorkArea == workArea
        and spec.lastApplicationQualityRecordComponent == component
end

local function markApplicationQualityRecorded(spec, workArea, component)
    if spec == nil then return end
    spec.lastApplicationQualityRecordTime =
        g_currentMission ~= nil and g_currentMission.time or 0
    spec.lastApplicationQualityRecordWorkArea = workArea
    spec.lastApplicationQualityRecordComponent = component
end

-- PF has no fixed two-stage bonus. Derive the positive contribution of this
-- pass from its own current/target N or pH levels. The returned value is
-- normalized to the untreated PF factor, so removing it cannot push yield
-- below the state that existed before the application.
local function getPrecisionFarmingApplicationBonus(vehicle, workArea, component)
    if TerraLogicMain == nil
        or TerraLogicMain.isPrecisionFarmingActive == nil
        or not TerraLogicMain:isPrecisionFarmingActive() then
        return nil, "vanilla"
    end
    local pfSpec = getPrecisionFarmingSprayerSpec(vehicle)
    if pfSpec == nil then return nil, "PF data unavailable" end

    local levelName = component == "lime" and "phLevel" or "nitrogenLevel"
    local targetName = component == "lime" and "phTargetLevel"
        or "nitrogenTargetLevel"
    local current, target = getAveragePFLevel(workArea, levelName, targetName)
    if current == nil or target == nil then
        if component == "lime" then
            current, target = tonumber(pfSpec.phActualValue), tonumber(pfSpec.phTargetValue)
        else
            current, target = tonumber(pfSpec.nActualValue), tonumber(pfSpec.nTargetValue)
        end
    end
    if current == nil or target == nil then return nil, "PF levels unavailable" end

    local after = target
    if pfSpec.sprayAmountAutoMode == false then
        after = current + math.max(tonumber(pfSpec.sprayAmountManual) or 1, 1)
    end
    local beforeFactor, afterFactor
    if component == "lime" then
        beforeFactor = interpolatePFYield(PF_PH_YIELD_POINTS, current - target)
        afterFactor = interpolatePFYield(PF_PH_YIELD_POINTS, after - target)
    else
        -- One internal PF nitrogen state represents 5 kg N/ha.
        beforeFactor = interpolatePFYield(PF_N_YIELD_POINTS,
            (current - target) * 5)
        afterFactor = interpolatePFYield(PF_N_YIELD_POINTS,
            (after - target) * 5)
    end
    local gain = math.max((afterFactor or 0) - (beforeFactor or 0), 0)
    if gain <= 0 then return 0, "PF no positive yield gain" end
    return math.clamp(gain / math.max(beforeFactor or 0, 0.01), 0, 20),
        "PF local N/pH gain"
end

-- Applies physical fertilizer, lime or herbicide dropouts. All three Category
-- B materials additionally persist the invisible quality of the successfully
-- treated part; physical misses keep their separate visible Vanilla result.
function TerraLogic:processSprayerArea(superFunc, workArea, dt)
    local spec = self.spec_terraLogic
    local classKey = spec ~= nil and spec.implementClassKey or nil
    local supportedApplication = classKey == "liquidSprayer"
        or classKey == "fertilizerSpreader"
        or classKey == "manureSpreader"
        or classKey == "slurrySpreader"
        or classKey == "slurryApplicator"
        -- Combination drills are classified by their sowing function, but may
        -- legitimately execute their integrated fertilizer WorkArea here.
        or self.spec_sowingMachine ~= nil
    if not supportedApplication then
        return superFunc(self, workArea, dt)
    end
    local profileName = spec.dropoutProfile == "fertilizerSpreader"
        and "fertilizerSpreader" or "liquidSprayer"
    local cfg = TerraLogicDropoutManager:getProfile(profileName)
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local quality, damagePenalty, speedPenalty, health,
        thresholdSpeed, thresholdShift =
        self:getOverSpeedApplicationQuality(speed)
    quality = TerraLogicQualityManager:getSpeedQuality(self, speed)
    spec.applicationQuality = quality
    spec.applicationQualityHealth = health
    spec.applicationQualityDamagePenalty = damagePenalty
    spec.applicationQualitySpeedPenalty = speedPenalty
    spec.applicationQualityThresholdSpeed = thresholdSpeed
    spec.applicationQualityThresholdShift = thresholdShift
    spec.applicationQualitySkippedLanes = 0
    spec.applicationQualityProcessedLanes = 0
    spec.applicationQualityProfile = profileName
    spec.applicationQualityPatternMode = cfg.patternType or "inactive"

    local params = self.spec_sprayer ~= nil and self.spec_sprayer.workAreaParameters or nil
    local fillTypeIndex, fillSource, fillUnitIndex =
        getSprayerApplicationFillType(self)
    local fillTypeDesc = fillTypeIndex ~= nil and g_fillTypeManager ~= nil
        and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    spec.applicationQualityFillType = fillTypeDesc ~= nil
        and (fillTypeDesc.name or fillTypeDesc.title or tostring(fillTypeIndex))
        or (fillTypeIndex ~= nil and tostring(fillTypeIndex) or "unknown")

    local component = getApplicationComponent(fillTypeIndex, fillTypeDesc)
    local physicalProfileName =
        getApplicationPhysicalDropoutProfile(self, component)
    spec.applicationPhysicalDropoutProfile = physicalProfileName
    local pfBonus, pfBonusSource = nil, "not applicable"
    if component == "fertilizer" or component == "lime" then
        pfBonus, pfBonusSource = getPrecisionFarmingApplicationBonus(
            self, workArea, component)
    end
    local fillLevelBefore = nil
    if fillSource ~= nil and fillSource.getFillUnitFillLevel ~= nil then
        local ok, level = pcall(
            fillSource.getFillUnitFillLevel, fillSource, fillUnitIndex)
        if ok then fillLevelBefore = tonumber(level) end
    end
    local realArea, totalArea, processedAreas =
        self:processSurfacePatchDropoutArea(
            superFunc, workArea, dt, physicalProfileName)

    -- Work quality is a stable property of speed and implement class. PF's
    -- local remaining N/pH gain can legitimately fall to zero on an already
    -- optimal patch, but that must not turn poor overspeed work back into
    -- 100% quality or make the HUD oscillate along PF map boundaries.
    local workQuality = select(1,
        TerraLogicQualityManager:getWorkQualityModel(
            self, speed, component, nil))
    local yieldQuality, modeledPenalty, economy =
        TerraLogicQualityManager:getWorkQualityModel(
            self, speed, component, pfBonus)
    quality = workQuality
    spec.applicationQuality = workQuality
    spec.applicationQualityYieldQuality = yieldQuality
    spec.applicationQualityComponent = component
    spec.applicationQualityPfBonus = pfBonus
    spec.applicationQualityPfBonusSource = pfBonusSource
    spec.applicationQualityEconomy = economy
    local balance = TerraLogic.getWorkQualityBalance(
        self, component, fillTypeIndex)
    local precisionFarmingActive = TerraLogicMain ~= nil
        and TerraLogicMain.isPrecisionFarmingActive ~= nil
        and TerraLogicMain:isPrecisionFarmingActive()
    local aggregateVanillaFertilizer = component == "fertilizer"
        and not precisionFarmingActive
    local successfulArea = tonumber(realArea) or 0
    local hasProcessedGeometry = processedAreas == nil
        or #processedAreas > 0
    local paramsAfter = self.spec_sprayer ~= nil
        and self.spec_sprayer.workAreaParameters or params
    local usage = paramsAfter ~= nil and tonumber(paramsAfter.usage) or 0
    local consumedFill = false
    if fillLevelBefore ~= nil and fillSource ~= nil
        and fillSource.getFillUnitFillLevel ~= nil then
        local ok, levelAfter = pcall(
            fillSource.getFillUnitFillLevel, fillSource, fillUnitIndex)
        consumedFill = ok and tonumber(levelAfter) ~= nil
            and tonumber(levelAfter) < fillLevelBefore - 0.0001
    end
    -- Precision Farming may update its own N/pH map while the underlying
    -- Vanilla sprayer reports no changed density area. Positive per-pass
    -- usage or an observed fill-level decrease is still proof that this work
    -- area successfully applied material. No-consumption passes over an
    -- already treated area remain excluded.
    if successfulArea <= 0 and hasProcessedGeometry
        and (usage > 0 or consumedFill) then
        successfulArea = math.max(tonumber(totalArea) or 0, 1)
    end
    spec.applicationQualitySuccessfulArea = successfulArea
    spec.applicationQualityUsage = usage
    spec.applicationQualityConsumedFill = consumedFill
    local duplicateRecord = successfulArea > 0
        and wasApplicationQualityRecordedThisFrame(
            spec, workArea, component)
    if not duplicateRecord then
        for _, entry in ipairs(getDropoutLedgerAreas(
                processedAreas, workArea, successfulArea)) do
            TerraLogicQualityManager:recordWorkArea(
                getDropoutLedgerWorkArea(self, entry),
                component, workQuality,
                entry.terraLogicSuccessfulArea,
                balance.weight, balance.maxPenalty, self, modeledPenalty,
                nil, aggregateVanillaFertilizer)
        end
        if successfulArea > 0 and hasProcessedGeometry then
            markApplicationQualityRecorded(spec, workArea, component)
        end
    end
    spec.applicationQualityStatus = successfulArea <= 0
        and "no successful application"
        or (workQuality >= 0.9999 and "perfect" or "quality ledger")
    spec.applicationQualityPatternMode = getArePhysicalDropoutsEnabled()
        and "surface islands + quality ledger" or "quality ledger"
    return realArea, totalArea
end

function TerraLogic:onDelete()
    if TerraLogicQualityManager ~= nil
        and TerraLogicQualityManager.pendingMowerClears ~= nil then
        TerraLogicQualityManager.pendingMowerClears[self] = nil
    end
    local spec = self.spec_terraLogic
    if spec == nil or spec.qualityPatternNodes == nil then
        return
    end
    for _, node in pairs(spec.qualityPatternNodes) do
        if node ~= nil and node ~= 0 then
            delete(node)
        end
    end
    spec.qualityPatternNodes = nil
end

function TerraLogic:onWriteStream(streamId, connection)
    if not connection:getIsServer() then
        streamWriteBool(streamId,
            self.spec_terraLogic.actualWorkActive == true)
        streamWriteBool(streamId,
            self.spec_terraLogic.qualityWorkActive == true)
    end
end

function TerraLogic:onReadStream(streamId, connection)
    if connection:getIsServer() then
        self.spec_terraLogic.actualWorkActive = streamReadBool(streamId)
        self.spec_terraLogic.qualityWorkActive = streamReadBool(streamId)
    end
end

function TerraLogic:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self.spec_terraLogic
        local dirty = bitAND(dirtyMask, spec.actualWorkDirtyFlag) ~= 0
        streamWriteBool(streamId, dirty)
        if dirty then
            streamWriteBool(streamId, spec.actualWorkActive == true)
            streamWriteBool(streamId, spec.qualityWorkActive == true)
        end
    end
end

function TerraLogic:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        self.spec_terraLogic.actualWorkActive = streamReadBool(streamId)
        self.spec_terraLogic.qualityWorkActive = streamReadBool(streamId)
    end
end

-- Handles sowing dropouts and all successful operations of combination drills.
function TerraLogic:processSowingMachineArea(superFunc, workArea, dt)
    local terraLogicSpec = self.spec_terraLogic
    terraLogicSpec.seedQualityHookActive = true
    if terraLogicSpec.seedQualityHookLogged ~= true then
        terraLogicSpec.seedQualityHookLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Seed quality processing hook active: vehicle=%s",
            self.getName ~= nil and self:getName() or "sowing machine"
        )
    end
    local sowingParams = self.spec_sowingMachine ~= nil
        and self.spec_sowingMachine.workAreaParameters or nil
    local selectedFruit = sowingParams ~= nil and sowingParams.seedsFruitType or nil
    local selectedFruitDesc = selectedFruit ~= nil and g_fruitTypeManager ~= nil
        and g_fruitTypeManager:getFruitTypeByIndex(selectedFruit) or nil

    -- Combined seeders commonly expose only a sowingMachine WorkArea even
    -- though their sprayer specialization applies fertilizer in the same
    -- pass. Capture the application state here because processSprayerArea is
    -- therefore never called for many base-game and mod machines.
    local combinedApplication = nil
    if self.spec_sprayer ~= nil then
        local applicationParams = self.spec_sprayer.workAreaParameters
        local fillTypeIndex, fillSource, fillUnitIndex =
            getSprayerApplicationFillType(self)
        local fillTypeDesc = fillTypeIndex ~= nil
            and g_fillTypeManager ~= nil
            and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
        local component = getApplicationComponent(fillTypeIndex, fillTypeDesc)
        local fillLevelBefore = nil
        if fillSource ~= nil and fillSource.getFillUnitFillLevel ~= nil then
            local ok, level = pcall(
                fillSource.getFillUnitFillLevel, fillSource, fillUnitIndex)
            if ok then fillLevelBefore = tonumber(level) end
        end
        local pfBonus, pfBonusSource = nil, "not applicable"
        if component == "fertilizer" or component == "lime" then
            pfBonus, pfBonusSource = getPrecisionFarmingApplicationBonus(
                self, workArea, component)
        end
        combinedApplication = {
            fillTypeIndex = fillTypeIndex,
            fillTypeDesc = fillTypeDesc,
            fillSource = fillSource,
            fillUnitIndex = fillUnitIndex,
            fillLevelBefore = fillLevelBefore,
            changedAreaBefore = applicationParams ~= nil
                and tonumber(applicationParams.lastChangedArea) or nil,
            totalAreaBefore = applicationParams ~= nil
                and tonumber(applicationParams.lastTotalArea) or nil,
            component = component,
            pfBonus = pfBonus,
            pfBonusSource = pfBonusSource
        }
    end
    local seedCells = TerraLogicQualityManager:getTouchedCells(workArea, false)
    local seedMetricsBefore = getFreshSeedCellMetrics(
        self, seedCells, selectedFruitDesc)
    local qualityContext = self:prepareOverSpeedSeedQualityArea(workArea)
    local function processSowingAndQuality(vehicle, area, deltaTime)
        if qualityContext == nil or FSDensityMapUtil == nil then
            return superFunc(vehicle, area, deltaTime)
        end

        local seedSpec = vehicle.spec_terraLogic
        local cfg = TerraLogicDropoutManager:getProfile("seed")
        local densityFailedLanes = {}

        local function filterDensitySowingCall(originalFunction,
                fruitTypeIndex, startX, startZ, widthX, widthZ,
                heightX, heightZ, ...)
            local trailingArguments = {...}
            local trailingArgumentCount = select("#", ...)
            local geometry = getDensityCallPatternGeometry(
                startX, startZ, widthX, widthZ, heightX, heightZ,
                math.max(
                    cfg.patternLaneWidthM or 0.75,
                    cfg.minimumVisibleLaneWidthM or 0
                ),
                cfg.maximumPatternLanes,
                true
            )
            if geometry == nil then
                return originalFunction(
                    fruitTypeIndex, startX, startZ, widthX, widthZ,
                    heightX, heightZ,
                    unpack(trailingArguments, 1, trailingArgumentCount)
                )
            end

            local lanes = {}
            for laneIndex = 1, geometry.lanes do
                lanes[#lanes + 1] = getPatternLane(geometry, laneIndex)
            end
            local failedLanes, selection, latch, latchTelemetry =
                TerraLogicDropoutManager:selectLatchedFailedLanes(
                    "seed", seedSpec.seedQualityLatch,
                    lanes, geometry,
                    seedSpec.seedQuality or 1,
                    seedSpec.seedQualitySpeedRatio or 0,
                    fruitTypeIndex or qualityContext.fruitTypeIndex
                )
            seedSpec.seedQualityLatch = latch
            seedSpec.seedQualityWorkAreaDepthM = latchTelemetry.workAreaDepthM
            seedSpec.seedQualityEffectiveLaneWidthM = latchTelemetry.effectiveLaneWidthM
            seedSpec.seedQualityHoldDistanceM = latchTelemetry.holdDistanceM
            seedSpec.seedQualityHoldRemainingM = latchTelemetry.remainingDistanceM
            seedSpec.seedQualityMissedFraction = latchTelemetry.missedFraction
            seedSpec.seedQualityLatchReused = latchTelemetry.reused
            local failed = {}
            for _, failedLane in ipairs(failedLanes) do
                failed[failedLane.patternIndex] = true
                densityFailedLanes[#densityFailedLanes + 1] = failedLane
            end
            seedSpec.seedQualityPatternLanes = #failedLanes
            seedSpec.seedQualityPatternMode = selection.mode
            seedSpec.seedQualityLaneCap = selection.laneCap
            seedSpec.seedQualityFullWidthChance = selection.fullWidthChance

            if #failedLanes == 0 then
                return originalFunction(
                    fruitTypeIndex, startX, startZ, widthX, widthZ,
                    heightX, heightZ,
                    unpack(trailingArguments, 1, trailingArgumentCount)
                )
            end

            local realAreaSum, totalAreaSum = 0, 0
            local runStart = nil

            local function processSuccessfulRun(runEnd)
                if runStart == nil then
                    return
                end
                local lane = getPatternLaneRange(geometry, runStart, runEnd)
                local realArea, totalArea = originalFunction(
                    fruitTypeIndex,
                    lane.startX, lane.startZ,
                    lane.widthX, lane.widthZ,
                    lane.heightX, lane.heightZ,
                    unpack(trailingArguments, 1, trailingArgumentCount)
                )
                realAreaSum = realAreaSum + (tonumber(realArea) or 0)
                totalAreaSum = totalAreaSum + (tonumber(totalArea) or 0)
                runStart = nil
            end

            for laneIndex = 1, geometry.lanes do
                if failed[laneIndex] then
                    processSuccessfulRun(laneIndex - 1)
                else
                    runStart = runStart or laneIndex
                end
            end
            processSuccessfulRun(geometry.lanes)

            seedSpec.seedQualityDensityHookActive = true
            seedSpec.seedQualityDensityCalls =
                (seedSpec.seedQualityDensityCalls or 0) + 1
            if seedSpec.seedQualityDensityHookLogged ~= true then
                seedSpec.seedQualityDensityHookLogged = true
                TerraLogicLogging.debug(
                    "[FS25_TerraLogic] Seed density filter active: vehicle=%s quality=%.3f threshold=%.2f speed=%.2f mode=%s skippedLanes=%d/%d cap=%d fullWidthChance=%.4f",
                    vehicle.getName ~= nil and vehicle:getName() or "sowing machine",
                    seedSpec.seedQuality or 1,
                    seedSpec.seedQualityThresholdSpeed or 0,
                    math.abs(vehicle:getLastSpeed(true) or 0),
                    selection.mode or "inactive",
                    #failedLanes, geometry.lanes,
                    selection.laneCap or 0,
                    selection.fullWidthChance or 0
                )
            end
            return realAreaSum, totalAreaSum
        end

        local originalSowingArea = FSDensityMapUtil.updateSowingArea
        local originalDirectSowingArea = FSDensityMapUtil.updateDirectSowingArea
        if originalSowingArea ~= nil then
            FSDensityMapUtil.updateSowingArea = function(...)
                return filterDensitySowingCall(originalSowingArea, ...)
            end
        end
        if originalDirectSowingArea ~= nil then
            FSDensityMapUtil.updateDirectSowingArea = function(...)
                return filterDensitySowingCall(originalDirectSowingArea, ...)
            end
        end

        local results = {pcall(superFunc, vehicle, area, deltaTime)}
        FSDensityMapUtil.updateSowingArea = originalSowingArea
        FSDensityMapUtil.updateDirectSowingArea = originalDirectSowingArea
        if not results[1] then
            error(results[2])
        end

        local postClearPixels = 0
        local postClearError = nil
        local fruitTypeDesc = g_fruitTypeManager:getFruitTypeByIndex(
            qualityContext.fruitTypeIndex
        )
        local fruitModifier, _, fruitMapId = getFreshFruitDensityContext(
            seedSpec, fruitTypeDesc, TerraLogic.SEED_QUALITY.freshRawState
        )
        if fruitModifier ~= nil then
            for _, failedLane in ipairs(densityFailedLanes) do
                setModifierToPatternLane(fruitModifier, failedLane)
                local changedPixels, clearError = clearFruitPixelsAllStates(
                    fruitModifier, fruitMapId
                )
                postClearPixels = postClearPixels + changedPixels
                postClearError = postClearError or clearError
            end
        else
            postClearError = "selected fruit modifier unavailable"
        end

        seedSpec.seedQualityPostClearPixels = postClearPixels
        seedSpec.seedQualityFailedPixels = postClearPixels
        if seedSpec.seedQualityPostClearLogged ~= true then
            seedSpec.seedQualityPostClearLogged = true
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] Seed post-clear active: vehicle=%s fruit=%s changedPixels=%d status=%s",
                vehicle.getName ~= nil and vehicle:getName() or "sowing machine",
                fruitTypeDesc ~= nil and fruitTypeDesc.name or "unknown",
                postClearPixels, postClearError or "ok"
            )
        end
        seedSpec.seedQualityStatus = postClearError ~= nil
            and postClearError
            or string.format("density filter + post-clear %d pixels", postClearPixels)
        return results[2], results[3]
    end
    local realArea, totalArea = self:processOverSpeedStoneArea(
        processSowingAndQuality, workArea, dt)
    local successfulSeedCells = nil
    if (tonumber(realArea) or 0) > 0 and seedMetricsBefore ~= nil then
        local seedMetricsAfter = getFreshSeedCellMetrics(
            self, seedCells, selectedFruitDesc)
        if seedMetricsAfter ~= nil then
            successfulSeedCells = {}
            for key, afterDensity in pairs(seedMetricsAfter) do
                if afterDensity > (seedMetricsBefore[key] or 0) + 0.001 then
                    successfulSeedCells[key] = true
                end
            end
        end
    end
    -- Physical gaps and invisible placement quality are separate Category B
    -- effects. The shared quality model already slows only the above-shop
    -- deterioration while dropouts are enabled, so store that complete
    -- remaining quality penalty on successfully seeded cells. Missing cells
    -- contain no crop and therefore cannot receive this harvest penalty.
    local seedBalance = TerraLogic.getWorkQualityBalance(self, "seed")
    local residualHarvestPenalty = math.clamp(
        tonumber(terraLogicSpec.seedYieldPenalty) or 0,
        0,
        1
    )
    if self.spec_sowingMachine ~= nil
        and self.spec_sowingMachine.useDirectPlanting == true then
        local soilQuality, soilPenalty =
            TerraLogicQualityManager:getWorkQualityModel(
                self, math.abs(self:getLastSpeed(true) or 0), "soilCultivate")
        local soilBalance = TerraLogic.getWorkQualityBalance(
            self, "soilCultivate")
        TerraLogicQualityManager:recordWorkArea(
            workArea, "soilCultivate", soilQuality, realArea,
            soilBalance.weight, soilBalance.maxPenalty, self, soilPenalty,
            successfulSeedCells)
    end
    -- Direct drilling records its integrated soil pass first. That pass may
    -- invalidate an older crop's seed quality; the successful new sowing is
    -- then written last and therefore remains in the ledger.
    TerraLogicQualityManager:recordWorkArea(
        workArea, "seed", terraLogicSpec.seedWorkQuality or 1, realArea,
        seedBalance.weight, seedBalance.maxPenalty, self,
        residualHarvestPenalty, successfulSeedCells)

    if combinedApplication ~= nil then
        local application = combinedApplication
        local params = self.spec_sprayer ~= nil
            and self.spec_sprayer.workAreaParameters or nil
        local usage = params ~= nil and tonumber(params.usage) or 0
        local changedAreaAfter = params ~= nil
            and tonumber(params.lastChangedArea) or nil
        local totalAreaAfter = params ~= nil
            and tonumber(params.lastTotalArea) or nil
        local applicationChangedArea = 0
        if changedAreaAfter ~= nil then
            applicationChangedArea = math.max(
                changedAreaAfter - (application.changedAreaBefore or 0), 0)
            if application.changedAreaBefore ~= nil
                and changedAreaAfter < application.changedAreaBefore then
                applicationChangedArea = math.max(changedAreaAfter, 0)
            end
        end
        local applicationTotalArea = 0
        if totalAreaAfter ~= nil then
            applicationTotalArea = math.max(
                totalAreaAfter - (application.totalAreaBefore or 0), 0)
            if application.totalAreaBefore ~= nil
                and totalAreaAfter < application.totalAreaBefore then
                applicationTotalArea = math.max(totalAreaAfter, 0)
            end
        end
        local consumedFill = false
        if application.fillLevelBefore ~= nil
            and application.fillSource ~= nil
            and application.fillSource.getFillUnitFillLevel ~= nil then
            local ok, fillLevelAfter = pcall(
                application.fillSource.getFillUnitFillLevel,
                application.fillSource, application.fillUnitIndex)
            consumedFill = ok and tonumber(fillLevelAfter) ~= nil
                and tonumber(fillLevelAfter)
                    < application.fillLevelBefore - 0.0001
        end

        -- Material use is the success signal for the secondary operation.
        -- This keeps empty/deactivated fertilizer tanks from creating quality
        -- entries while still supporting helper/PF consumption that may not
        -- reduce the local fill level directly.
        local successfulApplicationArea = applicationChangedArea
        if successfulApplicationArea <= 0
            and (usage > 0 or consumedFill) then
            successfulApplicationArea = applicationTotalArea
            if successfulApplicationArea <= 0 then
                successfulApplicationArea = math.max(
                    tonumber(realArea) or tonumber(totalArea) or 0, 1)
            end
        end

        local speed = math.abs(self:getLastSpeed(true) or 0)
        local workQuality = select(1,
            TerraLogicQualityManager:getWorkQualityModel(
                self, speed, application.component, nil))
        local yieldQuality, modeledPenalty, economy =
            TerraLogicQualityManager:getWorkQualityModel(
                self, speed, application.component, application.pfBonus)
        local balance = TerraLogic.getWorkQualityBalance(
            self, application.component, application.fillTypeIndex)
        local precisionFarmingActive = TerraLogicMain ~= nil
            and TerraLogicMain.isPrecisionFarmingActive ~= nil
            and TerraLogicMain:isPrecisionFarmingActive()
        local aggregateVanillaFertilizer =
            application.component == "fertilizer"
            and not precisionFarmingActive
        local duplicateRecord = successfulApplicationArea > 0
            and wasApplicationQualityRecordedThisFrame(
                terraLogicSpec, workArea, application.component)

        terraLogicSpec.combinedApplicationQuality = workQuality
        terraLogicSpec.combinedApplicationYieldQuality = yieldQuality
        terraLogicSpec.combinedApplicationComponent = application.component
        terraLogicSpec.combinedApplicationUsage = usage
        terraLogicSpec.combinedApplicationChangedArea = applicationChangedArea
        terraLogicSpec.combinedApplicationTotalArea = applicationTotalArea
        terraLogicSpec.combinedApplicationConsumedFill = consumedFill
        terraLogicSpec.combinedApplicationSuccessfulArea = successfulApplicationArea
        terraLogicSpec.combinedApplicationPfBonus = application.pfBonus
        terraLogicSpec.combinedApplicationPfBonusSource = application.pfBonusSource
        terraLogicSpec.combinedApplicationEconomy = economy
        terraLogicSpec.combinedApplicationStatus = successfulApplicationArea <= 0
            and "no successful combined application"
            or (duplicateRecord and "recorded by application work area"
                or "quality ledger")

        if not duplicateRecord then
            TerraLogicQualityManager:recordWorkArea(
                workArea, application.component, workQuality,
                successfulApplicationArea,
                balance.weight, balance.maxPenalty, self, modeledPenalty,
                nil, aggregateVanillaFertilizer)
            if successfulApplicationArea > 0 then
                markApplicationQualityRecorded(
                    terraLogicSpec, workArea, application.component)
            end
        end
    end
    return realArea, totalArea
end

function TerraLogic:processRollerArea(superFunc, workArea, dt)
    -- A combination roller may successfully process grass first and then let
    -- Vanilla overwrite that return value with a zero soil-roller result. Tap
    -- the existing density-map call for this synchronous super call so quality
    -- uses the real successful grass area without applying the roller twice.
    local grassArea = 0
    local prevalidatedGrassCells = nil
    local prevalidatedGrassCellCount = 0
    if self.spec_roller ~= nil and self.spec_roller.isGrassRoller == true then
        prevalidatedGrassCells = {}
        for _, position in ipairs(
                TerraLogicQualityManager:getTouchedCells(workArea, false)) do
            local surface = TerraLogicQualityManager:getSurfaceTypeAtWorldPosition(
                (position.ix + 0.5) * TerraLogicQualityManager.CELL_SIZE,
                (position.iz + 0.5) * TerraLogicQualityManager.CELL_SIZE)
            -- Natural meadow may be visually reset by a grass roller, but the
            -- yield-relevant effect is restricted to a real field. A recently
            -- cut grass field can report the generic "field" surface between
            -- remaining grass pixels; Vanilla's positive grassArea below is
            -- still the final proof that grass rolling actually succeeded.
            if surface == "grassField" or surface == "field" then
                prevalidatedGrassCells[
                    tostring(position.ix) .. ":" .. tostring(position.iz)] = true
                prevalidatedGrassCellCount = prevalidatedGrassCellCount + 1
            end
        end
    end
    local originalGrassRollerArea = FSDensityMapUtil ~= nil
        and FSDensityMapUtil.updateGrassRollerArea or nil
    if self.spec_roller ~= nil and self.spec_roller.isGrassRoller == true
        and originalGrassRollerArea ~= nil then
        FSDensityMapUtil.updateGrassRollerArea = function(...)
            local changedArea, totalArea = originalGrassRollerArea(...)
            grassArea = math.max(grassArea, tonumber(changedArea) or 0)
            return changedArea, totalArea
        end
    end
    local ok, realArea, totalArea = pcall(
        self.processOverSpeedStoneArea, self, superFunc, workArea, dt)
    if originalGrassRollerArea ~= nil then
        FSDensityMapUtil.updateGrassRollerArea = originalGrassRollerArea
    end
    if not ok then error(realArea) end
    local successfulArea = math.max(tonumber(realArea) or 0, grassArea)
    local quality, yieldPenalty = TerraLogicQualityManager:getWorkQualityModel(
        self, math.abs(self:getLastSpeed(true) or 0), "roller")
    local balance = TerraLogic.getWorkQualityBalance(self, "roller")
    local acceptedCells, touchedCells, ledgerChanged =
        TerraLogicQualityManager:recordWorkArea(
        workArea, "roller", quality, successfulArea,
        balance.weight, balance.maxPenalty, self, yieldPenalty,
        nil, false, prevalidatedGrassCells)
    local terraLogicSpec = self.spec_terraLogic
    if terraLogicSpec ~= nil then
        terraLogicSpec.rollerGrassAreaCaptured = grassArea
        terraLogicSpec.rollerSuccessfulArea = successfulArea
        terraLogicSpec.rollerPrevalidatedGrassCells = prevalidatedGrassCellCount
        terraLogicSpec.rollerLedgerAcceptedCells = acceptedCells or 0
        terraLogicSpec.rollerLedgerTouchedCells = touchedCells or 0
        terraLogicSpec.rollerLedgerChanged = ledgerChanged == true
        local now = g_currentMission ~= nil and g_currentMission.time or 0
        if TerraLogicLogging ~= nil and TerraLogicLogging.verbose == true
            and now >= (terraLogicSpec.nextRollerLedgerLogTime or 0) then
            terraLogicSpec.nextRollerLedgerLogTime = now + 1000
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] Roller quality ledger: vehicle=%s grass=%s vanillaArea=%.3f capturedGrassArea=%.3f successfulArea=%.3f prevalidated=%d accepted=%d/%d changed=%s quality=%.3f",
                self.getName ~= nil and self:getName() or "roller",
                tostring(self.spec_roller ~= nil
                    and self.spec_roller.isGrassRoller == true),
                tonumber(realArea) or 0,
                grassArea,
                successfulArea,
                prevalidatedGrassCellCount,
                acceptedCells or 0,
                touchedCells or 0,
                tostring(ledgerChanged == true),
                quality)
        end
    end
    return realArea, totalArea
end

function TerraLogic:processMulcherArea(superFunc, workArea, dt)
    local function processDropoutArea(vehicle, area, deltaTime)
        return vehicle:processSurfacePatchDropoutArea(
            superFunc, area, deltaTime, "mulcherPatch"
        )
    end
    local realArea, totalArea, processedAreas = self:processOverSpeedStoneArea(
        processDropoutArea, workArea, dt)
    local quality, yieldPenalty = TerraLogicQualityManager:getWorkQualityModel(
        self, math.abs(self:getLastSpeed(true) or 0), "mulch")
    local entries = processedAreas or {{
        workArea = workArea,
        realArea = tonumber(realArea) or 0
    }}
    for _, entry in ipairs(entries) do
        TerraLogicQualityManager:recordWorkArea(
            entry.workArea or workArea, "mulch", quality,
            tonumber(entry.realArea) or 0, 0.025, 0.025,
            self, yieldPenalty)
    end
    return realArea, totalArea
end

local function getIsShopMechanicalWeederCategory(category)
    local normalized = string.lower(tostring(category or ""))
    return normalized == "weeders"
        or string.find(normalized, "weeder", 1, true) ~= nil
end

function TerraLogic:processWeederArea(superFunc, workArea, dt)
    local terraLogicSpec = self.spec_terraLogic
    local isShopMechanicalWeeder = getIsShopMechanicalWeederCategory(
        terraLogicSpec ~= nil and terraLogicSpec.storeCategory or nil)
    if self.spec_weeder ~= nil
        and self.spec_weeder.isGrasslandWeeder == true
        and not isShopMechanicalWeeder then
        -- The Vanilla Puler/Aerostar/Super 7 weeders also set the misleading
        -- grassland flag. Only bypass tools outside the actual Weeders shop
        -- category; those regular mechanical weeders must keep TerraLogic.
        return superFunc(self, workArea, dt)
    end
    local isHoe = self.spec_weeder ~= nil
        and self.spec_weeder.isHoeWeeder == true
    local profileName = isHoe and "hoePatch" or "weederPatch"
    local cropDamageProfileName = isHoe
        and "hoeCropDamage" or "weederCropDamage"
    local function processDropoutArea(vehicle, area, deltaTime)
        return vehicle:processSurfacePatchDropoutArea(
            superFunc, area, deltaTime, profileName
        )
    end
    local realArea, totalArea =
        self:processOverSpeedStoneArea(
            processDropoutArea, workArea, dt)
    if terraLogicSpec ~= nil
        and terraLogicSpec.liveWorkQualityGroups ~= nil then
        terraLogicSpec.liveWorkQualityGroups.herbicide = nil
    end
    -- This secondary stage runs after normal weed removal. If an island is
    -- genuinely cultivated, the quality manager invalidates seed/rolling and
    -- any legacy weed-control state in the same fixed cells. It never records
    -- accidental crop destruction as useful cultivation.
    applyWeederCropDamage(self, workArea, cropDamageProfileName)
    return realArea, totalArea
end

function TerraLogic:processStonePickerArea(superFunc, workArea, dt)
    local function processDropoutArea(vehicle, area, deltaTime)
        return vehicle:processSurfacePatchDropoutArea(
            superFunc, area, deltaTime, "stonePickerPatch"
        )
    end
    return self:processOverSpeedStoneArea(
        processDropoutArea, workArea, dt
    )
end

-- Implement recognition ----------------------------------------------------

-- Reads the store category used as one signal for profile selection.
local function getStoreCategory(self)
    local terraLogicSpec = self.spec_terraLogic
    if terraLogicSpec ~= nil and terraLogicSpec.storeCategoryResolved == true then
        return terraLogicSpec.storeCategory or "unknown"
    end
    local category = "unknown"
    if g_storeManager == nil or self.configFileName == nil then
        return category
    end
    local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)
    if storeItem ~= nil and storeItem.categoryName ~= nil then
        category = string.lower(tostring(storeItem.categoryName))
    end
    if terraLogicSpec ~= nil then
        terraLogicSpec.storeCategory = category
        terraLogicSpec.storeCategoryResolved = true
    end
    return category
end

-- Yield balance belongs to the processed work component, not to the vehicle's
-- primary TerraLogic class. Combination implements therefore use seed values for
-- seed placement and application values for fertilizer/lime instead of
-- accidentally reusing one profile for every specialization.
function TerraLogic.getWorkQualityBalance(self, component, fillTypeIndex)
    local profiles = TerraLogicImplementProfiles.YIELD_QUALITY
    local profile = nil
    if component == "soilPlow" or component == "soilCultivate"
        or component == "soilDirect" then
        profile = TerraLogicQualityManager.GROUP_DEFINITIONS.soil
    elseif component == "seed" then
        local category = getStoreCategory(self)
        if category == "planters"
            or string.find(category, "planter", 1, true) ~= nil then
            profile = profiles.precisionPlanter
        elseif self.spec_sowingMachine ~= nil
            and self.spec_sowingMachine.useDirectPlanting == true then
            profile = profiles.directDrill
        else
            profile = profiles.sowingMachine
        end
    elseif component == "fertilizer" then
        profile = TerraLogicQualityManager.GROUP_DEFINITIONS.fertilizer
    elseif component == "lime" then
        profile = TerraLogicQualityManager.GROUP_DEFINITIONS.lime
    elseif component == "herbicide" then
        profile = TerraLogicQualityManager.GROUP_DEFINITIONS.herbicide
    elseif component == "roller" then
        profile = TerraLogicQualityManager.GROUP_DEFINITIONS.roller
    end
    local fallback = TerraLogicQualityManager.COMPONENTS[component]
    return profile or {
        weight = fallback ~= nil and fallback.yieldWeight or 0,
        maxPenalty = fallback ~= nil and fallback.maxYieldPenalty or 0
    }
end

function TerraLogic:getOverSpeedGroundToolType()
    if self.spec_mower ~= nil then
        return "mower", TerraLogic.IMPLEMENT_CLASSES.mower
    end
    if self.spec_windrower ~= nil then
        return "windrower", TerraLogic.IMPLEMENT_CLASSES.windrower
    end
    if self.spec_tedder ~= nil then
        return "tedder", TerraLogic.IMPLEMENT_CLASSES.tedder
    end
    if self.spec_baler ~= nil then
        return "baler", TerraLogic.IMPLEMENT_CLASSES.baler
    end
    if self.spec_forageWagon ~= nil then
        local category = string.lower(tostring(getStoreCategory(self) or ""))
        -- Only actual shop-category loader wagons are supported. Ordinary
        -- trailers and pickup-capable auger/transfer wagons retain Vanilla.
        if string.find(category, "loaderwagons", 1, true) ~= nil then
            return "loaderWagon", TerraLogic.IMPLEMENT_CLASSES.loaderWagon
        end
        return nil, nil
    end
    if self.spec_plow ~= nil then
        return "plow", TerraLogic.IMPLEMENT_CLASSES.plow
    end
    if self.spec_sowingMachine ~= nil then
        local category = getStoreCategory(self)
        if category == "planters"
            or string.find(category, "planter", 1, true) ~= nil then
            return "precisionPlanter", TerraLogic.IMPLEMENT_CLASSES.precisionPlanter
        end
        if self.spec_sowingMachine.useDirectPlanting == true then
            return "directDrill", TerraLogic.IMPLEMENT_CLASSES.directDrill
        end
        return "sowingMachine", TerraLogic.IMPLEMENT_CLASSES.sowingMachine
    end
    if self.spec_cultivator ~= nil then
        local category = getStoreCategory(self)
        if category == "spaders" then
            return "spader", TerraLogic.IMPLEMENT_CLASSES.spader
        end
        if category == "powerharrows" or self.spec_cultivator.isPowerHarrow == true then
            return "powerHarrow", TerraLogic.IMPLEMENT_CLASSES.powerHarrow
        end
        if category == "discharrows" then
            return "discHarrow", TerraLogic.IMPLEMENT_CLASSES.discHarrow
        end
        if category == "subsoilers" or self.spec_cultivator.isSubsoiler == true then
            return "subsoiler", TerraLogic.IMPLEMENT_CLASSES.subsoiler
        end
        if self.spec_cultivator.useDeepMode == true then
            return "cultivator", TerraLogic.IMPLEMENT_CLASSES.cultivator
        end
        return "shallowCultivator", TerraLogic.IMPLEMENT_CLASSES.shallowCultivator
    end
    if self.spec_roller ~= nil then
        return "roller", TerraLogic.IMPLEMENT_CLASSES.roller
    end
    if self.spec_mulcher ~= nil then
        return "mulcher", TerraLogic.IMPLEMENT_CLASSES.mulcher
    end
    if self.spec_stonePicker ~= nil then
        return "stonePicker", TerraLogic.IMPLEMENT_CLASSES.stonePicker
    end
    if self.spec_weeder ~= nil then
        local category = getStoreCategory(self)
        if self.spec_weeder.isGrasslandWeeder == true
            and not getIsShopMechanicalWeederCategory(category) then
            return nil, nil
        end
        if self.spec_weeder.isHoeWeeder == true then
            return "hoe", TerraLogic.IMPLEMENT_CLASSES.hoe
        end
        return "weeder", TerraLogic.IMPLEMENT_CLASSES.weeder
    end
    if self.spec_sprayer ~= nil then
        local category = string.lower(tostring(getStoreCategory(self) or ""))
        -- Category checks deliberately precede all generic sprayer handling.
        -- Transport and utility barrels share broad GIANTS code with working
        -- applicators, so only explicit working shop groups are supported.
        if string.find(category, "slurrytransport", 1, true) ~= nil then
            return nil, nil
        end
        if string.find(category, "manurespreaders", 1, true) ~= nil then
            return "manureSpreader", TerraLogic.IMPLEMENT_CLASSES.manureSpreader
        end
        if string.find(category, "slurrytanks", 1, true) ~= nil then
            return "slurrySpreader", TerraLogic.IMPLEMENT_CLASSES.slurrySpreader
        end
        if string.find(category, "slurrytools", 1, true) ~= nil then
            return "slurryApplicator", TerraLogic.IMPLEMENT_CLASSES.slurryApplicator
        end
        local isSolidSpreader = string.find(category, "fertilizer", 1, true) ~= nil
            and string.find(category, "spreader", 1, true) ~= nil
        local isLiquidSprayer = string.find(category, "sprayer", 1, true) ~= nil
        if isSolidSpreader then
            return "fertilizerSpreader", TerraLogic.IMPLEMENT_CLASSES.fertilizerSpreader
        end
        if isLiquidSprayer then
            return "liquidSprayer", TerraLogic.IMPLEMENT_CLASSES.liquidSprayer
        end
        -- Fill type alone is deliberately not a recognition signal. Unknown
        -- categories retain their original speed limit and processing.
        return nil, nil
    end
    return nil, nil
end

function TerraLogic:updateOverSpeedImplementClass()
    local spec = self.spec_terraLogic
    if spec == nil then
        return
    end

    local classKey, implementClass = self:getOverSpeedGroundToolType()
    spec.storeCategory = getStoreCategory(self)
    local classificationSource = "specialization"
    if self.spec_cultivator ~= nil then
        if spec.storeCategory == "spaders" or spec.storeCategory == "powerharrows"
            or spec.storeCategory == "discharrows" or spec.storeCategory == "subsoilers" then
            classificationSource = "store category"
        elseif spec.storeCategory == "cultivators" then
            classificationSource = self.spec_cultivator.useDeepMode == true
                and "store cultivators + deep mode" or "store cultivators + shallow mode"
        elseif self.spec_cultivator.isSubsoiler == true then
            classificationSource = "cultivator.isSubsoiler"
        elseif self.spec_cultivator.isPowerHarrow == true then
            classificationSource = "cultivator.isPowerHarrow"
        else
            classificationSource = self.spec_cultivator.useDeepMode == true
                and "cultivator.useDeepMode=true" or "cultivator.useDeepMode=false"
        end
    elseif self.spec_sowingMachine ~= nil then
        if classKey == "precisionPlanter" then
            classificationSource = "store planter category"
        else
            classificationSource = self.spec_sowingMachine.useDirectPlanting == true
                and "sowingMachine.useDirectPlanting" or "sowingMachine specialization"
        end
    end
    spec.implementClassKey = classKey
    spec.isMowerTool = self.spec_mower ~= nil
    spec.isSurfaceForageTool = self.spec_mower ~= nil
        or self.spec_windrower ~= nil or self.spec_tedder ~= nil
        or self.spec_baler ~= nil or self.spec_forageWagon ~= nil
    spec.classificationSource = classificationSource
    spec.isGroundTool = implementClass ~= nil
        and implementClass.work ~= nil
        and implementClass.work.groundContactTool == true
    spec.groundToolType = implementClass ~= nil and implementClass.name or "Not ground-engaging"
    spec.workDepthCm = implementClass ~= nil and implementClass.work ~= nil
        and implementClass.work.depthCm or 0
    spec.impactDepthFactor = implementClass ~= nil and implementClass.impacts ~= nil
        and implementClass.impacts.depthFactor or 1
    spec.impactStoneProtection = implementClass ~= nil
        and implementClass.impacts ~= nil
        and implementClass.impacts.stoneProtection == true
    spec.impactMediumDamageFactor = implementClass ~= nil
        and implementClass.impacts ~= nil
        and implementClass.impacts.stoneProtection == true
        and implementClass.impacts.mediumDamageFactor or 1
    spec.additionalDraftEnabled = implementClass ~= nil and implementClass.draft ~= nil
        and implementClass.draft.enabled == true
    spec.additionalDraftScale = implementClass ~= nil and implementClass.draft ~= nil
        and implementClass.draft.overspeedScale or 0
    spec.implementAbrasionFactor = implementClass ~= nil and implementClass.wear ~= nil
        and implementClass.wear.abrasionFactor or 0
    spec.wearModel = implementClass ~= nil and implementClass.wear ~= nil
        and implementClass.wear.model or "soil"
    spec.yieldWeight = implementClass ~= nil and implementClass.yield ~= nil
        and implementClass.yield.weight or 0
    spec.maxYieldPenalty = implementClass ~= nil and implementClass.yield ~= nil
        and implementClass.yield.maxPenalty or 0
    spec.dropoutProfile = implementClass ~= nil and implementClass.dropoutProfile or nil
    spec.impactDropoutProfile = implementClass ~= nil
        and implementClass.impactDropoutProfile or nil
    local classOptimalSpeed = implementClass ~= nil and implementClass.work ~= nil
        and tonumber(implementClass.work.optimalSpeedKph) or nil
    if classOptimalSpeed ~= nil and spec.ratedSpeed ~= nil then
        spec.optimalSpeed = math.min(spec.ratedSpeed, classOptimalSpeed)
    else
        spec.optimalSpeed = spec.ratedSpeed
    end
    spec.safeSpeed, spec.safeSpeedRatio, spec.safeSpeedSource,
        spec.shopToClassSpeedFactor, spec.safeSpeedFallback =
        TerraLogic.resolveWearSafeSpeed(spec.ratedSpeed, implementClass)
end

-- Foldable rollers do not have a conventional lowered state. Compare their
-- synchronized fold animation time directly with the fold limits of the actual
-- ROLLER WorkAreas. WorkArea:getIsWorkAreaActive() is not sufficient here:
-- some rollers report ground contact while still folded for transport. Every
-- other implement keeps TerraLogic's established detection unchanged.
function TerraLogic:getIsOverSpeedWorkAreaInWorkPosition()
    if self.spec_roller == nil or self.spec_foldable == nil then
        return true
    end

    local workAreaSpec = self.spec_workArea
    if workAreaSpec == nil or workAreaSpec.workAreas == nil then
        return true
    end

    local foldTime = self.getFoldAnimTime ~= nil
        and tonumber(self:getFoldAnimTime())
        or tonumber(self.spec_foldable.foldAnimTime)
    if foldTime == nil then return true end

    local hasRollerWorkArea = false
    for _, workArea in ipairs(workAreaSpec.workAreas) do
        local isRollerArea = workArea.functionName == "processRollerArea"
            or (WorkAreaType ~= nil and WorkAreaType.ROLLER ~= nil
                and workArea.type == WorkAreaType.ROLLER)
        if isRollerArea then
            hasRollerWorkArea = true
            local minimum = tonumber(workArea.foldMinLimit) or 0
            local maximum = tonumber(workArea.foldMaxLimit) or 1
            local isInsideWorkRange
            if workArea.foldLimitedOuterRange == true then
                -- Same boundary semantics as GIANTS' Foldable specialization.
                isInsideWorkRange = foldTime <= minimum or foldTime > maximum
            else
                isInsideWorkRange = foldTime >= minimum and foldTime <= maximum
            end
            if isInsideWorkRange then
                return true
            end
        end
    end

    -- Preserve compatibility with unusual mod rollers that expose no standard
    -- roller WorkArea at all. Recognized roller areas, however, must have at
    -- least one area inside its configured fold range.
    return not hasRollerWorkArea
end

function TerraLogic:getIsOverSpeedWorkAreaProcessing()
    local spec = self.spec_terraLogic
    if spec == nil or not spec.isGroundTool then
        return false
    end
    local powerConsumer = self.spec_powerConsumer
    local maxForce = powerConsumer ~= nil and tonumber(powerConsumer.maxForce) or 0
    if spec.baseMaxForce ~= nil then
        maxForce = spec.baseMaxForce
    end
    if not spec.isMowerTool and (maxForce == nil or maxForce <= 0) then
        return false
    end

    if self.spec_workArea == nil
        or self.spec_workArea.workAreas == nil
        or #self.spec_workArea.workAreas == 0 then
        return false
    end
    if not TerraLogic.getIsOverSpeedWorkAreaInWorkPosition(self) then
        return false
    end
    return true
end

function TerraLogic:getIsOverSpeedGroundContactActive()
    local spec = self.spec_terraLogic
    if spec == nil or not spec.isGroundTool then
        return false
    end
    spec.workDetectionSource = "inactive"

    -- No PTO/turned-on requirement by design. Abrasion comes from dragging the
    -- working elements through the ground. This GIANTS function checks the
    -- complete implement chain and correctly rejects a raised parent/tool.
    if self.getIsImplementChainLowered ~= nil then
        if not self:getIsImplementChainLowered(true) then
            spec.workDetectionSource = "implement chain raised"
            return false
        end
    elseif not spec.isMowerTool then
        return false
    end
    -- Some attachment chains can report their parent as lowered while this
    -- individual tool is still in transport position. Require the tool's own
    -- lowered state as a second guard whenever the specialization exposes it.
    if self.getIsLowered ~= nil and self:getIsLowered() == false then
        spec.workDetectionSource = "implement raised"
        return false
    end
    -- A powered surface tool such as a mulcher can remain lowered while its
    -- rotor is switched off. Rollers normally have no turn-on specialization
    -- and therefore continue through the lowered/contact path.
    if (spec.wearModel == "surface" or self.spec_stonePicker ~= nil)
        and self.spec_turnOnVehicle ~= nil
        and self.getIsTurnedOn ~= nil
        and not self:getIsTurnedOn() then
        spec.workDetectionSource = "powered tool switched off"
        return false
    end
    if not TerraLogic.getIsOverSpeedWorkAreaInWorkPosition(self) then
        spec.workDetectionSource = "work areas outside fold range"
        return false
    end
    if not self:getIsOverSpeedWorkAreaProcessing() then
        return false
    end

    spec.workDetectionSource = spec.isMowerTool
        and "active lowered mower" or "lowered + maxForce"
    return true
end

function TerraLogic:getOverSpeedWorkingWidth()
    local spec = self.spec_terraLogic
    if spec.workingWidth ~= nil then
        return spec.workingWidth
    end

    local width = 0
    if self.spec_workArea ~= nil and self.spec_workArea.workAreas ~= nil then
        for _, workArea in ipairs(self.spec_workArea.workAreas) do
            if workArea.start ~= nil and workArea.width ~= nil then
                local sx, _, sz = getWorldTranslation(workArea.start)
                local wx, _, wz = getWorldTranslation(workArea.width)
                local dx, dz = wx - sx, wz - sz
                width = math.max(width, math.sqrt(dx * dx + dz * dz))
            end
        end
    end

    if width <= 0 then
        width = tonumber(self.sizeWidth) or 0
    end

    spec.workingWidth = width > 0 and width or 1
    return spec.workingWidth
end

function TerraLogic:getOverSpeedSoilSamplePosition()
    local workAreas = self.spec_workArea ~= nil and self.spec_workArea.workAreas or nil
    if workAreas ~= nil then
        local fallbackWorkArea = nil
        for _, workArea in ipairs(workAreas) do
            if fallbackWorkArea == nil and workArea.start ~= nil and workArea.width ~= nil then
                fallbackWorkArea = workArea
            end
            if workArea.start ~= nil and workArea.width ~= nil
                and self.getIsWorkAreaProcessing ~= nil
                and self:getIsWorkAreaProcessing(workArea) then
                local sx, _, sz = getWorldTranslation(workArea.start)
                local wx, _, wz = getWorldTranslation(workArea.width)
                return (sx + wx) * 0.5, (sz + wz) * 0.5, "activeWorkArea"
            end
        end

        if fallbackWorkArea ~= nil then
            local sx, _, sz = getWorldTranslation(fallbackWorkArea.start)
            local wx, _, wz = getWorldTranslation(fallbackWorkArea.width)
            return (sx + wx) * 0.5, (sz + wz) * 0.5, "firstWorkArea"
        end
    end

    local node = self.rootNode
    if self.spec_powerConsumer ~= nil and self.spec_powerConsumer.forceNode ~= nil then
        node = self.spec_powerConsumer.forceNode
    end
    if node ~= nil then
        local x, _, z = getWorldTranslation(node)
        return x, z, "forceNode"
    end

    return nil, nil, "noPosition"
end

function TerraLogic:getRawPrecisionFarmingSoilType(x, z, soilMap)
    -- PF keeps an unmasked raw map internally even when its public query hides
    -- unsampled or stale soil data. Try the known object/map layouts first.
    if soilMap ~= nil then
        -- This is PF's actual physical soil-type storage. It is deliberately
        -- read directly: SoilMap:getTypeIndexAtWorldPos applies the gameplay
        -- coverage mask and therefore returns 0 until soil data is purchased
        -- or sampled. PF itself uses this same bit-vector map for its field
        -- soil distribution calculation, independently of that coverage.
        local bitVectorMap = tonumber(soilMap.bitVectorMap)
        local terrainSize = g_currentMission ~= nil and tonumber(g_currentMission.terrainSize) or nil
        if bitVectorMap ~= nil and bitVectorMap ~= 0
            and terrainSize ~= nil and terrainSize > 0
            and getBitVectorMapSize ~= nil
            and getBitVectorMapPoint ~= nil then
            local okSize, mapWidth, mapHeight = pcall(getBitVectorMapSize, bitVectorMap)
            mapWidth = tonumber(mapWidth)
            mapHeight = tonumber(mapHeight)
            if okSize and mapWidth ~= nil and mapWidth > 1
                and mapHeight ~= nil and mapHeight > 1 then
                local pixelX = (x + terrainSize * 0.5) / terrainSize * (mapWidth - 1)
                local pixelZ = (z + terrainSize * 0.5) / terrainSize * (mapHeight - 1)
                pixelX = math.max(0, math.min(mapWidth - 1, pixelX))
                pixelZ = math.max(0, math.min(mapHeight - 1, pixelZ))

                local numChannels = tonumber(soilMap.numChannels)
                if numChannels == nil and getBitVectorMapNumChannels ~= nil then
                    local okChannels, detectedChannels = pcall(getBitVectorMapNumChannels, bitVectorMap)
                    if okChannels then
                        numChannels = tonumber(detectedChannels)
                    end
                end
                if numChannels ~= nil and numChannels > 0 then
                    local okValue, packedValue = pcall(
                        getBitVectorMapPoint,
                        bitVectorMap,
                        pixelX,
                        pixelZ,
                        0,
                        numChannels
                    )
                    packedValue = tonumber(packedValue)
                    if okValue and packedValue ~= nil then
                        local rawValue = bit32 ~= nil and bit32.band(packedValue, 3)
                            or (packedValue % 4)
                        if rawValue >= 0 and rawValue <= 3 then
                            return rawValue + 1, "soilMap.bitVectorMap (unmasked)"
                        end
                    end
                end
            end
        end

        local nestedMapFields = {
            "map", "soilMap", "soilTypeMap", "densityMap", "valueMap", "localMap"
        }
        for _, fieldName in ipairs(nestedMapFields) do
            local nestedMap = soilMap[fieldName]
            if type(nestedMap) == "table" or type(nestedMap) == "userdata" then
                local valueMethod = nestedMap.getValueAtWorldPos
                if type(valueMethod) == "function" then
                    local okValue, rawValue = pcall(valueMethod, nestedMap, x, z)
                    rawValue = tonumber(rawValue)
                    if okValue and rawValue ~= nil and rawValue >= 0 and rawValue <= 3 then
                        return rawValue + 1, "soilMap." .. fieldName .. ".getValueAtWorldPos"
                    end
                end
            end
        end

        if getDensityTypeIndexAtWorldPos ~= nil then
            local handleFields = {
                "mapId", "soilMapId", "soilTypeMapId", "densityMapId", "dataPlaneId", "id"
            }
            for _, fieldName in ipairs(handleFields) do
                local mapId = tonumber(soilMap[fieldName])
                if mapId ~= nil and mapId ~= 0 then
                    local okValue, rawValue = pcall(getDensityTypeIndexAtWorldPos, mapId, x, 0, z)
                    rawValue = tonumber(rawValue)
                    if okValue and rawValue ~= nil and rawValue >= 0 and rawValue <= 3 then
                        return rawValue + 1, "soilMap." .. fieldName .. "/densityType"
                    end
                end
            end
        end
    end

    if g_terrainNode == nil
        or getTerrainDataPlaneByName == nil
        or getDensityTypeIndexAtWorldPos == nil then
        return nil, "raw PF/terrain API unavailable"
    end

    local layerNames = {"soilMap", "soilType"}
    for _, layerName in ipairs(layerNames) do
        local okPlane, dataPlaneId = pcall(getTerrainDataPlaneByName, g_terrainNode, layerName)
        if okPlane and dataPlaneId ~= nil and dataPlaneId ~= 0 then
            local okValue, rawTypeIndex = pcall(getDensityTypeIndexAtWorldPos, dataPlaneId, x, 0, z)
            rawTypeIndex = tonumber(rawTypeIndex)
            if okValue and rawTypeIndex ~= nil and rawTypeIndex >= 0 and rawTypeIndex <= 3 then
                return rawTypeIndex + 1, "terrainDataPlane:" .. layerName
            end
        end
    end

    -- Some maps expose soilMap as an info layer rather than a named terrain
    -- data plane. The engine accepts compatible layer handles for the same raw
    -- density-type query; pcall keeps incompatible maps completely safe.
    if getInfoLayerFromTerrain ~= nil then
        for _, layerName in ipairs(layerNames) do
            local okLayer, infoLayerId = pcall(getInfoLayerFromTerrain, g_terrainNode, layerName)
            if okLayer and infoLayerId ~= nil and infoLayerId ~= 0 then
                local okValue, rawTypeIndex = pcall(getDensityTypeIndexAtWorldPos, infoLayerId, x, 0, z)
                rawTypeIndex = tonumber(rawTypeIndex)
                if okValue and rawTypeIndex ~= nil and rawTypeIndex >= 0 and rawTypeIndex <= 3 then
                    return rawTypeIndex + 1, "terrainInfoLayer:" .. layerName
                end
            end
        end
    end

    return nil, "raw PF/terrain soil layer not found"
end

-- Precision Farming and draft ---------------------------------------------

-- Samples soil data at a throttled interval for draft and abrasion modifiers.
function TerraLogic:updateOverSpeedSoilData(dt)
    local spec = self.spec_terraLogic
    spec.soilUpdateTimer = spec.soilUpdateTimer - dt
    if spec.soilUpdateTimer > 0 then
        return
    end
    spec.soilUpdateTimer = TerraLogic.SOIL_UPDATE_INTERVAL_MS

    local previousResistance = spec.resistanceMultiplier
    local previousAbrasion = spec.abrasionMultiplier
    local previousSoilType = spec.soilTypeIndex

    spec.soilTypeIndex = 0
    spec.soilName = "Vanilla / unknown"
    spec.pfActive = false
    spec.pfMode = TerraLogicMain ~= nil
        and TerraLogicMain.precisionFarmingMode or "auto"
    spec.resistanceMultiplier = 1
    spec.abrasionMultiplier = 1
    spec.impactFrequencyFactor = 1
    spec.impactSeverityFactor = 1
    spec.impactSoilSource = "Neutral fallback"
    spec.resistanceSource = "Vanilla"
    spec.abrasionSource = "Vanilla"

    local function finalizeSoilValues()
        if TerraLogicMain ~= nil then
            local resistanceOverride = tonumber(TerraLogicMain.resistanceOverride) or 0
            local abrasionOverride = tonumber(TerraLogicMain.abrasionOverride) or 0
            if resistanceOverride > 0 then
                spec.resistanceMultiplier = resistanceOverride
                spec.resistanceSource = "Console override"
            end
            if abrasionOverride > 0 then
                spec.abrasionMultiplier = abrasionOverride
                spec.abrasionSource = "Console override"
            end
        end

        if spec.wearModel == "surface" then
            spec.abrasionMultiplier = 1
            spec.abrasionSource = "Surface wear / PF ignored"
        end

        if previousSoilType ~= spec.soilTypeIndex
            or previousResistance ~= spec.resistanceMultiplier
            or previousAbrasion ~= spec.abrasionMultiplier then
            spec.telemetryElapsedMs = 0
            spec.telemetryDistanceM = 0
            spec.telemetryVanillaDamage = 0
            spec.telemetryCurrentDamage = 0
            spec.telemetryActiveMs = 0
            spec.telemetrySpeedMultiplierTime = 0
            spec.telemetryTotalMultiplierTime = 0
            spec.telemetryDraftMultiplierTime = 0
            spec.vanillaDamagePerHectare = nil
            spec.currentDamagePerHectare = nil
            spec.telemetryWorking = false
        end
    end

    if spec.pfMode == "off" then
        finalizeSoilValues()
        return
    end

    -- Precision Farming is entirely optional. The resolver supports current
    -- instance, metatable/class methods and several mission-owned map paths.
    if TerraLogicMain == nil
        or TerraLogicMain.getPrecisionFarmingSoilMap == nil then
        finalizeSoilValues()
        return
    end

    local soilMap, getSoilTypeIndex, pfSource = TerraLogicMain:getPrecisionFarmingSoilMap()
    spec.pfSource = pfSource or "not detected"
    if not TerraLogicMain.pfResolutionLogged then
        TerraLogicMain.pfResolutionLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] PF resolver: active=%s source=%s",
            tostring(soilMap ~= nil and getSoilTypeIndex ~= nil),
            tostring(spec.pfSource)
        )
    end
    if soilMap == nil or getSoilTypeIndex == nil then
        finalizeSoilValues()
        return
    end

    spec.pfActive = true

    local x, z, positionSource = self:getOverSpeedSoilSamplePosition()
    if x == nil or z == nil then
        finalizeSoilValues()
        return
    end

    local hasFieldSoilData = false
    if g_currentMission.terrainDetailId ~= nil and getDensityAtWorldPos ~= nil then
        local okField, fieldValue = pcall(
            getDensityAtWorldPos,
            g_currentMission.terrainDetailId,
            x,
            0,
            z
        )
        hasFieldSoilData = okField and tonumber(fieldValue) ~= nil and fieldValue ~= 0
    end

    local rawSoilTypeIndex, rawSource = self:getRawPrecisionFarmingSoilType(x, z, soilMap)
    local ok, visibleSoilTypeIndex = pcall(
        getSoilTypeIndex,
        soilMap,
        x,
        z
    )
    local soilTypeIndex = rawSoilTypeIndex
    local soilValueSource = rawSource
    if soilTypeIndex == nil then
        soilTypeIndex = visibleSoilTypeIndex
        soilValueSource = "PF visible fallback"
    end
    spec.pfLastQueryOk = ok
    spec.pfLastSoilTypeIndex = soilTypeIndex
    spec.pfLastPositionSource = positionSource
    spec.pfSoilValueSource = soilValueSource
    if positionSource == "activeWorkArea" and not spec.pfQueryLogged then
        spec.pfQueryLogged = true
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] PF soil query: vehicle=%s position=%s x=%.2f z=%.2f pfOk=%s visibleIndex=%s finalIndex=%s valueSource=%s",
            self.getName ~= nil and self:getName() or tostring(self.configFileName),
            tostring(positionSource),
            x,
            z,
            tostring(ok),
            tostring(visibleSoilTypeIndex),
            tostring(soilTypeIndex),
            tostring(soilValueSource)
        )

        if rawSoilTypeIndex == nil and type(soilMap) == "table"
            and not TerraLogicMain.pfFieldDumpLogged then
            TerraLogicMain.pfFieldDumpLogged = true
            local fields = {}
            for key, value in pairs(soilMap) do
                local lowerKey = string.lower(tostring(key))
                if string.find(lowerKey, "map", 1, true) ~= nil
                    or string.find(lowerKey, "soil", 1, true) ~= nil
                    or string.find(lowerKey, "density", 1, true) ~= nil
                    or string.find(lowerKey, "layer", 1, true) ~= nil then
                    fields[#fields + 1] = string.format("%s:%s", tostring(key), type(value))
                end
            end
            table.sort(fields)
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] PF soilMap fields: %s",
                #fields > 0 and table.concat(fields, ", ") or "<none>"
            )
        end
    end
    local soilData = TerraLogic.SOIL_DATA[tonumber(soilTypeIndex)]
    if soilData ~= nil then
        spec.soilTypeIndex = soilTypeIndex
        spec.soilName = soilData.name
        spec.resistanceMultiplier = soilData.resistance
        spec.abrasionMultiplier = soilData.abrasion
        if hasFieldSoilData then
            spec.impactFrequencyFactor = soilData.impactFrequency
            spec.impactSeverityFactor = soilData.impactSeverity
            spec.impactSoilSource = "Precision Farming"
        end
        spec.resistanceSource = "Precision Farming"
        spec.abrasionSource = "Precision Farming"
    end
    finalizeSoilValues()
end

function TerraLogic:updateOverSpeedResistance()
    local spec = self.spec_terraLogic
    local powerConsumer = self.spec_powerConsumer
    if powerConsumer == nil or powerConsumer.maxForce == nil or powerConsumer.maxForce <= 0 then
        return
    end

    -- Detect configuration/work-mode/third-party changes and adopt the changed
    -- value as the new unmodified base instead of fighting the other system.
    if spec.lastAppliedMaxForce == nil
        or math.abs(powerConsumer.maxForce - spec.lastAppliedMaxForce) > 0.0001 then
        spec.baseMaxForce = powerConsumer.maxForce
    end

    local modEnabled = TerraLogicMain == nil or TerraLogicMain.enabled ~= false
    if not modEnabled and spec.impactDropoutState ~= nil then
        spec.impactDropoutState = nil
        spec.impactDropoutStatus = "inactive"
        spec.impactDropoutFailedLanes = 0
        spec.impactDropoutTotalLanes = 0
    end
    local draftModel = TerraLogicSettings ~= nil
        and TerraLogicSettings:getEffectiveDraftModel() or "terraLogic"
    local groundContactActive = modEnabled and self:getIsOverSpeedGroundContactActive()
    local draftContactActive = groundContactActive and spec.additionalDraftEnabled == true
    local damage = self.getDamageAmount ~= nil and self:getDamageAmount() or 0
    local speedRatio = draftContactActive and self:getWorkingSpeedRatio() or nil
    local draftMultiplier = 1
    if speedRatio ~= nil then
        draftMultiplier = self:getOverSpeedBalanceFactors(speedRatio)
    end
    local damageResistance = draftContactActive
        and self:getDamageResistanceMultiplier(damage) or 1
    local soilResistance = draftContactActive and spec.resistanceMultiplier or 1
    local effectiveResistance = soilResistance * damageResistance * draftMultiplier
    local appliedResistance = effectiveResistance
    local mrCompensation = 1

    if draftModel == "mr" then
        -- More Realistic owns the complete live draft calculation. Keep its
        -- unmodified XML base force and do not stack TerraLogic soil/damage/speed
        -- multipliers on top of it.
        appliedResistance = 1
        damageResistance = 1
        draftMultiplier = 1
        effectiveResistance = 1
    elseif TerraLogicSettings ~= nil
        and TerraLogicSettings:isMoreRealisticActive() then
        -- MR multiplies maxForce later in PowerConsumer.onUpdate. When the
        -- administrator explicitly selects TerraLogic, divide that known MR factor
        -- out here so the resulting physical force is TerraLogic's value, not a
        -- stacked TerraLogic*MR curve.
        local speed = math.abs(tonumber(self.lastSpeedReal) or 0) * 3600
        local weather = g_currentMission ~= nil
            and g_currentMission.environment ~= nil
            and g_currentMission.environment.weather or nil
        local wetness = weather ~= nil and weather:getGroundWetness() or 0
        local category = self.mrPowerConsumerToolCategory or self.mrStoreCategory
        local mrSpeed = tonumber(PowerConsumer.mrGetDraftForceMultiplier(
            category, speed, wetness, self.mrPtoCurrentRpmRatio or 0)) or 1
        local mrSurface = tonumber(PowerConsumer.mrGetForceMultiplier(self)) or 1
        mrCompensation = math.max(mrSpeed * mrSurface, 0.05)
        appliedResistance = effectiveResistance / mrCompensation
    end

    powerConsumer.maxForce = spec.baseMaxForce * appliedResistance
    spec.lastAppliedMaxForce = powerConsumer.maxForce
    spec.damageResistanceMultiplier = damageResistance
    spec.currentDraftMultiplier = draftMultiplier
    spec.effectiveResistanceMultiplier = effectiveResistance
    spec.draftModel = draftModel
    spec.moreRealisticCompensation = mrCompensation
end

-- Preserve the original working-state result, but stop this implement from
-- contributing a hard limit to the towing vehicle's recursive speed query.
function TerraLogic:getSpeedLimit(superFunc, onlyIfWorking)
    local originalLimit, doCheckSpeedLimit = superFunc(self, onlyIfWorking)
    local spec = self.spec_terraLogic
    local modEnabled = TerraLogicMain == nil
        or TerraLogicMain.enabled ~= false

    -- Do not use the live lowered/contact result as the unlock condition here.
    -- GIANTS can query the recursive speed limit before the lowered state for
    -- the current physics tick has settled. That intermittently returned the
    -- XML/shop speed even though the plow was already working in the ground.
    --
    -- Returning infinity for an eligible ground/application/surface-dropout
    -- tool is safe: the original doCheckSpeedLimit value still tells the towing
    -- vehicle whether this implement is currently allowed to contribute a
    -- working limit at all. Actual wear, draft, quality and physical work stay
    -- guarded by their stricter live checks elsewhere.
    local surfaceDropoutProfile = spec ~= nil
        and TerraLogicDropoutManager:getProfile(spec.dropoutProfile) or nil
    local isSurfaceDropoutTool = spec ~= nil
        and surfaceDropoutProfile ~= nil
        and surfaceDropoutProfile.patternType == "surfaceIslands"
    local surfaceDropoutEligible = isSurfaceDropoutTool
        and getArePhysicalDropoutsEnabled()
    local dropoutDependentSpeedClass = spec ~= nil
        and TerraLogicImplementProfiles.DROPOUT_DEPENDENT_SPEED_CLASSES[
            spec.implementClassKey
        ] == true
    local dropoutSpeedConsequenceAvailable = not dropoutDependentSpeedClass
        or getArePhysicalDropoutsEnabled()
    -- Unlock only classes with a verified processing hook. This prevents a
    -- newly recognized, merely documented or zero-yield utility specialization
    -- from inheriting unlimited speed because it exposes WorkArea/MaxForce.
    local hasGameplayConsequence = spec ~= nil
        and TerraLogic.SPEED_UNLOCK_CONSEQUENCE_CLASSES[
            spec.implementClassKey
        ] == true
    local groundToolEligible = spec ~= nil
        and spec.isGroundTool == true
        and self:getIsOverSpeedWorkAreaProcessing()
        and not isSurfaceDropoutTool
        and hasGameplayConsequence
        and dropoutSpeedConsequenceAvailable
    local applicationActive = spec ~= nil
        and hasGameplayConsequence
        and self:getIsOverSpeedApplicationActive()
        and dropoutSpeedConsequenceAvailable
    if modEnabled
        and (groundToolEligible or surfaceDropoutEligible or applicationActive) then
        local rootVehicle = self.rootVehicle
            or (self.getRootVehicle ~= nil and self:getRootVehicle()) or self
        local automated = rootVehicle.getIsAIActive ~= nil
            and rootVehicle:getIsAIActive() or false
        if not automated and rootVehicle.getIsCpActive ~= nil then
            automated = rootVehicle:getIsCpActive()
        end
        local ad = rootVehicle.ad
        if not automated and ad ~= nil and ad.stateModule ~= nil
            and ad.stateModule.isActive ~= nil then
            automated = ad.stateModule:isActive()
        end
        if automated then
            spec.speedLimitUnlockEligible = false
            spec.speedLimitUnlockSource = "automation uses shop speed"
            return originalLimit, doCheckSpeedLimit
        end
        spec.speedLimitUnlockEligible = true
        if surfaceDropoutEligible then
            spec.speedLimitUnlockSource = "surface dropout tool"
        elseif groundToolEligible then
            spec.speedLimitUnlockSource = "ground tool + MaxForce"
        else
            spec.speedLimitUnlockSource = "active application tool"
        end
        if spec.speedLimitUnlockLogged ~= true then
            spec.speedLimitUnlockLogged = true
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] Speed-limit unlock active: vehicle=%s source=%s original=%s doCheck=%s",
                self.getName ~= nil and self:getName() or tostring(self.configFileName),
                spec.speedLimitUnlockSource,
                tostring(originalLimit),
                tostring(doCheckSpeedLimit)
            )
        end
        return math.huge, doCheckSpeedLimit
    end
    if spec ~= nil then
        spec.speedLimitUnlockEligible = false
        if modEnabled and (isSurfaceDropoutTool
                or dropoutDependentSpeedClass)
            and not getArePhysicalDropoutsEnabled() then
            spec.speedLimitUnlockSource = "physical dropouts disabled"
        else
            spec.speedLimitUnlockSource = modEnabled
                and (spec.isGroundTool == true
                    and not hasGameplayConsequence
                    and "no quality/dropout consequence" or "not eligible")
                or "mod disabled"
        end
    end
    return originalLimit, doCheckSpeedLimit
end

function TerraLogic:getWorkingSpeedRatio()
    local spec = self.spec_terraLogic
    if spec == nil or spec.optimalSpeed == nil then
        return nil
    end

    if not self:getIsOverSpeedGroundContactActive() then
        return nil
    end

    local currentSpeed = math.abs(self:getLastSpeed(true) or 0)
    -- A lowered implement standing still is ready, but it is not accumulating
    -- sliding abrasion. This also keeps the always-on HUD's dash state aligned
    -- with the actual wear model.
    if currentSpeed < 0.5 then
        return nil
    end
    return currentSpeed / spec.optimalSpeed, currentSpeed
end

-- Replaces active-work wear with the configured speed, soil and age model.
function TerraLogic:updateDamageAmount(superFunc, dt)
    local vanillaDamage = math.max(tonumber(superFunc(self, dt)) or 0, 0)

    local speedRatio = self:getWorkingSpeedRatio()
    if speedRatio == nil
        or (TerraLogicMain ~= nil and TerraLogicMain.enabled == false) then
        return vanillaDamage
    end

    local spec = self.spec_terraLogic
    local _, speedMultiplier = self:getOverSpeedBalanceFactors(speedRatio)
    local wearable = self.spec_wearable
    local actualWearRate = wearable ~= nil
        and math.max(tonumber(wearable.wearDuration) or 0, 0) or 0
    local referenceWearRate = getReferenceWearRate()
    local actualNeutralDamage = dt * actualWearRate * 0.35
    local referenceNeutralDamage = dt * referenceWearRate * 0.35
    local xmlWearRateFactor = referenceWearRate > 0
        and actualWearRate / referenceWearRate or 1
    local wearPolicy = getWearPolicy()
    local vanillaAgeUsageFactor = getVanillaAgeUsageFactor(self)
    local adjustedAgeUsageFactor =
        TerraLogic.getAdjustedAgeUsageFactor(self)
    local implementFactor = math.clamp(
        tonumber(spec.implementAbrasionFactor) or 0,
        0,
        1
    )
    local soilFactor = math.max(tonumber(spec.abrasionMultiplier) or 1, 0)
    local baselineAbrasionMultiplier, abrasiveLoad =
        getEffectiveAbrasionMultiplier(spec)
    local wearScale = getRuntimeBalanceMultiplier("wear")

    -- Recover the XML-neutral damage from Vanilla's already age-amplified
    -- return value, then apply TerraLogic's stretched 100-hour ageing ramp. This also
    -- safely migrates long-running saves without changing stored age/hours.
    local actualNeutralFromVanilla = vanillaDamage > 0
        and vanillaAgeUsageFactor > 0
        and vanillaDamage / vanillaAgeUsageFactor or actualNeutralDamage
    local policyBaselineDamage = actualNeutralFromVanilla
        * adjustedAgeUsageFactor
    if wearPolicy == "forceVanilla" then
        policyBaselineDamage = referenceNeutralDamage
            * adjustedAgeUsageFactor
    end
    local policyAdjustment = (policyBaselineDamage - vanillaDamage) * wearScale
    local abrasionAdjustment = policyBaselineDamage
        * (baselineAbrasionMultiplier - 1) * wearScale

    local abradedBaselineDamage = policyBaselineDamage
        * baselineAbrasionMultiplier
    local targetDamage
    if spec.wearModel == "surface" then
        -- Preserve the implement's own XML/Vanilla wear rate as requested.
        -- With M=v^3 per time and half the working time at v=2, the same
        -- hectare receives exactly four times the continuous damage.
        targetDamage = abradedBaselineDamage * speedMultiplier
    elseif speedMultiplier > 1 and wearPolicy == "normalize" then
        -- Preserve the anti-cheat normalization for extremely durable mod XMLs
        -- only above shop speed. At/below shop, the implement's own XML rate
        -- and the complete adjusted age factor receive the speed saving.
        targetDamage = abradedBaselineDamage
            + referenceNeutralDamage * adjustedAgeUsageFactor
                * baselineAbrasionMultiplier * (speedMultiplier - 1)
    else
        targetDamage = abradedBaselineDamage * speedMultiplier
    end
    local speedAdjustment = (targetDamage - abradedBaselineDamage) * wearScale
    local currentDamage = math.max(
        vanillaDamage
            + policyAdjustment + abrasionAdjustment + speedAdjustment,
        0)

    spec.xmlWearRateFactor = xmlWearRateFactor
    spec.xmlWearDurationMinutes = actualWearRate > 0
        and ((Wearable ~= nil and tonumber(Wearable.WEAR_FACTOR) or 1)
            / actualWearRate / 60000) or 0
    spec.referenceWearRate = referenceWearRate
    spec.wearPolicy = wearPolicy
    spec.vanillaAgeUsageFactor = vanillaAgeUsageFactor
    spec.adjustedAgeUsageFactor = adjustedAgeUsageFactor
    spec.baselineAbrasionMultiplier = baselineAbrasionMultiplier
    spec.abrasiveLoad = abrasiveLoad
    spec.lastPolicyAdjustmentDamage = policyAdjustment
    spec.lastAbrasionAdjustmentDamage = abrasionAdjustment
    spec.lastSpeedAdjustmentDamage = speedAdjustment
    spec.lastContinuousDamageMultiplier = vanillaDamage > 0
        and currentDamage / vanillaDamage or nil

    if spec.wearRateWarningLogged ~= true
        and (xmlWearRateFactor < TerraLogic.WEAR_CUSTOM_RATE_WARNING_MIN
            or xmlWearRateFactor > TerraLogic.WEAR_CUSTOM_RATE_WARNING_MAX) then
        spec.wearRateWarningLogged = true
        Logging.warning(
            "[FS25_TerraLogic] unusual wearable rate on '%s': XML/runtime x%.3f vs GIANTS 480min reference (duration %.2fmin, policy %s)",
            self.getName ~= nil and self:getName() or "implement",
            xmlWearRateFactor,
            spec.xmlWearDurationMinutes,
            wearPolicy
        )
    end

    spec.telemetryVanillaDamage = (spec.telemetryVanillaDamage or 0) + vanillaDamage
    spec.telemetryCurrentDamage = (spec.telemetryCurrentDamage or 0) + currentDamage
    spec.telemetryContinuousDamage = (spec.telemetryContinuousDamage or 0) + currentDamage
    local balanceTest = spec.balanceTest
    if balanceTest ~= nil and balanceTest.active == true then
        balanceTest.wearPolicy = wearPolicy
        balanceTest.xmlWearRateFactor = xmlWearRateFactor
        balanceTest.xmlWearDurationMinutes = spec.xmlWearDurationMinutes
        balanceTest.implementAbrasionFactor = implementFactor
        balanceTest.soilAbrasionFactor = soilFactor
        balanceTest.baselineAbrasionMultiplier = baselineAbrasionMultiplier
        balanceTest.vanillaDamage = (balanceTest.vanillaDamage or 0) + vanillaDamage
        balanceTest.continuousDamage = (balanceTest.continuousDamage or 0) + currentDamage
        balanceTest.speedAdjustmentDamage = (balanceTest.speedAdjustmentDamage or 0)
            + speedAdjustment
        balanceTest.abrasionAdjustmentDamage = (balanceTest.abrasionAdjustmentDamage or 0)
            + abrasionAdjustment
        balanceTest.wearPolicyAdjustmentDamage =
            (balanceTest.wearPolicyAdjustmentDamage or 0) + policyAdjustment
    end
    return currentDamage
end

-- Updates simulation state and telemetry once per vehicle tick.
function TerraLogic:onUpdateTick(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if dt <= 0 then
        return
    end

    local spec = self.spec_terraLogic
    if spec == nil or spec.ratedSpeed == nil then
        return
    end
    if self.isServer then
        local now = g_currentMission ~= nil and (g_currentMission.time or 0) or 0
        local actualWorkActive = spec.lastActualWorkTime ~= nil
            and now - spec.lastActualWorkTime <= 500
        local qualityWorkActive = spec.lastQualityWorkTime ~= nil
            and now - spec.lastQualityWorkTime <= 500
        local stateChanged = false
        if spec.actualWorkActive ~= actualWorkActive then
            spec.actualWorkActive = actualWorkActive
            stateChanged = true
        end
        if spec.qualityWorkActive ~= qualityWorkActive then
            spec.qualityWorkActive = qualityWorkActive
            stateChanged = true
        end
        if stateChanged then
            self:raiseDirtyFlags(spec.actualWorkDirtyFlag)
        end
    end
    if spec.workAreaFunctionsRefreshed ~= true
        and (self.spec_sowingMachine ~= nil or self.spec_sprayer ~= nil) then
        self:refreshOverSpeedWorkAreaProcessingFunctions()
    end
    self:updateOverSpeedImplementClass()
    self:updateOverSpeedPlowEffects()

    local modEnabled = TerraLogicMain == nil or TerraLogicMain.enabled ~= false
    local physicalDropoutsEnabled = getArePhysicalDropoutsEnabled()
    if not physicalDropoutsEnabled and spec.impactDropoutState ~= nil then
        spec.impactDropoutState = nil
        spec.impactDropoutStatus = "physical dropouts disabled"
        spec.impactDropoutFailedLanes = 0
        spec.impactDropoutTotalLanes = 0
        spec.impactDropoutFailedNormalized = nil
    end
    if spec.lastModEnabled ~= modEnabled then
        spec.lastModEnabled = modEnabled
        spec.telemetryElapsedMs = 0
        spec.telemetryDistanceM = 0
        spec.telemetryVanillaDamage = 0
        spec.telemetryCurrentDamage = 0
        spec.telemetryContinuousDamage = 0
        spec.telemetryActiveMs = 0
        spec.telemetrySpeedMultiplierTime = 0
        spec.telemetryTotalMultiplierTime = 0
        spec.telemetryDraftMultiplierTime = 0
        spec.vanillaDamagePerHectare = nil
        spec.currentDamagePerHectare = nil
        spec.continuousDamagePerHectare = nil
        spec.telemetryWorking = false
        spec.speedDamageMultiplier = 1
        spec.totalDamageMultiplier = 1
        spec.speedDraftMultiplier = 1
        spec.stoneDamageLastSecond = 0
        spec.stoneSurfaceDamageLastSecond = 0
        spec.stoneGeneratedDamageLastSecond = 0
        spec.randomImpactDamageLastSecond = 0
        spec.randomImpactDamageWindow = 0
    end

    self:updateOverSpeedSoilData(dt)
    if self.isServer then
        self:updateOverSpeedResistance()
    end

    -- Accumulate only a few scalars per frame and publish a stable snapshot
    -- once per second. This avoids per-frame table allocations and makes every
    -- live per-hectare value use the same measured distance/time window.
    local speedRatio, currentSpeed = self:getWorkingSpeedRatio()
    if not modEnabled then
        speedRatio = nil
    end
    spec.telemetryElapsedMs = (spec.telemetryElapsedMs or 0) + dt
    if speedRatio ~= nil then
        local distanceM = currentSpeed / 3.6 * (dt / 1000)
        local workingWidth = self:getOverSpeedWorkingWidth()
        local frameAreaHa = distanceM * workingWidth / 10000
        if physicalDropoutsEnabled and spec.impactDropoutProfile ~= nil then
            local activeState = spec.impactDropoutState
            local failedFraction = activeState ~= nil
                and (spec.impactDropoutFailedLanes or 0)
                    / math.max(spec.impactDropoutTotalLanes or 0, 1)
                or 0
            spec.impactDropoutMissedDistanceM =
                (spec.impactDropoutMissedDistanceM or 0)
                + distanceM * failedFraction
            spec.impactDropoutMissedAreaHa =
                (spec.impactDropoutMissedAreaHa or 0)
                + frameAreaHa * failedFraction
            local dropoutTest = spec.balanceTest
            if dropoutTest ~= nil and dropoutTest.active == true then
                dropoutTest.impactDropoutMissedAreaHa =
                    (dropoutTest.impactDropoutMissedAreaHa or 0)
                    + frameAreaHa * failedFraction
            end
            spec.impactDropoutState =
                TerraLogicDropoutManager:advanceImpactDropout(
                    spec.impactDropoutProfile,
                    activeState,
                    distanceM
                )

            local dropoutCfg = TerraLogicDropoutManager:getProfile(
                spec.impactDropoutProfile
            )
            -- Visual plough patches are intentionally retired. Keeping this
            -- nil also avoids running their former one-metre candidate lattice.
            local surfaceCfg = nil
            local ratedSpeed = math.max(tonumber(spec.ratedSpeed) or 0, 0)
            local ratedRatio = ratedSpeed > 0 and currentSpeed / ratedSpeed or 0
            local activationMargin = surfaceCfg ~= nil
                and math.max(tonumber(surfaceCfg.activationMarginKph) or 0, 0)
                or 0
            if self.spec_plow ~= nil and surfaceCfg ~= nil
                and currentSpeed > ratedSpeed + activationMargin then
                local excessProgress = math.clamp(ratedRatio - 1, 0, 1)
                local minimumChance = math.clamp(
                    tonumber(surfaceCfg.minimumPatchChance) or 0.05,
                    0,
                    1
                )
                local maximumChance = math.clamp(
                    tonumber(surfaceCfg.maximumPatchChance) or 0.80,
                    minimumChance,
                    1
                )
                local patchChance = minimumChance
                    + (maximumChance - minimumChance)
                        * excessProgress ^ math.max(
                            tonumber(surfaceCfg.patchChanceExponent) or 1.20,
                            0.1
                        )
                local candidateSpacingM = math.max(
                    tonumber(surfaceCfg.candidateSpacingM) or 1,
                    0.25
                )
                local expectedEventsPer100m = patchChance
                    * 100 / candidateSpacingM
                spec.impactDropoutThrowEventsPer100m =
                    expectedEventsPer100m
                spec.impactDropoutThrowEventsPerHa = workingWidth > 0
                    and expectedEventsPer100m * 100 / workingWidth or 0

                -- Distance lattice: exactly one deterministic candidate per
                -- configured travel interval, independent of FPS. Speed only
                -- changes the acceptance probability, never the candidate
                -- density or the maximum number of writes per metre.
                spec.plowThrowEventAccumulator =
                    (spec.plowThrowEventAccumulator or 0) + distanceM
                local crossedCandidates = math.floor(
                    spec.plowThrowEventAccumulator / candidateSpacingM
                )
                if crossedCandidates > 0 then
                    spec.plowThrowEventAccumulator =
                        spec.plowThrowEventAccumulator % candidateSpacingM
                    local maximumCandidatesPerFrame = math.max(
                        math.floor(
                            tonumber(surfaceCfg.maximumCandidatesPerFrame) or 16
                        ),
                        1
                    )
                    local evaluatedCandidates = math.min(
                        crossedCandidates,
                        maximumCandidatesPerFrame
                    )
                    local sequence = spec.plowSurfaceCandidateSequence or 0
                    local emittedEvents = 0
                    local candidateSalt = tonumber(surfaceCfg.candidateSalt) or 31847
                    for candidateOffset = 1, evaluatedCandidates do
                        local candidateSequence = sequence + candidateOffset
                        local pattern = TerraLogicDropoutManager:getPatternValue(
                            candidateSequence,
                            0,
                            0,
                            candidateSalt,
                            1
                        )
                        if pattern < patchChance then
                            emittedEvents = emittedEvents + 1
                        end
                    end
                    spec.plowSurfaceCandidateSequence =
                        sequence + crossedCandidates
                    if emittedEvents > 0 then
                        local maximumPending = math.max(
                            math.floor(
                                tonumber(surfaceCfg.maximumPendingEvents) or 4
                            ),
                            1
                        )
                        spec.plowIrregularPendingEvents = math.min(
                            (spec.plowIrregularPendingEvents or 0) + emittedEvents,
                            maximumPending
                        )
                    end
                end
            else
                spec.impactDropoutThrowEventsPer100m = 0
                spec.impactDropoutThrowEventsPerHa = 0
                spec.plowThrowEventAccumulator = 0
                spec.plowIrregularPendingEvents = 0
            end
            if spec.impactDropoutState == nil then
                spec.impactDropoutStatus = "inactive"
                spec.impactDropoutFailedLanes = 0
                spec.impactDropoutTotalLanes = 0
                spec.impactDropoutFailedNormalized = nil
            end
        end
        spec.telemetryDistanceM = (spec.telemetryDistanceM or 0) + distanceM
        local draftMultiplier, speedMultiplier = self:getOverSpeedBalanceFactors(speedRatio)
        local abrasion = getEffectiveAbrasionMultiplier(spec)
        local effectiveTotalMultiplier = tonumber(spec.lastContinuousDamageMultiplier)
            or abrasion
        spec.telemetryActiveMs = (spec.telemetryActiveMs or 0) + dt
        spec.telemetrySpeedMultiplierTime = (spec.telemetrySpeedMultiplierTime or 0)
            + speedMultiplier * dt
        spec.telemetryTotalMultiplierTime = (spec.telemetryTotalMultiplierTime or 0)
            + effectiveTotalMultiplier * dt
        spec.telemetryDraftMultiplierTime = (spec.telemetryDraftMultiplierTime or 0)
            + draftMultiplier * dt

        local balanceTest = spec.balanceTest
        if balanceTest ~= nil and balanceTest.active == true then
            balanceTest.activeMs = (balanceTest.activeMs or 0) + dt
            balanceTest.distanceM = (balanceTest.distanceM or 0) + distanceM
            balanceTest.areaHa = (balanceTest.areaHa or 0) + frameAreaHa
            balanceTest.speedTime = (balanceTest.speedTime or 0) + currentSpeed * dt
            balanceTest.speedMin = math.min(balanceTest.speedMin or currentSpeed, currentSpeed)
            balanceTest.speedMax = math.max(balanceTest.speedMax or currentSpeed, currentSpeed)
            balanceTest.draftTime = (balanceTest.draftTime or 0) + draftMultiplier * dt
            balanceTest.draftMax = math.max(balanceTest.draftMax or 1, draftMultiplier)
            balanceTest.abrasionTime = (balanceTest.abrasionTime or 0) + abrasion * dt
            balanceTest.resistanceTime = (balanceTest.resistanceTime or 0)
                + (spec.resistanceMultiplier or 1) * dt
            local ratedSpeed = tonumber(spec.ratedSpeed) or 0
            if ratedSpeed > 0 and currentSpeed > ratedSpeed then
                balanceTest.aboveRatedMs = (balanceTest.aboveRatedMs or 0) + dt
                balanceTest.aboveRatedAreaHa = (balanceTest.aboveRatedAreaHa or 0)
                    + frameAreaHa
            end
            local powerConsumer = self.spec_powerConsumer
            local currentMaxForce = powerConsumer ~= nil
                and tonumber(powerConsumer.maxForce) or 0
            balanceTest.maxForceTime = (balanceTest.maxForceTime or 0)
                + currentMaxForce * dt
            balanceTest.maxForceMax = math.max(balanceTest.maxForceMax or 0, currentMaxForce)
            local rootVehicle = self.rootVehicle or self
            local motorLoad = rootVehicle.getMotorLoadPercentage ~= nil
                and tonumber(rootVehicle:getMotorLoadPercentage()) or nil
            if motorLoad ~= nil then
                balanceTest.motorLoadTime = (balanceTest.motorLoadTime or 0)
                    + motorLoad * dt
                balanceTest.motorLoadMax = math.max(balanceTest.motorLoadMax or 0, motorLoad)
            end
            local soilIndex = tonumber(spec.soilTypeIndex) or 0
            balanceTest.soilTime = balanceTest.soilTime or {}
            balanceTest.soilTime[soilIndex] = (balanceTest.soilTime[soilIndex] or 0) + dt
        end

        local eventsPerHa, impactEnergy, excessImpactEnergy,
            scaledExcessImpactEnergy,
            smallImpactDamage, mediumImpactDamage, bigImpactDamage =
            self:getOverSpeedImpactRisk(currentSpeed)
        spec.impactRiskEventsPerHa = eventsPerHa
        spec.impactEnergy = impactEnergy
        spec.excessImpactEnergy = excessImpactEnergy
        spec.scaledExcessImpactEnergy = scaledExcessImpactEnergy
        spec.impactSmallMaximumDamage = smallImpactDamage
        spec.impactMediumMaximumDamage = mediumImpactDamage
        spec.impactBigMaximumDamage = bigImpactDamage
        spec.impactRiskEventsPerKm = eventsPerHa * workingWidth / 10
        spec.expectedRandomImpactDamagePerHectare = eventsPerHa
            * TerraLogic.IMPACT_RANDOM_MEAN_FACTOR
            * (TerraLogic.IMPACT_TIERS.small.probability
                    * smallImpactDamage
                + TerraLogic.IMPACT_TIERS.medium.probability
                    * mediumImpactDamage
                + TerraLogic.IMPACT_TIERS.big.probability
                    * bigImpactDamage)
        if self.isServer and self.addDamageAmount ~= nil and eventsPerHa > 0 then
            local impactProbability = 1 - math.exp(-eventsPerHa * frameAreaHa)
            if math.random() < impactProbability then
                local tierRoll = math.random()
                local impactTier = "small"
                local maximumImpactDamage = smallImpactDamage
                if tierRoll > TerraLogic.IMPACT_TIERS.small.probability then
                    impactTier = "medium"
                    maximumImpactDamage = mediumImpactDamage
                    if tierRoll > TerraLogic.IMPACT_TIERS.small.probability
                        + TerraLogic.IMPACT_TIERS.medium.probability then
                        impactTier = "big"
                        maximumImpactDamage = bigImpactDamage
                    end
                end
                local randomFactor = TerraLogic.IMPACT_RANDOM_MIN_FACTOR
                    + (1 - TerraLogic.IMPACT_RANDOM_MIN_FACTOR) * math.random()
                local impactDamage = maximumImpactDamage * randomFactor
                self:addDamageAmount(impactDamage)
                spec.telemetryCurrentDamage = (spec.telemetryCurrentDamage or 0) + impactDamage
                spec.randomImpactDamageWindow = (spec.randomImpactDamageWindow or 0) + impactDamage
                local balanceTest = spec.balanceTest
                if balanceTest ~= nil and balanceTest.active == true then
                    balanceTest.randomImpactDamage = (balanceTest.randomImpactDamage or 0)
                        + impactDamage
                    balanceTest.randomImpactCount = (balanceTest.randomImpactCount or 0) + 1
                    if impactTier == "small" then
                        balanceTest.smallImpactCount = (balanceTest.smallImpactCount or 0) + 1
                    elseif impactTier == "medium" then
                        balanceTest.mediumImpactCount = (balanceTest.mediumImpactCount or 0) + 1
                    else
                        balanceTest.bigImpactCount = (balanceTest.bigImpactCount or 0) + 1
                    end
                end
                spec.impactCount = (spec.impactCount or 0) + 1
                if impactTier == "small" then
                    spec.impactSmallCount = (spec.impactSmallCount or 0) + 1
                elseif impactTier == "medium" then
                    spec.impactMediumCount = (spec.impactMediumCount or 0) + 1
                else
                    spec.impactBigCount = (spec.impactBigCount or 0) + 1
                end
                if physicalDropoutsEnabled
                    and spec.impactDropoutProfile ~= nil then
                    local triggered
                    spec.impactDropoutState, triggered =
                        TerraLogicDropoutManager:triggerImpactDropout(
                            spec.impactDropoutProfile,
                            spec.impactDropoutState,
                            impactTier,
                            currentSpeed / math.max(spec.ratedSpeed or currentSpeed, 0.1)
                        )
                    if triggered then
                        spec.impactDropoutTriggerCount =
                            (spec.impactDropoutTriggerCount or 0) + 1
                        if impactTier == "medium" then
                            spec.impactDropoutMediumCount =
                                (spec.impactDropoutMediumCount or 0) + 1
                        elseif impactTier == "big" then
                            spec.impactDropoutBigCount =
                                (spec.impactDropoutBigCount or 0) + 1
                        end
                        local test = spec.balanceTest
                        if test ~= nil and test.active == true then
                            test.impactDropoutCount =
                                (test.impactDropoutCount or 0) + 1
                        end
                        -- Below shop speed the impact remains damage-only.
                        -- Above shop speed one medium/big hit schedules one
                        -- bounded 1x2 density-pixel cultivated patch after all
                        -- Vanilla plow WorkAreas have finished writing.
                        if self.spec_plow ~= nil
                            and currentSpeed > math.max(
                                tonumber(spec.ratedSpeed) or currentSpeed,
                                0
                            ) + 0.05 then
                            spec.pendingPlowStoneImpact = {
                                tier = impactTier,
                                gameTime = g_currentMission ~= nil
                                    and g_currentMission.time or 0
                            }
                        end
                    end
                end
                spec.lastImpactTier = impactTier
                spec.lastImpactDamage = impactDamage
                spec.lastImpactGameTime = g_currentMission ~= nil and g_currentMission.time or 0
                TerraLogicLogging.debug(
                    "[FS25_TerraLogic] Impact spike: vehicle=%s tier=%s depth=%.0fcm depthFactor=%.2f speed=%.1f rated=%.1f energy=%.2f excess=%.2f soilFreq=%.2f soilSeverity=%.2f damage=%.1f%% risk=%.2f events/ha",
                    self.getName ~= nil and self:getName() or tostring(self.configFileName),
                    impactTier,
                    spec.workDepthCm or 0,
                    spec.impactDepthFactor or 1,
                    currentSpeed,
                    spec.ratedSpeed,
                    impactEnergy,
                    excessImpactEnergy,
                    spec.impactFrequencyFactor or 1,
                    spec.impactSeverityFactor or 1,
                    impactDamage * 100,
                    eventsPerHa
                )
            end
        end
    else
        spec.impactRiskEventsPerHa = 0
        spec.impactEnergy = 0
        spec.excessImpactEnergy = 0
        spec.scaledExcessImpactEnergy = 0
        spec.impactSmallMaximumDamage = 0
        spec.impactMediumMaximumDamage = 0
        spec.impactBigMaximumDamage = 0
        spec.impactRiskEventsPerKm = 0
        spec.expectedRandomImpactDamagePerHectare = 0
        spec.plowThrowEventAccumulator = 0
        spec.plowIrregularPendingEvents = 0
    end

    if spec.telemetryElapsedMs >= TerraLogic.TELEMETRY_INTERVAL_MS then
        local width = self:getOverSpeedWorkingWidth()
        local areaHa = (spec.telemetryDistanceM or 0) * width / 10000
        local vanillaDamage = spec.telemetryVanillaDamage or 0
        local currentDamage = spec.telemetryCurrentDamage or 0
        local continuousDamage = spec.telemetryContinuousDamage or 0
        local activeMs = spec.telemetryActiveMs or 0

        spec.damageRatePerMs = currentDamage / spec.telemetryElapsedMs
        if areaHa > 0 then
            spec.vanillaDamagePerHectare = vanillaDamage / areaHa
            spec.currentDamagePerHectare = currentDamage / areaHa
            spec.continuousDamagePerHectare = continuousDamage / areaHa
            spec.randomImpactDamagePerHectareLastSecond =
                (spec.randomImpactDamageWindow or 0) / areaHa
            spec.stoneDamagePerHectareLastSecond =
                ((spec.stoneSurfaceDamageWindow or 0)
                    + (spec.stoneGeneratedDamageWindow or 0)) / areaHa
        else
            -- Per-area and derived distance values must describe the latest
            -- one-second window, not the last time the implement happened to
            -- move. Time-based wear/h remains available while stationary.
            spec.vanillaDamagePerHectare = nil
            spec.currentDamagePerHectare = nil
            spec.continuousDamagePerHectare = nil
            spec.randomImpactDamagePerHectareLastSecond = nil
            spec.stoneDamagePerHectareLastSecond = nil
        end
        spec.telemetryWorking = activeMs > 0
        if activeMs > 0 then
            spec.speedDamageMultiplier = spec.telemetrySpeedMultiplierTime / activeMs
            spec.totalDamageMultiplier = spec.telemetryTotalMultiplierTime / activeMs
            spec.speedDraftMultiplier = spec.telemetryDraftMultiplierTime / activeMs
        else
            -- Never leave the last working pass visible while transporting the
            -- raised implement. These are display snapshots; actual TerraLogic wear is
            -- already skipped by updateDamageAmount when speedRatio is nil.
            spec.speedDamageMultiplier = 1
            spec.totalDamageMultiplier = 1
            spec.speedDraftMultiplier = 1
        end

        spec.stoneDamageLastSecond = (spec.stoneSurfaceDamageWindow or 0)
            + (spec.stoneGeneratedDamageWindow or 0)
        spec.stoneSurfaceDamageLastSecond = spec.stoneSurfaceDamageWindow or 0
        spec.stoneGeneratedDamageLastSecond = spec.stoneGeneratedDamageWindow or 0
        spec.stoneGeneratedWeightedHaLastSecond = spec.stoneGeneratedWeightedHaWindow or 0
        spec.stoneExistingWeightedHaLastSecond = spec.stoneExistingWeightedHaWindow or 0
        spec.stoneScansLastSecond = spec.stoneScanCountWindow or 0
        spec.randomImpactDamageLastSecond = spec.randomImpactDamageWindow or 0

        spec.telemetryElapsedMs = 0
        spec.telemetryDistanceM = 0
        spec.telemetryVanillaDamage = 0
        spec.telemetryCurrentDamage = 0
        spec.telemetryContinuousDamage = 0
        spec.telemetryActiveMs = 0
        spec.telemetrySpeedMultiplierTime = 0
        spec.telemetryTotalMultiplierTime = 0
        spec.telemetryDraftMultiplierTime = 0
        spec.stoneScanCountWindow = 0
        spec.stoneSurfaceDamageWindow = 0
        spec.stoneGeneratedDamageWindow = 0
        spec.stoneGeneratedWeightedHaWindow = 0
        spec.stoneExistingWeightedHaWindow = 0
        spec.randomImpactDamageWindow = 0
    end
end

-- Builds a read-only snapshot consumed by all developer debug panels.
function TerraLogic:getOverSpeedDebugData()
    local spec = self.spec_terraLogic
    local speed = math.abs(self:getLastSpeed(true) or 0)
    local damage = self.getDamageAmount ~= nil and self:getDamageAmount() or 0
    local damageRatePerHour = (spec.damageRatePerMs or 0) * 3600000
    local width = self:getOverSpeedWorkingWidth()
    local damagePerHectare = spec.currentDamagePerHectare
    local ratedSpeed = tonumber(spec.ratedSpeed) or 0
    local safeSpeedRatio = math.clamp(
        tonumber(spec.safeSpeedRatio)
            or TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT,
        0.10,
        0.99
    )
    local referenceWidth = TerraLogicMain ~= nil
        and tonumber(TerraLogicMain.NORMALIZED_REFERENCE_WIDTH_M) or 3
    referenceWidth = math.max(referenceWidth or 3, 0.1)
    local function getDistanceAndNormalized(perHectare)
        if perHectare == nil or width == nil or width <= 0 then
            return nil, nil
        end
        local perTenKilometers = perHectare * width
        return perTenKilometers, perTenKilometers / referenceWidth
    end
    local currentDamagePer10Km, normalizedDamagePerHectare =
        getDistanceAndNormalized(damagePerHectare)
    local vanillaDamagePer10Km, normalizedVanillaDamagePerHectare =
        getDistanceAndNormalized(spec.vanillaDamagePerHectare)
    local continuousDamagePer10Km, normalizedContinuousDamagePerHectare =
        getDistanceAndNormalized(spec.continuousDamagePerHectare)
    local totalVsVanillaMultiplier = spec.vanillaDamagePerHectare ~= nil
        and spec.vanillaDamagePerHectare > 0 and damagePerHectare ~= nil
        and damagePerHectare / spec.vanillaDamagePerHectare or nil
    local continuousVsVanillaMultiplier = spec.vanillaDamagePerHectare ~= nil
        and spec.vanillaDamagePerHectare > 0
        and spec.continuousDamagePerHectare ~= nil
        and spec.continuousDamagePerHectare / spec.vanillaDamagePerHectare or nil
    local vanillaDamageRatePerHour = totalVsVanillaMultiplier ~= nil
        and totalVsVanillaMultiplier > 0
        and damageRatePerHour / totalVsVanillaMultiplier or nil
    local hectaresToFullDamage = damagePerHectare ~= nil and damagePerHectare > 0
        and math.max(1 - damage, 0) / damagePerHectare or nil
    local kilometersToFullDamage = currentDamagePer10Km ~= nil
        and currentDamagePer10Km > 0
        and math.max(1 - damage, 0) / currentDamagePer10Km * 10 or nil

    local price = self.getPrice ~= nil and self:getPrice() or 0
    local powerConsumer = self.spec_powerConsumer
    local modifiedMaxForce = powerConsumer ~= nil and tonumber(powerConsumer.maxForce) or 0
    local baseMaxForce = tonumber(spec.baseMaxForce) or modifiedMaxForce or 0
    local profileDraftActive = spec.additionalDraftEnabled == true
    local soilMaxForce = baseMaxForce
        * (profileDraftActive and (spec.resistanceMultiplier or 1) or 1)
    local projectedDamageResistance = profileDraftActive
        and self:getDamageResistanceMultiplier(damage) or 1
    local projectedMaxForce = soilMaxForce * projectedDamageResistance
        * (spec.speedDraftMultiplier or 1)
    local currentRepairCost = Wearable.calculateRepairPrice(price, damage)
    local fullRepairCost = Wearable.calculateRepairPrice(price, 1)
    local function getRepairCostForDamageIncrement(damageIncrement)
        local increment = math.max(tonumber(damageIncrement) or 0, 0)
        if increment <= 0 then
            return nil
        end
        local current = math.clamp(damage, 0, 1)
        local toFull = math.max(1 - current, 0)
        if increment <= toFull then
            return Wearable.calculateRepairPrice(price, current + increment)
                - currentRepairCost
        end
        -- If one projected hectare exceeds the remaining service life, model
        -- repair at 100% and continue from zero. Clamping at 100% understated
        -- extreme-overspeed costs exactly where the balancing view matters.
        local cost = fullRepairCost - currentRepairCost
        increment = increment - toFull
        local fullCycles = math.floor(increment)
        cost = cost + fullCycles * fullRepairCost
        local remainder = increment - fullCycles
        if remainder > 0 then
            cost = cost + Wearable.calculateRepairPrice(price, remainder)
        end
        return cost
    end
    local measuredRepairCostPerHectare =
        getRepairCostForDamageIncrement(damagePerHectare)
    local projectedDamagePerHectare = nil
    if spec.continuousDamagePerHectare ~= nil then
        projectedDamagePerHectare = spec.continuousDamagePerHectare
            + math.max(
                tonumber(spec.expectedRandomImpactDamagePerHectare) or 0,
                0
            )
            + math.max(
                tonumber(spec.stoneDamagePerHectareLastSecond) or 0,
                0
            )
    end
    local repairCostPerHectare =
        getRepairCostForDamageIncrement(projectedDamagePerHectare)
    local projectedHectaresToFullDamage = projectedDamagePerHectare ~= nil
        and projectedDamagePerHectare > 0
        and math.max(1 - damage, 0) / projectedDamagePerHectare or nil
    local repairCostPer10Km = repairCostPerHectare ~= nil
        and width ~= nil and width > 0 and repairCostPerHectare * width or nil
    local normalizedRepairCostPerHectare = repairCostPer10Km ~= nil
        and repairCostPer10Km / referenceWidth or nil
    local lastImpactSecondsAgo = nil
    if spec.lastImpactGameTime ~= nil and g_currentMission ~= nil then
        lastImpactSecondsAgo = math.max(g_currentMission.time - spec.lastImpactGameTime, 0) / 1000
    end
    local lastStoneEventSecondsAgo = nil
    if spec.lastStoneEventGameTime ~= nil and g_currentMission ~= nil then
        lastStoneEventSecondsAgo = math.max(
            g_currentMission.time - spec.lastStoneEventGameTime, 0
        ) / 1000
    end
    self:getOverSpeedStoneMapContext()
    local groundContactActive = self:getIsOverSpeedGroundContactActive()
    local effectiveAbrasion, abrasiveLoad =
        getEffectiveAbrasionMultiplier(spec)
    local wearableRate = self.spec_wearable ~= nil
        and math.max(tonumber(self.spec_wearable.wearDuration) or 0, 0) or 0
    local referenceWearRate = getReferenceWearRate()
    local xmlWearRateFactor = referenceWearRate > 0
        and wearableRate / referenceWearRate or 1
    local xmlWearDurationMinutes = wearableRate > 0
        and ((Wearable ~= nil and tonumber(Wearable.WEAR_FACTOR) or 1)
            / wearableRate / 60000) or 0
    local liveSeedQuality, liveSeedDamagePenalty, liveSeedSpeedPenalty,
        liveSeedHealth, liveSeedThresholdSpeed, liveSeedThresholdShift = spec.seedQuality or 1,
            spec.seedQualityDamagePenalty or 0,
            spec.seedQualitySpeedPenalty or 0,
            spec.seedQualityHealth or (1 - damage),
            spec.seedQualityThresholdSpeed or spec.ratedSpeed or 0,
            spec.seedQualityThresholdShift or 0
    local liveSeedWorkQuality = spec.seedWorkQuality or 1
    local liveSeedYieldPenalty = spec.seedYieldPenalty or 0
    if self.spec_sowingMachine ~= nil then
        local thresholdQuality
        thresholdQuality, liveSeedDamagePenalty, liveSeedSpeedPenalty,
            liveSeedHealth, liveSeedThresholdSpeed, liveSeedThresholdShift =
                self:getOverSpeedSeedQuality(speed)
        local liveSeedParams = self.spec_sowingMachine.workAreaParameters
        local liveSeedFruitType = liveSeedParams ~= nil
            and liveSeedParams.seedsFruitType or nil
        local liveSeedAllowsDropouts = not (FruitType ~= nil
            and FruitType.GRASS ~= nil
            and liveSeedFruitType == FruitType.GRASS)
        liveSeedWorkQuality, liveSeedYieldPenalty =
            TerraLogicQualityManager:getWorkQualityModel(
                self, speed, "seed", nil, liveSeedAllowsDropouts)
        local seedBalance = TerraLogic.getWorkQualityBalance(self, "seed")
        local physicalDropoutPenalty = getArePhysicalDropoutsEnabled()
            and TerraLogicQualityManager:calculateYieldPenalty(
                math.max(tonumber(thresholdQuality) or 1, 0),
                seedBalance.weight,
                seedBalance.maxPenalty
            ) or 0
        liveSeedQuality = 1 - physicalDropoutPenalty
    end
    local liveApplicationQuality, liveApplicationDamagePenalty,
        liveApplicationSpeedPenalty, liveApplicationHealth,
        liveApplicationThresholdSpeed, liveApplicationThresholdShift =
            spec.applicationQuality or 1,
            spec.applicationQualityDamagePenalty or 0,
            spec.applicationQualitySpeedPenalty or 0,
            spec.applicationQualityHealth or (1 - damage),
            spec.applicationQualityThresholdSpeed or spec.ratedSpeed or 0,
            spec.applicationQualityThresholdShift or 0
    if self.spec_sprayer ~= nil then
        local ignoredQuality
        ignoredQuality, liveApplicationDamagePenalty,
            liveApplicationSpeedPenalty, liveApplicationHealth,
            liveApplicationThresholdSpeed, liveApplicationThresholdShift =
                self:getOverSpeedApplicationQuality(speed)
        liveApplicationQuality = select(1,
            TerraLogicQualityManager:getWorkQualityModel(
                self, speed, spec.applicationQualityComponent or "fertilizer",
                nil))
    end

    return {
        name = self.getName ~= nil and self:getName() or "Implement",
        speed = speed,
        ratedSpeed = spec.ratedSpeed,
        optimalSpeed = spec.optimalSpeed or spec.ratedSpeed,
        safeSpeedRatio = safeSpeedRatio,
        safeSpeed = tonumber(spec.safeSpeed) or ratedSpeed * safeSpeedRatio,
        safeSpeedSource = spec.safeSpeedSource or "80% shop fallback",
        safeSpeedFallback = spec.safeSpeedFallback == true,
        shopToClassSpeedFactor = spec.shopToClassSpeedFactor,
        shopSpeedRatio = ratedSpeed > 0 and speed / ratedSpeed or 0,
        implementClassKey = spec.implementClassKey or "unknown",
        storeCategory = spec.storeCategory or "unknown",
        classificationSource = spec.classificationSource or "unknown",
        workDepthCm = spec.workDepthCm or 0,
        impactDepthFactor = spec.impactDepthFactor or 1,
        impactStoneProtection = spec.impactStoneProtection == true,
        impactMediumDamageFactor = spec.impactMediumDamageFactor or 1,
        implementAbrasionFactor = spec.implementAbrasionFactor or 0,
        wearModel = spec.wearModel or "soil",
        abrasiveShare = TerraLogic.WEAR_ABRASIVE_SHARE,
        abrasiveLoad = abrasiveLoad,
        baselineAbrasionMultiplier = effectiveAbrasion,
        effectiveAbrasionMultiplier = effectiveAbrasion,
        wearPolicy = getWearPolicy(),
        vanillaAgeUsageFactor = getVanillaAgeUsageFactor(self),
        adjustedAgeUsageFactor =
            TerraLogic.getAdjustedAgeUsageFactor(self),
        ageUsageFullHours =
            TerraLogic.getAdjustedAgeUsageFullHours(self),
        xmlWearRateFactor = xmlWearRateFactor,
        xmlWearDurationMinutes = xmlWearDurationMinutes,
        referenceWearDurationMinutes = TerraLogic.WEAR_REFERENCE_DURATION_MINUTES,
        customWearRateDetected = xmlWearRateFactor
                < TerraLogic.WEAR_CUSTOM_RATE_WARNING_MIN
            or xmlWearRateFactor > TerraLogic.WEAR_CUSTOM_RATE_WARNING_MAX,
        draftSpeedStrength = TerraLogic.DRAFT_SPEED_STRENGTH_FALLBACK,
        draftSpeedExponent = TerraLogic.DRAFT_SPEED_EXPONENT_FALLBACK,
        draftSpeedMaximum = TerraLogic.DRAFT_MAX_FALLBACK,
        additionalDraftEnabled = spec.additionalDraftEnabled == true,
        additionalDraftScale = spec.additionalDraftScale or 0,
        damagePercent = damage * 100,
        damageRatePercentPerHour = damageRatePerHour * 100,
        vanillaDamageRatePercentPerHour = vanillaDamageRatePerHour ~= nil
            and vanillaDamageRatePerHour * 100 or nil,
        workingWidth = width,
        isGroundTool = spec.isGroundTool == true,
        groundToolType = spec.groundToolType or "Unknown",
        groundContactActive = groundContactActive,
        workAreaProcessing = groundContactActive,
        workDetectionSource = spec.workDetectionSource or "inactive",
        speedLimitUnlockEligible = spec.speedLimitUnlockEligible == true,
        speedLimitUnlockSource = spec.speedLimitUnlockSource or "not queried",
        pfActive = spec.pfActive == true,
        pfMode = spec.pfMode or "auto",
        pfSource = spec.pfSource or "unknown",
        pfLastQueryOk = spec.pfLastQueryOk == true,
        pfLastSoilTypeIndex = tonumber(spec.pfLastSoilTypeIndex) or 0,
        pfLastPositionSource = spec.pfLastPositionSource or "not queried",
        pfSoilValueSource = spec.pfSoilValueSource or "not resolved",
        baseMaxForce = baseMaxForce,
        modifiedMaxForce = modifiedMaxForce or 0,
        soilMaxForce = soilMaxForce,
        projectedMaxForce = projectedMaxForce,
        soilTypeIndex = tonumber(spec.soilTypeIndex) or 0,
        soilName = spec.soilName,
        resistanceMultiplier = spec.effectiveResistanceMultiplier or spec.resistanceMultiplier or 1,
        abrasionMultiplier = spec.abrasionMultiplier or 1,
        abrasionSource = spec.abrasionSource or "Vanilla",
        resistanceSource = spec.resistanceSource or "Vanilla",
        soilResistanceMultiplier = spec.resistanceMultiplier or 1,
        damageResistanceMultiplier = projectedDamageResistance,
        damageResistanceFullAt = TerraLogic.DAMAGE_RESISTANCE_FULL_AT,
        damageResistanceExponent = TerraLogic.DAMAGE_RESISTANCE_EXPONENT,
        speedDamageMultiplier = groundContactActive
            and (spec.speedDamageMultiplier or 1) or 1,
        totalDamageMultiplier = groundContactActive
            and (spec.totalDamageMultiplier or 1) or 1,
        speedDraftMultiplier = groundContactActive
            and (spec.speedDraftMultiplier or 1) or 1,
        wearSpeedApplicationActive = groundContactActive,
        liveWearSpeedMultiplier = self:getOverSpeedWearMultiplier(speed),
        liveWearPerAreaVsShop = self:getOverSpeedWearMultiplier(speed)
            / math.max(ratedSpeed > 0 and speed / ratedSpeed or 1, 0.01),
        wearAtSafeSpeed = self:getOverSpeedWearMultiplier(
            tonumber(spec.safeSpeed) or ratedSpeed),
        wearAtShopSpeed = TerraLogic.WEAR_AT_SHOP_SPEED,
        wearClassShopFactorMin = TerraLogic.WEAR_CLASS_SHOP_FACTOR_MIN,
        wearClassShopFactorMax = TerraLogic.WEAR_CLASS_SHOP_FACTOR_MAX,
        wearBelowShopExponent = TerraLogic.WEAR_BELOW_SAFE_EXPONENT,
        wearAboveShopExponent = TerraLogic.WEAR_ABOVE_SHOP_EXPONENT,
        impactRiskEventsPerHa = spec.impactRiskEventsPerHa or 0,
        impactRiskEventsPerKm = spec.impactRiskEventsPerKm or 0,
        expectedRandomImpactDamagePerHectare =
            spec.expectedRandomImpactDamagePerHectare or 0,
        soilImpactEventsPerHa = TerraLogic.IMPACT_BASE_EVENTS_PER_HA
            * (spec.impactFrequencyFactor or 1),
        impactFrequencyFactor = spec.impactFrequencyFactor or 1,
        impactSeverityFactor = spec.impactSeverityFactor or 1,
        impactSoilSource = spec.impactSoilSource or "Neutral fallback",
        impactEnergy = spec.impactEnergy or 1,
        excessImpactEnergy = spec.excessImpactEnergy or 0,
        scaledExcessImpactEnergy = spec.scaledExcessImpactEnergy or 0,
        impactCount = spec.impactCount or 0,
        impactSmallCount = spec.impactSmallCount or 0,
        impactMediumCount = spec.impactMediumCount or 0,
        impactBigCount = spec.impactBigCount or 0,
        lastImpactTier = spec.lastImpactTier or "none",
        impactSmallProbability = TerraLogic.IMPACT_TIERS.small.probability,
        impactMediumProbability = TerraLogic.IMPACT_TIERS.medium.probability,
        impactBigProbability = TerraLogic.IMPACT_TIERS.big.probability,
        impactSmallEventsPerHa = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.small.probability,
        impactMediumEventsPerHa = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.medium.probability,
        impactBigEventsPerHa = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.big.probability,
        impactSmallMaximumDamagePercent = (spec.impactSmallMaximumDamage or 0) * 100,
        impactMediumMaximumDamagePercent = (spec.impactMediumMaximumDamage or 0) * 100,
        impactBigMaximumDamagePercent = (spec.impactBigMaximumDamage or 0) * 100,
        impactSmallExpectedDamagePerHaPercent = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.small.probability
            * (spec.impactSmallMaximumDamage or 0)
            * TerraLogic.IMPACT_RANDOM_MEAN_FACTOR * 100,
        impactMediumExpectedDamagePerHaPercent = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.medium.probability
            * (spec.impactMediumMaximumDamage or 0)
            * TerraLogic.IMPACT_RANDOM_MEAN_FACTOR * 100,
        impactBigExpectedDamagePerHaPercent = (spec.impactRiskEventsPerHa or 0)
            * TerraLogic.IMPACT_TIERS.big.probability
            * (spec.impactBigMaximumDamage or 0)
            * TerraLogic.IMPACT_RANDOM_MEAN_FACTOR * 100,
        impactDropoutProfile = spec.impactDropoutProfile or "none",
        impactDropoutStatus = spec.impactDropoutStatus or "inactive",
        impactDropoutFailedLanes = spec.impactDropoutFailedLanes or 0,
        impactDropoutTotalLanes = spec.impactDropoutTotalLanes or 0,
        impactVisualOnlyLanes = spec.impactVisualOnlyLanes or 0,
        impactVisualOnlyPixels = spec.impactVisualOnlyPixels or 0,
        impactDropoutRemainingDistanceM = spec.impactDropoutState ~= nil
            and (spec.impactDropoutState.remainingDistanceM or 0) or 0,
        impactDropoutHoldDistanceM = spec.impactDropoutState ~= nil
            and (spec.impactDropoutState.holdDistanceM or 0) or 0,
        impactDropoutLastTier = spec.impactDropoutState ~= nil
            and (spec.impactDropoutState.lastTier or "none") or "none",
        impactDropoutTriggerCount = spec.impactDropoutTriggerCount or 0,
        impactDropoutMediumCount = spec.impactDropoutMediumCount or 0,
        impactDropoutBigCount = spec.impactDropoutBigCount or 0,
        impactDropoutThrowCount = spec.impactDropoutThrowCount or 0,
        impactDropoutThrowEventsPerHa = spec.impactDropoutThrowEventsPerHa or 0,
        impactDropoutThrowEventsPer100m = spec.impactDropoutThrowEventsPer100m or 0,
        plowIrregularPendingEvents = spec.plowIrregularPendingEvents or 0,
        plowIrregularEventCount = spec.plowIrregularEventCount or 0,
        plowIrregularLastPassEvents = spec.plowIrregularLastPassEvents or 0,
        plowIrregularLastPixels = spec.plowIrregularLastPixels or 0,
        plowIrregularLastTwoPixelEvents =
            spec.plowIrregularLastTwoPixelEvents or 0,
        plowVisualTwistedFraction = spec.plowVisualTwistedFraction or 0,
        plowVisualMaximumDeviationSteps =
            spec.plowVisualMaximumDeviationSteps or 0,
        plowVisualScatteredPixels = spec.plowVisualScatteredPixels or 0,
        plowVisualScatteredCells = spec.plowVisualScatteredCells or 0,
        plowVisualDeferredPendingCells =
            spec.plowVisualDeferredPendingCells or 0,
        plowVisualCommitMode = spec.plowVisualCommitMode or "inactive",
        plowVisualDistributionMode =
            spec.plowVisualDistributionMode or "inactive",
        plowRasterGameplayFailureCells =
            spec.plowRasterGameplayFailureCells or 0,
        plowDensityTerrainSizeM = spec.plowDensityTerrainSizeM or 0,
        plowDensityDetailMapSize = spec.plowDensityDetailMapSize or 0,
        plowDensityPixelSizeM = spec.plowDensityPixelSizeM or 0.5,
        plowDensityLinearScale = spec.plowDensityLinearScale or 1,
        plowDropoutResolutionFactor = spec.plowDropoutResolutionFactor or 1,
        plowDensityResolutionSource =
            spec.plowDensityResolutionSource or "unknown",
        plowQualityProtectionMode =
            spec.plowQualityProtectionMode or "inactive",
        plowQualityProtectionHoldM =
            spec.plowQualityProtectionHoldM or 0,
        plowWorldStableFailureFraction =
            spec.plowWorldStableFailureFraction or 0,
        plowMixedCultivatedPixels = spec.plowMixedCultivatedPixels or 0,
        plowMixedTwistedPixels = spec.plowMixedTwistedPixels or 0,
        plowVisualEffectStatus = spec.plowVisualEffectStatus or "inactive",
        plowDropoutHookActive = spec.plowDropoutHookActive == true,
        workAreaFunctionsRebound = spec.workAreaFunctionsRebound or 0,
        impactDropoutMissedAreaHa = spec.impactDropoutMissedAreaHa or 0,
        impactDropoutMissedDistanceM = spec.impactDropoutMissedDistanceM or 0,
        lastImpactDamagePercent = spec.lastImpactDamage ~= nil and spec.lastImpactDamage * 100 or nil,
        lastImpactSecondsAgo = lastImpactSecondsAgo,
        stoneSystemActive = spec.stoneSystemActive == true,
        stoneSystemStatus = spec.stoneSystemStatus or "unknown",
        stoneToolMode = spec.stoneToolMode or "unknown",
        stoneSurfaceFactor = spec.stoneSurfaceFactor or 0,
        stoneGenerationFactor = spec.stoneGenerationFactor or 0,
        hiddenImpactFactor = spec.hiddenImpactFactor or 1,
        stoneExistingLevel = spec.stoneExistingLevel or 0,
        stoneExistingCoveragePercent = (spec.stoneExistingCoverage or 0) * 100,
        stoneGeneratedLevelDelta = spec.stoneGeneratedLevelDelta or 0,
        stoneGeneratedWeightedHaLastScan = spec.stoneGeneratedWeightedHaLastScan or 0,
        stoneExistingWeightedHaLastSecond = spec.stoneExistingWeightedHaLastSecond or 0,
        stoneGeneratedWeightedHaLastSecond = spec.stoneGeneratedWeightedHaLastSecond or 0,
        stoneDamageLastSecondPercent = (spec.stoneDamageLastSecond or 0) * 100,
        stoneSurfaceDamageLastSecondPercent = (spec.stoneSurfaceDamageLastSecond or 0) * 100,
        stoneGeneratedDamageLastSecondPercent = (spec.stoneGeneratedDamageLastSecond or 0) * 100,
        stoneScansLastSecond = spec.stoneScansLastSecond or 0,
        lastStoneEventSource = spec.lastStoneEventSource or "none",
        lastStoneEventDamagePercent = spec.lastStoneEventDamage ~= nil
            and spec.lastStoneEventDamage * 100 or nil,
        lastStoneEventSecondsAgo = lastStoneEventSecondsAgo,
        draftEnabled = spec.additionalDraftEnabled == true
            and (TerraLogicMain == nil or TerraLogicMain.draftEnabled ~= false),
        globalDraftEnabled = TerraLogicMain == nil
            or TerraLogicMain.draftEnabled ~= false,
        randomImpactsEnabled = TerraLogicMain == nil or TerraLogicMain.randomImpactsEnabled ~= false,
        stoneImpactsEnabled = TerraLogicMain == nil or TerraLogicMain.stoneImpactsEnabled ~= false,
        wearRuntimeMultiplier = getRuntimeBalanceMultiplier("wear"),
        draftRuntimeMultiplier = getRuntimeBalanceMultiplier("draft"),
        damageResistanceRuntimeMultiplier = getRuntimeBalanceMultiplier("damageResistance"),
        randomFrequencyRuntimeMultiplier = getRuntimeBalanceMultiplier("randomFrequency"),
        randomDamageRuntimeMultiplier = getRuntimeBalanceMultiplier("randomDamage"),
        stoneSurfaceRuntimeMultiplier = getRuntimeBalanceMultiplier("stoneSurface"),
        stoneGeneratedRuntimeMultiplier = getRuntimeBalanceMultiplier("stoneGenerated"),
        stoneHiddenRuntimeMultiplier = getRuntimeBalanceMultiplier("stoneHidden"),
        seedQuality = liveSeedQuality,
        seedWorkQuality = liveSeedWorkQuality,
        seedYieldPenalty = liveSeedYieldPenalty,
        seedQualityHealth = liveSeedHealth,
        seedQualityDamagePenalty = liveSeedDamagePenalty,
        seedQualitySpeedPenalty = liveSeedSpeedPenalty,
        seedQualityThresholdSpeed = liveSeedThresholdSpeed,
        seedQualityThresholdShift = liveSeedThresholdShift,
        seedQualityStatus = spec.seedQualityStatus or "inactive",
        seedQualityFruit = spec.seedQualityFruit or "none",
        seedQualityFailedPixels = spec.seedQualityFailedPixels or 0,
        seedQualityProtectedLanes = spec.seedQualityProtectedLanes or 0,
        seedQualityPatternLanes = spec.seedQualityPatternLanes or 0,
        seedQualityPatternMode = spec.seedQualityPatternMode or "inactive",
        seedQualityLaneCap = spec.seedQualityLaneCap or 0,
        seedQualityFullWidthChance = spec.seedQualityFullWidthChance or 0,
        seedQualitySpeedRatio = spec.seedQualitySpeedRatio or 0,
        seedQualityHookActive = spec.seedQualityHookActive == true,
        seedQualityDensityHookActive = spec.seedQualityDensityHookActive == true,
        seedQualityDensityCalls = spec.seedQualityDensityCalls or 0,
        seedQualityPostClearPixels = spec.seedQualityPostClearPixels or 0,
        seedQualityWorkAreaDepthM = spec.seedQualityWorkAreaDepthM or 0,
        seedQualityEffectiveLaneWidthM = spec.seedQualityEffectiveLaneWidthM or 0,
        seedQualityHoldDistanceM = spec.seedQualityHoldDistanceM or 0,
        seedQualityHoldRemainingM = spec.seedQualityHoldRemainingM or 0,
        seedQualityMissedFraction = spec.seedQualityMissedFraction or 0,
        seedQualityLatchReused = spec.seedQualityLatchReused == true,
        applicationQuality = liveApplicationQuality,
        applicationQualityHealth = liveApplicationHealth,
        applicationQualityDamagePenalty = liveApplicationDamagePenalty,
        applicationQualitySpeedPenalty = liveApplicationSpeedPenalty,
        applicationQualityThresholdSpeed = liveApplicationThresholdSpeed,
        applicationQualityThresholdShift = liveApplicationThresholdShift,
        applicationQualityStatus = spec.applicationQualityStatus or "inactive",
        applicationQualityFillType = spec.applicationQualityFillType or "unknown",
        applicationQualityProfile = spec.applicationQualityProfile or "none",
        applicationQualityPatternMode = spec.applicationQualityPatternMode or "inactive",
        applicationQualitySkippedLanes = spec.applicationQualitySkippedLanes or 0,
        applicationQualityProcessedLanes = spec.applicationQualityProcessedLanes or 0,
        yieldWeight = spec.yieldWeight or 0,
        maxYieldPenalty = spec.maxYieldPenalty or 0,
        rollerQualityFailure = spec.rollerQualityFailure or 0,
        rollerQualityStatus = spec.rollerQualityStatus or "inactive",
        rollerQualityFailedPixels = spec.rollerQualityFailedPixels or 0,
        isSowingMachine = self.spec_sowingMachine ~= nil,
        isApplicationTool = self.spec_sprayer ~= nil,
        workAreaFunctionsRebound = spec.workAreaFunctionsRebound or 0,
        isSoilRoller = self.spec_roller ~= nil
            and self.spec_roller.isSoilRoller == true,
        telemetryWorking = spec.telemetryWorking == true,
        modEnabled = TerraLogicMain == nil or TerraLogicMain.enabled ~= false,
        vanillaDamagePerHectare = spec.vanillaDamagePerHectare,
        currentDamagePerHectare = spec.currentDamagePerHectare,
        projectedDamagePerHectare = projectedDamagePerHectare,
        measuredRepairCostPerHectare = measuredRepairCostPerHectare,
        randomImpactDamagePerHectareLastSecond =
            spec.randomImpactDamagePerHectareLastSecond,
        stoneDamagePerHectareLastSecond =
            spec.stoneDamagePerHectareLastSecond,
        continuousDamagePerHectare = spec.continuousDamagePerHectare,
        normalizedReferenceWidth = referenceWidth,
        currentDamagePer10Km = currentDamagePer10Km,
        vanillaDamagePer10Km = vanillaDamagePer10Km,
        continuousDamagePer10Km = continuousDamagePer10Km,
        normalizedDamagePerHectare = normalizedDamagePerHectare,
        normalizedVanillaDamagePerHectare = normalizedVanillaDamagePerHectare,
        normalizedContinuousDamagePerHectare = normalizedContinuousDamagePerHectare,
        totalVsVanillaMultiplier = totalVsVanillaMultiplier,
        continuousVsVanillaMultiplier = continuousVsVanillaMultiplier,
        randomImpactDamageLastSecondPercent = (spec.randomImpactDamageLastSecond or 0) * 100,
        hectaresToFullDamage = hectaresToFullDamage,
        projectedHectaresToFullDamage = projectedHectaresToFullDamage,
        kilometersToFullDamage = kilometersToFullDamage,
        repairCostPerHectare = repairCostPerHectare,
        repairCostPer10Km = repairCostPer10Km,
        normalizedRepairCostPerHectare = normalizedRepairCostPerHectare,
        currentRepairCost = currentRepairCost,
        fullRepairCost = fullRepairCost
    }
end
