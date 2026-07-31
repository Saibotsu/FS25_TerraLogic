--[[
    TerraLogicSettings.lua
    Savegame settings, in-game options and multiplayer synchronization.

    Copyright (c) 2026 The Mod Workshop. All rights reserved.
    Unauthorized copying, modification, or redistribution is prohibited
    except where expressly permitted by the copyright owner.

    Source fingerprint: TMW-TL-SET-1.200317
]]

TerraLogicSettings = {
    DRAFT_TERRALOGIC = "terraLogic",
    DRAFT_MR = "mr",
    VISIBLE_STONES_VANILLA = "vanilla",
    VISIBLE_STONES_TERRALOGIC = "terraLogic",
    draftModel = "terraLogic",
    visibleStoneDamageModel = "terraLogic",
    physicalDropoutsEnabled = true,
    showQualityText = true,
    speedHudMode = "dynamic",
    menuInstalled = false
}
-- Numeric source signature only; it is deliberately excluded from gameplay math.
TerraLogicSettings.SOURCE_FINGERPRINT = 1.200317

TerraLogicLogging = TerraLogicLogging or {verbose = false}

-- Public legacy aliases keep integrations and older diagnostic snippets
-- working after the TerraLogic rename. New code uses the TerraLogic names.
OverSpeedDamageSettings = TerraLogicSettings
OSDLogging = TerraLogicLogging

-- Emits detailed diagnostics only after the player enables verbose logging.
function TerraLogicLogging.debug(message, ...)
    if TerraLogicLogging.verbose then
        Logging.info(message, ...)
    end
end

-- Persistence helpers -------------------------------------------------------

-- Returns the current and legacy savegame setting paths.
local function getSettingsPath()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local directory = missionInfo ~= nil and missionInfo.savegameDirectory or nil
    if directory == nil or directory == "" then return nil end
    return directory .. "/terraLogicSettings.xml",
        directory .. "/overSpeedDamageSettings.xml"
end

local function getLocalSettingsPath()
    if getUserProfileAppPath == nil then return nil end
    local directory = getUserProfileAppPath() .. "modSettings"
    return directory .. "/FS25_TerraLogic.xml", directory,
        directory .. "/FS25_OverSpeedDamage.xml"
end

-- Loads client-only HUD preferences that do not affect multiplayer gameplay.
function TerraLogicSettings:loadLocal()
    local path, _, legacyPath = getLocalSettingsPath()
    if path == nil then return end
    local migrated = false
    if not fileExists(path) then
        if legacyPath == nil or not fileExists(legacyPath) then return end
        path = legacyPath
        migrated = true
    end
    local xml = loadXMLFile("terraLogicLocalSettings", path)
    if xml ~= nil and xml ~= 0 then
        self.showQualityText = Utils.getNoNil(
            getXMLBool(xml, "settings#showQualityText"), true)
        local mode = string.lower(tostring(
            getXMLString(xml, "settings#speedHudMode") or "dynamic"))
        self.speedHudMode = (mode == "always" or mode == "off")
            and mode or "dynamic"
        delete(xml)
    end
    if migrated then self:saveLocal() end
end

-- Saves client-only HUD preferences outside the savegame.
function TerraLogicSettings:saveLocal()
    local path, directory = getLocalSettingsPath()
    if path == nil then return end
    if not fileExists(directory) and createFolder ~= nil then
        createFolder(directory)
    end
    local xml = createXMLFile("terraLogicLocalSettings", path, "settings")
    if xml ~= nil and xml ~= 0 then
        setXMLBool(xml, "settings#showQualityText", self.showQualityText == true)
        setXMLString(xml, "settings#speedHudMode", self.speedHudMode)
        saveXMLFile(xml)
        delete(xml)
    end
end

-- Detects whether More Realistic is active in the current mission.
function TerraLogicSettings:isMoreRealisticActive()
    return PowerConsumer ~= nil
        and type(PowerConsumer.mrGetDraftForceMultiplier) == "function"
        and type(PowerConsumer.mrGetForceMultiplier) == "function"
end

-- Resolves the selected draft provider with a safe TerraLogic fallback.
function TerraLogicSettings:getEffectiveDraftModel()
    if self.draftModel == self.DRAFT_MR and self:isMoreRealisticActive() then
        return self.DRAFT_MR
    end
    return self.DRAFT_TERRALOGIC
end

function TerraLogicSettings:getPhysicalDropoutsEnabled()
    return self.physicalDropoutsEnabled ~= false
end

function TerraLogicSettings:getVisibleStoneDamageModel()
    return self.visibleStoneDamageModel == self.VISIBLE_STONES_VANILLA
        and self.VISIBLE_STONES_VANILLA or self.VISIBLE_STONES_TERRALOGIC
end

function TerraLogicSettings:applyVisibleStoneDamageModel(value)
    value = string.lower(tostring(value or ""))
    if value ~= self.VISIBLE_STONES_VANILLA then
        value = self.VISIBLE_STONES_TERRALOGIC
    end
    self.visibleStoneDamageModel = value
    if self.visibleStoneDamageOption ~= nil then
        self.visibleStoneDamageOption:setState(
            value == self.VISIBLE_STONES_TERRALOGIC and 2 or 1)
    end
end

function TerraLogicSettings:applyPhysicalDropoutsEnabled(value)
    self.physicalDropoutsEnabled = value ~= false
    if self.physicalDropoutsOption ~= nil then
        self.physicalDropoutsOption:setState(
            self.physicalDropoutsEnabled and 2 or 1)
    end
end

function TerraLogicSettings:applyDraftModel(value)
    value = string.lower(tostring(value or ""))
    if value ~= self.DRAFT_MR then value = self.DRAFT_TERRALOGIC end
    if value == self.DRAFT_MR and not self:isMoreRealisticActive() then
        value = self.DRAFT_TERRALOGIC
    end
    self.draftModel = value
    if self.menuOption ~= nil then
        self.menuOption:setState(value == self.DRAFT_MR and 2 or 1)
    end
end

-- Loads synchronized gameplay settings and migrates legacy OSD settings.
function TerraLogicSettings:load()
    self:loadLocal()
    local default = self:isMoreRealisticActive() and self.DRAFT_MR or self.DRAFT_TERRALOGIC
    self:applyDraftModel(default)
    self:applyPhysicalDropoutsEnabled(true)
    self:applyVisibleStoneDamageModel(self.VISIBLE_STONES_TERRALOGIC)
    local path, legacyPath = getSettingsPath()
    if path == nil then return end
    local migrated = false
    if not fileExists(path) then
        if legacyPath == nil or not fileExists(legacyPath) then return end
        path = legacyPath
        migrated = true
    end
    local xml = loadXMLFile("osdSettings", path)
    if xml ~= nil and xml ~= 0 then
        self:applyDraftModel(getXMLString(xml, "settings#draftModel") or default)
        self:applyPhysicalDropoutsEnabled(Utils.getNoNil(
            getXMLBool(xml, "settings#physicalDropoutsEnabled"), true))
        self:applyVisibleStoneDamageModel(
            getXMLString(xml, "settings#visibleStoneDamageModel")
                or self.VISIBLE_STONES_TERRALOGIC)
        delete(xml)
    end
    if migrated then self:save() end
end

-- Saves server-owned gameplay settings and the local player's HUD choices.
function TerraLogicSettings:save()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local path = getSettingsPath()
    if path == nil then return end
    local xml = createXMLFile("osdSettings", path, "settings")
    if xml ~= nil and xml ~= 0 then
        setXMLString(xml, "settings#draftModel", self.draftModel)
        setXMLBool(xml, "settings#physicalDropoutsEnabled",
            self.physicalDropoutsEnabled ~= false)
        setXMLString(xml, "settings#visibleStoneDamageModel",
            self:getVisibleStoneDamageModel())
        saveXMLFile(xml)
        delete(xml)
    end
end

-- Returns whether this client may change synchronized multiplayer settings.
function TerraLogicSettings:isLocalAdmin()
    return g_server ~= nil
        or (g_currentMission ~= nil and g_currentMission.isMasterUser == true)
end

function TerraLogicSettings:setFromMenu(value)
    if not self:isLocalAdmin() then return end
    if g_server ~= nil then
        self:applyDraftModel(value)
        self:save()
        g_server:broadcastEvent(TerraLogicSettingsEvent.new(
            self.draftModel, self.physicalDropoutsEnabled,
            self.visibleStoneDamageModel))
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(TerraLogicSettingsEvent.new(
            value, self.physicalDropoutsEnabled,
            self.visibleStoneDamageModel))
    end
end

function TerraLogicSettings:setPhysicalDropoutsFromMenu(value)
    if not self:isLocalAdmin() then return end
    value = value ~= false
    if g_server ~= nil then
        self:applyPhysicalDropoutsEnabled(value)
        self:save()
        g_server:broadcastEvent(TerraLogicSettingsEvent.new(
            self.draftModel, self.physicalDropoutsEnabled,
            self.visibleStoneDamageModel))
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(TerraLogicSettingsEvent.new(
            self.draftModel, value, self.visibleStoneDamageModel))
    end
end

function TerraLogicSettings:setVisibleStoneDamageModelFromMenu(value)
    if not self:isLocalAdmin() then return end
    value = value == self.VISIBLE_STONES_VANILLA
        and self.VISIBLE_STONES_VANILLA or self.VISIBLE_STONES_TERRALOGIC
    if g_server ~= nil then
        self:applyVisibleStoneDamageModel(value)
        self:save()
        g_server:broadcastEvent(TerraLogicSettingsEvent.new(
            self.draftModel, self.physicalDropoutsEnabled,
            self.visibleStoneDamageModel))
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(TerraLogicSettingsEvent.new(
            self.draftModel, self.physicalDropoutsEnabled, value))
    end
end

TerraLogicSettingsMenuCallbacks = {}

-- Menu callbacks ------------------------------------------------------------

-- Forwards the draft-model selection from the options menu.
function TerraLogicSettingsMenuCallbacks:onDraftModelChanged(state)
    TerraLogicSettings:setFromMenu(state == 2 and "mr" or "terraLogic")
end

function TerraLogicSettingsMenuCallbacks:onPhysicalDropoutsChanged(state)
    TerraLogicSettings:setPhysicalDropoutsFromMenu(state == 2)
end

function TerraLogicSettingsMenuCallbacks:onVisibleStoneDamageChanged(state)
    TerraLogicSettings:setVisibleStoneDamageModelFromMenu(
        state == 1 and "vanilla" or "terraLogic")
end

function TerraLogicSettingsMenuCallbacks:onQualityTextChanged(state)
    TerraLogicSettings.showQualityText = state == 2
    TerraLogicSettings:saveLocal()
end

function TerraLogicSettingsMenuCallbacks:onSpeedHudModeChanged(state)
    TerraLogicSettings.speedHudMode = ({
        "dynamic", "always", "off"
    })[state] or "dynamic"
    TerraLogicSettings:saveLocal()
end

-- Repairs focus IDs after dynamically inserting controls into the menu.
local function updateFocusIds(element)
    if element == nil then return end
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in pairs(element.elements or {}) do updateFocusIds(child) end
end

-- Adds TerraLogic controls to the in-game settings page when it is available.
function TerraLogicSettings:tryInstallMenu()
    if self.menuInstalled or g_gui == nil or g_gui.screenControllers == nil then
        return self.menuInstalled
    end
    local menu = g_gui.screenControllers[InGameMenu]
    local page = menu ~= nil and menu.pageSettings or nil
    if page == nil or page.gameSettingsLayout == nil
        or page.multiVolumeVoiceBox == nil then return false end

    TerraLogicSettingsMenuCallbacks.name = page.name
    local header
    for _, element in ipairs(page.gameSettingsLayout.elements or {}) do
        if element.name == "sectionHeader" then
            header = element:clone(page.gameSettingsLayout)
            break
        end
    end
    if header ~= nil then
        header:setText(g_i18n:getText("terraLogic_settingSection"))
        updateFocusIds(header)
        table.insert(page.controlsList, header)
    end

    local function addOption(id, callback, texts, state, titleKey, tooltipKey)
        local box = page.multiVolumeVoiceBox:clone(page.gameSettingsLayout)
        box.id = id .. "Box"
        local option = box.elements[1]
        option.id = id
        option.target = TerraLogicSettingsMenuCallbacks
        option:setCallback("onClickCallback", callback)
        option:setTexts(texts)
        option:setState(state)
        if option.elements ~= nil and option.elements[1] ~= nil then
            option.elements[1]:setText(g_i18n:getText(tooltipKey))
        end
        if box.elements[2] ~= nil then
            box.elements[2]:setText(g_i18n:getText(titleKey))
        end
        updateFocusIds(box)
        table.insert(page.controlsList, box)
        return option, box
    end

    self.menuOption, self.draftModelBox = addOption(
        "terraLogicDraftModel", "onDraftModelChanged",
        {g_i18n:getText("terraLogic_settingDraftTerraLogic"),
            g_i18n:getText("terraLogic_settingDraftMR")},
        self.draftModel == self.DRAFT_MR and 2 or 1,
        "terraLogic_settingDraftTitle", "terraLogic_settingDraftTooltip")
    self.draftModelBox:setVisible(self:isMoreRealisticActive())
    self.physicalDropoutsOption = addOption(
        "terraLogicPhysicalDropouts", "onPhysicalDropoutsChanged",
        {g_i18n:getText("terraLogic_settingOff"),
            g_i18n:getText("terraLogic_settingOn")},
        self.physicalDropoutsEnabled and 2 or 1,
        "terraLogic_settingPhysicalDropoutsTitle",
        "terraLogic_settingPhysicalDropoutsTooltip")
    self.visibleStoneDamageOption = addOption(
        "terraLogicVisibleStoneDamage", "onVisibleStoneDamageChanged",
        {g_i18n:getText("terraLogic_settingVisibleStonesVanilla"),
            g_i18n:getText("terraLogic_settingVisibleStonesTerraLogic")},
        self.visibleStoneDamageModel == self.VISIBLE_STONES_TERRALOGIC and 2 or 1,
        "terraLogic_settingVisibleStonesTitle",
        "terraLogic_settingVisibleStonesTooltip")
    self.qualityTextOption = addOption(
        "terraLogicQualityText", "onQualityTextChanged",
        {g_i18n:getText("terraLogic_settingOff"),
            g_i18n:getText("terraLogic_settingOn")},
        self.showQualityText and 2 or 1,
        "terraLogic_settingQualityTextTitle", "terraLogic_settingQualityTextTooltip")
    local speedHudState = self.speedHudMode == "always" and 2
        or (self.speedHudMode == "off" and 3 or 1)
    self.speedHudModeOption = addOption(
        "terraLogicSpeedHudMode", "onSpeedHudModeChanged",
        {g_i18n:getText("terraLogic_settingHudDynamic"),
            g_i18n:getText("terraLogic_settingHudAlways"),
            g_i18n:getText("terraLogic_settingHudOff")},
        speedHudState,
        "terraLogic_settingHudModeTitle", "terraLogic_settingHudModeTooltip")
    page.gameSettingsLayout:invalidateLayout()
    self.menuInstalled = true

    if InGameMenuSettingsFrame ~= nil
        and InGameMenuSettingsFrame.terraLogicAdminHookInstalled ~= true then
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen,
            function()
                local control = TerraLogicSettings.menuOption
                if control ~= nil then
                    control:setState(TerraLogicSettings.draftModel == "mr" and 2 or 1)
                    control:setDisabled(not TerraLogicSettings:isLocalAdmin())
                end
                local draftBox = TerraLogicSettings.draftModelBox
                if draftBox ~= nil then
                    draftBox:setVisible(
                        TerraLogicSettings:isMoreRealisticActive())
                end
                local dropoutsControl =
                    TerraLogicSettings.physicalDropoutsOption
                if dropoutsControl ~= nil then
                    dropoutsControl:setState(
                        TerraLogicSettings.physicalDropoutsEnabled
                            and 2 or 1)
                    dropoutsControl:setDisabled(
                        not TerraLogicSettings:isLocalAdmin())
                end
                local qualityControl = TerraLogicSettings.qualityTextOption
                local stoneControl =
                    TerraLogicSettings.visibleStoneDamageOption
                if stoneControl ~= nil then
                    stoneControl:setState(
                        TerraLogicSettings.visibleStoneDamageModel == "terraLogic"
                            and 2 or 1)
                    stoneControl:setDisabled(
                        not TerraLogicSettings:isLocalAdmin())
                end
                if qualityControl ~= nil then
                    qualityControl:setState(
                        TerraLogicSettings.showQualityText and 2 or 1)
                    qualityControl:setDisabled(false)
                end
                local hudControl = TerraLogicSettings.speedHudModeOption
                if hudControl ~= nil then
                    local mode = TerraLogicSettings.speedHudMode
                    hudControl:setState(mode == "always" and 2
                        or (mode == "off" and 3 or 1))
                    hudControl:setDisabled(false)
                end
                if TerraLogicSettings.draftModelBox ~= nil then
                    local parent = TerraLogicSettings.draftModelBox.parent
                    if parent ~= nil and parent.invalidateLayout ~= nil then
                        parent:invalidateLayout()
                    end
                end
            end
        )
        InGameMenuSettingsFrame.terraLogicAdminHookInstalled = true
    end
    return true
end

TerraLogicSettingsEvent = {}
OverSpeedDamageSettingsEvent = TerraLogicSettingsEvent
local TerraLogicSettingsEvent_mt = Class(TerraLogicSettingsEvent, Event)
InitEventClass(TerraLogicSettingsEvent, "TerraLogicSettingsEvent")

-- Multiplayer event ---------------------------------------------------------

-- Constructs an empty settings event for network deserialization.
function TerraLogicSettingsEvent.emptyNew()
    return Event.new(TerraLogicSettingsEvent_mt)
end

function TerraLogicSettingsEvent.new(
        draftModel, physicalDropoutsEnabled, visibleStoneDamageModel)
    local self = TerraLogicSettingsEvent.emptyNew()
    self.draftModel = draftModel == "mr" and "mr" or "terraLogic"
    self.physicalDropoutsEnabled = physicalDropoutsEnabled ~= false
    self.visibleStoneDamageModel = visibleStoneDamageModel == "vanilla"
        and "vanilla" or "terraLogic"
    return self
end

function TerraLogicSettingsEvent:readStream(streamId, connection)
    self.draftModel = streamReadUIntN(streamId, 1) == 1 and "mr" or "terraLogic"
    self.physicalDropoutsEnabled = streamReadUIntN(streamId, 1) == 1
    self.visibleStoneDamageModel = streamReadUIntN(streamId, 1) == 1
        and "terraLogic" or "vanilla"
    self:run(connection)
end

function TerraLogicSettingsEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.draftModel == "mr" and 1 or 0, 1)
    streamWriteUIntN(streamId, self.physicalDropoutsEnabled and 1 or 0, 1)
    streamWriteUIntN(streamId,
        self.visibleStoneDamageModel == "terraLogic" and 1 or 0, 1)
end

function TerraLogicSettingsEvent:run(connection)
    if connection:getIsServer() then
        TerraLogicSettings:applyDraftModel(self.draftModel)
        TerraLogicSettings:applyPhysicalDropoutsEnabled(
            self.physicalDropoutsEnabled)
        TerraLogicSettings:applyVisibleStoneDamageModel(
            self.visibleStoneDamageModel)
        return
    end
    local userManager = g_currentMission ~= nil and g_currentMission.userManager or nil
    local userId = userManager ~= nil and userManager:getUserIdByConnection(connection) or nil
    local user = userId ~= nil and userManager:getUserByUserId(userId) or nil
    if user == nil or not user:getIsMasterUser() then return end
    TerraLogicSettings:applyDraftModel(self.draftModel)
    TerraLogicSettings:applyPhysicalDropoutsEnabled(
        self.physicalDropoutsEnabled)
    TerraLogicSettings:applyVisibleStoneDamageModel(
        self.visibleStoneDamageModel)
    TerraLogicSettings:save()
    g_server:broadcastEvent(TerraLogicSettingsEvent.new(
        TerraLogicSettings.draftModel,
        TerraLogicSettings.physicalDropoutsEnabled,
        TerraLogicSettings.visibleStoneDamageModel), nil, connection)
end

if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil
    and FSBaseMission.terraLogicSettingsSyncHookInstalled ~= true then
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(
        FSBaseMission.sendInitialClientState,
        function(_, connection)
            if g_server ~= nil then
                connection:sendEvent(TerraLogicSettingsEvent.new(
                    TerraLogicSettings.draftModel,
                    TerraLogicSettings.physicalDropoutsEnabled,
                    TerraLogicSettings.visibleStoneDamageModel))
            end
        end
    )
    FSBaseMission.terraLogicSettingsSyncHookInstalled = true
end
