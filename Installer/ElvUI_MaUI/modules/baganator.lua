local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G
local ipairs, pairs, tinsert, tonumber, tostring = ipairs, pairs, tinsert, tonumber, tostring
local gmatch, strfind, strsub, tconcat = string.gmatch, string.find, string.sub, table.concat
local C_EncodingUtil = _G.C_EncodingUtil

local PROFILE_NAME = "MaUI"

-- Baganator.API only takes strings, so the table is encoded the same way Baganator exports it
local function Encode(data)
	return "BGR!1!" .. C_EncodingUtil.EncodeBase64(C_EncodingUtil.CompressString(C_EncodingUtil.SerializeCBOR(data)))
end

-- game versions ------------------------------------------------------------------
-- The MaUI categories are built on Retail. Classic clients (Forever included) have no later expansions
-- and no Mythic+ season: the expansion and season conditions go and the categories built on them are dropped.
local CLASSIC_DROPPED = { ["Old"] = true, ["M+"] = true, ["Current"] = true, ["Delves"] = true, ["Hunt"] = true }

-- longest first, so "(a||b)" goes as a whole before its parts
local CLASSIC_CONDITIONS = {
	"&(#current expansion||#active season)",
	"&#current expansion",
	"#current expansion&",
	"&#active season",
	"#active season&",
}

local function StripConditions(search)
	for _, condition in ipairs(CLASSIC_CONDITIONS) do
		local first, last = strfind(search, condition, 1, true)
		while first do
			search = strsub(search, 1, first - 1) .. strsub(search, last + 1)
			first, last = strfind(search, condition, 1, true)
		end
	end

	-- "a&b||a&b" is left when both sides only differed in the expansion or season;
	-- a search with brackets keeps its "||" as they are, they may belong to a bracket
	if strfind(search, "(", 1, true) then return search end
	local parts, seen = {}, {}
	for part in gmatch(search .. "||", "(.-)||") do
		if not seen[part] then
			seen[part] = true
			tinsert(parts, part)
		end
	end
	return tconcat(parts, "||")
end

-- the category ids to drop and every other custom category's search adapted
local function AdaptCategories(categories)
	local dropped = {}
	for id, category in pairs(categories) do
		if CLASSIC_DROPPED[category.name] then
			dropped[tostring(id)] = true
		elseif category.search then
			category.search = StripConditions(category.search)
		end
	end
	return dropped
end

local function Without(list, dropped, field)
	local kept = {}
	for _, entry in ipairs(list) do
		if not dropped[tostring(field and entry[field] or entry)] then tinsert(kept, entry) end
	end
	return kept
end

local function ClassicData(data)
	if data.kind == "profile" then
		local dropped = AdaptCategories(data.custom_categories or {})
		for id in pairs(dropped) do
			for _, map in ipairs({ data.custom_categories, data.category_modifications, data.category_hidden }) do
				if map then map[id], map[tonumber(id)] = nil, nil end
			end
		end
		if data.category_display_order then data.category_display_order = Without(data.category_display_order, dropped) end
	else
		-- the categories export lists its categories with their id as `source`
		local byId = {}
		for _, category in ipairs(data.categories or {}) do
			byId[category.source] = category
		end
		local dropped = AdaptCategories(byId)
		data.categories = Without(data.categories or {}, dropped, "source")
		data.modifications = Without(data.modifications or {}, dropped, "source")
		if data.order then data.order = Without(data.order, dropped) end
		if data.hidden then
			for id in pairs(dropped) do
				data.hidden[id] = nil
			end
		end
	end
	return data
end

-- the data this game version gets, a copy so the registered data stays as it is
function MaUI:BaganatorData(kind)
	local data = Utils.CopyTable(self:GetData("baganator", kind) or self:GetData("baganator", "profile"))
	return E.Retail and data or ClassicData(data)
end

MaUI:RegisterModule({
	key = "baganator",
	order = 50,
	name = "Baganator",
	desc = L["Bag layout with the MaUI categories."],
	addon = "Baganator",
	choices = {
		{ "profile", L["Full profile"] },
		{ "categories", L["Categories only"] },
	},
	IsSupported = function()
		return C_EncodingUtil and C_EncodingUtil.SerializeCBOR and MaUI:GetData("baganator", "profile") ~= nil
	end,
	Apply = function(state)
		_G.Baganator.API.ImportString(Encode(MaUI:BaganatorData(state.choices.baganator)), PROFILE_NAME)
	end,
})
