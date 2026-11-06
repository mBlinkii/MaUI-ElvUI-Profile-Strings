local addonName, Engine = ...
local E = unpack(ElvUI)

local _G = _G
local GetAddOnMetadata = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata

local MaUI = {}
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

Engine[1] = MaUI
Engine[2] = L
Engine[3] = E
_G[addonName] = Engine

MaUI.AddonName = addonName
MaUI.Version = GetAddOnMetadata(addonName, "Version")
MaUI.ProfileVersion = GetAddOnMetadata(addonName, "X-MaUI-Profile")
MaUI.Title = "|CFF29C0E3M|r|CFF5493FFa|r|CFF854FE3U|r|CFFA632E3I|r"
MaUI.Discord = "https://discord.gg/ZScRCUyqjY"
MaUI.GitHub = "https://github.com/mBlinkii/MaUI-ElvUI-Profile-Strings"

-- the layouts were built for 2560x1440 at an ElvUI scale of 0.5333
MaUI.DesignHeight = 1440
MaUI.DesignScale = 0.5333333

local mediaPath = "Interface\\AddOns\\" .. addonName .. "\\media\\"
MaUI.Media = {
	logo = mediaPath .. "logo",
	icon = mediaPath .. "icon",
	discord = mediaPath .. "discord",
	github = mediaPath .. "github",
	pattern = mediaPath .. "pattern",
	circle = mediaPath .. "circle",
	ring = mediaPath .. "ring",
	pill = mediaPath .. "pill",
	arc = mediaPath .. "arc",
	check = mediaPath .. "check",
	cross = mediaPath .. "cross",
	arrow = mediaPath .. "arrow",
	update = mediaPath .. "update",
	glow = mediaPath .. "glow",
	fade = mediaPath .. "fade",
	white = "Interface\\Buttons\\WHITE8X8",
}

-- defaults until MaUI:ApplyTheme swaps in the MaUI profile's ElvUI colors and the class color
MaUI.Colors = {
	accentA = { 0.16, 0.75, 0.89 },
	accentB = { 0.65, 0.20, 0.89 },
	accent = { 0.33, 0.58, 1.00 },
	background = { 0.055, 0.058, 0.075 },
	sidebar = { 0.035, 0.037, 0.05 },
	surface = { 0.09, 0.094, 0.12 },
	surfaceHover = { 0.12, 0.125, 0.16 },
	border = { 0, 0, 0 },
	track = { 0.2, 0.2, 0.24 },
	onAccent = { 0.93, 0.94, 0.96 },
	text = { 0.93, 0.94, 0.96 },
	muted = { 0.58, 0.61, 0.68 },
	success = { 0.25, 0.85, 0.45 },
	warning = { 1.00, 0.72, 0.20 },
	danger = { 0.96, 0.32, 0.32 },
}

MaUI.Flavor = {
	retail = E.Retail,
	classic = not E.Retail,
}

function MaUI:Print(...)
	print(MaUI.Title .. ":", ...)
end
