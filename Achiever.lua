local _G, _ = _G or getfenv()

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.0.2.1'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'
local ACHIEVER_STARTED = false
local ACHIEVER_INIT = false
local ACHIEVER_DATA_READY = false
local READY_QUIET = 3.0
local READY_HINT_AT = 20.0
local READY_MAX = 30.0
local STARTUP_DELAY = 8.0
local readyQuiet = 0
local readyWaited = 0
local readyHintShown = false
local uiGateInstalled = false
local startupTimer = nil
local inWorld = false

-- Biztosítjuk, hogy a táblák mindig létezzenek (SavedVariables előtt is).
local function ensureDB()
    if type(achieverDB) ~= 'table' then achieverDB = {} end
    if type(achieverDB.categories) ~= 'table' then
        achieverDB.categories = { version = -1, data = {}, byParent = {} }
    end
    if type(achieverDB.achievements) ~= 'table' then
        achieverDB.achievements = { version = -1, totalPoints = 0, data = {}, byCategory = {}, nextById = {}, previousById = {} }
    end
    if type(achieverDB.criteria) ~= 'table' then
        achieverDB.criteria = { version = -1, data = {}, byAchievement = {} }
    end
    if type(achieverDBpc) ~= 'table' then achieverDBpc = {} end
    if type(achieverDBpc.criteria) ~= 'table' then achieverDBpc.criteria = {} end
    if type(achieverDBpc.achievements) ~= 'table' then achieverDBpc.achievements = {} end
    if achieverDBpc.debug == nil then achieverDBpc.debug = "disabled" end
    if achieverDBpc.buttonmain == nil then achieverDBpc.buttonmain = "enabled" end
    if achieverDBpc.buttonsmall == nil then achieverDBpc.buttonsmall = "disabled" end
    if achieverDBpc.alert == nil then achieverDBpc.alert = "disabled" end -- loot CTD ellen alapból KI
end
ensureDB()

local function say(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
end
local function debug(msg)
    if achieverDBpc and achieverDBpc.debug == "enabled" then
        say('|cffc663fcDEBUG: |cffff55ff' .. tostring(msg or 'nil'))
    end
end
local function warn(msg)
    say('|cf3f3f66cWARN: |cffff55ff' .. tostring(msg or 'nil'))
end
local function safeUi(fn)
    if type(fn) ~= 'function' then return end
    local ok, err = pcall(fn)
    if not ok then warn('Achiever UI error: ' .. tostring(err)) end
end

local function toggleDebug()
    ensureDB()
    if achieverDBpc.debug == "enabled" then
        achieverDBpc.debug = "disabled"
        say('Achiever DEBUG mode disabled')
    else
        achieverDBpc.debug = "enabled"
        say('Achiever DEBUG mode enabled')
    end
end

SLASH_ACHIEVERDEBUG1 = "/acdebug"
SlashCmdList.ACHIEVERDEBUG = toggleDebug

SLASH_ACHIEVERALERT1 = "/acalert"
SlashCmdList.ACHIEVERALERT = function()
    ensureDB()
    if achieverDBpc.alert == "enabled" then
        achieverDBpc.alert = "disabled"
        say('Achiever alert popup disabled')
    else
        achieverDBpc.alert = "enabled"
        say('Achiever alert popup enabled (may crash on TBC!)')
    end
end

Achiever = CreateFrame("Frame")
SLASH_RELOADUI1 = "/rl"
SlashCmdList.RELOADUI = ReloadUI

local function split(str, sep)
    local res = {}
    if type(str) ~= 'string' then return res end
    sep = sep or ';'
    local first = 1
    while true do
        local pos = string.find(str, sep, first, true)
        if not pos then
            res[#res + 1] = string.sub(str, first)
            break
        end
        res[#res + 1] = string.sub(str, first, pos - 1)
        first = pos + 1
    end
    return res
end

local function tonum(v)
    if v == nil or v == '' or v == '_' then return nil end
    return tonumber(v)
end

Achiever:RegisterEvent("ADDON_LOADED")
Achiever:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Achiever:RegisterEvent("PLAYER_ENTERING_WORLD")
Achiever:RegisterEvent("VARIABLES_LOADED")
Achiever:RegisterEvent("CHAT_MSG_ADDON")
Achiever:RegisterEvent("CHAT_MSG_WHISPER")
Achiever:RegisterEvent("PLAYER_LEAVING_WORLD")

Achiever.version = ACHIEVER_ADDON_VERSION
Achiever.channel = ACHIEVER_ADDON_CHANNEL
Achiever.channelIndex = nil
Achiever.achievementFrameSummaryCategorySubscribers = {}

Achiever.processServerMessage = function(self, message)
    if type(message) ~= 'string' then return end
    ensureDB()
    readyQuiet = 0

    local params = split(message, '#')
    if params[1] ~= 'ACHI' then return end

    if params[2] == 'AC' then
        local a = split(params[3], ';')
        local id = tonum(a[1])
        if not id then return end
        local points = tonum(a[7]) or 0
        local categoryId = tonum(a[6])
        local order = tonum(a[8])
        achieverDB.achievements.data[id] = {
            id = id,
            faction = tonum(a[2]),
            previousId = tonum(a[3]),
            name = (a[4] == '_' or not a[4]) and '' or a[4],
            description = (a[5] == '_' or not a[5]) and '' or a[5],
            categoryId = categoryId,
            points = points,
            order = order,
            flags = tonum(a[9]),
            icon = tonum(a[10]),
            titleReward = (a[11] == '_' or not a[11]) and '' or a[11],
            count = tonum(a[12]),
            refAchievement = tonum(a[13]),
        }
        achieverDB.achievements.totalPoints = (achieverDB.achievements.totalPoints or 0) + points
        if categoryId and order then
            achieverDB.achievements.byCategory[categoryId] = achieverDB.achievements.byCategory[categoryId] or {}
            achieverDB.achievements.byCategory[categoryId][order] = id
        end
        local previousId = tonum(a[3])
        if previousId and previousId ~= 0 then
            achieverDB.achievements.previousById[id] = previousId
            achieverDB.achievements.nextById[previousId] = id
        end
        ACHIEVER_STARTED = true

    elseif params[2] == 'ACV' then
        achieverDB.achievements.version = tonum(params[3])
        ACHIEVER_STARTED = true

    elseif params[2] == 'CA' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        local parentId = tonum(a[2])
        local order = tonum(a[4])
        achieverDB.categories.data[id] = {
            id = id,
            parentId = parentId,
            name = (a[3] == '_' or not a[3]) and '' or a[3],
            order = order,
        }
        if parentId and order then
            achieverDB.categories.byParent[parentId] = achieverDB.categories.byParent[parentId] or {}
            achieverDB.categories.byParent[parentId][order] = id
        end
        ACHIEVER_STARTED = true

    elseif params[2] == 'CAV' then
        achieverDB.categories.version = tonum(params[3])
        ACHIEVER_STARTED = true

    elseif params[2] == 'CR' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        local achievementId = tonum(a[2])
        local order = tonum(a[15])
        achieverDB.criteria.data[id] = {
            id = id,
            achievementId = achievementId,
            type = tonum(a[3]),
            assetId = tonum(a[4]),
            count = tonum(a[5]),
            assetId1 = tonum(a[6]),
            count1 = tonum(a[7]),
            assetId2 = tonum(a[8]),
            count2 = tonum(a[9]),
            name = (a[10] == '_' or not a[10]) and '' or a[10],
            flags = tonum(a[11]),
            timedType = tonum(a[12]),
            timerStartEvent = tonum(a[13]),
            timeLimit = tonum(a[14]),
            order = order,
        }
        if achievementId and order then
            achieverDB.criteria.byAchievement[achievementId] = achieverDB.criteria.byAchievement[achievementId] or {}
            achieverDB.criteria.byAchievement[achievementId][order] = id
        end
        ACHIEVER_STARTED = true

    elseif params[2] == 'CRV' then
        achieverDB.criteria.version = tonum(params[3])
        ACHIEVER_STARTED = true

    elseif params[2] == 'CH_AC' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        achieverDBpc.achievements[id] = { date = tonum(a[2]) }
        ACHIEVER_STARTED = true

    elseif params[2] == 'CH_CR' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        achieverDBpc.criteria[id] = { counter = tonum(a[2]), date = tonum(a[3]) }
        ACHIEVER_STARTED = true

    elseif params[2] == 'AE' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        achieverDBpc.achievements[id] = { date = tonum(a[2]) }

        -- Alapból NEM hívjuk az AlertFrame-et: TBC-n ez okozta a loot-CTD-t.
        if achieverDBpc.alert == "enabled" and type(AlertFrame_ShowAchievementEarned) == 'function' then
            safeUi(function() AlertFrame_ShowAchievementEarned(id) end)
        end

        safeUi(function()
            if type(Achiever_RefreshUi) == 'function' then Achiever_RefreshUi() end
            local af = _G['AchievementFrameAchievements']
            if af and type(AchievementFrameAchievements_OnEvent) == 'function' then
                AchievementFrameAchievements_OnEvent(af, 'ACHIEVEMENT_EARNED', id)
            end
            for _, v in pairs(self.achievementFrameSummaryCategorySubscribers or {}) do
                if v and type(AchievementFrameSummaryCategory_OnEvent) == 'function' then
                    AchievementFrameSummaryCategory_OnEvent(v, 'ACHIEVEMENT_EARNED', id)
                end
            end
            if type(AchievementFrameSummary_Update) == 'function' then
                AchievementFrameSummary_Update()
            end
        end)

        local ad = achieverDB.achievements.data[id]
        if ad then debug("ACHIEVEMENT EARNED " .. tostring(ad.name)) end
        ACHIEVER_STARTED = true

    elseif params[2] == 'ACU' then
        local a = split(params[3], ";")
        local id = tonum(a[1])
        if not id then return end
        local achievementId = tonum(a[2])
        achieverDBpc.criteria[id] = {
            achievementId = achievementId,
            counter = tonum(a[3]),
            date = tonum(a[4]),
        }
        safeUi(function()
            local af = _G['AchievementFrameAchievements']
            if af and type(AchievementFrameAchievements_OnEvent) == 'function' then
                AchievementFrameAchievements_OnEvent(af, 'CRITERIA_UPDATE', id)
            end
        end)
        safeUi(function()
            local af = _G['AchievementFrameStats']
            if af and type(AchievementFrameStats_OnEvent) == 'function' then
                AchievementFrameStats_OnEvent(af, 'CRITERIA_UPDATE', id)
            end
        end)
        local ad = achievementId and achieverDB.achievements.data[achievementId]
        local cd = achieverDB.criteria.data[id]
        if ad and cd then
            debug("ACHIEVEMENT CRITERIA UPDATE " .. tostring(ad.name) .. '[' .. tostring(cd.name) .. ']')
        end
        ACHIEVER_STARTED = true
    else
        warn('server response: unhandled ' .. tostring(params[2]))
    end
end

Achiever.apiEnableDataSend = function(self, version)
    debug('request to enable sending achievement info, ' .. tostring(version))
    SendChatMessage('.achievements enableAchiever ' .. tostring(version))
end
Achiever.apiRequestCategoryInfo = function(self, version)
    SendChatMessage('.achievements getCategories ' .. tostring(version))
end
Achiever.apiRequestAchievementInfo = function(self, version)
    SendChatMessage('.achievements getAchievements ' .. tostring(version))
end
Achiever.apiRequestCriteriaInfo = function(self, version)
    SendChatMessage('.achievements getCriteria ' .. tostring(version))
end
Achiever.apiRequestCharacterCriteria = function(self)
    ensureDB()
    achieverDBpc.criteria = {}
    SendChatMessage('.achievements getCharacterCriteria')
end
Achiever.apiRequestCharacterAchievements = function(self)
    ensureDB()
    achieverDBpc.achievements = {}
    SendChatMessage('.achievements getCharacterAchievements')
end

Achiever.getChannelIndex = function(self, channelName)
    local lastVal = 0
    local chanList = { GetChannelList() }
    for _, value in next, chanList do
        if value == channelName then return lastVal end
        lastVal = value
    end
    return nil
end

Achiever.joinChannel = function(self)
    self.channelIndex = self:getChannelIndex(self.channel)
    if self.channelIndex == nil then JoinChannelByName(self.channel) end
end

local function staticComplete()
    local function ok(section)
        return type(section) == 'table' and (tonumber(section.version) or -1) >= 1
    end
    ensureDB()
    return ok(achieverDB.categories) and ok(achieverDB.achievements) and ok(achieverDB.criteria)
end

local function onTick(self, elapsed)
    if not inWorld then return end
    local dt = tonumber(elapsed) or 0

    if not ACHIEVER_INIT then
        startupTimer = (startupTimer or 0) + dt
        if startupTimer >= STARTUP_DELAY then
            startupTimer = nil
            Achiever:startup()
        end
        return
    end

    if ACHIEVER_DATA_READY then
        self:SetScript("OnUpdate", nil)
        return
    end

    readyWaited = readyWaited + dt
    readyQuiet = readyQuiet + dt
    if (readyQuiet >= READY_QUIET and staticComplete()) or readyWaited >= READY_MAX then
        ACHIEVER_DATA_READY = true
        self:SetScript("OnUpdate", nil)
        if not staticComplete() then
            say('Achiever: no complete server data after ' .. READY_MAX .. 's, the achievement window is unlocked anyway. Check /acready.')
        end
    elseif not readyHintShown and readyWaited >= READY_HINT_AT then
        readyHintShown = true
        say('Achiever: still waiting for the server data (no reply to enableAchiever). The achievement window stays locked.')
    end
end

function Achiever_RefreshUi()
    if not AchievementFrame or not AchievementFrame:IsShown() then return end
    if type(AchievementFrameCategories_GetCategoryList) == 'function' and ACHIEVEMENTUI_CATEGORIES then
        AchievementFrameCategories_GetCategoryList(ACHIEVEMENTUI_CATEGORIES)
    end
    if type(AchievementFrameCategories_Update) == 'function' then AchievementFrameCategories_Update() end
    if type(AchievementFrame_ForceUpdate) == 'function' then AchievementFrame_ForceUpdate() end
end

local function installUiGate()
    if uiGateInstalled or type(AchievementFrame_ToggleAchievementFrame) ~= 'function' then return end
    uiGateInstalled = true
    local original = AchievementFrame_ToggleAchievementFrame
    AchievementFrame_ToggleAchievementFrame = function(...)
        if not (ACHIEVER_DATA_READY or staticComplete()) then
            local function v(sec) return type(sec) == 'table' and tostring(sec.version) or 'nil' end
            say('Achiever: achievement data still loading (versions cat=' .. v(achieverDB.categories)
                .. ' ach=' .. v(achieverDB.achievements) .. ' crit=' .. v(achieverDB.criteria) .. '). Use /acready.')
            return
        end

        -- A vararg csak itt, a vararg függvényen belül használható.
        local ok, err = pcall(original, ...)
        if not ok then warn('Achiever UI error: ' .. tostring(err)) end

        safeUi(Achiever_RefreshUi)
    end
end

local linkGateInstalled = false
local function installLinkGate()
    if linkGateInstalled or type(SetItemRef) ~= 'function' then return end
    linkGateInstalled = true
    local original = SetItemRef
    SetItemRef = function(link, text, button, ...)
        if type(link) == 'string' and string.find(link, '^achievement:') then
            if type(AchievementFrame_ToggleAchievementFrame) == 'function' then
                safeUi(function() AchievementFrame_ToggleAchievementFrame() end)
            end
            return
        end
        return original(link, text, button, ...)
    end
end

local function scheduleStartup()
    if ACHIEVER_INIT or startupTimer ~= nil then return end
    startupTimer = 0
    installUiGate()
    installLinkGate()
    Achiever:SetScript("OnUpdate", onTick)
end

Achiever.startup = function(self)
    if ACHIEVER_INIT then return end
    ACHIEVER_INIT = true
    ensureDB()

    local factionGroup = UnitFactionGroup("player")
    local realm = GetRealmName()
    if achieverDB.realm ~= realm or achieverDB.faction ~= factionGroup then
        achieverDB = {}
        ensureDB()
    end
    achieverDB.realm = realm
    achieverDB.faction = factionGroup
    achieverDB.Alliance = (factionGroup == "Alliance")
    achieverDB.Horde = (factionGroup == "Horde")

    local function versionOf(section)
        if type(section) ~= 'table' then return -1 end
        return tonumber(section.version) or -1
    end
    local function hasRows(section)
        return type(section) == 'table' and type(section.data) == 'table' and next(section.data) ~= nil
    end

    local vc = versionOf(achieverDB.categories)
    local va = versionOf(achieverDB.achievements)
    local vr = versionOf(achieverDB.criteria)
    local sendVersion = 0
    if vc >= 1 and va >= 1 and vr >= 1 and hasRows(achieverDB.categories) and hasRows(achieverDB.achievements) then
        sendVersion = math.min(vc, va, vr)
    else
        achieverDB.categories = { version = -1, data = {}, byParent = {} }
        achieverDB.achievements = { version = -1, totalPoints = 0, data = {}, byCategory = {}, nextById = {}, previousById = {} }
        achieverDB.criteria = { version = -1, data = {}, byAchievement = {} }
    end

    readyQuiet = 0
    readyWaited = 0
    Achiever:SetScript("OnUpdate", onTick)

    debug('enableAchiever, data version ' .. tostring(sendVersion))
    self:apiEnableDataSend(sendVersion)
end

SLASH_ACHIEVERREADY1 = '/acready'
SlashCmdList.ACHIEVERREADY = function()
    ensureDB()
    local function v(sec) return type(sec) == 'table' and tostring(sec.version) or 'nil' end
    say(string.format('Achiever ready: init=%s inWorld=%s dataReady=%s waited=%.1f quiet=%.1f versions cat=%s ach=%s crit=%s',
        tostring(ACHIEVER_INIT), tostring(inWorld), tostring(ACHIEVER_DATA_READY), readyWaited, readyQuiet,
        v(achieverDB.categories), v(achieverDB.achievements), v(achieverDB.criteria)))
end

Achiever:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
    if not event then return end
    if event == "ADDON_LOADED" and arg1 == ACHIEVER_ADDON_NAME then
        ensureDB()
        debug('ADDON_LOADED')
    elseif event == 'VARIABLES_LOADED' then
        ensureDB()
        debug('VARIABLES_LOADED')
    elseif event == 'PLAYER_ENTERING_WORLD' then
        debug('PLAYER_ENTERING_WORLD')
        inWorld = true
        scheduleStartup()
    elseif event == 'PLAYER_LEAVING_WORLD' then
        inWorld = false
    elseif event == 'CHAT_MSG_ADDON' or event == 'CHAT_MSG_WHISPER' then
        if ACHIEVER_INIT and type(arg1) == 'string' then
            local s, e = string.find(arg1, 'ACHI#', 1, true)
            if s == 1 and e == 5 then
                local ok, err = pcall(self.processServerMessage, self, arg1)
                if not ok then warn('Achiever server message error: ' .. tostring(err)) end
            end
        end
    end
end)

NEWBIE_TOOLTIP_ACHIEVEMENT = "View information about your achievements and statistics.";
TOGGLEACHIEVEMENTS = 'Open Achievements';
BINDING_HEADER_ACHIEVER = "Achiever";
BINDING_NAME_TOGGLEACHIEVEMENTS = "Show Achievements";

function AchievementsMicroButton_OnLoad()
    if not this then return end
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    this:RegisterEvent("PLAYER_LEVEL_UP")
    this:RegisterEvent("UPDATE_BINDINGS")
    this:RegisterEvent("UNIT_LEVEL")
    this:RegisterEvent("PLAYER_ENTERING_WORLD")
    this:SetNormalTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Up")
    this:SetPushedTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Down")
    this:SetDisabledTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Disabled")
    this:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
    if GetBindingKey("TOGGLEACHIEVEMENTS") then
        this.tooltipText = "Achievements" .. " " .. NORMAL_FONT_COLOR_CODE .. "(" .. GetBindingKey("TOGGLEACHIEVEMENTS") .. ")" .. FONT_COLOR_CODE_CLOSE
    else
        this.tooltipText = "Achievements"
    end
    this.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT
end

function AchievementsMicroButton_OnEvent()
    if not this then return end
    if event == "PLAYER_LEVEL_UP" or event == "UNIT_LEVEL" or event == "PLAYER_ENTERING_WORLD" then
        safeUi(UpdateAchievementsButton)
    elseif event == "UPDATE_BINDINGS" then
        if GetBindingKey("TOGGLEACHIEVEMENTS") then
            this.tooltipText = "Achievements" .. " " .. NORMAL_FONT_COLOR_CODE .. "(" .. GetBindingKey("TOGGLEACHIEVEMENTS") .. ")" .. FONT_COLOR_CODE_CLOSE
        else
            this.tooltipText = "Achievements"
        end
    end
end

function UpdateAchievementsButton()
    if not AchievementsMicroButton then return end
    local level = UnitLevel("player") or 1
    if TalentMicroButton and QuestLogMicroButton then
        if level < 10 then
            AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0)
        else
            AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0)
        end
        QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -3, 0)
    end
    if HelpMicroButton then HelpMicroButton:Hide() end
    if AchievementFrame and AchievementFrame:IsShown() then
        AchievementsMicroButton:SetButtonState("PUSHED", 1)
        if SetButtonPulse then SetButtonPulse(AchievementsMicroButton, 0, 1) end
    else
        AchievementsMicroButton:SetButtonState("NORMAL")
    end
    if achieverDBpc and achieverDBpc.buttonsmall == "disabled" and Achiever_Minimap then
        Achiever_Minimap:Hide()
    end
end

local function toggleMainButton()
    ensureDB()
    if not AchievementsMicroButton then return end
    if achieverDBpc.buttonmain == "enabled" then
        achieverDBpc.buttonmain = "disabled"
        AchievementsMicroButton:Hide()
        if HelpMicroButton then HelpMicroButton:Show() end
        if TalentMicroButton and QuestLogMicroButton then
            if (UnitLevel("player") or 1) < 10 then
                QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0)
            else
                QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0)
            end
        end
        say('Achiever main bar button disabled')
    else
        achieverDBpc.buttonmain = "enabled"
        AchievementsMicroButton:Show()
        safeUi(UpdateAchievementsButton)
        say('Achiever main bar button enabled')
    end
end

local function toggleSmallButton()
    ensureDB()
    if achieverDBpc.buttonsmall == "enabled" then
        achieverDBpc.buttonsmall = "disabled"
        if Achiever_Minimap then Achiever_Minimap:Hide() end
        say('Achiever movable button disabled')
    else
        achieverDBpc.buttonsmall = "enabled"
        if Achiever_Minimap then Achiever_Minimap:Show() end
        say('Achiever movable button enabled')
    end
end

SLASH_ACHIEVERBUTTONMAIN1 = "/acbuttonmain"
SlashCmdList.ACHIEVERBUTTONMAIN = toggleMainButton
SLASH_ACHIEVERBUTTONSMALL1 = "/acbuttonsmall"
SlashCmdList.ACHIEVERBUTTONSMALL = toggleSmallButton
