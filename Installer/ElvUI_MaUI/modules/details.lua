local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G
local error = error

local PROFILE_NAME = "MaUI"

MaUI:RegisterModule({
	key = "details",
	order = 40,
	name = "Details!",
	desc = L["Damage meter windows in the MaUI style."],
	addon = "Details",
	IsSupported = function()
		return MaUI:GetData("details", "profile") ~= nil
	end,
	Apply = function()
		local Details = _G.Details
		local data = Utils.CopyTable(MaUI:GetData("details", "profile"))

		-- Details only imports strings, so the table goes through its own encoder first;
		-- builds without the Blizzard encoding ignore the last argument and fall back to LibDeflate
		local encoded = Details:CompressData(data, "print", true)
		if not Details:ImportProfile(encoded, PROFILE_NAME, false, false, true) then error(L["Details! rejected the profile."]) end
	end,
})
