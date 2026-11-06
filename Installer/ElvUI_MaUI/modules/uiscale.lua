local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local floor = floor

function MaUI:IsDesignResolution()
	return Utils.ScreenHeight() == self.DesignHeight
end

-- "layout" keeps every frame where it was designed, "pixel" is sharp but needs manual adjusting below 1440p
function MaUI:GetTargetScale(mode)
	local scale = (self:IsDesignResolution() and self.DesignScale) or (mode == "pixel" and E:PixelBestSize()) or Utils.LayoutScale()
	return floor(scale * 10000 + 0.5) / 10000
end

MaUI:RegisterModule({
	key = "uiscale",
	order = 20,
	name = L["UI scale"],
	desc = L["Sets the ElvUI scale the layout was built for."],
	icon = MaUI.Media.icon,
	choices = {
		{ "layout", L["Keep layout"] },
		{ "pixel", L["Pixel perfect"] },
	},
	Apply = function(state)
		-- runs after the ElvUI step, the imported global settings must not bring back an old scale
		-- ElvUI applies the new scale on the reload that ends the installation
		E.global.general.UIScale = MaUI:GetTargetScale(state.choices.uiscale)
	end,
})
