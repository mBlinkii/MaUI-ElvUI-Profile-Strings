local MaUI, L, E = unpack(ElvUI_MaUI)

local _G = _G
local type, next = type, next
local strmatch = strmatch
local C_AddOns = _G.C_AddOns
local GetPhysicalScreenSize = GetPhysicalScreenSize

local Utils = {}
MaUI.Utils = Utils

if strmatch(MaUI.Version or "", "^@") then MaUI.Version = "dev" end

function Utils.CopyTable(src)
	if type(src) ~= "table" then return src end

	local copy = {}
	for k, v in next, src do
		copy[k] = Utils.CopyTable(v)
	end
	return copy
end

-- merges src into dst recursively, src wins on conflicts
function Utils.Merge(dst, src)
	for k, v in next, src do
		if type(v) == "table" and type(dst[k]) == "table" then
			Utils.Merge(dst[k], v)
		else
			dst[k] = Utils.CopyTable(v)
		end
	end
	return dst
end

-- tables kept in the SavedVariables are stored as compressed text and only unpacked when needed
function Utils.Pack(tbl)
	local codec = _G.C_EncodingUtil
	if not (codec and codec.SerializeCBOR) then return Utils.CopyTable(tbl) end
	return codec.EncodeBase64(codec.CompressString(codec.SerializeCBOR(tbl)))
end

function Utils.Unpack(value)
	if type(value) ~= "string" then return value end
	local codec = _G.C_EncodingUtil
	return codec.DeserializeCBOR(codec.DecompressString(codec.DecodeBase64(value)))
end

-- "loaded", "disabled" (installed but not loaded) or "missing"
function Utils.AddonState(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
	if isLoaded(name) then return "loaded" end

	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or _G.GetAddOnInfo
	local _, _, _, _, reason = getInfo(name)
	return reason == "MISSING" and "missing" or "disabled"
end

function Utils.AddonIcon(name)
	local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
	return getMetadata(name, "IconTexture") or getMetadata(name, "IconAtlas")
end

function Utils.ScreenHeight()
	local _, height = GetPhysicalScreenSize()
	return height
end

-- the scale that keeps the 1440p layout at the same size in UI units on this screen
function Utils.LayoutScale()
	return MaUI.DesignScale * Utils.ScreenHeight() / MaUI.DesignHeight
end

function Utils.Hex(color)
	return E:RGBToHex(color[1], color[2], color[3])
end

function Utils.Colorize(text, color)
	return Utils.Hex(color) .. text .. "|r"
end
