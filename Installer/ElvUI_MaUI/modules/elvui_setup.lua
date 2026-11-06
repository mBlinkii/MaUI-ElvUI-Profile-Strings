local MaUI, L, E = unpack(ElvUI_MaUI)

local _G = _G
local format, ipairs, next, strsub, tinsert = format, ipairs, next, strsub, tinsert

-- pages 2 and 3 of ElvUI's own installer, preselected when ElvUI was never set up on this character

local function FreshCharacter()
	return MaUI.ElvUIFresh
end

MaUI:RegisterModule({
	key = "cvars",
	order = 5, -- before the profile, as in ElvUI's own installer
	name = L["Game settings"],
	desc = L["ElvUI's recommended CVars: cooldown numbers, key down casting, nameplate and chat options."],
	icon = "Interface\\Icons\\INV_Misc_Gear_01",
	default = FreshCharacter,
	Apply = function()
		E:SetupCVars(true)
	end,
})

-- chat -----------------------------------------------------------------------
-- MaUI keeps a single chat window on the left with one tab per topic, the right panel stays empty.
-- Built like ElvUI's E:SetupChat, only with this tab layout.

-- everything that has no tab of its own, including what ElvUI would put in its right window
local GENERAL_GROUPS = {
	"SYSTEM", "CHANNEL", "SAY", "EMOTE", "YELL", "PING", "BN_INLINE_TOAST_ALERT",
	"MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
	"ERRORS", "AFK", "DND", "IGNORED", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "ACHIEVEMENT",
	"COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT", "CURRENCY", "MONEY",
}

-- in tab order; the combat log is Blizzard's own ChatFrame2
local TABS = {
	{ name = _G.GENERAL, groups = GENERAL_GROUPS, channels = { _G.GENERAL, _G.TRADE } },
	{ name = _G.WHISPER, groups = { "WHISPER", "BN_WHISPER" } },
	{ name = _G.GROUP, groups = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" } },
	{ name = _G.GUILD, groups = { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "GUILD_DISCORD" } },
	{ name = _G.COMBAT_LOG, combatLog = true },
}

-- chat types that show player names in class color, as ElvUI sets them
local CLASS_COLOR_GROUPS = { "SAY", "EMOTE", "YELL", "WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "ACHIEVEMENT", "GUILD_ACHIEVEMENT", "COMMUNITIES_CHANNEL" }
for i = 1, _G.MAX_WOW_CHAT_CHANNELS or _G.Constants.ChatFrameConstants.MaxChatChannels do
	tinsert(CLASS_COLOR_GROUPS, "CHANNEL" .. i)
end

local function SetMessageGroups(frame, groups)
	frame:RemoveAllMessageGroups()
	for _, group in ipairs(groups) do
		-- not every client knows every group (PING, INSTANCE_CHAT on Classic Era, ...)
		if _G.ChatTypeGroup[group] then frame:AddMessageGroup(group) end
	end
end

local function ColorNamesByClass(group)
	local info = _G.ChatTypeGroup[group]
	if info then
		for _, value in next, info do
			_G.SetChatColorNameByClass(strsub(value, 10), true)
		end
	else
		_G.SetChatColorNameByClass(group, true)
	end
end

local function SetupChat()
	_G.FCF_ResetChatWindows()

	-- the voice transcription window takes ChatFrame3 on Retail and only shows up when used
	local voice = _G.VoiceTranscriptionFrame_UpdateVisibility and _G[_G.CHAT_FRAMES[3]]
	if voice then
		_G.FCF_ResetChatWindow(voice, _G.VOICE)
		_G.FCF_DockFrame(voice, 3)
		_G.VoiceTranscriptionFrame_UpdateVisibility(voice)
		_G.VoiceTranscriptionFrame_UpdateVoiceTab(voice)
		_G.VoiceTranscriptionFrame_UpdateEditBox(voice)
	end

	local general, combatLog = _G.ChatFrame1, _G.ChatFrame2
	local frames = {}

	for _, tab in ipairs(TABS) do
		local frame
		if tab.combatLog then
			-- docked again so it moves behind the new tabs
			frame = combatLog
			_G.FCF_UnDockFrame(frame)
			_G.FCF_DockFrame(frame)
		elseif tab.name == _G.GENERAL then
			frame = general
		else
			frame = _G.FCF_OpenNewWindow(tab.name, true)
		end

		if tab.groups then SetMessageGroups(frame, tab.groups) end
		for _, channel in ipairs(tab.channels or {}) do
			frame:AddChannel(channel)
		end

		tinsert(frames, frame)
	end

	general:ClearAllPoints()
	general:SetPoint("BOTTOMLEFT", _G.LeftChatToggleButton, "TOPLEFT", 1, 3)

	local CH = E:GetModule("Chat")
	for _, frame in ipairs(frames) do
		if E.private.chat.enable then CH:FCFTab_UpdateColors(CH:GetTab(frame)) end
		_G.FCF_SetChatWindowFontSize(nil, frame, 12)
		_G.FCF_SavePositionAndDimensions(frame)
		_G.FCF_StopDragging(frame)
	end

	for _, group in ipairs(CLASS_COLOR_GROUPS) do
		ColorNamesByClass(group)
	end

	_G.ChangeChatColor("CHANNEL1", 0.76, 0.90, 0.91) -- General
	_G.ChangeChatColor("CHANNEL2", 0.91, 0.62, 0.47) -- Trade
	_G.ChangeChatColor("CHANNEL3", 0.91, 0.89, 0.47) -- Local Defense

	if E.private.chat.enable then CH:PositionChats() end
	_G.FCF_SelectDockFrame(general)
end

MaUI:RegisterModule({
	key = "chat",
	order = 6,
	name = L["Chat"],
	desc = format(L["One chat window on the left with the tabs %s."], format("%s, %s, %s, %s, %s", _G.GENERAL, _G.WHISPER, _G.GROUP, _G.GUILD, _G.COMBAT_LOG)),
	icon = "Interface\\Icons\\INV_Letter_15",
	default = FreshCharacter,
	Apply = SetupChat,
})
