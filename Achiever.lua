-- Achiever (WoW 2.4.3 / TBC kliens, Lua 5.1)
local _G = _G
-- Defensive guard: a second XML/TOC include must never create another frame.
if _G.Achiever and _G.Achiever.runtimeLoaded then return end

ACHIEVER_ADDON_NAME = 'Achiever'
local ACHIEVER_ADDON_VERSION = '0.3.4'
local ACHIEVER_ADDON_CHANNEL = 'ACHIEVER_CHANNEL'

-- Beállítások ------------------------------------------------------------
local STARTUP_DELAY   = 6.0    -- ennyi mp-et vár a világba lépés után, mielőtt bármit küld a szervernek
local REQUEST_SPACING = 3.0
local RESPONSE_QUIET = 3.0
local RESPONSE_TIMEOUT = 45.0
local TRANSFER_TIMEOUT = 300.0
local ALWAYS_RELOAD = false

-- Állapot ----------------------------------------------------------------
local ACHIEVER_STARTED = false  -- jött-e már válasz a szervertől
local ACHIEVER_INIT    = false  -- lefutott-e az indítás (bejelentkezésenként csak egyszer fut)

local PAT_HASH = '[^#]+'
local PAT_SEMI = '[^;]+'

---------------------------------------------------------------------------
-- Segédfüggvények
---------------------------------------------------------------------------
local function debug(msg)
    if achieverDBpc and achieverDBpc.debug == "enabled" then
        DEFAULT_CHAT_FRAME:AddMessage('|cffc663fcDEBUG: |cffff55ff' .. tostring(msg))
    end
end

local function warn(msg)
    DEFAULT_CHAT_FRAME:AddMessage(tostring(msg))
end

local function split(str, pattern)
    local res = {}
    if type(str) ~= 'string' then
        return res
    end
    -- Keep empty fields; gmatch("[^;]+") shifts every subsequent column.
    local delimiter = pattern == PAT_HASH and '#' or ';'
    local first = 1
    while true do
        local pos = string.find(str, delimiter, first, true)
        if not pos then
            res[#res + 1] = string.sub(str, first)
            break
        end
        res[#res + 1] = string.sub(str, first, pos - 1)
        first = pos + 1
    end
    return res
end

local function newDB()
    local v = -1
    return {
        categories   = { version = v, data = {}, byParent = {} },
        achievements = { version = v, totalPoints = 0, data = {}, byCategory = {}, nextById = {}, previousById = {} },
        criteria     = { version = v, data = {}, byAchievement = {} },
    }
end

-- Nem destruktív: csak a hiányzó táblákat pótolja, így a UI soha nem kap nil-t.
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
    for _, key in ipairs({'categories', 'achievements', 'criteria'}) do
        local section = achieverDB[key]
        if type(section.version) ~= 'number' then section.version = -1 end
    end
end

-- Már a fájl betöltésekor legyen használható (nil-védelem az XML/UI scripteknek).
-- A SavedVariables később úgyis felülírja / kiegészíti.
ensureDB()

---------------------------------------------------------------------------
-- Slash parancsok
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Fő frame
---------------------------------------------------------------------------
Achiever = CreateFrame("Frame")
Achiever.runtimeLoaded = true
Achiever.state = 'waiting-world'
Achiever.errors = 0
Achiever.received = 0
Achiever.incoming = 0
Achiever.rejected = 0
Achiever.lastError = ''

local function reportError(context, err)
    Achiever.errors = Achiever.errors + 1
    Achiever.lastError = context .. ': ' .. tostring(err)
    if Achiever.errors == 1 then
        warn('Achiever error: ' .. Achiever.lastError .. ' (/acstatus)')
    end
    debug(Achiever.lastError)
end

local function safeCall(context, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then reportError(context, err) end
    return ok
end

SLASH_ACHIEVERSTATUS1 = '/acstatus'
SlashCmdList.ACHIEVERSTATUS = function()
    warn('Achiever ' .. Achiever.version .. ': ' .. Achiever.state ..
        ', incoming=' .. Achiever.incoming .. ', received=' .. Achiever.received .. ', rejected=' .. Achiever.rejected ..
        ', errors=' .. Achiever.errors)
    warn(Achiever:GetSyncProgress())
    if Achiever.lastCommand then warn('Last command sent: ' .. Achiever.lastCommand) end
    if Achiever.lastRejectedCommand then warn('Last rejected message type: ' .. Achiever.lastRejectedCommand) end
    if Achiever.lastError ~= '' then warn(Achiever.lastError) end
end
SLASH_ACHIEVERRESET1 = '/acreset'
SlashCmdList.ACHIEVERRESET = function()
    -- Keep character achievements/settings; invalidate only the static cache.
    achieverDB.cacheClean = false
    ReloadUI()
end

Achiever:RegisterEvent("ADDON_LOADED")
Achiever:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
Achiever:RegisterEvent("PLAYER_ENTERING_WORLD")
Achiever:RegisterEvent("PLAYER_LEAVING_WORLD")
Achiever:RegisterEvent("VARIABLES_LOADED")
Achiever:RegisterEvent("CHAT_MSG_ADDON")
Achiever:RegisterEvent("CHAT_MSG_WHISPER")
Achiever:RegisterEvent("CHAT_MSG_SYSTEM")

Achiever.version = ACHIEVER_ADDON_VERSION
Achiever.channel = ACHIEVER_ADDON_CHANNEL
Achiever.channelIndex = nil

Achiever.achievementFrameSummaryCategorySubscribers = {}

---------------------------------------------------------------------------
-- Szerver üzenetek feldolgozása
---------------------------------------------------------------------------
-- A UI-frissítések és az "achievement earned" ablakok NEM az eseménykezelőben, hanem
-- késleltetve, egyesével futnak le (egyszerre érkező 3 achievementnél a 3 ablak/frissítés
-- egyszerre történő kirajzolása fagyást / crasht okozhat).
local ALERT_SPACING = 4.0   -- két "achievement earned" ablak között eltelő idő
local UI_SPACING    = 0.15  -- két UI-frissítés között eltelő idő

local uiJobs, uiFirst, uiLast = {}, 1, 0
local alertQueue, alertFirst, alertLast = {}, 1, 0
local uiTimer = 0
local alertTimer = ALERT_SPACING
local summaryPending = false
local uiPending, alertPending = {}, {}
local activeRequest, requestAge, responseAge, responseSeen
local worldActive = false
local onUpdate   -- előre deklarálva, lent van definiálva

local function ensureUpdate()
    Achiever:SetScript("OnUpdate", onUpdate)
end

local function queueUi(kind, id)
    -- All criteria updates use the same refresh; avoid an unbounded backlog.
    local key = kind == 'criteria' and kind or (kind .. ':' .. tostring(id))
    if uiPending[key] or uiLast - uiFirst >= 63 then return end
    uiPending[key] = true
    uiLast = uiLast + 1
    uiJobs[uiLast] = { kind = kind, id = id, key = key }
    ensureUpdate()
end

local function queueAlert(id)
    if alertPending[id] or alertLast - alertFirst >= 31 then return end
    alertPending[id] = true
    alertLast = alertLast + 1
    alertQueue[alertLast] = id
    ensureUpdate()
end

local function runUiJob(job)
    local kind, id = job.kind, job.id
    if kind == 'summary' then summaryPending = false end
    if not AchievementFrame or not AchievementFrame:IsShown() then return end
    if kind == 'earned' then
        local frameAch = _G['AchievementFrameAchievements']
        if frameAch and AchievementFrameAchievements_OnEvent then
            safeCall('earned UI', AchievementFrameAchievements_OnEvent, frameAch, 'ACHIEVEMENT_EARNED', id)
        end
        if AchievementFrameSummaryCategory_OnEvent then
            for k, v in pairs(Achiever.achievementFrameSummaryCategorySubscribers) do
                safeCall('category UI', AchievementFrameSummaryCategory_OnEvent, v, 'ACHIEVEMENT_EARNED', id)
            end
        end
    elseif kind == 'criteria' then
        local frameAch = _G['AchievementFrameAchievements']
        if frameAch and AchievementFrameAchievements_OnEvent then
            safeCall('criteria UI', AchievementFrameAchievements_OnEvent, frameAch, 'CRITERIA_UPDATE', id)
        end
        local frameStats = _G['AchievementFrameStats']
        if frameStats and AchievementFrameStats_OnEvent then
            safeCall('stats UI', AchievementFrameStats_OnEvent, frameStats, 'CRITERIA_UPDATE', id)
        end
    elseif kind == 'summary' then
        summaryPending = false
        if AchievementFrameSummary_Update then safeCall('summary UI', AchievementFrameSummary_Update) end
    end
end

local numericFields = {
    AC = {1, 2, 3, 6, 7, 8, 9, 10, 12, 13},
    CA = {1, 2, 4},
    CR = {1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15},
    CH_AC = {1, 2}, AE = {1, 2}, CH_CR = {1, 2, 3}, ACU = {1, 2, 3, 4},
}
local function validNumber(value)
    local n = tonumber(value)
    return n and n == n and n ~= math.huge and n ~= -math.huge
        and math.abs(n) <= 9007199254740991 and n == math.floor(n)
end
local function removeIndex(index, key, order, id)
    local list = index[key]
    if list and list[order] == id then list[order] = nil end
end

local function handleServerMessage(self, message)
    local params = split(message, PAT_HASH)
    if params[1] ~= 'ACHI' then return end

    local cmd = params[2]
    if not cmd then return end

    local a, id
    if cmd ~= 'ACV' and cmd ~= 'CAV' and cmd ~= 'CRV' then
        if not numericFields[cmd] then return false end
        a = split(params[3], PAT_SEMI)
        for _, column in ipairs(numericFields[cmd]) do
            if not validNumber(a[column]) then return false end
        end
        id = tonumber(a[1])
        if id <= 0 then return false end
        local orderColumn = cmd == 'AC' and 8 or cmd == 'CA' and 4 or cmd == 'CR' and 15
        if orderColumn and (tonumber(a[orderColumn]) < 0 or tonumber(a[orderColumn]) > 100000) then return false end
        if cmd == 'AC' and (a[4] == nil or a[5] == nil or a[11] == nil) then return false end
        if cmd == 'CA' and a[3] == nil then return false end
        if cmd == 'CR' and a[10] == nil then return false end
    elseif not validNumber(params[3]) then
        return false
    end

    if cmd == 'AC' then
        if activeRequest and activeRequest.label == 'achievements' and not activeRequest.rowsStarted then
            local version = achieverDB.achievements.version
            achieverDB.achievements = newDB().achievements
            achieverDB.achievements.version = version
            activeRequest.rowsStarted = true
        end
        local data = achieverDB.achievements.data
        -- ha ugyanaz az achievement újra megérkezik, ne számoljuk duplán a pontot
        local old = data[id]
        if old and old.points then
            achieverDB.achievements.totalPoints = achieverDB.achievements.totalPoints - old.points
            removeIndex(achieverDB.achievements.byCategory, old.categoryId, old.order, id)
            local previous = achieverDB.achievements.previousById[id]
            if previous and achieverDB.achievements.nextById[previous] == id then
                achieverDB.achievements.nextById[previous] = nil
            end
            achieverDB.achievements.previousById[id] = nil
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
        if activeRequest and activeRequest.label == 'categories' and not activeRequest.rowsStarted then
            local version = achieverDB.categories.version
            achieverDB.categories = newDB().categories
            achieverDB.categories.version = version
            activeRequest.rowsStarted = true
        end
        local old = achieverDB.categories.data[id]
        if old then removeIndex(achieverDB.categories.byParent, tostring(old.parentId), old.order, id) end
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
        if activeRequest and activeRequest.label == 'criteria' and not activeRequest.rowsStarted then
            local version = achieverDB.criteria.version
            achieverDB.criteria = newDB().criteria
            achieverDB.criteria.version = version
            activeRequest.rowsStarted = true
        end
        local old = achieverDB.criteria.data[id]
        if old then removeIndex(achieverDB.criteria.byAchievement, old.achievementId, old.order, id) end
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
        local alreadyEarned = achieverDBpc.achievements[id] ~= nil
        achieverDBpc.achievements[id] = { date = tonumber(a[2]) }

        if not alreadyEarned then queueUi('earned', id) end
        if not summaryPending then
            summaryPending = true
            queueUi('summary', id)
        end

        local ad = achieverDB.achievements.data[id]
        if ad then debug("ACHIEVEMENT EARNED " .. tostring(ad.name)) end
        if not alreadyEarned then queueAlert(id) end
        ACHIEVER_STARTED = true

    elseif cmd == 'ACU' then
        achieverDBpc.criteria[id] = {
            achievementId = tonumber(a[2]),
            counter = tonumber(a[3]),
            date = tonumber(a[4]),
        }
        queueUi('criteria', id)
        ACHIEVER_STARTED = true

    else
        warn('server response: unhandled ' .. tostring(cmd))
    end
    self.received = self.received + 1
    if activeRequest and activeRequest.commands[cmd] then
        responseSeen, responseAge = true, 0
        activeRequest.packets = (activeRequest.packets or 0) + 1
        if numericFields[cmd] then activeRequest.rows = (activeRequest.rows or 0) + 1 end
    end
    return true
end

-- pcall: egy hibás / váratlan szerverüzenet sem okozhat Lua errort
Achiever.processServerMessage = function(self, message)
    self.incoming = self.incoming + 1
    if type(message) ~= 'string' or #message > 8192 then
        self.rejected = self.rejected + 1
        self.lastRejectedCommand = 'length/type'
        return false
    end
    local ok, result = pcall(handleServerMessage, self, message)
    if not ok then
        reportError('server message', result)
    elseif not result then
        self.rejected = self.rejected + 1
        self.lastRejectedCommand = string.sub(string.match(message, '^ACHI#([^#]+)') or 'prefix/format', 1, 40)
    end
    return ok and result
end

---------------------------------------------------------------------------
-- Szerver API (parancsok)
---------------------------------------------------------------------------
local function wireVersion(version)
    local n = tonumber(version)
    -- -1 is an INTERNAL missing-cache sentinel only. The server accepts an
    -- unsigned version: -1 becomes UINT_MAX and suppresses all snapshot data.
    if not n or n ~= n or n < 0 or n > 2147483647 or n ~= math.floor(n) then return 0 end
    return n
end
local function sendServerCommand(command)
    Achiever.lastCommand = command
    SendChatMessage(command)
end

Achiever.apiEnableDataSend = function(self, version)
    local v = wireVersion(version)
    debug('request to enable sending achievement info, ' .. tostring(v))
    sendServerCommand('.achievements enableAchiever ' .. v)
end
Achiever.apiRequestCategoryInfo = function(self, version)
    sendServerCommand('.achievements getCategories ' .. wireVersion(version))
end
Achiever.apiRequestAchievementInfo = function(self, version)
    sendServerCommand('.achievements getAchievements ' .. wireVersion(version))
end
Achiever.apiRequestCriteriaInfo = function(self, version)
    sendServerCommand('.achievements getCriteria ' .. wireVersion(version))
end
Achiever.apiRequestCharacterCriteria = function(self)
    debug('requested character criteria progress from server')
    if type(achieverDBpc.criteria) ~= 'table' then achieverDBpc.criteria = {} end
    sendServerCommand('.achievements getCharacterCriteria')
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

---------------------------------------------------------------------------
-- Indítás: késleltetve, egyszer, a kérések lassan egymás után mennek ki
---------------------------------------------------------------------------
local pending = {}
local pendingFirst, pendingLast = 1, 0
local waitTimer = 0
local startupTimer = 0
local worldEntered = false
local completedSteps, totalSteps = 0, 0
local syncAge = 0
local failedRequest
local stageNames = {
    categories = 'categories', achievements = 'achievement data', criteria = 'criteria data',
    ['character criteria'] = 'character criteria', ['character achievements'] = 'character achievements',
    enable = 'enable live updates',
}

-- This is real step/message progress, not an invented download percentage:
-- the protocol does not announce the total number of expected records.
function Achiever:GetSyncProgress()
    local request = activeRequest or failedRequest or pending[pendingFirst]
    local text = 'Achiever progress: ' .. completedSteps .. '/' .. totalSteps .. ' steps completed'
    if request then
        text = text .. '; current=' .. (stageNames[request.label] or request.label) ..
            '; records=' .. (request.rows or 0) .. '; packets=' .. (request.packets or 0)
        if activeRequest or failedRequest then
            text = text .. string.format('; step time=%.1fs; response idle=%.1fs', requestAge or 0, responseAge or 0)
            if not responseSeen and not request.noReply then
                text = text .. string.format('; first response timeout in=%.1fs', math.max(0, RESPONSE_TIMEOUT - (requestAge or 0)))
                if activeRequest then text = text .. '; WAITING FOR SERVER RESPONSE' end
            elseif activeRequest then
                text = text .. (responseSeen and '; RECEIVING/QUIET WINDOW' or '; EMPTY RESPONSE MAY BE VALID')
            end
        else
            text = text .. string.format('; sending in=%.1fs', math.max(0, REQUEST_SPACING - waitTimer))
        end
    elseif not ACHIEVER_INIT then
        text = 'Achiever progress: starting in ' .. string.format('%.1fs', math.max(0, STARTUP_DELAY - startupTimer))
    end
    return text .. string.format('; elapsed=%.1fs; received=%d; rejected=%d', syncAge, self.received, self.rejected) ..
        (not worldActive and '; PAUSED WHILE ZONING' or '')
end

function Achiever:PrintSyncProgress()
    warn(self:GetSyncProgress())
end

local function queueRequest(fn, commands, label, noReply)
    pendingLast = pendingLast + 1
    pending[pendingLast] = {fn = fn, commands = commands or {}, label = label, noReply = noReply}
    totalSteps = totalSteps + 1
end

Achiever.startup = function(self)
    if ACHIEVER_INIT then return end
    ACHIEVER_INIT = true

    ensureDB()

    local factionGroup = UnitFactionGroup("player")

    -- Old versions may have saved half a download as a valid cache.
    if ALWAYS_RELOAD or achieverDB.cacheSchema ~= 2 or not achieverDB.cacheClean
        or achieverDB.realm ~= GetRealmName() or achieverDB.faction ~= factionGroup then
        achieverDB = newDB()
    end
    achieverDB.cacheSchema = 2
    achieverDB.cacheClean = false
    achieverDB.realm = GetRealmName()
    achieverDB.faction = factionGroup
    self.state = 'syncing'
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
    -- No completion markers are known for the character snapshots: these use
    -- a quiet-window barrier, including the legitimate empty-character case.
    queueRequest(function() me:apiRequestCategoryInfo(achieverDB.categories.version) end,
        {CA = true, CAV = true}, 'categories', achieverDB.categories.version >= 0)
    queueRequest(function() me:apiRequestAchievementInfo(achieverDB.achievements.version) end,
        {AC = true, ACV = true}, 'achievements', achieverDB.achievements.version >= 0)
    queueRequest(function() me:apiRequestCriteriaInfo(achieverDB.criteria.version) end,
        {CR = true, CRV = true}, 'criteria', achieverDB.criteria.version >= 0)
    queueRequest(function() me:apiRequestCharacterCriteria() end,
        {CH_CR = true}, 'character criteria', true)
    -- Enabling with the old per-character 0 would request ALL static data a
    -- second time on servers whose enable handler also sends initial snapshots.
    queueRequest(function()
        me:apiEnableDataSend(math.min(achieverDB.categories.version,
            achieverDB.achievements.version, achieverDB.criteria.version))
    end,
        {}, 'enable', true)
end

onUpdate = function(frame, elapsed)
    local dt = elapsed or _G.arg1
    if type(dt) ~= 'number' then return end
    if not worldActive then return end
    -- Never let a long loading-screen frame skip all pacing barriers.
    dt = math.min(dt, 0.5)

    -- 1) várakozás a világba lépés után, majd indítás
    if not ACHIEVER_INIT then
        startupTimer = startupTimer + dt
        if startupTimer >= STARTUP_DELAY then
            Achiever:startup()
        end
        return
    end

    local busy = false
    if Achiever.state == 'syncing' then
        syncAge = syncAge + dt
    end

    -- 2) szerverparancsok kiküldése, egyesével
    if activeRequest then
        busy = true
        requestAge, responseAge = requestAge + dt, responseAge + dt
        local quiet = (responseSeen or activeRequest.label == 'enable') and RESPONSE_QUIET or 8.0
        if (responseSeen or activeRequest.noReply) and responseAge >= quiet then
            completedSteps = completedSteps + 1
            activeRequest = nil
            waitTimer = 0
        elseif (not responseSeen and requestAge >= RESPONSE_TIMEOUT) or requestAge >= TRANSFER_TIMEOUT then
            Achiever.state = 'sync-timeout'
            reportError('sync timeout', activeRequest.label)
            failedRequest = activeRequest
            activeRequest = nil
            pending, pendingFirst, pendingLast = {}, 1, 0
        end
    elseif pendingFirst <= pendingLast then
        busy = true
        waitTimer = waitTimer + dt
        if waitTimer >= REQUEST_SPACING then
            waitTimer = 0
            local request = pending[pendingFirst]
            pending[pendingFirst] = nil
            pendingFirst = pendingFirst + 1
            activeRequest = request
            requestAge, responseAge, responseSeen = 0, 0, false
            if not safeCall('request ' .. request.label, request.fn) then
                Achiever.state = 'sync-error'
                failedRequest = request
                activeRequest = nil
                pending, pendingFirst, pendingLast = {}, 1, 0
            end
        end
    end
    if Achiever.state == 'syncing' and not activeRequest and pendingFirst > pendingLast then
        -- A quiet window is a pacing heuristic, NOT a server acknowledgement.
        if not next(achieverDB.categories.data) or not next(achieverDB.achievements.data)
            or achieverDB.categories.version < 0 or achieverDB.achievements.version < 0
            or achieverDB.criteria.version < 0 then
            Achiever.state = 'sync-incomplete'
            reportError('sync incomplete', 'missing database or version markers')
        else
            Achiever.state = 'ready'
            achieverDB.cacheClean = true
            if not summaryPending then summaryPending = true; queueUi('summary', 0) end
        end
    end

    -- 3) UI-frissítések, egyesével
    if Achiever.state == 'ready' and uiFirst <= uiLast then
        busy = true
        uiTimer = uiTimer + dt
        if uiTimer >= UI_SPACING then
            uiTimer = 0
            local job = uiJobs[uiFirst]
            uiJobs[uiFirst] = nil
            uiPending[job.key] = nil
            uiFirst = uiFirst + 1
            if uiFirst > uiLast then uiJobs, uiFirst, uiLast = {}, 1, 0 end
            safeCall('UI job', runUiJob, job)
        end
    end

    -- 4) "achievement earned" ablakok, egyesével, időközönként
    if Achiever.state == 'ready' and alertFirst <= alertLast then
        busy = true
        if alertTimer < ALERT_SPACING then
            alertTimer = alertTimer + dt
        else
            alertTimer = 0
            local id = alertQueue[alertFirst]
            alertQueue[alertFirst] = nil
            alertPending[id] = nil
            alertFirst = alertFirst + 1
            if alertFirst > alertLast then alertQueue, alertFirst, alertLast = {}, 1, 0 end
            if AlertFrame_ShowAchievementEarned then
                safeCall('alert', AlertFrame_ShowAchievementEarned, id)
            end
        end
    elseif alertTimer < ALERT_SPACING then
        busy = true
        alertTimer = alertTimer + dt
    end

    -- ha nincs több teendő, az OnUpdate leáll
    if not busy then
        Achiever:SetScript("OnUpdate", nil)
    end
end

-- 2.4.3-ban a handlerek paramétereket és (régi módon) globálisokat is kaphatnak:
-- mindkettőt kezeljük, így biztosan nem lesz "OnEvent with no event".
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
        worldActive = true
        if not ACHIEVER_INIT then Achiever.state = 'waiting-startup' end
        -- Zónaváltásnál / töltőképernyőnél is lefut: csak az első alkalommal indítunk.
        if not worldEntered then
            worldEntered = true
            startupTimer = 0
            ensureUpdate()
        end
        if ACHIEVER_INIT then ensureUpdate() end

    elseif e == "PLAYER_LEAVING_WORLD" then
        worldActive = false

    elseif e == "CHAT_MSG_ADDON" or e == "CHAT_MSG_WHISPER" or e == "CHAT_MSG_SYSTEM" then
        if ACHIEVER_INIT then
            local msg
            -- CHAT_MSG_WHISPER: arg1 = üzenet; CHAT_MSG_ADDON: arg1 = prefix, arg2 = üzenet
            if e == "CHAT_MSG_ADDON" and (m1 == 'ACHI' or m1 == 'ACHI#') and type(m2) == 'string' then
                msg = string.find(m2, 'ACHI#', 1, true) == 1 and m2 or ('ACHI#' .. m2)
            elseif type(m1) == 'string' and string.find(m1, 'ACHI#', 1, true) == 1 then
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

---------------------------------------------------------------------------
-- Micro button / UI
---------------------------------------------------------------------------
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

    -- move nearby buttons
    if ( UnitLevel("player") < 10 ) then
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMLEFT", 0, 0);
        if QuestLogMicroButton then QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -2, 0); end
    else
        AchievementsMicroButton:SetPoint("BOTTOMLEFT", "TalentMicroButton", "BOTTOMRIGHT", -2, 0);
    end
    -- hide help button to free up space
    if HelpMicroButton then HelpMicroButton:Hide(); end
    if QuestLogMicroButton then QuestLogMicroButton:SetPoint("BOTTOMLEFT", "AchievementsMicroButton", "BOTTOMRIGHT", -3, 0); end

    -- Update main bar button
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
