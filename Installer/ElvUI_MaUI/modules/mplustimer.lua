local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G
local error, type = error, type

local PROFILE_NAME = "MaUI"

MaUI:RegisterModule({
	key = "mplustimer",
	order = 60,
	name = "MaUI M+ Timer",
	desc = L["Mythic+ timer matching the MaUI layout."],
	addon = "MauiMPlusTimer",
	IsSupported = function()
		return E.Retail and MaUI:GetData("mplustimer", "profile") ~= nil
	end,
	Apply = function()
		-- the timer has no public import API; its AceDB SavedVariables pick the profile up on the reload
		local db = _G.MauiMPlusTimerDB
		if type(db) ~= "table" then error(L["The M+ Timer settings are not loaded."]) end

		db.profiles = db.profiles or {}
		db.profileKeys = db.profileKeys or {}
		db.profiles[PROFILE_NAME] = Utils.CopyTable(MaUI:GetData("mplustimer", "profile"))
		db.profileKeys[E.mynameRealm] = PROFILE_NAME
	end,
})
