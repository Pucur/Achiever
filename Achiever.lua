
local _G = _G

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.0.3.1'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'

local STARTUP_DELAY   = 6.0
local REQUEST_SPACING = 1.0 
local ALWAYS_RELOAD   = true

local ACHIEVER_STARTED = false
local ACHIEVER_INIT    = false

local PAT_HASH = '[^#]+'
local PAT_SEMI = '[^;]+'

local function debug(msg)
    if achieverDBpc and achieverDBpc.debug == "enabled" then
        DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff' .. tostring(msg))
    end
end

local function warn(msg)
    DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff' .. tostring(msg))
end

local function split(str, pattern)
    local res = {}
    if type(str) ~= 'string' then
        return res
    end
    local n = 0
    for w in string.gmatch(str, pattern) do
        n = n + 1
        res[n] = w
    end
    return res
end

local function newDB()
    local v = 0
    if achieverDBpc and achieverDBpc.version then v = achieverDBpc.version end
    return {
        categories   = { version = v, data = {}, byParent = {} },
        achievements = { version = v, totalPoints = 0, data = {}, byCategory = {}, nextById = {}, previousById = {} },
        criteria     = { version = v, data = {}, byAchievement = {} },
    }
end

local function ensureDB()
    if type(achieverDBpc) ~= 'table' then achieverDBpc = {} end
    if type(achieverDBpc.criteria) ~= 'table' then achieverDBpc.criteria = {} end
    if type(achieverDBpc.achievements) ~= 'table' then achieverDBpc.achievements = {} end
    if not achieverDBpc.version then achieverDBpc.version = 0 end
    if not achieverDBpc.debug then achieverDBpc.debug = "disabled" end
    if not achieverDBpc.buttonmain then achieverDBpc.buttonmain = "enabled" end
    if not achieverDBpc.buttonsmall then achieverDBpc.buttonsmall = "disabled" end

    if type(achieverDB) ~= 'table' then achieverDB = {} end
    local fresh = newDB()
    if type(achieverDB.categories) ~= 'table' then achieverDB.categories = fresh.categories end
    if type(achieverDB.categories.data) ~= 'table' then achieverDB.categories.data = {} end
    if type(achieverDB.categories.byParent) ~= 'table' then achieverDB.categories.byParent = {} end

    if type(achieverDB.achievements) ~= 'table' then achieverDB.achievements = fresh.achievements end
    local ac = achieverDB.achievements
    if type(ac.data) ~= 'table' then ac.data = {} end
    if type(ac.byCategory) ~= 'table' then ac.byCategory = {} end
    if type(ac.nextById) ~= 'table' then ac.nextById = {} end
    if type(ac.previousById) ~= 'table' then ac.previousById = {} end
    if not ac.totalPoints then ac.totalPoints = 0 end

    if type(achieverDB.criteria) ~= 'table' then achieverDB.criteria = fresh.criteria end
    if type(achieverDB.criteria.data) ~= 'table' then achieverDB.criteria.data = {} end
    if type(achieverDB.criteria.byAchievement) ~= 'table' then achieverDB.criteria.byAchievement = {} end
end

ensureDB()

local function toggleDebug()
    ensureDB()
    if achieverDBpc.debug == "enabled" then
        achieverDBpc.debug = "disabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode disabled')
    else
        achieverDBpc.debug = "enabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode enabled')
    end
end

SLASH_ACHIEVERDEBUG1 = "/acdebug"
SlashCmdList["ACHIEVERDEBUG"] = function()
    toggleDebug()
end

SLASH_RELOADUI1 = "/rl"
SlashCmdList["RELOADUI"] = ReloadUI

Achiever = CreateFrame("Frame")

Achiever:RegisterEvent("ADDON_LOADED")
Achiever:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Achiever:RegisterEvent("PLAYER_ENTERING_WORLD")
Achiever:RegisterEvent("VARIABLES_LOADED")
Achiever:RegisterEvent("CHAT_MSG_ADDON")
Achiever:RegisterEvent("CHAT_MSG_WHISPER")

Achiever.version = ACHIEVER_ADDON_VERSION
Achiever.channel = ACHIEVER_ADDON_CHANNEL
Achiever.channelIndex = nil

Achiever.achievementFrameSummaryCategorySubscribers = {}

local function handleServerMessage(self, message)
    local params = split(message, PAT_HASH)
    if params[1] ~= 'ACHI' then return end

    local cmd = params[2]
    if not cmd then return end

    local a, id
    if cmd ~= 'ACV' and cmd ~= 'CAV' and cmd ~= 'CRV' then
        a = split(params[3], PAT_SEMI)
        id = tonumber(a[1])
        if not id then return end
    end

    if cmd == 'AC' then
        local data = achieverDB.achievements.data
        local old = data[id]
        if old and old.points then
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints - old.points
        end

        local d = {}
        d.id = id
        d.faction = tonumber(a[2])
        d.previousId = tonumber(a[3])
        d.name = (a[4] ~= '_' and a[4]) or ''
        d.description = (a[5] ~= '_' and a[5]) or ''
        d.categoryId = tonumber(a[6])
        d.points = tonumber(a[7])
        d.order = tonumber(a[8])
        d.flags = tonumber(a[9])
        d.icon = tonumber(a[10])
        d.titleReward = (a[11] ~= '_' and a[11]) or ''
        d.count = tonumber(a[12])
        d.refAchievement = tonumber(a[13])
        data[id] = d

        achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints + (d.points or 0)

        local categoryId = d.categoryId
        if categoryId then
            local bc = achieverDB.achievements.byCategory
            if bc[categoryId] == nil then bc[categoryId] = {} end
            if d.order then bc[categoryId][d.order] = id end
        end

        local previousId = d.previousId
        if previousId == 0 then previousId = nil end
        if previousId then
            achieverDB.achievements.previousById[id] = previousId
            achieverDB.achievements.nextById[previousId] = id
        end
        ACHIEVER_STARTED = true

    elseif cmd == 'ACV' then
        achieverDB.achievements.version = tonumber(params[3])
        ACHIEVER_STARTED = true

    elseif cmd == 'CA' then
        local d = {}
        d.id = id
        d.parentId = tonumber(a[2])
        d.name = (a[3] ~= '_' and a[3]) or ''
        d.order = tonumber(a[4])
        achieverDB.categories.data[id] = d

        local parentId = a[2]
        if parentId and d.order then
            local bp = achieverDB.categories.byParent
            if bp[parentId] == nil then bp[parentId] = {} end
            bp[parentId][d.order] = id
        end
        ACHIEVER_STARTED = true

    elseif cmd == 'CAV' then
        achieverDB.categories.version = tonumber(params[3])
        ACHIEVER_STARTED = true

    elseif cmd == 'CR' then
        local d = {}
        d.id = id
        d.achievementId = tonumber(a[2])
        d.type = tonumber(a[3])
        d.assetId = tonumber(a[4])
        d.count = tonumber(a[5])
        d.assetId1 = tonumber(a[6])
        d.count1 = tonumber(a[7])
        d.assetId2 = tonumber(a[8])
        d.count2 = tonumber(a[9])
        d.name = (a[10] ~= '_' and a[10]) or ''
        d.flags = tonumber(a[11])
        d.timedType = tonumber(a[12])
        d.timerStartEvent = tonumber(a[13])
        d.timeLimit = tonumber(a[14])
        d.order = tonumber(a[15])
        achieverDB.criteria.data[id] = d

        if d.achievementId and d.order then
            local ba = achieverDB.criteria.byAchievement
            if ba[d.achievementId] == nil then ba[d.achievementId] = {} end
            ba[d.achievementId][d.order] = id
        end
        ACHIEVER_STARTED = true

    elseif cmd == 'CRV' then
        achieverDB.criteria.version = tonumber(params[3])
        ACHIEVER_STARTED = true

    elseif cmd == 'CH_AC' then
        achieverDBpc.achievements[id] = { date = tonumber(a[2]) }
        ACHIEVER_STARTED = true

    elseif cmd == 'CH_CR' then
        achieverDBpc.criteria[id] = { counter = tonumber(a[2]), date = tonumber(a[3]) }
        ACHIEVER_STARTED = true

    elseif cmd == 'AE' then
        achieverDBpc.achievements[id] = { date = tonumber(a[2]) }

        local frameAch = _G['AchievementFrameAchievements']
        if frameAch and AchievementFrameAchievements_OnEvent then
            AchievementFrameAchievements_OnEvent(frameAch, 'ACHIEVEMENT_EARNED', id)
        end
        if AchievementFrameSummaryCategory_OnEvent then
            for k, v in pairs(Achiever.achievementFrameSummaryCategorySubscribers) do
                AchievementFrameSummaryCategory_OnEvent(v, 'ACHIEVEMENT_EARNED', id)
            end
        end
        if AchievementFrameSummary_Update then AchievementFrameSummary_Update() end

        local ad = achieverDB.achievements.data[id]
        if ad then debug("ACHIEVEMENT EARNED " .. tostring(ad.name)) end
        if AlertFrame_ShowAchievementEarned then AlertFrame_ShowAchievementEarned(id) end
        ACHIEVER_STARTED = true

    elseif cmd == 'ACU' then
        achieverDBpc.criteria[id] = {
            achievementId = tonumber(a[2]),
            counter = tonumber(a[3]),
            date = tonumber(a[4]),
        }

        local frameAch = _G['AchievementFrameAchievements']
        if frameAch and AchievementFrameAchievements_OnEvent then
            AchievementFrameAchievements_OnEvent(frameAch, 'CRITERIA_UPDATE', id)
        end
        local frameStats = _G['AchievementFrameStats']
        if frameStats and AchievementFrameStats_OnEvent then
            AchievementFrameStats_OnEvent(frameStats, 'CRITERIA_UPDATE', id)
        end
        ACHIEVER_STARTED = true

    else
        warn('server response: unhandled ' .. tostring(cmd))
    end
end

Achiever.processServerMessage = function(self, message)
    if type(message) ~= 'string' then return end
    local ok, err = pcall(handleServerMessage, self, message)
    if not ok then
        debug('processServerMessage hiba: ' .. tostring(err))
    end
end

Achiever.apiEnableDataSend = function(self, version)
    debug('request to enable sending achievement info, ' .. tostring(version or 0))
    SendChatMessage('.achievements enableAchiever ' .. (version or 0))
end
Achiever.apiRequestCategoryInfo = function(self, version)
    SendChatMessage('.achievements getCategories ' .. (version or 0))
end
Achiever.apiRequestAchievementInfo = function(self, version)
    SendChatMessage('.achievements getAchievements ' .. (version or 0))
end
Achiever.apiRequestCriteriaInfo = function(self, version)
    SendChatMessage('.achievements getCriteria ' .. (version or 0))
end
Achiever.apiRequestCharacterCriteria = function(self)
    debug('requested character criteria progress from server')
    if type(achieverDBpc.criteria) ~= 'table' then achieverDBpc.criteria = {} end
    SendChatMessage('.achievements getCharacterCriteria')
end
Achiever.apiRequestCharacterAchievements = function(self)
    debug('requested character achievements from server')
    if type(achieverDBpc.achievements) ~= 'table' then achieverDBpc.achievements = {} end
    SendChatMessage('.achievements getCharacterAchievements')
end

Achiever.getChannelIndex = function(self, channelName)
    local lastVal = 0
    local chanList = { GetChannelList() }
    local result = nil
    for _, value in next, chanList do
        if value == channelName then
            result = lastVal
            break
        end
        lastVal = value
    end
    return result
end

Achiever.joinChannel = function(self)
    self.channelIndex = self:getChannelIndex(self.channel)
    if self.channelIndex == nil then
        JoinChannelByName(self.channel)
    end
end

local pending = {}
local pendingFirst, pendingLast = 1, 0
local waitTimer = 0
local startupTimer = 0
local worldEntered = false

local function queueRequest(fn)
    pendingLast = pendingLast + 1
    pending[pendingLast] = fn
end

Achiever.startup = function(self)
    if ACHIEVER_INIT then return end
    ACHIEVER_INIT = true

    ensureDB()

    local factionGroup = UnitFactionGroup("player")

    if ALWAYS_RELOAD then
        achieverDB = newDB()
    end
    if factionGroup == "Alliance" then
        achieverDB.Alliance = true
        achieverDB.Horde = false
    elseif factionGroup == "Horde" then
        achieverDB.Horde = true
        achieverDB.Alliance = false
    end

    if achieverDBpc.buttonsmall == "disabled" and Achiever_Minimap then
        Achiever_Minimap:Hide()
    end

    debug('request data to UI ' .. tostring(achieverDBpc.version))

    local me = self
    queueRequest(function() me:apiRequestCategoryInfo(achieverDB.categories.version) end)
    queueRequest(function() me:apiRequestAchievementInfo(achieverDB.achievements.version) end)
    queueRequest(function() me:apiRequestCriteriaInfo(achieverDB.criteria.version) end)
    queueRequest(function() me:apiRequestCharacterCriteria() end)
    queueRequest(function() me:apiRequestCharacterAchievements() end)
    queueRequest(function() me:apiEnableDataSend(achieverDBpc.version) end)
end

local function onUpdate(frame, elapsed)
    local dt = elapsed or _G.arg1
    if type(dt) ~= 'number' then return end

    if not ACHIEVER_INIT then
        startupTimer = startupTimer + dt
        if startupTimer >= STARTUP_DELAY then
            Achiever:startup()
        end
        return
    end

    if pendingFirst <= pendingLast then
        waitTimer = waitTimer + dt
        if waitTimer >= REQUEST_SPACING then
            waitTimer = 0
            local fn = pending[pendingFirst]
            pending[pendingFirst] = nil
            pendingFirst = pendingFirst + 1
            local ok, err = pcall(fn)
            if not ok then
                debug('kérés hiba: ' .. tostring(err))
            end
        end
    else
        -- minden kérés elment: nincs több dolga, az OnUpdate leállítható
        Achiever:SetScript("OnUpdate", nil)
    end
end

Achiever:SetScript("OnEvent", function(frame, ev, a1, a2)
    local e = ev or _G.event
    local m1 = a1 or _G.arg1
    local m2 = a2 or _G.arg2
    if not e then return end

    if e == "VARIABLES_LOADED" then
        ensureDB()

    elseif e == "ADDON_LOADED" then
        if m1 == ACHIEVER_ADDON_NAME then
            ensureDB()
            debug('ADDON_LOADED')
        end

    elseif e == "PLAYER_ENTERING_WORLD" then
        if not worldEntered then
            worldEntered = true
            startupTimer = 0
            Achiever:SetScript("OnUpdate", onUpdate)
        end

    elseif e == "CHAT_MSG_ADDON" or e == "CHAT_MSG_WHISPER" then
        if ACHIEVER_INIT then
            local msg
            if type(m1) == 'string' and string.find(m1, 'ACHI#', 1, true) == 1 then
                msg = m1
            elseif type(m2) == 'string' and string.find(m2, 'ACHI#', 1, true) == 1 then
                msg = m2
            end
            if msg then
                Achiever:processServerMessage(msg)
            end
        end
    end
end)

NEWBIE_TOOLTIP_ACHIEVEMENT = "View information about your achievements and statistics.";
TOGGLEACHIEVEMENTS = 'Open Achievements';
BINDING_HEADER_ACHIEVER = "Achiever";
BINDING_NAME_TOGGLEACHIEVEMENTS = "Show Achievements";

function AchievementsMicroButton_OnLoad()
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    this:RegisterEvent("PLAYER_LEVEL_UP");
    this:RegisterEvent("UPDATE_BINDINGS");
    this:RegisterEvent("UNIT_LEVEL");
    this:RegisterEvent("PLAYER_ENTERING_WORLD");
    this:SetNormalTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Up");
    this:SetPushedTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Down");
    this:SetDisabledTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Disabled");
    this:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight");
    if ( GetBindingKey("TOGGLEACHIEVEMENTS") ) then
        this.tooltipText = "Achievements".." "..NORMAL_FONT_COLOR_CODE.."("..GetBindingKey("TOGGLEACHIEVEMENTS")..")"..FONT_COLOR_CODE_CLOSE;
    else
        this.tooltipText = "Achievements";
    end
    this.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT;
end

function AchievementsMicroButton_OnEvent()
    if ( event == "PLAYER_LEVEL_UP" ) then
        UpdateAchievementsButton();
    elseif ( event == "UNIT_LEVEL" or event == "PLAYER_ENTERING_WORLD" ) then
        UpdateAchievementsButton();
    elseif ( event == "UPDATE_BINDINGS" ) then
        if ( GetBindingKey("TOGGLEACHIEVEMENTS") ) then
            this.tooltipText = "Achievements".." "..NORMAL_FONT_COLOR_CODE.."("..GetBindingKey("TOGGLEACHIEVEMENTS")..")"..FONT_COLOR_CODE_CLOSE;
        else
            this.tooltipText = "Achievements";
        end
    end
end

function UpdateAchievementsButton()
    if not AchievementsMicroButton then return end

    if ( UnitLevel("player") < 10 ) then
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        if QuestLogMicroButton then QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0); end
    else
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
    end
    
    if HelpMicroButton then HelpMicroButton:Hide(); end
    if QuestLogMicroButton then QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -3, 0); end

    if AchievementFrame and AchievementFrame:IsShown() then
        AchievementsMicroButton:SetButtonState("PUSHED", 1);
        if SetButtonPulse then SetButtonPulse(AchievementsMicroButton, 0, 1); end
    else
        AchievementsMicroButton:SetButtonState("NORMAL");
    end

    if achieverDBpc and achieverDBpc.buttonsmall == "disabled" and Achiever_Minimap then
        Achiever_Minimap:Hide();
    end
end

local function toggleMainButton()
    ensureDB()
    if achieverDBpc.buttonmain == "enabled" then
        achieverDBpc.buttonmain = "disabled"
        if AchievementsMicroButton then AchievementsMicroButton:Hide(); end
        if HelpMicroButton then HelpMicroButton:Show(); end
        if QuestLogMicroButton then
            if ( UnitLevel("player") < 10 ) then
                QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
            else
                QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button disabled')
    else
        achieverDBpc.buttonmain = "enabled"
        if AchievementsMicroButton then AchievementsMicroButton:Show(); end
        UpdateAchievementsButton();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button enabled')
    end
end

local function toggleSmallButton()
    ensureDB()
    if achieverDBpc.buttonsmall == "enabled" then
        achieverDBpc.buttonsmall = "disabled"
        if Achiever_Minimap then Achiever_Minimap:Hide(); end
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button disabled')
    else
        achieverDBpc.buttonsmall = "enabled"
        if Achiever_Minimap then Achiever_Minimap:Show(); end
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button enabled')
    end
end

SLASH_ACHIEVERBUTTONMAIN1 = "/acbuttonmain"
SlashCmdList["ACHIEVERBUTTONMAIN"] = function()
    toggleMainButton()
end

SLASH_ACHIEVERBUTTONSMALL1 = "/acbuttonsmall"
SlashCmdList["ACHIEVERBUTTONSMALL"] = function()
    toggleSmallButton()
end
