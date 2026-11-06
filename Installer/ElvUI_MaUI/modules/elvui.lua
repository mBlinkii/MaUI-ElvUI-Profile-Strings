local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils
local D = E:GetModule("Distributor")

local _G = _G
local format, ipairs, pairs, strfind, type = format, ipairs, pairs, strfind, type
local floor = math.floor

-- game versions ------------------------------------------------------------------
-- The MaUI panels are built on Retail. Datatexts another game version does not have get a replacement,
-- dock buttons it does not have (false) are dropped and their panel shrinks, so no slot stays empty.
local function MissingDatatexts()
	local missing = {}
	local vanilla = E.Classic or E.TBC

	if not E.Retail then missing["mMT - M+ Score"] = "mMT - Game menu" end
	if not (E.Retail or E.Mists) then
		-- Forever has no specialization datatext at all, its gear sets fit the slot best (friends are already in the dock)
		missing["Talent/Loot Specialization"] = E.Forever and "Equipment Sets" or "DualSpecialization"
	end
	if vanilla then
		missing.Difficulty = "mMT - Dungeon"
		missing.mMT_Dock_Achievement = false
		missing.mMT_Dock_CollectionsJournal = false
	end
	if vanilla or E.Forever then missing.mMT_Dock_EncounterJournal = false end

	return missing
end

-- swaps the datatexts this game version lacks; returns how many slots each panel lost
function MaUI:AdaptDatatexts(profile)
	local panels = profile.datatexts and profile.datatexts.panels
	local missing, removed = MissingDatatexts(), {}
	if not panels then return removed end

	for name, panel in pairs(panels) do
		if type(panel) == "table" then
			local last, dropped = 0, 0
			for key, datatext in pairs(panel) do
				if type(key) == "number" then
					last = key > last and key or last
					if missing[datatext] == false then dropped = dropped + 1 end
				end
			end

			if dropped == 0 then
				for i = 1, last do
					if missing[panel[i]] then panel[i] = missing[panel[i]] end
				end
			else
				-- the remaining slots move up, gaps stay gaps ("" is an empty slot)
				local slots = {}
				for i = 1, last do
					local datatext = panel[i]
					if missing[datatext] ~= false then slots[#slots + 1] = (datatext ~= nil and missing[datatext]) or datatext or "" end
				end
				for i = 1, last do
					panel[i] = slots[i]
				end
				removed[name] = dropped
			end
		end
	end

	return removed
end

-- data panels ----------------------------------------------------------------------
-- The installer lets the user pick which of MaUI's data panels to keep: the currency panel at the
-- top left and how much of the bar at the bottom of the screen. Panels left out are switched off.

local CURRENCY_PANEL = "mMT - CURRENCY"
-- the decorative bars above the action bars
local COSMETIC_PANELS = { "MAUI - COSMETICK LEFT", "MAUI - COSMETICK CENTER", "MAUI - COSMETICK RIGHT" }

-- the bar at the bottom of the screen from left to right, `x` is the stretch a panel covers in the
-- schematic the installer draws (0 = left screen edge, 1 = right edge)
MaUI.BottomPanels = {
	{ name = "mMT - LEFT", x = { 0, 0.24 } },
	{ name = "mMT - EXTRA LEFT", x = { 0.27, 0.45 } },
	{ name = "mMT - CENTER", x = { 0.47, 0.53 } },
	{ name = "mMT - EXTRA RIGHT", x = { 0.55, 0.73 } },
	{ name = "mMT - RIGHT", x = { 0.76, 1 } },
}

MaUI.PanelPresets = {
	{ key = "full", name = L["Full"], desc = L["Dock, information panels and clock."], panels = { "mMT - LEFT", "mMT - EXTRA LEFT", "mMT - CENTER", "mMT - EXTRA RIGHT", "mMT - RIGHT" } },
	{ key = "center", name = L["Center only"], desc = L["Information panels and clock in the middle."], panels = { "mMT - EXTRA LEFT", "mMT - CENTER", "mMT - EXTRA RIGHT" } },
	{ key = "dock", name = L["Dock only"], desc = L["Dock on the left, system and gold on the right."], panels = { "mMT - LEFT", "mMT - RIGHT" } },
	{ key = "none", name = L["None"], desc = L["No bar at the bottom of the screen."], panels = {} },
}

function MaUI:GetPanelPreset(key)
	for _, preset in ipairs(self.PanelPresets) do
		if preset.key == key then return preset end
	end
	return self.PanelPresets[1]
end

-- switches off the panels the user left out; `choice` = { bar = preset key, currency = boolean, cosmetic = boolean }
function MaUI:ApplyPanelChoice(profile, choice)
	local panels = profile.datatexts and profile.datatexts.panels
	if not (panels and choice) then return end

	local keep = {}
	for _, name in ipairs(self:GetPanelPreset(choice.bar).panels) do
		keep[name] = true
	end

	for _, panel in ipairs(self.BottomPanels) do
		if panels[panel.name] and not keep[panel.name] then panels[panel.name].enable = false end
	end
	if panels[CURRENCY_PANEL] and not choice.currency then panels[CURRENCY_PANEL].enable = false end
	if choice.cosmetic == false then
		for _, name in ipairs(COSMETIC_PANELS) do
			if panels[name] then panels[name].enable = false end
		end
	end
end

-- the panel definitions (global settings) lose the dropped slots, the remaining buttons keep their size
function MaUI:AdaptPanels(global)
	local base = self:GetData("elvui", "base")
	local removed = self:AdaptDatatexts({ datatexts = Utils.CopyTable(base.datatexts or {}) })
	local custom = global.datatexts and global.datatexts.customPanels

	for name, count in pairs(removed) do
		local panel = custom and custom[name]
		if panel and panel.numPoints then
			local points = panel.numPoints - count
			if panel.width then panel.width = floor(panel.width * points / panel.numPoints + 0.5) end
			panel.numPoints = points
		end
	end
	return global
end

MaUI.Layouts = {
	{
		key = "tankdd",
		profile = "Tank-DD",
		name = L["Tank / DPS"],
		desc = L["Compact player and target frames in the center, party and raid frames on the left."],
		roles = { "TANK", "DAMAGER" },
	},
	{
		key = "heal",
		profile = "Heal",
		name = L["Healer"],
		desc = L["Party and raid frames in the center of the screen, close to your spells."],
		roles = { "HEALER" },
	},
}

--[[ The parts of ElvUI the advanced mode installs one by one:
	profile, private, global   top level keys of the matching ElvUI settings
	movers                     patterns of the mover names that belong to the section;
	                           movers matching no section belong to "general"
]]
MaUI.ProfileSections = {
	{ key = "general", name = L["General"], desc = L["Fonts, colors, minimap, cooldown text, skins and all other frame positions."], profile = { "general", "cooldown" }, private = { "general", "skins" }, global = { "general" } },
	{ key = "actionbar", name = L["Action bars"], desc = L["Action, pet and stance bars, micro menu and extra buttons."], profile = { "actionbar", "convertPages" }, movers = { "^ElvAB_", "^PetAB$", "^ShiftAB$", "^BossButton$", "^ZoneAbility$", "^VehicleLeaveButton$", "^VehicleSeatMover$", "^MicrobarMover$", "^TotemTrackerMover$" } },
	{ key = "unitframe", name = L["Unit frames"], desc = L["Player, target, party, raid, boss and arena frames with their aura filters."], profile = { "unitframe" }, global = { "unitframe" }, movers = { "^ElvUF_", "^ClassBarMover$", "^AdditionalPowerMover$", "^AltPowerBarMover$", "^ArenaHeaderMover$", "^BossHeaderMover$" } },
	{ key = "nameplates", name = L["Nameplates"], desc = L["Nameplates with the MaUI filters and styles."], profile = { "nameplates" }, global = { "nameplates" }, movers = { "^ElvNP_" } },
	{ key = "auras", name = L["Auras"], desc = L["Buffs and debuffs at the minimap."], profile = { "auras" }, movers = { "^BuffsMover$", "^DebuffsMover$", "^PrivateAurasMover$" } },
	{ key = "bags", name = L["Bags"], desc = L["ElvUI's bags and bank."], profile = { "bags" }, private = { "bags" }, movers = { "^ElvUIBagMover$", "^ElvUIBankMover$" } },
	{ key = "chat", name = L["Chat"], desc = L["Chat panels, fonts and tabs styling."], profile = { "chat" }, movers = { "^LeftChatMover$", "^RightChatMover$" } },
	{ key = "datatexts", name = L["Data texts & bars"], desc = L["Data panels, the dock and the experience, reputation and honor bars."], profile = { "datatexts", "databars" }, global = { "datatexts" }, movers = { "^DTPanel", "^ExperienceBarMover$", "^ReputationBarMover$", "^HonorBarMover$", "^AzeriteBarMover$", "^ThreatBarMover$" } },
	{ key = "tooltip", name = L["Tooltip"], desc = L["Tooltip style and position."], profile = { "tooltip" }, movers = { "^TooltipMover$" } },
	{ key = "mmt", name = "mMediaTag", desc = L["Everything mMediaTag adds: dock, tags, icons, skins and the Cooldown Manager."], profile = { "mMediaTag" }, movers = { "^mMediaTag" } },
}

function MaUI:MoverSection(name)
	for _, section in ipairs(self.ProfileSections) do
		for _, pattern in ipairs(section.movers or {}) do
			if strfind(name, pattern) then return section.key end
		end
	end
	return "general"
end

function MaUI:GetLayout(key)
	for _, layout in ipairs(self.Layouts) do
		if layout.key == key then return layout end
	end
end

-- names carry no version, an update keeps the profile and its name
function MaUI:ProfileName(state)
	if state.existing then return state.existing end
	-- the advanced mode changes the profile the character already uses
	if state.advanced then return E.data:GetCurrentProfile() end
	return format("MaUI %s%s", self:GetLayout(state.layout).profile, state.cdm and " CDM" or "")
end

-- a copy of the private or global data, limited to the selected sections in the advanced mode
local function SelectedPart(data, field, state)
	if not state.advanced then return Utils.CopyTable(data) end

	local part = {}
	for _, section in ipairs(MaUI.ProfileSections) do
		if state.sections[section.key] then
			for _, key in ipairs(section[field] or {}) do
				part[key] = Utils.CopyTable(data[key])
			end
		end
	end
	return part
end

-- the current profile with the selected sections and their movers replaced by MaUI's
local function MergeSections(profile, state)
	local target = Utils.CopyTable(_G.ElvDB.profiles[E.data:GetCurrentProfile()] or {})
	local selected = state.sections

	-- a section MaUI leaves at ElvUI's defaults has no key, so it is cleared instead of kept
	for _, section in ipairs(MaUI.ProfileSections) do
		if selected[section.key] then
			for _, key in ipairs(section.profile) do
				target[key] = Utils.CopyTable(profile[key])
			end
		end
	end

	local movers = {}
	for name, point in pairs(target.movers or {}) do
		if not selected[MaUI:MoverSection(name)] then movers[name] = point end
	end
	for name, point in pairs(profile.movers or {}) do
		if selected[MaUI:MoverSection(name)] then movers[name] = point end
	end
	target.movers = movers

	return target
end

MaUI:RegisterModule({
	key = "elvui",
	order = 10,
	name = "ElvUI",
	desc = L["Profile, private and global settings."],
	addon = "ElvUI",
	required = true,
	Apply = function(state)
		if state.existing then
			-- the profile is already on the account; private settings are per character and still needed
			local private = MaUI:GetData("elvui", "private")
			if private then E:CopyTable(E.private, E:FilterTableFromBlacklist(Utils.CopyTable(private), D.blacklistedKeys.private)) end
			E.private.install_complete = E.version

			if state.update and MaUI:ProfileStatus(state.existing) == "outdated" then MaUI:UpdateProfile(state.existing) end
			if E.data:GetCurrentProfile() ~= state.existing then E.data:SetProfile(state.existing) end
			return
		end

		local global = MaUI:GlobalData()
		if global then
			E:CopyTable(E.global, E:FilterTableFromBlacklist(SelectedPart(global, "global", state), D.blacklistedKeys.global))

			-- ElvUI only builds custom data panels on load; until then mMediaTag drops the skins of
			-- panels it cannot find when the profile switch below refreshes it
			local DT = E:GetModule("DataTexts")
			for name in pairs(E.global.datatexts.customPanels) do
				if not DT.RegisteredPanels[name] then DT:BuildPanelFrame(name) end
			end
		end

		local private = MaUI:GetData("elvui", "private")
		if private then
			-- merged into the character's private profile, so settings MaUI does not touch are kept
			E:CopyTable(E.private, E:FilterTableFromBlacklist(SelectedPart(private, "private", state), D.blacklistedKeys.private))
		end
		E.private.install_complete = E.version

		local profile = MaUI:BuildProfile(state)
		if state.advanced then
			D:SetImportedProfile("profile", MaUI:ProfileName(state), MergeSections(profile, state), true)
		else
			D:SetImportedProfile("profile", MaUI:ProfileName(state), profile, true)
			MaUI:RememberProfile(MaUI:ProfileName(state), state, profile)
		end
	end,
})
