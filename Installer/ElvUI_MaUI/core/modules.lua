local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils

local _G = _G
local format, ipairs, pcall, sort, tinsert, time = format, ipairs, pcall, sort, tinsert, time
local InCombatLockdown = InCombatLockdown
local UnitName = UnitName
local C_Timer = C_Timer

-- profile data, registered by the files of ElvUI_MaUI_Data
MaUI.Data = {}

function MaUI:RegisterData(module, key, data)
	self.Data[module] = self.Data[module] or {}
	self.Data[module][key] = data
end

-- the profile data is a LoadOnDemand addon, so it only takes memory once the installer needs it
local DATA_ADDON = MaUI.AddonName .. "_Data"

function MaUI:LoadData()
	if self.dataRequested then return end
	self.dataRequested = true

	local loadAddOn = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
	local loaded, reason = loadAddOn(DATA_ADDON)
	if not loaded and reason == "DISABLED" then
		local enableAddOn = _G.C_AddOns and _G.C_AddOns.EnableAddOn or _G.EnableAddOn
		enableAddOn(DATA_ADDON, UnitName("player"))
		loaded = loadAddOn(DATA_ADDON)
	end

	if not loaded then MaUI:Print(format(L["The profile data (%s) could not be loaded, is it installed?"], DATA_ADDON)) end
end

function MaUI:GetData(module, key)
	self:LoadData()
	local data = self.Data[module]
	return data and data[key]
end

--[[ A module is one installable part of MaUI:
	key, order        id and install order
	name, desc        display texts
	icon              texture, nil uses the icon from the addon's toc
	addon             addon folder the module needs, nil if none
	required          always installed, cannot be deselected
	IsSupported()     optional, false hides the module on this game client
	choices           optional list of { value, label } shown as a switch, first entry is the default
	default()         optional, false leaves the module unselected at first
	Contribute(profile, state)  optional, adds to the ElvUI profile before it is applied
	Apply(state)      does the work; errors are caught and shown per step
]]
MaUI.Modules = {}

function MaUI:RegisterModule(module)
	tinsert(self.Modules, module)
	sort(self.Modules, function(a, b)
		return a.order < b.order
	end)
end

function MaUI:GetModule(key)
	for _, module in ipairs(self.Modules) do
		if module.key == key then return module end
	end
end

function MaUI:IsSupported(module)
	return not module.IsSupported or module.IsSupported()
end

-- "loaded", "disabled" or "missing"
function MaUI:ModuleState(module)
	return module.addon and Utils.AddonState(module.addon) or "loaded"
end

function MaUI:IsAvailable(module)
	return self:IsSupported(module) and self:ModuleState(module) == "loaded"
end

-- what the user picked in the installer
-- existing: an ElvUI profile MaUI installed before, the character switches to it instead of a new install
-- update: bring that profile to the current MaUI data when it is outdated
-- advanced: only the selected ElvUI sections go into the current profile
-- panels: the data panels to keep, { bar = key of MaUI.PanelPresets, currency = boolean, cosmetic = boolean }
-- updating: the outdated MaUI profile the installer only updates, it then shows the update and done page
MaUI.State = { layout = "tankdd", cdm = false, advanced = false, sections = {}, modules = {}, choices = {}, update = true, panels = {} }

function MaUI:ResetState()
	local state, last = self.State, MaUIInstallerCharDB

	state.layout = last.layout or "tankdd"
	state.cdm = self:IsCDMSupported() and (last.cdm == nil or last.cdm)
	state.advanced = false
	state.updating = nil
	state.panels = { bar = "full", currency = true, cosmetic = true }
	state.update = true

	-- suggest the MaUI profile the character already uses, otherwise the newest on the account
	local current = E.data:GetCurrentProfile()
	local found = self:FindProfiles()
	state.existing = nil
	for _, profile in ipairs(found) do
		if profile.name == current then state.existing = current end
	end
	state.existing = state.existing or (found[1] and found[1].name)
	if state.existing then
		local layout, cdm = self:ProfileLayout(state.existing)
		if layout then state.layout, state.cdm = layout, cdm end
	end

	for _, section in ipairs(self.ProfileSections) do
		state.sections[section.key] = true
	end

	for _, module in ipairs(self.Modules) do
		state.modules[module.key] = self:IsAvailable(module) and (not module.default or module.default())
		state.choices[module.key] = module.choices and module.choices[1][1]
	end
end

function MaUI:IsSelected(module)
	return self:IsAvailable(module) and (module.required or self.State.modules[module.key])
end

function MaUI:GetSteps()
	local steps = {}
	for _, module in ipairs(self.Modules) do
		if self:IsSelected(module) then tinsert(steps, module) end
	end
	return steps
end

-- the ElvUI profile of the chosen layout, with everything the selected modules add to it
function MaUI:BuildProfile(state)
	local profile = Utils.CopyTable(self:GetData("elvui", "base"))
	Utils.Merge(profile, self:GetData("elvui", state.cdm and state.layout .. "_cdm" or state.layout))

	for _, module in ipairs(self:GetSteps()) do
		if module.Contribute then module.Contribute(profile, state) end
	end

	-- the data panels the user picked, then the datatexts this game version has
	self:ApplyPanelChoice(profile, state.panels)
	self:AdaptDatatexts(profile)
	return profile
end

-- runs the selected modules one after another; onStep(module, status, err) reports progress
function MaUI:Install(onStep, onDone)
	if InCombatLockdown() then
		MaUI:Print(L["The installation cannot run in combat."])
		return false
	end

	local steps, failed, index = self:GetSteps(), 0, 0

	local function NextStep()
		index = index + 1
		local module = steps[index]
		if not module then
			self:CompleteInstall()
			onDone(failed)
			return
		end

		onStep(module, "running")
		C_Timer.After(0.35, function()
			local ok, err = pcall(module.Apply, self.State)
			if not ok then
				failed = failed + 1
				MaUI:Print(module.name .. ":", err)
			end

			onStep(module, ok and "done" or "failed", err)
			C_Timer.After(0.15, NextStep)
		end)
	end

	NextStep()
	return true
end

function MaUI:CompleteInstall()
	local db = MaUIInstallerCharDB
	db.installed = self.ProfileVersion
	db.layout = self.State.layout
	db.cdm = self.State.cdm
	db.time = time()
	db.skipped = nil

	-- the same mark ElvUI's own E:SetupComplete sets, our installation covers its setup
	E.private.install_complete = E.version
	self:ReleaseElvUIInstaller()
end

function MaUI:IsCDMSupported()
	-- the same game versions mMT's cooldown manager runs on (Retail and Forever)
	return E.Modern and _G.EssentialCooldownViewer ~= nil and self:GetData("mmt", "cdm") ~= nil
end
