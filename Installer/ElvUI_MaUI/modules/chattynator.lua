local MaUI, L = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G
local C_EncodingUtil = _G.C_EncodingUtil

local PROFILE_NAME = "MaUI"

-- Chattynator.API only takes strings, so the table is encoded the same way Chattynator exports it
local function Encode(data)
	data.addon, data.version, data.kind = "Chattynator", 1, "profile"
	return "CHATTY!1!" .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(data)))
end

MaUI:RegisterModule({
	key = "chattynator",
	order = 55,
	name = "Chattynator",
	desc = L["Chat window with the MaUI tabs in the ElvUI style."],
	addon = "Chattynator",
	IsSupported = function()
		return C_EncodingUtil and C_EncodingUtil.SerializeCBOR and MaUI:GetData("chattynator", "profile") ~= nil
	end,
	Apply = function()
		-- a copy, the import takes the table over and the registered data has to stay as it is
		_G.Chattynator.API.ImportString(Encode(Utils.CopyTable(MaUI:GetData("chattynator", "profile"))), PROFILE_NAME)
	end,
})
