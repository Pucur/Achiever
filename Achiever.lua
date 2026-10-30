local _G, _ = _G or getfenv()

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.0.2.0'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'
local ACHIEVER_REQUESTED_DATA = false
local ACHIEVER_STARTED = false
local ACHIEVER_INIT = false
local ACHIEVER_DATA_READY = false  -- az achievement ablak csak ekkor nyitható
local READY_QUIET = 3.0            -- ennyi csend a utolsó szerver-csomag után
local READY_HINT_AT = 20.0         -- ennyi mp után jelzünk, ha még nincs adat
local readyQuiet = 0
local readyWaited = 0
local readyHintShown = false
local uiGateInstalled = false

local function debug(msg)
    if achieverDBpc.debug == "enabled" then
	    DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff'.. (msg or 'nil'))
    end
end
local function warn(msg)
	DEFAULT_CHAT_FRAME:AddMessage('|cf3f3f66cWARN: |cffff55ff'.. (msg or 'nil'))
end

-- UI hívások védelme: egy hiányzó/hibás UI-frame ne rombolja le a chat-feldolgozást.
local function safeUi(fn)
    local ok, err = pcall(fn)
    if not ok then warn('Achiever UI error: ' .. tostring(err)) end
end

local function toggleDebug()
    if achieverDBpc.debug == "enabled" then
        achieverDBpc.debug = "disabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode disabled')
    else
        achieverDBpc.debug = "enabled"
        DEFAULT_CHAT_FRAME:AddMessage('Achiever DEBUG mode enabled')
    end
end

SLASH_ACHIEVERDEBUG1 = "/acdebug"
SlashCmdList.ACHIEVERDEBUG = function()
    toggleDebug()
end

Achiever = CreateFrame("Frame")
achieverDBpc = {
    criteria = {},
    achievements = {}
}
SLASH_RELOADUI1 = "/rl"
SlashCmdList.RELOADUI = ReloadUI

local function split(str, sep)
    -- Keeps empty fields: gsub('[^sep]+') dropped them and shifted every later column.
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
    readyQuiet = 0

    local params = split(message, '#')
    if (params[1] == 'ACHI') then
        if (params[2] == 'AC') then
            --debug('server response: new achievement entry ')
            local a = split(params[3], ';')
            local id = tonumber(a[1])
            achieverDB.achievements.data[id] = {}
            achieverDB.achievements.data[id].id = tonumber(id)
            achieverDB.achievements.data[id].faction = tonumber(a[2])
            achieverDB.achievements.data[id].previousId = tonumber(a[3])
            local name = ''
            if (a[4] ~= '_') then name = a[4] end
            achieverDB.achievements.data[id].name = name
            local description = ''
            if (a[5] ~= '_') then description = a[5] end
            achieverDB.achievements.data[id].description = description
            achieverDB.achievements.data[id].categoryId = tonumber(a[6])
            achieverDB.achievements.data[id].points = tonumber(a[7])
            achieverDB.achievements.data[id].order = tonumber(a[8])
            achieverDB.achievements.data[id].flags = tonumber(a[9])
            achieverDB.achievements.data[id].icon = tonumber(a[10])
            local titleReward = ''
            if (a[11] ~= '_') then titleReward = a[11] end
            achieverDB.achievements.data[id].titleReward = titleReward
            achieverDB.achievements.data[id].count = tonumber(a[12])
            achieverDB.achievements.data[id].refAchievement = tonumber(a[13])
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints + tonumber(a[7])

            local n = tonumber(a[14])
            local c = tonumber(a[15])

            local categoryId = tonumber(a[6])
            if (achieverDB.achievements.byCategory[categoryId] == nil) then
                achieverDB.achievements.byCategory[categoryId] = {}
            end
            -- table.insert(achieverDB.achievements.byCategory[categoryId], id)
            achieverDB.achievements.byCategory[categoryId][tonumber(a[8])] = id

            local previousId = tonumber(a[3])
            if (previousId == 0) then previousId = nil end
            if (previousId) then
                achieverDB.achievements.previousById[id] = previousId
                achieverDB.achievements.nextById[previousId] = id
            end

            ACHIEVER_STARTED = true
            
            if (n == c) then
                --debug('loaded achievements from server')
            end

        elseif (params[2] == 'ACV') then
            debug('server response: achievement data version')
            achieverDB.achievements.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CA') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDB.categories.data[id] = {}
            achieverDB.categories.data[id].id = tonumber(id)
            achieverDB.categories.data[id].parentId = tonumber(a[2])
            local name = ''
            if (a[3] ~= '_') then name = a[3] end
            achieverDB.categories.data[id].name = name
            achieverDB.categories.data[id].order = tonumber(a[4])
            local n = tonumber(a[5])
            local c = tonumber(a[6])

            local parentId = a[2]
            if (achieverDB.categories.byParent[parentId] == nil) then
                achieverDB.categories.byParent[parentId] = {}
            end
            -- table.insert(achieverDB.categories.byParent[parentId], id)
            achieverDB.categories.byParent[parentId][tonumber(a[4])] = id
            ACHIEVER_STARTED = true

            if (n == c) then
                debug('loaded categories from server')
            end
        elseif (params[2] == 'CAV') then
            debug('server response: criteria data version')
            achieverDB.categories.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CR') then
            --debug('server response: get all criteria')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDB.criteria.data[id] = {}
            achieverDB.criteria.data[id].id = tonumber(id)
            achieverDB.criteria.data[id].achievementId = tonumber(a[2])
            achieverDB.criteria.data[id].type = tonumber(a[3])
            achieverDB.criteria.data[id].assetId = tonumber(a[4])
            achieverDB.criteria.data[id].count = tonumber(a[5])
            achieverDB.criteria.data[id].assetId1 = tonumber(a[6])
            achieverDB.criteria.data[id].count1 = tonumber(a[7])
            achieverDB.criteria.data[id].assetId2 = tonumber(a[8])
            achieverDB.criteria.data[id].count2 = tonumber(a[9])
            local name = ''
            if (a[10] ~= '_') then name = a[10] end
            achieverDB.criteria.data[id].name = name
            achieverDB.criteria.data[id].flags = tonumber(a[11])
            achieverDB.criteria.data[id].timedType = tonumber(a[12])
            achieverDB.criteria.data[id].timerStartEvent = tonumber(a[13])
            achieverDB.criteria.data[id].timeLimit = tonumber(a[14])
            achieverDB.criteria.data[id].order = tonumber(a[15])
            local n = tonumber(a[16])
            local c = tonumber(a[17])

            local achievementId = tonumber(a[2])
            if (achieverDB.criteria.byAchievement[achievementId] == nil) then
                achieverDB.criteria.byAchievement[achievementId] = {}
            end
            achieverDB.criteria.byAchievement[achievementId][tonumber(a[15])] = id
            -- table.insert(achieverDB.criteria.byAchievement[achievementId], id)
            ACHIEVER_STARTED = true

            if (n == c) then
                --debug('loaded criteria from server')
            end
        elseif (params[2] == 'CRV') then
            debug('server response: criteria data version')
            achieverDB.criteria.version = tonumber(params[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CH_AC') then
            --debug('server response: char achievements')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDBpc.achievements[id] = {}
            achieverDBpc.achievements[id].date = tonumber(a[2])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'CH_CR') then
            --debug('server response: char criteria')
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            achieverDBpc.criteria[id] = {}
            achieverDBpc.criteria[id].counter = tonumber(a[2])
            achieverDBpc.criteria[id].date = tonumber(a[3])
            ACHIEVER_STARTED = true
        elseif (params[2] == 'AE') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.achievements) then achieverDBpc.achievements = {} end
            achieverDBpc.achievements[id] = {}
            achieverDBpc.achievements[id].date = tonumber(a[2])
            safeUi(function()
                AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'ACHIEVEMENT_EARNED', id)
                for k, v in pairs(self.achievementFrameSummaryCategorySubscribers) do
                    AchievementFrameSummaryCategory_OnEvent(v, 'ACHIEVEMENT_EARNED', id)
                end
                AchievementFrameSummary_Update()
                AlertFrame_ShowAchievementEarned(id)
            end)
            local ad = achieverDB.achievements.data[id]
            if ad then debug("ACHIEVEMENT EARNED " .. tostring(ad.name)) end
            ACHIEVER_STARTED = true
        elseif (params[2] == 'ACU') then
            local a = split(params[3], ";")
            local id = tonumber(a[1])
            if (not achieverDBpc.criteria) then achieverDBpc.criteria = {} end
            achieverDBpc.criteria[id] = {}
            achieverDBpc.criteria[id].achievementId = tonumber(a[2])
            achieverDBpc.criteria[id].counter = tonumber(a[3])
            achieverDBpc.criteria[id].date = tonumber(a[4])
            safeUi(function()
                AchievementFrameAchievements_OnEvent(_G['AchievementFrameAchievements'], 'CRITERIA_UPDATE', id)
                AchievementFrameStats_OnEvent(_G['AchievementFrameStats'], 'CRITERIA_UPDATE', id)
            end)
            local ad = achieverDB.achievements.data[tonumber(a[2])]
            local cd = achieverDB.criteria.data[id]
            if ad and cd then
                debug("ACHIEVEMENT CRITERIA UPDATE " .. tostring(ad.name) .. '[' .. tostring(cd.name) .. ']')
            end
            ACHIEVER_STARTED = true
        else
            warn('server response: unhandled ' .. params[2])
        end
    end
end

Achiever.apiEnableDataSend = function(self, version)

    debug('request to enable sending achievement info, ' .. version)
    SendChatMessage('.achievements enableAchiever ' .. version)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCategoryInfo = function(self, version)

    --debug('requested information about categories from server, ' .. version)
    SendChatMessage('.achievements getCategories ' .. version)
    --SendChatMessage('!achievements getCategoties ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestAchievementInfo = function(self, version)

    --debug('requested information about achievements from server, ' .. version)
    SendChatMessage('.achievements getAchievements ' .. version)
    --SendChatMessage('!achievements getAchievements ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCriteriaInfo = function(self, version)

    --debug('requested information about criteria from server, ' .. version)
    SendChatMessage('.achievements getCriteria ' .. version)
    --SendChatMessage('!achievements getCriteria ' .. version, 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterCriteria = function(self)
    debug('requested character criteria progress from server')
    achieverDBpc.criteria = {}
    SendChatMessage('.achievements getCharacterCriteria')
    --SendChatMessage('!achievements getCharacterCriteria', 'CHANNEL', nil, Achiever.channelIndex)
end
Achiever.apiRequestCharacterAchievements = function(self)
    debug('requested character achievements from server')
    achieverDBpc.achievements = {}
    SendChatMessage('.achievements getCharacterAchievements')
    --SendChatMessage('.achievements getCharacterAchievements', 'CHANNEL', nil, Achiever.channelIndex)
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
    if (self.channelIndex == nil) then
        JoinChannelByName(self.channel)
    else
        --self:startup()
    end
end

local READY_MAX = 30.0  -- ennyi mp után feloldjuk az ablakot, akkor is, ha nincs teljes adat
-- Indítás: késleltetve, bejelentkezésenként egyszer. Ezután az OnUpdate figyeli, hogy a
-- szerver-adat tényleg megérkezett-e (CAV/ACV/CRV + csend), és csak utána nyitható az ablak.
local STARTUP_DELAY = 8.0
local startupTimer = nil   -- nil = nincs ütemezve
local inWorld = false

local function staticComplete()
    local function ok(section)
        return type(section) == 'table' and (tonumber(section.version) or -1) >= 1
    end
    return ok(achieverDB.categories) and ok(achieverDB.achievements) and ok(achieverDB.criteria)
end

local function onTick(self, elapsed)
    if not inWorld then return end
    local dt = tonumber(elapsed) or tonumber(arg1) or 0

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
            DEFAULT_CHAT_FRAME:AddMessage('Achiever: no complete server data after ' .. READY_MAX .. 's, the achievement window is unlocked anyway. Check /acready.')
        end
    elseif not readyHintShown and readyWaited >= READY_HINT_AT then
        readyHintShown = true
        DEFAULT_CHAT_FRAME:AddMessage('Achiever: still waiting for the server data (no reply to enableAchiever). The achievement window stays locked.')
    end
end

-- Az achievement ablak megnyitását (keybind, micro gomb) addig zárjuk, amíg az adat nincs kész.
local function installUiGate()
    if uiGateInstalled or type(AchievementFrame_ToggleAchievementFrame) ~= 'function' then return end
    uiGateInstalled = true
    local original = AchievementFrame_ToggleAchievementFrame
    AchievementFrame_ToggleAchievementFrame = function(...)
        if not (ACHIEVER_DATA_READY or staticComplete()) then
            local function v(sec) return type(sec) == 'table' and tostring(sec.version) or 'nil' end
            DEFAULT_CHAT_FRAME:AddMessage('Achiever: achievement data still loading (versions cat=' .. v(achieverDB.categories)
                .. ' ach=' .. v(achieverDB.achievements) .. ' crit=' .. v(achieverDB.criteria) .. '). Use /acready.')
            return
        end
        return original(...)
    end
end

local function scheduleStartup()
    if ACHIEVER_INIT or startupTimer ~= nil then return end
    startupTimer = 0
    installUiGate()
    Achiever:SetScript("OnUpdate", onTick)
end

Achiever.startup = function(self)
    if ACHIEVER_INIT then return end
    ACHIEVER_INIT = true

    if type(achieverDB) ~= 'table' then achieverDB = {} end
    if type(achieverDBpc) ~= 'table' then achieverDBpc = {} end
    if type(achieverDBpc.criteria) ~= 'table' then achieverDBpc.criteria = {} end
    if type(achieverDBpc.achievements) ~= 'table' then achieverDBpc.achievements = {} end
    if (not achieverDBpc.debug) then achieverDBpc.debug = "disabled" end
    if (not achieverDBpc.buttonmain) then achieverDBpc.buttonmain = "enabled" end
    if (not achieverDBpc.buttonsmall) then
        achieverDBpc.buttonsmall = "disabled"
        if Achiever_Minimap then Achiever_Minimap:Hide() end
    end

    -- A statikus cache realm + faction szerint érvényes. Bejelentkezés/reload között megmarad.
    local factionGroup = UnitFactionGroup("player")
    local realm = GetRealmName()
    if achieverDB.realm ~= realm or achieverDB.faction ~= factionGroup then
        achieverDB = {}
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
        -- Teljes, érvényes cache: a szerver ilyenkor nem küld újra statikus adatot.
        sendVersion = math.min(vc, va, vr)
    else
        -- Hiányos vagy régi cache: teljes újraküldés. A régi táblák kellenek eldobni,
        -- különben az achievement-pontok duplán számolódnának.
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
    local function v(sec)
        return type(sec) == 'table' and tostring(sec.version) or 'nil'
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format('Achiever ready: init=%s inWorld=%s dataReady=%s waited=%.1f quiet=%.1f versions cat=%s ach=%s crit=%s',
        tostring(ACHIEVER_INIT), tostring(inWorld), tostring(ACHIEVER_DATA_READY), readyWaited, readyQuiet,
        v(achieverDB.categories), v(achieverDB.achievements), v(achieverDB.criteria)))
end
Achiever:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
    if (not event) then
        warn('OnEvent with no event')
		return
	elseif (event == "ADDON_LOADED" and arg1 == ACHIEVER_ADDON_NAME) then
        debug('ADDON_LOADED')
	elseif (event == 'CHAT_MSG_CHANNEL_LEAVE') then
        debug('OnEvent CHAT_MSG_CHANNEL_LEAVE')
    elseif (event == 'VARIABLES_LOADED') then
        debug('VARIABLES_LOADED')
	elseif (event == 'PLAYER_ENTERING_WORLD') then
		debug('PLAYER_ENTERING_WORLD')
		inWorld = true
		scheduleStartup()
	elseif (event == 'PLAYER_LEAVING_WORLD') then
		inWorld = false
elseif (event == 'CHAT_MSG_ADDON' or event == 'CHAT_MSG_WHISPER') then
		if (ACHIEVER_INIT and arg1) then
			local s, e  = string.find(arg1, 'ACHI#', 1, true)
			if (s == 1 and e == 5) then
				debug('hidden achievement server message: ' .. arg1)
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
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    this:RegisterEvent("PLAYER_LEVEL_UP");
    this:RegisterEvent("UPDATE_BINDINGS");
    this:RegisterEvent("UNIT_LEVEL");
    this:RegisterEvent("PLAYER_ENTERING_WORLD");
    this:SetNormalTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Up");
    this:SetPushedTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Down");
    this:SetDisabledTexture("Interface\\AddOns\\Achiever\\textures\\UI-MicroButton-Achievement-Disabled");
    this:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight");
    this:RegisterForClicks("LeftButtonUp", "RightButtonUp");
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
    -- move nearby buttons
    if ( UnitLevel("player") < 10 ) then
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0);
    else
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
        --QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0);
    end
    -- hide help button to free up space
    HelpMicroButton:Hide();
    QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -3, 0);

    -- Update main bar button
    if ( AchievementFrame:IsShown() ) then
        AchievementsMicroButton:SetButtonState("PUSHED", 1);
        SetButtonPulse(AchievementsMicroButton, 0, 1);
    else
        AchievementsMicroButton:SetButtonState("NORMAL");
    end

    if achieverDBpc.buttonsmall == "disabled" then
        Achiever_Minimap:Hide();
    end
end

local function toggleMainButton()
    if achieverDBpc.buttonmain == "enabled" then
        achieverDBpc.buttonmain = "disabled"
        AchievementsMicroButton:Hide();
        HelpMicroButton:Show();
        if ( UnitLevel("player") < 10 ) then
            QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        else
            QuestLogMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
        end
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button disabled')
    else
        achieverDBpc.buttonmain = "enabled"
        AchievementsMicroButton:Show();
        UpdateAchievementsButton();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever main bar button enabled')
    end
end

local function toggleSmallButton()
    if achieverDBpc.buttonsmall == "enabled" then
        achieverDBpc.buttonsmall = "disabled"
        Achiever_Minimap:Hide();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button disabled')
    else
        achieverDBpc.buttonsmall = "enabled"
        Achiever_Minimap:Show();
        DEFAULT_CHAT_FRAME:AddMessage('Achiever movable button enabled')
    end
end

SLASH_ACHIEVERBUTTONMAIN1 = "/acbuttonmain"
SlashCmdList.ACHIEVERBUTTONMAIN = function()
    toggleMainButton()
end

SLASH_ACHIEVERBUTTONSMALL1 = "/acbuttonsmall"
SlashCmdList.ACHIEVERBUTTONSMALL = function()
    toggleSmallButton()
end
