local MaUI, L, E = unpack(ElvUI_MaUI)

local _G = _G
local error, ipairs, tinsert, tremove = error, ipairs, tinsert, tremove
local C_EditMode = _G.C_EditMode

local LAYOUT_NAME = "MaUI"

-- the layout exported in this client, nil where MaUI has none
local function DataKey()
	return (E.Retail and "editmode") or (E.Forever and "editmode_forever") or nil
end

local function NumPresetLayouts()
	local manager = _G.EditModePresetLayoutManager
	return manager and #manager:GetCopyOfPresetLayouts() or 2
end

MaUI:RegisterModule({
	key = "blizzard",
	order = 30,
	name = L["Blizzard Edit Mode"],
	desc = L["Adds the MaUI Edit Mode layout for the frames ElvUI leaves to Blizzard."],
	icon = "Interface\\Icons\\INV_Misc_Wrench_01",
	-- each client has its own Edit Mode systems, a layout from another client breaks the anchors
	-- (QueueStatusButton: "anchor family connection" with the retail layout in Forever)
	IsSupported = function()
		local key = DataKey()
		return key and C_EditMode and C_EditMode.ConvertStringToLayoutInfo and MaUI:GetData("blizzard", key) ~= nil
	end,
	Apply = function()
		local info = C_EditMode.ConvertStringToLayoutInfo(MaUI:GetData("blizzard", DataKey()))
		if not info then error(L["The Edit Mode layout could not be read."]) end

		info.layoutName = LAYOUT_NAME
		info.layoutType = _G.Enum.EditModeLayoutType.Account

		local saved = C_EditMode.GetLayouts()
		local layouts = saved.layouts
		for i = #layouts, 1, -1 do
			if layouts[i].layoutName == LAYOUT_NAME then tremove(layouts, i) end
		end

		local accountLayouts = 0
		for _, layout in ipairs(layouts) do
			if layout.layoutType == info.layoutType then accountLayouts = accountLayouts + 1 end
		end

		local maxLayouts = _G.Constants and _G.Constants.EditModeConsts and _G.Constants.EditModeConsts.EditModeMaxLayoutsPerType
		if maxLayouts and accountLayouts >= maxLayouts then error(L["All Edit Mode layout slots are in use, delete one and run the installer again."]) end

		tinsert(layouts, info)
		C_EditMode.SaveLayouts(saved)
		C_EditMode.SetActiveLayout(NumPresetLayouts() + #layouts)
	end,
})
