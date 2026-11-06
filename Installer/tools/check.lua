--[[
Loads ElvUI_MaUI outside the game against stubbed WoW, ElvUI and addon APIs, clicks
through every installer page and runs the installation. Catches nil calls, typos and
broken data before a /reload does.

	lua5.1 Installer/tools/check.lua            (run from the repository root)
]]

local ADDON = "ElvUI_MaUI"
local ROOT = "Installer/" .. ADDON .. "/"

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

-- generic widget stub -------------------------------------------------------

local Stub
local METHODS = {
	GetWidth = function() return 100 end,
	GetHeight = function() return 40 end,
	GetStringWidth = function() return 60 end,
	GetStringHeight = function() return 48 end,
	GetPoint = function() return "TOPLEFT", nil, "TOPLEFT", 0, 0 end,
	GetName = function(self) return self.__name end,
	GetParent = function(self) return self.__parent or Stub() end,
	GetText = function(self) return self.__text end,
	SetText = function(self, text) self.__text = text end,
	IsEnabled = function(self) return self.__enabled ~= false end,
	SetEnabled = function(self, value) self.__enabled = value and true or false end,
	IsShown = function(self) return self.__shown end,
	Show = function(self) self.__shown = true end,
	Hide = function(self)
		local was = self.__shown
		self.__shown = false
		-- like WoW, hiding a shown frame runs its OnHide (only OnHide, the other scripts are called by the checks)
		if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
	end,
	SetShown = function(self, value) self.__shown = value and true or false end,
	SetScript = function(self, event, func) self.__scripts[event] = func end,
	CreateShadow = function(self) self.shadow = Stub(nil, self) end,
	GetScript = function(self, event) return self.__scripts[event] end,
	HookScript = function(self, event, func)
		local old = self.__scripts[event]
		self.__scripts[event] = old and function(...) old(...) func(...) end or func
	end,
	SetFont = function(_, font, size)
		assert(type(font) == "string" and type(size) == "number", "SetFont needs a font path and size")
	end,
	SetTexture = function(_, texture)
		assert(texture == nil or type(texture) == "string" or type(texture) == "number", "bad texture " .. tostring(texture))
	end,
	SetPoint = function(_, point, ...)
		assert(type(point) == "string", "SetPoint needs a point")
		-- like WoW: only frames and regions can be anchors, a box (a plain Lua table) cannot
		local relative = ...
		assert(type(relative) ~= "table" or not relative.isBox, "SetPoint: Wrong object type for function (anchored to a box)")
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			assert(v == nil or type(v) ~= "number" or v == v, "SetPoint got NaN")
		end
	end,
	SetAllPoints = function(_, relative)
		assert(type(relative) ~= "table" or not relative.isBox, "SetAllPoints: Wrong object type for function (anchored to a box)")
	end,
	SetVertexColor = function(_, r, g, b)
		assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetVertexColor needs numbers")
	end,
}

function Stub(name, parent)
	local object = { __name = name, __parent = parent, __scripts = {}, __shown = true }
	return setmetatable(object, {
		__index = function(self, key)
			-- widget methods are capitalized, anything else is a field the addon has not set yet
			if type(key) ~= "string" or not key:find("^%u") then return nil end
			local method = METHODS[key]
			if not method then
				if type(key) == "string" and key:find("^Create") then
					method = function(owner) return Stub(nil, owner) end
				else
					method = function() end
				end
			end
			rawset(self, key, method)
			return method
		end,
	})
end

local function Click(object)
	local onClick = object.__scripts.OnClick
	assert(onClick, "no OnClick")
	if object:IsEnabled() then onClick(object) end
end

-- WoW API -------------------------------------------------------------------

local timers = {}
_G.C_Timer = { After = function(_, func) table.insert(timers, func) end }
local function RunTimers()
	while #timers > 0 do
		table.remove(timers, 1)()
	end
end

_G.CreateFrame = function(_, name, parent) local f = Stub(name, parent) if name then _G[name] = f end return f end
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local screen = { 1920, 1080 }
_G.GetPhysicalScreenSize = function() return screen[1], screen[2] end
_G.GetLocale = function() return "deDE" end
_G.InCombatLockdown = function() return false end
_G.ReloadUI = function() _G.__reloaded = true end
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.OKAY = "OK"
_G.EssentialCooldownViewer = Stub()
_G.format, _G.strmatch, _G.tinsert, _G.sort, _G.tremove = string.format, string.match, table.insert, table.sort, table.remove
_G.floor, _G.time, _G.date, _G.strsub, _G.strfind, _G.strlower, _G.strmatch = math.floor, os.time, os.date, string.sub, string.find, string.lower, string.match

local addons = { ElvUI = true, ElvUI_mMediaTag = true, Details = true, Baganator = true, MauiMPlusTimer = true }
local LoadToc -- defined with the addon loader below
local dataLoads = 0
_G.C_AddOns = {
	IsAddOnLoaded = function(name) return addons[name] == true end,
	LoadAddOn = function(name)
		assert(name == ADDON .. "_Data", "unexpected LoadAddOn " .. name)
		dataLoads = dataLoads + 1
		LoadToc(name)
		return true
	end,
	GetAddOnInfo = function(name) return name, name, "", false, addons[name] == nil and "MISSING" or "DISABLED" end,
	GetAddOnMetadata = function(name, key)
		if key == "Version" then return "@project-version@" end
		if key == "X-MaUI-Profile" then return "8.5" end
		if key == "IconTexture" then return "Interface\\AddOns\\" .. name .. "\\icon" end
	end,
}

-- serializing keeps a copy and hands out a key for it, so packed snapshots really come back
local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end

local serialized = {}
local function Same(s) return s end
_G.C_EncodingUtil = {
	SerializeCBOR = function(t)
		assert(type(t) == "table")
		serialized[#serialized + 1] = DeepCopy(t)
		return "cbor:" .. #serialized
	end,
	DeserializeCBOR = function(s) return DeepCopy(serialized[tonumber(s:match("^cbor:(%d+)$"))]) end,
	CompressString = Same,
	DecompressString = Same,
	EncodeBase64 = Same,
	DecodeBase64 = Same,
}

local savedEditMode
_G.Enum = { EditModeLayoutType = { Account = 1, Character = 2 } }
_G.C_EditMode = {
	ConvertStringToLayoutInfo = function(s) assert(type(s) == "string" and #s > 20) return { systems = {} } end,
	GetLayouts = function() return { activeLayout = 1, layouts = { { layoutName = "MaUI", layoutType = 1 }, { layoutName = "Other", layoutType = 1 } } } end,
	SaveLayouts = function(layouts) savedEditMode = layouts end,
	SetActiveLayout = function(index) _G.__activeLayout = index end,
}

-- chat frames: a dock list that follows Blizzard's FCF_* rules closely enough to check the tab order
_G.GENERAL, _G.TRADE, _G.WHISPER, _G.GROUP, _G.GUILD, _G.COMBAT_LOG, _G.VOICE = "Allgemein", "Handel", "Flüstern", "Gruppe", "Gilde", "Kampflog", "Sprache"
_G.MAX_WOW_CHAT_CHANNELS = 20
_G.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2", "ChatFrame3" }
_G.ChatTypeGroup = setmetatable({ PING = false }, { __index = function(_, k) return { "CHAT_MSG_" .. k } end })

local function ChatFrame(name, title)
	local frame = Stub(name)
	frame.title, frame.groups, frame.channels = title, {}, {}
	frame.AddMessageGroup = function(self, group) self.groups[group] = true end
	frame.RemoveAllMessageGroups = function(self) self.groups = {} end
	frame.AddChannel = function(self, channel) self.channels[channel] = true end
	frame.RemoveChannel = function(self, channel) self.channels[channel] = nil end
	_G[name] = frame
	return frame
end

local dock
local function Undock(frame)
	for i = #dock, 1, -1 do
		if dock[i] == frame then table.remove(dock, i) end
	end
end
_G.FCF_ResetChatWindows = function()
	dock = { ChatFrame("ChatFrame1", "Allgemein"), ChatFrame("ChatFrame2", "Kampflog"), ChatFrame("ChatFrame3", "Sprache") }
	_G.ChatFrame1.channels = { Allgemein = true, Handel = true }
	_G.ChatFrame2.groups = { COMBAT = true }
end
_G.FCF_DockFrame = function(frame, index)
	Undock(frame)
	table.insert(dock, math.min(index or #dock + 1, #dock + 1), frame)
end
_G.FCF_UnDockFrame = Undock
_G.FCF_OpenNewWindow = function(name, noDefaultChannels)
	assert(noDefaultChannels, "new tabs should start without channels")
	local frame = ChatFrame("ChatFrame" .. (#dock + 1), name)
	table.insert(dock, frame)
	return frame
end
for _, name in ipairs({ "FCF_ResetChatWindow", "FCF_SetChatWindowFontSize", "FCF_SavePositionAndDimensions", "FCF_StopDragging", "FCF_SelectDockFrame",
	"SetChatColorNameByClass", "ChangeChatColor", "VoiceTranscriptionFrame_UpdateVisibility", "VoiceTranscriptionFrame_UpdateVoiceTab", "VoiceTranscriptionFrame_UpdateEditBox" }) do
	_G[name] = function() end
end
_G.LeftChatToggleButton = Stub("LeftChatToggleButton")

-- ElvUI ---------------------------------------------------------------------

local function CopyInto(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyInto(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end

-- custom data panels only exist after ElvUI built them
local DT = { RegisteredPanels = { LeftChatDataPanel = {} } }
function DT:BuildPanelFrame(name) self.RegisteredPanels[name] = {} end

local imported = {}
local D = {
	blacklistedKeys = { profile = {}, private = {}, global = {} },
	-- like ElvUI: the profile is stored under its name and the character switches to it
	SetImportedProfile = function(_, kind, key, data, force)
		imported[kind] = { key = key, data = data, force = force }
		_G.ElvDB.profiles[key] = data
		_G.__currentProfile = key

		-- like mMediaTag's CheckAndRemoveSettings on the profile switch: skins of unknown panels are dropped
		local skins = data.mMediaTag and data.mMediaTag.data_panel_skin and data.mMediaTag.data_panel_skin.panels
		for name in pairs(skins or {}) do
			if not DT.RegisteredPanels[name] then skins[name] = nil end
		end
	end,
}

local modules = {}
local E = {
	Retail = true,
	Modern = true,
	version = 15.3,
	mult = 1,
	mynameRealm = "Tester - Realm",
	private = { chat = { enable = true } },
	global = { general = { UIScale = 0.71 } },
	db = {},
	media = { normFont = "Fonts\\ARIALN.TTF" },
	UIParent = Stub("ElvUIParent"),
	PopupDialogs = {},
	Options = { args = {} },
	Libs = {
		EP = { RegisterPlugin = function(_, _, func) _G.__optionsLoader = func end },
		LSM = { Fetch = function() return "Fonts\\FRIZQT__.TTF" end },
	},
}
-- AceHook's RawHook/Unhook/IsHooked, enough to swap and restore a method
local function HookMixin(m)
	local originals = {}
	function m:RawHook(obj, method, handler)
		assert(not originals[method], "hooked twice: " .. method)
		originals[method] = obj[method]
		obj[method] = handler
	end
	function m:Unhook(obj, method)
		obj[method], originals[method] = originals[method], nil
	end
	function m:IsHooked(_, method)
		return originals[method] ~= nil
	end
end

local calls = { install = 0, cvars = 0, chat = 0 }
function E:Install() calls.install = calls.install + 1 end
function E:SetupCVars(quiet) assert(quiet, "CVars should run without ElvUI's message") calls.cvars = calls.cvars + 1 end
function E:SetupChat() error("MaUI sets up the chat itself") end

-- the profile the character uses before installing; ElvDB.global is the same table as E.global
_G.ElvDB = { global = E.global, profiles = { ["Mein Profil"] = { actionbar = { mine = true }, nameplates = { mine = true }, movers = { ElvAB_1 = "MINE", ElvNP_PlayerMover = "MINE", MinimapMover = "MINE" } } } }
_G.__currentProfile = "Mein Profil"
E.data = {
	GetCurrentProfile = function() return _G.__currentProfile end,
	SetProfile = function(_, name) assert(_G.ElvDB.profiles[name], "unknown profile " .. name) _G.__currentProfile = name end,
}

function E:GetModule(name)
	if name == "DataTexts" then return DT end
	if name == "Chat" then return Stub("Chat") end
	assert(name == "Distributor", "unexpected module " .. name)
	return D
end
function E:NewModule(name)
	local m = Stub(name)
	m.GetName = function() return name end
	HookMixin(m)
	modules[name] = m
	return m
end
function E:RegisterModule(name) assert(modules[name], "unknown module " .. name) end
function E:CopyTable(dst, src) return CopyInto(dst, src) end
function E:FilterTableFromBlacklist(t) return t end
function E:RGBToHex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
function E:PixelBestSize() return 0.7111 end
E.myclass = "PRIEST"
function E:ClassColor(class, usePriestColor) assert(class == "PRIEST" and usePriestColor) return { r = 1, g = 1, b = 1 } end
function E:StaticPopup_Show() end
function E:ToggleOptions() end
_G.ElvUI = { E, {}, {}, {}, {} }

-- other addons ----------------------------------------------------------------

local detailsImport
_G.Details = {
	CompressData = function(_, data, kind, blizzard) assert(type(data) == "table" and kind == "print" and blizzard) return "D!ProfileV2-x" end,
	ImportProfile = function(_, str, name, autorun, prompt, overwrite) detailsImport = { str, name, overwrite } return true end,
}

local baganatorImport
_G.Baganator = { API = { ImportString = function(str, name) baganatorImport = { str, name } end } }

_G.MauiMPlusTimerDB = { profileKeys = {}, profiles = { Default = {} } }

local mmtUpdated
local MMT_ROLES = "Interface\\AddOns\\ElvUI_mMediaTag\\media\\icons\\role\\"
_G.ElvUI_mMediaTag = {
	{ UpdateModule = function(_, name) mmtUpdated = name end },
	[5] = { role_icons = { tank = "shield9", heal = "heal13", dd = "bigsword2" } }, -- mMT's profile defaults
	[7] = { icons = { role = { shield9 = MMT_ROLES .. "shield9", heal13 = MMT_ROLES .. "heal13", bigsword2 = MMT_ROLES .. "bigsword2" } } },
}

-- load the addon in toc order -----------------------------------------------

function LoadToc(name)
	local folder = "Installer/" .. name .. "/"
	local engine = {}
	local toc = assert(io.open(folder .. name .. ".toc"))
	for line in toc:lines() do
		line = line:gsub("\r", "")
		if line ~= "" and not line:find("^#") then
			local chunk = assert(loadfile(folder .. line:gsub("\\", "/")))
			local ok, err = pcall(chunk, name, engine)
			check(ok, "loading " .. name .. "/" .. line .. ": " .. tostring(err))
		end
	end
	toc:close()
end

LoadToc(ADDON)

local MaUI, L = unpack(_G.ElvUI_MaUI)
check(MaUI.Version == "dev", "unpackaged version should read dev")
check(L["Next"] == "Weiter", "German locale not applied")

-- the profile data waits in its LoadOnDemand addon until something asks for it
check(next(MaUI.Data) == nil and dataLoads == 0, "the profile data should not load with the installer")
check(MaUI.DataRevision and MaUI.LegacyKeys["8.5/heal_cdm"] and MaUI.ThemeColors.backdropcolor, "the index should come with the installer")

-- every data block the modules need is registered
for _, pair in ipairs({
	{ "elvui", "base" }, { "elvui", "tankdd" }, { "elvui", "tankdd_cdm" }, { "elvui", "heal" }, { "elvui", "heal_cdm" },
	{ "elvui", "private" }, { "elvui", "global" }, { "mmt", "datapanels" }, { "mmt", "cdm" }, { "blizzard", "editmode" }, { "blizzard", "editmode_forever" },
	{ "details", "profile" }, { "baganator", "profile" }, { "baganator", "categories" }, { "mplustimer", "profile" },
}) do
	check(type(MaUI:GetData(pair[1], pair[2])) ~= "nil", "missing data " .. pair[1] .. "/" .. pair[2])
end

-- stable text form of a table, to see whether the data survives an installation untouched
local function Serialize(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Serialize(value[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end
local dataSnapshot = Serialize(MaUI.Data)
check(dataLoads == 1, "the data addon should load once: " .. dataLoads)

-- boot and walk through the installer ---------------------------------------

local addonModule = modules[ADDON]
addonModule:Initialize()
check(E.private.install_complete == nil, "ElvUI's data must not be touched before installing")
E:Install() -- what ElvUI does at the end of its E:Initialize on a fresh character
check(calls.install == 0, "ElvUI's installer should be held back while ours is pending")
RunTimers()

local frame = _G.MaUIInstallerFrame
local C = MaUI.Colors
check(C.accent[1] == 1 and C.accent[2] == 1, "accent should take the class color")
check(C.onAccent[1] < 0.2, "white class colors need dark text on accents")
local backdrop = MaUI:GetData("elvui", "base").general.backdropcolor
check(math.abs(C.background[1] - backdrop.r) < 0.0001, "background should come from the MaUI profile")
check(frame and frame:IsShown(), "installer did not open on first login")
_G.__optionsLoader()
check(E.Options.args.MaUIInstaller, "options entry missing")

local Installer, State = MaUI.Installer, MaUI.State
check(State.cdm == true, "CDM should default on for retail")
check(State.modules.details and State.modules.baganator and State.modules.mplustimer, "found addons should be preselected")
check(State.modules.cvars and State.modules.chat, "CVars and chat should be preselected on a fresh character")

-- pages: 1 welcome, 2 ElvUI setup, 3 existing profiles, 4 layout, 5 ElvUI modules, 6 data panels, 7 addons, 8 scale, 9 install, 10 done
local nextButton = Installer.content.next
check(State.existing == nil and not MaUI.Pages[3].IsShown(), "no MaUI profile on the account yet, so no profile page")
check(MaUI:GetSteps()[1].key == "cvars" and MaUI:GetSteps()[2].key == "chat", "CVars and chat should run before the profile")

Click(nextButton) -- welcome -> ElvUI setup
check(Installer.index == 2, "the ElvUI setup should come right after the welcome page")
check(Installer.content.stepLabel:GetText() == "SCHRITT 2 VON 8", "step counter should leave hidden pages out: " .. tostring(Installer.content.stepLabel:GetText()))
check(#MaUI.Pages[2].frame.cards == 2, "setup page should show CVars and chat")

check(MaUI.Pages[4].frame == nil, "pages should be built when they are first shown")
Click(nextButton) -- -> layout, past the hidden profile page
check(Installer.index == 4, "next should skip the hidden profile page")
local layoutCards = MaUI.Pages[4].frame.cards
Click(layoutCards[2]) -- pick the healer layout
check(State.layout == "heal", "layout card did not select")
check(not MaUI.Pages[5].IsShown(), "the ElvUI modules page belongs to the advanced mode only")

Click(nextButton) -- -> data panels
check(Installer.index == 6, "next should skip the hidden modules page")
local panelsPage = MaUI.Pages[6].frame
check(#panelsPage.cards == 4 and panelsPage.cards[1]:IsShown(), "the data panels page should offer four bars")
Click(panelsPage.cards[3]) -- dock only
Click(panelsPage.currency.toggle) -- no currency panel
check(State.panels.bar == "dock" and not State.panels.currency and State.panels.cosmetic, "the data panel choice did not apply")

Click(nextButton) -- -> addons
check(Installer.index == 7, "did not reach the addons page")
local baganatorCard
for _, card in ipairs(MaUI.Pages[7].frame.cards) do
	if card.module.key == "baganator" then baganatorCard = card end
end
Click(baganatorCard.choice.buttons[2])
check(State.choices.baganator == "categories", "segmented choice did not apply")

Click(nextButton) -- -> scale
check(MaUI.Pages[8].frame.notice:IsShown(), "1080p should show the resolution notice")
check(math.abs(MaUI:GetTargetScale("layout") - 0.4) < 0.001, "layout scale for 1080p should be 0.4")

Click(nextButton) -- -> install
check(Installer.index == 9, "did not reach the install page")
Click(nextButton) -- runs the installation
check(Installer.installing, "install did not start")
RunTimers()
check(Installer.installed and Installer.failed == 0, "installation reported failures: " .. tostring(Installer.failed))

-- results ---------------------------------------------------------------------

local profile = imported.profile
check(profile and profile.key == "MaUI Heal CDM" and profile.force, "ElvUI profile not imported under its name")
check(MaUIInstallerDB.profiles["MaUI Heal CDM"] and MaUIInstallerDB.profiles["MaUI Heal CDM"].revision == MaUI.DataRevision, "installed profile not remembered with its data revision")
check(type(MaUIInstallerDB.profiles["MaUI Heal CDM"].data) == "string", "the profile snapshot should be stored packed")
local installedPanels = profile.data.datatexts.panels
check(installedPanels["mMT - EXTRA LEFT"].enable == false and installedPanels["mMT - CENTER"].enable == false, "panels outside the chosen bar should be switched off")
check(installedPanels["mMT - LEFT"].enable ~= false and installedPanels["mMT - RIGHT"].enable ~= false, "the dock and the right panel should stay")
check(installedPanels["mMT - CURRENCY"].enable == false and installedPanels["MAUI - COSMETICK CENTER"].enable ~= false, "currency off, decorative bars on")
check(MaUIInstallerDB.profiles["MaUI Heal CDM"].panels.bar == "dock", "the panel choice should be remembered for updates")
check(MaUI:ProfileStatus("MaUI Heal CDM") == "current", "a fresh installation should be up to date")
check(profile and profile.data.mMediaTag.cooldown_manager.spell_active_state, "CDM spell settings missing from the profile")
check(profile and profile.data.movers.ElvUF_PlayerMover, "movers missing from the profile")
check(profile and profile.data.mMediaTag.data_panel_skin.panels["MAUI - COSMETICK CENTER"], "data panel skins lost on the first installation")
check(mmtUpdated == "DataPanelSkin", "mMT data panels not refreshed")
check(E.private.bags and E.private.bags.enable == false, "private settings not applied")
check(E.global.general.UIScale == 0.4, "UI scale not set: " .. tostring(E.global.general.UIScale))
check(savedEditMode and #savedEditMode.layouts == 2 and savedEditMode.layouts[2].layoutName == "MaUI", "Edit Mode layout not saved once")
check(_G.__activeLayout == 4, "Edit Mode layout not activated: " .. tostring(_G.__activeLayout))
check(detailsImport and detailsImport[2] == "MaUI" and detailsImport[3], "Details import missing")
check(baganatorImport and baganatorImport[1]:find("^BGR!1!") and baganatorImport[2] == "MaUI", "Baganator import missing")
check(_G.MauiMPlusTimerDB.profileKeys["Tester - Realm"] == "MaUI" and _G.MauiMPlusTimerDB.profiles.MaUI, "M+ Timer profile missing")
check(MaUIInstallerCharDB.installed == "8.5" and MaUIInstallerCharDB.layout == "heal", "install state not saved")
check(calls.cvars == 1, "CVars setup did not run once")

-- chat: one docked window on the left, five tabs in the requested order, the voice tab hidden behind
local order = {}
for _, frame in ipairs(dock) do
	if frame.title ~= "Sprache" then order[#order + 1] = frame.title end
end
check(table.concat(order, ",") == "Allgemein,Flüstern,Gruppe,Gilde,Kampflog", "chat tab order: " .. table.concat(order, ","))
local tabs = {}
for _, frame in ipairs(dock) do tabs[frame.title] = frame end
check(tabs.Allgemein.channels.Allgemein and tabs.Allgemein.channels.Handel, "general tab should show General and Trade")
check(tabs.Allgemein.groups.LOOT and tabs.Allgemein.groups.SAY and not tabs.Allgemein.groups.WHISPER and not tabs.Allgemein.groups.GUILD, "general tab groups")
check(not tabs.Allgemein.groups.PING, "groups the client does not know must be skipped")
check(tabs.Handel == nil, "there should be no trade tab")
check(tabs["Flüstern"].groups.WHISPER and tabs["Flüstern"].groups.BN_WHISPER, "whisper tab groups")
check(tabs.Gruppe.groups.PARTY and tabs.Gruppe.groups.RAID and tabs.Gruppe.groups.INSTANCE_CHAT, "group tab groups")
check(tabs.Gilde.groups.GUILD and tabs.Gilde.groups.OFFICER, "guild tab groups")
check(tabs.Kampflog == _G.ChatFrame2 and tabs.Kampflog.groups.COMBAT, "combat log should stay Blizzard's ChatFrame2")
check(E.private.install_complete == E.version, "ElvUI should count as set up after our installation")
check(calls.install == 0, "ElvUI's installer must not open after our installation")

-- the stored data must come out of an installation unchanged
check(Serialize(MaUI.Data) == dataSnapshot, "an installation modified the registered data")

Click(nextButton) -- -> done
check(Installer.index == #MaUI.Pages, "did not reach the done page")
Click(nextButton)
check(_G.__reloaded, "last page should reload the UI")

-- tank layout without the Cooldown Manager on a 1440p screen
screen[1], screen[2] = 2560, 1440
MaUI:ResetState()
State.layout, State.cdm = "tankdd", false
check(MaUI:GetTargetScale("pixel") == 0.5333, "1440p should always use the design scale")
local tank = MaUI:BuildProfile(State)
State.existing = nil
check(MaUI:ProfileName(State) == "MaUI Tank-DD", "tank profile name: " .. MaUI:ProfileName(State))
check(tank.movers.ElvUF_PlayerMover == MaUI:GetData("elvui", "tankdd").movers.ElvUF_PlayerMover, "tank layout movers not applied")
check(not (tank.mMediaTag.cooldown_manager or {}).spell_active_state or MaUI:GetData("elvui", "base").mMediaTag.cooldown_manager.spell_active_state, "CDM spell settings leaked into the plain layout")

-- a reload on the installed character: nothing opens, nothing is held back
_G.MaUIInstallerFrame:Hide()
addonModule:Initialize()
RunTimers()
check(not _G.MaUIInstallerFrame:IsShown(), "installer opened again on an installed character")
check(not addonModule:IsHooked(E, "Install"), "ElvUI's installer held back on an installed character")
check(not MaUI.ElvUIFresh, "installed character should not count as fresh")

-- the installed character resets ElvUI's private settings: both installers want to run again, ours goes first
E.private = { chat = { enable = true } }
addonModule:Initialize()
E:Install()
RunTimers()
check(_G.MaUIInstallerFrame:IsShown(), "installer should open again after ElvUI's private settings were reset")
check(calls.install == 0, "ElvUI's installer should be held back after the reset")
check(MaUI.ElvUIFresh and MaUI.State.modules.cvars, "a reset character counts as fresh")
check(MaUIInstallerCharDB.layout == "heal", "the last layout choice should survive the reset")
MaUI:ReleaseElvUIInstaller() -- a reload ends the session hook
_G.MaUIInstallerFrame:Hide()

-- a second, fresh character that skips: ElvUI's installer comes right back, ours stays closed afterwards;
-- it starts with its intro cinematic, the installer waits for it
_G.MaUIInstallerCharDB, E.private = {}, { chat = { enable = true } }
_G.CinematicFrame = Stub()
_G.CinematicFrame:Show()
addonModule:Initialize()
E:Install()
RunTimers()
check(not _G.MaUIInstallerFrame:IsShown(), "the installer must wait while the intro cinematic plays")
_G.CinematicFrame:Hide()
addonModule:CINEMATIC_STOP()
RunTimers()
check(_G.MaUIInstallerFrame:IsShown() and calls.install == 0, "fresh character: ours should open after the cinematic, ElvUI's be held back")
-- a later cinematic closes the installer, it comes back on the same page
local cinematicPage = Installer.index
_G.CinematicFrame:Show()
_G.MaUIInstallerFrame:Hide()
_G.CinematicFrame:Hide()
addonModule:CINEMATIC_STOP()
RunTimers()
check(_G.MaUIInstallerFrame:IsShown() and Installer.index == cinematicPage, "a cinematic should not close the installer for good")
-- closed by the user it stays closed
_G.MaUIInstallerFrame:Hide()
addonModule:CINEMATIC_STOP()
RunTimers()
check(not _G.MaUIInstallerFrame:IsShown(), "an installer the user closed must stay closed")
_G.MaUIInstallerFrame:Show()
_G.CinematicFrame = nil
Click(Installer.content.skip)
check(calls.install == 1, "skipping should open ElvUI's installer once")
check(E.private.install_complete == nil, "skipping must leave ElvUI unmarked")
check(MaUIInstallerCharDB.skipped and not MaUIInstallerCharDB.installed, "skip not remembered")
check(not addonModule:IsHooked(E, "Install"), "skipping should release ElvUI's installer")

_G.MaUIInstallerFrame:Hide()
addonModule:Initialize()
E:Install()
RunTimers()
check(not _G.MaUIInstallerFrame:IsShown(), "skipped installer opened again")
check(calls.install == 2, "after a skip ElvUI's installer should run as usual")

-- the user finishes ElvUI's own installer, later resets ElvUI's private settings: ours is offered again
E.private.install_complete = E.version
addonModule:Initialize()
RunTimers()
check(not _G.MaUIInstallerFrame:IsShown(), "nothing should open while ElvUI is set up")
E.private = { chat = { enable = true } }
addonModule:Initialize()
RunTimers()
check(_G.MaUIInstallerFrame:IsShown(), "installer should open after a reset, even when it was skipped before")

-- a new character on an account with a MaUI profile: CVars and chat first, then it just uses that profile
MaUI:ReleaseElvUIInstaller()
_G.MaUIInstallerCharDB, E.private = {}, { chat = { enable = true } }
_G.__currentProfile, imported.profile, calls.cvars = "Mein Profil", nil, 0
MaUI:ShowInstaller()
check(State.existing == "MaUI Heal CDM", "the existing MaUI profile should be suggested")
Click(nextButton) -- -> ElvUI setup
Click(nextButton) -- -> existing profiles
check(Installer.index == 3, "the profile page should show when MaUI profiles exist")
check(MaUI.Pages[3].frame.rows[1].profileName == "MaUI Heal CDM" and MaUI.Pages[3].frame.rows[2].profileName == nil, "rows: the profile, then a new install")
Click(nextButton) -- -> addons, layout and modules do not apply to an existing profile
check(Installer.index == 7, "an existing profile should skip the layout and data panel pages")
Click(nextButton) -- -> scale
Click(nextButton) -- -> install
Click(nextButton)
RunTimers()
check(Installer.installed and Installer.failed == 0, "existing profile install reported failures")
check(_G.__currentProfile == "MaUI Heal CDM", "the character should switch to the existing profile")
check(imported.profile == nil, "an existing profile must not be imported again")
check(calls.cvars == 1 and E.private.bags and E.private.bags.enable == false, "CVars and private settings should still be applied")

-- a new MaUI release changes its data: the profile is outdated and only the changes are carried over
local name = "MaUI Heal CDM"
local base = MaUI:GetData("elvui", "base")
local userProfile = _G.ElvDB.profiles[name]
userProfile.general.valuecolor.r = 0.123 -- the user changed something MaUI keeps as it was
userProfile.tooltip = userProfile.tooltip or {}
userProfile.tooltip.userSetting = "mine" -- and added something of their own
base.general.newMaUISetting = 42 -- MaUI adds a setting
base.general.backdropfadecolor = nil -- and drops one the user never touched
MaUI.DataRevision = "next-release"
check(MaUI:ProfileStatus(name) == "outdated" and MaUI:CurrentProfileUpdate() == name, "changed data should mark the profile outdated")

addonModule:Initialize() -- next login on that character
RunTimers()
check(_G.MaUIUpdateNotice and _G.MaUIUpdateNotice:IsShown(), "login should show the update notice")
check(_G.ElvDB.profiles[name].general.newMaUISetting == nil, "the preview must not change the profile")
local noticeText = _G.MaUIUpdateNotice.text:GetText()
check(noticeText:find("Was sich ändert (2 Einstellungen):", 1, true) and noticeText:find("Allgemein: 2 Einstellungen", 1, true), "the notice should list what changes: " .. noticeText)
local previewList, previewTotal = MaUI:PreviewUpdate(name)
check(previewTotal == 2 and #previewList == 1 and previewList[1].count == 2, "the preview should count the changes per area")
check(previewList[1].subjects[1] == "backdropfadecolor" or previewList[1].subjects[1] == "newMaUISetting", "the preview should name what an area changes")

-- the notice opens the installer on the update page, which shows the changes before anything happens
Click(_G.MaUIUpdateNotice.primary)
check(not _G.MaUIUpdateNotice:IsShown() and Installer.frame:IsShown(), "the notice should hand over to the installer")
local updatePage = MaUI.Pages[Installer.index]
check(State.updating == name and updatePage.update == "only", "the installer should open on the update page")
check(Installer:Position(Installer.index) == 1 and select(2, Installer:Position(Installer.index)) == 2, "an update should only have the update and done step")
check(not Installer.content.back:IsShown(), "the update page has no way back")
check(updatePage.frame.rows[1]:IsShown() and updatePage.frame.rows[1].name:GetText() == "Allgemein" and updatePage.frame.rows[1].count:GetText() == "2", "the update page should list the changed areas")
check(not updatePage.frame.rows[2]:IsShown() and updatePage.frame.summary.total.value:GetText() == "2", "the update page should sum up the changes")
check(_G.ElvDB.profiles[name].general.newMaUISetting == nil, "opening the update must not change the profile")
Click(nextButton) -- runs the update
check(Installer.index == #MaUI.Pages and Installer.updated == 2, "the update should end on the done page")
check(MaUI.Pages[Installer.index].frame.headline:GetText() == "Profil aktualisiert", "the done page should talk about the update")
local updated = _G.ElvDB.profiles[name]
check(updated.general.newMaUISetting == 42, "new MaUI settings should be added")
check(updated.datatexts.panels["mMT - CENTER"].enable == false, "an update must not switch on panels the user left out")
check(updated.general.valuecolor.r == 0.123, "the user's own changes must stay")
check(updated.tooltip.userSetting == "mine", "settings the user added must stay")
check(updated.general.backdropfadecolor == nil, "settings MaUI dropped should go when the user left them alone")
check(MaUI:ProfileStatus(name) == "current", "the profile should be up to date after the update")
check(MaUI:UpdateProfile(name) == 0, "a second update should find nothing to change")

-- advanced mode: only nameplates and unit frames go into the current profile
MaUI:ReleaseElvUIInstaller()
_G.MaUIInstallerCharDB, E.private = {}, { chat = { enable = true } }
_G.__currentProfile, calls.install, imported.profile = "Mein Profil", 0, nil
MaUI:ShowInstaller()
Click(nextButton) -- -> ElvUI setup
Click(nextButton) -- -> existing profiles
Click(MaUI.Pages[3].frame.rows[2]) -- install a new one instead
check(State.existing == nil, "the new install row should clear the existing profile")
Click(nextButton) -- -> layout
local layoutPage = MaUI.Pages[4].frame
Click(layoutPage.advancedOption.toggle)
check(State.advanced and MaUI.Pages[5].IsShown(), "advanced toggle should show the modules page")
Click(nextButton) -- -> ElvUI modules
check(Installer.index == 5, "advanced mode should open the modules page")
for _, card in ipairs(MaUI.Pages[5].frame.cards) do
	if card.key ~= "nameplates" and card.key ~= "unitframe" then Click(card.toggle) end
end
check(nextButton:IsEnabled(), "two selected modules should allow going on")
for _ = 1, 3 do Click(nextButton) end -- addons, scale, install (no data panel page in the advanced mode)
check(Installer.index == 9, "advanced mode did not reach the install page")
Click(nextButton)
RunTimers()
local merged = imported.profile
check(merged and merged.key == "Mein Profil", "advanced mode must write into the current profile")
check(merged and merged.data.actionbar.mine, "unselected sections of the current profile must stay")
check(merged and merged.data.nameplates and not merged.data.nameplates.mine, "selected sections should come from MaUI")
check(merged and merged.data.movers.ElvAB_1 == "MINE" and merged.data.movers.MinimapMover == "MINE", "movers of unselected sections must stay")
check(merged and merged.data.movers.ElvUF_PlayerMover and merged.data.movers.ElvNP_PlayerMover ~= "MINE", "movers of selected sections should come from MaUI")
check(merged and merged.data.mMediaTag == nil, "mMediaTag was not selected and must not be added")
check(MaUI:MoverSection("DTPanelmDockMover") == "datatexts" and MaUI:MoverSection("ObjectiveFrameMover") == "general", "mover sections")

-- profiles imported by hand from older releases: v8 and later can be updated, older ones only used
local v85 = MaUI:LegacyData(MaUI:ParseProfileName("MaUI v8.5 Heal CDM"))
check(v85 and v85.movers.ElvUF_PlayerMover, "the v8.5 healer profile should be rebuilt from the stored difference")
v85.chat = v85.chat or {}
v85.chat.userSetting = "mine"
_G.ElvDB.profiles["MaUI v8.5 Heal CDM"] = v85
_G.ElvDB.profiles["MaUI v8 TANK/DD"] = MaUI:LegacyData(MaUI:ParseProfileName("MaUI v8 TANK/DD"))
_G.ElvDB.profiles["MaUI [v7] Tank-DD"] = { general = { old = true } }
_G.ElvDB.profiles["MaUI Kopie"] = { general = {} }

local parsed = MaUI:ParseProfileName("MaUI v8 TANK/DD")
check(parsed.version == "8" and parsed.layout == "tankdd" and not parsed.cdm, "v8 name parsing")
parsed = MaUI:ParseProfileName("MaUI [v7] Heal")
check(parsed.version == "7" and parsed.layout == "heal", "v7 name parsing")
parsed = MaUI:ParseProfileName("MaUI 8.5 Tank-DD CDM")
check(parsed and parsed.version == "8.5" and parsed.layout == "tankdd" and parsed.cdm, "names from early installer builds have no v")
check(MaUI:ParseProfileName("MaUI Tank-DD") == nil, "current installer names carry no version")
check(MaUI:ProfileStatus("MaUI v8.5 Heal CDM") == "outdated", "a v8.5 import should offer an update")
check(MaUI:ProfileStatus("MaUI v8 TANK/DD") == "outdated", "a v8 import should offer an update")
check(MaUI:ProfileStatus("MaUI [v7] Tank-DD") == "old", "a v7 import is too old for updates")
check(MaUI:ProfileStatus("MaUI Kopie") == "unknown", "an unknown MaUI name cannot be updated")

local order = {}
for _, profile in ipairs(MaUI:FindProfiles()) do order[#order + 1] = profile.name end
check(order[1] == "MaUI Heal CDM", "installed profiles come first: " .. table.concat(order, ", "))
check(order[2] == "MaUI v8.5 Heal CDM" and order[3] == "MaUI v8 TANK/DD", "updatable imports next, newest version first: " .. table.concat(order, ", "))
check(order[#order] == "MaUI [v7] Tank-DD", "profiles too old for updates come last: " .. table.concat(order, ", "))

-- the profile page shows them with their status; picking the v8.5 one takes over its layout
MaUI:ShowInstaller()
Click(nextButton) -- -> ElvUI setup
Click(nextButton) -- -> existing profiles
local profilePage = MaUI.Pages[3].frame
local v85Row
for _, row in ipairs(profilePage.rows) do
	if row.profileName == "MaUI v8.5 Heal CDM" then v85Row = row end
end
check(v85Row and v85Row.pill.text:GetText() == "Update verfügbar", "the list should show that the profile is outdated")
check(v85Row and v85Row.detail:GetText():find("v8.5", 1, true), "the list should show the version: " .. tostring(v85Row and v85Row.detail:GetText()))
Click(v85Row)
check(State.existing == "MaUI v8.5 Heal CDM" and State.layout == "heal" and State.cdm, "picking an import should take over its layout")
check(profilePage.updateOption:IsShown(), "an outdated pick should offer the update")
MaUI.Installer.frame:Hide()

local changes = MaUI:UpdateProfile("MaUI v8.5 Heal CDM")
local v85Updated = _G.ElvDB.profiles["MaUI v8.5 Heal CDM"]
check(changes > 0, "updating the v8.5 import should change something")
check(v85Updated.general.newMaUISetting == 42, "the update should bring the current MaUI settings")
check(v85Updated.chat.userSetting == "mine", "the user's own settings in an import must stay")
check(MaUI:ProfileStatus("MaUI v8.5 Heal CDM") == "current" and MaUIInstallerDB.profiles["MaUI v8.5 Heal CDM"].version == "8.5", "an updated import should be tracked from then on")
check(MaUI:UpdateProfile("MaUI [v7] Tank-DD") == 0 and _G.ElvDB.profiles["MaUI [v7] Tank-DD"].general.old, "a v7 profile must not be touched")

-- ElvUI options: logo, profile information and the update button for the character's profile
_G.__currentProfile = "MaUI v8 TANK/DD"
_G.__optionsLoader()
local options = E.Options.args.MaUIInstaller
check(options.args.hero.image == MaUI.Media.logo and options.args.hero.name():find(MaUI.Version, 1, true), "the options should show the logo and the version")
local profileArgs = options.args.profile.args
local info = profileArgs.title.name() .. profileArgs.info.name()
check(info:find("MaUI v8 TANK/DD", 1, true) and info:find("Update verfügbar", 1, true), "the options should show the profile and that it is outdated: " .. info)
check(info:find("v8, manuell importiert", 1, true), "the options should say where the profile came from: " .. info)
check(not profileArgs.update.disabled() and profileArgs.hint.name():find("Was sich ändert", 1, true), "an outdated profile should be updatable from the options, with a preview")
profileArgs.update.func()
check(State.updating == "MaUI v8 TANK/DD" and MaUI:ProfileStatus("MaUI v8 TANK/DD") == "outdated", "the options should open the update in the installer")
Click(nextButton) -- runs the update
check(MaUI:ProfileStatus("MaUI v8 TANK/DD") == "current" and profileArgs.update.disabled(), "after the update the button should be disabled")
check(profileArgs.info.name():find("Aktuell", 1, true) and profileArgs.hint.name() == "", "the options should show the profile as up to date")
local accountList = options.args.account.args.list.name()
check(accountList:find("shield9", 1, true) and accountList:find("bigsword2", 1, true) and accountList:find("heal13", 1, true), "the options should use mMT's role icons")
check(MaUI.Widgets.RoleIcon("HEALER") == MMT_ROLES .. "heal13", "the installer should use the role icon of the MaUI profile")
check(accountList:find("MaUI Heal CDM", 1, true) and accountList:find("Zu alt für Updates", 1, true), "the account list should show every MaUI profile with its status")
_G.__currentProfile = "Mein Profil"
check(profileArgs.info.name():find("Kein MaUI-Profil", 1, true), "a foreign profile should be named as such")

-- other game versions: datatexts they lack are replaced, missing dock buttons are dropped without gaps
local FLAVORS = { "Retail", "Classic", "TBC", "Wrath", "Mists", "Forever" }
local function Datatexts(flavor)
	for _, key in ipairs(FLAVORS) do E[key] = key == flavor end
	E.Modern = E.Retail or E.Forever
	local profile = MaUI:BuildProfile({ layout = "tankdd", cdm = false })
	local global = MaUI:GlobalData()
	local all = {}
	for _, panel in pairs(profile.datatexts.panels) do
		for key, datatext in pairs(panel) do
			if type(key) == "number" then all[datatext] = true end
		end
	end
	return all, profile.datatexts.panels["mMT - LEFT"], global.datatexts.customPanels["mMT - LEFT"]
end

local function Slots(panel)
	local count = 0
	for key, datatext in pairs(panel) do
		if type(key) == "number" then
			count = count + 1
			check(datatext ~= "", "the dock should not get an empty slot")
		end
	end
	return count
end

local retail, retailDock, retailPanel = Datatexts("Retail")
check(retail["mMT - M+ Score"] and retail["Talent/Loot Specialization"] and Slots(retailDock) == 12 and retailPanel.numPoints == 12, "Retail keeps the panels as built")

for _, flavor in ipairs({ "Classic", "TBC" }) do
	local dts, dock, panel = Datatexts(flavor)
	check(not dts["mMT - M+ Score"] and dts["mMT - Game menu"], flavor .. ": the M+ Score should become the game menu")
	check(not dts["Talent/Loot Specialization"] and dts.DualSpecialization, flavor .. ": the specialization should become dual specialization")
	check(not dts.Difficulty and dts["mMT - Dungeon"], flavor .. ": difficulty should become the dungeon datatext")
	check(not dts.mMT_Dock_Achievement and not dts.mMT_Dock_CollectionsJournal and not dts.mMT_Dock_EncounterJournal, flavor .. ": dock buttons without a window should go")
	check(Slots(dock) == 9 and panel.numPoints == 9 and panel.width == 405, flavor .. ": the dock should shrink to 9 buttons of the same size, got " .. Slots(dock) .. "/" .. panel.numPoints .. "/" .. tostring(panel.width))
end

local wrath, wrathDock = Datatexts("Wrath")
check(wrath.DualSpecialization and wrath.Difficulty and wrath["mMT - Game menu"] and Slots(wrathDock) == 12, "Wrath: dual specialization and game menu, the full dock")

local mists = Datatexts("Mists")
check(mists["Talent/Loot Specialization"] and mists["mMT - Game menu"] and not mists["mMT - M+ Score"], "Mists: only the M+ Score is replaced")

local forever, foreverDock, foreverPanel = Datatexts("Forever")
check(forever["Equipment Sets"] and not forever.Friends and not forever["Talent/Loot Specialization"] and forever.Difficulty, "Forever: equipment sets instead of the specialization, friends stay in the dock")
check(Slots(foreverDock) == 11 and foreverPanel.numPoints == 11 and not forever.mMT_Dock_EncounterJournal, "Forever: the dock loses the encounter journal only")

-- Baganator: classic clients lose the expansion and season conditions and the categories built on them
local function BaganatorSearches(data)
	local searches, names = {}, {}
	for id, category in pairs(data.custom_categories or {}) do
		searches[tostring(id)], names[tostring(id)] = category.search, category.name
	end
	for _, category in ipairs(data.categories or {}) do
		searches[category.source], names[category.source] = category.search, category.name
	end
	return searches, names
end
for _, flavor in ipairs({ "Retail", "Forever", "Classic" }) do
	for _, key in ipairs(FLAVORS) do E[key] = key == flavor end
	for _, kind in ipairs({ "profile", "categories" }) do
		local data = MaUI:BaganatorData(kind)
		local searches, names = BaganatorSearches(data)
		local conditions, droppedLeft = false, false
		for id, search in pairs(searches) do
			if search:find("current expansion", 1, true) or search:find("active season", 1, true) then conditions = true end
			if names[id] == "Old" or names[id] == "M+" or names[id] == "Current" or names[id] == "Delves" or names[id] == "Hunt" then droppedLeft = true end
		end
		local order = data.category_display_order or data.order
		local orderOk = true
		for _, id in ipairs(order) do
			if names[id] == nil and tonumber(id) then orderOk = false end
		end
		if flavor == "Retail" then
			check(Serialize(data) == Serialize(MaUI:GetData("baganator", kind)), "Baganator: retail must get its " .. kind .. " unchanged")
		else
			check(not conditions and not droppedLeft and orderOk, flavor .. ": Baganator " .. kind .. " must lose the expansion conditions and Old, M+, Current, Delves and Hunt")
			check(searches["735"] == "#essen trinken" and searches["718"] == "#ausrüstung&#set bonus", flavor .. ": Baganator searches should keep everything else: " .. tostring(searches["718"]))
		end
	end
end
check(MaUI:GetData("baganator", "profile").custom_categories["735"].search:find("current expansion", 1, true), "the registered Baganator data must stay as it is")

for _, key in ipairs(FLAVORS) do E[key] = key == "Retail" end
E.Modern = true

print(failures == 0 and "OK - all checks passed" or (failures .. " check(s) failed"))
os.exit(failures == 0 and 0 or 1)
