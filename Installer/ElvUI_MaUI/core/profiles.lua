local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils
local D = E:GetModule("Distributor")

local _G = _G
local format, ipairs, next, pairs, sort, strfind, strlower, strmatch, time, tinsert, tonumber, type = format, ipairs, next, pairs, sort, strfind, strlower, strmatch, time, tinsert, tonumber, type

--[[ MaUIInstallerDB (account wide) remembers every ElvUI profile the installer created:
	profiles[name] = { layout, cdm, panels, version, revision, time, data }
	global = { revision, data }
	`data` is what MaUI wrote at that time (packed by Utils.Pack); an update compares it with the current MaUI data
	and only carries over what changed between the two, so the user's own edits stay.
]]

local function DB()
	_G.MaUIInstallerDB = _G.MaUIInstallerDB or {}
	local db = _G.MaUIInstallerDB
	db.profiles = db.profiles or {}
	return db
end

-- diff -------------------------------------------------------------------------

local function Equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in next, a do
		if not Equal(v, b[k]) then return false end
	end
	for k in next, b do
		if a[k] == nil then return false end
	end
	return true
end

-- carries the changes from `old` to `new` (two versions of MaUI's data) over to `target`, which the user
-- may have edited: new and changed values are set, removed values only go when the user left them alone.
-- `report(key, second, third)` hears about every change with the first three keys of its path,
-- e.g. "movers", "ElvAB_1" or "unitframe", "units", "player"
local function ApplyChanges(target, old, new, report, top, second, third)
	local changes = 0
	old = type(old) == "table" and old or {}

	for k, value in next, new do
		local first, next_, last = top or k, top and (second or k) or nil, second and (third or k) or nil
		if type(value) == "table" then
			-- a missing table (the user reset it to defaults) only gets what MaUI changed in it
			local sub = type(target[k]) == "table" and target[k] or {}
			local count = ApplyChanges(sub, old[k], value, report, first, next_, last)
			if count > 0 then target[k] = sub end
			changes = changes + count
		elseif value ~= old[k] and target[k] ~= value then
			target[k] = value
			changes = changes + 1
			if report then report(first, next_, last) end
		end
	end

	for k, value in next, old do
		if new[k] == nil and target[k] ~= nil and Equal(target[k], value) then
			target[k] = nil
			changes = changes + 1
			if report then report(top or k, top and (second or k) or nil, second and (third or k) or nil) end
		end
	end

	return changes
end
MaUI.ApplyChanges = ApplyChanges

-- registry -----------------------------------------------------------------------

-- MaUI's global ElvUI settings as this game version gets them
function MaUI:GlobalData()
	local global = self:GetData("elvui", "global")
	return global and self:AdaptPanels(E:FilterTableFromBlacklist(Utils.CopyTable(global), D.blacklistedKeys.global))
end

-- called after a full installation wrote `profile` (the complete MaUI profile) under `name`
function MaUI:RememberProfile(name, state, profile)
	local db = DB()
	db.profiles[name] = {
		layout = state.layout,
		cdm = state.cdm,
		panels = Utils.CopyTable(state.panels), -- updates keep the panels the user switched off
		version = self.ProfileVersion,
		revision = self.DataRevision,
		time = time(),
		data = Utils.Pack(profile),
	}
	db.global = { revision = self.DataRevision, data = Utils.Pack(self:GlobalData()) }
end

function MaUI:GetProfileInfo(name)
	return DB().profiles[name]
end

-- profiles imported by hand from older releases --------------------------------

-- releases before this one differ too much to be updated
local LEGACY_MAJOR = 8

local function RemovePaths(data, removed)
	for k, value in next, removed do
		if value == true then
			data[k] = nil
		elseif type(data[k]) == "table" then
			RemovePaths(data[k], value)
		end
	end
end

-- version, layout and CDM from names like "MaUI v8.5 Heal CDM", "MaUI v8 TANK/DD", "MaUI [v7] Tank-DD"
-- or "MaUI 8.5 Tank-DD" (early installer builds, before they kept track of their profiles)
function MaUI:ParseProfileName(name)
	local version = strmatch(name, "^MaUI %[?v?(%d+[%.%d]*)%]?")
	if not version then return end

	local layout = strfind(strlower(name), "heal") and "heal" or "tankdd"
	local cdm = strfind(name, "CDM") ~= nil
	return { version = version, major = tonumber(strmatch(version, "^%d+")), layout = layout, cdm = cdm, key = version .. "/" .. layout .. (cdm and "_cdm" or "") }
end

-- the profile an old release installed, rebuilt from the current layout and the difference convert.py stored
function MaUI:LegacyData(legacy)
	local delta = self:GetData("legacy", legacy.key)
	if not delta then return end

	local data = Utils.CopyTable(self:GetData("elvui", "base"))
	Utils.Merge(data, self:GetData("elvui", legacy.cdm and legacy.layout .. "_cdm" or legacy.layout))
	Utils.Merge(data, delta.set)
	RemovePaths(data, delta.removed)
	return data
end

-- status ---------------------------------------------------------------------------

--[[ "current"   installed by this installer with the current data
	"outdated"  an update is available: installed with older data, or imported by hand from v8 or later
	"old"       imported by hand from a release before v8, it can be used but not updated
	"unknown"   a MaUI profile with a name the installer does not recognize
]]
function MaUI:ProfileStatus(name)
	local info = self:GetProfileInfo(name)
	if info then return info.revision == self.DataRevision and "current" or "outdated" end

	local legacy = self:ParseProfileName(name)
	if not legacy then return "unknown" end
	if legacy.major < LEGACY_MAJOR then return "old" end
	-- the index knows which old releases have data, so the status never loads the data addon
	return self.LegacyKeys[legacy.key] and "outdated" or "unknown"
end

local STATUS_ORDER = { current = 1, outdated = 2, unknown = 3, old = 4 }

-- every MaUI profile of the account: installed ones newest first, then imported ones by version
function MaUI:FindProfiles()
	local found = {}
	for name in pairs(_G.ElvDB.profiles or {}) do
		local info = self:GetProfileInfo(name)
		if info or strfind(name, "^MaUI") then
			tinsert(found, { name = name, info = info, legacy = not info and self:ParseProfileName(name) or nil, status = self:ProfileStatus(name) })
		end
	end

	sort(found, function(a, b)
		if (a.info ~= nil) ~= (b.info ~= nil) then return a.info ~= nil end
		if a.info then
			if a.info.time ~= b.info.time then return (a.info.time or 0) > (b.info.time or 0) end
		elseif STATUS_ORDER[a.status] ~= STATUS_ORDER[b.status] then
			return STATUS_ORDER[a.status] < STATUS_ORDER[b.status]
		elseif a.legacy and b.legacy and a.legacy.version ~= b.legacy.version then
			return (tonumber(a.legacy.version) or 0) > (tonumber(b.legacy.version) or 0)
		end
		return a.name < b.name
	end)
	return found
end

-- whether FindProfiles would find anything, without building and sorting the list
function MaUI:HasProfiles()
	for name in pairs(_G.ElvDB.profiles or {}) do
		if self:GetProfileInfo(name) or strfind(name, "^MaUI") then return true end
	end
	return false
end

-- layout and CDM of any MaUI profile the installer can work with
function MaUI:ProfileLayout(name)
	local info = self:GetProfileInfo(name) or self:ParseProfileName(name)
	if info then return info.layout, info.cdm end
end

-- the outdated MaUI profile the character uses, if any
function MaUI:CurrentProfileUpdate()
	local name = E.data:GetCurrentProfile()
	return self:ProfileStatus(name) == "outdated" and name or nil
end

-- update -------------------------------------------------------------------------

-- what the profile looked like when MaUI wrote it: the stored copy, or for an old release the rebuilt data
local function UpdateSource(self, name)
	local info = self:GetProfileInfo(name)
	if info then return info, Utils.Unpack(info.data) end

	local legacy = self:ParseProfileName(name)
	local data = legacy and legacy.major >= LEGACY_MAJOR and self:LegacyData(legacy)
	if data then return { layout = legacy.layout, cdm = legacy.cdm, version = legacy.version }, data end
end

-- brings a MaUI profile (and the account's global settings) to the current MaUI data and returns the number
-- of changed settings; a preview only counts them on copies. `report(kind, key, second)` hears about each one
local function RunUpdate(self, name, preview, report)
	local info, old = UpdateSource(self, name)
	if not info then return 0 end

	local new = self:BuildProfile({ layout = info.layout, cdm = info.cdm, panels = info.panels })
	local changes, db = 0, DB()

	if db.global and db.global.revision ~= self.DataRevision then
		local global = self:GlobalData()
		local target = preview and Utils.CopyTable(_G.ElvDB.global) or _G.ElvDB.global
		changes = changes + ApplyChanges(target, Utils.Unpack(db.global.data), global, report and function(key, second, third)
			report("global", key, second, third)
		end)
		if not preview then db.global = { revision = self.DataRevision, data = Utils.Pack(global) } end
	end

	local target = Utils.CopyTable(_G.ElvDB.profiles[name] or {})
	changes = changes + ApplyChanges(target, old, new, report and function(key, second, third)
		report("profile", key, second, third)
	end)
	if preview then return changes end

	if E.data:GetCurrentProfile() == name then
		D:SetImportedProfile("profile", name, target, true)
	else
		_G.ElvDB.profiles[name] = target
	end

	-- an old release imported by hand is tracked like an installation from now on
	db.profiles[name] = info
	info.data, info.version, info.revision, info.time = Utils.Pack(new), self.ProfileVersion, self.DataRevision, time()
	return changes
end

function MaUI:UpdateProfile(name)
	return RunUpdate(self, name)
end

-- the ElvUI area (a key of MaUI.ProfileSections) a changed profile setting belongs to
local function SectionOf(self, key, second)
	if key == "movers" then return self:MoverSection(second or "") end
	for _, section in ipairs(self.ProfileSections) do
		for _, sectionKey in ipairs(section.profile) do
			if sectionKey == key then return section.key end
		end
	end
	return "general"
end

-- tables that only hold the real subjects, "unitframe.units.player" is about the player
local CONTAINERS = { units = true, panels = true, customPanels = true, viewers = true, bars = true }

-- the readable thing a change is about: the unit, bar, panel or mover ("ElvUF_PlayerMover" -> "ElvUF_Player")
local function SubjectOf(key, second, third)
	if key == "movers" then return second and (second:gsub("Mover$", "")) end
	if second and CONTAINERS[second] then return third end
	return second
end

-- what an update would change, per area and biggest first:
-- { { name = "Unit frames", count = 3, subjects = { "player", "target" } }, ... }, subjects by most changes
function MaUI:PreviewUpdate(name)
	local counts, subjects, names = {}, {}, { global = L["Global settings"] }
	for _, section in ipairs(self.ProfileSections) do
		names[section.key] = section.name
	end

	local total = RunUpdate(self, name, true, function(kind, key, second, third)
		local area = kind == "global" and "global" or SectionOf(self, key, second)
		counts[area] = (counts[area] or 0) + 1

		local subject = SubjectOf(key, second, third)
		if type(subject) == "string" then
			subjects[area] = subjects[area] or {}
			subjects[area][subject] = (subjects[area][subject] or 0) + 1
		end
	end)

	local list = {}
	for area, count in pairs(counts) do
		local byCount, ordered = subjects[area] or {}, {}
		for subject in pairs(byCount) do
			tinsert(ordered, subject)
		end
		sort(ordered, function(a, b)
			if byCount[a] ~= byCount[b] then return byCount[a] > byCount[b] end
			return a < b
		end)
		tinsert(list, { name = names[area] or area, count = count, subjects = ordered })
	end
	sort(list, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return list, total
end

-- the preview as text lines, "• Unit frames: 3 settings"
function MaUI:UpdateSummary(name, limit)
	local list, total = self:PreviewUpdate(name)
	local lines = {}
	for i, area in ipairs(list) do
		if i > (limit or #list) then
			tinsert(lines, format(L["and %d more areas"], #list - i + 1))
			break
		end
		tinsert(lines, format(L["%s: %d settings"], area.name, area.count))
	end
	return lines, total
end
