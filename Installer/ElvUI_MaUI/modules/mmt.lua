local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G

-- mMediaTag keeps its settings inside the ElvUI profile, so this module only adds to it
MaUI:RegisterModule({
	key = "mmt",
	order = 11,
	name = "mMediaTag & Tools",
	desc = L["Data panel skins and the Cooldown Manager setup."],
	addon = "ElvUI_mMediaTag",
	required = true,
	Contribute = function(profile, state)
		profile.mMediaTag = profile.mMediaTag or {}
		local mmt = profile.mMediaTag

		local panels = MaUI:GetData("mmt", "datapanels")
		if panels then
			mmt.data_panel_skin = mmt.data_panel_skin or {}
			mmt.data_panel_skin.panels = Utils.Merge(Utils.CopyTable(panels), mmt.data_panel_skin.panels or {})
		end

		-- the CDM export carries the per spell settings the layout itself does not; the layout wins on overlaps
		local cdm = state.cdm and MaUI:GetData("mmt", "cdm")
		if cdm then
			mmt.cooldown_manager = Utils.Merge(Utils.CopyTable(cdm.settings), mmt.cooldown_manager or {})
			profile.movers = Utils.Merge(Utils.CopyTable(cdm.movers), profile.movers or {})
		end
	end,
	Apply = function()
		local mMT = _G.ElvUI_mMediaTag and _G.ElvUI_mMediaTag[1]
		if mMT and mMT.UpdateModule then mMT:UpdateModule("DataPanelSkin") end
	end,
})
