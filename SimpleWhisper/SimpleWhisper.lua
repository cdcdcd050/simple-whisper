----------------------------------------------------------------------
-- SimpleWhisper (귓속말) — 간단한 귓속말 메신저
----------------------------------------------------------------------
local addonName = ...

-- UI strings (English default, Korean override below)
local locale = GetLocale()

local L = {
    TITLE           = "SimpleWhisper",
    LDB_LABEL       = "Whisper",
    CHAT_PREFIX     = "|cff00ccff[SW]|r",
    TOOLTIP_HINT    = "|cff00ff00Click|r to toggle window",
    NO_SELECTION    = "Select a conversation on the left.",
    SLASH_HELP      = "|cff00ccff/swsw|r — Toggle whisper window",
    CLOSE           = "Close",
    ME              = "Me",
    BTN_TIME        = "Time",
    BTN_DELETE      = "Delete",
    BTN_COPY        = "Copy",
    BTN_OPTIONS     = "Options",
    BTN_INVITE      = "Invite",
    BTN_DELETE_ALL  = "Del All",
    BTN_RESET       = "Reset",
    BTN_CANCEL      = "Cancel",
    OPT_SOUND       = "Notification sound",
    OPT_SOUND_SEL   = "Sound :",
    OPT_AUTO_OPEN   = "Auto-open on receive",
    OPT_COMBAT     = "In combat:",
    COMBAT_1       = "Instant",
    COMBAT_2       = "After",
    COMBAT_3       = "Never",
    COMBAT_TIP_1   = "Open immediately during combat",
    COMBAT_TIP_2   = "Open after combat ends",
    COMBAT_TIP_3   = "Do not open during combat",
    OPT_HIDE_CHAT   = "Hide whispers from chat",
    OPT_INTERCEPT   = "Open whispers here",
    OPT_ESC_CLOSE   = "ESC closes immediately",
    OPT_FONT_SIZE   = "Font size",
    OPT_OPACITY     = "Opacity",
    SND_1           = "Whisper",
    SND_2           = "Auction",
    SND_3           = "Custom",
    URL_DIALOG      = "Copy this URL:",
    CONFIRM_DELETE  = "Delete conversation with %s?",
    CONFIRM_DEL_ALL = "Delete all conversations?\n(Settings will be kept)",
    CONFIRM_RESET   = "Reset all settings?\n(Conversations will be kept)",
    COPY_TITLE      = "Ctrl+C to copy",
    MSG_SOUND_ON    = "Notification sound enabled.",
    MSG_SOUND_OFF   = "Notification sound disabled.",
    MSG_CUSTOM_SND  = "Place sw3.ogg in SimpleWhisper/Sounds/ folder.",
    MSG_AUTO_ON     = "Window will auto-open on whisper.",
    MSG_AUTO_OFF    = "Window will not auto-open on whisper.",
    MSG_HIDE_ON     = "Whispers hidden from chat frame.",
    MSG_HIDE_OFF    = "Whispers shown in chat frame.",
    MSG_INTCPT_ON   = "Whispers will open in SimpleWhisper.",
    MSG_INTCPT_OFF  = "Whispers will open in default chat.",
    MSG_ESC_ON      = "ESC will close window immediately.",
    MSG_ESC_OFF     = "ESC will unfocus first, then close.",
    MSG_ALL_DEL     = "All conversations deleted.",
    UNREAD_FMT      = "Unread: |cffff3333%d|r",
    WHO_REFRESH     = "Refresh",
    WHO_OFFLINE     = "Offline",
    COPY_WHO        = "[Who]",
    COPY_SYS        = "[System]",
    MEMO_HINT       = "Click to type...",
    MEMO_FMT        = "%s memo:",
    WHO_LEVEL_PAT   = "^Level (%d+)",
    WHO_TOTAL_PAT   = "(%d+) players? total",
    WHO_NOTFOUND_PAT = "not found",
    READ_MARKER     = "Read up to here",
}

----------------------------------------------------------------------
-- 데이터 구조 (세션 전용)
----------------------------------------------------------------------
local conversations = {}   -- ["이름"] = { {who, msg, time}, ... }
local nameList = {}        -- 최근 활동순
local unreadCounts = {}    -- ["이름"] = 숫자
local selectedName = nil
local mainFrame = nil
local ldbObject = nil
local pendingWhoName = nil  -- /who 조회 대상
local pendingWhoTimer = nil  -- /who 타임아웃 타이머
local whoFilterUntil = 0  -- /who 시스템 메시지 필터 만료 시간
local pendingCombatNames = {}  -- 전투 중 보류된 대화 이름 목록
local lastReadIndices = {}   -- ["이름"] = 마지막 읽은 메시지 인덱스
local AddMessage             -- forward declare (WHO_LIST_UPDATE 콜백에서 사용)
local RefreshNameList        -- forward declare (AddMessage에서 사용)
local RefreshChatDisplay     -- forward declare (WHO_LIST_UPDATE 콜백에서 사용)

----------------------------------------------------------------------
-- 유틸리티
----------------------------------------------------------------------
local function ShortName(fullName)
    return Ambiguate(fullName, "none")
end

-- BNet 친구 이름 해석: bnID → 배틀태그 또는 계정명
local function ResolveBNetName(bnID)
    if not bnID then return nil end
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local info = C_BattleNet.GetAccountInfoByID(bnID)
        if info then
            return info.battleTag or info.accountName
        end
    elseif BNGetFriendInfoByID then
        local _, accountName, battleTag = BNGetFriendInfoByID(bnID)
        return battleTag or accountName
    end
    return nil
end

-- BNet 친구의 현재 캐릭터 이름 조회
local function GetBNetToonName(bnID)
    if not bnID then return nil end
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local info = C_BattleNet.GetAccountInfoByID(bnID)
        if info and info.gameAccountInfo then
            return info.gameAccountInfo.characterName
        end
    elseif BNGetFriendInfoByID then
        local _, _, _, _, characterName = BNGetFriendInfoByID(bnID)
        return characterName
    end
    return nil
end

-- BNet 메시지 발송 (Retail/Classic 호환)
local function SendBNetWhisper(bnID, text)
    if C_BattleNet and C_BattleNet.SendWhisper then
        C_BattleNet.SendWhisper(bnID, text)
    elseif BNSendWhisper then
        BNSendWhisper(bnID, text)
    end
end

local function TimeStamp()
    return date("%H:%M:%S")
end

-- Class name → token mapping for /who results
local CLASS_NAME_TO_TOKEN = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Death Knight"] = "DEATHKNIGHT",
    ["Shaman"] = "SHAMAN", ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK",
    ["Monk"] = "MONK", ["Druid"] = "DRUID", ["Demon Hunter"] = "DEMONHUNTER",
    ["Evoker"] = "EVOKER",
}


if locale == "koKR" then
    L.TITLE         = "심플귓속말"
    L.LDB_LABEL     = "귓속말"
    L.CHAT_PREFIX   = "|cff00ccff[귓속말]|r"
    L.TOOLTIP_HINT  = "|cff00ff00클릭|r하여 창 열기/닫기"
    L.NO_SELECTION  = "왼쪽에서 대화 상대를 선택하세요."
    L.SLASH_HELP    = "|cff00ccff/swsw|r — 귓속말 창 열기/닫기"
    L.CLOSE         = "닫기"
    L.ME            = "나"
    L.BTN_TIME      = "시간"
    L.BTN_DELETE    = "삭제"
    L.BTN_COPY      = "복사"
    L.BTN_OPTIONS   = "옵션"
    L.BTN_INVITE    = "초대"
    L.BTN_DELETE_ALL = "전체삭제"
    L.BTN_RESET     = "초기화"
    L.BTN_CANCEL    = "취소"
    L.OPT_SOUND     = "수신 알림 소리"
    L.OPT_SOUND_SEL = "소리 선택 :"
    L.OPT_AUTO_OPEN = "수신 시 자동 열기"
    L.OPT_COMBAT    = "전투중:"
    L.COMBAT_1      = "즉시"
    L.COMBAT_2      = "종료후"
    L.COMBAT_3      = "안열기"
    L.COMBAT_TIP_1  = "전투 중에도 즉시 열기"
    L.COMBAT_TIP_2  = "전투 종료 후 열기"
    L.COMBAT_TIP_3  = "전투 중에는 열지 않기"
    L.OPT_HIDE_CHAT = "기본 채팅창에서 귓속말 숨기기"
    L.OPT_INTERCEPT = "귓속말 보낼 때 여기서 열기"
    L.OPT_ESC_CLOSE = "ESC 클릭 시 즉시 닫기"
    L.OPT_FONT_SIZE = "글꼴 크기"
    L.OPT_OPACITY   = "불투명도"
    L.SND_1         = "귓속말 알림"
    L.SND_2         = "경매장"
    L.SND_3         = "커스텀"
    L.URL_DIALOG    = "URL을 복사하세요:"
    L.CONFIRM_DELETE = "%s 님과의 대화를 삭제합니다."
    L.CONFIRM_DEL_ALL = "모든 대화를 삭제합니다.\n(설정은 유지됩니다)"
    L.CONFIRM_RESET = "모든 설정을 기본값으로 초기화합니다.\n(대화 내용은 유지됩니다)"
    L.COPY_TITLE    = "Ctrl+C로 복사"
    L.MSG_SOUND_ON  = "귓속말 수신 시 알림 소리가 재생됩니다."
    L.MSG_SOUND_OFF = "귓속말 수신 시 알림 소리가 꺼집니다."
    L.MSG_CUSTOM_SND = "sw3.ogg 파일을 만들어 SimpleWhisper/Sounds/ 에 넣으세요."
    L.MSG_AUTO_ON   = "귓속말을 받으면 창이 자동으로 열립니다."
    L.MSG_AUTO_OFF  = "귓속말을 받아도 창이 자동으로 열리지 않습니다."
    L.MSG_HIDE_ON   = "채팅창에서 귓속말이 숨겨집니다."
    L.MSG_HIDE_OFF  = "채팅창에서 귓속말이 표시됩니다."
    L.MSG_INTCPT_ON = "귓속말을 보낼 때 심플귓속말 창이 열립니다."
    L.MSG_INTCPT_OFF = "귓속말을 보낼 때 기본 채팅창이 열립니다."
    L.MSG_ESC_ON    = "ESC를 누르면 창이 즉시 닫힙니다."
    L.MSG_ESC_OFF   = "ESC를 누르면 포커스 해제 후 닫힙니다."
    L.MSG_ALL_DEL   = "모든 대화가 삭제되었습니다."
    L.UNREAD_FMT    = "안 읽은 메시지: |cffff3333%d|r"
    L.WHO_REFRESH   = "새로고침"
    L.WHO_OFFLINE   = "오프라인"
    L.COPY_WHO      = "[조회]"
    L.COPY_SYS      = "[시스템]"
    L.MEMO_HINT     = "클릭하여 입력..."
    L.MEMO_FMT      = "%s 메모:"
    L.READ_MARKER   = "여기까지 읽음"
    L.WHO_LEVEL_PAT = "^(%d+)레벨"
    L.WHO_TOTAL_PAT = "모두%s+(%d+)%s*명"
    L.WHO_NOTFOUND_PAT = "찾지 못했습니다"
    CLASS_NAME_TO_TOKEN = {
        ["전사"] = "WARRIOR", ["성기사"] = "PALADIN", ["사냥꾼"] = "HUNTER",
        ["도적"] = "ROGUE", ["사제"] = "PRIEST", ["죽음의 기사"] = "DEATHKNIGHT",
        ["주술사"] = "SHAMAN", ["마법사"] = "MAGE", ["흑마법사"] = "WARLOCK",
        ["수도사"] = "MONK", ["드루이드"] = "DRUID", ["악마사냥꾼"] = "DEMONHUNTER",
        ["기원사"] = "EVOKER",
    }
end

-- 채팅에서 수집한 직업 캐시 (이름 → 직업)
local classCache = {}

local classCacheFrame = CreateFrame("Frame")
classCacheFrame:RegisterEvent("CHAT_MSG_CHANNEL")
classCacheFrame:RegisterEvent("CHAT_MSG_SAY")
classCacheFrame:RegisterEvent("CHAT_MSG_YELL")
classCacheFrame:RegisterEvent("CHAT_MSG_GUILD")
classCacheFrame:RegisterEvent("CHAT_MSG_PARTY")
classCacheFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
classCacheFrame:RegisterEvent("CHAT_MSG_RAID")
classCacheFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
classCacheFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
classCacheFrame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
classCacheFrame:SetScript("OnEvent", function(self, event, _, fullName, _, _, _, _, _, _, _, _, _, guid)
    if guid and guid ~= "" and fullName then
        local _, englishClass = GetPlayerInfoByGUID(guid)
        if englishClass then
            local name = Ambiguate(fullName, "none")
            classCache[name] = englishClass
        end
    end
end)

local function ResolveClass(name)
    -- 채팅 캐시
    if classCache[name] then return classCache[name] end
    -- 대상/포커스/마우스오버
    for _, unitId in ipairs({"target", "focus", "mouseover"}) do
        if UnitName(unitId) == name then
            local _, englishClass = UnitClass(unitId)
            if englishClass then return englishClass end
        end
    end
    -- 파티/공격대
    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumGroupMembers() - 1
    end
    if prefix then
        for i = 1, count do
            local unitId = prefix .. i
            if UnitName(unitId) == name then
                local _, englishClass = UnitClass(unitId)
                if englishClass then return englishClass end
            end
        end
    end
    return nil
end

local function EnsureConversation(name, fullName, isBN, bnID)
    if not conversations[name] then
        conversations[name] = { fullName = fullName or name }
    elseif fullName and fullName ~= name then
        conversations[name].fullName = fullName
    end
    -- BNet 정보 저장
    if isBN then
        conversations[name].isBN = true
    end
    if bnID then
        conversations[name].bnID = bnID
    end
    -- BNet이 아닌 경우만 직업 탐색
    if not conversations[name].isBN then
        if not conversations[name].class then
            conversations[name].class = ResolveClass(name)
        end
        if not conversations[name].class and conversations[name].guid then
            local _, englishClass = GetPlayerInfoByGUID(conversations[name].guid)
            if englishClass then
                conversations[name].class = englishClass
            end
        end
    end
end

-- nameList에서 name을 맨 앞으로 이동 (최근 활동순)
local function BumpName(name)
    for i, n in ipairs(nameList) do
        if n == name then
            table.remove(nameList, i)
            break
        end
    end
    table.insert(nameList, 1, name)
end

----------------------------------------------------------------------
-- 소리 재생
----------------------------------------------------------------------
local SOUND_OPTIONS = {
    { name = L.SND_1, file = "Sound\\Interface\\iTellMessage.ogg" },
    { name = L.SND_2, file = "Sound\\Interface\\AuctionWindowOpen.ogg" },
    { name = L.SND_3, file = "Interface\\AddOns\\SimpleWhisper\\Sounds\\sw3.ogg" },
}

local function PlayWhisperSound()
    if SimpleWhisper_DB and SimpleWhisper_DB.soundEnabled then
        local idx = SimpleWhisper_DB.soundChoice or 1
        local snd = SOUND_OPTIONS[idx]
        if snd then
            PlaySoundFile(snd.file, "Master")
        end
    end
end

----------------------------------------------------------------------
-- LDB (Arcana) 연동
----------------------------------------------------------------------
local minimapBadge = nil  -- 미니맵 배지 (ADDON_LOADED 후 설정됨)

local function UpdateLDBText()
    local total = 0
    for _, c in pairs(unreadCounts) do
        total = total + c
    end
    if ldbObject then
        if total > 0 then
            ldbObject.text = L.LDB_LABEL .. "(|cffff3333" .. total .. "|r)"
        else
            ldbObject.text = L.LDB_LABEL .. "(0)"
        end
    end
    if minimapBadge then
        if total > 0 then
            minimapBadge.text:SetText(total)
            minimapBadge:Show()
            minimapBadge.icon:SetVertexColor(1, 0.5, 0.7)
        else
            minimapBadge:Hide()
            minimapBadge.icon:SetVertexColor(1, 1, 1)
        end
    end
end

----------------------------------------------------------------------
-- 메시지 추가
----------------------------------------------------------------------
AddMessage = function(name, dir, text, fullName)
    EnsureConversation(name, fullName)
    local entry = { who = dir, msg = text, time = TimeStamp(), date = date("%Y-%m-%d") }
    table.insert(conversations[name], entry)
    if dir ~= "sys" then
        BumpName(name)
    end

    if dir == "in" and name ~= selectedName then
        unreadCounts[name] = (unreadCounts[name] or 0) + 1
        UpdateLDBText()
    end
    if mainFrame and mainFrame:IsShown() then
        if dir == "out" then
            RefreshNameList()
            mainFrame.nameScroll:SetVerticalScroll(0)
        elseif dir == "in" and name ~= selectedName then
            RefreshNameList()
        end
    end
end

----------------------------------------------------------------------
-- /who 조회 공통 함수
----------------------------------------------------------------------
local function SendWhoQuery(charName)
    if pendingWhoName then return end
    if mainFrame and mainFrame.whoCooldown and mainFrame.whoCooldown > 0 then return end  -- 전역 쿨타임
    -- 누구 목록(O창)이 열려있고 강제 조회가 아니면 캐시에서 추출
    if FriendsFrame and FriendsFrame:IsShown() then
        if C_FriendList and C_FriendList.GetNumWhoResults then
            local numResults = C_FriendList.GetNumWhoResults() or 0
            for i = 1, numResults do
                local info = C_FriendList.GetWhoInfo(i)
                if info and info.fullName then
                    local whoShort = Ambiguate(info.fullName, "none")
                    if whoShort == charName then
                        if info.filename and conversations[charName] then
                            conversations[charName].class = info.filename
                        end
                        if conversations[charName] then
                            if info.level and info.level > 0 then
                                conversations[charName].whoLevel = info.level
                            end
                            conversations[charName].whoGuild = (info.fullGuildName and info.fullGuildName ~= "") and info.fullGuildName or nil
                        end
                        if mainFrame then
                            RefreshNameList()
                            if mainFrame.whoInfoText and charName == selectedName then
                                local display = charName .. " LV." .. (info.level or "?")
                                if info.fullGuildName and info.fullGuildName ~= "" then
                                    display = display .. " <" .. info.fullGuildName .. ">"
                                end
                                mainFrame.whoInfoText:SetText("|cff00ff00" .. display .. "|r")
                            end
                            if mainFrame.refreshBtn then
                                mainFrame.refreshBtn:Hide()
                                mainFrame.whoCooldown = 0
                            end
                        end
                        break
                    end
                end
            end
        end
        return
    end
    local conv = conversations[charName]
    if not conv or conv.isBN then return end
    whoFilterUntil = GetTime() + 7
    local fullName = conv.fullName or charName
    pendingWhoName = charName
    -- 새로고침 버튼 쿨다운 시작 (2초 후부터 카운트 표시 — 즉시 응답 시 안 보임)
    if mainFrame and mainFrame.refreshBtn then
        mainFrame.refreshBtn:Hide()
        mainFrame.whoCooldown = 5
        if mainFrame.whoCooldownTicker then mainFrame.whoCooldownTicker:Cancel() end
        mainFrame.whoCooldownTicker = C_Timer.After(2, function()
            if not mainFrame or mainFrame.whoCooldown <= 0 then return end
            mainFrame.whoCooldown = 3
            mainFrame.refreshBtn:Show()
            mainFrame.refreshText:SetText("|cffaaaaaa3|r")
            mainFrame.refreshText:SetTextColor(0.5, 0.5, 0.5)
            mainFrame.whoCooldownTicker = C_Timer.NewTicker(1, function(ticker)
                mainFrame.whoCooldown = mainFrame.whoCooldown - 1
                if mainFrame.whoCooldown > 0 then
                    mainFrame.refreshText:SetText("|cffaaaaaa" .. mainFrame.whoCooldown .. "|r")
                else
                    ticker:Cancel()
                    mainFrame.whoCooldownTicker = nil
                    mainFrame.refreshText:SetText(L.WHO_REFRESH)
                    mainFrame.refreshText:SetTextColor(0.5, 0.8, 0.5)
                end
            end)
        end)
    end
    if pendingWhoTimer then pendingWhoTimer:Cancel() end
    local whoTarget = charName
    pendingWhoTimer = C_Timer.NewTimer(1, function()
        if not pendingWhoName or pendingWhoName ~= whoTarget then
            pendingWhoTimer = nil
            return
        end
        pendingWhoName = nil
        pendingWhoTimer = nil
        -- 누구 목록 UI 복원
        if C_FriendList and C_FriendList.SetWhoToUI then
            C_FriendList.SetWhoToUI(true)
        elseif SetWhoToUI then
            SetWhoToUI(1)
        end
    end)
    -- 누구 목록 UI 표시 억제
    if C_FriendList and C_FriendList.SetWhoToUI then
        C_FriendList.SetWhoToUI(false)
    elseif SetWhoToUI then
        SetWhoToUI(0)
    end
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(fullName)
    elseif SlashCmdList["WHO"] then
        SlashCmdList["WHO"](fullName)
    else
        pendingWhoName = nil
        if pendingWhoTimer then pendingWhoTimer:Cancel(); pendingWhoTimer = nil end
    end
end

----------------------------------------------------------------------
-- UI 생성 (lazy)
----------------------------------------------------------------------
local SelectConversation  -- forward declare
local DeleteConversation  -- forward declare

RefreshNameList = function()
    if not mainFrame then return end
    local buttons = mainFrame.nameButtons
    -- 기존 버튼 숨기기
    for _, btn in ipairs(buttons) do btn:Hide() end

    for i, name in ipairs(nameList) do
        local btn = buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, mainFrame.nameContent)
            local btnH = (SimpleWhisper_DB.fontSize or 12) + 9
            btn:SetSize(mainFrame.nameScroll:GetWidth(), btnH)
            btn:SetNormalFontObject("GameFontNormal")
            btn:SetHighlightFontObject("GameFontHighlight")
            btn:SetText(" ")  -- FontString 생성용
            btn:GetFontString():SetJustifyH("LEFT")
            btn:GetFontString():SetWordWrap(false)
            btn:GetFontString():SetNonSpaceWrap(false)
            btn:GetFontString():SetPoint("LEFT", 4, 0)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.15)
            local selBg = btn:CreateTexture(nil, "BACKGROUND")
            selBg:SetAllPoints()
            selBg:SetColorTexture(1, 1, 1, 0.15)
            selBg:Hide()
            local selBar = btn:CreateTexture(nil, "OVERLAY")
            selBar:SetPoint("TOPLEFT", 0, 0)
            selBar:SetPoint("BOTTOMLEFT", 0, 0)
            selBar:SetWidth(3)
            selBar:SetColorTexture(1, 0.82, 0, 1)
            selBar:Hide()
            btn.selTex = selBg
            btn.selBar = selBar
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" then
                    local fullName = conversations[self.charName] and conversations[self.charName].fullName or self.charName
                    if FriendsFrame_ShowDropdown then
                        FriendsFrame_ShowDropdown(fullName, true)
                    else
                        ChatFrame_SendTell(fullName)
                    end
                else
                    SelectConversation(self.charName)
                    SendWhoQuery(self.charName)
                end
            end)
            buttons[i] = btn
        end
        btn:ClearAllPoints()
        local btnH = (SimpleWhisper_DB.fontSize or 12) + 9
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * btnH)
        btn.charName = name

        local label = name
        local count = unreadCounts[name] or 0
        if count > 0 then
            label = label .. " |cffff3333(" .. count .. ")|r"
        end
        btn:SetText(label)
        -- 직업 색상, BNet 색상, 또는 기본 색상
        local conv = conversations[name]
        if conv and conv.isBN then
            btn:GetFontString():SetTextColor(0, 0.706, 0.847) -- BNet 청록색
        elseif conv and conv.class and RAID_CLASS_COLORS[conv.class] then
            local cc = RAID_CLASS_COLORS[conv.class]
            btn:GetFontString():SetTextColor(cc.r, cc.g, cc.b)
        else
            btn:GetFontString():SetTextColor(0.9, 0.9, 0.9)
        end
        -- 선택된 대화 배경 하이라이트
        if name == selectedName then
            btn.selTex:Show()
            if btn.selBar then btn.selBar:Show() end
        else
            btn.selTex:Hide()
            if btn.selBar then btn.selBar:Hide() end
        end
        btn:Show()
    end
    mainFrame.nameContent:SetHeight(math.max(1, #nameList * ((SimpleWhisper_DB.fontSize or 12) + 9)))
end

local function LinkifyURLs(text)
    text = text:gsub("([Hh][Tt][Tt][Pp][Ss]?://[%w%.%-_~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", "|cff4488ff|Hurl:%1|h[%1]|h|r")
    text = text:gsub("([Ww][Ww][Ww]%.[%w%.%-_~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+)", "|cff4488ff|Hurl:http://%1|h[%1]|h|r")
    return text
end

RefreshChatDisplay = function()
    if not mainFrame then return end
    local msgFrame = mainFrame.chatDisplay
    msgFrame:Clear()
    if not selectedName or not conversations[selectedName] then
        msgFrame:AddMessage("|cff888888" .. L.NO_SELECTION .. "|r")
        return
    end
    local lastDate = nil
    local readIdx = lastReadIndices[selectedName]
    local totalMsgs = #conversations[selectedName]
    for i, entry in ipairs(conversations[selectedName]) do
        local isReadBoundary = readIdx and readIdx > 0 and readIdx < totalMsgs and i == readIdx + 1
        local entryDate = entry.date
        local isNewDate = entryDate and entryDate ~= lastDate
        local dateTimeStr = entryDate and entry.time and (entryDate .. " " .. entry.time) or entryDate

        if isReadBoundary and isNewDate then
            -- 날짜가 바뀌면 날짜+시간만 표시 (읽음 마커 생략)
            msgFrame:AddMessage("|cff666666————————————————————————|r")
            msgFrame:AddMessage("|cff888888— " .. dateTimeStr .. " —|r")
            lastDate = entryDate
        elseif isReadBoundary then
            msgFrame:AddMessage("|cff666666————————————————————————|r")
            msgFrame:AddMessage("|cffffcc00— " .. L.READ_MARKER .. " —|r")
            msgFrame:AddMessage("|cff666666————————————————————————|r")
        elseif isNewDate then
            if lastDate then
                msgFrame:AddMessage("|cff666666————————————————————————|r")
            end
            msgFrame:AddMessage("|cff888888— " .. dateTimeStr .. " —|r")
            lastDate = entryDate
        end
        local line
        local conv = conversations[selectedName]
        local fullName = conv.fullName or selectedName
        local isBN = conv.isBN
        local timePrefix = SimpleWhisper_DB.showTime and ("|cffaaaaaa[" .. entry.time .. "]|r ") or ""
        local msg = LinkifyURLs(entry.msg)
        if entry.who == "in" then
            if isBN then
                line = string.format("%s|cff00b4d8%s|r: |cff00b4d8%s|r",
                    timePrefix, selectedName, msg)
            else
                line = string.format("%s|cffff88ff|Hplayer:%s|h%s|h|r: |cffff88ff%s|r",
                    timePrefix, fullName, selectedName, msg)
            end
        elseif entry.who == "who" then
            line = string.format("%s|cff00ff00%s|r", timePrefix, msg)
        elseif entry.who == "sys" then
            line = string.format("%s|cffff4444%s|r", timePrefix, msg)
        else
            local myName = UnitName("player") or L.ME
            if isBN then
                line = string.format("%s|cff2ca2ff%s|r: |cff2ca2ff%s|r",
                    timePrefix, myName, msg)
            else
                line = string.format("%s|cffffbbdd%s|r: |cffffbbdd%s|r",
                    timePrefix, myName, msg)
            end
        end
        msgFrame:AddMessage(line)
    end
    if mainFrame.scrollDownBtn then
        mainFrame.scrollDownBtn:SetShown(not msgFrame:AtBottom())
    end
end

SelectConversation = function(name, noFocus)
    local prevName = selectedName
    if prevName and prevName ~= name and conversations[prevName] then
        lastReadIndices[prevName] = #conversations[prevName]
    end
    selectedName = name
    unreadCounts[name] = 0
    UpdateLDBText()
    if mainFrame then
        mainFrame.deleteBtn:Enable()
        -- BNet 대화는 초대 불가 (크로스 게임일 수 있음)
        local conv = conversations[name]
        if conv and conv.isBN then
            mainFrame.inviteBtn:Disable()
        else
            mainFrame.inviteBtn:Enable()
        end
        RefreshNameList()
        RefreshChatDisplay()
        mainFrame.inputBox:SetText("")
        -- 저장된 /who 정보 즉시 표시
        if mainFrame.whoInfoText then
            local conv = conversations[name]
            if conv and conv.whoLevel then
                local display = name .. " LV." .. conv.whoLevel
                if conv.whoGuild then
                    display = display .. " <" .. conv.whoGuild .. ">"
                end
                mainFrame.whoInfoText:SetText("|cff00ff00" .. display .. "|r")
            elseif name ~= prevName then
                mainFrame.whoInfoText:SetText("")
            end
        end
        if not noFocus then
            mainFrame.inputBox:SetFocus()
        end
        -- 메모 로드
        mainFrame.memoLabel:SetText(string.format(L.MEMO_FMT, name))
        local memo = conversations[name] and conversations[name].memo or ""
        mainFrame.memoBox:SetText(memo)
        mainFrame.memoBox.hint:SetShown(memo == "")
    end
end

DeleteConversation = function(name)
    conversations[name] = nil
    unreadCounts[name] = nil
    lastReadIndices[name] = nil
    for i, n in ipairs(nameList) do
        if n == name then
            table.remove(nameList, i)
            break
        end
    end
    if selectedName == name then
        selectedName = nil
    end
    if mainFrame then
        mainFrame.deleteBtn:Disable()
        mainFrame.inviteBtn:Disable()
        if mainFrame.whoInfoText then mainFrame.whoInfoText:SetText("") end
        if mainFrame.refreshBtn then mainFrame.refreshBtn:Hide() end
    end
    UpdateLDBText()
    RefreshNameList()
    RefreshChatDisplay()
end

local function CreateMainFrame()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "SimpleWhisperFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(450, 298)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(300, 200, 800, 600)
    elseif f.SetMinResize then
        f:SetMinResize(300, 200)
        f:SetMaxResize(800, 600)
    end
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- 배경
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 1)

    -- 통합 툴바 (드래그 핸들 + 옵션 버튼)
    local optBar = CreateFrame("Frame", nil, f)
    optBar:SetHeight(24)
    optBar:SetPoint("TOPLEFT", 6, -6)
    optBar:SetPoint("TOPRIGHT", -6, -6)
    optBar:EnableMouse(true)
    optBar:RegisterForDrag("LeftButton")
    optBar:SetScript("OnDragStart", function() f:StartMoving() end)
    optBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        SimpleWhisper_DB.windowPos = { point = point, x = x, y = y }
    end)

    local toolbarBg = optBar:CreateTexture(nil, "BACKGROUND")
    toolbarBg:SetAllPoints()
    toolbarBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local toolbarBottom = f:CreateTexture(nil, "ARTWORK")
    toolbarBottom:SetHeight(1)
    toolbarBottom:SetPoint("LEFT", f, "LEFT", 8, 0)
    toolbarBottom:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    toolbarBottom:SetPoint("TOP", optBar, "BOTTOM", 0, 0)
    toolbarBottom:SetColorTexture(0.6, 0.5, 0.3, 0.6)

    -- /who 정보 표시 (제목 바 우측)
    local whoInfoText = optBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whoInfoText:SetPoint("LEFT", optBar, "LEFT", 8, 0)
    whoInfoText:SetTextColor(0, 1, 0, 0.9)
    whoInfoText:SetText("")
    f.whoInfoText = whoInfoText

    -- /who 새로고침 버튼 (제목 바, whoInfoText 우측)
    local refreshBtn = CreateFrame("Button", nil, optBar)
    refreshBtn:SetSize(50, 16)
    refreshBtn:SetPoint("LEFT", whoInfoText, "RIGHT", 6, 0)
    local refreshText = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refreshText:SetAllPoints()
    refreshText:SetText("")
    refreshBtn:SetScript("OnClick", function()
        if not selectedName then return end
        if pendingWhoName then return end  -- 조회 중이면 무시
        if f.whoCooldown and f.whoCooldown > 0 then return end  -- 쿨다운 중이면 무시
        SendWhoQuery(selectedName)
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        if f.whoCooldown and f.whoCooldown > 0 then return end
        refreshText:SetTextColor(1, 1, 1)
    end)
    refreshBtn:SetScript("OnLeave", function(self)
        if f.whoCooldown and f.whoCooldown > 0 then return end
        refreshText:SetTextColor(0.5, 0.8, 0.5)
    end)
    refreshText:SetTextColor(0.5, 0.8, 0.5)
    refreshBtn:Hide()
    f.refreshBtn = refreshBtn
    f.refreshText = refreshText
    f.whoCooldown = 0

    -- 햄버거 메뉴 버튼 (채팅 영역 우측 상단)
    local hamburgerBtn = CreateFrame("Button", nil, f)
    hamburgerBtn:SetSize(26, 26)
    hamburgerBtn:SetPoint("TOPRIGHT", -12, -30)
    hamburgerBtn:SetFrameStrata("FULLSCREEN")
    local hamburgerText = hamburgerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hamburgerText:SetPoint("CENTER", 0, 0)
    local hFont, _, hFlags = hamburgerText:GetFont()
    hamburgerText:SetFont(hFont, 22, hFlags)
    hamburgerText:SetText("≡")
    hamburgerBtn:SetScript("OnEnter", function(self)
        hamburgerText:SetTextColor(1, 1, 0)
    end)
    hamburgerBtn:SetScript("OnLeave", function(self)
        hamburgerText:SetTextColor(1, 0.82, 0)
    end)

    -- 이름 목록 토글 버튼 (채팅 영역 좌측 상단)
    local nameToggleBtn = CreateFrame("Button", nil, f)
    nameToggleBtn:SetSize(20, 26)
    nameToggleBtn:SetPoint("TOPLEFT", 10, -115)
    nameToggleBtn:SetFrameStrata("FULLSCREEN")
    local nameToggleText = nameToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameToggleText:SetPoint("CENTER", 0, 0)
    local ntFont, _, ntFlags = nameToggleText:GetFont()
    nameToggleText:SetFont(ntFont, 16, ntFlags)
    nameToggleText:SetText("◀")
    nameToggleBtn:SetAlpha(0.25)
    nameToggleBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        nameToggleText:SetTextColor(1, 1, 0)
        if f.divLine and not SimpleWhisper_DB.nameListHidden then
            f.divLine:SetColorTexture(0.8, 0.7, 0.4, 0.9)
            f.divLine:SetWidth(2)
        end
    end)
    nameToggleBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.25)
        nameToggleText:SetTextColor(1, 0.82, 0)
        if f.divLine and f.divider and not f.divider.dragging then
            f.divLine:SetColorTexture(0.4, 0.4, 0.4, 0.6)
            f.divLine:SetWidth(1)
        end
    end)

    local TOP_WITH_TOOLBAR = -34
    local TOP_WITHOUT_TOOLBAR = -8
    f.toolbarBottom = toolbarBottom

    local HAMBURGER_Y_WITH_TOOLBAR = -30
    local HAMBURGER_Y_WITHOUT_TOOLBAR = -10


    local function SetNameListVisible(visible)
        SimpleWhisper_DB.nameListHidden = not visible
        if f.nameScroll then f.nameScroll:SetShown(visible) end
        if f.divider then f.divider:SetShown(visible) end

        local top = SimpleWhisper_DB.toolbarHidden and TOP_WITHOUT_TOOLBAR or TOP_WITH_TOOLBAR
        if visible then
            local dx = SimpleWhisper_DB.dividerX or 100
            if f.chatDisplay then
                f.chatDisplay:ClearAllPoints()
                f.chatDisplay:SetPoint("TOPLEFT", dx + 6, top)
                f.chatDisplay:SetPoint("BOTTOMRIGHT", -4, 60)
            end
            if f.inputBox then
                f.inputBox:ClearAllPoints()
                f.inputBox:SetPoint("BOTTOMLEFT", dx + 6, 28)
                f.inputBox:SetPoint("BOTTOMRIGHT", -10, 28)
            end
            nameToggleText:SetText("◀")
            -- 디바이더에 앵커링 (디바이더가 있으면)
            if f.divider then
                nameToggleBtn:ClearAllPoints()
                nameToggleBtn:SetPoint("CENTER", f.divider, "CENTER", -12, 0)
            end
        else
            if f.chatDisplay then
                f.chatDisplay:ClearAllPoints()
                f.chatDisplay:SetPoint("TOPLEFT", 8, top)
                f.chatDisplay:SetPoint("BOTTOMRIGHT", -4, 60)
            end
            if f.inputBox then
                f.inputBox:ClearAllPoints()
                f.inputBox:SetPoint("BOTTOMLEFT", 8, 28)
                f.inputBox:SetPoint("BOTTOMRIGHT", -10, 28)
            end
            nameToggleText:SetText("▶")
            nameToggleBtn:ClearAllPoints()
            local closedTop = SimpleWhisper_DB.toolbarHidden and TOP_WITHOUT_TOOLBAR or TOP_WITH_TOOLBAR
            nameToggleBtn:SetPoint("TOPLEFT", 10, closedTop)
            nameToggleBtn:SetPoint("BOTTOMLEFT", 10, 26)
        end
    end
    f.SetNameListVisible = SetNameListVisible

    local function SetToolbarVisible(visible)
        SimpleWhisper_DB.toolbarHidden = not visible
        optBar:SetShown(visible)
        toolbarBottom:SetShown(visible)
        local top = visible and TOP_WITH_TOOLBAR or TOP_WITHOUT_TOOLBAR
        local nameListVisible = not SimpleWhisper_DB.nameListHidden
        if nameListVisible then
            if f.nameScroll then
                f.nameScroll:SetPoint("TOPLEFT", 8, top)
            end
            if f.chatDisplay then
                local dx = SimpleWhisper_DB.dividerX or 100
                f.chatDisplay:SetPoint("TOPLEFT", dx + 6, top)
            end
            -- divider
            local dx = SimpleWhisper_DB.dividerX or 100
            if f.divider then
                f.divider:SetPoint("TOPLEFT", dx - 3, top)
            end
        else
            if f.chatDisplay then
                f.chatDisplay:ClearAllPoints()
                f.chatDisplay:SetPoint("TOPLEFT", 8, top)
                f.chatDisplay:SetPoint("BOTTOMRIGHT", -4, 60)
            end
        end
        -- 햄버거 버튼 위치 이동
        hamburgerBtn:ClearAllPoints()
        hamburgerBtn:SetPoint("TOPRIGHT", -12, visible and HAMBURGER_Y_WITH_TOOLBAR or HAMBURGER_Y_WITHOUT_TOOLBAR)
        -- 이름 목록 토글 버튼 위치 이동 (접힌 상태에서만 재배치, 펼침 시 디바이더 앵커)
        if SimpleWhisper_DB.nameListHidden then
            nameToggleBtn:ClearAllPoints()
            nameToggleBtn:SetPoint("TOPLEFT", 10, visible and TOP_WITH_TOOLBAR or TOP_WITHOUT_TOOLBAR)
            nameToggleBtn:SetPoint("BOTTOMLEFT", 10, 26)
        end
    end
    f.SetToolbarVisible = SetToolbarVisible

    hamburgerBtn:SetScript("OnClick", function()
        local willShow = not optBar:IsShown()
        SetToolbarVisible(willShow)
    end)

    nameToggleBtn:SetScript("OnClick", function()
        local willShow = SimpleWhisper_DB.nameListHidden
        SetNameListVisible(willShow)
    end)

    local function ShrinkButtonFont(btn)
        local fs = btn:GetFontString()
        if fs then
            local font, size, flags = fs:GetFont()
            fs:SetFont(font, size - 1, flags)
        end
        btn:SetWidth(math.max(24, btn:GetTextWidth() + 16))
    end

    local timeBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    timeBtn:SetHeight(20)
    timeBtn:SetPoint("LEFT", 0, 0)
    timeBtn:SetText(L.BTN_TIME)
    ShrinkButtonFont(timeBtn)
    timeBtn:SetScript("OnClick", function()
        SimpleWhisper_DB.showTime = not SimpleWhisper_DB.showTime
        RefreshChatDisplay()
    end)

    StaticPopupDialogs["SW_URL_DIALOG"] = {
        text = L.URL_DIALOG,
        hasEditBox = true,
        OnShow = function(self, data)
            self.EditBox:SetText(data.url)
            self.EditBox:HighlightText()
            self.EditBox:SetFocus()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        button1 = L.CLOSE,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["SIMPLEWHISPER_DELETE"] = {
        text = L.CONFIRM_DELETE,
        button1 = L.BTN_DELETE,
        button2 = L.BTN_CANCEL,
        OnAccept = function()
            if selectedName then
                DeleteConversation(selectedName)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local deleteBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    deleteBtn:SetHeight(20)
    deleteBtn:SetText(L.BTN_DELETE)
    ShrinkButtonFont(deleteBtn)
    deleteBtn:Disable()
    deleteBtn:SetScript("OnClick", function()
        if selectedName then
            StaticPopup_Show("SIMPLEWHISPER_DELETE", selectedName)
        end
    end)
    f.deleteBtn = deleteBtn

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("RIGHT", 0, 0)
    closeBtn:SetText("X")
    ShrinkButtonFont(closeBtn)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- 옵션 버튼
    local optBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    optBtn:SetHeight(20)
    optBtn:SetPoint("RIGHT", closeBtn, "LEFT", -1, 0)
    optBtn:SetText(L.BTN_OPTIONS)
    ShrinkButtonFont(optBtn)

    -- 옵션 패널
    local optPanel = CreateFrame("Frame", nil, f,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    optPanel:SetHeight(160) -- 임시, SizeOptPanel에서 재계산
    optPanel:SetPoint("TOPRIGHT", optBtn, "BOTTOMRIGHT", 0, -2)
    optPanel:SetFrameStrata("TOOLTIP")
    optPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    optPanel:SetIgnoreParentAlpha(true)
    optPanel:SetAlpha(1)
    optPanel:Hide()

    local soundCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    soundCheck:SetSize(20, 20)
    soundCheck:SetPoint("TOPLEFT", 6, -6)
    soundCheck:SetChecked(SimpleWhisper_DB.soundEnabled)
    soundCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.soundEnabled = self:GetChecked()
        if self:GetChecked() then
            print(L.CHAT_PREFIX .. " " .. L.MSG_SOUND_ON)
        else
            print(L.CHAT_PREFIX .. " " .. L.MSG_SOUND_OFF)
        end
    end)
    local soundLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundLabel:SetPoint("LEFT", soundCheck, "RIGHT", 2, 0)
    soundLabel:SetText(L.OPT_SOUND)

    -- 소리 선택 행 (수신 알림 소리 아래)
    local soundSelectLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundSelectLabel:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 22, -4)
    soundSelectLabel:SetText(L.OPT_SOUND_SEL)

    local soundBtns = {}
    local function UpdateSoundBtns()
        local idx = SimpleWhisper_DB.soundChoice or 1
        for i, btn in ipairs(soundBtns) do
            if i == idx then
                btn:GetFontString():SetTextColor(1, 1, 0)
            else
                btn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end
    for i = 1, #SOUND_OPTIONS do
        local btn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
        btn:SetHeight(16)
        btn:SetText(i)
        ShrinkButtonFont(btn)
        if i == 1 then
            btn:SetPoint("LEFT", soundSelectLabel, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", soundBtns[i - 1], "RIGHT", 0, 0)
        end
        btn:SetScript("OnClick", function()
            SimpleWhisper_DB.soundChoice = i
            UpdateSoundBtns()
            PlaySoundFile(SOUND_OPTIONS[i].file, "Master")
            if i == #SOUND_OPTIONS then
                print(L.CHAT_PREFIX .. " " .. L.MSG_CUSTOM_SND)
            end
        end)
        soundBtns[i] = btn
    end
    UpdateSoundBtns()

    local autoOpenCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    autoOpenCheck:SetSize(20, 20)
    autoOpenCheck:SetPoint("TOPLEFT", soundSelectLabel, "BOTTOMLEFT", -22, -4)
    autoOpenCheck:SetChecked(SimpleWhisper_DB.autoOpen ~= false)
    local autoOpenLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoOpenLabel:SetPoint("LEFT", autoOpenCheck, "RIGHT", 2, 0)
    autoOpenLabel:SetText(L.OPT_AUTO_OPEN)

    -- 전투 중 수신: 버튼 3개 (즉시/종료후/안열기)
    local combatLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    combatLabel:SetPoint("TOPLEFT", autoOpenCheck, "BOTTOMLEFT", 22, -6)
    combatLabel:SetText(L.OPT_COMBAT)

    local combatBtns = {}
    local COMBAT_LABELS = { L.COMBAT_1, L.COMBAT_2, L.COMBAT_3 }
    local function UpdateCombatBtns()
        local idx = SimpleWhisper_DB.combatMode or 1
        for i, btn in ipairs(combatBtns) do
            if i == idx then
                btn:GetFontString():SetTextColor(1, 1, 0)
            else
                btn:GetFontString():SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end
    for i = 1, 3 do
        local btn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
        btn:SetHeight(16)
        btn:SetText(COMBAT_LABELS[i])
        ShrinkButtonFont(btn)
        if i == 1 then
            btn:SetPoint("TOPLEFT", combatLabel, "BOTTOMLEFT", 0, -2)
        else
            btn:SetPoint("LEFT", combatBtns[i - 1], "RIGHT", 0, 0)
        end
        local COMBAT_TIPS = { L.COMBAT_TIP_1, L.COMBAT_TIP_2, L.COMBAT_TIP_3 }
        btn:SetScript("OnClick", function()
            SimpleWhisper_DB.combatMode = i
            UpdateCombatBtns()
            print(L.CHAT_PREFIX .. " " .. COMBAT_TIPS[i])
        end)
        combatBtns[i] = btn
    end
    UpdateCombatBtns()

    local function SetCombatBtnsEnabled(enabled)
        for _, btn in ipairs(combatBtns) do
            if enabled then btn:Enable() else btn:Disable() end
        end
        combatLabel:SetFontObject(enabled and "GameFontNormalSmall" or "GameFontDisableSmall")
        if enabled then
            UpdateCombatBtns()
        else
            for _, btn in ipairs(combatBtns) do
                btn:GetFontString():SetTextColor(0.4, 0.4, 0.4)
            end
        end
    end
    -- autoOpen OnClick (SetCombatBtnsEnabled 정의 후 설정)
    autoOpenCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.autoOpen = self:GetChecked()
        if self:GetChecked() then
            print(L.CHAT_PREFIX .. " " .. L.MSG_AUTO_ON)
        else
            print(L.CHAT_PREFIX .. " " .. L.MSG_AUTO_OFF)
        end
        SetCombatBtnsEnabled(self:GetChecked())
    end)
    -- 초기 상태
    if not (SimpleWhisper_DB.autoOpen ~= false) then
        SetCombatBtnsEnabled(false)
    end

    local hideChatCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    hideChatCheck:SetSize(20, 20)
    hideChatCheck:SetPoint("TOPLEFT", autoOpenCheck, "BOTTOMLEFT", 0, -40)
    hideChatCheck:SetChecked(SimpleWhisper_DB.hideFromChat or false)
    hideChatCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.hideFromChat = self:GetChecked()
        if self:GetChecked() then
            print(L.CHAT_PREFIX .. " " .. L.MSG_HIDE_ON)
        else
            print(L.CHAT_PREFIX .. " " .. L.MSG_HIDE_OFF)
        end
    end)
    local hideChatLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideChatLabel:SetPoint("LEFT", hideChatCheck, "RIGHT", 2, 0)
    hideChatLabel:SetText(L.OPT_HIDE_CHAT)

    local interceptCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    interceptCheck:SetSize(20, 20)
    interceptCheck:SetPoint("TOPLEFT", hideChatCheck, "BOTTOMLEFT", 0, -2)
    interceptCheck:SetChecked(SimpleWhisper_DB.interceptWhisper ~= false)
    interceptCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.interceptWhisper = self:GetChecked()
        if self:GetChecked() then
            print(L.CHAT_PREFIX .. " " .. L.MSG_INTCPT_ON)
        else
            print(L.CHAT_PREFIX .. " " .. L.MSG_INTCPT_OFF)
        end
    end)
    local interceptLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interceptLabel:SetPoint("LEFT", interceptCheck, "RIGHT", 2, 0)
    interceptLabel:SetText(L.OPT_INTERCEPT)

    local escCloseCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    escCloseCheck:SetSize(20, 20)
    escCloseCheck:SetPoint("TOPLEFT", interceptCheck, "BOTTOMLEFT", 0, -2)
    escCloseCheck:SetChecked(SimpleWhisper_DB.escClose ~= false)
    escCloseCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.escClose = self:GetChecked()
        if self:GetChecked() then
            print(L.CHAT_PREFIX .. " " .. L.MSG_ESC_ON)
        else
            print(L.CHAT_PREFIX .. " " .. L.MSG_ESC_OFF)
        end
    end)
    local escCloseLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    escCloseLabel:SetPoint("LEFT", escCloseCheck, "RIGHT", 2, 0)
    escCloseLabel:SetText(L.OPT_ESC_CLOSE)

    -- 구분선: 외형 설정
    local optDivider = optPanel:CreateTexture(nil, "ARTWORK")
    optDivider:SetHeight(1)
    optDivider:SetPoint("TOPLEFT", escCloseCheck, "BOTTOMLEFT", 0, -6)
    optDivider:SetPoint("RIGHT", optPanel, "RIGHT", -6, 0)
    optDivider:SetColorTexture(0.5, 0.5, 0.5, 0.4)

    -- 슬라이더 트랙 바 추가 헬퍼
    local function AddSliderTrack(slider)
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(4)
        track:SetPoint("LEFT", 4, 0)
        track:SetPoint("RIGHT", -4, 0)
        track:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    end

    -- 폰트 크기 슬라이더
    local fontSizeLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeLabel:SetPoint("TOPLEFT", optDivider, "BOTTOMLEFT", 0, -8)
    fontSizeLabel:SetText(L.OPT_FONT_SIZE)

    local fontSizeValue = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeValue:SetPoint("LEFT", fontSizeLabel, "RIGHT", 4, 0)
    fontSizeValue:SetText((SimpleWhisper_DB.fontSize or 12) .. "pt")

    local fontSizeSlider = CreateFrame("Slider", nil, optPanel, "OptionsSliderTemplate")
    fontSizeSlider:SetHeight(17)
    fontSizeSlider:SetPoint("RIGHT", optPanel, "RIGHT", -8, 0)
    fontSizeSlider:SetPoint("TOPLEFT", fontSizeLabel, "BOTTOMLEFT", 2, -8)
    fontSizeSlider:SetMinMaxValues(10, 22)
    fontSizeSlider:SetValueStep(1)
    fontSizeSlider:SetObeyStepOnDrag(true)
    fontSizeSlider:SetValue(SimpleWhisper_DB.fontSize or 12)
    fontSizeSlider.Low:SetText("")
    fontSizeSlider.High:SetText("")
    AddSliderTrack(fontSizeSlider)

    -- 불투명도 체크박스 + 슬라이더
    local opacityCheck = CreateFrame("CheckButton", nil, optPanel, "UICheckButtonTemplate")
    opacityCheck:SetSize(20, 20)
    opacityCheck:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", -2, -8)
    opacityCheck:SetChecked(SimpleWhisper_DB.opacityEnabled or false)

    local opacityLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("LEFT", opacityCheck, "RIGHT", 2, 0)
    opacityLabel:SetText(L.OPT_OPACITY)

    local opacityValue = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityValue:SetPoint("LEFT", opacityLabel, "RIGHT", 4, 0)

    local opacitySlider = CreateFrame("Slider", nil, optPanel, "OptionsSliderTemplate")
    opacitySlider:SetHeight(17)
    opacitySlider:SetPoint("RIGHT", optPanel, "RIGHT", -8, 0)
    opacitySlider:SetPoint("TOPLEFT", opacityCheck, "BOTTOMLEFT", 2, -10)
    opacitySlider:SetMinMaxValues(0.3, 1.0)
    opacitySlider:SetValueStep(0.05)
    opacitySlider:SetObeyStepOnDrag(true)
    opacitySlider:SetValue(SimpleWhisper_DB.opacity or 0.85)
    opacitySlider.Low:SetText("")
    opacitySlider.High:SetText("")
    AddSliderTrack(opacitySlider)

    local function ApplyOpacity()
        if SimpleWhisper_DB.opacityEnabled then
            local val = SimpleWhisper_DB.opacity or 0.85
            f:SetAlpha(val)
            opacityValue:SetText(math.floor(val * 100) .. "%")
            opacitySlider:Enable()
        else
            f:SetAlpha(1.0)
            opacityValue:SetText("100%")
            opacitySlider:Disable()
        end
    end

    opacityCheck:SetScript("OnClick", function(self)
        SimpleWhisper_DB.opacityEnabled = self:GetChecked()
        ApplyOpacity()
    end)

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        SimpleWhisper_DB.opacity = value
        if SimpleWhisper_DB.opacityEnabled then
            opacityValue:SetText(math.floor(value * 100) .. "%")
            f:SetAlpha(value)
        end
    end)

    ApplyOpacity()

    fontSizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        SimpleWhisper_DB.fontSize = value
        fontSizeValue:SetText(value .. "pt")
        if f.ApplyFontSize then
            f.ApplyFontSize()
        end
    end)

    -- 초기화 구분선
    local resetDivider = optPanel:CreateTexture(nil, "ARTWORK")
    resetDivider:SetHeight(1)
    resetDivider:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", -4, -10)
    resetDivider:SetPoint("RIGHT", optPanel, "RIGHT", -6, 0)
    resetDivider:SetColorTexture(0.5, 0.5, 0.5, 0.4)

    -- 대화 전체 삭제 버튼
    StaticPopupDialogs["SIMPLEWHISPER_DELETE_ALL"] = {
        text = L.CONFIRM_DEL_ALL,
        button1 = L.BTN_DELETE,
        button2 = L.BTN_CANCEL,
        OnAccept = function()
            wipe(conversations)
            wipe(nameList)
            wipe(unreadCounts)
            wipe(lastReadIndices)
            selectedName = nil
            UpdateLDBText()
            if mainFrame then
                mainFrame.deleteBtn:Disable()
                mainFrame.inviteBtn:Disable()
                mainFrame.memoBox:SetText("")
                mainFrame.memoBox.hint:Show()
                mainFrame.memoLabel:SetText("")
                if mainFrame.whoInfoText then mainFrame.whoInfoText:SetText("") end
                if mainFrame.refreshBtn then mainFrame.refreshBtn:Hide() end
            end
            RefreshNameList()
            RefreshChatDisplay()
            print(L.CHAT_PREFIX .. " " .. L.MSG_ALL_DEL)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local deleteAllBtn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
    deleteAllBtn:SetHeight(20)
    deleteAllBtn:SetPoint("TOP", resetDivider, "BOTTOM", 0, -6)
    deleteAllBtn:SetText(L.BTN_DELETE_ALL)
    ShrinkButtonFont(deleteAllBtn)
    deleteAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("SIMPLEWHISPER_DELETE_ALL")
    end)

    -- 초기화 버튼
    local resetBtn = CreateFrame("Button", nil, optPanel, "UIPanelButtonTemplate")
    resetBtn:SetHeight(20)
    resetBtn:SetPoint("TOP", deleteAllBtn, "BOTTOM", 0, -4)
    resetBtn:SetText(L.BTN_RESET)
    ShrinkButtonFont(resetBtn)

    StaticPopupDialogs["SIMPLEWHISPER_RESET"] = {
        text = L.CONFIRM_RESET,
        button1 = L.BTN_RESET,
        button2 = L.BTN_CANCEL,
        OnAccept = function()
            -- 기본값 적용
            SimpleWhisper_DB.soundEnabled = true
            SimpleWhisper_DB.showTime = false
            SimpleWhisper_DB.autoOpen = true
            SimpleWhisper_DB.combatMode = 1
            SimpleWhisper_DB.hideFromChat = true
            SimpleWhisper_DB.interceptWhisper = true
            SimpleWhisper_DB.escClose = true
            SimpleWhisper_DB.opacityEnabled = true
            SimpleWhisper_DB.opacity = 0.85
            SimpleWhisper_DB.fontSize = 12
            SimpleWhisper_DB.toolbarHidden = false
            SimpleWhisper_DB.nameListHidden = false
            SimpleWhisper_DB.windowPos = { point = "CENTER", x = 0, y = 0 }
            SimpleWhisper_DB.windowSize = nil
            SimpleWhisper_DB.dividerX = 100

            -- UI 반영
            soundCheck:SetChecked(true)
            SimpleWhisper_DB.showTime = false
            autoOpenCheck:SetChecked(true)
            UpdateCombatBtns()
            SetCombatBtnsEnabled(true)
            hideChatCheck:SetChecked(true)
            interceptCheck:SetChecked(true)
            escCloseCheck:SetChecked(true)
            opacityCheck:SetChecked(true)
            opacitySlider:SetValue(0.85)
            fontSizeSlider:SetValue(12)
            ApplyOpacity()
            if f.ApplyFontSize then f.ApplyFontSize() end
            SetToolbarVisible(true)
            SetNameListVisible(true)

            -- 창 위치/크기 초기화
            f:ClearAllPoints()
            f:SetPoint("CENTER")
            f:SetSize(450, 298)
            f.UpdatePanelWidths(100)
            RefreshNameList()
            RefreshChatDisplay()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("SIMPLEWHISPER_RESET")
    end)

    local tocVersion = (C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version")) or (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or ""
    local versionText = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("TOP", resetBtn, "BOTTOM", 0, -4)
    versionText:SetText("|cff888888v" .. tocVersion .. "|r")

    local optLabels = { soundLabel, autoOpenLabel, hideChatLabel, interceptLabel, escCloseLabel, opacityLabel, fontSizeLabel }

    -- 옵션 패널 크기 계산 (높이: 고정 합산, 너비: 텍스트 측정)
    -- 세로: 앵커 체인 합산
    local optH = 6                           -- 상단 여백
        + 20 + 4                             -- soundCheck + gap
        + 16 + 4                             -- soundSelectLabel행 + gap
        + 6 + 12 + 2 + 16 + 4               -- 전투 중 라벨 + 버튼행 (autoOpen 아래)
        + (20 + 2) * 4                       -- hideChat~escCloseCheck (4개 × (20+2))
        + 6 + 1                              -- gap + optDivider
        + 8 + 12 + 8 + 17                   -- gap + fontSizeLabel + gap + fontSizeSlider
        + 8 + 20 + 10 + 17                  -- gap + opacityCheck + gap + opacitySlider
        + 10 + 1                             -- gap + resetDivider
        + 6 + 20 + 4 + 20                   -- gap + deleteAllBtn + gap + resetBtn
        + 4 + 12                             -- gap + versionText
        + 6                                  -- 하단 여백
    optPanel:SetHeight(optH)

    -- 가로: 라벨/소리행 너비 측정
    local maxW = 0
    for _, lbl in ipairs(optLabels) do
        local w = lbl:GetStringWidth()
        if w > maxW then maxW = w end
    end
    local panelW = maxW + 20 + 2 + 12       -- 체크박스(20) + 간격(2) + 여백(12)
    local soundRowW = 22 + soundSelectLabel:GetStringWidth() + 4
    for _, btn in ipairs(soundBtns) do
        soundRowW = soundRowW + btn:GetWidth()
    end
    soundRowW = soundRowW + 12
    -- 전투 중 버튼행 (라벨과 버튼이 별도 줄)
    local combatRowW = 22
    for _, btn in ipairs(combatBtns) do
        combatRowW = combatRowW + btn:GetWidth()
    end
    combatRowW = combatRowW + 12
    panelW = math.max(panelW, soundRowW, combatRowW, 130)
    optPanel:SetWidth(panelW)

    -- 옵션 패널 외부 클릭 시 닫기
    optPanel:SetScript("OnShow", function()
        optPanel:SetScript("OnUpdate", function()
            if not optPanel:IsMouseOver() and not optBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                optPanel:Hide()
            end
        end)
    end)
    optPanel:SetScript("OnHide", function()
        optPanel:SetScript("OnUpdate", nil)
    end)

    optBtn:SetScript("OnClick", function()
        if optPanel:IsShown() then optPanel:Hide() else optPanel:Show() end
    end)

    -- 복사 팝업
    local copyFrame = CreateFrame("Frame", "SimpleWhisperCopyFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    copyFrame:SetSize(400, 300)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    copyFrame:Hide()
    table.insert(UISpecialFrames, "SimpleWhisperCopyFrame")

    local copyClose = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
    copyClose:SetPoint("TOPRIGHT", -2, -2)
    copyClose:SetScript("OnClick", function() copyFrame:Hide() end)

    local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copyTitle:SetPoint("TOPLEFT", 10, -10)
    copyTitle:SetText(L.COPY_TITLE)

    local copyScroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", 10, -30)
    copyScroll:SetPoint("BOTTOMRIGHT", -30, 10)

    local copyBox = CreateFrame("EditBox", nil, copyScroll)
    copyBox:SetMultiLine(true)
    copyBox:SetMaxLetters(0)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject("ChatFontNormal")
    copyBox:SetWidth(340)
    copyScroll:SetScrollChild(copyBox)
    copyBox:SetScript("OnEscapePressed", function() copyFrame:Hide() end)

    local inviteBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    inviteBtn:SetHeight(20)
    inviteBtn:SetPoint("RIGHT", optBtn, "LEFT", -1, 0)
    inviteBtn:SetText(L.BTN_INVITE)
    ShrinkButtonFont(inviteBtn)
    inviteBtn:Disable()
    inviteBtn:SetScript("OnClick", function()
        if not selectedName then return end
        local fullName = conversations[selectedName] and conversations[selectedName].fullName or selectedName
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(fullName)
        else
            InviteUnit(fullName)
        end
    end)
    f.inviteBtn = inviteBtn

    local copyBtn = CreateFrame("Button", nil, optBar, "UIPanelButtonTemplate")
    copyBtn:SetHeight(20)
    copyBtn:SetPoint("RIGHT", inviteBtn, "LEFT", -1, 0)
    copyBtn:SetText(L.BTN_COPY)
    ShrinkButtonFont(copyBtn)
    copyBtn:SetScript("OnClick", function()
        if not selectedName or not conversations[selectedName] then return end
        local lines = {}
        local lastDate = nil
        local readIdx = lastReadIndices[selectedName]
        local totalMsgs = #conversations[selectedName]
        for i, entry in ipairs(conversations[selectedName]) do
            local isReadBoundary = readIdx and readIdx > 0 and readIdx < totalMsgs and i == readIdx + 1
            local entryDate = entry.date
            local isNewDate = entryDate and entryDate ~= lastDate
            local dateTimeStr = entryDate and entry.time and (entryDate .. " " .. entry.time) or entryDate

            if isReadBoundary and isNewDate then
                table.insert(lines, "————————————————")
                table.insert(lines, "— " .. dateTimeStr .. " —")
                lastDate = entryDate
            elseif isReadBoundary then
                table.insert(lines, "————————————————")
                table.insert(lines, "— " .. L.READ_MARKER .. " —")
                table.insert(lines, "————————————————")
            elseif isNewDate then
                if lastDate then
                    table.insert(lines, "————————————————")
                end
                table.insert(lines, "— " .. dateTimeStr .. " —")
                lastDate = entryDate
            end
            local timePrefix = entry.time and ("[" .. entry.time .. "] ") or ""
            if entry.who == "in" then
                table.insert(lines, timePrefix .. selectedName .. ": " .. entry.msg)
            elseif entry.who == "who" then
                table.insert(lines, timePrefix .. L.COPY_WHO .. " " .. entry.msg)
            elseif entry.who == "sys" then
                table.insert(lines, timePrefix .. L.COPY_SYS .. " " .. entry.msg)
            else
                local myName = UnitName("player") or L.ME
                table.insert(lines, timePrefix .. myName .. ": " .. entry.msg)
            end
        end
        local text = table.concat(lines, "\n")
        copyBox:SetText(text)
        copyBox:SetWidth(copyScroll:GetWidth())
        copyFrame:Show()
        copyBox:HighlightText()
        copyBox:SetFocus()
    end)

    -- 구분선 (드래그 가능)
    local dividerWidth = SimpleWhisper_DB.dividerX or 100
    -- 시간표시 버튼을 대화삭제 왼쪽으로 이동
    timeBtn:ClearAllPoints()
    timeBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -1, 0)

    deleteBtn:SetPoint("RIGHT", copyBtn, "LEFT", -1, 0)
    local divider = CreateFrame("Frame", nil, f)
    f.divider = divider
    divider:SetWidth(12)
    divider:SetPoint("TOPLEFT", dividerWidth - 3, -34)
    divider:SetPoint("BOTTOMLEFT", dividerWidth - 3, 26)
    divider:EnableMouse(true)
    divider:RegisterForDrag("LeftButton")

    -- 이름 목록 토글 버튼을 디바이더에 앵커링 (펼침 상태일 때)
    if not SimpleWhisper_DB.nameListHidden then
        nameToggleBtn:ClearAllPoints()
        nameToggleBtn:SetPoint("CENTER", divider, "CENTER", -12, 0)
    end

    local divLine = divider:CreateTexture(nil, "ARTWORK")
    divLine:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    divLine:SetWidth(1)
    divLine:SetPoint("TOP", 0, 0)
    divLine:SetPoint("BOTTOM", 0, 0)
    f.divLine = divLine

    divider:SetScript("OnEnter", function(self)
        SetCursor("UI_RESIZE_CURSOR")
        divLine:SetColorTexture(0.8, 0.7, 0.4, 0.9)
        divLine:SetWidth(2)
    end)
    divider:SetScript("OnLeave", function(self)
        if not self.dragging then
            SetCursor(nil)
            divLine:SetColorTexture(0.4, 0.4, 0.4, 0.6)
            divLine:SetWidth(1)
        end
    end)

    local function UpdatePanelWidths(dx)
        local listW = dx - 8
        if listW < 10 then listW = 10 end
        if listW > 220 then listW = 220 end
        dx = listW + 8

        local top = SimpleWhisper_DB.toolbarHidden and -8 or -34
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", dx - 3, top)
        divider:SetPoint("BOTTOMLEFT", dx - 3, 26)

        f.nameScroll:ClearAllPoints()
        f.nameScroll:SetPoint("TOPLEFT", 8, top)
        f.nameScroll:SetPoint("BOTTOMLEFT", 8, 26)
        f.nameScroll:SetWidth(listW)
        f.nameContent:SetWidth(listW)

        f.chatDisplay:ClearAllPoints()
        f.chatDisplay:SetPoint("TOPLEFT", dx + 6, top)
        f.chatDisplay:SetPoint("BOTTOMRIGHT", -4, 60)

        f.inputBox:ClearAllPoints()
        f.inputBox:SetPoint("BOTTOMLEFT", dx + 6, 28)
        f.inputBox:SetPoint("BOTTOMRIGHT", -10, 28)

        -- 이름 버튼 너비 갱신
        for _, btn in ipairs(f.nameButtons) do
            btn:SetWidth(listW)
        end

        SimpleWhisper_DB.dividerX = dx

        -- 이름 목록 토글 버튼은 디바이더에 앵커되어 자동으로 따라감
    end
    f.UpdatePanelWidths = UpdatePanelWidths

    divider:SetScript("OnDragStart", function(self)
        self.dragging = true
        SetCursor("UI_RESIZE_CURSOR")
        self:SetScript("OnUpdate", function(self)
            SetCursor("UI_RESIZE_CURSOR")
            local cx = GetCursorPosition()
            local scale = f:GetEffectiveScale()
            local fx = f:GetLeft() * scale
            local dx = (cx - fx) / scale
            UpdatePanelWidths(dx)
        end)
    end)
    divider:SetScript("OnDragStop", function(self)
        self.dragging = false
        SetCursor(nil)
        divLine:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        divLine:SetWidth(1)
        self:SetScript("OnUpdate", nil)
    end)

    ----------------------------------------------------------------
    -- 왼쪽 패널: 이름 목록
    ----------------------------------------------------------------
    local listW = dividerWidth - 8
    local nameScroll = CreateFrame("ScrollFrame", "SimpleWhisperNameScroll", f)
    nameScroll:SetPoint("TOPLEFT", 8, -34)
    nameScroll:SetPoint("BOTTOMLEFT", 8, 26)
    nameScroll:SetWidth(listW)
    nameScroll:EnableMouseWheel(true)
    nameScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        local step = 22  -- 버튼 높이 1줄분
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, cur - step))
        else
            self:SetVerticalScroll(math.min(max, cur + step))
        end
    end)
    f.nameScroll = nameScroll

    local nameContent = CreateFrame("Frame", nil, nameScroll)
    nameContent:SetSize(listW, 1)
    nameScroll:SetScrollChild(nameContent)
    f.nameContent = nameContent
    f.nameButtons = {}

    ----------------------------------------------------------------
    -- 오른쪽 상단: 대화 내용 (ScrollingMessageFrame)
    ----------------------------------------------------------------
    local chatDisplay = CreateFrame("ScrollingMessageFrame", nil, f)
    chatDisplay:SetPoint("TOPLEFT", dividerWidth + 6, -34)
    chatDisplay:SetPoint("BOTTOMRIGHT", -4, 60)
    chatDisplay:SetFontObject("ChatFontNormal")
    chatDisplay:SetJustifyH("LEFT")

    -- 폰트 크기는 inputBox 생성 후 적용됨 (아래 ApplyFontSize 참조)
    chatDisplay:SetMaxLines(128)
    chatDisplay:SetFading(false)
    chatDisplay:EnableMouse(true)
    chatDisplay:RegisterForDrag("LeftButton")
    chatDisplay:SetScript("OnDragStart", function() f:StartMoving() end)
    chatDisplay:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, _, x, y = f:GetPoint()
        SimpleWhisper_DB.windowPos = { point = point, x = x, y = y }
    end)
    chatDisplay:EnableMouseWheel(true)
    chatDisplay:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
        f.scrollDownBtn:SetShown(not self:AtBottom())
    end)
    chatDisplay:SetHyperlinksEnabled(true)
    chatDisplay:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local linkType, value = link:match("^(%a+):(.+)$")
        if linkType == "url" then
            StaticPopup_Show("SW_URL_DIALOG", nil, nil, { url = value })
            return
        end
        SetItemRef(link, text, button, self)
    end)
    f.chatDisplay = chatDisplay

    -- 맨 아래로 스크롤 버튼
    local scrollDownBtn = CreateFrame("Button", nil, f)
    scrollDownBtn:SetFrameStrata("FULLSCREEN")
    scrollDownBtn:SetSize(24, 24)
    scrollDownBtn:SetPoint("BOTTOMRIGHT", chatDisplay, "BOTTOMRIGHT", -8, 0)
    scrollDownBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    scrollDownBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    scrollDownBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Highlight")
    scrollDownBtn:SetScript("OnClick", function()
        chatDisplay:ScrollToBottom()
        scrollDownBtn:Hide()
    end)
    scrollDownBtn:Hide()
    f.scrollDownBtn = scrollDownBtn

    ----------------------------------------------------------------
    -- 오른쪽 하단: 입력창
    ----------------------------------------------------------------
    local inputBox = CreateFrame("EditBox", "SimpleWhisperInputBox", f,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    inputBox:SetPoint("BOTTOMLEFT", dividerWidth + 6, 28)
    inputBox:SetPoint("BOTTOMRIGHT", -10, 28)
    inputBox:SetHeight(24)
    inputBox:SetFontObject("ChatFontNormal")
    inputBox:SetTextColor(1, 0.733, 0.867)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(255)
    inputBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    inputBox:SetBackdropColor(0, 0, 0, 0.5)
    inputBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    inputBox:SetTextInsets(6, 6, 0, 0)

    inputBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text == "" or not selectedName then return end
        local conv = conversations[selectedName]
        if conv and conv.isBN and conv.bnID then
            SendBNetWhisper(conv.bnID, text)
        else
            local fullName = conv and conv.fullName or selectedName
            SendChatMessage(text, "WHISPER", nil, fullName)
        end
        self:SetText("")
    end)
    inputBox:SetScript("OnEscapePressed", function(self)
        if SimpleWhisper_DB.escClose then
            self:ClearFocus(); f:Hide()
        else
            if self:HasFocus() then
                self:ClearFocus()
            else
                f:Hide()
            end
        end
    end)
    -- 팝업 외부 클릭 시 입력란 포커스 해제
    local focusWatcher = CreateFrame("Frame", nil, f)
    focusWatcher:SetScript("OnUpdate", function()
        if not inputBox:HasFocus() then return end
        if IsMouseButtonDown("LeftButton") and not f:IsMouseOver() then
            inputBox:ClearFocus()
        end
    end)
    f.inputBox = inputBox

    -- 메모란 (입력창 아래, 창 맨 하단 — 제목 표시줄 스타일)
    local memoBar = CreateFrame("Frame", nil, f)
    memoBar:SetHeight(20)
    memoBar:SetPoint("BOTTOMLEFT", 6, 6)
    memoBar:SetPoint("BOTTOMRIGHT", -6, 6)

    local memoBg = memoBar:CreateTexture(nil, "BACKGROUND")
    memoBg:SetAllPoints()
    memoBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local memoTop = memoBar:CreateTexture(nil, "ARTWORK")
    memoTop:SetHeight(1)
    memoTop:SetPoint("TOPLEFT")
    memoTop:SetPoint("TOPRIGHT")
    memoTop:SetColorTexture(0.6, 0.5, 0.3, 0.6)

    local memoLabel = memoBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memoLabel:SetPoint("LEFT", 6, 0)
    memoLabel:SetText("")
    memoLabel:SetTextColor(0.3, 0.9, 0.3)
    f.memoLabel = memoLabel

    local memoBox = CreateFrame("EditBox", nil, memoBar)
    memoBox:SetPoint("LEFT", memoLabel, "RIGHT", 4, 0)
    memoBox:SetPoint("RIGHT", -6, 0)
    memoBox:SetHeight(16)
    memoBox:SetFontObject("GameFontNormalSmall")
    memoBox:SetTextColor(0.3, 0.9, 0.3)
    memoBox:SetAutoFocus(false)
    memoBox:SetMaxLetters(200)
    memoBox:SetTextInsets(0, 0, 0, 0)

    local memoHint = memoBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    memoHint:SetPoint("LEFT", 0, 0)
    memoHint:SetText(L.MEMO_HINT)
    memoBox.hint = memoHint

    memoBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText()
        memoHint:SetShown(text == "")
        if selectedName and conversations[selectedName] then
            conversations[selectedName].memo = (text ~= "") and text or nil
        end
    end)
    memoBox:SetScript("OnEditFocusGained", function(self)
        memoHint:Hide()
    end)
    memoBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then memoHint:Show() end
    end)
    memoBox:SetScript("OnEscapePressed", function(self)
        if SimpleWhisper_DB.escClose then
            self:ClearFocus(); f:Hide()
        else
            self:ClearFocus()
        end
    end)
    memoBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.memoBox = memoBox

    -- 폰트 크기 적용 함수
    local function ApplyFontSize()
        local size = SimpleWhisper_DB.fontSize or 12
        local fontPath, _, fontFlags = ChatFontNormal:GetFont()
        chatDisplay:SetFont(fontPath, size, fontFlags)
        inputBox:SetFont(fontPath, size, fontFlags)
        inputBox:SetHeight(size + 10)
        -- 이름 목록
        local btnH = size + 9
        for _, btn in ipairs(f.nameButtons) do
            btn:SetSize(f.nameScroll:GetWidth(), btnH)
            btn:GetFontString():SetFont(fontPath, size, fontFlags)
        end
        RefreshNameList()
        -- 메모 바
        local memoSize = math.max(size - 1, 10)
        f.memoBox:SetFont(fontPath, memoSize, fontFlags)
        f.memoLabel:SetFont(fontPath, memoSize, fontFlags)
        f.memoBox.hint:SetFont(fontPath, memoSize, fontFlags)
    end
    f.ApplyFontSize = ApplyFontSize
    ApplyFontSize()

    -- 리사이즈 핸들 (우하단)
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local w, h = f:GetSize()
        SimpleWhisper_DB.windowSize = { w = w, h = h }
        local point, _, _, x, y = f:GetPoint()
        SimpleWhisper_DB.windowPos = { point = point, x = x, y = y }
    end)

    -- 위치 복원
    local pos = SimpleWhisper_DB and SimpleWhisper_DB.windowPos
    if pos then
        f:ClearAllPoints()
        f:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
            pos.x or 0, pos.y or 0)
    end

    -- 크기 복원
    local size = SimpleWhisper_DB and SimpleWhisper_DB.windowSize
    if size then
        f:SetSize(size.w or 450, size.h or 298)
    end

    -- 툴바 상태 복원
    if SimpleWhisper_DB.toolbarHidden then
        SetToolbarVisible(false)
    end

    -- 이름 목록 상태 복원
    if SimpleWhisper_DB.nameListHidden then
        SetNameListVisible(false)
    end

    -- ESC로 닫기
    table.insert(UISpecialFrames, "SimpleWhisperFrame")

    -- 창을 닫으면 선택 해제 (자동 열기 시에는 SelectConversation이 다시 설정)
    f:SetScript("OnHide", function()
        if selectedName and conversations[selectedName] then
            lastReadIndices[selectedName] = #conversations[selectedName]
        end
        selectedName = nil
        f.deleteBtn:Disable()
        f.inviteBtn:Disable()
        optPanel:Hide()
        inputBox:SetText("")
        memoLabel:SetText("")
        memoBox:SetText("")
        memoBox.hint:Show()
    end)

    mainFrame = f
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- 창 토글
----------------------------------------------------------------------
local function ToggleMainFrame()
    local f = CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        RefreshNameList()
        RefreshChatDisplay()
    end
end

----------------------------------------------------------------------
-- 채팅창 이름 클릭 후킹 (SetItemRef)
----------------------------------------------------------------------
local function OpenWhisperTo(name, fullName)
    EnsureConversation(name, fullName)
    BumpName(name)
    local f = CreateMainFrame()
    f:Show()
    -- 타겟/포커스/마우스오버에서 정보 추출
    for _, unitId in ipairs({"target", "focus", "mouseover"}) do
        if UnitName(unitId) == name and UnitIsPlayer(unitId) then
            local _, englishClass = UnitClass(unitId)
            if englishClass and conversations[name] then
                conversations[name].class = englishClass
            end
            local level = UnitLevel(unitId)
            if level and level > 0 and conversations[name] then
                conversations[name].whoLevel = level
            end
            local guildName = GetGuildInfo(unitId)
            if conversations[name] then
                conversations[name].whoGuild = (guildName and guildName ~= "") and guildName or conversations[name].whoGuild
            end
            break
        end
    end
    -- 누구 목록이 열려있으면 캐시에서 직업/레벨/길드 추출
    if FriendsFrame and FriendsFrame:IsShown() and C_FriendList and C_FriendList.GetNumWhoResults then
        local numResults = C_FriendList.GetNumWhoResults() or 0
        for i = 1, numResults do
            local info = C_FriendList.GetWhoInfo(i)
            if info and info.fullName then
                local whoShort = Ambiguate(info.fullName, "none")
                if whoShort == name then
                    if info.filename and conversations[name] then
                        conversations[name].class = info.filename
                    end
                    if conversations[name] then
                        if info.level and info.level > 0 then conversations[name].whoLevel = info.level end
                        conversations[name].whoGuild = (info.fullGuildName and info.fullGuildName ~= "") and info.fullGuildName or nil
                    end
                    break
                end
            end
        end
    end
    SelectConversation(name)
    f.nameScroll:SetVerticalScroll(0)
end

-- BNet 대화 열기 (BNplayer 링크 클릭용)
local function OpenBNetWhisperTo(bnID)
    local displayName = ResolveBNetName(bnID)
    if not displayName then return end
    local shortDisplay = displayName:match("^(.-)#") or displayName
    EnsureConversation(shortDisplay, displayName, true, bnID)
    BumpName(shortDisplay)
    local f = CreateMainFrame()
    f:Show()
    SelectConversation(shortDisplay)
    f.nameScroll:SetVerticalScroll(0)
end

local origSetItemRef = SetItemRef
function SetItemRef(link, text, button, chatFrame, ...)
    if SimpleWhisper_DB and SimpleWhisper_DB.interceptWhisper ~= false then
        local playerName = link:match("^player:([^:]+)")
        if playerName and button == "LeftButton" then
            OpenWhisperTo(ShortName(playerName), playerName)
            return
        end
        -- BNet 플레이어 링크: BNplayer:이름:bnID
        local bnName, bnIDStr = link:match("^BNplayer:([^:]+):(%d+)")
        if bnIDStr and button == "LeftButton" then
            local bnID = tonumber(bnIDStr)
            if bnID then
                OpenBNetWhisperTo(bnID)
                return
            end
        end
    end
    return origSetItemRef(link, text, button, chatFrame, ...)
end

-- 모든 귓속말 시작 경로 가로채기 (초상화/우클릭/파티/공격대/채팅입력 등)
-- 귓속말 모드 전환 시 항상 UpdateHeader가 호출되므로 여기서 일괄 처리
local function editBoxUpdateHeader(editBox)
    if not SimpleWhisper_DB or SimpleWhisper_DB.interceptWhisper == false then return end
    local chatType = editBox:GetAttribute("chatType")
    local tellTarget = editBox:GetAttribute("tellTarget")
    if chatType == "WHISPER" and tellTarget then
        OpenWhisperTo(ShortName(tellTarget), tellTarget)
        C_Timer.After(0, function()
            if editBox:GetAttribute("chatType") == "WHISPER" then
                editBox:SetAttribute("chatType", "SAY")
                editBox:SetAttribute("tellTarget", nil)
            end
            if ChatEdit_OnEscapePressed then
                ChatEdit_OnEscapePressed(editBox)
            end
        end)
    end
end

-- 12.0+ (ChatFrameUtil) / 이전 버전 분기
if ChatFrameUtil and ChatFrameUtil.ActivateChat then
    hooksecurefunc(ChatFrameUtil, "ActivateChat", function(editBox)
        if editBox._SW_Hooked then return end
        hooksecurefunc(editBox, "UpdateHeader", editBoxUpdateHeader)
        editBox._SW_Hooked = true
    end)
else
    hooksecurefunc("ChatEdit_UpdateHeader", editBoxUpdateHeader)
end

----------------------------------------------------------------------
-- 이벤트 프레임
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= addonName then return end

        -- DB 초기화
        if not SimpleWhisper_DB then
            SimpleWhisper_DB = {
                windowPos = { point = "CENTER", x = 0, y = 0 },
                soundEnabled = true,
                showTime = false,
            }
        end
        if SimpleWhisper_DB.soundEnabled == nil then
            SimpleWhisper_DB.soundEnabled = true
        end
        if SimpleWhisper_DB.autoOpen == nil then
            SimpleWhisper_DB.autoOpen = true
        end
        if SimpleWhisper_DB.combatMode == nil then
            SimpleWhisper_DB.combatMode = 1
        end
        if SimpleWhisper_DB.hideFromChat == nil then
            SimpleWhisper_DB.hideFromChat = true
        end
        if SimpleWhisper_DB.interceptWhisper == nil then
            SimpleWhisper_DB.interceptWhisper = true
        end
        if SimpleWhisper_DB.escClose == nil then
            SimpleWhisper_DB.escClose = true
        end
        if SimpleWhisper_DB.opacity == nil then
            SimpleWhisper_DB.opacity = 0.85
        end
        if SimpleWhisper_DB.opacityEnabled == nil then
            SimpleWhisper_DB.opacityEnabled = true
        end
        if SimpleWhisper_DB.fontSize == nil then
            SimpleWhisper_DB.fontSize = 12
        end
        if SimpleWhisper_DB.toolbarHidden == nil then
            SimpleWhisper_DB.toolbarHidden = false
        end
        if not SimpleWhisper_DB.windowPos then
            SimpleWhisper_DB.windowPos = { point = "CENTER", x = 0, y = 0 }
        end

        -- 안읽음 카운트 복원
        if SimpleWhisper_DB.unreadCounts then
            for name, count in pairs(SimpleWhisper_DB.unreadCounts) do
                unreadCounts[name] = count
            end
        end

        -- 대화 내용 복원
        if SimpleWhisper_DB.conversations then
            for name, data in pairs(SimpleWhisper_DB.conversations) do
                conversations[name] = data
            end
        end
        if SimpleWhisper_DB.nameList then
            for _, name in ipairs(SimpleWhisper_DB.nameList) do
                table.insert(nameList, name)
            end
        end
        if SimpleWhisper_DB.lastReadIndices then
            for name, idx in pairs(SimpleWhisper_DB.lastReadIndices) do
                lastReadIndices[name] = idx
            end
        end

        -- LDB 오브젝트 생성
        local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
        if LDB then
            ldbObject = LDB:NewDataObject("SimpleWhisper", {
                type = "data source",
                text = L.LDB_LABEL,
                icon = "Interface\\CHATFRAME\\UI-ChatIcon-Chat-Up",
                OnClick = function(_, button)
                    if button == "LeftButton" then
                        ToggleMainFrame()
                    end
                end,
                OnTooltipShow = function(tt)
                    tt:AddLine(L.TITLE)
                    local total = 0
                    for _, c in pairs(unreadCounts) do total = total + c end
                    if total > 0 then
                        tt:AddLine(string.format(L.UNREAD_FMT, total))
                    end
                    tt:AddLine(L.TOOLTIP_HINT)
                end,
            })
            UpdateLDBText()
        end

        -- 미니맵 버튼
        if SimpleWhisper_DB.minimapPos == nil then
            SimpleWhisper_DB.minimapPos = 220
        end
        local minimapBtn = CreateFrame("Button", "SimpleWhisperMinimapBtn", Minimap)
        minimapBtn:SetSize(32, 32)
        minimapBtn:SetFrameStrata("MEDIUM")
        minimapBtn:SetFrameLevel(8)
        minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(24, 24)
        bg:SetPoint("CENTER", 0, 0)
        bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        local overlay = minimapBtn:CreateTexture(nil, "OVERLAY")
        overlay:SetSize(54, 54)
        overlay:SetPoint("TOPLEFT")
        overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(25, 25)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexture("Interface\\CHATFRAME\\UI-ChatIcon-Chat-Up")
        -- 안 읽은 수 배지 (빨간 동그라미 + 숫자)
        local badge = CreateFrame("Frame", nil, minimapBtn)
        badge:SetSize(25.4, 25.4)
        badge:SetPoint("CENTER", -0.2, -0.2)
        badge:SetFrameLevel(minimapBtn:GetFrameLevel() + 1)
        local badgeBg = badge:CreateTexture(nil, "BACKGROUND")
        badgeBg:SetAllPoints()
        badgeBg:Hide()
        local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        local bFont, bSize = badgeText:GetFont()
        badgeText:SetFont(bFont, bSize, "THICKOUTLINE")
        badgeText:SetPoint("BOTTOMRIGHT", 4, -2)
        badgeText:SetTextColor(1, 1, 1)
        badge:Hide()
        badge.text = badgeText
        badge.icon = icon
        minimapBadge = badge
        UpdateLDBText()
        local function UpdateMinimapPos()
            local angle = math.rad(SimpleWhisper_DB.minimapPos)
            local x = 80 * math.cos(angle)
            local y = 80 * math.sin(angle)
            minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end
        UpdateMinimapPos()
        minimapBtn:RegisterForDrag("RightButton")
        minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        minimapBtn:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                ToggleMainFrame()
            end
        end)
        minimapBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(L.TITLE)
            local total = 0
            for _, c in pairs(unreadCounts) do total = total + c end
            if total > 0 then
                GameTooltip:AddLine(string.format(L.UNREAD_FMT, total))
            end
            GameTooltip:AddLine(L.TOOLTIP_HINT)
            GameTooltip:Show()
        end)
        minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        minimapBtn:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                cx, cy = cx / scale, cy / scale
                SimpleWhisper_DB.minimapPos = math.deg(math.atan2(cy - my, cx - mx))
                UpdateMinimapPos()
            end)
        end)
        minimapBtn:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        -- 기본 채팅창 귓속말 필터
        local function WhisperFilter()
            return SimpleWhisper_DB.hideFromChat
        end
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", WhisperFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", WhisperFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", WhisperFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", WhisperFilter)

        -- /who 시스템 메시지 필터: 원본 이벤트 핸들러 후킹
        for i = 1, NUM_CHAT_WINDOWS do
            local cf = _G["ChatFrame" .. i]
            if cf then
                local origOnEvent = cf:GetScript("OnEvent")
                if origOnEvent then
                    cf:SetScript("OnEvent", function(self, event, msg, ...)
                        if event == "CHAT_MSG_SYSTEM" and GetTime() < whoFilterUntil then
                            if msg and (msg:match("|Hplayer:.-|h%[.-%]|h:") or msg:match(L.WHO_TOTAL_PAT) or msg:match(L.WHO_NOTFOUND_PAT)) then
                                return  -- 표시하지 않음
                            end
                        end
                        return origOnEvent(self, event, msg, ...)
                    end)
                end
            end
        end

        -- 슬래시 명령어
        SLASH_SIMPLEWHISPER1 = "/swsw"
        SlashCmdList["SIMPLEWHISPER"] = function(msg)
            msg = (msg or ""):trim():lower()
            if msg == "demo" then
                -- 샘플 데이터 추가
                do
                    local today = date("%Y-%m-%d")
                    local yesterday = date("%Y-%m-%d", time() - 86400)
                    conversations["Deathknight"] = {
                        fullName = "Deathknight", class = "DEATHKNIGHT",
                        whoLevel = 70, whoGuild = "Frozen Throne",
                        { who = "in",  msg = "Hey, want to run ICC tonight?", time = "21:03:12", date = yesterday },
                        { who = "out", msg = "Sure, what time?", time = "21:03:45", date = yesterday },
                        { who = "in",  msg = "8pm server time. Bring flasks.", time = "21:04:10", date = yesterday },
                        { who = "in",  msg = "Ready when you are.", time = "19:30:00", date = today },
                        { who = "out", msg = "On my way!", time = "19:30:22", date = today },
                        { who = "in",  msg = "Great, meet at the entrance.", time = "19:31:05", date = today },
                    }
                    conversations["Hunter"] = {
                        fullName = "Hunter", class = "HUNTER",
                        whoLevel = 70, whoGuild = "Frozen Throne",
                        { who = "in",  msg = "Need help with the daily quest?", time = "14:20:00", date = today },
                        { who = "out", msg = "Which one?", time = "14:20:30", date = today },
                        { who = "in",  msg = "The group quest in Icecrown.", time = "14:21:15", date = today },
                        { who = "out", msg = "On my way.", time = "14:21:40", date = today },
                        { who = "in",  msg = "Thanks!", time = "14:22:00", date = today },
                    }
                    conversations["Mage"] = {
                        fullName = "Mage", class = "MAGE",
                        whoLevel = 70, whoGuild = "Arcane Society",
                        { who = "in",  msg = "Can you help me with something?", time = "10:15:00", date = today },
                        { who = "out", msg = "Of course, what do you need?", time = "10:15:30", date = today },
                        { who = "in",  msg = "Portal to Dalaran please.", time = "10:16:00", date = today },
                    }
                    conversations["Shaman"] = {
                        fullName = "Shaman", class = "SHAMAN",
                        whoLevel = 70, whoGuild = "Arcane Society",
                        { who = "out", msg = "Hey, are you free for arena?", time = "18:00:00", date = today },
                        { who = "in",  msg = "Give me 10 minutes.", time = "18:05:30", date = today },
                    }
                    conversations["Rogue"] = {
                        fullName = "Rogue", class = "ROGUE",
                        whoLevel = 70,
                        { who = "in",  msg = "Got some items you might want.", time = "22:45:00", date = yesterday },
                        { who = "out", msg = "What kind?", time = "22:45:20", date = yesterday },
                        { who = "in",  msg = "Meet me at the AH. Good prices.", time = "22:46:00", date = yesterday },
                    }
                    conversations["Paladin"] = {
                        fullName = "Paladin", class = "PALADIN",
                        whoLevel = 70, whoGuild = "Silver Hand",
                        { who = "in",  msg = "LFM for heroic dungeon, need healer", time = "15:00:00", date = today },
                        { who = "out", msg = "I can heal! Invite me", time = "15:00:30", date = today },
                        { who = "in",  msg = "Nice, sending invite now", time = "15:01:00", date = today },
                        { who = "out", msg = "Got it, on my way", time = "15:01:15", date = today },
                    }
                    conversations["Warrior"] = {
                        fullName = "Warrior", class = "WARRIOR",
                        whoLevel = 70, whoGuild = "Silver Hand",
                        { who = "in",  msg = "Is the sword you listed on AH still available?", time = "17:30:00", date = today },
                        { who = "out", msg = "Yeah, still there. How much are you offering?", time = "17:30:45", date = today },
                        { who = "in",  msg = "500g?", time = "17:31:10", date = today },
                        { who = "out", msg = "Haha, can't go below 800g", time = "17:31:30", date = today },
                        { who = "in",  msg = "Ah, that's too expensive :(", time = "17:32:00", date = today },
                    }
                    conversations["Druid"] = {
                        fullName = "Druid", class = "DRUID",
                        whoLevel = 70,
                        { who = "out", msg = "Can you teach me the resto rotation?", time = "20:10:00", date = yesterday },
                        { who = "in",  msg = "Resto spec? Give me a sec.", time = "20:12:00", date = yesterday },
                        { who = "in",  msg = "Rejuv > Lifebloom > Wild Growth, in that order.", time = "20:13:00", date = yesterday },
                        { who = "out", msg = "Thank you so much!", time = "20:13:30", date = yesterday },
                    }
                    nameList = {"Deathknight", "Warrior", "Hunter", "Paladin", "Mage", "Druid", "Shaman", "Rogue"}
                    unreadCounts["Deathknight"] = 1
                    unreadCounts["Hunter"] = 2
                    unreadCounts["Warrior"] = 3
                    print(L.CHAT_PREFIX .. " Demo data loaded.")
                end
                UpdateLDBText()
                if mainFrame and mainFrame:IsShown() then
                    RefreshNameList()
                    RefreshChatDisplay()
                end
                return
            elseif msg == "t1" then
                -- 가짜 귓속말 수신 이벤트 시뮬레이션 (테스트용)
                local fakeName = "TestPlayer"
                local fakeMsg = "Test whisper " .. date("%H:%M:%S")
                EnsureConversation(fakeName, fakeName)
                AddMessage(fakeName, "in", fakeMsg, fakeName)
                PlayWhisperSound()
                local wasHidden = not mainFrame or not mainFrame:IsShown()
                if wasHidden and SimpleWhisper_DB.autoOpen ~= false then
                    if not InCombatLockdown() or SimpleWhisper_DB.combatMode == 1 then
                        local f = CreateMainFrame()
                        f:Show()
                        SelectConversation(fakeName, true)
                        f.nameScroll:SetVerticalScroll(0)
                    elseif InCombatLockdown() and SimpleWhisper_DB.combatMode == 2 then
                        pendingCombatNames[fakeName] = true
                    end
                end
                if not wasHidden and mainFrame and mainFrame:IsShown() then
                    if not selectedName then
                        SelectConversation(fakeName, true)
                    else
                        RefreshNameList()
                        if fakeName == selectedName then
                            unreadCounts[fakeName] = 0
                            UpdateLDBText()
                            RefreshChatDisplay()
                        end
                    end
                end
                print(L.CHAT_PREFIX .. " Test whisper from " .. fakeName)
                return
            end
            ToggleMainFrame()
        end

        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGOUT" then
        -- 현재 선택된 대화의 읽음 위치도 저장
        if selectedName and conversations[selectedName] then
            lastReadIndices[selectedName] = #conversations[selectedName]
        end
        SimpleWhisper_DB.conversations = conversations
        SimpleWhisper_DB.nameList = nameList
        SimpleWhisper_DB.unreadCounts = unreadCounts
        SimpleWhisper_DB.lastReadIndices = lastReadIndices

    elseif event == "CHAT_MSG_WHISPER" then
        local text, fullName, _, _, _, _, _, _, _, _, _, guid = ...
        local name = ShortName(fullName)
        EnsureConversation(name, fullName)
        if guid then
            conversations[name].guid = guid
            local _, englishClass = GetPlayerInfoByGUID(guid)
            if englishClass then
                conversations[name].class = englishClass
            end
        end
        AddMessage(name, "in", text, fullName)
        PlayWhisperSound()

        -- 창이 없거나 숨겨져 있으면 자동으로 열기 (옵션 확인)
        local wasHidden = not mainFrame or not mainFrame:IsShown()
        if wasHidden and SimpleWhisper_DB.autoOpen ~= false then
            if not InCombatLockdown() or SimpleWhisper_DB.combatMode == 1 then
                local f = CreateMainFrame()
                f:Show()
                SelectConversation(name, true)
                f.nameScroll:SetVerticalScroll(0)
            elseif InCombatLockdown() and SimpleWhisper_DB.combatMode == 2 then
                pendingCombatNames[name] = true
            end
        end
        -- 창이 이미 열려 있었을 때만 대화 선택/갱신
        if not wasHidden and mainFrame and mainFrame:IsShown() then
            if not selectedName then
                SelectConversation(name, true)
                mainFrame.nameScroll:SetVerticalScroll(0)
            else
                RefreshNameList()
                if name == selectedName then
                    unreadCounts[name] = 0
                    UpdateLDBText()
                    RefreshChatDisplay()
                end
            end
        end

    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local text, fullName, _, _, _, _, _, _, _, _, _, guid = ...
        local name = ShortName(fullName)
        EnsureConversation(name, fullName)
        if guid then
            conversations[name].guid = guid
            local _, englishClass = GetPlayerInfoByGUID(guid)
            if englishClass then
                conversations[name].class = englishClass
            end
        end
        AddMessage(name, "out", text, fullName)

        if mainFrame and mainFrame:IsShown() then
            RefreshNameList()
            if name == selectedName then
                RefreshChatDisplay()
            end
        end

    elseif event == "CHAT_MSG_BN_WHISPER" then
        local text, senderName = ...
        local bnID = select(13, ...)
        -- bnID로 배틀태그/계정명 해석
        local displayName = ResolveBNetName(bnID) or senderName
        -- 배틀태그에서 # 뒤 제거 (간결한 표시)
        local shortDisplay = displayName:match("^(.-)#") or displayName
        EnsureConversation(shortDisplay, displayName, true, bnID)
        AddMessage(shortDisplay, "in", text, displayName)
        PlayWhisperSound()

        local wasHidden = not mainFrame or not mainFrame:IsShown()
        if wasHidden and SimpleWhisper_DB.autoOpen ~= false then
            if not InCombatLockdown() or SimpleWhisper_DB.combatMode == 1 then
                local f = CreateMainFrame()
                f:Show()
            elseif InCombatLockdown() and SimpleWhisper_DB.combatMode == 2 then
                pendingCombatNames[shortDisplay] = true
            end
        end
        if mainFrame and mainFrame:IsShown() then
            if not selectedName then
                SelectConversation(shortDisplay, true)
            else
                RefreshNameList()
                if shortDisplay == selectedName then
                    unreadCounts[shortDisplay] = 0
                    UpdateLDBText()
                    RefreshChatDisplay()
                end
            end
        end

    elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local text, recipientName = ...
        local bnID = select(13, ...)
        local displayName = ResolveBNetName(bnID) or recipientName
        local shortDisplay = displayName:match("^(.-)#") or displayName
        EnsureConversation(shortDisplay, displayName, true, bnID)
        AddMessage(shortDisplay, "out", text, displayName)

        if mainFrame and mainFrame:IsShown() then
            RefreshNameList()
            if shortDisplay == selectedName then
                RefreshChatDisplay()
            end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...

        -- /who 결과 캡처 (RAW: |Hplayer:이름|h[이름]|h: 정보...)
        if pendingWhoName then
            local whoName, whoInfo = msg:match("|Hplayer:.-|h%[(.-)%]|h:%s*(.+)$")
            if whoName then
                local whoShort = ShortName(whoName)
                if whoShort == pendingWhoName then
                    local target = pendingWhoName
                    pendingWhoName = nil
                    if pendingWhoTimer then pendingWhoTimer:Cancel(); pendingWhoTimer = nil end
                    if C_FriendList and C_FriendList.SetWhoToUI then C_FriendList.SetWhoToUI(true) elseif SetWhoToUI then SetWhoToUI(1) end
                    -- /who 결과 파싱
                    local level = whoInfo:match(L.WHO_LEVEL_PAT)
                    local guild = whoInfo:match("<(.-)>")
                    -- 직업 추출 → conv.class 업데이트
                    for korName, token in pairs(CLASS_NAME_TO_TOKEN) do
                        if whoInfo:find(korName) then
                            if conversations[target] then
                                conversations[target].class = token
                            end
                            break
                        end
                    end
                    -- /who 결과를 conversations에 저장 (로그아웃 시 함께 저장됨)
                    if conversations[target] then
                        local conv = conversations[target]
                        if level then conv.whoLevel = tonumber(level) end
                        if guild then conv.whoGuild = guild end
                        conv.whoLevel = conv.whoLevel or (level and tonumber(level))
                        conv.whoGuild = guild  -- nil이면 길드 없음
                    end
                    if mainFrame then RefreshNameList() end
                    -- 표시 텍스트 생성
                    local conv = conversations[target]
                    local display = target
                    local lv = conv and conv.whoLevel
                    local gd = conv and conv.whoGuild
                    if lv then
                        display = display .. " LV." .. lv
                    end
                    if gd then
                        display = display .. " <" .. gd .. ">"
                    end
                    -- 제목 바에 표시 + 새로고침 버튼 숨기기
                    if mainFrame and target == selectedName then
                        if mainFrame.whoInfoText then
                            mainFrame.whoInfoText:SetText("|cff00ff00" .. display .. "|r")
                        end
                        if mainFrame.refreshBtn then
                            mainFrame.refreshBtn:Hide()
                            mainFrame.whoCooldown = 0
                            if mainFrame.whoCooldownTicker then
                                mainFrame.whoCooldownTicker:Cancel()
                                mainFrame.whoCooldownTicker = nil
                            end
                        end
                    end
                    return
                end
            end
            local whoCount = msg:match(L.WHO_TOTAL_PAT)
            if whoCount or msg:match(L.WHO_NOTFOUND_PAT) then
                local target = pendingWhoName
                pendingWhoName = nil
                if pendingWhoTimer then pendingWhoTimer:Cancel(); pendingWhoTimer = nil end
                if C_FriendList and C_FriendList.SetWhoToUI then C_FriendList.SetWhoToUI(true) elseif SetWhoToUI then SetWhoToUI(1) end
                if (whoCount and tonumber(whoCount) == 0) or msg:match(L.WHO_NOTFOUND_PAT) then
                    if mainFrame and target == selectedName then
                        if mainFrame.whoInfoText then
                            mainFrame.whoInfoText:SetText("|cffff4444" .. L.WHO_OFFLINE .. "|r")
                        end
                        if mainFrame.refreshBtn then
                            mainFrame.refreshBtn:Hide()
                            mainFrame.whoCooldown = 0
                            if mainFrame.whoCooldownTicker then
                                mainFrame.whoCooldownTicker:Cancel()
                                mainFrame.whoCooldownTicker = nil
                            end
                        end
                    end
                end
            end
        end

        local patterns = {
            ERR_CHAT_PLAYER_NOT_FOUND_S,  -- "%s님을 찾을 수 없습니다."
            ERR_CHAT_IGNORED_S,           -- "%s님이 당신을 무시하고 있습니다."
        }
        for _, pat in ipairs(patterns) do
            if pat then
                local matchPat = "^" .. pat:gsub("%%s", "(.+)") .. "$"
                local failName = msg:match(matchPat)
                if failName then
                    local short = ShortName(failName)
                    if conversations[short] then
                        AddMessage(short, "sys", msg, failName)
                        if short == selectedName and mainFrame and mainFrame:IsShown() then
                            RefreshChatDisplay()
                        end
                    end
                    break
                end
            end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- 전투 종료 후 보류된 대화 열기
        if next(pendingCombatNames) then
            -- 이미 창이 열려있으면 보류 목록만 비움
            if mainFrame and mainFrame:IsShown() then
                wipe(pendingCombatNames)
            else
                local f = CreateMainFrame()
                f:Show()
                -- 보류 이름이 1개면 자동 선택
                local count = 0
                local singleName = nil
                for n in pairs(pendingCombatNames) do
                    count = count + 1
                    singleName = n
                end
                if count == 1 then
                    SelectConversation(singleName, true)
                end
                wipe(pendingCombatNames)
            end
        end

    end
end)
