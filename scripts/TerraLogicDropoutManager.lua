--[[
    TerraLogicDropoutManager.lua
    Deterministic dropout patterns and work-quality curve definitions.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-DROP-1.200097
]]

-- Encapsulated work-quality/dropout model. Game-specific density-map writes
-- remain in TerraLogic.lua; all pattern selection and balance values live
-- here and are selected through each implement's dropoutProfile entry.
TerraLogicDropoutManager = {}
OverSpeedDamageDropoutManager = TerraLogicDropoutManager
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicDropoutManager.SOURCE_FINGERPRINT = 1.200097

TerraLogicDropoutManager.PROFILES = {
    seed = {
        enabled = true,
        patternType = "stagedLanes",
        -- Seed dropouts are purely speed-driven. Implement damage must not
        -- move their onset below the rated/shop working speed.
        damageThresholdShift = 0.00,
        fallbackMinimumThresholdRatio = 0.75,
        overspeedReferenceRatio = 1.25,
        overspeedPenaltyAtReference = 0.10,
        overspeedLinearPenaltyPerExcess = 0.50,
        overspeedExponent = 2.00,
        patternLaneWidthM = 0.75,
        -- The fruit density map and slightly shifting WorkArea edges can hide
        -- narrower gaps. This only affects the spatial grouping, not quality.
        minimumVisibleLaneWidthM = 1.00,
        patternLengthM = 2.00,
        -- Keep one sampled pattern active until every overlapping Vanilla
        -- density write has moved beyond it.
        persistenceMarginM = 2.00,
        maximumPersistenceDistanceM = 12.00,
        maximumPatternLanes = 20,
        singleLaneMaximumSpeedRatio = 1.15,
        multiLaneMaximumSpeedRatio = 1.50,
        multiLaneMaximumFraction = 0.50,
        fullWidthStartSpeedRatio = 1.50,
        fullWidthChanceAtDoubleSpeed = 0.015,
        fullWidthMaximumChance = 0.05,
        fullWidthChanceExponent = 2.00,
        freshRawState = 1
    },

    -- Kept separate deliberately: liquid and granular application can receive
    -- different physical models without touching the vehicle specialization.
    liquidSprayer = {
        enabled = true,
        patternType = "independentCells",
        damageThresholdShift = 1.00,
        fallbackMinimumThresholdRatio = 0.75,
        overspeedReferenceRatio = 1.25,
        overspeedPenaltyAtReference = 0.10,
        overspeedLinearPenaltyPerExcess = 0.50,
        overspeedExponent = 2.00,
        patternLaneWidthM = 2.50,
        patternLengthM = 4.00,
        maximumPatternLanes = 16
    },
    fertilizerSpreader = {
        enabled = true,
        patternType = "independentCells",
        damageThresholdShift = 1.00,
        fallbackMinimumThresholdRatio = 0.75,
        overspeedReferenceRatio = 1.25,
        overspeedPenaltyAtReference = 0.10,
        overspeedLinearPenaltyPerExcess = 0.50,
        overspeedExponent = 2.00,
        patternLaneWidthM = 2.50,
        patternLengthM = 4.00,
        maximumPatternLanes = 16
    },
    roller = {
        enabled = true,
        patternType = "rollerRollback",
        failureAtOnePointFiveRated = 0.01,
        overspeedExponent = 2.00,
        maximumFailureFraction = 0.08,
        patternLaneWidthM = 1.00,
        patternLengthM = 3.00,
        maximumPatternLanes = 16,
        freshRawState = 1
    },

    -- Event-driven mechanical work gaps. Unlike seed/application quality,
    -- these patterns are not sampled continuously: an impact starts a
    -- distance-latched failure and the affected tool segments recover after
    -- travelling the configured distance. Further ground tools can reuse the
    -- same mechanism by assigning their own profile in ImplementProfiles.
    plowImpact = {
        enabled = true,
        patternType = "impactLatchedSegments",
        -- Vanilla terrain detail uses roughly 0.5 m per pixel. Runtime code
        -- compares this reference with the active map so 4x maps remain
        -- balanced whether they use a 4096 or 8192 detail map.
        referenceDensityPixelSizeM = 0.50,
        -- Roughly one density-map-visible plow body/share. Keeping this narrow
        -- prevents a stone or throw fault from becoming a round, full-width
        -- patch on wide implements.
        segmentWidthM = 0.50,
        -- The terrain texture raster swallows 0.5 m corridors on some maps.
        -- Keep the mechanical lane at share width but make the actual ground-
        -- type rollback just wide enough to produce a cultivated texture.
        minimumPostPassWidthM = 0.85,
        -- Fixed world-space padding avoids engine APIs that cannot query the
        -- PNG-backed PLOW_LEVEL info layer directly.
        plowLevelRasterPaddingFallbackM = 0.10,
        -- Sample the pre-pass plowing requirement ahead of the implement.
        -- This avoids an already plowed headland or adjacent overlap becoming
        -- the latched state for the entire new row.
        plowLevelSnapshotForwardOffsetM = 4.00,
        plowTextureScatter = {
            enabled = true,
            -- Keep each visual disturbance close to one terrain-density-map
            -- pixel. Large 1 x 1.25 m cells produced long, repeated diagonal
            -- herringbone lines instead of locally disturbed furrows.
            -- One raster cell across the implement, two cells in the direction
            -- of travel. The elongated footprint breaks the ladder-rung look
            -- without spanning neighbouring plow bodies sideways. Density-
            -- pixel factors keep the shape consistent on base and 4x maps.
            cellLengthM = 0.50,
            cellWidthM = 0.50,
            cellLengthDensityPixels = 2.00,
            cellWidthDensityPixels = 1.00,
            -- All overlapping WorkAreas are collected and written once in the
            -- final same-frame post-pass. No trailing distance is required.
            trailingCommitGuardDensityPixels = 0.00,
            -- Rank cells inside independently scrambled 3x3 world-raster
            -- blocks. At low coverage this yields roughly one well-separated
            -- spot per block instead of hash clusters following plow geometry.
            visualStratificationSize = 3,
            -- Surface-quality degradation. Between realistic and shop speed
            -- an increasing fraction of isolated cells keeps the cultivated
            -- texture while its original PLOW_LEVEL is restored immediately.
            -- It therefore looks poorly turned without becoming a gameplay
            -- dropout. True missing plow work starts only above shop speed.
            twistedFractionAtShopSpeed = 0.10,
            maximumTwistedFraction = 0.75,
            -- A light warning starts above realistic speed, while the much
            -- smaller cells prevent that warning from dominating the field.
            frequencyExponentToShop = 1.30,
            -- Above shop speed use a normalized exponential squared curve.
            -- The target is surface coverage, not candidate frequency; the
            -- writer compensates for every 1x2 patch occupying two pixels.
            visualNoiseCurveStrength = 3.00,
            randomPlowFraction = 0.40,
            patternSalt = 8831,
            angleSalt = 14591,
            -- Keep the broken furrows close to the actual driving direction
            -- just above shop speed. The available angle range opens
            -- progressively and reaches fully chaotic orientations at the
            -- configured ratio. 0.50 means up to half of the circular angle
            -- range in either direction, i.e. every engine-supported angle.
            fullAngleSpreadRatio = 2.00,
            angleSpreadExponentToShop = 1.10,
            angleSpreadExponentAboveShop = 1.20,
            shopAngleDeviationFraction = 0.25,
            maximumAngleDeviationFraction = 0.50
        },
        maximumPatternLanes = 48,
        maximumFailedFraction = 0.45,
        -- True PLOW_LEVEL failures are deliberately separate from the visual
        -- surface noise. A normalized exponential squared curve yields about
        -- 1.4% at 1.1x, 8% at 1.25x, 25% at 1.5x and 45% at 2x shop speed.
        gameplayFailureMaximumFraction = 0.45,
        gameplayFailureCurveStrength = 3.00,
        -- Mechanical stone events still use a short share-lane latch. The
        -- continuous speed-quality failure subset is committed through the
        -- world-density-raster noise path instead of these lanes.
        patternLengthM = 1.00,
        persistenceMarginM = 0.35,
        maximumPersistenceDistanceM = 2.50,
        -- All plow WorkAreas share one lateral coordinate system. This is
        -- essential for multi-part plows: otherwise a rear WorkArea can fill
        -- the gap left by the front WorkArea and only a small island remains.
        useCombinedPlowWidth = true,
        triggers = {
            medium = {
                minimumDistanceM = 2.5,
                maximumDistanceM = 5.5,
                minimumSegments = 1,
                maximumSegments = 1,
                maximumWanderSegments = 0.75,
                wanderCycles = 0.45
            },
            big = {
                minimumDistanceM = 4.0,
                maximumDistanceM = 8.0,
                minimumSegments = 2,
                maximumSegments = 2,
                separateSegments = true,
                maximumWanderSegments = 1.00,
                wanderCycles = 0.55
            },
            -- Not a stone hit: excessive forward speed throws soil too far or
            -- lets one body briefly lose a clean furrow. These are deliberately
            -- narrow and become frequent rather than wide at extreme speed.
            overspeedThrow = {
                minimumDistanceM = 0.45,
                maximumDistanceM = 0.90,
                minimumSegments = 1,
                maximumSegments = 1,
                -- A normal overlap on the next bout most often covers an
                -- outer body. Keep speed-quality failures on inner bodies;
                -- real medium/big stone impacts remain unrestricted.
                protectOuterSegments = true,
                -- Speed-quality faults stay on one share. Sideways wandering
                -- created the diagonal hook/zig-zag pattern visible on the
                -- PLOW_LEVEL overlay and did not resemble a failed furrow.
                maximumWanderSegments = 0.0,
                wanderCycles = 0.0
            }
        },
        overspeedThrow = {
            -- Sparse, distance-based surface defects. Each event writes one
            -- raster-aligned CULTIVATED patch after every Vanilla plow
            -- WorkArea has finished. There is no continuous raster scan.
            activationMarginKph = 0.05,
            candidateSpacingM = 1.00,
            minimumPatchChance = 0.05,
            maximumPatchChance = 0.80,
            patchChanceExponent = 1.20,
            maximumCandidatesPerFrame = 16,
            maximumEventsPerWorkAreaPass = 2,
            maximumPendingEvents = 4,
            lateralBandWidthM = 2.00,
            maximumLateralBands = 8,
            candidateSalt = 31847,
            lateralSalt = 41777,
            -- Every mark spans exactly two adjacent density pixels so the
            -- terrain raster cannot swallow a 1x1 area.
            patchDensityPixels = 2
        }
    }
}

-- Profile access and quality curves ----------------------------------------

-- Returns one immutable-by-convention profile shared by all matching tools.
function TerraLogicDropoutManager:getProfile(profileName)
    return self.PROFILES[profileName]
end

-- Resolves the two-stage plow-quality curve without touching the wear model:
-- realistic..shop affects cultivated surface-noise cells whose PLOW_LEVEL is
-- preserved; shop+ lets neighbouring cells merge and additionally permits
-- gameplay dropouts.
-- Returned angle steps remain available for the mixed texture inside genuine
-- failures and use GIANTS' map-independent discrete ground-angle range.
function TerraLogicDropoutManager:getPlowTextureQuality(
        profileName, currentSpeed, realisticSpeed, ratedSpeed, angleCount)
    local cfg = self:getProfile(profileName)
    local scatter = cfg ~= nil and cfg.plowTextureScatter or nil
    local current = math.max(tonumber(currentSpeed) or 0, 0)
    local rated = math.max(tonumber(ratedSpeed) or 0, 0.01)
    local realistic = math.clamp(
        tonumber(realisticSpeed) or rated,
        0,
        rated
    )
    if scatter == nil or scatter.enabled ~= true or current <= realistic then
        return {
            twistedFraction = 0,
            maximumDeviationSteps = 0,
            toShopProgress = 0,
            aboveShopProgress = 0,
            gameplayDropoutsAllowed = false
        }
    end

    local toShopProgress = 0
    if rated - realistic > 0.01 and current <= rated then
        toShopProgress = math.clamp(
            (current - realistic) / (rated - realistic),
            0,
            1
        )
    elseif current > rated then
        toShopProgress = 1
    end
    local fullSpreadRatio = math.max(
        tonumber(scatter.fullAngleSpreadRatio) or 2,
        1.01
    )
    local aboveShopProgress = math.clamp(
        (current / rated - 1) / (fullSpreadRatio - 1),
        0,
        1
    )
    local shopFraction = math.clamp(
        tonumber(scatter.twistedFractionAtShopSpeed) or 0,
        0,
        1
    )
    local maximumFraction = math.clamp(
        tonumber(scatter.maximumTwistedFraction) or shopFraction,
        shopFraction,
        1
    )
    local twistedFraction = shopFraction
        * toShopProgress ^ math.max(
            tonumber(scatter.frequencyExponentToShop) or 1,
            0.01
        )
    local noiseStrength = math.max(
        tonumber(scatter.visualNoiseCurveStrength) or 4,
        0.01
    )
    local fullExcess = math.max(fullSpreadRatio - 1, 0.01)
    local currentExcess = math.clamp(current / rated - 1, 0, fullExcess)
    local normalizedNoise = (1 - math.exp(
        -noiseStrength * currentExcess * currentExcess
    )) / math.max(
        1 - math.exp(-noiseStrength * fullExcess * fullExcess),
        0.0001
    )
    twistedFraction = twistedFraction
        + (maximumFraction - shopFraction) * normalizedNoise

    local shopDeviation = math.clamp(
        tonumber(scatter.shopAngleDeviationFraction) or 0.125,
        0,
        0.5
    )
    local maximumDeviation = math.clamp(
        tonumber(scatter.maximumAngleDeviationFraction) or 0.5,
        shopDeviation,
        0.5
    )
    local deviationFraction = shopDeviation
        * toShopProgress ^ math.max(
            tonumber(scatter.angleSpreadExponentToShop) or 1,
            0.01
        )
    deviationFraction = deviationFraction
        + (maximumDeviation - shopDeviation)
            * aboveShopProgress ^ math.max(
                tonumber(scatter.angleSpreadExponentAboveShop) or 1,
                0.01
            )
    local count = math.max(math.floor(tonumber(angleCount) or 1), 1)
    local maximumDeviationSteps = math.min(
        math.floor(count * deviationFraction + 0.5),
        math.floor(count * 0.5)
    )
    -- A selected bad cell must visibly differ. At small quality losses this
    -- produces rare one-step rotations instead of many invisible rewrites.
    if twistedFraction > 0 and maximumDeviationSteps < 1 then
        maximumDeviationSteps = 1
    end

    local activationMargin = cfg.overspeedThrow ~= nil
        and math.max(
            tonumber(cfg.overspeedThrow.activationMarginKph) or 0,
            0
        ) or 0
    return {
        twistedFraction = math.clamp(twistedFraction, 0, 1),
        maximumDeviationSteps = maximumDeviationSteps,
        toShopProgress = toShopProgress,
        aboveShopProgress = aboveShopProgress,
        gameplayDropoutsAllowed = current > rated + activationMargin
    }
end

function TerraLogicDropoutManager:getPlowGameplayFailureFraction(
        profileName, currentSpeed, ratedSpeed)
    local cfg = self:getProfile(profileName)
    local current = math.max(tonumber(currentSpeed) or 0, 0)
    local rated = math.max(tonumber(ratedSpeed) or 0, 0.01)
    local activationMargin = cfg ~= nil and cfg.overspeedThrow ~= nil
        and math.max(
            tonumber(cfg.overspeedThrow.activationMarginKph) or 0,
            0
        ) or 0
    if cfg == nil or current <= rated + activationMargin then
        return 0
    end

    local maximumFraction = math.clamp(
        tonumber(cfg.gameplayFailureMaximumFraction)
            or tonumber(cfg.maximumFailedFraction) or 0.45,
        0,
        1
    )
    local strength = math.max(
        tonumber(cfg.gameplayFailureCurveStrength) or 3,
        0.01
    )
    local excess = math.clamp(current / rated - 1, 0, 1)
    local normalized = (1 - math.exp(-strength * excess * excess))
        / math.max(1 - math.exp(-strength), 0.0001)
    return math.clamp(maximumFraction * normalized, 0, maximumFraction)
end

-- Produces a deterministic pseudo-random value from map position and lane.
function TerraLogicDropoutManager:getPatternValue(x, z, laneIndex, salt, patternLength)
    local cellSize = math.max(tonumber(patternLength) or 2, 0.25)
    local cellX = math.floor((tonumber(x) or 0) / cellSize)
    local cellZ = math.floor((tonumber(z) or 0) / cellSize)
    local value = math.sin(
        cellX * 12.9898 + cellZ * 78.233
            + (tonumber(laneIndex) or 0) * 37.719
            + (tonumber(salt) or 0) * 11.131
    ) * 43758.5453
    return value - math.floor(value)
end

function TerraLogicDropoutManager:getStratifiedPatternValue(
        pixelX, pixelZ, salt, blockSize, blockCache)
    local size = math.clamp(
        math.floor(tonumber(blockSize) or 3),
        2,
        8
    )
    local count = size * size
    local x = math.floor(tonumber(pixelX) or 0)
    local z = math.floor(tonumber(pixelZ) or 0)
    local blockX = math.floor(x / size)
    local blockZ = math.floor(z / size)
    local localX = x - blockX * size
    local localZ = z - blockZ * size
    local localIndex = localZ * size + localX
    local normalizedSalt = tonumber(salt) or 0
    local cacheKey = string.format(
        "%d:%d:%d:%d",
        blockX,
        blockZ,
        size,
        math.floor(normalizedSalt)
    )
    local block = blockCache ~= nil and blockCache[cacheKey] or nil
    if block == nil then
        local shift = math.floor(
            self:getPatternValue(
                blockX, blockZ, 0, normalizedSalt + 101, 1
            ) * count
        )
        -- Choose a block-specific stride that is coprime with count so every
        -- local cell receives one unique rank.
        local stride = math.floor(
            self:getPatternValue(
                blockX, blockZ, 0, normalizedSalt + 211, 1
            ) * count
        ) + 1
        while true do
            local a, b = stride, count
            while b ~= 0 do
                a, b = b, a % b
            end
            if a == 1 then
                break
            end
            stride = stride + 1
            if stride > count then
                stride = 1
            end
        end
        block = {shift = shift, stride = stride}
        if blockCache ~= nil then
            blockCache[cacheKey] = block
        end
    end
    local rank = (localIndex * block.stride + block.shift) % count
    local jitter = self:getPatternValue(
        x, z, 0, normalizedSalt + 307, 1
    )
    return (rank + jitter) / count
end

function TerraLogicDropoutManager:getQualityFromThreshold(
        spec, profileName, currentSpeed, damage)
    local cfg = self:getProfile(profileName)
    if cfg == nil then
        return 1, 0, 0, 1, 0, 0
    end

    local speed = math.max(tonumber(currentSpeed) or 0, 0)
    local rated = tonumber(spec.ratedSpeed) or 0
    local optimal = tonumber(spec.optimalSpeed) or rated
    local conditionDamage = math.clamp(tonumber(damage) or 0, 0, 1)
    if rated <= 0 then
        return 1, 0, 0, 1 - conditionDamage, 0, 0
    end

    local thresholdFloor = optimal > 0 and optimal < rated
        and optimal
        or rated * math.clamp(cfg.fallbackMinimumThresholdRatio or 0.75, 0.1, 1)
    local thresholdShift = (rated - thresholdFloor) * conditionDamage
        * math.max(tonumber(cfg.damageThresholdShift) or 1, 0)
    local thresholdSpeed = math.clamp(rated - thresholdShift, thresholdFloor, rated)

    local speedPenalty = 0
    if speed > thresholdSpeed then
        local excess = speed / thresholdSpeed - 1
        local referenceExcess = math.max(cfg.overspeedReferenceRatio - 1, 0.01)
        speedPenalty = (cfg.overspeedLinearPenaltyPerExcess or 0) * excess
            + cfg.overspeedPenaltyAtReference
                * (excess / referenceExcess) ^ cfg.overspeedExponent
    end

    return math.clamp(1 - speedPenalty, 0, 1),
        0, speedPenalty, 1 - conditionDamage, thresholdSpeed, thresholdShift
end

local function sortStrongestFirst(a, b)
    return a.patternValue > b.patternValue
end

-- Selects spatially distributed lanes while keeping the requested fraction.
function TerraLogicDropoutManager:selectFailedLanes(
        profileName, lanes, geometry, quality, speedRatio, salt)
    local cfg = self:getProfile(profileName)
    if cfg == nil then
        return {}, {mode = "inactive", laneCap = 0, fullWidthChance = 0}
    end

    local candidates = {}
    for laneIndex, lane in ipairs(lanes) do
        lane.patternIndex = laneIndex
        lane.patternValue = self:getPatternValue(
            lane.centerX, lane.centerZ, laneIndex, salt, cfg.patternLengthM
        )
        if lane.patternValue >= quality then
            candidates[#candidates + 1] = lane
        end
    end

    if cfg.patternType ~= "stagedLanes" then
        return candidates, {
            mode = cfg.patternType or "independentCells",
            laneCap = #lanes,
            fullWidthChance = 0
        }
    end

    table.sort(candidates, sortStrongestFirst)
    local ratio = math.max(tonumber(speedRatio) or 0, 0)
    local laneCap
    local mode
    if ratio <= cfg.singleLaneMaximumSpeedRatio then
        laneCap = 1
        mode = "single-lane"
    elseif ratio <= cfg.multiLaneMaximumSpeedRatio then
        laneCap = math.max(1, math.ceil(
            #lanes * math.clamp(cfg.multiLaneMaximumFraction or 0.5, 0, 1)
        ))
        mode = "multi-lane"
    else
        laneCap = math.max(1, #lanes - 1)
        mode = "extreme"
    end

    local fullWidthChance = 0
    local fullWidthStart = math.max(cfg.fullWidthStartSpeedRatio or 1.5, 1)
    if ratio > fullWidthStart then
        local spanToDouble = math.max(2 - fullWidthStart, 0.01)
        local progression = (ratio - fullWidthStart) / spanToDouble
        fullWidthChance = math.min(
            math.max(cfg.fullWidthMaximumChance or 0.05, 0),
            math.max(cfg.fullWidthChanceAtDoubleSpeed or 0.015, 0)
                * progression ^ math.max(cfg.fullWidthChanceExponent or 2, 0.1)
        )
    end

    local centerX = geometry.xs + (geometry.widthX + geometry.heightX) / 3
    local centerZ = geometry.zs + (geometry.widthZ + geometry.heightZ) / 3
    local fullWidthValue = self:getPatternValue(
        centerX, centerZ, 0, (tonumber(salt) or 0) + 7919, cfg.patternLengthM
    )
    if fullWidthChance > 0 and fullWidthValue >= 1 - fullWidthChance then
        local allLanes = {}
        for _, lane in ipairs(lanes) do
            allLanes[#allLanes + 1] = lane
        end
        return allLanes, {
            mode = "rare full-width",
            laneCap = #lanes,
            fullWidthChance = fullWidthChance
        }
    end

    local failures = {}
    for candidateIndex = 1, math.min(#candidates, laneCap) do
        failures[#failures + 1] = candidates[candidateIndex]
    end
    return failures, {
        mode = mode,
        laneCap = laneCap,
        fullWidthChance = fullWidthChance
    }
end

-- Samples both successful and failed patches for a minimum travel distance.
-- Latching successful patches is important: otherwise repeated WorkArea calls
-- would keep rolling until a failure occurs and bias the configured quality.
function TerraLogicDropoutManager:selectLatchedFailedLanes(
        profileName, latch, lanes, geometry, quality, speedRatio, salt)
    local cfg = self:getProfile(profileName)
    if cfg == nil or geometry == nil then
        return {}, {mode = "inactive", laneCap = 0, fullWidthChance = 0}, nil, {
            workAreaDepthM = 0,
            holdDistanceM = 0,
            remainingDistanceM = 0,
            effectiveLaneWidthM = 0,
            missedFraction = 0,
            reused = false
        }
    end

    local centerX = geometry.xs + (geometry.widthX + geometry.heightX) / 3
    local centerZ = geometry.zs + (geometry.widthZ + geometry.heightZ) / 3
    local depthM = math.sqrt(
        geometry.heightX * geometry.heightX + geometry.heightZ * geometry.heightZ
    )
    local widthM = math.sqrt(
        geometry.widthX * geometry.widthX + geometry.widthZ * geometry.widthZ
    )
    local holdDistanceM = math.max(
        tonumber(cfg.patternLengthM) or 2,
        depthM + math.max(tonumber(cfg.persistenceMarginM) or 0, 0)
    )
    holdDistanceM = math.min(
        holdDistanceM,
        math.max(tonumber(cfg.maximumPersistenceDistanceM) or holdDistanceM, 0.25)
    )

    local normalizedSalt = tonumber(salt) or 0
    local reusable = latch ~= nil
        and latch.profileName == profileName
        and latch.salt == normalizedSalt
        and latch.startX ~= nil and latch.startZ ~= nil
    local distanceM = math.huge
    if reusable then
        local dx, dz = centerX - latch.startX, centerZ - latch.startZ
        distanceM = math.sqrt(dx * dx + dz * dz)
        reusable = distanceM < (tonumber(latch.holdDistanceM) or holdDistanceM)
    end

    local failedLanes = {}
    local selection
    if reusable then
        local used = {}
        for _, normalizedPosition in ipairs(latch.failedNormalizedPositions or {}) do
            local laneIndex = math.clamp(
                math.floor(normalizedPosition * geometry.lanes) + 1,
                1,
                geometry.lanes
            )
            if not used[laneIndex] then
                used[laneIndex] = true
                local lane = lanes[laneIndex]
                lane.patternIndex = laneIndex
                failedLanes[#failedLanes + 1] = lane
            end
        end
        selection = {
            mode = (latch.mode or "latched") .. " (latched)",
            laneCap = latch.laneCap or 0,
            fullWidthChance = latch.fullWidthChance or 0
        }
    else
        failedLanes, selection = self:selectFailedLanes(
            profileName, lanes, geometry, quality, speedRatio, normalizedSalt
        )
        local positions = {}
        for _, lane in ipairs(failedLanes) do
            positions[#positions + 1] =
                ((lane.patternIndex or 1) - 0.5) / math.max(geometry.lanes, 1)
        end
        latch = {
            profileName = profileName,
            salt = normalizedSalt,
            startX = centerX,
            startZ = centerZ,
            holdDistanceM = holdDistanceM,
            failedNormalizedPositions = positions,
            mode = selection.mode,
            laneCap = selection.laneCap,
            fullWidthChance = selection.fullWidthChance
        }
        distanceM = 0
    end

    local activeHoldDistance = tonumber(latch.holdDistanceM) or holdDistanceM
    return failedLanes, selection, latch, {
        workAreaDepthM = depthM,
        holdDistanceM = activeHoldDistance,
        remainingDistanceM = math.max(activeHoldDistance - distanceM, 0),
        effectiveLaneWidthM = widthM / math.max(geometry.lanes, 1),
        missedFraction = #failedLanes / math.max(geometry.lanes, 1),
        reused = reusable
    }
end

-- Starts or extends an impact-driven mechanical dropout. Positions are kept
-- normalized so one state works with mod implements of any width and with
-- WorkAreas whose actual density-map width differs slightly from the model.
-- Starts a temporary mechanical dropout after a sufficiently strong impact.
function TerraLogicDropoutManager:triggerImpactDropout(
        profileName, state, impactTier, speedRatio)
    local cfg = self:getProfile(profileName)
    local trigger = cfg ~= nil and cfg.triggers ~= nil
        and cfg.triggers[impactTier] or nil
    if cfg == nil or cfg.enabled ~= true or trigger == nil then
        return state, false
    end

    local ratioProgress = math.clamp(
        ((tonumber(speedRatio) or 1) - 1) / 1.0,
        0,
        1
    )
    local minimumDistance = math.max(tonumber(trigger.minimumDistanceM) or 0, 0)
    local maximumDistance = math.max(
        tonumber(trigger.maximumDistanceM) or minimumDistance,
        minimumDistance
    )
    local holdDistance = minimumDistance
        + (maximumDistance - minimumDistance) * ratioProgress
    local minimumSegments = math.max(
        math.floor(tonumber(trigger.minimumSegments) or 1),
        1
    )
    local maximumSegments = math.max(
        math.floor(tonumber(trigger.maximumSegments) or minimumSegments),
        minimumSegments
    )
    local segmentCount = math.random(minimumSegments, maximumSegments)
    local center = math.random()

    if state == nil or state.profileName ~= profileName
        or (tonumber(state.remainingDistanceM) or 0) <= 0 then
        state = {
            profileName = profileName,
            failures = {},
            remainingDistanceM = 0,
            holdDistanceM = 0,
            triggerCount = 0
        }
    end
    local function addFailure(failureCenter, failureSegmentCount)
        state.failures[#state.failures + 1] = {
            center = failureCenter,
            segmentCount = failureSegmentCount,
            tier = impactTier,
            remainingDistanceM = holdDistance,
            holdDistanceM = holdDistance,
            -- A speed-dependent sideways walk makes the missed strip resemble
            -- an unstable furrow / changing throw distance instead of a
            -- rectangular unworked island.
            wanderSegments = math.max(
                tonumber(trigger.maximumWanderSegments) or 0,
                0
            ) * ratioProgress,
            wanderCycles = math.max(tonumber(trigger.wanderCycles) or 0.5, 0),
            wanderPhase = math.random() * math.pi * 2
        }
    end
    if trigger.separateSegments == true and segmentCount > 1 then
        local offset = math.random()
        for segmentIndex = 1, segmentCount do
            addFailure(
                (offset + (segmentIndex - 1) / segmentCount) % 1,
                1
            )
        end
    else
        addFailure(center, segmentCount)
    end
    state.remainingDistanceM = math.max(
        tonumber(state.remainingDistanceM) or 0,
        holdDistance
    )
    state.holdDistanceM = math.max(
        tonumber(state.holdDistanceM) or 0,
        holdDistance
    )
    state.triggerCount = (state.triggerCount or 0) + 1
    state.lastTier = impactTier
    return state, true
end

function TerraLogicDropoutManager:advanceImpactDropout(
        profileName, state, travelledDistanceM)
    if state == nil or state.profileName ~= profileName then
        return nil
    end
    local travelled = math.max(tonumber(travelledDistanceM) or 0, 0)
    local activeFailures = {}
    local maximumRemaining = 0
    for _, failure in ipairs(state.failures or {}) do
        failure.remainingDistanceM = math.max(
            (tonumber(failure.remainingDistanceM) or 0) - travelled,
            0
        )
        if failure.remainingDistanceM > 0 then
            activeFailures[#activeFailures + 1] = failure
            maximumRemaining = math.max(
                maximumRemaining,
                failure.remainingDistanceM
            )
        end
    end
    state.failures = activeFailures
    state.remainingDistanceM = maximumRemaining
    if #activeFailures == 0 then
        return nil
    end
    state.lastTier = activeFailures[#activeFailures].tier or state.lastTier
    return state
end

-- Converts normalized impact positions into density-map lanes. Adjacent and
-- overlapping failures are merged by the caller into successful lane runs.
function TerraLogicDropoutManager:getImpactFailedLanes(
        profileName, state, geometry)
    local cfg = self:getProfile(profileName)
    if cfg == nil or state == nil or geometry == nil
        or state.profileName ~= profileName
        or (tonumber(state.remainingDistanceM) or 0) <= 0 then
        return {}, {}
    end

    local failedIndexes = {}
    local failedCount = 0
    local maximumFailed = math.max(
        math.floor(
            geometry.lanes
                * math.clamp(tonumber(cfg.maximumFailedFraction) or 1, 0, 1)
        ),
        1
    )
    for _, failure in ipairs(state.failures or {}) do
        local count = math.clamp(
            math.floor(tonumber(failure.segmentCount) or 1),
            1,
            geometry.lanes
        )
        local holdDistance = math.max(
            tonumber(failure.holdDistanceM)
                or tonumber(state.holdDistanceM) or 0,
            0.001
        )
        local travelledProgress = math.clamp(
            1 - (tonumber(failure.remainingDistanceM) or 0) / holdDistance,
            0,
            1
        )
        local wanderNormalized = (tonumber(failure.wanderSegments) or 0)
            / math.max(geometry.lanes, 1)
            * math.sin(
                (tonumber(failure.wanderPhase) or 0)
                    + travelledProgress * math.pi * 2
                        * (tonumber(failure.wanderCycles) or 0.5)
            )
        local dynamicCenter = math.clamp(
            (tonumber(failure.center) or 0.5) + wanderNormalized,
            0,
            0.999999
        )
        local centerIndex = math.clamp(
            math.floor(dynamicCenter * geometry.lanes) + 1,
            1,
            geometry.lanes
        )
        local failureTrigger = cfg.triggers ~= nil
            and cfg.triggers[failure.tier] or nil
        if failureTrigger ~= nil
            and failureTrigger.protectOuterSegments == true
            and geometry.lanes >= 3 then
            centerIndex = math.clamp(centerIndex, 2, geometry.lanes - 1)
        end
        local firstIndex = math.clamp(
            centerIndex - math.floor((count - 1) / 2),
            1,
            math.max(geometry.lanes - count + 1, 1)
        )
        for laneIndex = firstIndex, math.min(firstIndex + count - 1, geometry.lanes) do
            if not failedIndexes[laneIndex] and failedCount < maximumFailed then
                failedIndexes[laneIndex] = true
                failedCount = failedCount + 1
            end
        end
    end

    local failedLanes = {}
    for laneIndex = 1, geometry.lanes do
        if failedIndexes[laneIndex] then
            failedLanes[#failedLanes + 1] = laneIndex
        end
    end
    return failedLanes, failedIndexes
end
