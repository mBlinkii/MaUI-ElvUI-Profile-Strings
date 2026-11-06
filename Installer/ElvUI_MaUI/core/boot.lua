local MaUI, L, E = unpack(ElvUI_MaUI)
local EP = E.Libs.EP

local _G = _G
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

local module = E:NewModule(MaUI.AddonName, "AceEvent-3.0", "AceHook-3.0")

-- opens by itself only once per character, afterwards only through /maui
local function ShouldAutoShow()
	local db = MaUIInstallerCharDB
	return not db.installed and not db.skipped
end

-- ElvUI calls E:Install on login and after every profile switch as long as install_complete is unset.
-- While our installer is pending the call is swallowed for this session only, ElvUI's data stays untouched.
local function HoldElvUIInstaller()
	if not module:IsHooked(E, "Install") then
		module:RawHook(E, "Install", function() end, true)
	end
end

function MaUI:ReleaseElvUIInstaller()
	if module:IsHooked(E, "Install") then module:Unhook(E, "Install") end
end

function MaUI:SkipInstall()
	MaUIInstallerCharDB.skipped = true
	self:ReleaseElvUIInstaller()

	-- the user gets ElvUI's installer exactly when ElvUI would have shown it without us
	if not E.private.install_complete then E:Install() end
end

-- a new character often starts with its intro cinematic, which hides the interface and closes open windows;
-- the installer waits for it and comes back when a cinematic closed it
local function InCinematic()
	local cinematic, movie = _G.CinematicFrame, _G.MovieFrame
	return (cinematic and cinematic:IsShown()) or (movie and movie:IsShown())
end

local autoShown -- opened by itself in this session

local function AutoShow()
	if not ShouldAutoShow() or InCinematic() then return end

	if InCombatLockdown() then
		MaUI.Installer.pending = true
		return
	end

	local installer = MaUI.Installer
	if not autoShown then
		autoShown = true
		MaUI:ShowInstaller()
		-- a cinematic closes open windows while it is already on screen, the user closing it is not one
		if installer.frame and not installer.cinematicHook then
			installer.cinematicHook = true
			installer.frame:HookScript("OnHide", function()
				if InCinematic() then installer.closedByCinematic = true end
			end)
		end
	elseif installer.closedByCinematic then
		-- it opens again on the same page; closed by the user it stays closed
		installer.frame:Show()
	end
	installer.closedByCinematic = nil
end

function module:CINEMATIC_STOP()
	C_Timer.After(1, AutoShow)
end
module.STOP_MOVIE = module.CINEMATIC_STOP

-- ElvUI builds its options on demand, ui\options.lua adds ours then
local function LoadOptions()
	MaUI:LoadOptions()
end

function module:PLAYER_REGEN_DISABLED()
	MaUI:HideInstallerForCombat()
end

function module:PLAYER_REGEN_ENABLED()
	MaUI:RestoreInstallerAfterCombat()

	local pending = MaUI.Installer.pending
	if pending then
		MaUI.Installer.pending = nil
		MaUI:ShowInstaller(pending ~= true and pending or nil)
	end
end

function module:Initialize()
	_G.MaUIInstallerCharDB = _G.MaUIInstallerCharDB or {}

	EP:RegisterPlugin(MaUI.AddonName, LoadOptions)
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")

	-- runs before ElvUI's own install check at the end of E:Initialize
	MaUI.ElvUIFresh = not E.private.install_complete

	-- install_complete lives in ElvUI's private settings; when it is gone on a character that was set up
	-- before, those settings were reset and ElvUI asks to be installed again, so we offer ours again too
	local db = MaUIInstallerCharDB
	if E.private.install_complete then
		db.elvuiInstalled = true
	elseif db.installed or db.elvuiInstalled then
		db.installed, db.skipped, db.elvuiInstalled = nil, nil, nil
	end

	autoShown = nil
	if ShouldAutoShow() then
		HoldElvUIInstaller()

		self:RegisterEvent("CINEMATIC_STOP")
		self:RegisterEvent("STOP_MOVIE")
		C_Timer.After(2, AutoShow)
	else
		-- the character uses a MaUI profile that is older than the data of this installer
		local update = MaUI:CurrentProfileUpdate()
		if update then
			C_Timer.After(4, function()
				MaUI:ShowUpdateNotice(update)
			end)
		end
	end
end

_G.SLASH_MAUIINSTALLER1 = "/maui"
_G.SLASH_MAUIINSTALLER2 = "/mauiinstall"
_G.SlashCmdList.MAUIINSTALLER = function()
	MaUI:ToggleInstaller()
end

function _G.ElvUI_MaUI_OnAddonCompartmentClick()
	MaUI:ToggleInstaller()
end

E:RegisterModule(module:GetName())
