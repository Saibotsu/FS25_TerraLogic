--[[
    TerraLogicQualityManager.lua
    Persistent work-quality cells, harvest penalties and multiplayer sync.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-QUAL-1.200274
]]

TerraLogicQualityManager = {}
OverSpeedQualityManager = TerraLogicQualityManager
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicQualityManager.SOURCE_FINGERPRINT = 1.200274

TerraLogicQualityManager.CELL_SIZE = 4
TerraLogicQualityManager.CHUNK_SIZE = 32
TerraLogicQualityManager.CHUNK_CELL_COUNT = 32 * 32
TerraLogicQualityManager.LAYER_FLUSH_THRESHOLD = 128
-- A mower can process the same fixed TerraLogic cell through several WorkAreas and
-- over several simulation frames. Finish the harvest only after that cell has
-- not been touched for a short period, so perennial recovery runs once per
-- cut instead of once per WorkArea/frame.
TerraLogicQualityManager.MOWER_CELL_SETTLE_TIME_MS = 500
TerraLogicQualityManager.SAVE_FILE = "terraLogicWorkQuality.xml"
TerraLogicQualityManager.LEGACY_SAVE_FILE = "overSpeedWorkQuality.xml"
-- Quality is almost perfect throughout the advertised working range. Above
-- shop speed the yield-per-hour target, not an arbitrary linear quality loss,
-- drives the curve. K=1 makes every overspeed marginally uneconomical before
-- draft, abrasion and random impacts are counted as additional costs.
TerraLogicQualityManager.QUALITY_AT_REAL_SPEED = 1.00
TerraLogicQualityManager.QUALITY_AT_SHOP_SPEED = 0.95
TerraLogicQualityManager.MINIMUM_SPEED_QUALITY = 0.00
TerraLogicQualityManager.ECONOMY_CURVE_K = 1.00
TerraLogicQualityManager.MAXIMUM_TOTAL_YIELD_PENALTY = 0.80
local CATEGORY_BALANCE = TerraLogicImplementProfiles.WORK_QUALITY_CATEGORIES
TerraLogicQualityManager.COMPONENTS = {
    soilPlow      = {group = "soil", labelKey = "terraLogic_workQualitySoil", fallbackLabel = "Soil preparation quality", yieldWeight = CATEGORY_BALANCE.soil.weight, maxYieldPenalty = CATEGORY_BALANCE.soil.maxPenalty, bit = 1},
    soilCultivate = {group = "soil", labelKey = "terraLogic_workQualitySoil", fallbackLabel = "Soil preparation quality", yieldWeight = CATEGORY_BALANCE.soil.weight, maxYieldPenalty = CATEGORY_BALANCE.soil.maxPenalty, bit = 2},
    seed          = {group = "seed", labelKey = "terraLogic_workQualitySeed", fallbackLabel = "Seeding quality", yieldWeight = CATEGORY_BALANCE.seed.weight, maxYieldPenalty = CATEGORY_BALANCE.seed.maxPenalty, directDensityPenalty = true, bit = 4},
    fertilizer    = {group = "fertilizer", labelKey = "terraLogic_workQualityFertilizer", fallbackLabel = "Fertilizing quality", yieldWeight = CATEGORY_BALANCE.fertilizer.weight, maxYieldPenalty = CATEGORY_BALANCE.fertilizer.maxPenalty, bit = 8},
    herbicide     = {group = "herbicide", labelKey = "terraLogic_workQualityHerbicide", fallbackLabel = "Weed control quality", yieldWeight = CATEGORY_BALANCE.herbicide.weight, maxYieldPenalty = CATEGORY_BALANCE.herbicide.maxPenalty, bit = 16},
    roller        = {group = "roller", labelKey = "terraLogic_workQualityRoller", fallbackLabel = "Rolling quality", yieldWeight = CATEGORY_BALANCE.roller.weight, maxYieldPenalty = CATEGORY_BALANCE.roller.maxPenalty, bit = 32},
    mulch         = {group = "mulch", labelKey = "terraLogic_workQualityMulch", fallbackLabel = "Mulching quality", yieldWeight = 0.025, maxYieldPenalty = 0.025, bit = 64},
    lime          = {group = "lime", labelKey = "terraLogic_workQualityLime", fallbackLabel = "Liming quality", yieldWeight = CATEGORY_BALANCE.lime.weight, maxYieldPenalty = CATEGORY_BALANCE.lime.maxPenalty, bit = 128}
}
TerraLogicQualityManager.COMPONENT_ORDER = {
    "soilPlow", "soilCultivate", "seed", "fertilizer", "lime", "herbicide", "roller", "mulch"
}
TerraLogicQualityManager.GROUP_ORDER = {
    "soil", "seed", "fertilizer", "lime", "herbicide", "roller", "mulch"
}
TerraLogicQualityManager.GROUP_DEFINITIONS = {
    soil = TerraLogicQualityManager.COMPONENTS.soilPlow,
    seed = TerraLogicQualityManager.COMPONENTS.seed,
    fertilizer = TerraLogicQualityManager.COMPONENTS.fertilizer,
    lime = TerraLogicQualityManager.COMPONENTS.lime,
    herbicide = TerraLogicQualityManager.COMPONENTS.herbicide,
    roller = TerraLogicQualityManager.COMPONENTS.roller,
    mulch = TerraLogicQualityManager.COMPONENTS.mulch
}
-- Live-only effects are never serialized into field chunks. Mower quality is
-- evaluated for the current cut and scales only the grass liters created by
-- that pass; the underlying mown area remains Vanilla/PF-owned.
TerraLogicQualityManager.LIVE_COMPONENTS = {
    mower = {
        group = "mower",
        labelKey = "terraLogic_workQualityMower",
        fallbackLabel = "Mowing quality",
        yieldWeight = TerraLogicImplementProfiles.YIELD_QUALITY.mower.weight,
        maxYieldPenalty = TerraLogicImplementProfiles.YIELD_QUALITY.mower.maxPenalty
    }
}

-- Components whose underlying Vanilla result is destroyed by a later pass.
-- Fertilizer, lime and mulch deliberately survive tillage: Vanilla keeps
-- their agronomic benefit. Soil work destroys the crop/seedbed, rolling and
-- crop-specific weed control. A successful new seed pass likewise starts a
-- new crop and invalidates rolling and weed control from the previous crop.
TerraLogicQualityManager.OVERWRITTEN_COMPONENTS = {
    soilPlow = {"seed", "roller", "herbicide"},
    soilCultivate = {"seed", "roller", "herbicide"},
    seed = {"roller", "herbicide"}
}
TerraLogicQualityManager.BONUS_GROUPS = {
    -- Vanilla fertilizer has two successful 22.5 percentage-point stages.
    -- One WorkArea change represents one newly earned stage.
    fertilizer = {bonus = 0.225, label = "fertilizer stage", rateLimitedRange = 0.80},
    lime = {bonus = 0.15, label = "lime", rateLimitedRange = 0.80},
    herbicide = {bonus = 0.20, label = "weed control", rateLimitedRange = 0.80},
    roller = {bonus = 0.025, label = "rolling"},
    mulch = {bonus = 0.025, label = "mulching"}
}
TerraLogicQualityManager.chunks = {}
TerraLogicQualityManager.dirty = false
TerraLogicQualityManager.clientCells = {}
TerraLogicQualityManager.pendingHarvestClears = {}
TerraLogicQualityManager.pendingMowerClears = {}
TerraLogicQualityManager.partialHarvestCells = {}

-- Text and compact-storage helpers -----------------------------------------

-- Clears counters used only by the harvest debug screen.
function TerraLogicQualityManager:resetHarvestDiagnostics()
    self.harvestDiagnosticCount = 0
    self.harvestClearDiagnosticCount = 0
    self.harvestDiagnosticState = {}
end

function TerraLogicQualityManager:getText(key, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local translated = g_i18n:getText(key)
        if translated ~= nil and translated ~= "" and translated ~= key then
            return translated
        end
    end
    return fallback or key
end

function TerraLogicQualityManager:getComponentLabel(name)
    local definition = self.COMPONENTS[name] or self.GROUP_DEFINITIONS[name]
        or self.LIVE_COMPONENTS[name]
    if definition == nil then return tostring(name or "") end
    return self:getText(definition.labelKey, definition.fallbackLabel)
end

local ZERO_DATA = string.rep(string.char(0), TerraLogicQualityManager.CHUNK_CELL_COUNT)
local PERFECT_DATA = string.rep(string.char(255), TerraLogicQualityManager.CHUNK_CELL_COUNT)
local BYTE_TO_HEX = {}
for value = 0, 255 do BYTE_TO_HEX[value] = string.format("%02X", value) end

local function getCellIndex(value)
    return math.floor(value / TerraLogicQualityManager.CELL_SIZE)
end

local function getChunkPosition(ix, iz)
    local chunkX = math.floor(ix / TerraLogicQualityManager.CHUNK_SIZE)
    local chunkZ = math.floor(iz / TerraLogicQualityManager.CHUNK_SIZE)
    local localX = ix - chunkX * TerraLogicQualityManager.CHUNK_SIZE
    local localZ = iz - chunkZ * TerraLogicQualityManager.CHUNK_SIZE
    return chunkX, chunkZ,
        tostring(chunkX) .. ":" .. tostring(chunkZ),
        localZ * TerraLogicQualityManager.CHUNK_SIZE + localX + 1
end

local function hasBit(mask, bit)
    return mask % (bit * 2) >= bit
end

local function addBit(mask, bit)
    return hasBit(mask, bit) and mask or mask + bit
end

local function removeBit(mask, bit)
    return hasBit(mask, bit) and mask - bit or mask
end

local function bytesToHex(data)
    local result = {}
    for index = 1, #data do
        result[index] = BYTE_TO_HEX[string.byte(data, index)]
    end
    return table.concat(result)
end

local function hexToBytes(value, defaultByte)
    if value == nil then
        return string.rep(string.char(defaultByte), TerraLogicQualityManager.CHUNK_CELL_COUNT)
    end
    local result = {}
    for index = 1, TerraLogicQualityManager.CHUNK_CELL_COUNT do
        local startIndex = index * 2 - 1
        local byte = tonumber(string.sub(value, startIndex, startIndex + 1), 16)
        result[index] = string.char(byte or defaultByte)
    end
    return table.concat(result)
end

local function mergeFormat5SoilLayers(
        statusData, cultivateHex, directHex, defaultByte, isQuality)
    local cultivateData = hexToBytes(cultivateHex, defaultByte)
    local directData = hexToBytes(directHex, defaultByte)
    local result = {}
    for offset = 1, TerraLogicQualityManager.CHUNK_CELL_COUNT do
        local mask = string.byte(statusData, offset) or 0
        local hasCultivate, hasDirect = hasBit(mask, 2), hasBit(mask, 64)
        local first = string.byte(cultivateData, offset) or defaultByte
        local second = string.byte(directData, offset) or defaultByte
        local value = defaultByte
        if hasCultivate and hasDirect then
            if isQuality then
                local q1 = first == 255 and 1 or first / 254
                local q2 = second == 255 and 1 or second / 254
                local quality = (q1 + q2) * 0.5
                value = quality >= 0.9995 and 255
                    or math.clamp(math.floor(quality * 254 + 0.5), 0, 254)
            else
                value = math.clamp(math.floor((first + second) * 0.5 + 0.5), 0, 255)
            end
        elseif hasCultivate then
            value = first
        elseif hasDirect then
            value = second
        end
        result[offset] = string.char(value)
    end
    return table.concat(result)
end

local function newLayer(defaultByte, data)
    data = data or string.rep(string.char(defaultByte), TerraLogicQualityManager.CHUNK_CELL_COUNT)
    local nonDefaultCount = 0
    for index = 1, TerraLogicQualityManager.CHUNK_CELL_COUNT do
        if string.byte(data, index) ~= defaultByte then
            nonDefaultCount = nonDefaultCount + 1
        end
    end
    return {
        data = data,
        defaultByte = defaultByte,
        changes = {},
        changeCount = 0,
        nonDefaultCount = nonDefaultCount
    }
end

local function getLayerByte(layer, offset)
    local changed = layer.changes[offset]
    return changed ~= nil and changed or string.byte(layer.data, offset)
end

local function flushLayer(layer)
    if layer.changeCount == 0 then return end
    local bytes = {}
    for index = 1, TerraLogicQualityManager.CHUNK_CELL_COUNT do
        bytes[index] = string.char(layer.changes[index]
            or string.byte(layer.data, index)
            or layer.defaultByte)
    end
    layer.data = table.concat(bytes)
    layer.changes = {}
    layer.changeCount = 0
end

local function setLayerByte(layer, offset, value)
    local oldValue = getLayerByte(layer, offset)
    if oldValue == value then return false end
    if oldValue == layer.defaultByte and value ~= layer.defaultByte then
        layer.nonDefaultCount = layer.nonDefaultCount + 1
    elseif oldValue ~= layer.defaultByte and value == layer.defaultByte then
        layer.nonDefaultCount = layer.nonDefaultCount - 1
    end
    if layer.changes[offset] == nil then
        layer.changeCount = layer.changeCount + 1
    end
    layer.changes[offset] = value
    if layer.changeCount >= TerraLogicQualityManager.LAYER_FLUSH_THRESHOLD then
        flushLayer(layer)
    end
    return true
end

local function newChunk(chunkX, chunkZ, statusData)
    return {
        x = chunkX,
        z = chunkZ,
        status = newLayer(0, statusData or ZERO_DATA),
        qualities = {},
        penalties = {},
        counts = {}
    }
end

local function getAreaGeometry(workArea)
    if workArea == nil or workArea.start == nil or workArea.width == nil
        or workArea.height == nil then
        return nil
    end
    local sx, _, sz = getWorldTranslation(workArea.start)
    local wx, _, wz = getWorldTranslation(workArea.width)
    local hx, _, hz = getWorldTranslation(workArea.height)
    return sx, sz, wx - sx, wz - sz, hx - sx, hz - sz
end

local function appendCell(result, seen, x, z)
    local ix, iz = getCellIndex(x), getCellIndex(z)
    local cellKey = tostring(ix) .. ":" .. tostring(iz)
    if seen[cellKey] then return end
    local chunkX, chunkZ, chunkKey, offset = getChunkPosition(ix, iz)
    seen[cellKey] = true
    result[#result + 1] = {
        ix = ix, iz = iz, chunkX = chunkX, chunkZ = chunkZ,
        chunkKey = chunkKey, offset = offset
    }
end

-- Converts a work-area parallelogram into stable map-aligned quality cells.
function TerraLogicQualityManager:getTouchedCells(workArea, includeApplicationWidth)
    local sx, sz, widthX, widthZ, heightX, heightZ = getAreaGeometry(workArea)
    if sx == nil then return {} end
    local width = math.sqrt(widthX * widthX + widthZ * widthZ)
    local depth = math.sqrt(heightX * heightX + heightZ * heightZ)
    local columns = math.max(1, math.ceil(width / self.CELL_SIZE))
    local rows = math.max(1, math.ceil(depth / self.CELL_SIZE))
    local result, seen = {}, {}
    for column = 0, columns do
        local u = columns > 0 and column / columns or 0.5
        for row = 0, rows do
            local v = rows > 0 and row / rows or 0.5
            local x = sx + widthX * u + heightX * v
            local z = sz + widthZ * u + heightZ * v
            appendCell(result, seen, x, z)
        end
    end

    -- Centred broadcast spreaders describe their fan with the two outer
    -- nodes behind the start node. Sampling only the two start vectors can
    -- therefore miss the outer working width. Add the complete line between
    -- the outer nodes for application work areas. At 45 m this is only about
    -- twelve additional four-metre samples per processed area.
    if includeApplicationWidth then
        local wx, wz = sx + widthX, sz + widthZ
        local hx, hz = sx + heightX, sz + heightZ
        local pairs = {
            {sx, sz, wx, wz},
            {sx, sz, hx, hz},
            {wx, wz, hx, hz}
        }
        local widest, widestLength = nil, 0
        for _, pair in ipairs(pairs) do
            local dx, dz = pair[3] - pair[1], pair[4] - pair[2]
            local length = math.sqrt(dx * dx + dz * dz)
            if length > widestLength then
                widest, widestLength = pair, length
            end
        end
        if widest ~= nil and widestLength > 0.01 then
            local steps = math.max(1, math.ceil(widestLength / self.CELL_SIZE))
            for index = 0, steps do
                local t = index / steps
                appendCell(
                    result,
                    seen,
                    widest[1] + (widest[3] - widest[1]) * t,
                    widest[2] + (widest[4] - widest[2]) * t
                )
            end
        end
    end
    return result
end

-- Classifies arable land, field grass and natural meadow at a world position.
function TerraLogicQualityManager:getSurfaceTypeAtWorldPosition(x, z)
    local fruitTypeIndex = nil
    if FSDensityMapUtil ~= nil
        and FSDensityMapUtil.getFruitTypeIndexAtWorldPos ~= nil then
        fruitTypeIndex = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
    end
    local field = false
    if FSDensityMapUtil ~= nil
        and FSDensityMapUtil.getIsFieldAtWorldPos ~= nil then
        field = FSDensityMapUtil.getIsFieldAtWorldPos(x, z) == true
    else
        -- Compatibility fallback for maps that replace the standard helper.
        field = true
    end
    local isMeadow = fruitTypeIndex ~= nil and FruitType ~= nil
        and FruitType.MEADOW ~= nil and fruitTypeIndex == FruitType.MEADOW
    local isGrass = fruitTypeIndex ~= nil
        and FruitType ~= nil and FruitType.GRASS ~= nil
        and fruitTypeIndex == FruitType.GRASS
    -- A single density-map point can fall between grass blades and report no
    -- fruit even though the surrounding TerraLogic cell was successfully rolled.
    -- Confirm GRASS/MEADOW over a small footprint before rejecting the cell.
    if not isMeadow and not isGrass and FSDensityMapUtil ~= nil
        and FSDensityMapUtil.getFruitArea ~= nil and FruitType ~= nil then
        local halfSize = math.min(self.CELL_SIZE * 0.25, 1)
        local function hasFruitArea(fruitIndex)
            if fruitIndex == nil then return false end
            local ok, area = pcall(
                FSDensityMapUtil.getFruitArea,
                fruitIndex,
                x - halfSize, z - halfSize,
                x + halfSize, z - halfSize,
                x - halfSize, z + halfSize,
                true, true)
            return ok and (tonumber(area) or 0) > 0
        end
        isGrass = hasFruitArea(FruitType.GRASS)
        isMeadow = not isGrass and hasFruitArea(FruitType.MEADOW)
    end
    if isMeadow or isGrass then
        return field and "grassField" or "grass"
    end
    return field and "field" or "outside"
end

function TerraLogicQualityManager:isComponentAllowedAtCell(
        component, ix, iz, vehicle)
    local surface = self:getSurfaceTypeAtWorldPosition(
        (ix + 0.5) * self.CELL_SIZE,
        (iz + 0.5) * self.CELL_SIZE
    )
    if surface == "outside" or surface == "grass" then return false end

    local definition = self.COMPONENTS[component]
    local group = definition ~= nil and definition.group or component
    local rollerSpec = vehicle ~= nil and vehicle.spec_roller or nil
    if surface == "grassField" then
        if group == "fertilizer" then
            return true
        end
        -- Vanilla grass neither requires nor consumes lime. Precision Farming
        -- does model persistent pH depletion over several cuts, so only PF
        -- saves receive a grass-lime quality record.
        if group == "lime" then
            return TerraLogicMain ~= nil
                and TerraLogicMain.isPrecisionFarmingActive ~= nil
                and TerraLogicMain:isPrecisionFarmingActive()
        end
        -- Grass sown on a real field receives seed quality (and direct-drill
        -- soil preparation quality). They describe the persistent grass stand
        -- and therefore remain valid across regrowth until new tillage/reseeding
        -- overwrites them. Native changed-area checks still gate every write.
        if surface == "grassField"
            and (group == "seed" or group == "soil") then
            return true
        end
        -- Natural meadow was rejected above. Only a real grass field owns a
        -- persistent grass-roller ledger.
        return group == "roller"
            and (rollerSpec == nil or rollerSpec.isGrassRoller == true)
    end

    -- A grass-only roller must not leave soil-rolling quality on arable land.
    if group == "roller" and rollerSpec ~= nil
        and rollerSpec.isGrassRoller == true
        and rollerSpec.isSoilRoller ~= true then
        return false
    end
    return true
end

function TerraLogicQualityManager:getOrCreateChunk(chunkX, chunkZ, chunkKey)
    local chunk = self.chunks[chunkKey]
    if chunk == nil then
        chunk = newChunk(chunkX, chunkZ)
        self.chunks[chunkKey] = chunk
    end
    return chunk
end

function TerraLogicQualityManager:calculateYieldPenalty(
        quality, yieldWeight, maxYieldPenalty)
    local weight = math.max(tonumber(yieldWeight) or 0, 0)
    local maximum = math.clamp(tonumber(maxYieldPenalty) or 0, 0, 1)
    local workQuality = math.clamp(tonumber(quality) or 1, 0, 1)
    return math.min(weight * (1 - workQuality), maximum)
end

local function smoothStep01(value)
    value = math.clamp(tonumber(value) or 0, 0, 1)
    return value * value * (3 - 2 * value)
end

function TerraLogicQualityManager:getProtectedQualitySpeeds(realSpeed, shopSpeed)
    shopSpeed = math.max(tonumber(shopSpeed) or 0, 0.01)
    realSpeed = math.max(tonumber(realSpeed) or shopSpeed, 0.01)
    local shopToClass = shopSpeed / realSpeed
    if shopSpeed < realSpeed then
        realSpeed = TerraLogicImplementProfiles
            .getLowShopSafeSpeed(shopSpeed)
    elseif shopToClass < 1.05 or shopToClass > 1.40 then
        realSpeed = shopSpeed * 0.80
    end
    return math.min(realSpeed, shopSpeed), shopSpeed
end

-- Returns the common speed/economy terms. `hourlyTarget` is deliberately the
-- value shown by the balancing HUD: below 1 means that speed cannot pay for
-- itself through increased field throughput alone.
-- Quality and economy model -------------------------------------------------

-- Calculates quality, time saving and profitability from the active speed.
function TerraLogicQualityManager:getSpeedEconomyForSpeeds(
        realSpeed, shopSpeed, currentSpeed)
    local protectedReal, protectedShop = self:getProtectedQualitySpeeds(
        realSpeed, shopSpeed)
    local speed = math.max(tonumber(currentSpeed) or 0, 0)
    local quality
    if speed <= protectedReal then
        quality = self.QUALITY_AT_REAL_SPEED
    elseif speed <= protectedShop then
        local span = math.max(protectedShop - protectedReal, 0.01)
        local t = (speed - protectedReal) / span
        quality = self.QUALITY_AT_REAL_SPEED
            - (self.QUALITY_AT_REAL_SPEED - self.QUALITY_AT_SHOP_SPEED)
                * smoothStep01(t)
    else
        quality = self.QUALITY_AT_SHOP_SPEED
    end

    local shopRatio = speed / protectedShop
    local overspeed = math.max(shopRatio - 1, 0)
    local hourlyTarget = shopRatio > 1
        and math.exp(-self.ECONOMY_CURVE_K * overspeed * overspeed)
        or shopRatio
    local areaRetention = shopRatio > 0
        and hourlyTarget / shopRatio or 1
    return {
        speed = speed,
        realSpeed = protectedReal,
        shopSpeed = protectedShop,
        shopRatio = shopRatio,
        overspeed = overspeed,
        timeSaved = shopRatio > 1 and 1 - 1 / shopRatio or 0,
        preShopQuality = math.clamp(quality, 0, 1),
        hourlyTarget = math.clamp(hourlyTarget, 0, 1),
        areaRetention = math.clamp(areaRetention, 0, 1)
    }
end

function TerraLogicQualityManager:getSpeedEconomy(vehicle, currentSpeed)
    local spec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    return self:getSpeedEconomyForSpeeds(
        spec ~= nil and spec.optimalSpeed or nil,
        spec ~= nil and spec.ratedSpeed or nil,
        currentSpeed)
end

function TerraLogicQualityManager:applyProductiveEconomy(economy, maximumPenalty)
    local cap = math.clamp(tonumber(maximumPenalty) or 0, 0, 1)
    local shopAreaFactor = 1 - cap * (1 - self.QUALITY_AT_SHOP_SPEED)
    local areaFactor, quality
    if economy.shopRatio <= 1 then
        quality = economy.preShopQuality
        areaFactor = 1 - cap * (1 - quality)
    else
        areaFactor = math.max(1 - cap,
            shopAreaFactor * economy.areaRetention)
        quality = cap > 0 and 1 - (1 - areaFactor) / cap or 1
    end
    quality = math.clamp(quality, 0, 1)
    local penalty = math.clamp(1 - areaFactor, 0, cap)
    return quality, penalty, areaFactor, shopAreaFactor
end

-- Preserves the existing first-order quality loss at shop speed, then bends
-- that loss smoothly towards a class-specific lower bound. `additionalLoss`
-- is intentionally unbounded, so the curve never reaches a hard cap at a
-- finite speed but converges on the minimum at increasingly absurd speeds.
function TerraLogicQualityManager:approachMinimumQuality(
        minimumQuality, additionalLoss)
    local minimum = math.clamp(tonumber(minimumQuality) or 0, 0, 0.99)
    local shopQuality = self.QUALITY_AT_SHOP_SPEED
    local remainingRange = math.max(shopQuality - minimum, 0.0001)
    local loss = math.max(tonumber(additionalLoss) or 0, 0)
    return minimum + remainingRange * math.exp(-loss / remainingRange)
end

-- Converts the shared speed curve into one of the two gameplay effects.
-- Productive work may reduce the whole yield down to its category cap. Bonus
-- work can only remove the positive contribution passed in `bonusOverride`.
function TerraLogicQualityManager:getWorkQualityModel(
        vehicle, currentSpeed, component, bonusOverride,
        dropoutReductionAllowed)
    local definition = self.COMPONENTS[component]
        or self.GROUP_DEFINITIONS[component]
        or self.LIVE_COMPONENTS[component]
    local group = definition ~= nil and (definition.group or component)
        or component
    local economy = self:getSpeedEconomy(vehicle, currentSpeed)
    local bonusDefinition = self.BONUS_GROUPS[group]
    local quality, penalty, areaFactor, shopAreaFactor
    local vehicleSpec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    local classKey = vehicleSpec ~= nil
        and vehicleSpec.implementClassKey or nil
    local minimumQuality = TerraLogicImplementProfiles
        .getMinimumWorkQuality(classKey, component)
    local isDirectDrillSoilPass = component == "soilCultivate"
        and vehicleSpec ~= nil
        and vehicleSpec.implementClassKey == "directDrill"
    local hasMatchingPhysicalDropouts =
        TerraLogicImplementProfiles.WORK_QUALITY_DROPOUT_COMPONENTS[
            component
        ] == true or isDirectDrillSoilPass
    local dropoutOverspeedShare = 1
    if economy.shopRatio > 1 and dropoutReductionAllowed ~= false
        and TerraLogicSettings ~= nil
        and TerraLogicSettings:getPhysicalDropoutsEnabled()
        and hasMatchingPhysicalDropouts then
        dropoutOverspeedShare = math.clamp(
            tonumber(TerraLogicImplementProfiles
                .WORK_QUALITY_DROPOUT_OVERSPEED_SHARE) or 0.30,
            0,
            1
        )
    end

    if bonusDefinition ~= nil then
        local bonus = math.max(tonumber(bonusOverride)
            or bonusDefinition.bonus or 0, 0)
        local totalAtShop = 1 + bonus * self.QUALITY_AT_SHOP_SPEED
        local totalNow
        if economy.shopRatio <= 1 then
            quality = economy.preShopQuality
            totalNow = 1 + bonus * quality
        elseif tonumber(bonusDefinition.rateLimitedRange) ~= nil
            and minimumQuality ~= nil then
            -- Application equipment has a limited mass/volume flow. Slightly
            -- exceeding shop speed therefore under-applies gently. The
            -- squared demand is flat at shop speed, while the exponential
            -- envelope prevents an abrupt total loss at high overspeed.
            local range = math.max(
                tonumber(bonusDefinition.rateLimitedRange) or 0.80, 0.01)
            local t = economy.overspeed / range
            local additionalLoss = self.QUALITY_AT_SHOP_SPEED
                * 2 * t * t * dropoutOverspeedShare
            quality = self:approachMinimumQuality(
                minimumQuality, additionalLoss)
            totalNow = 1 + bonus * quality
            economy.rateLimitedCurve = true
            economy.rateLimitedRange = range
        elseif (tonumber(bonusDefinition.bonus) or 0) <= 0.05
            and minimumQuality ~= nil then
            -- A 2.5% roller/mulcher bonus is smaller than almost every useful
            -- overspeed time saving. Strict hourly break-even would therefore
            -- collapse quality to zero almost immediately. Keep these tiny
            -- optional bonuses readable and smooth; wear/impacts still punish
            -- speed and the balancing HUD may honestly report it as profitable.
            local additionalLoss = 4.05
                * economy.overspeed * economy.overspeed
            quality = self:approachMinimumQuality(
                minimumQuality, additionalLoss)
            totalNow = 1 + bonus * quality
            economy.microBonusCurve = true
        else
            totalNow = math.max(1, totalAtShop * economy.areaRetention)
            quality = bonus > 0 and (totalNow - 1) / bonus or 1
        end
        quality = math.clamp(quality, 0, 1)
        if dropoutOverspeedShare < 1 and minimumQuality == nil then
            quality = math.clamp(
                self.QUALITY_AT_SHOP_SPEED
                    - (self.QUALITY_AT_SHOP_SPEED - quality)
                        * dropoutOverspeedShare,
                0,
                1
            )
            totalNow = 1 + bonus * quality
        end
        areaFactor = totalNow / math.max(1 + bonus, 0.0001)
        shopAreaFactor = totalAtShop / math.max(1 + bonus, 0.0001)
        penalty = math.clamp(1 - areaFactor, 0, 1)
        economy.effectType = "bonus"
        economy.bonus = bonus
        economy.bonusFloorReached = minimumQuality ~= nil
            and quality <= minimumQuality + 0.00001
            or totalNow <= 1.00001
    else
        local cap = math.clamp(definition ~= nil
            and definition.maxYieldPenalty or 0, 0, 1)
        if economy.shopRatio > 1 and minimumQuality ~= nil and cap > 0 then
            shopAreaFactor = 1 - cap
                * (1 - self.QUALITY_AT_SHOP_SPEED)
            -- -log(retention) follows the old economy curve at mild overspeed
            -- but keeps growing after the former hard yield cap was reached.
            local retention = math.max(economy.areaRetention, 0.000000001)
            local additionalLoss = shopAreaFactor / cap
                * (-math.log(retention)) * dropoutOverspeedShare
            quality = self:approachMinimumQuality(
                minimumQuality, additionalLoss)
            areaFactor = 1 - cap * (1 - quality)
            penalty = math.clamp(1 - areaFactor, 0, cap)
            economy.minimumEnvelopeCurve = true
        else
            quality, penalty, areaFactor, shopAreaFactor =
                self:applyProductiveEconomy(economy, cap)
        end
        if dropoutOverspeedShare < 1 and minimumQuality == nil then
            areaFactor = math.clamp(
                shopAreaFactor
                    - (shopAreaFactor - areaFactor)
                        * dropoutOverspeedShare,
                1 - cap,
                1
            )
            quality = cap > 0
                and 1 - (1 - areaFactor) / cap or 1
            quality = math.clamp(quality, 0, 1)
            penalty = math.clamp(1 - areaFactor, 0, cap)
        end
        economy.effectType = "wholeYield"
        economy.maximumPenalty = cap
        economy.penaltyFloorReached = minimumQuality ~= nil
            and quality <= minimumQuality + 0.00001
            or areaFactor <= 1 - cap + 0.00001
    end

    economy.quality = quality
    economy.minimumQuality = minimumQuality
    economy.dropoutWorkQualityOverspeedShare = dropoutOverspeedShare
    economy.yieldPenalty = penalty
    economy.areaFactor = areaFactor
    economy.shopAreaFactor = shopAreaFactor
    economy.profitabilityIndex = economy.shopRatio
        * areaFactor / math.max(shopAreaFactor, 0.0001)
    return quality, penalty, economy
end

-- Quality ledger ------------------------------------------------------------

-- Writes one successful operation into a cell while preserving group history.
function TerraLogicQualityManager:setCellComponent(
        ix, iz, component, quality, yieldWeight, maxYieldPenalty,
        explicitHarvestPenalty, aggregateVanillaFertilizer)
    local definition = self.COMPONENTS[component]
    if definition == nil then return false end
    local chunkX, chunkZ, chunkKey, offset = getChunkPosition(ix, iz)
    local chunk = self:getOrCreateChunk(chunkX, chunkZ, chunkKey)
    local oldMask = getLayerByte(chunk.status, offset)
    local changed = setLayerByte(chunk.status, offset, addBit(oldMask, definition.bit))

    quality = math.clamp(tonumber(quality) or 1, 0, 1)
    if aggregateVanillaFertilizer == true and component == "fertilizer" then
        self.applicationCellStamps = self.applicationCellStamps or {}
        local stampKey = chunkKey .. ":" .. tostring(offset) .. ":fertilizer"
        local now = g_currentMission ~= nil and g_currentMission.time or 0
        local lastStamp = self.applicationCellStamps[stampKey]
        local isNewStage = lastStamp == nil or now - lastStamp >= 30000
        self.applicationCellStamps[stampKey] = now
        local countLayer = chunk.counts[component]
        local oldCount = countLayer ~= nil
            and getLayerByte(countLayer, offset) or 0
        local oldLayer = chunk.qualities[component]
        local oldEncoded = oldLayer ~= nil
            and getLayerByte(oldLayer, offset) or 255
        local oldQuality = oldEncoded == 255 and 1 or oldEncoded / 254
        local count = oldCount
        if isNewStage and oldCount < 2 then count = oldCount + 1 end
        if count <= 0 then count = 1 end
        if isNewStage and count > oldCount then
            quality = (oldQuality * oldCount + quality) / count
        elseif oldCount > 0 then
            -- Work areas overlap between frames. A cell which already belongs
            -- to this fertilizer stage must retain its accumulated value; it
            -- is not a new application merely because a neighbouring pixel
            -- changed during the same call.
            quality = oldQuality
        end
        if countLayer == nil then
            countLayer = newLayer(0, ZERO_DATA)
            chunk.counts[component] = countLayer
        end
        if setLayerByte(countLayer, offset, count) then changed = true end
        local totalBonus = 0.225 * math.min(count, 2)
        explicitHarvestPenalty = totalBonus * (1 - quality)
            / math.max(1 + totalBonus, 0.0001)
    end
    local encoded = quality >= 0.9995 and 255
        or math.clamp(math.floor(quality * 254 + 0.5), 0, 254)
    local layer = chunk.qualities[component]
    if encoded < 255 and layer == nil then
        layer = newLayer(255, PERFECT_DATA)
        chunk.qualities[component] = layer
    end
    if layer ~= nil and setLayerByte(layer, offset, encoded) then
        changed = true
        if layer.nonDefaultCount == 0 then
            chunk.qualities[component] = nil
        end
    end

    local penalty = explicitHarvestPenalty ~= nil
        and math.clamp(tonumber(explicitHarvestPenalty) or 0, 0, 1)
        or self:calculateYieldPenalty(
            quality,
            yieldWeight ~= nil and yieldWeight or definition.yieldWeight,
            maxYieldPenalty ~= nil and maxYieldPenalty
                or definition.maxYieldPenalty
        )
    local penaltyEncoded = math.clamp(
        math.floor(penalty * 255 + 0.5),
        0,
        255
    )
    local penaltyLayer = chunk.penalties[component]
    if penaltyEncoded > 0 and penaltyLayer == nil then
        penaltyLayer = newLayer(0, ZERO_DATA)
        chunk.penalties[component] = penaltyLayer
    end
    if penaltyLayer ~= nil
        and setLayerByte(penaltyLayer, offset, penaltyEncoded) then
        changed = true
        if penaltyLayer.nonDefaultCount == 0 then
            chunk.penalties[component] = nil
        end
    end
    return changed
end

function TerraLogicQualityManager:getPackedCell(ix, iz)
    local _, _, chunkKey, offset = getChunkPosition(ix, iz)
    local chunk = self.chunks[chunkKey]
    if chunk == nil then return nil end
    local mask = getLayerByte(chunk.status, offset)
    if mask == 0 then return nil end
    local cell = {mask = mask, values = {}, penalties = {}, applicationCounts = {}}
    for _, name in ipairs(self.COMPONENT_ORDER) do
        local definition = self.COMPONENTS[name]
        if hasBit(mask, definition.bit) then
            local layer = chunk.qualities[name]
            local encoded = layer ~= nil and getLayerByte(layer, offset) or 255
            if encoded < 255 then cell.values[name] = encoded / 254 end
            local penaltyLayer = chunk.penalties[name]
            local penaltyEncoded = penaltyLayer ~= nil
                and getLayerByte(penaltyLayer, offset) or 0
            if penaltyEncoded > 0 then
                cell.penalties[name] = penaltyEncoded / 255
            end
            local countLayer = chunk.counts[name]
            if countLayer ~= nil then
                cell.applicationCounts[name] = math.max(
                    getLayerByte(countLayer, offset), 1)
            end
        end
    end
    return cell
end

-- Vanilla's field-info query covers a 5x5 metre area rather than a single
-- point. Aggregate every four-metre TerraLogic cell intersecting the same footprint
-- so that the displayed quality cannot disappear at an internal cell edge.
function TerraLogicQualityManager:getPackedSummaryInArea(x, z, radius)
    radius = math.max(tonumber(radius) or 0, 0)
    local minIx, maxIx = getCellIndex(x - radius), getCellIndex(x + radius)
    local minIz, maxIz = getCellIndex(z - radius), getCellIndex(z + radius)
    local mask, sums, penaltySums, applicationCountSums, counts =
        0, {}, {}, {}, {}
    for ix = minIx, maxIx do
        for iz = minIz, maxIz do
            local cell = self:getPackedCell(ix, iz)
            if cell ~= nil then
                for _, name in ipairs(self.COMPONENT_ORDER) do
                    local definition = self.COMPONENTS[name]
                    if hasBit(cell.mask or 0, definition.bit) then
                        mask = addBit(mask, definition.bit)
                        sums[name] = (sums[name] or 0) + (cell.values[name] or 1)
                        penaltySums[name] = (penaltySums[name] or 0)
                            + ((cell.penalties or {})[name] or 0)
                        applicationCountSums[name] =
                            (applicationCountSums[name] or 0)
                            + ((cell.applicationCounts or {})[name] or 1)
                        counts[name] = (counts[name] or 0) + 1
                    end
                end
            end
        end
    end
    if mask == 0 then return nil end
    local result = {mask = mask, values = {}, penalties = {}, applicationCounts = {}}
    for _, name in ipairs(self.COMPONENT_ORDER) do
        if counts[name] ~= nil and counts[name] > 0 then
            local quality = sums[name] / counts[name]
            if quality < 0.9995 then result.values[name] = quality end
            local penalty = (penaltySums[name] or 0) / counts[name]
            if penalty > 0 then result.penalties[name] = penalty end
            result.applicationCounts[name] = math.max(math.floor(
                (applicationCountSums[name] or counts[name]) / counts[name]
                    + 0.5), 1)
        end
    end
    return result
end

function TerraLogicQualityManager:clearCell(position)
    local chunk = self.chunks[position.chunkKey]
    if chunk == nil or getLayerByte(chunk.status, position.offset) == 0 then
        return false
    end
    setLayerByte(chunk.status, position.offset, 0)
    for _, name in ipairs(self.COMPONENT_ORDER) do
        local layer = chunk.qualities[name]
        if layer ~= nil then
            setLayerByte(layer, position.offset, 255)
            if layer.nonDefaultCount == 0 then chunk.qualities[name] = nil end
        end
        local penaltyLayer = chunk.penalties[name]
        if penaltyLayer ~= nil then
            setLayerByte(penaltyLayer, position.offset, 0)
            if penaltyLayer.nonDefaultCount == 0 then
                chunk.penalties[name] = nil
            end
        end
        local countLayer = chunk.counts[name]
        if countLayer ~= nil then
            setLayerByte(countLayer, position.offset, 0)
            if countLayer.nonDefaultCount == 0 then chunk.counts[name] = nil end
        end
    end
    if chunk.status.nonDefaultCount == 0 then
        self.chunks[position.chunkKey] = nil
    end
    return true
end

function TerraLogicQualityManager:clearCellComponent(position, component)
    local definition = self.COMPONENTS[component]
    local chunk = definition ~= nil and self.chunks[position.chunkKey] or nil
    if chunk == nil then return false end
    local oldMask = getLayerByte(chunk.status, position.offset)
    if not hasBit(oldMask, definition.bit) then return false end
    setLayerByte(chunk.status, position.offset, removeBit(oldMask, definition.bit))
    local layer = chunk.qualities[component]
    if layer ~= nil then
        setLayerByte(layer, position.offset, 255)
        if layer.nonDefaultCount == 0 then chunk.qualities[component] = nil end
    end
    local penaltyLayer = chunk.penalties[component]
    if penaltyLayer ~= nil then
        setLayerByte(penaltyLayer, position.offset, 0)
        if penaltyLayer.nonDefaultCount == 0 then
            chunk.penalties[component] = nil
        end
    end
    local countLayer = chunk.counts[component]
    if countLayer ~= nil then
        setLayerByte(countLayer, position.offset, 0)
        if countLayer.nonDefaultCount == 0 then chunk.counts[component] = nil end
    end
    if chunk.status.nonDefaultCount == 0 then
        self.chunks[position.chunkKey] = nil
    end
    return true
end

-- Persistent establishment defects gradually normalize over repeated crop
-- cycles. A 50 percent recovery share produces 50 -> 75 -> 87.5 -> 93.75.
-- The matching yield penalty follows the same decay. The component bit stays
-- present so field info can continue showing the recovered quality.
-- Harvest lifecycle ---------------------------------------------------------

-- Recovers persistent plough/grass quality once after a completed harvest.
function TerraLogicQualityManager:recoverPersistentQualityAfterHarvest(
        position, component, recoveryShare)
    local definition = self.COMPONENTS[component]
    if definition == nil then return false end
    local chunk = self.chunks[position.chunkKey]
    if chunk == nil then return false end
    local mask = getLayerByte(chunk.status, position.offset)
    if not hasBit(mask, definition.bit) then return false end

    local changed = false
    recoveryShare = math.clamp(tonumber(recoveryShare) or 0.5, 0, 1)
    local qualityLayer = chunk.qualities[component]
    local encoded = qualityLayer ~= nil
        and getLayerByte(qualityLayer, position.offset) or 255
    if encoded < 255 then
        local quality = encoded / 254
        local recovered = quality + (1 - quality) * recoveryShare
        local recoveredEncoded = recovered >= 0.9995 and 255
            or math.clamp(math.floor(recovered * 254 + 0.5), 0, 254)
        if setLayerByte(qualityLayer, position.offset, recoveredEncoded) then
            changed = true
        end
        if qualityLayer.nonDefaultCount == 0 then
            chunk.qualities[component] = nil
        end
    end

    local penaltyLayer = chunk.penalties[component]
    if penaltyLayer ~= nil then
        local oldPenalty = getLayerByte(penaltyLayer, position.offset)
        local recoveredPenalty = math.floor(
            oldPenalty * (1 - recoveryShare) + 0.5)
        if setLayerByte(penaltyLayer, position.offset, recoveredPenalty) then
            changed = true
        end
        if penaltyLayer.nonDefaultCount == 0 then
            chunk.penalties[component] = nil
        end
    end
    return changed
end

function TerraLogicQualityManager:recoverPlowQualityAfterHarvest(position)
    return self:recoverPersistentQualityAfterHarvest(
        position, "soilPlow", 0.5)
end

function TerraLogicQualityManager:advanceCellAfterHarvest(position)
    local changed = self:recoverPlowQualityAfterHarvest(position)
    for _, component in ipairs(self.COMPONENT_ORDER) do
        if component ~= "soilPlow" then
            changed = self:clearCellComponent(position, component) or changed
        end
    end
    return changed
end

-- Grass is a perennial crop in FS25. Cutting consumes only work that belongs
-- to this growth/cut cycle. Establishment quality (soil + seed) remains until
-- the player actually tills or reseeds the stand. PF lime also remains because
-- PF consumes pH gradually over several harvests; Vanilla grass ignores lime.
function TerraLogicQualityManager:clearAfterMowerPass(
        position, wasGrass, precisionFarmingActive)
    if not wasGrass then
        return self:advanceCellAfterHarvest(position)
    end

    local changed = self:recoverPlowQualityAfterHarvest(position)
    -- A perennial grass stand closes poor sowing gaps over repeated regrowth.
    -- Annual crops use advanceCellAfterHarvest() and still discard seed
    -- quality completely after their one harvest.
    changed = self:recoverPersistentQualityAfterHarvest(
        position, "seed", 0.5) or changed
    -- Shallow cultivation belongs to the harvested surface cycle and does not
    -- persist like a deep plowing defect. Grass establishment/seed remains
    -- valid for the perennial stand until the player tills or reseeds it.
    for _, component in ipairs({
            "soilCultivate", "fertilizer", "roller", "herbicide", "mulch"
        }) do
        changed = self:clearCellComponent(position, component) or changed
    end
    if not precisionFarmingActive then
        -- Also migrates legacy Vanilla-grass cells that could store lime before
        -- the lifecycle distinction was introduced.
        changed = self:clearCellComponent(position, "lime") or changed
    end
    return changed
end

function TerraLogicQualityManager:markPartialHarvest(
        position, domain, fruitTypeIndex)
    if position == nil or domain == nil then return false end
    local key = tostring(position.ix) .. ":" .. tostring(position.iz)
        .. ":" .. tostring(domain)
    local old = self.partialHarvestCells[key]
    local validFruitType = fruitTypeIndex ~= nil
        and (FruitType == nil or fruitTypeIndex ~= FruitType.UNKNOWN)
    local marker = {
        ix = position.ix,
        iz = position.iz,
        domain = domain,
        fruitTypeIndex = validFruitType and fruitTypeIndex
            or (old ~= nil and old.fruitTypeIndex or nil)
    }
    local changed = old == nil or old.domain ~= marker.domain
        or old.fruitTypeIndex ~= marker.fruitTypeIndex
    self.partialHarvestCells[key] = marker
    if changed then self.dirty = true end
    return changed
end

function TerraLogicQualityManager:completePartialHarvest(
        position, expectedDomain, precisionFarmingActive)
    if position == nil or expectedDomain == nil then return false end
    local key = tostring(position.ix) .. ":" .. tostring(position.iz)
        .. ":" .. tostring(expectedDomain)
    local marker = self.partialHarvestCells[key]
    if marker == nil then return false end
    self.partialHarvestCells[key] = nil
    local changed
    if marker.domain == "fieldGrass" then
        changed = self:clearAfterMowerPass(
            position, true, precisionFarmingActive == true)
    else
        changed = self:advanceCellAfterHarvest(position)
    end
    self.dirty = true
    return true
end

function TerraLogicQualityManager:completePartialHarvestBeforeNewWork(position)
    local surface = self:getSurfaceTypeAtWorldPosition(
        (position.ix + 0.5) * self.CELL_SIZE,
        (position.iz + 0.5) * self.CELL_SIZE)
    local cellKey = tostring(position.ix) .. ":" .. tostring(position.iz)
    local arableMarker = self.partialHarvestCells[cellKey .. ":arable"]
    local grassMarker = self.partialHarvestCells[cellKey .. ":fieldGrass"]
    local domain
    if surface == "grassField" then
        domain = "fieldGrass"
    elseif arableMarker ~= nil or grassMarker == nil then
        domain = "arable"
    else
        -- Tillage may already have converted field grass back to ordinary
        -- field ground before this successful-work callback runs.
        domain = "fieldGrass"
    end
    local pfActive = TerraLogicMain ~= nil
        and TerraLogicMain.isPrecisionFarmingActive ~= nil
        and TerraLogicMain:isPrecisionFarmingActive()
    return self:completePartialHarvest(position, domain, pfActive)
end

function TerraLogicQualityManager:scheduleMowerClear(
        mower, positions, domain, fruitTypeIndex, precisionFarmingActive)
    if mower == nil or positions == nil then return end
    local now = g_currentMission ~= nil and g_currentMission.time or 0
    for _, position in ipairs(positions) do
        -- Key globally by fixed cell and domain, not by vehicle. Separate
        -- front/rear or butterfly mower objects therefore share one harvest
        -- completion for the same perennial cell.
        local key = tostring(position.ix) .. ":" .. tostring(position.iz)
            .. ":" .. tostring(domain)
        self:markPartialHarvest(position, domain, fruitTypeIndex)
        local entry = self.pendingMowerClears[key]
        if entry == nil then
            self.pendingMowerClears[key] = {
                position = position,
                domain = domain,
                fruitTypeIndex = fruitTypeIndex,
                lastTouchedAt = now,
                precisionFarmingActive = precisionFarmingActive == true
            }
        else
            entry.domain = domain or entry.domain
            entry.fruitTypeIndex = fruitTypeIndex or entry.fruitTypeIndex
            entry.lastTouchedAt = now
            entry.precisionFarmingActive = precisionFarmingActive == true
        end
    end
end

function TerraLogicQualityManager:flushPendingMowerClears()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local now = g_currentMission.time or 0
    local changed = false
    -- Settle each global cell independently. This lets every section/frame and
    -- every attached mower read the same pre-cut quality before one shared
    -- perennial recovery is applied.
    for key, entry in pairs(self.pendingMowerClears) do
        if now - (entry.lastTouchedAt or 0)
                >= self.MOWER_CELL_SETTLE_TIME_MS then
            entry.position.fruitTypeIndex = entry.fruitTypeIndex
            entry.position.useMinForageState = true
            local remaining, queryKnown =
                self:cellHasRemainingHarvestFruit(entry.position)
            if queryKnown and not remaining then
                changed = self:completePartialHarvest(
                    entry.position, entry.domain,
                    entry.precisionFarmingActive) or changed
            end
            self.pendingMowerClears[key] = nil
        end
    end
    self.dirty = self.dirty or changed
end

function TerraLogicQualityManager:clearOverwrittenComponents(
        position, newComponent)
    local components = self.OVERWRITTEN_COMPONENTS[newComponent]
    if components == nil then return false end
    local changed = false
    for _, component in ipairs(components) do
        changed = self:clearCellComponent(position, component) or changed
    end
    return changed
end

-- Invalidates crop-cycle components where an unintended mechanical pass has
-- genuinely destroyed plants, without crediting that accident as a successful
-- soil-quality operation. This deliberately reuses the normal contributor and
-- partial-harvest lifecycle rules instead of editing quality layers directly.
function TerraLogicQualityManager:invalidateSoilDamageWorkArea(
        workArea, vehicle)
    if g_currentMission == nil or not g_currentMission:getIsServer()
        or workArea == nil then
        return 0, false
    end
    local changed, acceptedCells = false, 0
    for _, position in ipairs(self:getTouchedCells(workArea, false)) do
        if self:isComponentAllowedAtCell(
                "soilCultivate", position.ix, position.iz, vehicle) then
            acceptedCells = acceptedCells + 1
            changed = self:completePartialHarvestBeforeNewWork(position)
                or changed
            changed = self:clearOverwrittenComponents(
                position, "soilCultivate") or changed
        end
    end
    if changed then self.dirty = true end
    return acceptedCells, changed
end

function TerraLogicQualityManager:beginStoredCellPrune()
    self.pruneChunkKeys = {}
    for chunkKey in pairs(self.chunks) do
        self.pruneChunkKeys[#self.pruneChunkKeys + 1] = chunkKey
    end
    self.pruneChunkIndex = 1
    self.pruneOffset = 1
    self.pruneRemoved = 0
end

function TerraLogicQualityManager:processStoredCellPrune(maxCells, maxOffsets)
    if self.pruneChunkKeys == nil then return end
    maxCells = math.max(tonumber(maxCells) or 64, 1)
    maxOffsets = math.max(tonumber(maxOffsets) or 2048, maxCells)
    local checkedCells, checkedOffsets = 0, 0
    while checkedCells < maxCells and checkedOffsets < maxOffsets do
        local chunkKey = self.pruneChunkKeys[self.pruneChunkIndex]
        if chunkKey == nil then
            if self.pruneRemoved > 0 then
                self.dirty = true
                TerraLogicLogging.debug(
                    "[FS25_TerraLogic] Removed %d invalid saved work-quality entries outside compatible surfaces",
                    self.pruneRemoved
                )
            end
            self.pruneChunkKeys = nil
            return
        end
        local chunk = self.chunks[chunkKey]
        if chunk == nil or self.pruneOffset > self.CHUNK_CELL_COUNT then
            self.pruneChunkIndex = self.pruneChunkIndex + 1
            self.pruneOffset = 1
        else
            local offset = self.pruneOffset
            self.pruneOffset = self.pruneOffset + 1
            checkedOffsets = checkedOffsets + 1
            local mask = getLayerByte(chunk.status, offset)
            if mask ~= 0 then
                checkedCells = checkedCells + 1
                local zeroOffset = offset - 1
                local position = {
                    ix = chunk.x * self.CHUNK_SIZE
                        + zeroOffset % self.CHUNK_SIZE,
                    iz = chunk.z * self.CHUNK_SIZE
                        + math.floor(zeroOffset / self.CHUNK_SIZE),
                    chunkKey = chunkKey,
                    offset = offset
                }
                for _, component in ipairs(self.COMPONENT_ORDER) do
                    local definition = self.COMPONENTS[component]
                    if hasBit(mask, definition.bit)
                        and not self:isComponentAllowedAtCell(
                            component, position.ix, position.iz, nil) then
                        if self:clearCellComponent(position, component) then
                            self.pruneRemoved = self.pruneRemoved + 1
                        end
                    end
                end
            end
        end
    end
end

function TerraLogicQualityManager:scheduleHarvestClear(
        cutter, positions, fruitTypeIndex, useMinForageState)
    if cutter == nil or positions == nil then return 0 end
    local pending = self.pendingHarvestClears[cutter]
    if pending == nil then
        pending = {}
        self.pendingHarvestClears[cutter] = pending
    end
    local added = 0
    for _, position in ipairs(positions) do
        local key = tostring(position.ix) .. ":" .. tostring(position.iz)
        local previous = pending[key]
        if previous == nil then added = added + 1 end
        local validFruitType = fruitTypeIndex ~= nil
            and (FruitType == nil or fruitTypeIndex ~= FruitType.UNKNOWN)
        position.fruitTypeIndex = validFruitType and fruitTypeIndex
            or (previous ~= nil and previous.fruitTypeIndex or nil)
        if validFruitType then
            position.useMinForageState = useMinForageState == true
        else
            position.useMinForageState = previous ~= nil
                and previous.useMinForageState == true
        end
        pending[key] = position
    end
    return added
end

function TerraLogicQualityManager:cellHasRemainingHarvestFruit(position)
    local fruitTypeIndex = position ~= nil and position.fruitTypeIndex or nil
    if fruitTypeIndex == nil
        or (FruitType ~= nil and fruitTypeIndex == FruitType.UNKNOWN)
        or FSDensityMapUtil == nil
        or FSDensityMapUtil.getFruitArea == nil then
        return true, false
    end
    local minX = position.ix * self.CELL_SIZE
    local minZ = position.iz * self.CELL_SIZE
    local maxX = minX + self.CELL_SIZE
    local maxZ = minZ + self.CELL_SIZE
    local ok, area = pcall(
        FSDensityMapUtil.getFruitArea,
        fruitTypeIndex,
        minX, minZ,
        maxX, minZ,
        minX, maxZ,
        false,
        position.useMinForageState == true
    )
    if not ok or area == nil then return true, false end
    return tonumber(area) ~= nil and tonumber(area) > 0, true
end

function TerraLogicQualityManager:flushPendingHarvestClears(cutter, maxCells)
    local pending = cutter ~= nil and self.pendingHarvestClears[cutter] or nil
    if pending == nil then return 0 end
    maxCells = tonumber(maxCells) or 32
    local advanced, pendingCount, checked = 0, 0, 0
    local retained, unknown = 0, 0
    for _ in pairs(pending) do pendingCount = pendingCount + 1 end
    for key, position in pairs(pending) do
        if checked >= maxCells then break end
        checked = checked + 1
        pending[key] = nil
        local hasRemainingFruit, queryKnown =
            self:cellHasRemainingHarvestFruit(position)
        if not queryKnown then
            unknown = unknown + 1
        elseif hasRemainingFruit then
            -- The fixed four-metre cell was only touched at its edge. Keep its
            -- quality data; it will be scheduled again when the cutter reaches
            -- the remaining crop in a later frame or adjacent pass.
            retained = retained + 1
        else
            local completed = self:completePartialHarvest(
                position, "arable", false)
            if not completed then
                completed = self:advanceCellAfterHarvest(position)
            end
            if completed then advanced = advanced + 1 end
        end
    end
    local deferred = 0
    for _ in pairs(pending) do deferred = deferred + 1 end
    if deferred == 0 then self.pendingHarvestClears[cutter] = nil end
    if advanced > 0 then self.dirty = true end
    if TerraLogicLogging ~= nil and TerraLogicLogging.verbose == true
        and (self.harvestClearDiagnosticCount or 0) < 40 then
        self.harvestClearDiagnosticCount =
            (self.harvestClearDiagnosticCount or 0) + 1
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Harvest clear: pendingCells=%d checked=%d advanced=%d retainedCrop=%d unknown=%d deferred=%d",
            pendingCount,
            checked,
            advanced,
            retained,
            unknown,
            deferred
        )
    end
    return advanced
end

function TerraLogicQualityManager:flushAllPendingHarvestClears()
    local cutters = {}
    for cutter in pairs(self.pendingHarvestClears) do
        cutters[#cutters + 1] = cutter
    end
    local cleared = 0
    for _, cutter in ipairs(cutters) do
        cleared = cleared + self:flushPendingHarvestClears(cutter, math.huge)
    end
    return cleared
end

-- Records only cells accepted by both Vanilla's changed area and surface rules.
function TerraLogicQualityManager:recordWorkArea(
        workArea, component, quality, changedArea,
        yieldWeight, maxYieldPenalty, vehicle, explicitHarvestPenalty,
        allowedCellKeys, aggregateVanillaFertilizer,
        prevalidatedSurfaceCellKeys)
    if g_currentMission == nil or not g_currentMission:getIsServer()
        or tonumber(changedArea) == nil or changedArea <= 0
        or self.COMPONENTS[component] == nil then
        return 0, 0, false
    end
    local definition = self.COMPONENTS[component]
    if definition.physicalDropoutsOnly == true then
        return 0, 0, false
    end
    local group = definition.group or component
    local vehicleSpec = vehicle ~= nil and vehicle.spec_terraLogic or nil
    if vehicleSpec ~= nil then
        vehicleSpec.liveWorkQualityGroups = vehicleSpec.liveWorkQualityGroups or {}
        vehicleSpec.liveWorkQualityGroups[group] = {
            quality = math.clamp(tonumber(quality) or 1, 0, 1),
            yieldPenalty = explicitHarvestPenalty ~= nil
                and math.clamp(tonumber(explicitHarvestPenalty) or 0, 0, 1)
                or self:calculateYieldPenalty(
                    quality,
                    definition.yieldWeight,
                    definition.maxYieldPenalty
                ),
            time = g_currentMission.time or 0
        }
    end
    local changed, acceptedCells = false, 0
    local isApplication = group == "fertilizer"
        or group == "lime" or group == "herbicide"
    local touchedPositions = self:getTouchedCells(workArea, isApplication)
    for _, position in ipairs(touchedPositions) do
        local cellKey = tostring(position.ix) .. ":" .. tostring(position.iz)
        local surfaceAllowed = prevalidatedSurfaceCellKeys ~= nil
                and prevalidatedSurfaceCellKeys[cellKey] == true
            or self:isComponentAllowedAtCell(
                component, position.ix, position.iz, vehicle)
        if (allowedCellKeys == nil or allowedCellKeys[cellKey] == true)
            and surfaceAllowed then
            acceptedCells = acceptedCells + 1
            -- Any successful agronomic pass after a partial harvest belongs to
            -- the next cycle. Close only that cell's marked arable/field-grass
            -- cycle before writing the new work; natural meadow has no marker.
            changed = self:completePartialHarvestBeforeNewWork(position)
                or changed
            -- Invalidate only after Vanilla reported a successful pass and
            -- only in the same TerraLogic cell admitted for the new component.
            changed = self:clearOverwrittenComponents(
                position, component) or changed
            if self:setCellComponent(
                    position.ix, position.iz, component, quality,
                    yieldWeight, maxYieldPenalty, explicitHarvestPenalty,
                    aggregateVanillaFertilizer) then
                changed = true
            end
        end
    end
    if acceptedCells > 0 and vehicleSpec ~= nil then
        vehicleSpec.lastActualWorkTime = g_currentMission.time or 0
        vehicleSpec.lastActualWorkProfile = group
        vehicleSpec.lastQualityWorkTime = g_currentMission.time or 0
        local stateChanged = false
        if vehicleSpec.actualWorkActive ~= true then
            vehicleSpec.actualWorkActive = true
            stateChanged = true
        end
        if vehicleSpec.qualityWorkActive ~= true then
            vehicleSpec.qualityWorkActive = true
            stateChanged = true
        end
        if vehicle ~= nil and vehicle.isServer and stateChanged then
            vehicle:raiseDirtyFlags(vehicleSpec.actualWorkDirtyFlag)
        end
    end
    if changed then self.dirty = true end
    return acceptedCells, #touchedPositions, changed
end

function TerraLogicQualityManager:getSpeedQualityForSpeeds(
        realSpeed, shopSpeed, currentSpeed)
    return self:getSpeedEconomyForSpeeds(
        realSpeed, shopSpeed, currentSpeed).preShopQuality
end

function TerraLogicQualityManager:getSpeedQuality(vehicle, currentSpeed)
    return self:getSpeedEconomy(vehicle, currentSpeed).preShopQuality
end

function TerraLogicQualityManager:getRootCropHarvesterPenalty(cutter)
    -- Harvesters and headers are deliberately outside TerraLogic's implement
    -- simulation. The common Cutter hook below only applies quality already
    -- stored by earlier field work; harvesting speed itself adds no penalty.
    return 0, 1, "stored field quality only"
end

function TerraLogicQualityManager:getCellAtWorldPosition(x, z, fallbackX, fallbackZ)
    local ix, iz = getCellIndex(x), getCellIndex(z)
    if g_currentMission == nil or g_currentMission:getIsServer() then
        return self:getPackedCell(ix, iz)
    end
    local key = tostring(ix) .. ":" .. tostring(iz)
    local cached = self.clientCells[key]
    local now = g_currentMission.time or 0
    if g_client ~= nil and (self.lastClientRequestKey ~= key
        or now >= (self.nextClientRequestTime or 0)) then
        local connection = g_client:getServerConnection()
        if connection ~= nil and TerraLogicQualityRequestEvent ~= nil then
            connection:sendEvent(TerraLogicQualityRequestEvent.new(
                ix, iz, x, z, fallbackX or x, fallbackZ or z))
            self.lastClientRequestKey = key
            self.nextClientRequestTime = now + 1000
        end
    end
    return cached ~= false and cached or nil
end

function TerraLogicQualityManager:getSummaryAtWorldPosition(x, z, fallbackX, fallbackZ)
    -- The quality box describes the land under the player, not the camera
    -- crosshair or an averaged neighbouring footprint.
    local cell = self:getCellAtWorldPosition(x, z)
    if cell == nil then return nil end
    local entries = self:getGroupedEntriesFromCell(cell)
    local sum, count = 0, #entries
    for _, entry in ipairs(entries) do sum = sum + entry.quality end
    return count > 0 and sum / count or nil, entries
end

function TerraLogicQualityManager:getGroupedEntriesFromCell(cell)
    local grouped = {}
    for _, component in ipairs(self.COMPONENT_ORDER) do
        local definition = self.COMPONENTS[component]
        if hasBit(cell.mask or 0, definition.bit)
            and definition.physicalDropoutsOnly ~= true then
            local group = definition.group or component
            local value = grouped[group]
            if value == nil then
                value = {
                    qualitySum = 0,
                    harvestPenaltySum = 0,
                    applicationCountSum = 0,
                    count = 0
                }
                grouped[group] = value
            end
            value.qualitySum = value.qualitySum
                + ((cell.values or {})[component] or 1)
            value.harvestPenaltySum = value.harvestPenaltySum
                + ((cell.penalties or {})[component] or 0)
            value.applicationCountSum = value.applicationCountSum
                + ((cell.applicationCounts or {})[component] or 1)
            value.count = value.count + 1
        end
    end
    local entries = {}
    for _, group in ipairs(self.GROUP_ORDER) do
        local value = grouped[group]
        local definition = self.GROUP_DEFINITIONS[group]
        if value ~= nil and value.count > 0 and definition ~= nil then
            local quality = value.qualitySum / value.count
            -- New records persist the category-specific economic result. Old
            -- saves without an explicit penalty still receive their legacy
            -- quality-derived fallback during migration/display.
            local storedPenalty = value.harvestPenaltySum / value.count
            local qualityPenalty = math.clamp(
                (definition.maxYieldPenalty or 0) * (1 - quality), 0,
                definition.maxYieldPenalty or 0)
            local targetPenalty = definition.directDensityPenalty == true
                and qualityPenalty or (storedPenalty > 0 and storedPenalty
                or (quality < 0.9995 and self:calculateYieldPenalty(
                    quality,
                    definition.yieldWeight,
                    definition.maxYieldPenalty
                ) or 0))
            local applicationCount = math.max(math.floor(
                value.applicationCountSum / value.count + 0.5), 1)
            local bonusDefinition = self.BONUS_GROUPS[group]
            local effectiveBonus = nil
            if bonusDefinition ~= nil then
                local denominator = 1 - quality - targetPenalty
                local inferredUnitBonus = denominator > 0.0001
                    and targetPenalty / denominator
                    or math.max(tonumber(bonusDefinition.bonus) or 0, 0)
                effectiveBonus = math.max(inferredUnitBonus, 0)
                    * applicationCount
            end
            entries[#entries + 1] = {
                name = group,
                label = self:getComponentLabel(group),
                quality = quality,
                yieldPenalty = targetPenalty,
                harvestPenalty = definition.directDensityPenalty == true
                    and storedPenalty or targetPenalty,
                directDensityPenalty = definition.directDensityPenalty == true,
                contributors = value.count,
                applicationCount = applicationCount,
                bonus = effectiveBonus
            }
        end
    end
    return entries
end

function TerraLogicQualityManager:getEffectiveYieldFactor(entries, useHarvestPenalty)
    local storedLoss, directDensityFactor = 0, 1
    local idealBonus, retainedBonus = 0, 0
    for _, entry in ipairs(entries or {}) do
        local definition = self.GROUP_DEFINITIONS[entry.name]
        local penalty = math.clamp(tonumber(useHarvestPenalty
            and entry.harvestPenalty or entry.yieldPenalty) or 0, 0, 1)
        local bonus = math.max(tonumber(entry.bonus) or 0, 0)
        if bonus > 0 then
            idealBonus = idealBonus + bonus
            retainedBonus = retainedBonus
                + bonus * math.clamp(tonumber(entry.quality) or 1, 0, 1)
        elseif definition ~= nil and definition.directDensityPenalty == true then
            directDensityFactor = directDensityFactor * (1 - penalty)
        else
            storedLoss = storedLoss + penalty
        end
    end
    local bonusFactor = (1 + retainedBonus) / math.max(1 + idealBonus, 0.0001)
    return math.clamp(
        directDensityFactor
            * (1 - math.min(storedLoss, self.MAXIMUM_TOTAL_YIELD_PENALTY))
            * bonusFactor,
        0,
        1
    )
end

function TerraLogicQualityManager:getAverageStoredYieldLoss(workArea, touchedCells)
    local lossSum, samples, touched = 0, 0,
        touchedCells or self:getTouchedCells(workArea)
    for _, position in ipairs(touched) do
        local cell = self:getPackedCell(position.ix, position.iz)
        local loss = 0
        if cell ~= nil then
            loss = 1 - self:getEffectiveYieldFactor(
                self:getGroupedEntriesFromCell(cell), true)
        end
        lossSum = lossSum + math.min(loss, self.MAXIMUM_TOTAL_YIELD_PENALTY)
        samples = samples + 1
    end
    return samples > 0 and lossSum / samples or 0, touched
end

-- Applies the stored total-yield factor before harvested material is credited.
function TerraLogicQualityManager:applyHarvestQuality(
    cutter, workArea, harvestedArea, multiplierAreaBefore,
    liveHarvestPenalty, liveHarvestQuality, liveHarvestClass,
    fruitTypeIndex, useMinForageState)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local params = cutter ~= nil and cutter.spec_cutter ~= nil
        and cutter.spec_cutter.workAreaParameters or nil
    harvestedArea = tonumber(harvestedArea) or 0
    if harvestedArea <= 0 then return end
    local lossSum, samples, storedSamples, penalizedSamples = 0, 0, 0, 0
    local touched = self:getTouchedCells(workArea)
    for _, position in ipairs(touched) do
        local cell = self:getPackedCell(position.ix, position.iz)
        local loss = math.max(tonumber(liveHarvestPenalty) or 0, 0)
        if cell ~= nil then
            storedSamples = storedSamples + 1
            self:markPartialHarvest(position, "arable", fruitTypeIndex)
            -- Stored penalties are relative losses of the complete local
            -- Vanilla/PF yield. A missing operation remains neutral because
            -- Vanilla/PF already owns its normal base-game bonus.
            -- Seed stores only the residual target loss not already
            -- represented by physical missing plants. Bonus groups are
            -- combined as one earned-bonus block, preventing several poor
            -- bonus passes from ever pushing yield below the prior baseline.
            loss = loss + (1 - self:getEffectiveYieldFactor(
                self:getGroupedEntriesFromCell(cell), true))
        end
        -- A live root-crop harvesting loss is independent of the stored field
        -- operations, so it must also count when this cell has no TerraLogic record.
        lossSum = lossSum + math.clamp(
            loss,
            0,
            self.MAXIMUM_TOTAL_YIELD_PENALTY
        )
        if loss > 0.0001 then penalizedSamples = penalizedSamples + 1 end
        samples = samples + 1
    end
    local averageLoss = samples > 0 and lossSum / samples or 0
    local oldMultiplierArea = -1
    local relativeAppliedLoss = 0
    if params ~= nil and params.lastMultiplierArea ~= nil then
        oldMultiplierArea = tonumber(params.lastMultiplierArea) or 0
        local currentBaseArea = oldMultiplierArea
            - math.max(tonumber(multiplierAreaBefore) or 0, 0)
        if currentBaseArea <= 0 then currentBaseArea = oldMultiplierArea end
        local requestedDeduction = currentBaseArea * averageLoss
        local newMultiplierArea = math.max(
            oldMultiplierArea - requestedDeduction,
            0
        )
        local appliedAreaDeduction = oldMultiplierArea - newMultiplierArea
        params.lastMultiplierArea = newMultiplierArea
        self.lastHarvestDebug = {
            averageLoss = averageLoss,
            baseMultiplier = harvestedArea > 0
                and currentBaseArea / harvestedArea or 0,
            finalMultiplier = harvestedArea > 0
                and math.max(
                    currentBaseArea * (1 - averageLoss),
                    0
                )
                    / harvestedArea or 0,
            appliedDeduction = harvestedArea > 0
                and appliedAreaDeduction / harvestedArea or 0,
            relativeLoss = currentBaseArea > 0
                and math.clamp(appliedAreaDeduction / currentBaseArea, 0, 1) or 0,
            samples = samples,
            liveHarvestPenalty = liveHarvestPenalty or 0,
            liveHarvestQuality = liveHarvestQuality or 1,
            liveHarvestClass = liveHarvestClass or "none",
            time = g_currentMission.time or 0
        }
        relativeAppliedLoss = self.lastHarvestDebug.relativeLoss
    end
    -- Do not clear a fixed four-metre cell on the header's first narrow
    -- contact. A later zero-area frame checks the complete cell and advances
    -- its crop-cycle ledger only after the matching fruit is actually gone.
    local newlyPending = self:scheduleHarvestClear(
        cutter,
        touched,
        fruitTypeIndex,
        useMinForageState
    )
    if TerraLogicLogging ~= nil and TerraLogicLogging.verbose == true then
        local now = g_currentMission.time or 0
        local state = self.harvestDiagnosticState[cutter]
        local changed = state == nil
            or state.storedSamples ~= storedSamples
            or state.penalizedSamples ~= penalizedSamples
            or math.abs((state.averageLoss or 0) - averageLoss) >= 0.005
        local intervalElapsed = state == nil
            or now - (state.lastLogTime or 0) >= 250
        if (changed or intervalElapsed)
            and (self.harvestDiagnosticCount or 0) < 160 then
            local pendingCount = 0
            local pending = self.pendingHarvestClears[cutter]
            if pending ~= nil then
                for _ in pairs(pending) do pendingCount = pendingCount + 1 end
            end
            self.harvestDiagnosticCount =
                (self.harvestDiagnosticCount or 0) + 1
            TerraLogicLogging.debug(
                "[FS25_TerraLogic] Harvest sample: area=%.4f multiplierArea=%.4f cells=%d stored=%d penalized=%d loss=%.2f%% applied=%.2f%% pending=%d(+%d) fruit=%s liveClass=%s",
                harvestedArea,
                oldMultiplierArea,
                samples,
                storedSamples,
                penalizedSamples,
                averageLoss * 100,
                relativeAppliedLoss * 100,
                pendingCount,
                newlyPending,
                tostring(fruitTypeIndex),
                tostring(liveHarvestClass or "none")
            )
            self.harvestDiagnosticState[cutter] = {
                storedSamples = storedSamples,
                penalizedSamples = penalizedSamples,
                averageLoss = averageLoss,
                lastLogTime = now
            }
        end
    end
end

-- Persistence ---------------------------------------------------------------

-- Returns the primary quality-ledger path in the active savegame.
function TerraLogicQualityManager:getSavePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local directory = info ~= nil and info.savegameDirectory or nil
    return directory ~= nil and directory .. "/" .. self.SAVE_FILE or nil
end

function TerraLogicQualityManager:getLegacySavePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local directory = info ~= nil and info.savegameDirectory or nil
    return directory ~= nil and directory .. "/" .. self.LEGACY_SAVE_FILE or nil
end

-- Keep one redundant copy outside the savegame directory. GIANTS rewrites a
-- save slot when saving; if a broken/disabled mod cannot recreate its custom
-- file during that pass, the slot copy can disappear. The mirror survives
-- such a pass and is automatically used by the next working mod version.
function TerraLogicQualityManager:getMirrorPath(createDirectory, legacy)
    if getUserProfileAppPath == nil then return nil end
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local directory = info ~= nil and info.savegameDirectory or nil
    local slot = info ~= nil and tonumber(info.savegameIndex) or nil
    if slot == nil and directory ~= nil then
        slot = tonumber(string.match(directory, "savegame(%d+)"))
    end
    if slot == nil then return nil end
    local mirrorDirectory = getUserProfileAppPath() .. "modSettings/"
        .. (legacy == true and "FS25_OverSpeedDamage" or "FS25_TerraLogic")
    if createDirectory == true and createFolder ~= nil then
        pcall(createFolder, mirrorDirectory)
    end
    return string.format(
        "%s/savegame%d_%s", mirrorDirectory, slot,
        legacy == true and self.LEGACY_SAVE_FILE or self.SAVE_FILE)
end

-- Loads current data, legacy data, or the redundant mirror in that order.
function TerraLogicQualityManager:load()
    self.chunks = {}
    self.applicationCellStamps = {}
    self.pendingHarvestClears = {}
    self.pendingMowerClears = {}
    self.partialHarvestCells = {}
    self:resetHarvestDiagnostics()
    self.pruneChunkKeys = nil
    self.pruneChunkIndex = nil
    self.pruneOffset = nil
    self.pruneRemoved = 0
    local path = self:getSavePath()
    if path == nil or fileExists == nil then return end
    local loadPath = path
    local mirrorPath = self:getMirrorPath(false)
    local legacyPath = self:getLegacySavePath()
    local legacyMirrorPath = self:getMirrorPath(false, true)
    local recoveredFromMirror = false
    local migratedFromLegacy = false
    if not fileExists(loadPath) then
        if legacyPath ~= nil and fileExists(legacyPath) then
            loadPath = legacyPath
            migratedFromLegacy = true
        elseif mirrorPath ~= nil and fileExists(mirrorPath) then
            loadPath = mirrorPath
            recoveredFromMirror = true
        elseif legacyMirrorPath ~= nil and fileExists(legacyMirrorPath) then
            loadPath = legacyMirrorPath
            recoveredFromMirror = true
            migratedFromLegacy = true
        else
            return
        end
        Logging.warning(
            "[TerraLogic] Work-quality data recovered from %s",
            tostring(loadPath)
        )
    end
    local xml = loadXMLFile("terraLogicWorkQuality", loadPath)
    local format = getXMLInt(xml, "quality#format") or 1
    local legacyNames = {
        soilPlow = "plow",
        soilCultivate = "cultivate",
        seed = "seed",
        fertilizer = "fertilizer",
        lime = "lime",
        herbicide = "herbicide",
        roller = "roller",
        mulch = "mulch"
    }
    local loadedCells, loadedChunks = 0, 0
    if format >= 2 then
        local index = 0
        while hasXMLProperty(xml, string.format("quality.chunk(%d)", index)) do
            local key = string.format("quality.chunk(%d)", index)
            local chunkX, chunkZ = getXMLInt(xml, key .. "#x"), getXMLInt(xml, key .. "#z")
            local statusHex = getXMLString(xml, key .. "#status")
            if chunkX ~= nil and chunkZ ~= nil and statusHex ~= nil then
                local chunk = newChunk(chunkX, chunkZ, hexToBytes(statusHex, 0))
                local format5StatusData = format == 5 and chunk.status.data or nil
                if format == 5 then
                    -- Format 5 temporarily used bit 64 for direct-drill soil.
                    -- Format 6 folds direct drilling into the normal soil-
                    -- cultivation contributor and restores bit 64 to mulch.
                    for offset = 1, self.CHUNK_CELL_COUNT do
                        local mask = getLayerByte(chunk.status, offset)
                        if hasBit(mask, 64) then
                            setLayerByte(chunk.status, offset,
                                addBit(removeBit(mask, 64), 2))
                        end
                    end
                end
                if chunk.status.nonDefaultCount > 0 then
                    for _, name in ipairs(self.COMPONENT_ORDER) do
                        local savedName = format < 5 and legacyNames[name] or name
                        local value = savedName ~= nil
                            and getXMLString(xml, key .. "#" .. savedName) or nil
                        if format == 5 and name == "soilCultivate" then
                            local directValue = getXMLString(
                                xml, key .. "#soilDirect")
                            value = bytesToHex(mergeFormat5SoilLayers(
                                format5StatusData, value, directValue, 255, true))
                        end
                        if value ~= nil then
                            local layer = newLayer(255, hexToBytes(value, 255))
                            if layer.nonDefaultCount > 0 then chunk.qualities[name] = layer end
                        end
                        local penaltyValue = nil
                        if not (format < 5 and name == "seed") then
                            penaltyValue = getXMLString(
                                xml,
                                savedName ~= nil
                                    and key .. "#penalty_" .. savedName
                                    or key .. "#unused"
                            )
                        end
                        if format == 5 and name == "soilCultivate" then
                            local directPenalty = getXMLString(
                                xml, key .. "#penalty_soilDirect")
                            penaltyValue = bytesToHex(mergeFormat5SoilLayers(
                                format5StatusData, penaltyValue,
                                directPenalty, 0, false))
                        end
                        if penaltyValue ~= nil then
                            local penaltyLayer = newLayer(
                                0,
                                hexToBytes(penaltyValue, 0)
                            )
                            if penaltyLayer.nonDefaultCount > 0 then
                                chunk.penalties[name] = penaltyLayer
                            end
                        end
                    end
                    if format >= 7 then
                        local countValue = getXMLString(
                            xml, key .. "#count_fertilizer")
                        if countValue ~= nil then
                            local countLayer = newLayer(
                                0, hexToBytes(countValue, 0))
                            if countLayer.nonDefaultCount > 0 then
                                chunk.counts.fertilizer = countLayer
                            end
                        end
                    else
                        -- Older saves stored every application as a universal
                        -- whole-yield deduction. Convert bonus work to the new
                        -- safe semantics: poor work may remove its own Vanilla
                        -- bonus, but can never reduce the pre-treatment yield.
                        local legacyBonus = {
                            fertilizer = 0.225,
                            lime = 0.15,
                            herbicide = 0.20,
                            roller = 0.025,
                            mulch = 0.025
                        }
                        for name, bonus in pairs(legacyBonus) do
                            local definition = self.COMPONENTS[name]
                            if definition ~= nil then
                                local countLayer = nil
                                if name == "fertilizer" then
                                    countLayer = newLayer(0, ZERO_DATA)
                                end
                                local qualityLayer = chunk.qualities[name]
                                local penaltyLayer = newLayer(0, ZERO_DATA)
                                for offset = 1, self.CHUNK_CELL_COUNT do
                                    local mask = getLayerByte(chunk.status, offset)
                                    if hasBit(mask, definition.bit) then
                                        local encoded = qualityLayer ~= nil
                                            and getLayerByte(qualityLayer, offset)
                                            or 255
                                        local quality = encoded == 255
                                            and 1 or encoded / 254
                                        local relativePenalty = bonus * (1 - quality)
                                            / math.max(1 + bonus, 0.0001)
                                        local penaltyEncoded = math.clamp(
                                            math.floor(relativePenalty * 255 + 0.5),
                                            0, 255)
                                        if penaltyEncoded > 0 then
                                            setLayerByte(
                                                penaltyLayer, offset,
                                                penaltyEncoded)
                                        end
                                        if countLayer ~= nil then
                                            setLayerByte(countLayer, offset, 1)
                                        end
                                    end
                                end
                                if penaltyLayer.nonDefaultCount > 0 then
                                    chunk.penalties[name] = penaltyLayer
                                else
                                    chunk.penalties[name] = nil
                                end
                                if countLayer ~= nil
                                    and countLayer.nonDefaultCount > 0 then
                                    chunk.counts.fertilizer = countLayer
                                end
                            end
                        end
                    end
                    self.chunks[tostring(chunkX) .. ":" .. tostring(chunkZ)] = chunk
                    loadedCells = loadedCells + chunk.status.nonDefaultCount
                    loadedChunks = loadedChunks + 1
                end
            end
            index = index + 1
        end
    else
        local index = 0
        while hasXMLProperty(xml, string.format("quality.cell(%d)", index)) do
            local key = string.format("quality.cell(%d)", index)
            local ix, iz = getXMLInt(xml, key .. "#x"), getXMLInt(xml, key .. "#z")
            if ix ~= nil and iz ~= nil then
                local found = false
                for _, name in ipairs(self.COMPONENT_ORDER) do
                    local savedName = legacyNames[name]
                    local value = savedName ~= nil
                        and getXMLInt(xml, key .. "#" .. savedName) or nil
                    if value ~= nil then
                        local quality = math.clamp(value / 100, 0, 1)
                        local definition = self.COMPONENTS[name]
                        local group = definition ~= nil
                            and (definition.group or name) or name
                        local bonusDefinition = self.BONUS_GROUPS[group]
                        local explicitPenalty = name == "seed" and 0 or nil
                        if bonusDefinition ~= nil then
                            local bonus = bonusDefinition.bonus or 0
                            explicitPenalty = bonus * (1 - quality)
                                / math.max(1 + bonus, 0.0001)
                        end
                        self:setCellComponent(
                            ix, iz, name, quality,
                            nil, nil, explicitPenalty,
                            name == "fertilizer"
                        )
                        found = true
                    end
                end
                if found then loadedCells = loadedCells + 1 end
            end
            index = index + 1
        end
        for _ in pairs(self.chunks) do loadedChunks = loadedChunks + 1 end
    end
    local loadedPartialHarvests = 0
    if format >= 8 then
        local partialIndex = 0
        while hasXMLProperty(
                xml, string.format("quality.partialHarvest(%d)", partialIndex)) do
            local key = string.format("quality.partialHarvest(%d)", partialIndex)
            local ix = getXMLInt(xml, key .. "#x")
            local iz = getXMLInt(xml, key .. "#z")
            local domain = getXMLString(xml, key .. "#domain")
            local fruitTypeIndex = getXMLInt(xml, key .. "#fruitType")
            if ix ~= nil and iz ~= nil
                and (domain == "arable" or domain == "fieldGrass") then
                local markerKey = tostring(ix) .. ":" .. tostring(iz)
                    .. ":" .. tostring(domain)
                self.partialHarvestCells[markerKey] = {
                    ix = ix,
                    iz = iz,
                    domain = domain,
                    fruitTypeIndex = fruitTypeIndex
                }
                loadedPartialHarvests = loadedPartialHarvests + 1
            end
            partialIndex = partialIndex + 1
        end
    end
    delete(xml)
    self.dirty = format < 8 or recoveredFromMirror or migratedFromLegacy
    self.mirrorNeedsSync = mirrorPath == nil or not fileExists(mirrorPath)
    self:beginStoredCellPrune()
    TerraLogicLogging.debug("[FS25_TerraLogic] Loaded %d work-quality cells in %d compact chunks (%d partial harvest markers)",
        loadedCells, loadedChunks, loadedPartialHarvests)
end

-- Writes only non-default cells using compact byte layers and updates the mirror.
function TerraLogicQualityManager:save()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    self:flushAllPendingHarvestClears()
    local path = self:getSavePath()
    if path == nil then return end
    if not self.dirty and self.mirrorNeedsSync ~= true then return end
    local index, savedCells = 0, 0
    if self.dirty then
        local xml = createXMLFile("terraLogicWorkQuality", path, "quality")
        setXMLInt(xml, "quality#format", 8)
        setXMLInt(xml, "quality#cellSize", self.CELL_SIZE)
        setXMLInt(xml, "quality#chunkSize", self.CHUNK_SIZE)
        for _, chunk in pairs(self.chunks) do
            if chunk.status.nonDefaultCount > 0 then
                savedCells = savedCells + chunk.status.nonDefaultCount
                flushLayer(chunk.status)
                local key = string.format("quality.chunk(%d)", index)
                setXMLInt(xml, key .. "#x", chunk.x)
                setXMLInt(xml, key .. "#z", chunk.z)
                setXMLString(xml, key .. "#status", bytesToHex(chunk.status.data))
                for name, layer in pairs(chunk.qualities) do
                    if layer.nonDefaultCount > 0 then
                        flushLayer(layer)
                        setXMLString(xml, key .. "#" .. name, bytesToHex(layer.data))
                    end
                end
                for name, penaltyLayer in pairs(chunk.penalties) do
                    if penaltyLayer.nonDefaultCount > 0 then
                        flushLayer(penaltyLayer)
                        setXMLString(
                            xml,
                            key .. "#penalty_" .. name,
                            bytesToHex(penaltyLayer.data)
                        )
                    end
                end
                for name, countLayer in pairs(chunk.counts) do
                    if countLayer.nonDefaultCount > 0 then
                        flushLayer(countLayer)
                        setXMLString(
                            xml,
                            key .. "#count_" .. name,
                            bytesToHex(countLayer.data)
                        )
                    end
                end
                index = index + 1
            end
        end
        local partialIndex = 0
        for key, marker in pairs(self.partialHarvestCells) do
            local position = marker ~= nil and {
                ix = marker.ix,
                iz = marker.iz
            } or nil
            if position ~= nil and self:getPackedCell(position.ix, position.iz) ~= nil then
                local xmlKey = string.format(
                    "quality.partialHarvest(%d)", partialIndex)
                setXMLInt(xml, xmlKey .. "#x", position.ix)
                setXMLInt(xml, xmlKey .. "#z", position.iz)
                setXMLString(xml, xmlKey .. "#domain", marker.domain)
                if marker.fruitTypeIndex ~= nil then
                    setXMLInt(
                        xml, xmlKey .. "#fruitType", marker.fruitTypeIndex)
                end
                partialIndex = partialIndex + 1
            else
                self.partialHarvestCells[key] = nil
            end
        end
        saveXMLFile(xml)
        delete(xml)
        self.dirty = false
        TerraLogicLogging.debug(
            "[FS25_TerraLogic] Saved %d work-quality cells in %d compact chunks to %s",
            savedCells,
            index,
            tostring(path)
        )
    end
    local mirrorPath = self:getMirrorPath(true)
    if mirrorPath ~= nil and fileExists ~= nil and fileExists(path)
        and copyFile ~= nil then
        local ok, copied = pcall(copyFile, path, mirrorPath, true)
        if ok and copied ~= false then
            self.mirrorNeedsSync = false
        else
            Logging.warning(
                "[FS25_TerraLogic] Could not update work-quality mirror %s",
                tostring(mirrorPath)
            )
        end
    end
end

TerraLogicQualityRequestEvent = {}
local TerraLogicQualityRequestEvent_mt = Class(TerraLogicQualityRequestEvent, Event)
InitEventClass(TerraLogicQualityRequestEvent, "TerraLogicQualityRequestEvent")

-- Multiplayer synchronization ----------------------------------------------

-- Constructs an empty client request for one quality cell.
function TerraLogicQualityRequestEvent.emptyNew()
    return Event.new(TerraLogicQualityRequestEvent_mt)
end

function TerraLogicQualityRequestEvent.new(ix, iz, x, z, fallbackX, fallbackZ)
    local self = TerraLogicQualityRequestEvent.emptyNew()
    self.ix, self.iz = ix, iz
    self.x, self.z = x, z
    self.fallbackX, self.fallbackZ = fallbackX, fallbackZ
    return self
end

function TerraLogicQualityRequestEvent:readStream(streamId, connection)
    self.ix = streamReadInt32(streamId)
    self.iz = streamReadInt32(streamId)
    self.x = streamReadFloat32(streamId)
    self.z = streamReadFloat32(streamId)
    self.fallbackX = streamReadFloat32(streamId)
    self.fallbackZ = streamReadFloat32(streamId)
    self:run(connection)
end

function TerraLogicQualityRequestEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.ix)
    streamWriteInt32(streamId, self.iz)
    streamWriteFloat32(streamId, self.x)
    streamWriteFloat32(streamId, self.z)
    streamWriteFloat32(streamId, self.fallbackX)
    streamWriteFloat32(streamId, self.fallbackZ)
end

function TerraLogicQualityRequestEvent:run(connection)
    if connection:getIsServer() then return end
    local cell = TerraLogicQualityManager:getPackedCell(self.ix, self.iz)
    connection:sendEvent(TerraLogicQualitySyncEvent.new(self.ix, self.iz, cell))
end

TerraLogicQualitySyncEvent = {}
local TerraLogicQualitySyncEvent_mt = Class(TerraLogicQualitySyncEvent, Event)
InitEventClass(TerraLogicQualitySyncEvent, "TerraLogicQualitySyncEvent")

function TerraLogicQualitySyncEvent.emptyNew()
    return Event.new(TerraLogicQualitySyncEvent_mt)
end

function TerraLogicQualitySyncEvent.new(ix, iz, cell)
    local self = TerraLogicQualitySyncEvent.emptyNew()
    self.ix, self.iz, self.cell = ix, iz, cell
    return self
end

function TerraLogicQualitySyncEvent:readStream(streamId, connection)
    self.ix = streamReadInt32(streamId)
    self.iz = streamReadInt32(streamId)
    local hasCell = streamReadBool(streamId)
    if hasCell then
        self.cell = {
            mask = streamReadUInt8(streamId),
            values = {},
            penalties = {}
        }
        for _, name in ipairs(TerraLogicQualityManager.COMPONENT_ORDER) do
            local encoded = streamReadUInt8(streamId)
            if encoded < 255 then self.cell.values[name] = encoded / 254 end
            local penaltyEncoded = streamReadUInt8(streamId)
            if penaltyEncoded > 0 then
                self.cell.penalties[name] = penaltyEncoded / 255
            end
        end
    end
    self:run(connection)
end

function TerraLogicQualitySyncEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.ix)
    streamWriteInt32(streamId, self.iz)
    streamWriteBool(streamId, self.cell ~= nil)
    if self.cell ~= nil then
        streamWriteUInt8(streamId, self.cell.mask or 0)
        for _, name in ipairs(TerraLogicQualityManager.COMPONENT_ORDER) do
            local quality = self.cell.values[name]
            streamWriteUInt8(streamId, quality ~= nil
                and math.clamp(math.floor(quality * 254 + 0.5), 0, 254) or 255)
            local penalty = (self.cell.penalties or {})[name]
            streamWriteUInt8(streamId, penalty ~= nil
                and math.clamp(math.floor(penalty * 255 + 0.5), 0, 255) or 0)
        end
    end
end

function TerraLogicQualitySyncEvent:run(connection)
    if not connection:getIsServer() then return end
    local key = tostring(self.ix) .. ":" .. tostring(self.iz)
    TerraLogicQualityManager.clientCells[key] = self.cell or false
end

if Cutter ~= nil and Cutter.onEndWorkAreaProcessing ~= nil
    and Cutter.terraLogicQualityEndHookInstalled ~= true then
    local originalOnEndWorkAreaProcessing = Cutter.onEndWorkAreaProcessing
    Cutter.onEndWorkAreaProcessing = function(self, dt, hasProcessed)
        local spec = self.spec_cutter
        local params = spec ~= nil and spec.workAreaParameters or nil
        local harvestedArea = params ~= nil and tonumber(params.lastArea) or 0
        if g_currentMission ~= nil and g_currentMission:getIsServer()
            and harvestedArea > 0 then
            local workArea = self.getWorkAreaByIndex ~= nil
                and self:getWorkAreaByIndex(1) or nil
            local liveHarvestPenalty, liveHarvestQuality, liveHarvestClass =
                TerraLogicQualityManager:getRootCropHarvesterPenalty(self)
            local fruitTypeIndex = params ~= nil and params.lastFruitType or nil
            local useMinForageState = spec ~= nil
                and spec.useMinForageState == true
            TerraLogicQualityManager:applyHarvestQuality(
                self, workArea, harvestedArea, 0,
                liveHarvestPenalty, liveHarvestQuality, liveHarvestClass,
                fruitTypeIndex, useMinForageState)
        elseif g_currentMission ~= nil and g_currentMission:getIsServer() then
            TerraLogicQualityManager:flushPendingHarvestClears(self)
        end
        return originalOnEndWorkAreaProcessing(self, dt, hasProcessed)
    end
    Cutter.terraLogicQualityEndHookInstalled = true
    TerraLogicLogging.debug(
        "[FS25_TerraLogic] Installed pre-liter Cutter work-quality hook"
    )
end

if Mower ~= nil and Mower.processMowerArea ~= nil
    and Mower.terraLogicQualityHookInstalled ~= true then
    local originalProcessMowerArea = Mower.processMowerArea
    Mower.processMowerArea = function(self, workArea, dt)
        -- Capture the surface before Vanilla changes GRASS/MEADOW into its cut
        -- state. This decides whether to use the perennial selective reset.
        local touchedBefore = TerraLogicQualityManager:getTouchedCells(workArea)
        local fieldGrassPositions = {}
        for _, position in ipairs(touchedBefore or {}) do
            local surface = TerraLogicQualityManager:getSurfaceTypeAtWorldPosition(
                (position.ix + 0.5) * TerraLogicQualityManager.CELL_SIZE,
                (position.iz + 0.5) * TerraLogicQualityManager.CELL_SIZE)
            if surface == "grassField" then
                fieldGrassPositions[#fieldGrassPositions + 1] = position
            end
        end
        local dropArea = self.getDropArea ~= nil and self:getDropArea(workArea) or nil
        local dropBefore = dropArea ~= nil
            and tonumber(dropArea.litersToDrop) or nil
        local mowerSpec = self.spec_mower
        local fillUnitIndex = mowerSpec ~= nil and mowerSpec.fillUnitIndex or nil
        local fillBefore = fillUnitIndex ~= nil
            and self.getFillUnitFillLevel ~= nil
            and self:getFillUnitFillLevel(fillUnitIndex) or nil
        local changedArea, totalArea = originalProcessMowerArea(self, workArea, dt)
        if g_currentMission ~= nil and g_currentMission:getIsServer()
            and (tonumber(changedArea) or 0) > 0 then
            local inputFruitType = mowerSpec ~= nil
                and mowerSpec.workAreaParameters ~= nil
                and mowerSpec.workAreaParameters.lastInputFruitType or nil
            local isMeadowInput = FruitType ~= nil
                and FruitType.MEADOW ~= nil
                and inputFruitType == FruitType.MEADOW
            local isGrassInput = FruitType ~= nil
                and FruitType.GRASS ~= nil
                and inputFruitType == FruitType.GRASS
            local ledgerPositions, harvestDomain = {}, nil
            if isGrassInput then
                -- Sown grass on a field owns the perennial ledger. Natural
                -- GRASS outside a field contributes no stored-quality loss.
                ledgerPositions = fieldGrassPositions
                harvestDomain = "fieldGrass"
            elseif not isMeadowInput
                and inputFruitType ~= nil
                and (FruitType == nil or inputFruitType ~= FruitType.UNKNOWN) then
                ledgerPositions = touchedBefore
                harvestDomain = "arable"
            end
            local loss = 0
            if #ledgerPositions > 0 then
                loss = TerraLogicQualityManager:getAverageStoredYieldLoss(
                    workArea, ledgerPositions)
                -- One mower work area can straddle sown field grass and
                -- natural GRASS. Approximate the stored share by fixed cells;
                -- the live mower penalty still applies to every cut liter.
                if isGrassInput and #touchedBefore > 0 then
                    loss = loss * math.clamp(
                        #ledgerPositions / #touchedBefore, 0, 1)
                end
            end
            local mowerPenalty = 0
            local terraLogicSpec = self.spec_terraLogic
            if terraLogicSpec ~= nil and terraLogicSpec.implementClassKey == "mower" then
                terraLogicSpec.liveWorkQualityGroups = terraLogicSpec.liveWorkQualityGroups or {}
                local mowerQualityEnabled = TerraLogicMain == nil
                    or TerraLogicMain.mowerQualityEnabled ~= false
                if mowerQualityEnabled then
                    local speed = self.getLastSpeed ~= nil
                        and math.abs(tonumber(self:getLastSpeed(true)) or 0) or 0
                    local mowerQuality, livePenalty, model =
                        TerraLogicQualityManager:getWorkQualityModel(
                            self, speed, "mower", nil)
                    mowerPenalty = math.clamp(tonumber(livePenalty) or 0, 0, 1)
                    terraLogicSpec.mowerQuality = mowerQuality
                    terraLogicSpec.mowerYieldPenalty = mowerPenalty
                    terraLogicSpec.mowerQualityModel = model
                    terraLogicSpec.liveWorkQualityGroups.mower = {
                        quality = mowerQuality,
                        yieldPenalty = mowerPenalty,
                        time = g_currentMission.time or 0
                    }
                else
                    terraLogicSpec.mowerQuality = nil
                    terraLogicSpec.mowerYieldPenalty = 0
                    terraLogicSpec.mowerQualityModel = nil
                    terraLogicSpec.liveWorkQualityGroups.mower = nil
                end
            end

            -- Stored agronomic losses and the current mowing loss are separate
            -- causes and therefore compose multiplicatively. Only newly created
            -- liters are touched; changedArea/totalArea stay exactly as Vanilla
            -- returned them so PF nitrogen/pH consumption and statistics remain
            -- based on the actual harvested surface.
            local retainedFactor = (1 - math.clamp(loss or 0, 0, 1))
                * (1 - mowerPenalty)
            local totalLoss = 1 - retainedFactor
            if totalLoss > 0 and dropArea ~= nil and dropBefore ~= nil then
                local dropAfter = tonumber(dropArea.litersToDrop) or dropBefore
                local newlyAdded = math.max(dropAfter - dropBefore, 0)
                local retained = newlyAdded * retainedFactor
                dropArea.litersToDrop = dropBefore + retained
                if workArea.lastPickupLiters ~= nil then
                    workArea.lastPickupLiters = workArea.lastPickupLiters * retainedFactor
                end
                if workArea.pickedUpLiters ~= nil then
                    workArea.pickedUpLiters = workArea.pickedUpLiters * retainedFactor
                end
            elseif totalLoss > 0 and fillUnitIndex ~= nil and fillBefore ~= nil
                and self.getFillUnitFillLevel ~= nil
                and self.addFillUnitFillLevel ~= nil then
                local fillAfter = self:getFillUnitFillLevel(fillUnitIndex)
                local deduction = math.max(fillAfter - fillBefore, 0) * totalLoss
                if deduction > 0 then
                    local fillType = self.getFillUnitFillType ~= nil
                        and self:getFillUnitFillType(fillUnitIndex) or FillType.UNKNOWN
                    self:addFillUnitFillLevel(
                        self:getOwnerFarmId(), fillUnitIndex, -deduction,
                        fillType, ToolType.UNDEFINED)
                end
            end
            local pfActive = TerraLogicMain ~= nil
                and TerraLogicMain.isPrecisionFarmingActive ~= nil
                and TerraLogicMain:isPrecisionFarmingActive()
            if harvestDomain ~= nil and #ledgerPositions > 0 then
                TerraLogicQualityManager:scheduleMowerClear(
                    self, ledgerPositions, harvestDomain,
                    inputFruitType, pfActive)
            end
        end
        return changedArea, totalArea
    end
    Mower.terraLogicQualityHookInstalled = true
    TerraLogicLogging.debug("[FS25_TerraLogic] Installed mower work-quality yield hook")
end
