--[[
    TerraLogicMain.lua
    Mission lifecycle, console tools, HUD rendering and debug interfaces.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-MAIN-1.200211
]]

TerraLogicMain = {}
OverSpeedDamageMain = TerraLogicMain
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicMain.SOURCE_FINGERPRINT = 1.200211

local MOD_NAME = g_currentModName
local MOD_DIR = g_currentModDirectory
local SPEC_NAME = "terraLogic"

TerraLogicMain.debugEnabled = false
TerraLogicMain.debugMode = "overview"
TerraLogicMain.NORMALIZED_REFERENCE_WIDTH_M = 3.00
TerraLogicMain.DEBUG_VIEWS = {
    overview = true,
    wear = true,
    economy = true,
    draft = true,
    impacts = true,
    quality = true,
    balancing = true,
    workquality = true,
    technical = true
}
TerraLogicMain.DEBUG_VIEW_HELP = {
    {name = "overview", description = "compact overall status"},
    {name = "wear", description = "wear curve, damage rates and normalization"},
    {name = "economy", description = "repair costs and remaining service life"},
    {name = "draft", description = "draft, MaxForce and Precision Farming soil"},
    {name = "impacts", description = "random impacts and real stone contacts"},
    {name = "quality", description = "sowing/application quality and dropouts"},
    {name = "balancing", description = "live time saving, quality and yield trade-off"},
    {name = "workquality", description = "stored work quality and real yield deductions"},
    {name = "technical", description = "recognition and internal diagnostics"}
}
TerraLogicMain.enabled = true
TerraLogicMain.abrasionOverride = 0
TerraLogicMain.resistanceOverride = 0
TerraLogicMain.precisionFarmingMode = "auto"
TerraLogicMain.wearPolicy = "normalize"
TerraLogicMain.draftEnabled = true
TerraLogicMain.randomImpactsEnabled = true
TerraLogicMain.stoneImpactsEnabled = true
TerraLogicMain.BALANCE_DEFAULTS = {
    wear = 1,
    draft = 1,
    damageResistance = 1,
    randomFrequency = 1,
    randomDamage = 1,
    stoneSurface = 1,
    stoneGenerated = 1,
    stoneHidden = 1
}
TerraLogicMain.BALANCE_NAMES = {
    wear = "wear",
    draft = "draft",
    damageresistance = "damageResistance",
    randomfrequency = "randomFrequency",
    randomdamage = "randomDamage",
    stonesurface = "stoneSurface",
    stonegenerated = "stoneGenerated",
    stonehidden = "stoneHidden"
}
TerraLogicMain.balanceMultipliers = {}
for name, value in pairs(TerraLogicMain.BALANCE_DEFAULTS) do
    TerraLogicMain.balanceMultipliers[name] = value
end

-- Safely calls an optional method while supporting different PF API versions.
local function resolveObjectMethod(object, methodName, ...)
    if object == nil then
        return nil, "object missing"
    end

    local directMethod = object[methodName]
    if type(directMethod) == "function" then
        return directMethod, "instance"
    end

    local mt = getmetatable(object)
    if mt ~= nil and type(mt.__index) == "table" then
        local metaMethod = mt.__index[methodName]
        if type(metaMethod) == "function" then
            return metaMethod, "metatable"
        end
    end

    for i = 1, select("#", ...) do
        local classObject = select(i, ...)
        if type(classObject) == "table" and type(classObject[methodName]) == "function" then
            return classObject[methodName], "class"
        end
    end

    return nil, "method missing"
end

-- Finds the active Precision Farming soil map without requiring PF to be loaded.
function TerraLogicMain:getPrecisionFarmingSoilMap()
    local pfEnvironment = FS25_precisionFarming
    local pfController = pfEnvironment ~= nil and pfEnvironment.g_precisionFarming or nil
    local candidates = {
        {object = pfController ~= nil and pfController.soilMap or nil, source = "FS25_precisionFarming.g_precisionFarming.soilMap"},
        {object = g_precisionFarming ~= nil and g_precisionFarming.soilMap or nil, source = "g_precisionFarming.soilMap"},
        {object = g_currentMission ~= nil and g_currentMission.precisionFarming ~= nil and g_currentMission.precisionFarming.soilMap or nil, source = "mission.precisionFarming.soilMap"},
        {object = g_currentMission ~= nil and g_currentMission.precisionFarmingSoilMap or nil, source = "mission.precisionFarmingSoilMap"},
        {object = g_currentMission ~= nil and g_currentMission.soilMap or nil, source = "mission.soilMap"}
    }

    local methodNames = {
        "getTypeIndexAtWorldPos",
        "getSoilTypeIndexAtWorldPos",
        "getSoilTypeAtWorldPos",
        "getTypeIndexAtWorldPosition"
    }

    for _, candidate in ipairs(candidates) do
        if candidate.object ~= nil then
            for _, methodName in ipairs(methodNames) do
                local method, methodSource = resolveObjectMethod(
                    candidate.object,
                    methodName,
                    pfEnvironment ~= nil and pfEnvironment.SoilMap or nil,
                    pfEnvironment ~= nil and pfEnvironment.PrecisionFarmingSoilMap or nil,
                    SoilMap,
                    PrecisionFarmingSoilMap
                )
                if method ~= nil then
                    return candidate.object, method,
                        candidate.source .. "/" .. methodSource .. "." .. methodName
                end
            end
        end
    end

    if pfEnvironment ~= nil then
        if pfController == nil then
            return nil, nil, "FS25_precisionFarming environment present, controller missing"
        end
        if pfController.soilMap == nil then
            return nil, nil, "PF controller present, soilMap missing"
        end
        return nil, nil, "PF cross-mod soilMap present, compatible method missing"
    end

    return nil, nil, g_precisionFarming ~= nil
        and "local PF global present, compatible soil map method missing"
        or "PF mod environment missing"
end

-- Installed is not the same as active in the current savegame. Requiring the
-- live controller/map prevents PF wording and PF balance from leaking into a
-- save that merely has the downloadable mod present on disk.
-- Returns true only when Precision Farming is active in this savegame.
function TerraLogicMain:isPrecisionFarmingActive()
    local loaded = g_modIsLoaded == nil
        or g_modIsLoaded["FS25_precisionFarming"] == true
    if not loaded then return false end
    local environment = FS25_precisionFarming
    local controller = environment ~= nil
        and environment.g_precisionFarming or g_precisionFarming
    if controller == nil and g_currentMission ~= nil then
        controller = g_currentMission.precisionFarming
    end
    if controller == nil then return false end
    return controller.soilMap ~= nil
        or controller.nitrogenMap ~= nil
        or controller.pHMap ~= nil
        or (g_currentMission ~= nil
            and g_currentMission.precisionFarmingSoilMap ~= nil)
end

-- Initializes persistent quality data, settings and console commands per mission.
function TerraLogicMain:loadMap(mapNode, mapFile)
    TerraLogicSettings:load()
    TerraLogicQualityManager:load()
    local commands = {
        {"tlDebug", "TerraLogic debug toggle/view: tlDebug [view|on|off]", "consoleCommandDebug"},
        {"tlView", "Open TerraLogic debug view: tlView <overview|wear|economy|draft|impacts|quality|balancing|workquality|technical>", "consoleCommandDebugView"},
        {"tlViews", "List TerraLogic debug views", "consoleCommandDebugViews"},
        {"tlDebugClose", "Close the active TerraLogic debug view", "consoleCommandDebugClose"},
        {"tlSetDamage", "Set selected implement damage: tlSetDamage <0-100>", "consoleCommandSetDamage"},
        {"tlPF", "Precision Farming mode: tlPF [auto|on|off]", "consoleCommandPrecisionFarming"},
        {"tlPFInspect", "Inspect Precision Farming runtime objects", "consoleCommandPrecisionFarmingInspect"},
        {"tlEnable", "Enable/disable TerraLogic: tlEnable [on|off]", "consoleCommandEnable"},
        {"tlWearPolicy", "XML wear policy: tlWearPolicy [respect|normalize|forceVanilla]", "consoleCommandWearPolicy"},
        {"tlAbrasion", "Temporary abrasion override: tlAbrasion <multiplier|0>", "consoleCommandAbrasion"},
        {"tlResistance", "Temporary resistance override: tlResistance <multiplier|0>", "consoleCommandResistance"},
        {"tlDraft", "Enable/disable additional draft: tlDraft [on|off]", "consoleCommandDraft"},
        {"tlImpacts", "Enable/disable random impacts: tlImpacts [on|off]", "consoleCommandRandomImpacts"},
        {"tlStones", "Enable/disable stone-map damage: tlStones [on|off]", "consoleCommandStoneImpacts"},
        {"tlMultiplier", "Runtime balance multiplier: tlMultiplier <name> <value|reset>", "consoleCommandMultiplier"},
        {"tlBalanceReset", "Reset temporary TerraLogic balance settings", "consoleCommandBalanceReset"},
        {"tlPrintBalance", "Print TerraLogic balance settings to log", "consoleCommandPrintBalance"},
        {"tlLog", "Verbose diagnostics: tlLog [on|off]", "consoleCommandLogging"},
        {"tlDraftModel", "Synchronized draft model: tlDraftModel [terralogic|mr]", "consoleCommandDraftModel"},
        {"tlTestStart", "Start balance run: tlTestStart <label> [revenuePerHa]", "consoleCommandTestStart"},
        {"tlTestStop", "Stop balance run and print report", "consoleCommandTestStop"},
        {"tlTestStatus", "Show active balance-run status", "consoleCommandTestStatus"},
        {"tlTestCancel", "Cancel active balance run", "consoleCommandTestCancel"}
    }
    for _, command in ipairs(commands) do
        addConsoleCommand(command[1], command[2], command[3], self)
    end
end

-- Saves both the quality ledger and the server-controlled settings.
function TerraLogicMain.saveWorkQualityData()
    TerraLogicQualityManager:save()
    TerraLogicSettings:save()
end

-- Performs small deferred maintenance tasks without creating frame-time spikes.
function TerraLogicMain:update(dt)
    -- Old saves are cleaned incrementally to avoid a load-time density-map
    -- spike on large maps. The smaller budget changes only cleanup duration,
    -- never the stored quality result.
    TerraLogicQualityManager:processStoredCellPrune(16, 512)
    TerraLogicQualityManager:flushPendingMowerClears()
    TerraLogicSettings:tryInstallMenu()
end

-- Flushes data and releases HUD resources when leaving a mission.
function TerraLogicMain:deleteMap()
    TerraLogicQualityManager:save()
    self:deleteSpeedHudOverlays()
    self:clearQualityFieldInfoRows()
    if self.qualityInfoBox ~= nil and g_currentMission ~= nil
        and g_currentMission.hud ~= nil
        and g_currentMission.hud.infoDisplay ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(self.qualityInfoBox)
    end
    self.qualityInfoBox = nil
    if self.balanceTestImplement ~= nil then
        local spec = self.balanceTestImplement.spec_terraLogic
        if spec ~= nil and spec.balanceTest ~= nil then
            spec.balanceTest.active = false
        end
        self.balanceTestImplement = nil
    end
    for _, name in ipairs({
            "tlDebug", "tlView", "tlViews", "tlDebugClose", "tlSetDamage",
            "tlPF", "tlPFInspect", "tlEnable", "tlWearPolicy", "tlAbrasion",
            "tlResistance", "tlDraft", "tlImpacts", "tlStones", "tlMultiplier",
            "tlBalanceReset", "tlPrintBalance", "tlLog", "tlDraftModel",
            "tlTestStart", "tlTestStop", "tlTestStatus", "tlTestCancel"
        }) do
        removeConsoleCommand(name)
    end
end

-- Console command helpers ----------------------------------------------------

-- Converts common textual on/off values into a boolean.
local function parseEnabled(value)
    value = value ~= nil and string.lower(tostring(value)) or ""
    if value == "on" or value == "true" or value == "1" then
        return true
    end
    if value == "off" or value == "false" or value == "0" then
        return false
    end
    return nil
end

function TerraLogicMain:consoleCommandLogging(value)
    local parsed = parseEnabled(value)
    if parsed ~= nil then
        TerraLogicLogging.verbose = parsed
        if parsed and TerraLogicQualityManager ~= nil
            and TerraLogicQualityManager.resetHarvestDiagnostics ~= nil then
            TerraLogicQualityManager:resetHarvestDiagnostics()
        end
    end
    return string.format("TerraLogic verbose logging: %s",
        TerraLogicLogging.verbose and "ON" or "OFF")
end

function TerraLogicMain:consoleCommandDraftModel(value)
    value = string.lower(tostring(value or ""))
    if value == "terralogic" or value == "tl" then
        value = "terraLogic"
    end
    if value == "terraLogic" or value == "mr" then
        if not TerraLogicSettings:isLocalAdmin() then
            return "TerraLogic: only the server administrator may change the draft model"
        end
        TerraLogicSettings:setFromMenu(value)
    end
    local effective = TerraLogicSettings:getEffectiveDraftModel()
    local suffix = TerraLogicSettings.draftModel == "mr"
        and effective ~= "mr" and " (More Realistic unavailable; TerraLogic fallback)" or ""
    local displayName = effective == "mr" and "More Realistic" or "TerraLogic"
    return string.format("TerraLogic draft model: %s%s", displayName, suffix)
end

-- Balance-test helpers -------------------------------------------------------

-- Returns a readable vehicle or implement name for diagnostics.
local function getObjectName(object, fallback)
    if object ~= nil then
        if object.getFullName ~= nil then
            return tostring(object:getFullName())
        end
        if object.getName ~= nil then
            return tostring(object:getName())
        end
    end
    return fallback or "unknown"
end

local function getStoreSpecNumber(object, ...)
    if object == nil or g_storeManager == nil or object.configFileName == nil then
        return nil
    end
    local item = g_storeManager:getItemByXMLFilename(object.configFileName)
    local specs = item ~= nil and item.specs or nil
    if specs == nil then
        return nil
    end
    for index = 1, select("#", ...) do
        local value = tonumber(specs[select(index, ...)])
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function getVehicleXmlNumber(object, key)
    if object == nil or object.xmlFile == nil
        or type(object.xmlFile.getValue) ~= "function" then
        return nil
    end
    local ok, value = pcall(object.xmlFile.getValue, object.xmlFile, key)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function getActiveMotorShopHp(object, runtimeHp)
    local motorConfigIndex = 1
    if object ~= nil and object.configurations ~= nil
        and object.configurations.motor ~= nil then
        motorConfigIndex = math.max(tonumber(object.configurations.motor) or 1, 1)
    end
    local key = string.format(
        "vehicle.motorized.motorConfigurations.motorConfiguration(%d)#hp",
        motorConfigIndex - 1
    )
    local configuredHp = getVehicleXmlNumber(object, key)
    if configuredHp ~= nil then
        return configuredHp
    end
    if runtimeHp ~= nil and runtimeHp > 0 then
        return math.floor(runtimeHp + 0.5)
    end
    return getStoreSpecNumber(object, "power", "maxPower")
end

local function getImplementNeededHp(object)
    return getVehicleXmlNumber(object, "vehicle.storeData.specs.neededPower")
        or getStoreSpecNumber(object, "neededPower", "powerNeeded")
end

local function getVanillaAgeUsageData(object)
    local age = tonumber(object ~= nil and object.age) or 0
    local lifetime = tonumber(object ~= nil and object.lifetime) or 0
    local operatingHours = (tonumber(object ~= nil and object.operatingTime) or 0)
        / 3600000
    local factor = 1
    if lifetime ~= 0 then
        local ageMultiplier = 0.15 * math.min(age / lifetime, 1)
        local lifetimeOperatingRatio = EconomyManager ~= nil
            and tonumber(EconomyManager.LIFETIME_OPERATINGTIME_RATIO) or 0.08333
        local operatingTimeMultiplier = 0.85 * math.min(
            operatingHours / math.max(lifetime * lifetimeOperatingRatio, 0.0001),
            1
        )
        local maximumMultiplier = EconomyManager ~= nil
            and tonumber(EconomyManager.MAX_DAILYUPKEEP_MULTIPLIER) or 4
        factor = 1 + maximumMultiplier
            * (ageMultiplier + operatingTimeMultiplier)
    end
    local adjustedFactor = TerraLogic ~= nil
        and TerraLogic.getAdjustedAgeUsageFactor ~= nil
        and TerraLogic.getAdjustedAgeUsageFactor(object) or factor
    return age, lifetime, operatingHours, factor, adjustedFactor
end

local function getEconomyData()
    local difficulty = g_currentMission ~= nil and g_currentMission.missionInfo ~= nil
        and tonumber(g_currentMission.missionInfo.economicDifficulty) or nil
    local names = {[1] = "easy", [2] = "normal", [3] = "hard"}
    local costMultiplier = nil
    local priceMultiplier = nil
    if EconomyManager ~= nil and type(EconomyManager.getCostMultiplier) == "function" then
        local ok, value = pcall(EconomyManager.getCostMultiplier)
        costMultiplier = ok and tonumber(value) or nil
    end
    if EconomyManager ~= nil and type(EconomyManager.getPriceMultiplier) == "function" then
        local ok, value = pcall(EconomyManager.getPriceMultiplier)
        priceMultiplier = ok and tonumber(value) or nil
    end
    return difficulty, names[difficulty] or "unknown", costMultiplier, priceMultiplier
end

local function percentOrZero(value)
    return (tonumber(value) or 0) * 100
end

function TerraLogicMain:consoleCommandTestStart(label, revenuePerHa)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return "TerraLogic: balance tests must be started on the server/host"
    end
    if self.balanceTestImplement ~= nil then
        local oldSpec = self.balanceTestImplement.spec_terraLogic
        if oldSpec ~= nil and oldSpec.balanceTest ~= nil
            and oldSpec.balanceTest.active == true then
            return "TerraLogic: a balance test is already active; use tlTestStop or tlTestCancel"
        end
    end

    local implement = self:getDebugImplement(true)
    if implement == nil or implement.spec_terraLogic == nil then
        return "TerraLogic: no supported implement selected or attached"
    end

    local revenue = nil
    if revenuePerHa ~= nil and revenuePerHa ~= "" then
        revenue = tonumber(revenuePerHa)
    end
    if (revenuePerHa ~= nil and revenuePerHa ~= "" and revenue == nil)
        or (revenue ~= nil and revenue < 0) then
        return "TerraLogic usage: tlTestStart <label> [revenuePerHa>=0]"
    end

    local spec = implement.spec_terraLogic
    local rootVehicle = implement.rootVehicle or implement
    local motor = rootVehicle.getMotor ~= nil and rootVehicle:getMotor() or nil
    local tractorRuntimeHp = motor ~= nil
        and (tonumber(motor.peakMotorPower) or 0) * 1.35962162 or 0
    local implementAge, implementLifetime, implementOperatingHours,
        vanillaAgeUsageFactor, adjustedAgeUsageFactor =
            getVanillaAgeUsageData(implement)
    local economyDifficulty, economyName, economyCostMultiplier,
        economyPriceMultiplier = getEconomyData()
    local startDamage = implement.getDamageAmount ~= nil
        and tonumber(implement:getDamageAmount()) or 0
    local price = implement.getPrice ~= nil and tonumber(implement:getPrice()) or 0
    local startRepairCost = Wearable.calculateRepairPrice(price or 0, startDamage or 0)
    local safeLabel = tostring(label or "test"):gsub("[^%w%._%-]", "_")

    spec.balanceTest = {
        active = true,
        label = safeLabel,
        startMissionTime = g_currentMission.time or 0,
        startDamage = startDamage or 0,
        price = price or 0,
        startRepairCost = startRepairCost or 0,
        revenuePerHa = revenue,
        economyDifficulty = economyDifficulty,
        economyName = economyName,
        economyCostMultiplier = economyCostMultiplier,
        economyPriceMultiplier = economyPriceMultiplier,
        implementName = getObjectName(implement, "implement"),
        implementClass = spec.implementClassKey or "unknown",
        storeCategory = spec.storeCategory or "unknown",
        tractorName = getObjectName(rootVehicle, "tractor"),
        tractorRuntimeHp = tractorRuntimeHp,
        tractorShopHp = getActiveMotorShopHp(rootVehicle, tractorRuntimeHp),
        implementNeededHp = getImplementNeededHp(implement),
        ratedSpeed = spec.ratedSpeed or 0,
        recommendedSpeed = spec.optimalSpeed or spec.ratedSpeed or 0,
        safeSpeedRatio = spec.safeSpeedRatio
            or (TerraLogic ~= nil
                and TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT or 0.80),
        safeSpeed = spec.safeSpeed or ((spec.ratedSpeed or 0) * (spec.safeSpeedRatio
            or (TerraLogic ~= nil
                and TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT or 0.80))),
        safeSpeedSource = spec.safeSpeedSource or "unknown",
        safeSpeedFallback = spec.safeSpeedFallback == true,
        shopToClassSpeedFactor = spec.shopToClassSpeedFactor,
        workingWidth = implement:getOverSpeedWorkingWidth(),
        workDepthCm = spec.workDepthCm or 0,
        implementAge = implementAge,
        implementLifetime = implementLifetime,
        implementOperatingHours = implementOperatingHours,
        vanillaAgeUsageFactor = vanillaAgeUsageFactor,
        adjustedAgeUsageFactor = adjustedAgeUsageFactor,
        baseMaxForce = spec.baseMaxForce
            or (implement.spec_powerConsumer ~= nil
                and tonumber(implement.spec_powerConsumer.maxForce) or 0),
        activeMs = 0,
        areaHa = 0,
        distanceM = 0,
        speedTime = 0,
        speedMin = nil,
        speedMax = 0,
        aboveRatedMs = 0,
        aboveRatedAreaHa = 0,
        draftTime = 0,
        draftMax = 1,
        abrasionTime = 0,
        resistanceTime = 0,
        maxForceTime = 0,
        maxForceMax = 0,
        motorLoadTime = 0,
        motorLoadMax = 0,
        vanillaDamage = 0,
        continuousDamage = 0,
        speedAdjustmentDamage = 0,
        abrasionAdjustmentDamage = 0,
        wearPolicyAdjustmentDamage = 0,
        randomImpactDamage = 0,
        stoneSurfaceDamage = 0,
        stoneGeneratedDamage = 0,
        randomImpactCount = 0,
        smallImpactCount = 0,
        mediumImpactCount = 0,
        bigImpactCount = 0,
        impactDropoutCount = 0,
        impactDropoutMissedAreaHa = 0,
        soilTime = {}
    }
    self.balanceTestImplement = implement

    Logging.info(
        "[FS25_TerraLogic] BALANCE TEST START label=%s tractor=%s implement=%s revenuePerHa=%s",
        safeLabel, spec.balanceTest.tractorName, spec.balanceTest.implementName,
        revenue ~= nil and string.format("%.2f", revenue) or "n/a"
    )
    local revenueText = revenue ~= nil and string.format("%.0f/ha", revenue) or "n/a"
    return string.format(
        "TerraLogic balance test '%s' started | %s + %s | revenue %s",
        safeLabel, spec.balanceTest.tractorName, spec.balanceTest.implementName,
        revenueText
    )
end

function TerraLogicMain:consoleCommandTestStatus()
    local implement = self.balanceTestImplement
    local spec = implement ~= nil and implement.spec_terraLogic or nil
    local test = spec ~= nil and spec.balanceTest or nil
    if test == nil or test.active ~= true then
        return "TerraLogic: no balance test active"
    end
    local activeHours = (test.activeMs or 0) / 3600000
    local averageSpeed = (test.activeMs or 0) > 0
        and (test.speedTime or 0) / test.activeMs or 0
    return string.format(
        "TerraLogic test '%s' | %.3f ha | %.1f km/h avg | %.1f min active",
        test.label, test.areaHa or 0, averageSpeed, activeHours * 60
    )
end

function TerraLogicMain:consoleCommandTestCancel()
    local implement = self.balanceTestImplement
    local spec = implement ~= nil and implement.spec_terraLogic or nil
    local test = spec ~= nil and spec.balanceTest or nil
    if test == nil or test.active ~= true then
        return "TerraLogic: no balance test active"
    end
    test.active = false
    self.balanceTestImplement = nil
    return string.format("TerraLogic balance test '%s' cancelled", test.label)
end

function TerraLogicMain:consoleCommandTestStop()
    local implement = self.balanceTestImplement
    local spec = implement ~= nil and implement.spec_terraLogic or nil
    local test = spec ~= nil and spec.balanceTest or nil
    if test == nil or test.active ~= true then
        return "TerraLogic: no balance test active"
    end
    test.active = false
    self.balanceTestImplement = nil

    local activeMs = test.activeMs or 0
    local activeHours = activeMs / 3600000
    local areaHa = test.areaHa or 0
    local endDamage = implement.getDamageAmount ~= nil
        and tonumber(implement:getDamageAmount()) or test.startDamage
    local actualDamage = math.max((endDamage or 0) - (test.startDamage or 0), 0)
    local stoneDamage = (test.stoneSurfaceDamage or 0) + (test.stoneGeneratedDamage or 0)
    local componentDamage = (test.continuousDamage or 0)
        + (test.randomImpactDamage or 0) + stoneDamage
    local averageSpeed = activeMs > 0 and (test.speedTime or 0) / activeMs or 0
    local averageDraft = activeMs > 0 and (test.draftTime or 0) / activeMs or 1
    local averageAbrasion = activeMs > 0 and (test.abrasionTime or 0) / activeMs or 1
    local averageResistance = activeMs > 0 and (test.resistanceTime or 0) / activeMs or 1
    local averageMaxForce = activeMs > 0 and (test.maxForceTime or 0) / activeMs or 0
    local averageMotorLoad = activeMs > 0 and (test.motorLoadTime or 0) / activeMs or 0
    local fieldCapacity = activeHours > 0 and areaHa / activeHours or 0
    local damagePerHa = areaHa > 0 and actualDamage / areaHa or 0
    local vanillaDamagePerHa = areaHa > 0 and (test.vanillaDamage or 0) / areaHa or 0
    local componentDamagePerHa = areaHa > 0 and componentDamage / areaHa or 0
    local referenceWidth = math.max(self.NORMALIZED_REFERENCE_WIDTH_M or 3, 0.1)
    local damagePer10Km = (test.distanceM or 0) > 0
        and actualDamage / test.distanceM * 10000 or 0
    local vanillaDamagePer10Km = (test.distanceM or 0) > 0
        and (test.vanillaDamage or 0) / test.distanceM * 10000 or 0
    local componentDamagePer10Km = (test.distanceM or 0) > 0
        and componentDamage / test.distanceM * 10000 or 0
    local normalizedDamagePerHa = damagePer10Km / referenceWidth
    local normalizedVanillaDamagePerHa = vanillaDamagePer10Km / referenceWidth
    local normalizedComponentDamagePerHa = componentDamagePer10Km / referenceWidth
    local endRepairCost = Wearable.calculateRepairPrice(test.price or 0, endDamage or 0)
    local repairCost = math.max(endRepairCost - (test.startRepairCost or 0), 0)
    local repairCostPerHa = areaHa > 0 and repairCost / areaHa or 0
    local repairCostPer10Km = (test.distanceM or 0) > 0
        and repairCost / test.distanceM * 10000 or 0
    local normalizedRepairCostPerHa = repairCostPer10Km / referenceWidth
    local vanillaEndDamage = math.min((test.startDamage or 0) + (test.vanillaDamage or 0), 1)
    local vanillaEndRepairCost = Wearable.calculateRepairPrice(test.price or 0, vanillaEndDamage)
    local vanillaRepairCost = math.max(vanillaEndRepairCost - (test.startRepairCost or 0), 0)
    local vanillaRepairCostPerHa = areaHa > 0 and vanillaRepairCost / areaHa or 0
    local extraRepairCostPerHa = repairCostPerHa - vanillaRepairCostPerHa
    local repairCostPerActiveHour = activeHours > 0 and repairCost / activeHours or 0
    local extraRepairCostPerActiveHour = activeHours > 0
        and (repairCost - vanillaRepairCost) / activeHours or 0
    local hectaresFreshToFull = damagePerHa > 0 and 1 / damagePerHa or math.huge
    local hectaresRemaining = damagePerHa > 0
        and math.max(1 - (endDamage or 0), 0) / damagePerHa or math.huge
    local hoursFreshToFull = fieldCapacity > 0 and hectaresFreshToFull / fieldCapacity or math.huge
    local hectaresPer25Damage = damagePerHa > 0 and 0.25 / damagePerHa or math.huge
    local hoursPer25Damage = fieldCapacity > 0
        and hectaresPer25Damage / fieldCapacity or math.huge
    local fullRepairCost = Wearable.calculateRepairPrice(test.price or 0, 1)
    local impactsPerHa = areaHa > 0 and (test.randomImpactCount or 0) / areaHa or 0
    local totalVsVanilla = (test.vanillaDamage or 0) > 0
        and componentDamage / test.vanillaDamage * 100 or 0
    local aboveRatedTimePercent = activeMs > 0
        and (test.aboveRatedMs or 0) / activeMs * 100 or 0
    local aboveRatedAreaPercent = areaHa > 0
        and (test.aboveRatedAreaHa or 0) / areaHa * 100 or 0
    local revenue = test.revenuePerHa
    local repairRevenuePercent = revenue ~= nil and revenue > 0
        and repairCostPerHa / revenue * 100 or nil

    Logging.info("[FS25_TerraLogic] ===== BALANCE TEST RESULT BEGIN =====")
    Logging.info(
        "[FS25_TerraLogic] TEST meta label=%s tractor=%s tractorRuntimeHp=%.2f tractorShopHp=%s implement=%s class=%s category=%s neededHp=%s rated=%.2f classRealistic=%.2f safe=%.2f safeRatio=%.4f safeSource=%s fallback=%s shopToClassFactor=%s width=%.2f depthCm=%.1f price=%.2f",
        test.label, test.tractorName, test.tractorRuntimeHp or 0,
        test.tractorShopHp ~= nil and string.format("%.2f", test.tractorShopHp) or "n/a",
        test.implementName, test.implementClass, test.storeCategory,
        test.implementNeededHp ~= nil and string.format("%.2f", test.implementNeededHp) or "n/a",
        test.ratedSpeed or 0, test.recommendedSpeed or 0,
        test.safeSpeed or 0, test.safeSpeedRatio or 0,
        tostring(test.safeSpeedSource or "unknown"),
        tostring(test.safeSpeedFallback == true),
        test.shopToClassSpeedFactor ~= nil
            and string.format("%.4f", test.shopToClassSpeedFactor) or "n/a",
        test.workingWidth or 0, test.workDepthCm or 0, test.price or 0
    )
    Logging.info(
        "[FS25_TerraLogic] TEST context economyDifficulty=%s economyName=%s economyCostMultiplier=%s economyPriceMultiplier=%s implementAge=%.3f implementLifetime=%.3f implementOperatingHours=%.3f vanillaAgeUsageFactor=%.4f adjustedAgeUsageFactor=%.4f wearPolicy=%s xmlWearMinutes=%.3f xmlWearRateFactor=%.6f implementAbrasion=%.4f soilAbrasion=%.4f baselineAbrasion=%.4f",
        test.economyDifficulty ~= nil and tostring(test.economyDifficulty) or "n/a",
        test.economyName or "unknown",
        test.economyCostMultiplier ~= nil
            and string.format("%.4f", test.economyCostMultiplier) or "n/a",
        test.economyPriceMultiplier ~= nil
            and string.format("%.4f", test.economyPriceMultiplier) or "n/a",
        test.implementAge or 0, test.implementLifetime or 0,
        test.implementOperatingHours or 0, test.vanillaAgeUsageFactor or 1,
        test.adjustedAgeUsageFactor or test.vanillaAgeUsageFactor or 1,
        tostring(test.wearPolicy or "unknown"),
        test.xmlWearDurationMinutes or 0,
        test.xmlWearRateFactor or 0,
        test.implementAbrasionFactor or 0,
        test.soilAbrasionFactor or 1,
        test.baselineAbrasionMultiplier or 1
    )
    Logging.info(
        "[FS25_TerraLogic] TEST work areaHa=%.6f distanceM=%.2f activeMinutes=%.3f fieldCapacityHaH=%.3f speedAvg=%.3f speedMin=%.3f speedMax=%.3f aboveRatedTimePct=%.2f aboveRatedAreaPct=%.2f",
        areaHa, test.distanceM or 0, activeHours * 60, fieldCapacity,
        averageSpeed, test.speedMin or 0, test.speedMax or 0,
        aboveRatedTimePercent, aboveRatedAreaPercent
    )
    Logging.info(
        "[FS25_TerraLogic] TEST load draftAvg=%.4f draftMax=%.4f abrasionAvg=%.4f resistanceAvg=%.4f baseMaxForce=%.4f maxForceAvg=%.4f maxForceMax=%.4f motorLoadAvgPct=%.2f motorLoadMaxPct=%.2f",
        averageDraft, test.draftMax or 1, averageAbrasion, averageResistance,
        test.baseMaxForce or 0, averageMaxForce, test.maxForceMax or 0,
        averageMotorLoad * 100, (test.motorLoadMax or 0) * 100
    )
    Logging.info(
        "[FS25_TerraLogic] TEST damage startPct=%.6f endPct=%.6f actualDeltaPct=%.6f componentTotalPct=%.6f continuousWearPct=%.6f vanillaPct=%.6f policyAdjustmentPct=%.6f speedAdjustmentPct=%.6f abrasionAdjustmentPct=%.6f randomImpactPct=%.6f stoneSurfacePct=%.6f stoneGeneratedPct=%.6f totalVsVanillaPct=%.2f",
        percentOrZero(test.startDamage), percentOrZero(endDamage),
        percentOrZero(actualDamage), percentOrZero(componentDamage),
        percentOrZero(test.continuousDamage),
        percentOrZero(test.vanillaDamage),
        percentOrZero(test.wearPolicyAdjustmentDamage),
        percentOrZero(test.speedAdjustmentDamage),
        percentOrZero(test.abrasionAdjustmentDamage),
        percentOrZero(test.randomImpactDamage),
        percentOrZero(test.stoneSurfaceDamage), percentOrZero(test.stoneGeneratedDamage),
        totalVsVanilla
    )
    Logging.info(
        "[FS25_TerraLogic] TEST impacts total=%d small=%d medium=%d big=%d impactsPerHa=%.3f randomDamagePct=%.6f realStoneDamagePct=%.6f",
        test.randomImpactCount or 0, test.smallImpactCount or 0,
        test.mediumImpactCount or 0, test.bigImpactCount or 0,
        impactsPerHa, percentOrZero(test.randomImpactDamage), percentOrZero(stoneDamage)
    )
    Logging.info(
        "[FS25_TerraLogic] TEST mechanicalDropouts triggers=%d missedAreaHa=%.6f missedPctOfWorkedArea=%.3f",
        test.impactDropoutCount or 0,
        test.impactDropoutMissedAreaHa or 0,
        areaHa > 0 and (test.impactDropoutMissedAreaHa or 0) / areaHa * 100 or 0
    )
    Logging.info(
        "[FS25_TerraLogic] TEST normalized damagePerHaPct=%.6f componentDamagePerHaPct=%.6f vanillaDamagePerHaPct=%.6f repairCost=%.2f repairCostPerHa=%.2f vanillaRepairCostPerHa=%.2f extraRepairCostPerHa=%.2f repairCostPerActiveHour=%.2f extraRepairCostPerActiveHour=%.2f hectaresFreshTo100=%s hectaresRemaining=%s hoursFreshTo100=%s",
        damagePerHa * 100, componentDamagePerHa * 100, vanillaDamagePerHa * 100,
        repairCost, repairCostPerHa, vanillaRepairCostPerHa,
        extraRepairCostPerHa, repairCostPerActiveHour,
        extraRepairCostPerActiveHour,
        hectaresFreshToFull < math.huge and string.format("%.3f", hectaresFreshToFull) or "n/a",
        hectaresRemaining < math.huge and string.format("%.3f", hectaresRemaining) or "n/a",
        hoursFreshToFull < math.huge and string.format("%.3f", hoursFreshToFull) or "n/a"
    )
    Logging.info(
        "[FS25_TerraLogic] TEST widthNormalized referenceWidthM=%.2f damagePer10KmPct=%.6f componentDamagePer10KmPct=%.6f vanillaDamagePer10KmPct=%.6f normalizedDamagePerHaPct=%.6f normalizedComponentDamagePerHaPct=%.6f normalizedVanillaDamagePerHaPct=%.6f repairCostPer10Km=%.2f normalizedRepairCostPerHa=%.2f",
        referenceWidth, damagePer10Km * 100, componentDamagePer10Km * 100,
        vanillaDamagePer10Km * 100, normalizedDamagePerHa * 100,
        normalizedComponentDamagePerHa * 100,
        normalizedVanillaDamagePerHa * 100, repairCostPer10Km,
        normalizedRepairCostPerHa
    )
    Logging.info(
        "[FS25_TerraLogic] TEST service hectaresPer25Damage=%s hoursPer25Damage=%s fullRepairCost=%.2f startRepairCost=%.2f endRepairCost=%.2f",
        hectaresPer25Damage < math.huge and string.format("%.3f", hectaresPer25Damage) or "n/a",
        hoursPer25Damage < math.huge and string.format("%.3f", hoursPer25Damage) or "n/a",
        fullRepairCost, test.startRepairCost or 0, endRepairCost
    )
    if revenue ~= nil then
        Logging.info(
            "[FS25_TerraLogic] TEST economics revenuePerHa=%.2f repairCostPerHa=%.2f repairShareOfRevenuePct=%.3f revenueAfterImplementRepairPerHa=%.2f",
            revenue, repairCostPerHa, repairRevenuePercent or 0,
            revenue - repairCostPerHa
        )
    else
        Logging.info(
            "[FS25_TerraLogic] TEST economics revenuePerHa=n/a repairCostPerHa=%.2f repairShareOfRevenuePct=n/a revenueAfterImplementRepairPerHa=n/a",
            repairCostPerHa
        )
    end
    for soilIndex = 0, 4 do
        local soilMs = test.soilTime ~= nil and (test.soilTime[soilIndex] or 0) or 0
        if soilMs > 0 then
            local soilData = TerraLogic ~= nil and TerraLogic.SOIL_DATA[soilIndex] or nil
            Logging.info(
                "[FS25_TerraLogic] TEST soil index=%d name=%s timePct=%.3f",
                soilIndex, soilData ~= nil and soilData.name or "Vanilla/unknown",
                activeMs > 0 and soilMs / activeMs * 100 or 0
            )
        end
    end
    Logging.info("[FS25_TerraLogic] ===== BALANCE TEST RESULT END =====")

    local economySummary = revenue ~= nil and string.format(
        "%.1f%% of %.0f revenue", repairRevenuePercent or 0, revenue
    ) or "revenue n/a"
    return string.format(
        "TerraLogic test '%s' logged | %.3f ha | %.2f%% damage/ha | %.0f repair/ha | %s",
        test.label, areaHa, damagePerHa * 100, repairCostPerHa, economySummary
    )
end

function TerraLogicMain:consoleCommandEnable(value)
    if value == nil or value == "" then
        return string.format("TerraLogic mod: %s", self.enabled and "ENABLED" or "DISABLED")
    end
    local enabled = parseEnabled(value)
    if enabled == nil then
        return "TerraLogic usage: tlEnable [on|off]"
    end
    self.enabled = enabled
    self.debugNextRefresh = 0
    return string.format("TerraLogic mod: %s", enabled and "ENABLED" or "DISABLED")
end

function TerraLogicMain:consoleCommandWearPolicy(value)
    local requested = value ~= nil and string.lower(tostring(value)) or ""
    if requested == "" then
        return string.format("TerraLogic wear policy: %s", self.wearPolicy)
    end
    local resolved = requested == "forcevanilla" and "forceVanilla" or requested
    if resolved ~= "respect" and resolved ~= "normalize"
        and resolved ~= "forceVanilla" then
        return "TerraLogic usage: tlWearPolicy <respect|normalize|forceVanilla>"
    end
    self.wearPolicy = resolved
    self.debugNextRefresh = 0
    return string.format("TerraLogic wear policy set to: %s", resolved)
end

local function setRuntimeToggle(owner, fieldName, value, label, usage)
    if value == nil or value == "" then
        return string.format("TerraLogic %s: %s", label, owner[fieldName] and "ENABLED" or "DISABLED")
    end
    local enabled = parseEnabled(value)
    if enabled == nil then
        return usage
    end
    owner[fieldName] = enabled
    owner.debugNextRefresh = 0
    return string.format("TerraLogic %s: %s", label, enabled and "ENABLED" or "DISABLED")
end

function TerraLogicMain:consoleCommandDraft(value)
    return setRuntimeToggle(self, "draftEnabled", value, "additional draft", "TerraLogic usage: tlDraft [on|off]")
end

function TerraLogicMain:consoleCommandRandomImpacts(value)
    return setRuntimeToggle(self, "randomImpactsEnabled", value, "random impacts", "TerraLogic usage: tlImpacts [on|off]")
end

function TerraLogicMain:consoleCommandStoneImpacts(value)
    return setRuntimeToggle(self, "stoneImpactsEnabled", value, "real stone impacts", "TerraLogic usage: tlStones [on|off]")
end

function TerraLogicMain:getBalanceMultiplier(name)
    local value = self.balanceMultipliers ~= nil and self.balanceMultipliers[name] or nil
    return tonumber(value) or 1
end

function TerraLogicMain:resolveBalanceName(name)
    local normalized = name ~= nil and string.lower(tostring(name)) or ""
    normalized = string.gsub(normalized, "[^a-z]", "")
    return self.BALANCE_NAMES[normalized]
end

function TerraLogicMain:consoleCommandMultiplier(name, value)
    local resolvedName = self:resolveBalanceName(name)
    if resolvedName == nil then
        local names = {
            "wear", "draft", "damageResistance", "randomFrequency",
            "randomDamage", "stoneSurface", "stoneGenerated", "stoneHidden"
        }
        return "TerraLogic multiplier names: " .. table.concat(names, ", ")
            .. " | usage: tlMultiplier <name> <value|reset>"
    end

    if value == nil or value == "" then
        return string.format(
            "TerraLogic multiplier %s: x%.3f (default x%.3f)",
            resolvedName,
            self:getBalanceMultiplier(resolvedName),
            self.BALANCE_DEFAULTS[resolvedName]
        )
    end

    if string.lower(tostring(value)) == "reset" then
        self.balanceMultipliers[resolvedName] = self.BALANCE_DEFAULTS[resolvedName]
    else
        local multiplier = tonumber(value)
        if multiplier == nil or multiplier < 0 then
            return "TerraLogic usage: tlMultiplier <name> <non-negative value|reset>"
        end
        self.balanceMultipliers[resolvedName] = multiplier
    end

    self.debugNextRefresh = 0
    return string.format("TerraLogic multiplier %s: x%.3f", resolvedName, self.balanceMultipliers[resolvedName])
end

function TerraLogicMain:consoleCommandBalanceReset()
    for name, value in pairs(self.BALANCE_DEFAULTS) do
        self.balanceMultipliers[name] = value
    end
    self.draftEnabled = true
    self.randomImpactsEnabled = true
    self.stoneImpactsEnabled = true
    self.abrasionOverride = 0
    self.resistanceOverride = 0
    self.wearPolicy = "normalize"
    self.debugNextRefresh = 0
    return "TerraLogic temporary balance settings reset to defaults"
end

function TerraLogicMain:consoleCommandPrintBalance()
    Logging.info("[FS25_TerraLogic] ===== RUNTIME BALANCE START =====")
    Logging.info(
        "[FS25_TerraLogic] toggles mod=%s draft=%s randomImpacts=%s realStones=%s PF=%s wearPolicy=%s",
        tostring(self.enabled), tostring(self.draftEnabled),
        tostring(self.randomImpactsEnabled), tostring(self.stoneImpactsEnabled),
        tostring(self.precisionFarmingMode), tostring(self.wearPolicy)
    )
    for _, name in ipairs({
        "wear", "draft", "damageResistance", "randomFrequency",
        "randomDamage", "stoneSurface", "stoneGenerated", "stoneHidden"
    }) do
        Logging.info(
            "[FS25_TerraLogic] multiplier.%s=%.6f",
            name, self:getBalanceMultiplier(name)
        )
    end
    Logging.info(
        "[FS25_TerraLogic] soilOverrides abrasion=%.6f resistance=%.6f (0=automatic)",
        self.abrasionOverride or 0, self.resistanceOverride or 0
    )

    if TerraLogic ~= nil then
        Logging.info(
            "[FS25_TerraLogic] wear safeRatioFallback=%.6f classShopFactorMin=%.6f classShopFactorMax=%.6f atShop=%.6f belowShopExponent=%.6f aboveShopExponent=%.6f max=%.6f referenceMinutes=%.2f ageUsageFullHours=%.2f abrasiveShare=%.6f customWarningMin=%.6f customWarningMax=%.6f",
            TerraLogic.WEAR_SAFE_SPEED_RATIO_DEFAULT,
            TerraLogic.WEAR_CLASS_SHOP_FACTOR_MIN,
            TerraLogic.WEAR_CLASS_SHOP_FACTOR_MAX,
            TerraLogic.WEAR_AT_SHOP_SPEED,
            TerraLogic.WEAR_BELOW_SAFE_EXPONENT,
            TerraLogic.WEAR_ABOVE_SHOP_EXPONENT,
            TerraLogic.WEAR_MAX,
            TerraLogic.WEAR_REFERENCE_DURATION_MINUTES,
            TerraLogic.AGE_USAGE_MINIMUM_FULL_HOURS,
            TerraLogic.WEAR_ABRASIVE_SHARE,
            TerraLogic.WEAR_CUSTOM_RATE_WARNING_MIN,
            TerraLogic.WEAR_CUSTOM_RATE_WARNING_MAX
        )
        Logging.info(
            "[FS25_TerraLogic] draft fallbackStrength=%.6f fallbackExponent=%.6f fallbackMax=%.6f damageResistanceMax=%.6f damageResistanceFullAt=%.6f damageResistanceExponent=%.6f",
            TerraLogic.DRAFT_SPEED_STRENGTH_FALLBACK,
            TerraLogic.DRAFT_SPEED_EXPONENT_FALLBACK,
            TerraLogic.DRAFT_MAX_FALLBACK,
            TerraLogic.DAMAGE_MAX_FORCE_INCREASE,
            TerraLogic.DAMAGE_RESISTANCE_FULL_AT,
            TerraLogic.DAMAGE_RESISTANCE_EXPONENT
        )
        Logging.info(
            "[FS25_TerraLogic] random basePerHa=%.6f randomMin=%.6f randomMean=%.6f excessScale=%.6f excessExponent=%.6f",
            TerraLogic.IMPACT_BASE_EVENTS_PER_HA,
            TerraLogic.IMPACT_RANDOM_MIN_FACTOR,
            TerraLogic.IMPACT_RANDOM_MEAN_FACTOR,
            TerraLogic.IMPACT_EXCESS_ENERGY_SCALE,
            TerraLogic.IMPACT_EXCESS_ENERGY_EXPONENT
        )
        for name, tier in pairs(TerraLogic.IMPACT_TIERS) do
            Logging.info(
                "[FS25_TerraLogic] impactTier.%s eventsPerHa=%.6f probability=%.6f touchDamage=%.6f excessDamage=%.6f maxDamage=%.6f",
                name, tier.eventsPerHa, tier.probability,
                tier.touchDamage, tier.excessDamage, tier.maxDamage
            )
        end
        Logging.info(
            "[FS25_TerraLogic] stones surfacePerWeightedHa=%.6f generatedPerWeightedHa=%.6f maxPerScan=%.6f",
            TerraLogic.STONE_SURFACE_DAMAGE_PER_WEIGHTED_HA,
            TerraLogic.STONE_GENERATED_DAMAGE_PER_WEIGHTED_HA,
            TerraLogic.STONE_DAMAGE_MAX_PER_SCAN
        )
        Logging.info(
            "[FS25_TerraLogic] core soilUpdateMs=%d telemetryMs=%d stoneScanMs=%d",
            TerraLogic.SOIL_UPDATE_INTERVAL_MS,
            TerraLogic.TELEMETRY_INTERVAL_MS,
            TerraLogic.STONE_SCAN_INTERVAL_MS
        )
        for index, soil in pairs(TerraLogic.SOIL_DATA) do
            Logging.info(
                "[FS25_TerraLogic] soil.%d name=%s resistance=%.6f abrasion=%.6f randomFrequency=%.6f randomSeverity=%.6f",
                index, soil.name, soil.resistance, soil.abrasion,
                soil.impactFrequency, soil.impactSeverity
            )
        end
        for name, implementClass in pairs(TerraLogic.IMPLEMENT_CLASSES) do
            local work = implementClass.work or {}
            local draft = implementClass.draft or {}
            local wear = implementClass.wear or {}
            local impacts = implementClass.impacts or {}
            local stones = implementClass.stones or {}
            Logging.info(
                "[FS25_TerraLogic] implementProfile.%s optimalSpeed=%s safeSpeedRatio=%s minimumShopFactor=%s maximumShopFactor=%s depthCm=%.1f groundContact=%s draftEnabled=%s draftScale=%.6f impactDepth=%.6f stoneProtection=%s mediumImpactDamageFactor=%.6f abrasionFactor=%.6f stoneMode=%s stoneSurface=%.6f stoneGenerated=%.6f stoneHidden=%.6f dropout=%s impactDropout=%s name=%s",
                name, tostring(work.optimalSpeedKph),
                tostring(wear.safeSpeedRatio or "default"),
                tostring(wear.minimumShopFactor or "default"),
                tostring(wear.maximumShopFactor or "default"),
                tonumber(work.depthCm) or 0,
                tostring(work.groundContactTool == true),
                tostring(draft.enabled == true), tonumber(draft.overspeedScale) or 0,
                tonumber(impacts.depthFactor) or 0,
                tostring(impacts.stoneProtection == true),
                tonumber(impacts.mediumDamageFactor) or 1,
                tonumber(wear.abrasionFactor) or 0,
                tostring(stones.mode or "none"), tonumber(stones.surface) or 0,
                tonumber(stones.generated) or 0, tonumber(stones.hidden) or 0,
                tostring(implementClass.dropoutProfile or "none"),
                tostring(implementClass.impactDropoutProfile or "none"),
                implementClass.name
            )
        end
        if TerraLogicImplementProfiles ~= nil
            and TerraLogicImplementProfiles.REAL_SPEED_KPH ~= nil then
            for name, speed in pairs(TerraLogicImplementProfiles.REAL_SPEED_KPH) do
                Logging.info(
                    "[FS25_TerraLogic] realSpeedReference.%s=%.2f km/h",
                    name, tonumber(speed) or 0
                )
            end
        end
        if TerraLogicImplementProfiles ~= nil
            and TerraLogicImplementProfiles.ABRASION_FACTOR ~= nil then
            for name, factor in pairs(TerraLogicImplementProfiles.ABRASION_FACTOR) do
                Logging.info(
                    "[FS25_TerraLogic] abrasionReference.%s=%.4f",
                    name, tonumber(factor) or 0
                )
            end
        end
    end
    local implement = self:getDebugImplement(true)
    if implement ~= nil and implement.getOverSpeedDebugData ~= nil then
        local data = implement:getOverSpeedDebugData()
        Logging.info(
            "[FS25_TerraLogic] activeImplement name=%s class=%s store=%s via=%s depthCm=%.1f depthFactor=%.6f speed=%.6f classRealistic=%.6f safe=%.6f safeRatio=%.6f safeSource=%s fallback=%s shopToClassFactor=%s shopRated=%.6f soil=%s soilAbrasion=%.6f implementAbrasion=%.6f baselineAbrasion=%.6f wearPolicy=%s xmlWearMinutes=%.3f xmlWearRateFactor=%.6f resistance=%.6f",
            tostring(data.name), tostring(data.implementClassKey),
            tostring(data.storeCategory), tostring(data.classificationSource),
            tonumber(data.workDepthCm) or 0, tonumber(data.impactDepthFactor) or 1,
            tonumber(data.speed) or 0, tonumber(data.optimalSpeed) or 0,
            tonumber(data.safeSpeed) or 0, tonumber(data.safeSpeedRatio) or 0,
            tostring(data.safeSpeedSource or "unknown"),
            tostring(data.safeSpeedFallback == true),
            data.shopToClassSpeedFactor ~= nil
                and string.format("%.6f", data.shopToClassSpeedFactor) or "n/a",
            tonumber(data.ratedSpeed) or 0, tostring(data.soilName),
            tonumber(data.abrasionMultiplier) or 1,
            tonumber(data.implementAbrasionFactor) or 0,
            tonumber(data.baselineAbrasionMultiplier) or 1,
            tostring(data.wearPolicy or "unknown"),
            tonumber(data.xmlWearDurationMinutes) or 0,
            tonumber(data.xmlWearRateFactor) or 0,
            tonumber(data.soilResistanceMultiplier) or 1
        )
    end
    Logging.info("[FS25_TerraLogic] ===== RUNTIME BALANCE END =====")
    return "TerraLogic: all balance settings written to log.txt"
end

local function setPositiveOverride(owner, fieldName, value, commandName)
    local multiplier = tonumber(value)
    if multiplier == nil or multiplier < 0 then
        return string.format("TerraLogic usage: %s <multiplier|0>", commandName)
    end
    owner[fieldName] = multiplier
    owner.debugNextRefresh = 0
    if multiplier == 0 then
        return string.format("TerraLogic %s override cleared; soil value is active", commandName)
    end
    return string.format("TerraLogic %s override: x%.3f", commandName, multiplier)
end

function TerraLogicMain:consoleCommandAbrasion(value)
    if value == nil or value == "" then
        return self.abrasionOverride > 0
            and string.format("TerraLogic abrasion override: x%.3f", self.abrasionOverride)
            or "TerraLogic abrasion: soil value (no override)"
    end
    return setPositiveOverride(self, "abrasionOverride", value, "abrasion")
end

function TerraLogicMain:consoleCommandResistance(value)
    if value == nil or value == "" then
        return self.resistanceOverride > 0
            and string.format("TerraLogic resistance override: x%.3f", self.resistanceOverride)
            or "TerraLogic resistance: soil value (no override)"
    end
    return setPositiveOverride(self, "resistanceOverride", value, "resistance")
end

function TerraLogicMain:consoleCommandPrecisionFarmingInspect()
    local env = FS25_precisionFarming
    local controller = env ~= nil and env.g_precisionFarming or nil
    local soilMap = controller ~= nil and controller.soilMap or nil
    local soilClass = env ~= nil and env.SoilMap or nil
    local resolvedMap, _, source = self:getPrecisionFarmingSoilMap()

    return string.format(
        "TerraLogic PF inspect | loaded=%s env=%s controller=%s soilMap=%s directMethod=%s SoilMapClass=%s classMethod=%s resolved=%s source=%s",
        g_modIsLoaded ~= nil and tostring(g_modIsLoaded["FS25_precisionFarming"]) or "n/a",
        type(env),
        type(controller),
        type(soilMap),
        soilMap ~= nil and type(soilMap.getTypeIndexAtWorldPos) or "n/a",
        type(soilClass),
        soilClass ~= nil and type(soilClass.getTypeIndexAtWorldPos) or "n/a",
        resolvedMap ~= nil and "YES" or "NO",
        tostring(source)
    )
end

function TerraLogicMain:consoleCommandPrecisionFarming(value)
    local requestedMode = value ~= nil and string.lower(tostring(value)) or ""
    if requestedMode == "" then
        local soilMap, _, source = self:getPrecisionFarmingSoilMap()
        local detected = soilMap ~= nil
        return string.format(
            "TerraLogic PF mode: %s | PF soil map detected: %s | source: %s",
            self.precisionFarmingMode,
            detected and "YES" or "NO",
            source
        )
    end

    if requestedMode ~= "auto" and requestedMode ~= "on" and requestedMode ~= "off" then
        return "TerraLogic usage: tlPF [auto|on|off]"
    end

    self.precisionFarmingMode = requestedMode
    local soilMap, _, source = self:getPrecisionFarmingSoilMap()
    local detected = soilMap ~= nil
    return string.format(
        "TerraLogic PF mode set to %s | PF soil map detected: %s | source: %s",
        requestedMode,
        detected and "YES" or "NO",
        source
    )
end

function TerraLogicMain:consoleCommandDebugView(value)
    local view = value ~= nil and string.lower(tostring(value)) or ""
    if view == "balance" then
        view = "overview"
    elseif view == "impact" or view == "stones" then
        view = "impacts"
    elseif view == "soil" or view == "resistance" then
        view = "draft"
    elseif view == "cost" or view == "costs" then
        view = "economy"
    elseif view == "fieldquality" or view == "yieldquality"
        or view == "yield" then
        view = "workquality"
    end
    if self.DEBUG_VIEWS[view] ~= true then
        return "TerraLogic: unknown debug view. Use 'tlViews' to list all panels."
    end

    -- There is deliberately only one active view. Selecting another one
    -- replaces the old mode instead of stacking a second overlay.
    self.debugMode = view
    self.debugEnabled = true
    self.debugLines = nil
    self.workQualityDebugLines = nil
    self.debugNextRefresh = 0
    self.workQualityDebugNextRefresh = 0
    return string.format("TerraLogic debug view: %s", string.upper(view))
end

function TerraLogicMain:consoleCommandDebugViews()
    local lines = {
        "TerraLogic DEBUG PANELS (open with: tlView <name>)"
    }
    for _, entry in ipairs(self.DEBUG_VIEW_HELP) do
        local active = self.debugEnabled and self.debugMode == entry.name
            and " [ACTIVE]" or ""
        lines[#lines + 1] = string.format(
            "  %-10s - %s%s",
            entry.name,
            entry.description,
            active
        )
    end
    lines[#lines + 1] = "Close the active panel with: tlDebugClose"
    return table.concat(lines, "\n")
end

function TerraLogicMain:consoleCommandDebugClose()
    self.debugEnabled = false
    self.debugLines = nil
    self.debugNextRefresh = 0
    return "TerraLogic debug view: CLOSED"
end

function TerraLogicMain:consoleCommandDebug(value)
    if value == nil or value == "" then
        if self.debugEnabled then
            return self:consoleCommandDebugClose()
        end
        return self:consoleCommandDebugView(self.debugMode or "overview")
    end

    local requested = string.lower(tostring(value))
    local enabled = parseEnabled(requested)
    if enabled == false then
        return self:consoleCommandDebugClose()
    elseif enabled == true then
        return self:consoleCommandDebugView(self.debugMode or "overview")
    end
    return self:consoleCommandDebugView(requested)
end

function TerraLogicMain:consoleCommandSetDamage(value)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return "TerraLogic: tlSetDamage must be executed on the server/host"
    end

    local damagePercent = tonumber(value)
    if damagePercent == nil or damagePercent < 0 or damagePercent > 100 then
        return "TerraLogic usage: tlSetDamage <0-100>"
    end

    local implement = self:getDebugImplement(true)
    if implement == nil or implement.setDamageAmount == nil then
        return "TerraLogic: no supported implement selected or attached"
    end

    implement:setDamageAmount(damagePercent / 100, true)
    local spec = implement.spec_terraLogic
    if spec ~= nil then
        spec.damageRatePerMs = 0
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
    end

    return string.format(
        "TerraLogic: damage for '%s' set to %.2f%%",
        implement.getName ~= nil and implement:getName() or "implement",
        damagePercent
    )
end

-- HUD implement selection ---------------------------------------------------

-- Finds the selected or attached implement used by debug panels.
function TerraLogicMain:getDebugImplement(allowInactive)
    if g_localPlayer == nil or g_localPlayer:getCurrentVehicle() == nil then
        return nil
    end

    local vehicle = g_localPlayer:getCurrentVehicle()
    local vehicleSpec = vehicle.spec_terraLogic
    if vehicleSpec ~= nil
        and (vehicleSpec.isGroundTool == true or vehicleSpec.isApplicationTool == true)
        and vehicleSpec.ratedSpeed ~= nil and vehicleSpec.optimalSpeed ~= nil then
        local isWorking = (vehicle.getIsOverSpeedGroundContactActive ~= nil
                and vehicle:getIsOverSpeedGroundContactActive())
            or (vehicle.getIsOverSpeedApplicationActive ~= nil
                and vehicle:getIsOverSpeedApplicationActive())
        if allowInactive or isWorking then
            return vehicle
        end
    end
    if vehicle.getSelectedImplement ~= nil then
        local selected = vehicle:getSelectedImplement()
        if selected ~= nil and selected.object ~= nil and selected.object.spec_terraLogic ~= nil then
            local selectedSpec = selected.object.spec_terraLogic
            if (selectedSpec.isGroundTool == true or selectedSpec.isApplicationTool == true)
                and selectedSpec.ratedSpeed ~= nil
                and selectedSpec.optimalSpeed ~= nil then
                return selected.object
            end
        end
    end

    local rootVehicle = vehicle.rootVehicle or vehicle
    if rootVehicle.childVehicles ~= nil then
        for _, child in ipairs(rootVehicle.childVehicles) do
            if child ~= vehicle and child.spec_terraLogic ~= nil
                and (child.spec_terraLogic.isGroundTool == true
                    or child.spec_terraLogic.isApplicationTool == true)
                and child.spec_terraLogic.ratedSpeed ~= nil
                and child.spec_terraLogic.optimalSpeed ~= nil then
                local isWorking = (child.getIsOverSpeedGroundContactActive ~= nil
                        and child:getIsOverSpeedGroundContactActive())
                    or (child.getIsOverSpeedApplicationActive ~= nil
                        and child:getIsOverSpeedApplicationActive())
                if allowInactive or isWorking then
                    return child
                end
            end
        end
    end

    return nil
end

-- Returns the world position sampled by the standard field-information HUD.
local function getHudWorldPosition(display)
    local player = display ~= nil and display.player or g_localPlayer
    if player ~= nil and player.getPositionData ~= nil then
        local x, _, z = player:getPositionData()
        return x, z
    end
    local vehicle = player ~= nil and player:getCurrentVehicle() or nil
    local node = vehicle ~= nil and (vehicle.rootNode or vehicle.components ~= nil
        and vehicle.components[1] ~= nil and vehicle.components[1].node) or nil
    if node == nil and player ~= nil then
        node = player.rootNode
    end
    if node == nil then return nil, nil end
    local x, _, z = getWorldTranslation(node)
    return x, z
end

local function getIsGameHudVisible()
    if g_noHudModeEnabled == true or g_currentMission == nil
        or g_currentMission.hud == nil then
        return false
    end
    local hud = g_currentMission.hud
    if type(hud.getIsVisible) == "function" and not hud:getIsVisible() then
        return false
    end
    if type(hud.isVisible) == "boolean" and not hud.isVisible then
        return false
    end
    return true
end

function TerraLogicMain:getFieldInfoDisplay()
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    local display = hud ~= nil and hud.fieldInfoDisplay or nil
    if display ~= nil and display.addCustomText ~= nil
        and display.clearCustomText ~= nil then
        return display
    end
    return nil
end

function TerraLogicMain:clearQualityFieldInfoRows()
    local display = self:getFieldInfoDisplay()
    if display ~= nil and self.qualityFieldInfoRows ~= nil then
        for _, rowIndex in ipairs(self.qualityFieldInfoRows) do
            if rowIndex ~= nil and rowIndex > 0 then
                display:clearCustomText(rowIndex)
            end
        end
    end
    self.qualityFieldInfoRows = nil
    self.qualityFieldInfoSignature = nil
end

local function getIsSpeedHudImplementReady(implement)
    local spec = implement ~= nil and implement.spec_terraLogic or nil
    if spec == nil then return false end
    if spec.isGroundTool == true then
        -- For ploughs and other ground tools, "active" means attached and
        -- lowered into working position. Terrain pixels do not need to change
        -- at this instant, so the HUD also remains useful while stationary.
        local lowered = implement.getIsImplementChainLowered ~= nil
            and implement:getIsImplementChainLowered(true) == true
        if implement.getIsImplementChainLowered == nil
            and spec.isMowerTool == true then
            lowered = implement.getIsLowered == nil or implement:getIsLowered() == true
        end
        -- Call the internal helper directly. It is intentionally not registered
        -- as a vehicle function, so duplicate specialization registration by a
        -- third-party vehicle type cannot bypass the folded-roller guard.
        local inWorkPosition = TerraLogic == nil
            or TerraLogic.getIsOverSpeedWorkAreaInWorkPosition == nil
            or TerraLogic.getIsOverSpeedWorkAreaInWorkPosition(implement) == true
        if spec.isMowerTool == true and implement.getIsTurnedOn ~= nil then
            return lowered and inWorkPosition and implement:getIsTurnedOn() == true
        end
        return lowered and inWorkPosition
    end
    if spec.isApplicationTool == true then
        return implement.getIsOverSpeedApplicationActive ~= nil
            and implement:getIsOverSpeedApplicationActive() == true
    end
    return false
end

-- Selects the most restrictive active implement for the shared speed HUD.
function TerraLogicMain:getSpeedHudImplement()
    local vehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if vehicle == nil then return nil end
    local candidates, seen = {}, {}
    local function addCandidate(candidate)
        if candidate ~= nil and not seen[candidate]
            and getIsSpeedHudImplementReady(candidate) then
            seen[candidate] = true
            candidates[#candidates + 1] = candidate
        end
    end

    -- Include a self-propelled work vehicle and every active child in the
    -- complete attachment chain. Selection no longer decides which tool owns
    -- the HUD; the slowest active rated speed is the operational bottleneck.
    addCandidate(vehicle)
    local rootVehicle = vehicle.rootVehicle or vehicle
    for _, child in ipairs(rootVehicle.childVehicles or {}) do
        addCandidate(child)
    end
    if vehicle.getSelectedImplement ~= nil then
        local selected = vehicle:getSelectedImplement()
        addCandidate(selected ~= nil and selected.object or nil)
    end

    local limiting = nil
    for _, candidate in ipairs(candidates) do
        local spec = candidate.spec_terraLogic
        local rated = spec ~= nil and tonumber(spec.ratedSpeed) or nil
        local safe = spec ~= nil
            and (tonumber(spec.safeSpeed) or tonumber(spec.optimalSpeed)) or nil
        if rated ~= nil and rated > 0 then
            local limitingSpec = limiting ~= nil
                and limiting.spec_terraLogic or nil
            local limitingRated = limitingSpec ~= nil
                and tonumber(limitingSpec.ratedSpeed) or math.huge
            local limitingSafe = limitingSpec ~= nil
                and (tonumber(limitingSpec.safeSpeed)
                    or tonumber(limitingSpec.optimalSpeed)) or math.huge
            if rated < limitingRated - 0.001
                or (math.abs(rated - limitingRated) <= 0.001
                    and (safe or rated) < limitingSafe) then
                limiting = candidate
            end
        end
    end
    return limiting, #candidates, candidates
end

-- Legacy note: this formatter belonged to the old limiting-implement label.
-- The label was removed, so the helper is intentionally retained but unused
-- until compact implement names are needed by a future HUD or debug view.
local function getCompactImplementName(implement)
    local name = implement ~= nil and implement.getName ~= nil
        and tostring(implement:getName() or "") or ""
    if name == "" then return "Implement" end
    local maxCharacters = 18
    if utf8Strlen ~= nil and utf8Substr ~= nil then
        local okLength, length = pcall(utf8Strlen, name)
        if okLength and tonumber(length) ~= nil and length > maxCharacters then
            local okText, shortened = pcall(
                utf8Substr, name, 0, maxCharacters - 1)
            if okText and shortened ~= nil then return shortened .. "…" end
        end
        return name
    end
    return #name > maxCharacters
        and string.sub(name, 1, maxCharacters - 1) .. "..." or name
end

function TerraLogicMain:getSpeedHudWorkQuality(implement, currentSpeed)
    local spec = implement ~= nil and implement.spec_terraLogic or nil
    if spec == nil or TerraLogicQualityManager == nil then return nil end
    local component = nil
    if implement.spec_mower ~= nil then
        component = "mower"
    elseif implement.spec_sowingMachine ~= nil then
        component = "seed"
    elseif implement.spec_sprayer ~= nil then
        component = spec.applicationQualityComponent or "fertilizer"
    elseif implement.spec_plow ~= nil then
        component = "soilPlow"
    elseif implement.spec_cultivator ~= nil or implement.spec_subsoiler ~= nil
        or spec.implementClassKey == "powerHarrow"
        or spec.implementClassKey == "discHarrow"
        or spec.implementClassKey == "spader" then
        component = "soilCultivate"
    elseif implement.spec_roller ~= nil then
        component = "roller"
    elseif implement.spec_mulcher ~= nil then
        component = "mulch"
    elseif implement.spec_weeder ~= nil then
        component = "herbicide"
    end
    if component == nil then return nil end
    -- The speed HUD describes execution quality, not PF's transient remaining
    -- N/pH gain at the exact map pixel. Using that local gain made the display
    -- jump back to 100% on already optimal ground.
    return select(1, TerraLogicQualityManager:getWorkQualityModel(
        implement, currentSpeed, component, nil))
end

local function getSpeedHudScaledPixels(widthPx, heightPx)
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    local reference = hud ~= nil and (hud.fillLevelsDisplay
        or hud.speedMeterDisplay) or nil
    if reference ~= nil
        and reference.scalePixelValuesToScreenVector ~= nil then
        return reference:scalePixelValuesToScreenVector(
            widthPx or 0, heightPx or 0)
    end
    if getNormalizedScreenValues ~= nil then
        return getNormalizedScreenValues(widthPx or 0, heightPx or 0)
    end
    return (widthPx or 0) / 1920, (heightPx or 0) / 1080
end

local function getSpeedHudDefaultTextPixels()
    return HUDElement ~= nil and HUDElement.TEXT_SIZE ~= nil
        and tonumber(HUDElement.TEXT_SIZE.DEFAULT_TEXT) or 14
end

-- Creates reusable overlays once; no textures are allocated during rendering.
function TerraLogicMain:ensureSpeedHudOverlays()
    if self.speedHudOverlays ~= nil then
        return self.speedHudOverlays.available == true
    end
    local state = {available = false, background = {}, bars = {}}
    self.speedHudOverlays = state
    if g_overlayManager == nil or ThreePartOverlay == nil then return false end

    local ok = pcall(function()
        state.background.left = g_overlayManager:createOverlay(
            "gui.filltypes_left", 0, 0, 0, 0)
        state.background.middle = g_overlayManager:createOverlay(
            "gui.filltypes_middle", 0, 0, 0, 0)
        state.background.right = g_overlayManager:createOverlay(
            "gui.filltypes_right", 0, 0, 0, 0)
        local background = HUD ~= nil and HUD.COLOR ~= nil
            and HUD.COLOR.BACKGROUND or {0.01, 0.01, 0.01, 0.58}
        for _, overlay in pairs(state.background) do
            overlay:setColor(background[1], background[2],
                background[3], background[4])
        end
        for index = 1, 3 do
            local bar = ThreePartOverlay.new()
            bar:setLeftPart("gui.progressbar_left", 0, 0)
            bar:setMiddlePart("gui.progressbar_middle", 0, 0)
            bar:setRightPart("gui.progressbar_right", 0, 0)
            state.bars[index] = bar
        end
    end)
    state.available = ok
    return ok
end

function TerraLogicMain:deleteSpeedHudOverlays()
    local state = self.speedHudOverlays
    if state == nil then return end
    for _, overlay in pairs(state.background or {}) do
        if overlay ~= nil and overlay.delete ~= nil then overlay:delete() end
    end
    for _, overlay in pairs(state.bars or {}) do
        if overlay ~= nil and overlay.delete ~= nil then overlay:delete() end
    end
    self.speedHudOverlays = nil
end

function TerraLogicMain:renderSpeedHudBackground(x, y, width, height)
    if not self:ensureSpeedHudOverlays() then return false end
    local state = self.speedHudOverlays
    local capWidth = select(1, getSpeedHudScaledPixels(10, 0))
    capWidth = math.min(capWidth, width * 0.25)
    local left, middle, right = state.background.left,
        state.background.middle, state.background.right
    left:setPosition(x, y)
    left:setDimension(capWidth, height)
    middle:setPosition(x + capWidth, y)
    middle:setDimension(math.max(width - capWidth * 2, 0), height)
    right:setPosition(x + width - capWidth, y)
    right:setDimension(capWidth, height)
    left:render()
    middle:render()
    right:render()
    return true
end

function TerraLogicMain:renderSpeedHudBar(
        index, x, y, width, height, color, roundedLeft, roundedRight)
    local state = self.speedHudOverlays
    local bar = state ~= nil and state.bars[index] or nil
    if bar == nil or width <= 0 then return false end
    local capWidth = select(1, getSpeedHudScaledPixels(3, 0))
    capWidth = math.min(capWidth, width * 0.5)
    local leftWidth = roundedLeft and capWidth or 0
    local rightWidth = roundedRight and capWidth or 0
    bar:setLeftPart(nil, leftWidth, height)
    bar:setMiddlePart(nil,
        math.max(width - leftWidth - rightWidth, 0), height)
    bar:setRightPart(nil, rightWidth, height)
    bar:setColor(color[1], color[2], color[3], color[4])
    bar:setPosition(x, y)
    bar:render()
    return true
end

-- Draws the compact speed range, current marker and optional quality label.
function TerraLogicMain:drawSpeedHud()
    if self.enabled == false or g_localPlayer == nil then return end
    local hudMode = TerraLogicSettings ~= nil
        and TerraLogicSettings.speedHudMode or "dynamic"
    if hudMode == "off" then return end
    local now = g_currentMission.time or 0
    local vehicle = g_localPlayer:getCurrentVehicle()
    if self.speedHudVehicle ~= vehicle then
        self.speedHudVehicle = vehicle
        self.speedHudVehicleNameHiddenUntil = vehicle ~= nil and now + 5000 or 0
        self.speedHudImplement = nil
        self.speedHudOptimalSince = nil
    end
    if vehicle == nil or drawFilledRect == nil or not getIsGameHudVisible() then
        return
    end

    local implement, activeImplementCount = self:getSpeedHudImplement()
    if implement == nil then
        self.speedHudImplement = nil
        self.speedHudOptimalSince = nil
        return
    end
    local spec = implement.spec_terraLogic
    local shopSpeed = tonumber(spec.ratedSpeed) or 0
    local realSpeed = tonumber(spec.safeSpeed)
        or tonumber(spec.optimalSpeed) or shopSpeed
    if shopSpeed <= 0 then return end
    local currentSpeed = math.abs(vehicle:getLastSpeed(true) or 0)

    if self.speedHudImplement ~= implement then
        self.speedHudImplement = implement
        self.speedHudOptimalSince = nil
    end
    local cruiseSpeed = nil
    if vehicle ~= nil and vehicle.getCruiseControlSpeed ~= nil then
        cruiseSpeed = tonumber(vehicle:getCruiseControlSpeed())
    elseif vehicle ~= nil and vehicle.spec_drivable ~= nil
        and vehicle.spec_drivable.cruiseControl ~= nil then
        cruiseSpeed = tonumber(vehicle.spec_drivable.cruiseControl.speed)
    end
    if cruiseSpeed ~= nil then
        if self.speedHudCruiseVehicle == vehicle
            and self.speedHudCruiseSpeed ~= nil
            and math.abs(cruiseSpeed - self.speedHudCruiseSpeed) >= 0.1 then
            self.speedHudForcedUntil = now + 3000
        end
        self.speedHudCruiseVehicle = vehicle
        self.speedHudCruiseSpeed = cruiseSpeed
    end
    local isOptimal = currentSpeed >= realSpeed - 0.25
        and currentSpeed <= shopSpeed + 0.25
    local hideForOptimalSpeed = false
    if hudMode == "dynamic" and isOptimal then
        self.speedHudOptimalSince = self.speedHudOptimalSince or now
        if now - self.speedHudOptimalSince >= 3000
            and now >= (self.speedHudForcedUntil or 0) then
            hideForOptimalSpeed = true
        end
    elseif hudMode == "dynamic" then
        self.speedHudOptimalSince = nil
    else
        self.speedHudOptimalSince = nil
    end
    if now < (self.speedHudVehicleNameHiddenUntil or 0)
        or hideForOptimalSpeed then
        return
    end

    -- Pixel values follow the Vanilla fill-level widget and are scaled through
    -- an existing HUDDisplay when available, including the user's UI scale.
    local centreX = 0.5
    local width, height = getSpeedHudScaledPixels(225, 6)
    local showQualityText = TerraLogicSettings == nil
        or TerraLogicSettings.showQualityText ~= false
    local paddingBottomPixels = showQualityText and 8 or 6
    local paddingX, paddingBottom = getSpeedHudScaledPixels(
        14, paddingBottomPixels)
    local qualityTextPixels = math.max(
        getSpeedHudDefaultTextPixels() - 2, 10)
    local _, textHeight = getSpeedHudScaledPixels(0,
        showQualityText and qualityTextPixels or 0)
    local _, textGap = getSpeedHudScaledPixels(0,
        showQualityText and 7 or 0)
    local _, paddingTop = getSpeedHudScaledPixels(0,
        showQualityText and 4 or 8)
    local boxWidth = width + paddingX * 2
    local boxHeight = paddingBottom + height + textGap + textHeight + paddingTop
    -- Raise the complete widget another seven pixels while retaining the same
    -- UI-scale-aware bottom anchoring on different resolutions.
    local _, boxY = getSpeedHudScaledPixels(0, 30)
    local centreY = boxY + paddingBottom + height * 0.5
    local x, y = centreX - width * 0.5, centreY - height * 0.5
    -- Zoom the scale around the useful working range. Realistic-to-shop speed
    -- always occupies 60% of the bar; the remaining 40% provides equally
    -- sized slow/overspeed safety zones. This keeps narrow green ranges
    -- readable instead of compressing them into a global 0..50 km/h scale.
    local safetyShare = 0.20
    local greenShare = 0.60
    local greenSpeedRange = math.max(shopSpeed - realSpeed, 0.1)
    local safetySpeedRange = greenSpeedRange * safetyShare / greenShare
    local visibleMinimum = realSpeed - safetySpeedRange
    local visibleMaximum = shopSpeed + safetySpeedRange
    local visibleRange = math.max(visibleMaximum - visibleMinimum, 0.1)
    local realX = x + width * safetyShare
    local shopX = x + width * (safetyShare + greenShare)
    -- Keep marker motion continuous across the zoomed range. The live speed is
    -- intentionally not rounded, so narrow working ranges remain precise.
    local markerRatio = (currentSpeed - visibleMinimum) / visibleRange
    local markerOutsideLeft = markerRatio < 0
    local markerOutsideRight = markerRatio > 1
    local markerOutside = markerOutsideLeft or markerOutsideRight
    local markerX = x + width * math.clamp(markerRatio, 0, 1)

    -- Use the same rounded background and progress-bar slices as Vanilla's
    -- fill-level display. Rectangle rendering remains as a compatibility
    -- fallback for HUD replacement mods which remove these shared classes.
    local boxX = centreX - boxWidth * 0.5
    local nativeStyle = self:renderSpeedHudBackground(
        boxX, boxY, boxWidth, boxHeight)
    if not nativeStyle then
        drawFilledRect(boxX, boxY, boxWidth, boxHeight,
            0.01, 0.01, 0.01, 0.58)
    end
    local blue = {0.0097, 0.4287, 0.6445, 1}
    local green = HUD ~= nil and HUD.COLOR ~= nil and HUD.COLOR.ACTIVE
        or {0.22, 0.68, 0.30, 1}
    local orange = {1, 0.4287, 0.0006, 1}
    if nativeStyle then
        self:renderSpeedHudBar(1, x, y, math.max(realX - x, 0),
            height, blue, true, false)
        self:renderSpeedHudBar(2, realX, y,
            math.max(shopX - realX, 0), height, green, false, false)
        self:renderSpeedHudBar(3, shopX, y,
            math.max(x + width - shopX, 0), height, orange, false, true)
    else
        drawFilledRect(x, y, math.max(realX - x, 0), height,
            blue[1], blue[2], blue[3], blue[4])
        drawFilledRect(realX, y, math.max(shopX - realX, 0), height,
            green[1], green[2], green[3], green[4])
        drawFilledRect(shopX, y, math.max(x + width - shopX, 0), height,
            orange[1], orange[2], orange[3], orange[4])
    end
    drawFilledRect(realX - 0.00054, y - 0.00214,
        0.00108, height + 0.00428, 0.85, 0.92, 1, 1)
    drawFilledRect(shopX - 0.00054, y - 0.00214,
        0.00108, height + 0.00428, 1, 0.82, 0.18, 1)
    -- An out-of-range marker remains clamped to the appropriate edge and
    -- blinks, signalling that the real speed lies beyond the zoomed scale.
    local markerVisible = not markerOutside
        or math.floor(now / 300) % 2 == 0
    if markerVisible then
        drawFilledRect(markerX - 0.0008, y - 0.00374,
            0.0016, height + 0.00748, 1, 1, 1, 1)
    end

    local quality = showQualityText
        and self:getSpeedHudWorkQuality(implement, currentSpeed) or nil
    if quality ~= nil and renderText ~= nil then
        local roundedQuality = math.floor(
            math.clamp(quality, 0, 1) * 100 + 0.5)
        local format = TerraLogicQualityManager:getText(
            "terraLogic_speedHudQuality", "Work quality: %d %%")
        local label = string.format(format, roundedQuality)
        local _, size = getSpeedHudScaledPixels(0, qualityTextPixels)
        setTextBold(false)
        setTextColor(1, 1, 1, 1)
        -- Fixed anchors keep changing percentages and tool counts stable.
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(x, y + height + textGap, size, label)
        if (activeImplementCount or 0) > 1 then
            local countFormat = TerraLogicQualityManager:getText(
                "terraLogic_speedHudActiveImplements", "%d tools")
            local countLabel = string.format(
                countFormat, activeImplementCount)
            setTextAlignment(RenderText.ALIGN_RIGHT)
            renderText(x + width, y + height + textGap, size, countLabel)
        end
        setTextAlignment(RenderText.ALIGN_LEFT)
    end
end

-- Creates a Vanilla-style field-info box for the stored quality components.
function TerraLogicMain:getOrCreateQualityInfoBox()
    if self.qualityInfoBox ~= nil then return self.qualityInfoBox end
    local infoDisplay = g_currentMission ~= nil and g_currentMission.hud ~= nil
        and g_currentMission.hud.infoDisplay or nil
    if infoDisplay == nil or infoDisplay.createBox == nil
        or InfoDisplayKeyValueBox == nil then
        if self.qualityInfoBoxUnavailableLogged ~= true then
            self.qualityInfoBoxUnavailableLogged = true
            Logging.warning("[FS25_TerraLogic] Native WORK QUALITY info box is unavailable")
        end
        return nil
    end
    self.qualityInfoBox = infoDisplay:createBox(InfoDisplayKeyValueBox)
    if self.qualityInfoBox ~= nil then
        TerraLogicLogging.debug("[FS25_TerraLogic] Native WORK QUALITY info box created")
    end
    return self.qualityInfoBox
end

-- Updates field quality at the same sample position used by the Vanilla HUD.
function TerraLogicMain:drawQualityHud()
    if g_localPlayer == nil or g_localPlayer:getCurrentVehicle() ~= nil
        or not getIsGameHudVisible() then return end
    local box = self:getOrCreateQualityInfoBox()
    if box == nil then return end
    local x, z, fallbackX, fallbackZ = getHudWorldPosition(nil)
    if x == nil then return end
    local quality, entries = TerraLogicQualityManager:getSummaryAtWorldPosition(
        x, z, fallbackX, fallbackZ)
    if quality == nil then
        local implement = self:getDebugImplement()
        local isActivePlow = implement ~= nil and implement.spec_plow ~= nil
            and implement.getIsOverSpeedGroundContactActive ~= nil
            and implement:getIsOverSpeedGroundContactActive()
        if isActivePlow then
            local vehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil
            local speed = vehicle ~= nil
                and math.abs(vehicle:getLastSpeed(true) or 0) or 0
            local livePenalty
            quality, livePenalty = TerraLogicQualityManager:getWorkQualityModel(
                implement, speed, "soilPlow")
            local definition = TerraLogicQualityManager.GROUP_DEFINITIONS.soil
            entries = {{
                name = "soil",
                label = TerraLogicQualityManager:getComponentLabel("soil"),
                quality = quality,
                yieldPenalty = livePenalty
            }}
        end
    end
    if quality == nil or entries == nil or #entries == 0 then
        return
    end

    box:clear()
    box:setTitle(TerraLogicQualityManager:getText(
        "terraLogic_workQualityTitle", "WORK QUALITY"))
    for _, entry in ipairs(entries) do
        local percent = math.floor(entry.quality * 100 + 0.5)
        box:addLine(entry.label, string.format("%d %%", percent),
            entry.quality < 0.90)
    end
    local yieldFactor = TerraLogicQualityManager:getEffectiveYieldFactor(entries)
    local pfActive = self.isPrecisionFarmingActive ~= nil
        and self:isPrecisionFarmingActive()
    box:addLine(
        TerraLogicQualityManager:getText(
            pfActive and "terraLogic_workQualityRemainingPF"
                or "terraLogic_workQualityRemainingVanilla",
            pfActive and "Remaining of Precision Farming yield"
                or "Remaining of Vanilla yield"
        ),
        string.format("%d %%", math.floor(yieldFactor * 100 + 0.5)),
        yieldFactor < 0.90
    )
    box:showNextFrame()
    if self.qualityInfoBoxShownLogged ~= true then
        self.qualityInfoBoxShownLogged = true
        TerraLogicLogging.debug("[FS25_TerraLogic] WORK QUALITY info box shown with %d row(s)",
            #entries + 1)
    end
end

-- Debug panel helpers --------------------------------------------------------

-- Formats finite values consistently for the developer HUD.
local function formatNumber(value, decimals)
    if value == nil or value == math.huge or value ~= value then
        return "n/a"
    end
    return string.format("%." .. tostring(decimals or 1) .. "f", value)
end

local DEBUG_VIEW_SECTIONS = {
    wear = { ["SPEED / IMPLEMENT"] = true, ["CONTINUOUS WEAR"] = true },
    economy = {
        ["SPEED / IMPLEMENT"] = true,
        ["CONTINUOUS WEAR"] = true,
        ["LIFETIME / COST"] = true
    },
    draft = {
        ["SPEED / IMPLEMENT"] = true,
        ["DRAFT / RESISTANCE"] = true,
        ["SOIL INPUTS"] = true
    },
    impacts = {
        ["SPEED / IMPLEMENT"] = true,
        ["RANDOM IMPACTS (ABSTRACT / HIDDEN)"] = true,
        ["REAL STONE MAP IMPACTS"] = true
    },
    quality = { ["SPEED / IMPLEMENT"] = true, ["WORK QUALITY"] = true },
    technical = { ["SPEED / IMPLEMENT"] = true, ["TECHNICAL"] = true }
}

local function filterDebugSections(lines, view)
    local allowed = DEBUG_VIEW_SECTIONS[view]
    if allowed == nil then
        return lines
    end
    local filtered = {lines[1]}
    local keep = false
    for index = 2, #lines do
        local line = lines[index]
        local section = type(line) == "string"
            and string.match(line, "^%-%-%- (.-) %-%-%-$") or nil
        if section ~= nil then
            keep = allowed[section] == true
        end
        if keep then
            filtered[#filtered + 1] = line
        end
    end
    return filtered
end

local function buildOverviewLines(data, state, currentSpeed, recommendedSpeed, ratedSpeed)
    local qualitySummary = "not applicable"
    if data.isSowingMachine then
        qualitySummary = string.format("seed %.1f%% | %s",
            data.seedQuality * 100, data.seedQualityStatus)
    elseif data.isApplicationTool then
        qualitySummary = string.format("application %.1f%% | %s",
            data.applicationQuality * 100, data.applicationQualityStatus)
    elseif data.isSoilRoller then
        qualitySummary = string.format("roller rollback %.2f%% | %s",
            data.rollerQualityFailure * 100, data.rollerQualityStatus)
    end
    return {
        string.format("TerraLogic OVERVIEW | %s | %s | %s", data.name, state, data.groundToolType),
        "--- IMPLEMENT / SPEED ---",
        string.format("Speed %.1f km/h | class realistic %.1f | safe %.1f | shop %.1f | width %.2f m | damage %.2f%%",
            currentSpeed, recommendedSpeed, data.safeSpeed, ratedSpeed, data.workingWidth or 0,
            data.damagePercent),
        string.format("Safe resolver %s | shop/class %s | window %.2f-%.2f%s",
            data.safeSpeedSource,
            formatNumber(data.shopToClassSpeedFactor, 2),
            data.wearClassShopFactorMin, data.wearClassShopFactorMax,
            data.safeSpeedFallback and " | FALLBACK" or ""),
        string.format("Class %s | depth %.0f cm | work detection %s",
            data.implementClassKey, data.workDepthCm, data.workDetectionSource),
        "--- WEAR SNAPSHOT (LAST SECOND) ---",
        string.format("Actual %s%%/ha | %s%%/10km | normalized @ %.1fm %s%%/ha",
            formatNumber(data.currentDamagePerHectare ~= nil
                and data.currentDamagePerHectare * 100 or nil, 3),
            formatNumber(data.currentDamagePer10Km ~= nil
                and data.currentDamagePer10Km * 100 or nil, 3),
            data.normalizedReferenceWidth,
            formatNumber(data.normalizedDamagePerHectare ~= nil
                and data.normalizedDamagePerHectare * 100 or nil, 3)),
        string.format("Rate %.3f%%/h | continuous/Vanilla %s x | total/Vanilla %s x",
            data.damageRatePercentPerHour,
            formatNumber(data.continuousVsVanillaMultiplier, 2),
            formatNumber(data.totalVsVanillaMultiplier, 2)),
        string.format("Wear model %s | abrasion tool x%.2f | soil x%.2f | share %.0f%% | baseline x%.2f | policy %s",
            data.wearModel, data.implementAbrasionFactor, data.abrasionMultiplier,
            data.abrasiveShare * 100, data.baselineAbrasionMultiplier,
            data.wearPolicy),
        "--- ECONOMY / LOAD ---",
        string.format("Projected repair %s/ha | measured last second %s/ha",
            data.repairCostPerHectare ~= nil
                and g_i18n:formatMoney(data.repairCostPerHectare, 0, true, false) or "n/a",
            data.measuredRepairCostPerHectare ~= nil
                and g_i18n:formatMoney(data.measuredRepairCostPerHectare, 0, true, false) or "n/a"),
        string.format("Projected remaining %s ha | measured %s ha / %s km",
            formatNumber(data.projectedHectaresToFullDamage, 1),
            formatNumber(data.hectaresToFullDamage, 1),
            formatNumber(data.kilometersToFullDamage, 1)),
        string.format("Draft x%.3f | MaxForce %.2f -> %.2f kN | soil %s",
            data.speedDraftMultiplier, data.baseMaxForce, data.modifiedMaxForce,
            data.soilName),
        "--- EVENTS / QUALITY ---",
        string.format("Random impact damage %.3f%%/s | real stones %.3f%%/s | quality %s",
            data.randomImpactDamageLastSecondPercent,
            data.stoneDamageLastSecondPercent, qualitySummary)
    }
end

local function renderDebugPanel(lines)
    if lines == nil or #lines == 0 then return end
    local topY, x, textX = 0.865, 0.009, 0.015
    local heights, sizes = {}, {}
    local totalHeight, maximumWidth = 0.014, 0.28
    for index, line in ipairs(lines) do
        local isTitle = index == 1
        local isHeading = type(line) == "string"
            and string.match(line, "^%-%-%- .+ %-%-%-$") ~= nil
        local size = isTitle and 0.0140 or (isHeading and 0.0128 or 0.0113)
        local height = isTitle and 0.020 or (isHeading and 0.017 or 0.0142)
        sizes[index], heights[index] = size, height
        totalHeight = totalHeight + height
        if getTextWidth ~= nil then
            maximumWidth = math.max(maximumWidth, getTextWidth(size, tostring(line)))
        else
            maximumWidth = math.max(maximumWidth, #tostring(line) * size * 0.42)
        end
    end
    if drawFilledRect ~= nil then
        drawFilledRect(
            x,
            math.max(topY - totalHeight, 0.006),
            math.min(maximumWidth + 0.018, 0.982),
            math.min(totalHeight, topY - 0.006),
            0.01, 0.01, 0.01, 0.66
        )
    end
    local y = 0.84
    for index, line in ipairs(lines) do
        local isTitle = index == 1
        local isHeading = type(line) == "string"
            and string.match(line, "^%-%-%- .+ %-%-%-$") ~= nil
        if setTextBold ~= nil then setTextBold(isTitle or isHeading) end
        renderText(textX, y, sizes[index], line)
        if setTextBold ~= nil then setTextBold(false) end
        y = y - heights[index]
    end
end

function TerraLogicMain:drawWorkQualityDebug()
    local now = g_currentMission.time or 0
    if self.workQualityDebugLines == nil
        or now >= (self.workQualityDebugNextRefresh or 0) then
        local x, z, fallbackX, fallbackZ = getHudWorldPosition(nil)
        local overallQuality, entries
        if x ~= nil then
            overallQuality, entries = TerraLogicQualityManager:getSummaryAtWorldPosition(
                x, z, fallbackX, fallbackZ)
        end

        local byName = {}
        for _, entry in ipairs(entries or {}) do byName[entry.name] = entry end
        local lines = {
            string.format("TerraLogic WORK QUALITY | sample x=%s z=%s",
                formatNumber(x, 1), formatNumber(z, 1)),
            string.format(
                "Speed curve | real 100%% -> shop %.0f%% | post-shop H=exp(-%.2f*overspeed^2)",
                TerraLogicQualityManager.QUALITY_AT_SHOP_SPEED * 100,
                TerraLogicQualityManager.ECONOMY_CURVE_K),
            "--- CURRENT STORED OPERATIONS ---"
        }
        local rawLoss = 0
        for _, name in ipairs(TerraLogicQualityManager.GROUP_ORDER) do
            local definition = TerraLogicQualityManager.GROUP_DEFINITIONS[name]
            local entry = byName[name]
            local quality = entry ~= nil and entry.quality or nil
            local contribution = entry ~= nil
                and (entry.yieldPenalty or 0) or 0
            rawLoss = rawLoss + contribution
            lines[#lines + 1] = string.format(
                "%-12s | %-8s | Q %6s | weight %5.1f%% | max %4.1f%% | factor x%.4f%s",
                string.upper(name), entry ~= nil and "DONE" or "NOT DONE",
                quality ~= nil and string.format("%.1f%%", quality * 100) or "n/a",
                definition.yieldWeight * 100,
                definition.maxYieldPenalty * 100,
                1 - contribution,
                definition.directDensityPenalty == true and " (physical + residual)" or "")
        end
        local cappedLoss = math.clamp(
            rawLoss,
            0,
            TerraLogicQualityManager.MAXIMUM_TOTAL_YIELD_PENALTY
        )
        lines[#lines + 1] = "--- CURRENT TerraLogic YIELD EFFECT ---"
        lines[#lines + 1] = string.format(
            "Stored mean quality %s | relative loss %.3f | cap %.3f | applied %.3f",
            overallQuality ~= nil and string.format("%.1f%%", overallQuality * 100)
                or "n/a", rawLoss,
            TerraLogicQualityManager.MAXIMUM_TOTAL_YIELD_PENALTY,
            cappedLoss)
        lines[#lines + 1] = string.format(
            "Nominal TerraLogic factor x%.4f | baseline x1.0000 -> x%.4f | loss %.2f%%",
            1 - cappedLoss, 1 - cappedLoss, cappedLoss * 100)
        lines[#lines + 1] = "Formula: whole-yield work uses economic area target; bonus work can only remove its earned bonus"
        lines[#lines + 1] = "SEED target loss = physical missing plants + residual harvest correction"
        lines[#lines + 1] = "NOT DONE is neutral; Vanilla or active PF handles missing base-game bonuses"

        lines[#lines + 1] = "--- LAST REAL HARVEST APPLICATION (SERVER) ---"
        local harvest = TerraLogicQualityManager.lastHarvestDebug
        if harvest ~= nil then
            lines[#lines + 1] = string.format(
                "Base Vanilla/PF x%.4f -> after TerraLogic x%.4f | deduction %.3f points",
                harvest.baseMultiplier, harvest.finalMultiplier,
                harvest.appliedDeduction)
            lines[#lines + 1] = string.format(
                "Actual relative yield loss %.2f%% | quality loss %.2f%% | sampled cells %d",
                harvest.relativeLoss * 100, harvest.averageLoss * 100,
                harvest.samples or 0)
            if (harvest.liveHarvestPenalty or 0) > 0 then
                lines[#lines + 1] = string.format(
                    "Live root harvester %s | Q %.1f%% | direct whole-yield penalty %.2f%%",
                    tostring(harvest.liveHarvestClass or "root crop"),
                    (harvest.liveHarvestQuality or 1) * 100,
                    (harvest.liveHarvestPenalty or 0) * 100)
            end
        else
            lines[#lines + 1] = "No harvest processed in this session yet"
        end
        self.workQualityDebugLines = lines
        self.workQualityDebugNextRefresh = now + 1000
    end

    renderDebugPanel(self.workQualityDebugLines)
end

function TerraLogicMain:drawBalancingDebug()
    local implement = self:getDebugImplement()
    if implement == nil or implement.spec_terraLogic == nil then
        renderDebugPanel({
            "TerraLogic BALANCING",
            "No supported active implement selected"
        })
        return
    end
    local data = implement:getOverSpeedDebugData()
    local spec = implement.spec_terraLogic
    local speed = math.max(tonumber(data.speed) or 0, 0)
    local shopSpeed = math.max(tonumber(data.ratedSpeed) or 0, 0.01)
    local economy = TerraLogicQualityManager:getSpeedEconomy(implement, speed)
    local ratio = economy.shopRatio
    local overspeed = economy.overspeed
    local timeSaved = economy.timeSaved
    local now = g_currentMission.time or 0
    local activeRows = {}
    local activeGroups = {}
    for _, group in ipairs(TerraLogicQualityManager.GROUP_ORDER) do
        local live = spec.liveWorkQualityGroups ~= nil
            and spec.liveWorkQualityGroups[group] or nil
        if live ~= nil and now - (live.time or 0) <= 1500 then
            activeGroups[group] = true
            activeRows[#activeRows + 1] = string.format(
                "%s | quality %.1f%% | yield loss %.1f%%",
                TerraLogicQualityManager:getComponentLabel(group),
                (live.quality or 1) * 100,
                (live.yieldPenalty or 0) * 100
            )
        end
    end
    local liveMower = spec.liveWorkQualityGroups ~= nil
        and spec.liveWorkQualityGroups.mower or nil
    if liveMower ~= nil and now - (liveMower.time or 0) <= 1500 then
        activeGroups.mower = true
        activeRows[#activeRows + 1] = string.format(
            "%s | quality %.1f%% | yield loss %.1f%%",
            TerraLogicQualityManager:getComponentLabel("mower"),
            (liveMower.quality or 1) * 100,
            (liveMower.yieldPenalty or 0) * 100)
    end
    if next(activeGroups) == nil then
        if implement.spec_sowingMachine ~= nil then
            activeGroups.seed = true
            if implement.spec_sowingMachine.useDirectPlanting == true then
                activeGroups.soil = true
            end
        elseif implement.spec_plow ~= nil or implement.spec_cultivator ~= nil then
            activeGroups.soil = true
        elseif implement.spec_sprayer ~= nil then
            activeGroups[spec.applicationQualityComponent or "fertilizer"] = true
        elseif implement.spec_roller ~= nil then
            activeGroups.roller = true
        elseif implement.spec_mulcher ~= nil then
            activeGroups.mulch = true
        elseif implement.spec_weeder ~= nil then
            activeGroups.herbicide = true
        elseif implement.spec_mower ~= nil then
            activeGroups.mower = true
        end
    end

    local currentFactor, shopFactor = 1, 1
    local modelRows = {}
    local componentByGroup = {
        soil = implement.spec_plow ~= nil and "soilPlow"
            or (implement.spec_sowingMachine ~= nil
                and implement.spec_sowingMachine.useDirectPlanting == true
                and "soilCultivate" or "soilCultivate"),
        seed = "seed", fertilizer = "fertilizer", lime = "lime",
        herbicide = "herbicide", roller = "roller", mulch = "mulch"
    }
    componentByGroup.mower = "mower"
    local modelGroupOrder = {}
    for _, group in ipairs(TerraLogicQualityManager.GROUP_ORDER) do
        modelGroupOrder[#modelGroupOrder + 1] = group
    end
    if activeGroups.mower == true then
        modelGroupOrder[#modelGroupOrder + 1] = "mower"
    end
    for _, group in ipairs(modelGroupOrder) do
        if activeGroups[group] == true then
            local component = componentByGroup[group]
            local bonusOverride = (group == "fertilizer" or group == "lime")
                and spec.applicationQualityPfBonus or nil
            local quality, penalty, model =
                TerraLogicQualityManager:getWorkQualityModel(
                    implement, speed, component, bonusOverride)
            local displayQuality = bonusOverride ~= nil
                and select(1, TerraLogicQualityManager:getWorkQualityModel(
                    implement, speed, component, nil)) or quality
            currentFactor = currentFactor * model.areaFactor
            shopFactor = shopFactor * model.shopAreaFactor
            local effectDetail = model.effectType == "bonus"
                and string.format(" | bonus %.1f%% only%s",
                    (model.bonus or 0) * 100,
                    model.bonusFloorReached and " | BASELINE FLOOR" or "")
                or string.format(" | whole-yield cap %.1f%%%s",
                    (model.maximumPenalty or 0) * 100,
                    model.penaltyFloorReached and " | CAP REACHED" or "")
            modelRows[#modelRows + 1] = string.format(
                "%s | Q %.1f%% | area x%.3f | loss %.1f%%%s",
                TerraLogicQualityManager:getComponentLabel(group),
                displayQuality * 100, model.areaFactor, penalty * 100,
                effectDetail)
        end
    end
    local relativeYieldFactor = currentFactor / math.max(shopFactor, 0.0001)
    local yieldLossVsShop = 1 - relativeYieldFactor
    local hourlyYieldIndex = ratio * relativeYieldFactor
    local breakEvenFactor = ratio > 0 and math.min(1 / ratio, 1) or 1
    local breakEvenLoss = 1 - breakEvenFactor
    local pfActive = self.isPrecisionFarmingActive ~= nil
        and self:isPrecisionFarmingActive()
    local lines = {
        string.format("TerraLogic BALANCING | %s", data.name),
        "--- SPEED ECONOMY ---",
        string.format(
            "Current %.1f km/h | realistic %.1f | shop %.1f | shop ratio x%.3f",
            speed, economy.realSpeed, shopSpeed, ratio),
        string.format(
            "Shop overspeed %.1f%% | time saved per area %.1f%%",
            overspeed * 100, timeSaved * 100),
        string.format(
            "Speed wear | x%.3f Vanilla at current speed | x%.3f per-area vs shop",
            data.liveWearSpeedMultiplier, data.liveWearPerAreaVsShop),
        string.format(
            "Age/usage | Vanilla x%.3f -> TerraLogic x%.3f | full operating-age %.0f h",
            data.vanillaAgeUsageFactor,
            data.adjustedAgeUsageFactor,
            data.ageUsageFullHours),
        "--- LIVE WORK QUALITY ---"
    }
    if #activeRows == 0 then
        lines[#lines + 1] = "No recent density change; showing live model for detected implement"
    end
    for _, row in ipairs(modelRows) do lines[#lines + 1] = row end
    lines[#lines + 1] = "--- PROFITABILITY CHECK ---"
    lines[#lines + 1] = string.format(
        "Current area x%.3f | shop area x%.3f | retained vs shop %.1f%%",
        currentFactor, shopFactor, relativeYieldFactor * 100)
    lines[#lines + 1] = string.format(
        "Yield loss vs shop %.1f%% | break-even loss %.1f%% | margin %+.1f pp",
        yieldLossVsShop * 100, breakEvenLoss * 100,
        (yieldLossVsShop - breakEvenLoss) * 100)
    local profitabilityStatus = ratio <= 1.0001
        and "AT/BELOW SHOP SPEED"
        or (hourlyYieldIndex <= 1.0001
            and "OVERSPEED NOT PROFITABLE" or "OVERSPEED STILL PROFITABLE")
    lines[#lines + 1] = string.format(
        "SPEED/YIELD PROFITABILITY FACTOR %.3f | %s",
        hourlyYieldIndex,
        profitabilityStatus)
    lines[#lines + 1] = "Factor <1 = not profitable | >1 = profitable | benchmark: shop speed"
    lines[#lines + 1] = string.format(
        "Economic target H %.3f | curve K %.2f | abrasion/impacts excluded",
        economy.hourlyTarget, TerraLogicQualityManager.ECONOMY_CURVE_K)
    lines[#lines + 1] = string.format(
        "Yield basis: %s | PF bonus uses local N/pH gain when available",
        pfActive and "Precision Farming" or "Vanilla")
    lines[#lines + 1] = "Whole-yield caps | soil 45% | seed 50% | bonus work cannot fall below its baseline"
    renderDebugPanel(lines)
end

function TerraLogicMain:draw()
    if g_currentMission ~= nil then
        self:drawSpeedHud()
        self:drawQualityHud()
    end
    if not self.debugEnabled or g_currentMission == nil then
        return
    end
    if self.debugMode == "workquality" then
        self:drawWorkQualityDebug()
        return
    end
    if self.debugMode == "balancing" then
        self:drawBalancingDebug()
        return
    end

    local implement = self:getDebugImplement()
    if implement == nil then
        renderDebugPanel({"TerraLogic DEBUG", "No supported implement selected/working"})
        return
    end

    local now = g_currentMission.time or 0
    if self.debugLines == nil
        or self.debugLineImplement ~= implement
        or self.debugLineMode ~= self.debugMode
        or now >= (self.debugNextRefresh or 0) then
        local data = implement:getOverSpeedDebugData()
        local wearDifference = nil
        if data.vanillaDamagePerHectare ~= nil and data.vanillaDamagePerHectare > 0
            and data.continuousDamagePerHectare ~= nil then
            wearDifference = (data.continuousDamagePerHectare / data.vanillaDamagePerHectare - 1) * 100
        end

        local state = data.modEnabled and (data.telemetryWorking and "WORKING" or "PAUSED") or "MOD DISABLED"
        local recommendedSpeed = tonumber(data.optimalSpeed) or tonumber(data.ratedSpeed) or 0
        local ratedSpeed = tonumber(data.ratedSpeed) or recommendedSpeed
        local currentSpeed = tonumber(data.speed) or 0
        local lines = {
            string.format("TerraLogic %s | %s | %s | %s",
                string.upper(self.debugMode or "overview"),
                data.name, state, data.groundToolType),

            "--- SPEED / IMPLEMENT ---",
            string.format("Speed %.1f km/h | class realistic %.1f | safe %.1f (%.0f%% shop) | shop %.1f | damage %.2f%%",
                currentSpeed, recommendedSpeed, data.safeSpeed,
                data.safeSpeedRatio * 100, ratedSpeed, data.damagePercent),
            string.format("Classification | %s | store %s | via %s",
                data.groundToolType, data.storeCategory, data.classificationSource),
            string.format("Speed-limit unlock | %s | %s",
                data.speedLimitUnlockEligible and "ELIGIBLE" or "INACTIVE",
                data.speedLimitUnlockSource),
            string.format("Safe resolver | %s | shop/class %s | valid window %.2f-%.2f%s",
                data.safeSpeedSource,
                formatNumber(data.shopToClassSpeedFactor, 2),
                data.wearClassShopFactorMin, data.wearClassShopFactorMax,
                data.safeSpeedFallback and " | FALLBACK ACTIVE" or ""),
            string.format("Assumed work depth %.0f cm | impact-frequency depth factor x%.2f",
                data.workDepthCm, data.impactDepthFactor),
            string.format("Whole-yield quality | weight %.1f%% | operation cap %.1f%%",
                data.yieldWeight * 100, data.maxYieldPenalty * 100),

            "--- WORK QUALITY ---",
            data.isSowingMachine and string.format(
                "Seed work Q %.1f%% | retained placement %.1f%% | direct yield loss %.1f%% | weight %.1f%% cap %.1f%%",
                data.seedWorkQuality * 100, data.seedQuality * 100,
                data.seedYieldPenalty * 100, data.yieldWeight * 100,
                data.maxYieldPenalty * 100)
                or "Seed quality | not a sowing machine / planter",
            data.isSowingMachine and string.format(
                "Seed pattern | fruit %s | %s | mode %s | skipped lanes %d/%d | full-width chance %.2f%% | post-clear pixels %d",
                data.seedQualityFruit, data.seedQualityStatus,
                data.seedQualityPatternMode, data.seedQualityPatternLanes,
                data.seedQualityLaneCap, data.seedQualityFullWidthChance * 100,
                data.seedQualityPostClearPixels)
                or "Seed pattern | inactive",
            data.isSowingMachine and string.format(
                "Seed patch | WorkArea depth %.2f m | lane width %.2f m | hold %.2f m (%.2f remaining) | missed %.1f%% | %s",
                data.seedQualityWorkAreaDepthM,
                data.seedQualityEffectiveLaneWidthM,
                data.seedQualityHoldDistanceM,
                data.seedQualityHoldRemainingM,
                data.seedQualityMissedFraction * 100,
                data.seedQualityLatchReused and "LATCHED" or "NEW SAMPLE")
                or "Seed patch | inactive",
            data.isApplicationTool and string.format(
                "Application quality %.1f%% | health %.1f%% | dropout threshold %.1f km/h (damage shift -%.1f) | speed penalty %.1f%%",
                data.applicationQuality * 100, data.applicationQualityHealth * 100,
                data.applicationQualityThresholdSpeed,
                data.applicationQualityThresholdShift,
                data.applicationQualitySpeedPenalty * 100)
                or "Application quality | not a sprayer / spreader",
            data.isApplicationTool and string.format(
                "Application pattern | profile %s | mode %s | fill %s | %s | processed lanes %d | skipped lanes %d",
                data.applicationQualityProfile, data.applicationQualityPatternMode,
                data.applicationQualityFillType, data.applicationQualityStatus,
                data.applicationQualityProcessedLanes,
                data.applicationQualitySkippedLanes)
                or "Application pattern | inactive",
            data.isSoilRoller and string.format(
                "Roller rollback %.2f%% | %s | removed seed pixels %d",
                data.rollerQualityFailure * 100, data.rollerQualityStatus,
                data.rollerQualityFailedPixels)
                or "Roller rollback | not a soil roller",
            data.impactDropoutProfile ~= "none" and string.format(
                "Mechanical dropout | profile %s | %s",
                data.impactDropoutProfile, data.impactDropoutStatus)
                or "Mechanical dropout | unsupported for this class",
            data.impactDropoutProfile ~= "none" and string.format(
                "Overspeed plow surface | expected %.2f patches/100 m | last %d patch(es), %d extended, %d px",
                data.impactDropoutThrowEventsPer100m,
                data.plowIrregularLastPassEvents,
                data.plowIrregularLastTwoPixelEvents,
                data.plowIrregularLastPixels)
                or "Overspeed plow surface | inactive",
            data.impactDropoutProfile ~= "none" and string.format(
                "Density raster | terrain %.0f m | detail %.0f px | %.3f m/px (%.2fx linear) | dropout frequency x%.3f | %s",
                data.plowDensityTerrainSizeM,
                data.plowDensityDetailMapSize,
                data.plowDensityPixelSizeM,
                data.plowDensityLinearScale,
                data.plowDropoutResolutionFactor,
                data.plowDensityResolutionSource)
                or "Density raster | inactive",
            data.impactDropoutProfile ~= "none" and string.format(
                "Tripped segments %d/%d | tier %s | recovery %.2f/%.2f m remaining/hold",
                data.impactDropoutFailedLanes,
                data.impactDropoutTotalLanes,
                data.impactDropoutLastTier,
                data.impactDropoutRemainingDistanceM,
                data.impactDropoutHoldDistanceM)
                or "Mechanical recovery | inactive",
            data.impactDropoutProfile ~= "none" and string.format(
                "Stone work result | below/equal shop: damage only | above shop: one 1x2 patch (%d px) with previous PLOW_LEVEL",
                data.impactVisualOnlyPixels)
                or "Stone work result | inactive",
            data.impactDropoutProfile ~= "none" and string.format(
                "Mechanical totals | triggers %d (throw %d / medium %d / big %d) | missed %.5f ha | width-weighted distance %.1f m",
                data.impactDropoutTriggerCount,
                data.impactDropoutThrowCount,
                data.impactDropoutMediumCount,
                data.impactDropoutBigCount,
                data.impactDropoutMissedAreaHa,
                data.impactDropoutMissedDistanceM)
                or "Mechanical totals | inactive",
            data.impactDropoutProfile ~= "none" and string.format(
                "Plow hook | %s | rebound %d | visual effects: %s",
                data.plowDropoutHookActive and "ACTIVE" or "NOT CALLED",
                data.workAreaFunctionsRebound,
                data.plowVisualEffectStatus)
                or "Plow visual effects | inactive",

            "--- CONTINUOUS WEAR ---",
            string.format("Curve anchors | reference %.1f km/h = x%.2f | shop %.1f km/h = x%.2f",
                data.safeSpeed, data.wearAtSafeSpeed,
                ratedSpeed, data.wearAtShopSpeed),
            string.format("Curve shape | smooth real-to-shop Hermite + shifted cubic excess | exponents %.2f / %.2f | vehicle/shop ratio x%.2f",
                data.wearBelowShopExponent, data.wearAboveShopExponent,
                data.shopSpeedRatio),
            string.format("Runtime wear x%.3f | speed curve x%.2f | effective total x%.2f | %s",
                data.wearRuntimeMultiplier, data.speedDamageMultiplier,
                data.totalDamageMultiplier,
                data.wearSpeedApplicationActive and "ACTIVE WORK" or "PAUSED / TRANSPORT"),
            string.format("Wear baseline | policy %s | XML %.1f min (rate x%.3f) | reference %.0f min%s",
                data.wearPolicy, data.xmlWearDurationMinutes,
                data.xmlWearRateFactor, data.referenceWearDurationMinutes,
                data.customWearRateDetected and " | EXTREME CUSTOM RATE" or ""),
            string.format("Age/usage damage | Vanilla x%.3f -> TerraLogic x%.3f | full operating-age at %.0f h",
                data.vanillaAgeUsageFactor,
                data.adjustedAgeUsageFactor,
                data.ageUsageFullHours),
            data.wearModel == "surface"
                and string.format("Surface wear | PF abrasion ignored | Vanilla/XML baseline x%.3f | above shop: speed ratio cubed",
                    data.baselineAbrasionMultiplier)
                or string.format("Abrasion model | general %.0f%% + abrasive %.0f%% | tool x%.2f | soil x%.2f | load x%.3f | safe baseline x%.3f",
                    (1 - data.abrasiveShare) * 100, data.abrasiveShare * 100,
                    data.implementAbrasionFactor, data.abrasionMultiplier,
                    data.abrasiveLoad, data.baselineAbrasionMultiplier),
            data.wearSpeedApplicationActive
                and string.format("Speed application | curve x%.3f scales complete class/soil baseline x%.3f",
                    data.speedDamageMultiplier, data.baselineAbrasionMultiplier)
                or "Speed application | INACTIVE: raised/not working; TerraLogic adds no speed wear (Vanilla wear remains Vanilla-owned)",
            string.format("Continuous damage/ha | Vanilla %s%% | TerraLogic %s%% | difference %s%%",
                formatNumber(data.vanillaDamagePerHectare ~= nil and data.vanillaDamagePerHectare * 100 or nil, 3),
                formatNumber(data.continuousDamagePerHectare ~= nil and data.continuousDamagePerHectare * 100 or nil, 3),
                wearDifference ~= nil and string.format("%+.1f", wearDifference) or "n/a"),
            string.format("Total live wear | actual %s%%/ha | %s%%/10km | normalized @ %.1fm %s%%/ha",
                formatNumber(data.currentDamagePerHectare ~= nil and data.currentDamagePerHectare * 100 or nil, 3),
                formatNumber(data.currentDamagePer10Km ~= nil and data.currentDamagePer10Km * 100 or nil, 3),
                data.normalizedReferenceWidth,
                formatNumber(data.normalizedDamagePerHectare ~= nil and data.normalizedDamagePerHectare * 100 or nil, 3)),
            string.format("Continuous normalized | Vanilla %s%%/ha | TerraLogic %s%%/ha | TerraLogic/Vanilla %s x",
                formatNumber(data.normalizedVanillaDamagePerHectare ~= nil
                    and data.normalizedVanillaDamagePerHectare * 100 or nil, 3),
                formatNumber(data.normalizedContinuousDamagePerHectare ~= nil
                    and data.normalizedContinuousDamagePerHectare * 100 or nil, 3),
                formatNumber(data.continuousVsVanillaMultiplier, 2)),
            string.format("Live rate | total %.3f%%/h | estimated Vanilla %s%%/h | total/Vanilla %s x",
                data.damageRatePercentPerHour,
                formatNumber(data.vanillaDamageRatePercentPerHour, 3),
                formatNumber(data.totalVsVanillaMultiplier, 2)),

            "--- DRAFT / RESISTANCE ---",
            string.format("Shared draft curve | x1 through shop | strength %.2f | exponent %.2f | cap x%.2f",
                data.draftSpeedStrength, data.draftSpeedExponent, data.draftSpeedMaximum),
            string.format("Additional draft %s | profile scale x%.2f | global %s | runtime x%.3f | current x%.3f",
                data.additionalDraftEnabled and "ELIGIBLE" or "EXCLUDED",
                data.additionalDraftScale, data.globalDraftEnabled and "ON" or "OFF",
                data.draftRuntimeMultiplier, data.speedDraftMultiplier),
            string.format("Normalized drawbar-power proxy | speed ratio %.2f x draft %.3f = %.3f",
                ratedSpeed > 0 and currentSpeed / ratedSpeed or 0,
                data.speedDraftMultiplier,
                (ratedSpeed > 0 and currentSpeed / ratedSpeed or 0) * data.speedDraftMultiplier),
            string.format("MaxForce | original %.2f | soil %.2f | damage x%.2f (power %.2f, cap at %.0f%%, runtime x%.2f) | final %.2f kN",
                data.baseMaxForce, data.soilMaxForce, data.damageResistanceMultiplier,
                data.damageResistanceExponent, data.damageResistanceFullAt * 100,
                data.damageResistanceRuntimeMultiplier, data.projectedMaxForce),

            "--- SOIL INPUTS ---",
            string.format("PF soil | #%d %s", data.soilTypeIndex, data.soilName),
            string.format("PF/raw abrasion x%.3f | %s", data.abrasionMultiplier, data.abrasionSource),
            data.wearModel == "surface"
                and string.format("Surface wear | soil abrasion bypassed | Vanilla/XML baseline x%.3f",
                    data.baselineAbrasionMultiplier)
                or string.format("Implement abrasion x%.3f | abrasive share %.0f%% | tool x soil load %.3f | baseline x%.3f",
                    data.implementAbrasionFactor, data.abrasiveShare * 100,
                    data.abrasiveLoad, data.baselineAbrasionMultiplier),
            string.format("Resistance x%.3f | %s", data.soilResistanceMultiplier, data.resistanceSource),

            "--- RANDOM IMPACTS (ABSTRACT / HIDDEN) ---",
            string.format("Status %s | frequency runtime x%.3f | damage runtime x%.3f",
                data.randomImpactsEnabled and "ON" or "OFF",
                data.randomFrequencyRuntimeMultiplier, data.randomDamageRuntimeMultiplier),
            string.format("PF frequency x%.2f = %.1f/ha | stone-hidden x%.2f (runtime x%.2f) | active %.1f/ha",
                data.impactFrequencyFactor, data.soilImpactEventsPerHa,
                data.hiddenImpactFactor, data.stoneHiddenRuntimeMultiplier,
                data.impactRiskEventsPerHa),
            string.format("Area scaling | width %.2fm | active %.1f/ha => expected %.2f hits/km",
                data.workingWidth or 0, data.impactRiskEventsPerHa,
                data.impactRiskEventsPerKm),
            string.format("Depth frequency x%.2f | small %.2f/ha | medium %.3f/ha | big %.3f/ha",
                data.impactDepthFactor, data.impactSmallEventsPerHa,
                data.impactMediumEventsPerHa, data.impactBigEventsPerHa),
            string.format("Stone protection %s | medium damage x%.2f (small/big unchanged)",
                data.impactStoneProtection and "YES" or "NO",
                data.impactMediumDamageFactor),
            string.format("Tier shares | small %.2f%% | medium %.2f%% | big %.3f%%",
                data.impactSmallProbability * 100, data.impactMediumProbability * 100,
                data.impactBigProbability * 100),
            string.format("Energy x%.2f | raw excess x%.2f -> scaled x%.3f | PF severity x%.2f | damage last second %.3f%%",
                data.impactEnergy, data.excessImpactEnergy,
                data.scaledExcessImpactEnergy, data.impactSeverityFactor,
                data.randomImpactDamageLastSecondPercent),
            string.format("Max damage now | small %.2f%% | medium %.2f%% | big %.2f%%",
                data.impactSmallMaximumDamagePercent,
                data.impactMediumMaximumDamagePercent,
                data.impactBigMaximumDamagePercent),
            string.format("Expected damage/ha now | small %.2f%% | medium %.2f%% | big %.2f%% | total %.2f%%",
                data.impactSmallExpectedDamagePerHaPercent,
                data.impactMediumExpectedDamagePerHaPercent,
                data.impactBigExpectedDamagePerHaPercent,
                data.impactSmallExpectedDamagePerHaPercent
                    + data.impactMediumExpectedDamagePerHaPercent
                    + data.impactBigExpectedDamagePerHaPercent),
            string.format("Hits S/M/B %d/%d/%d | last %s %s%% (%ss ago)",
                data.impactSmallCount, data.impactMediumCount, data.impactBigCount,
                data.lastImpactTier, formatNumber(data.lastImpactDamagePercent, 1),
                formatNumber(data.lastImpactSecondsAgo, 0)),

            "--- REAL STONE MAP IMPACTS ---",
            string.format("Status %s | map %s | tool mode %s",
                data.stoneImpactsEnabled and "ON" or "OFF",
                data.stoneSystemActive and "ACTIVE" or data.stoneSystemStatus,
                data.stoneToolMode),
            string.format("Surface factor x%.3f (runtime x%.3f) | generation factor x%.3f (runtime x%.3f)",
                data.stoneSurfaceFactor, data.stoneSurfaceRuntimeMultiplier,
                data.stoneGenerationFactor, data.stoneGeneratedRuntimeMultiplier),
            string.format("Map | existing level %.2f coverage %.1f%% | generated weighted %.5f ha",
                data.stoneExistingLevel, data.stoneExistingCoveragePercent,
                data.stoneGeneratedWeightedHaLastSecond),
            string.format("Damage last second | surface %.3f%% | generated %.3f%% | total %.3f%% | scans %d",
                data.stoneSurfaceDamageLastSecondPercent,
                data.stoneGeneratedDamageLastSecondPercent,
                data.stoneDamageLastSecondPercent, data.stoneScansLastSecond),
            string.format("Last real-stone event | %s | %s%% (%ss ago)",
                data.lastStoneEventSource,
                formatNumber(data.lastStoneEventDamagePercent, 3),
                formatNumber(data.lastStoneEventSecondsAgo, 1)),

            "--- LIFETIME / COST ---",
            string.format("Measured damage/ha (last second) | %s%%",
                formatNumber(data.currentDamagePerHectare ~= nil and data.currentDamagePerHectare * 100 or nil, 3)),
            string.format("Projected damage/ha | %.3f%% (continuous + expected random + measured real stones)",
                (data.projectedDamagePerHectare or 0) * 100),
            string.format("Live total damage rate | %.2f%%/h", data.damageRatePercentPerHour),
            string.format("Projected lifetime | %s ha to 100%% | repair/ha %s",
                formatNumber(data.projectedHectaresToFullDamage, 2),
                data.repairCostPerHectare ~= nil and g_i18n:formatMoney(data.repairCostPerHectare, 0, true, false) or "n/a"),
            string.format("Distance lifetime | %s km to 100%% | working width %.2f m",
                formatNumber(data.kilometersToFullDamage, 1), data.workingWidth or 0),
            string.format("Repair comparison | measured/ha %s | projected/10km %s | projected @ %.1fm/ha %s",
                data.measuredRepairCostPerHectare ~= nil
                    and g_i18n:formatMoney(data.measuredRepairCostPerHectare, 0, true, false) or "n/a",
                data.repairCostPer10Km ~= nil
                    and g_i18n:formatMoney(data.repairCostPer10Km, 0, true, false) or "n/a",
                data.normalizedReferenceWidth,
                data.normalizedRepairCostPerHectare ~= nil
                    and g_i18n:formatMoney(data.normalizedRepairCostPerHectare, 0, true, false) or "n/a"),
            string.format("Repair | now %s | at 100%% %s",
                g_i18n:formatMoney(data.currentRepairCost or 0, 0, true, false),
                g_i18n:formatMoney(data.fullRepairCost or 0, 0, true, false))
        }

        if self.debugMode == "technical" then
            lines[#lines + 1] = "--- TECHNICAL ---"
            lines[#lines + 1] = string.format("TECH | workArea=%s via %s | width=%sm | PF=%s:%s",
                data.workAreaProcessing and "ACTIVE" or "INACTIVE", data.workDetectionSource,
                formatNumber(data.workingWidth, 1),
                string.upper(data.pfMode), data.pfActive and "ACTIVE" or "INACTIVE")
            lines[#lines + 1] = string.format("PF query %s ok=%s soil=%d via %s",
                data.pfLastPositionSource, data.pfLastQueryOk and "YES" or "NO",
                data.pfLastSoilTypeIndex, data.pfSoilValueSource)
            lines[#lines + 1] = string.format("PF source: %s | actual maxForce %.2f kN",
                data.pfSource, data.modifiedMaxForce)
            lines[#lines + 1] = string.format("Wear compatibility | %s | XML %.1fmin rate x%.3f | ref %.0fmin | custom=%s",
                data.wearPolicy, data.xmlWearDurationMinutes,
                data.xmlWearRateFactor, data.referenceWearDurationMinutes,
                data.customWearRateDetected and "EXTREME" or "normal")
            lines[#lines + 1] = string.format("QUALITY TECH | rebound=%d | seed hook=%s | density filter=%s calls=%d",
                data.workAreaFunctionsRebound,
                data.seedQualityHookActive and "ACTIVE" or "NOT CALLED",
                data.seedQualityDensityHookActive and "ACTIVE" or "NOT CALLED",
                data.seedQualityDensityCalls)
            lines[#lines + 1] = string.format("STONE TECH | scans/s=%d | existing weighted=%.5f ha | generated delta pixels=%.1f | last scan generated=%.5f ha",
                data.stoneScansLastSecond, data.stoneExistingWeightedHaLastSecond,
                data.stoneGeneratedLevelDelta, data.stoneGeneratedWeightedHaLastScan)
        end

        if self.debugMode == "overview" then
            lines = buildOverviewLines(
                data, state, currentSpeed, recommendedSpeed, ratedSpeed
            )
        else
            lines = filterDebugSections(lines, self.debugMode)
        end

        self.debugLines = lines
        self.debugLineImplement = implement
        self.debugLineMode = self.debugMode
        self.debugNextRefresh = now + 1000
    end

    renderDebugPanel(self.debugLines)
end

-- Specialization installation ----------------------------------------------

-- Registers the TerraLogic specialization with the vehicle type manager.
function TerraLogicMain.registerSpecialization()
    g_specializationManager:addSpecialization(
        SPEC_NAME,
        "TerraLogic",
        MOD_DIR .. "scripts/TerraLogic.lua",
        nil
    )

    TypeManager.finalizeTypes = Utils.appendedFunction(
        TypeManager.finalizeTypes,
        TerraLogicMain.installSpecialization
    )
end

-- Adds TerraLogic only to vehicle types that satisfy its prerequisites.
function TerraLogicMain.installSpecialization()
    if TerraLogicMain.specializationInstallDone then
        return
    end
    local specialization = g_specializationManager:getSpecializationObjectByName(SPEC_NAME)
    if specialization == nil then
        Logging.error("[%s] Could not load specialization '%s'", MOD_NAME, SPEC_NAME)
        return
    end
    TerraLogicMain.specializationInstallDone = true

    local installedCount = 0

    for _, vehicleType in pairs(g_vehicleTypeManager.types) do
        local specializations = vehicleType.specializationsByName
        local isAttachable = specializations ~= nil and specializations.attachable ~= nil
        local isWearable = specializations ~= nil and specializations.wearable ~= nil
        local isMotorized = specializations ~= nil and specializations.motorized ~= nil
        local isMower = specializations ~= nil and specializations.mower ~= nil
        local isHarvester = specializations ~= nil
            and (specializations.combine ~= nil or specializations.cutter ~= nil)
        local isAlreadyInstalled = specializations ~= nil and specializations[SPEC_NAME] ~= nil

        -- Ordinary implements remain supported as before. The only motorized
        -- allow-list entry is a true Mower vehicle; combines/cutters stay out so
        -- TerraLogic does not collide with dedicated harvesting/yield mods.
        local supportedImplement = isAttachable and isWearable and not isMotorized
        local supportedSelfPropelledMower = isMotorized and isWearable
            and isMower and not isHarvester
        if (supportedImplement or supportedSelfPropelledMower)
            and not isAlreadyInstalled then
            vehicleType.specializationsByName[SPEC_NAME] = specialization
            table.insert(vehicleType.specializationNames, SPEC_NAME)
            table.insert(vehicleType.specializations, specialization)
            installedCount = installedCount + 1
        end
    end

    TerraLogicLogging.debug("[%s] Installed specialization on %d implement vehicle types", MOD_NAME, installedCount)
end

TerraLogicMain.registerSpecialization()
if FSBaseMission ~= nil and FSBaseMission.saveSavegame ~= nil
    and FSBaseMission.terraLogicQualitySaveHookInstalled ~= true then
    FSBaseMission.saveSavegame = Utils.appendedFunction(
        FSBaseMission.saveSavegame,
        TerraLogicMain.saveWorkQualityData
    )
    FSBaseMission.terraLogicQualitySaveHookInstalled = true
    TerraLogicLogging.debug(
        "[%s] Installed FSBaseMission work-quality save hook",
        MOD_NAME
    )
end
addModEventListener(TerraLogicMain)
