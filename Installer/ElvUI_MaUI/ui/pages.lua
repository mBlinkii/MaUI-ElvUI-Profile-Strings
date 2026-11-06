local MaUI, L, E = unpack(ElvUI_MaUI)
local W = MaUI.Widgets
local Utils = MaUI.Utils

local _G = _G
local date, format, ipairs, next, tinsert, tostring, unpack = date, format, ipairs, next, tinsert, tostring, unpack
local floor = math.floor
local GetPhysicalScreenSize = GetPhysicalScreenSize
local InCombatLockdown = InCombatLockdown
local pcall = pcall

local C = MaUI.Colors
local Media = MaUI.Media
local Pages = MaUI.Pages
local Installer = MaUI.Installer
local State = MaUI.State

local PAGE_WIDTH = 650

local function AddPage(page)
	tinsert(Pages, page)
end

-- a text line with a check in front, placed below anchor; returns the icon as the next anchor
local function CheckLine(parent, anchor, text)
	local icon = W.Texture(parent, Media.check, "ARTWORK", C.accent)
	icon:SetSize(16, 16)
	icon:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)

	local label = W.Text(parent, 13, C.text)
	label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
	label:SetWidth(parent:GetWidth() - 26)
	label:SetText(text)
	return icon
end

-- a full width row with a title, a description and a toggle; positioned by the page
local function OptionRow(parent, title, desc, onChange)
	local row = W.Panel(parent, C.surface, C.border, 0.85)
	row:SetSize(PAGE_WIDTH, 66)

	local titleText = W.Text(row, 14, C.text, true)
	titleText:SetPoint("TOPLEFT", 18, -14)
	titleText:SetText(title)

	local descText = W.Text(row, 12, C.muted)
	descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -6)
	descText:SetWidth(PAGE_WIDTH - 120)
	descText:SetText(desc)
	row.desc = descText

	row.toggle = W.Toggle(row, onChange)
	row.toggle:SetPoint("RIGHT", -18, 0)
	return row
end

local function SectionTitle(parent, text)
	local title = W.Text(parent, 11, C.muted, true)
	title:SetText(text)
	return title
end

-- shared by the setup and addons page ---------------------------------------

local ADDON_STATUS = {
	required = { L["Required"], C.accent },
	loaded = { L["Found"], C.success },
	disabled = { L["Disabled"], C.warning },
	missing = { L["Not installed"], C.muted },
	recommended = { L["Recommended"], C.accent },
	optional = { L["Optional"], C.muted },
}

local ADDON_PAGE_MODULES = { "elvui", "mmt", "blizzard", "details", "baganator", "mplustimer" }

local function CreateAddonCard(parent, module, width)
	local card = W.Panel(parent, C.surface, C.border, 0.85)
	card:SetSize(width, 112)
	card.module = module

	card.icon = W.Icon(card, 36, module.icon or Utils.AddonIcon(module.addon))
	card.icon:SetPoint("TOPLEFT", 14, -14)

	card.name = W.Text(card, 14, C.text, true)
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, -2)
	card.name:SetText(module.name)

	card.pill = W.Pill(card)
	card.pill:SetPoint("TOPRIGHT", -14, -14)

	card.desc = W.Text(card, 11, C.muted)
	card.desc:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -5)
	card.desc:SetPoint("RIGHT", card, "RIGHT", -14, 0)
	card.desc:SetHeight(28)
	card.desc:SetJustifyV("TOP")
	card.desc:SetText(module.desc)

	card.toggle = W.Toggle(card, function(checked)
		State.modules[module.key] = checked
		Installer:Refresh()
	end)
	card.toggle:SetPoint("BOTTOMLEFT", 14, 14)

	card.toggleLabel = W.Text(card, 12, C.muted, true)
	card.toggleLabel:SetPoint("LEFT", card.toggle, "RIGHT", 10, 0)

	if module.choices then
		card.choice = W.Segmented(card, module.choices, 190, function(value)
			State.choices[module.key] = value
		end)
		card.choice:SetPoint("BOTTOMRIGHT", -14, 11)
	end

	return card
end

local function RefreshAddonCard(card)
	local module = card.module
	local state = MaUI:ModuleState(module)
	local available = state == "loaded"
	local selected = MaUI:IsSelected(module)

	local status = (module.required and available and "required")
		or (not module.addon and (module.default and module.default() and "recommended" or "optional"))
		or state
	card.pill:SetStatus(unpack(ADDON_STATUS[status]))
	card.toggle:SetChecked(selected, true)
	card.toggle:SetEnabled(available)
	card.toggle:SetLocked(available and module.required)
	card.toggleLabel:SetText((module.required and available and L["Always installed"]) or (selected and L["Install"]) or (available and L["Skip"]) or L["Not available"])
	card.toggleLabel:SetTextColor(unpack(selected and C.text or C.muted))
	card:SetAlpha(available and 1 or 0.55)

	-- the choice takes the label's place, there is no room for both
	if card.choice then
		card.choice:SetShown(selected)
		card.choice:SetValue(State.choices[module.key], true)
		card.toggleLabel:SetShown(not selected)
	end
end

-- 1. welcome -----------------------------------------------------------------

local SYSTEM_STATUS = {
	ok = { L["Ready"], C.success },
	warn = { L["Check"], C.warning },
	missing = { L["Missing"], C.danger },
}

AddPage({
	nav = L["Welcome"],
	title = L["Welcome to MaUI"],
	subtitle = L["This installer sets up the complete MaUI interface for ElvUI: the layout for your role, the matching addon profiles and the right scale. It only takes a minute."],
	Build = function(_, frame)
		local features = W.Box(frame)
		features:SetPoint("TOPLEFT")
		features:SetSize(300, 300)

		local title = SectionTitle(features, L["WHAT YOU GET"])
		title:SetPoint("TOPLEFT")

		local anchor = title
		for _, text in ipairs({
			L["Layouts for tanks, damage dealers and healers"],
			L["Dock bar, profession menu and currency overview"],
			L["Mythic+ highlighting of important enemies"],
			L["Cooldown Manager styling by mMediaTag"],
			L["Matching profiles for your other addons"],
			L["Everything installable again with one click"],
		}) do
			anchor = CheckLine(features, anchor, text)
		end

		-- system check on the right
		local panel = W.Panel(frame, C.surface, C.border, 0.85)
		panel:SetPoint("TOPRIGHT")
		panel:SetSize(300, 236)

		local panelTitle = SectionTitle(panel, L["SYSTEM CHECK"])
		panelTitle:SetPoint("TOPLEFT", 18, -18)

		frame.checks = {}
		for i, key in ipairs({ "elvui", "mmt", "resolution", "client" }) do
			local row = W.Box(panel)
			row:SetSize(264, 40)
			row:SetPoint("TOPLEFT", 18, -44 - (i - 1) * 44)

			row.label = W.Text(row, 13, C.text, true)
			row.label:SetPoint("TOPLEFT", 0, -4)
			row.detail = W.Text(row, 11, C.muted)
			row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
			row.pill = W.Pill(row)
			row.pill:SetPoint("RIGHT", 0, 0)

			frame.checks[key] = row
		end

		frame.installed = W.Text(frame, 12, C.muted)
		frame.installed:SetPoint("BOTTOMLEFT", 0, 6)
		frame.installed:SetWidth(PAGE_WIDTH)
	end,
	Refresh = function(_, frame)
		local function Set(key, label, detail, status)
			local row = frame.checks[key]
			row.label:SetText(label)
			row.detail:SetText(detail)
			row.pill:SetStatus(unpack(SYSTEM_STATUS[status]))
		end

		Set("elvui", "ElvUI", format(L["Version %s"], E.version), "ok")

		local mmtState = Utils.AddonState("ElvUI_mMediaTag")
		Set("mmt", "mMediaTag & Tools", mmtState == "loaded" and L["Loaded"] or L["Required for MaUI"], mmtState == "loaded" and "ok" or "missing")

		local width, height = GetPhysicalScreenSize()
		local resolution = format("%d x %d", width, height)
		if MaUI:IsDesignResolution() then
			Set("resolution", L["Resolution"], resolution, "ok")
		else
			Set("resolution", L["Resolution"], format(L["%s, built for 1440p"], resolution), "warn")
		end

		Set("client", L["Game version"], E.Retail and L["Retail"] or L["Classic"], "ok")

		local db, update = MaUIInstallerCharDB, MaUI:CurrentProfileUpdate()
		if update then
			frame.installed:SetText(Utils.Colorize(format(L["An update is available for your profile \"%s\"."], update), C.warning))
		elseif db.installed then
			frame.installed:SetText(format(L["MaUI %s was installed on this character on %s."], db.installed, date("%d.%m.%Y", db.time or 0)))
		else
			frame.installed:SetText("")
		end
	end,
	NextLabel = function()
		return L["Let's go"]
	end,
})

-- 2. ElvUI setup ---------------------------------------------------------------

AddPage({
	nav = L["ElvUI setup"],
	title = L["ElvUI basic setup"],
	subtitle = L["The game settings and chat setup from ElvUI's own installer. MaUI runs them for you, so you do not need ElvUI's installer anymore."],
	Build = function(_, frame)
		frame.cards = {}
		for i, key in ipairs({ "cvars", "chat" }) do
			local card = CreateAddonCard(frame, MaUI:GetModule(key), PAGE_WIDTH)
			card:SetPoint("TOPLEFT", 0, -(i - 1) * 124)
			frame.cards[i] = card
		end

		frame.notice = W.Panel(frame, C.accent, C.accent, 0.08)
		frame.notice:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.5)
		frame.notice:SetPoint("TOPLEFT", 0, -258)
		frame.notice:SetSize(PAGE_WIDTH, 72)

		frame.noticeText = W.Text(frame.notice, 12, C.text)
		frame.noticeText:SetPoint("LEFT", 18, 0)
		frame.noticeText:SetWidth(PAGE_WIDTH - 36)
		frame.noticeText:SetSpacing(3)
	end,
	Refresh = function(_, frame)
		for _, card in ipairs(frame.cards) do
			RefreshAddonCard(card)
		end

		frame.noticeText:SetText(MaUI.ElvUIFresh and L["ElvUI was never set up on this character, so both steps are selected. They replace pages 2 and 3 of ElvUI's installer."]
			or L["ElvUI is already set up on this character. Only select these steps if you want to reset your game settings or chat windows."])
	end,
})

-- 3. existing profiles --------------------------------------------------------

local PROFILE_STATUS = {
	current = { L["Up to date"], C.success },
	outdated = { L["Update available"], C.warning },
	old = { L["Too old for updates"], C.danger },
	unknown = { L["Unknown"], C.muted },
}

local MAX_PROFILES = 6

local function SelectProfile(name)
	State.existing = name
	if name then
		local layout, cdm = MaUI:ProfileLayout(name)
		if layout then State.layout, State.cdm = layout, cdm end
	end
	Installer:Refresh()
end

-- "What changes (52 settings): Unit frames: 40 settings · Action bars: 12 settings"; the dry run of the update
-- is worked out once per profile, Refresh runs on every click
local summaries = {}

local function UpdateSummaryText(name)
	if not summaries[name] then
		local lines, total = MaUI:UpdateSummary(name, 3)
		summaries[name] = total > 0
			and (Utils.Colorize(format(L["What changes (%d settings):"], total), C.text) .. "  " .. table.concat(lines, "  ·  "))
			or ""
	end
	return summaries[name]
end

-- "Healer + CDM · v8.5 · installed on 01.11.2026"
local function ProfileDetail(profile)
	local source = profile.info or profile.legacy
	if not source then return L["Name not recognized, it cannot be updated."] end

	local layout = MaUI:GetLayout(source.layout)
	local text = (layout and layout.name or "?") .. (source.cdm and " + CDM" or "")
	if profile.info then
		return format(L["%s · v%s · installed on %s"], text, source.version or "?", date("%d.%m.%Y", source.time or 0))
	end
	return format(L["%s · v%s · imported by hand"], text, source.version)
end

AddPage({
	nav = L["Profile"],
	title = L["Existing MaUI profiles"],
	subtitle = L["Your account already has MaUI profiles. Pick one to use it on this character, or install a new one."],
	IsShown = function()
		return MaUI:HasProfiles()
	end,
	Build = function(_, frame)
		frame.rows = {}
		for i = 1, MAX_PROFILES + 1 do
			local row = W.Card(frame, PAGE_WIDTH, 40, function(self)
				SelectProfile(self.profileName)
			end)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
			row.badge:SetSize(18, 18)
			row.badge:ClearAllPoints()
			row.badge:SetPoint("RIGHT", -12, 0)
			row.badgeIcon:SetSize(13, 13)

			row.name = W.Text(row, 13, C.text, true)
			row.name:SetPoint("TOPLEFT", 14, -6)
			row.detail = W.Text(row, 10, C.muted)
			row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
			row.pill = W.Pill(row)
			row.pill:SetPoint("RIGHT", -40, 0)

			frame.rows[i] = row
		end

		frame.updateOption = OptionRow(frame, L["Update the profile"], L["Only the settings MaUI changed are carried over, your own changes stay."], function(checked)
			State.update = checked
		end)
		frame.updateOption:SetPoint("BOTTOMLEFT")
		-- one more line for the preview; with all profile rows shown it still clears the last one
		frame.updateOption:SetHeight(82)

		frame.updateSummary = W.Text(frame.updateOption, 12, C.muted)
		frame.updateSummary:SetPoint("TOPLEFT", frame.updateOption.desc, "BOTTOMLEFT", 0, -6)
		frame.updateSummary:SetWidth(PAGE_WIDTH - 120)
		frame.updateSummary:SetWordWrap(false)
	end,
	Refresh = function(_, frame)
		local found = MaUI:FindProfiles()
		local current = E.data:GetCurrentProfile()
		local newRow = math.min(#found, MAX_PROFILES) + 1

		for i, row in ipairs(frame.rows) do
			local profile = i < newRow and found[i]
			row:SetShown(profile or i == newRow)

			if i == newRow then
				row.profileName = nil
				row.name:SetText(L["Install new"])
				row.detail:SetText(L["Create a new MaUI profile and choose its layout."])
				row.pill:Hide()
			elseif profile then
				row.profileName = profile.name
				row.name:SetText(profile.name .. (profile.name == current and ("  " .. Utils.Colorize(L["(in use)"], C.muted)) or ""))
				row.detail:SetText(ProfileDetail(profile))
				row.pill:Show()
				row.pill:SetStatus(unpack(PROFILE_STATUS[profile.status]))
			end

			row:SetSelected(row:IsShown() and row.profileName == State.existing)
		end

		local outdated = State.existing ~= nil and MaUI:ProfileStatus(State.existing) == "outdated"
		frame.updateOption:SetShown(outdated)
		if outdated then frame.updateSummary:SetText(UpdateSummaryText(State.existing)) end
		frame.updateOption.toggle:SetChecked(State.update, true)
	end,
})

-- 4. layout ------------------------------------------------------------------

AddPage({
	nav = L["Layout"],
	IsShown = function()
		return not State.existing
	end,
	title = L["Choose your layout"],
	subtitle = L["Both layouts share the same look and only differ in where your unit frames sit. You can switch at any time by running the installer again."],
	Build = function(_, frame)
		frame.cards = {}
		local width = (PAGE_WIDTH - 20) / 2

		for i, layout in ipairs(MaUI.Layouts) do
			local card = W.Card(frame, width, 220, function()
				State.layout = layout.key
				Installer:Refresh()
			end)
			card:SetPoint("TOPLEFT", (i - 1) * (width + 20), 0)
			card.key = layout.key

			for j, role in ipairs(layout.roles) do
				-- the mMediaTag role icons the profile itself uses
				local file, coords = W.RoleIcon(role)
				local icon = W.Texture(card, file, "ARTWORK")
				if coords then icon:SetTexCoord(unpack(coords)) end
				icon:SetSize(54, 54)
				icon:SetPoint("TOP", (j - (#layout.roles + 1) / 2) * 62, -30)
			end

			local name = W.Text(card, 20, C.text, true)
			name:SetPoint("TOP", 0, -104)
			name:SetJustifyH("CENTER")
			name:SetText(layout.name)

			local desc = W.Text(card, 12, C.muted)
			desc:SetPoint("TOP", name, "BOTTOM", 0, -12)
			desc:SetWidth(width - 50)
			desc:SetJustifyH("CENTER")
			desc:SetSpacing(3)
			desc:SetText(layout.desc)

			frame.cards[i] = card
		end

		-- Cooldown Manager variant, retail only
		frame.cdmOption = OptionRow(frame, L["Cooldown Manager layout"], L["Moves your frames for Blizzard's Cooldown Manager, styled by mMediaTag."], function(checked)
			State.cdm = checked
		end)

		frame.advancedOption = OptionRow(frame, L["Advanced mode"], L["Pick single parts of ElvUI, e.g. only the nameplates, and copy them into your current profile."], function(checked)
			State.advanced = checked
			Installer:Refresh()
		end)
	end,
	Refresh = function(_, frame)
		for _, card in ipairs(frame.cards) do
			card:SetSelected(card.key == State.layout)
		end

		local cdm = MaUI:IsCDMSupported()
		frame.cdmOption:SetShown(cdm)
		frame.cdmOption:SetPoint("TOPLEFT", 0, -234)
		frame.cdmOption.toggle:SetChecked(State.cdm, true)

		frame.advancedOption:SetPoint("TOPLEFT", 0, cdm and -310 or -234)
		frame.advancedOption.toggle:SetChecked(State.advanced, true)
	end,
})

-- 5. ElvUI sections (advanced mode) -------------------------------------------

AddPage({
	nav = L["ElvUI modules"],
	title = L["ElvUI modules"],
	subtitle = function()
		return format(L["The selected parts and their frame positions are copied into your current ElvUI profile \"%s\". Everything else in it stays as it is."], E.data:GetCurrentProfile())
	end,
	IsShown = function()
		return State.advanced and not State.existing
	end,
	Build = function(_, frame)
		frame.cards = {}
		local width = (PAGE_WIDTH - 12) / 2

		for i, section in ipairs(MaUI.ProfileSections) do
			local card = W.Panel(frame, C.surface, C.border, 0.85)
			card:SetSize(width, 64)
			card:SetPoint("TOPLEFT", ((i - 1) % 2) * (width + 12), -floor((i - 1) / 2) * 72)

			card.toggle = W.Toggle(card, function(checked)
				State.sections[section.key] = checked
				Installer:Refresh()
			end)
			card.toggle:SetPoint("LEFT", 14, 0)

			local name = W.Text(card, 13, C.text, true)
			name:SetPoint("TOPLEFT", 66, -12)
			name:SetText(section.name)

			local desc = W.Text(card, 11, C.muted)
			desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
			desc:SetWidth(width - 80)
			desc:SetText(section.desc)

			card.key = section.key
			frame.cards[i] = card
		end
	end,
	Refresh = function(_, frame)
		for _, card in ipairs(frame.cards) do
			card.toggle:SetChecked(State.sections[card.key], true)
		end
	end,
	CanNext = function()
		for _, selected in next, State.sections do
			if selected then return true end
		end
	end,
})

-- 6. data panels -------------------------------------------------------------

-- a small drawing of the screen: the bar at the bottom, the currency panel and the decorative bars
local SCREEN_W, SCREEN_H = 127, 60
local COSMETIC_X = { { 0.29, 0.40 }, { 0.42, 0.58 }, { 0.60, 0.71 } }

local function Schematic(card)
	local screen = W.Texture(card, nil, "ARTWORK", C.sidebar)
	screen:SetSize(SCREEN_W, SCREEN_H)
	screen:SetPoint("TOP", 0, -14)

	local inner = SCREEN_W - 8
	local function Part(x, y, width, height)
		local part = W.Texture(card, nil, "OVERLAY")
		part:SetSize(width, height)
		part:SetPoint("BOTTOMLEFT", screen, "BOTTOMLEFT", 4 + x * inner, y)
		return part
	end

	card.bottom = {}
	for i, panel in ipairs(MaUI.BottomPanels) do
		card.bottom[i] = Part(panel.x[1], 4, (panel.x[2] - panel.x[1]) * inner, 4)
	end
	card.cosmetic = {}
	for i, x in ipairs(COSMETIC_X) do
		card.cosmetic[i] = Part(x[1], 16, (x[2] - x[1]) * inner, 2)
	end
	card.currency = Part(0, SCREEN_H - 24, 10, 20)
end

local function Paint(texture, active)
	texture:SetVertexColor(active and C.accent[1] or C.track[1], active and C.accent[2] or C.track[2], active and C.accent[3] or C.track[3], active and 1 or 0.6)
end

AddPage({
	nav = L["Data panels"],
	title = L["Data panels"],
	subtitle = L["Choose which of MaUI's data panels you want. Panels you leave out are only switched off and can be turned on again in ElvUI."],
	IsShown = function()
		return not State.existing and not State.advanced
	end,
	Build = function(_, frame)
		frame.currency = OptionRow(frame, L["Currency panel"], L["Your most important currencies at the top left of the screen."], function(checked)
			State.panels.currency = checked
			Installer:Refresh()
		end)
		frame.currency:SetPoint("TOPLEFT")

		frame.cosmetic = OptionRow(frame, L["Decorative bars"], L["The thin bars above the action bars."], function(checked)
			State.panels.cosmetic = checked
			Installer:Refresh()
		end)
		frame.cosmetic:SetPoint("TOPLEFT", 0, -74)

		local title = SectionTitle(frame, L["BAR AT THE BOTTOM"])
		title:SetPoint("TOPLEFT", 0, -154)

		frame.cards = {}
		local width = (PAGE_WIDTH - 30) / 4
		for i, preset in ipairs(MaUI.PanelPresets) do
			local card = W.Card(frame, width, 150, function()
				State.panels.bar = preset.key
				Installer:Refresh()
			end)
			card:SetPoint("TOPLEFT", (i - 1) * (width + 10), -172)
			card.preset = preset
			card.badge:SetSize(18, 18)
			card.badgeIcon:SetSize(13, 13)

			Schematic(card)

			local name = W.Text(card, 14, C.text, true)
			name:SetPoint("TOP", 0, -84)
			name:SetJustifyH("CENTER")
			name:SetText(preset.name)

			local desc = W.Text(card, 11, C.muted)
			desc:SetPoint("TOP", name, "BOTTOM", 0, -6)
			desc:SetWidth(width - 20)
			desc:SetJustifyH("CENTER")
			desc:SetText(preset.desc)

			frame.cards[i] = card
		end
	end,
	Refresh = function(_, frame)
		local choice = State.panels
		frame.currency.toggle:SetChecked(choice.currency, true)
		frame.cosmetic.toggle:SetChecked(choice.cosmetic, true)

		for _, card in ipairs(frame.cards) do
			card:SetSelected(card.preset.key == choice.bar)

			local keep = {}
			for _, name in ipairs(card.preset.panels) do
				keep[name] = true
			end
			for i, panel in ipairs(MaUI.BottomPanels) do
				Paint(card.bottom[i], keep[panel.name])
			end
			for _, part in ipairs(card.cosmetic) do
				Paint(part, choice.cosmetic)
			end
			Paint(card.currency, choice.currency)
		end
	end,
})

-- 7. addons ------------------------------------------------------------------

AddPage({
	nav = L["Addons"],
	title = L["Addon profiles"],
	subtitle = L["MaUI brings profiles for these addons. Everything that is installed and enabled is selected automatically."],
	Build = function(_, frame)
		frame.cards = {}
		local width = (PAGE_WIDTH - 14) / 2

		local index = 0
		for _, key in ipairs(ADDON_PAGE_MODULES) do
			local module = MaUI:GetModule(key)
			if module and MaUI:IsSupported(module) then
				local card = CreateAddonCard(frame, module, width)
				card:SetPoint("TOPLEFT", (index % 2) * (width + 14), -floor(index / 2) * 124)
				tinsert(frame.cards, card)
				index = index + 1
			end
		end
	end,
	Refresh = function(_, frame)
		for _, card in ipairs(frame.cards) do
			RefreshAddonCard(card)
		end
	end,
})

-- 8. scale -------------------------------------------------------------------

local function ScaleValue(parent, label)
	local value = W.Text(parent, 30, C.text, true)
	local caption = W.Text(parent, 11, C.muted, true)
	caption:SetText(label)
	caption:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -6)
	return value
end

AddPage({
	nav = L["Scale"],
	title = L["UI scale"],
	subtitle = L["MaUI is built for 2560 x 1440 at an ElvUI scale of 0.5333. On other resolutions the installer adjusts the scale so the layout keeps its proportions."],
	Build = function(_, frame)
		local panel = W.Panel(frame, C.surface, C.border, 0.85)
		panel:SetPoint("TOPLEFT")
		panel:SetSize(PAGE_WIDTH, 128)

		frame.resolution = ScaleValue(panel, L["YOUR RESOLUTION"])
		frame.resolution:SetPoint("TOPLEFT", 24, -28)

		local arrow = W.Texture(panel, Media.arrow, "ARTWORK", C.accent)
		arrow:SetSize(28, 28)
		arrow:SetPoint("TOP", 0, -32)

		frame.scale = ScaleValue(panel, L["ELVUI SCALE"])
		frame.scale:SetPoint("TOPLEFT", PAGE_WIDTH / 2 + 50, -28)

		frame.notice = W.Panel(frame, C.warning, C.warning, 0.08)
		frame.notice:SetBackdropBorderColor(C.warning[1], C.warning[2], C.warning[3], 0.5)
		frame.notice:SetPoint("TOPLEFT", 0, -144)
		frame.notice:SetSize(PAGE_WIDTH, 112)

		local noticeTitle = W.Text(frame.notice, 14, C.warning, true)
		noticeTitle:SetPoint("TOPLEFT", 18, -16)
		noticeTitle:SetText(L["Different resolution"])

		local noticeText = W.Text(frame.notice, 12, C.text)
		noticeText:SetPoint("TOPLEFT", noticeTitle, "BOTTOMLEFT", 0, -6)
		noticeText:SetWidth(PAGE_WIDTH - 36)
		noticeText:SetSpacing(3)
		noticeText:SetText(L["Keep layout scales everything so it looks exactly like on 1440p. Pixel perfect is sharper, but some frames have to be moved by hand afterwards."])

		frame.mode = W.Segmented(frame.notice, MaUI:GetModule("uiscale").choices, 260, function(value)
			State.choices.uiscale = value
			Installer:Refresh()
		end)
		frame.mode:SetPoint("BOTTOMLEFT", 18, 14)

		local option = W.Panel(frame, C.surface, C.border, 0.85)
		option:SetPoint("BOTTOMLEFT", 0, 0)
		option:SetSize(PAGE_WIDTH, 58)

		local optionText = W.Text(option, 14, C.text, true)
		optionText:SetPoint("LEFT", 18, 0)
		optionText:SetText(L["Set the UI scale during installation"])

		frame.toggle = W.Toggle(option, function(checked)
			State.modules.uiscale = checked
			Installer:Refresh()
		end)
		frame.toggle:SetPoint("RIGHT", -18, 0)
	end,
	Refresh = function(_, frame)
		local width, height = GetPhysicalScreenSize()
		frame.resolution:SetText(format("%d x %d", width, height))
		frame.scale:SetText(format("%.4f", MaUI:GetTargetScale(State.choices.uiscale)))
		frame.scale:SetTextColor(unpack(State.modules.uiscale and C.text or C.muted))
		frame.notice:SetShown(not MaUI:IsDesignResolution())
		frame.mode:SetValue(State.choices.uiscale, true)
		frame.toggle:SetChecked(State.modules.uiscale, true)
	end,
})

-- 9. install -----------------------------------------------------------------

AddPage({
	nav = L["Install"],
	title = L["Ready to install"],
	subtitle = function()
		if State.existing then return format(L["This character will use the existing profile \"%s\". Click Install to apply it."], State.existing) end
		return State.advanced and L["The selected ElvUI modules replace the matching parts of your current profile. Click Install to apply them."]
			or L["Your current ElvUI settings stay available as their own profile. Click Install to apply MaUI."]
	end,
	Build = function(_, frame)
		local list = W.Panel(frame, C.surface, C.border, 0.85)
		list:SetPoint("TOPLEFT")
		list:SetSize(360, 390)
		frame.list = list

		local listTitle = SectionTitle(list, L["STEPS"])
		listTitle:SetPoint("TOPLEFT", 18, -18)

		frame.rows = {}
		for i = 1, #MaUI.Modules do
			local row = W.Box(list)
			row:SetSize(324, 34)
			row:SetPoint("TOPLEFT", 18, -40 - (i - 1) * 37)
			row.status = W.StatusIcon(row, 24)
			row.status:SetPoint("LEFT")
			row.name = W.Text(row, 13, C.text, true)
			row.name:SetPoint("TOPLEFT", row.status, "TOPRIGHT", 12, 2)
			row.detail = W.Text(row, 11, C.muted)
			row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
			row.detail:SetWidth(288)
			row.detail:SetWordWrap(false)
			frame.rows[i] = row
		end

		local summary = W.Panel(frame, C.surface, C.border, 0.85)
		summary:SetPoint("TOPRIGHT")
		summary:SetSize(PAGE_WIDTH - 376, 390)

		local summaryTitle = SectionTitle(summary, L["SUMMARY"])
		summaryTitle:SetPoint("TOPLEFT", 18, -18)

		frame.summary = {}
		for i, key in ipairs({ "profile", "layout", "cdm", "panels", "scale" }) do
			local caption = W.Text(summary, 11, C.muted)
			caption:SetPoint("TOPLEFT", 18, -46 - (i - 1) * 54)
			local value = W.Text(summary, 15, C.text, true)
			value:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -5)
			value:SetWidth(PAGE_WIDTH - 412)
			frame.summary[key] = { caption = caption, value = value }
		end
	end,
	Refresh = function(_, frame)
		if Installer.installing or Installer.installed then return end

		local steps = MaUI:GetSteps()
		for i, row in ipairs(frame.rows) do
			local module = steps[i]
			row:SetShown(module ~= nil)
			if module then
				row.module = module
				row.name:SetText(module.name)
				row.detail:SetText(module.desc)
				row.detail:SetTextColor(unpack(C.muted))
				row.status:SetStatus("pending")
			end
		end
		frame.list:SetHeight(52 + #steps * 37)

		local function Set(key, caption, value)
			frame.summary[key].caption:SetText(caption)
			frame.summary[key].value:SetText(value)
		end

		Set("profile", L["ElvUI profile"], MaUI:ProfileName(State))
		local layout = MaUI:GetLayout(State.layout).name
		-- a MaUI profile with an unknown name does not say which layout it is
		if State.existing and not MaUI:ProfileLayout(State.existing) then layout = L["Unknown"] end
		if State.advanced then
			local count = 0
			for _, selected in next, State.sections do
				if selected then count = count + 1 end
			end
			layout = format(L["%s, %d of %d ElvUI modules"], layout, count, #MaUI.ProfileSections)
		end
		Set("layout", L["Layout"], layout)
		Set("cdm", L["Cooldown Manager"], MaUI:IsCDMSupported() and (State.cdm and L["Yes"] or L["No"]) or L["Not available"])
		-- an existing profile or the advanced mode keep the panels as they are
		local panels = (State.existing or State.advanced) and L["Unchanged"] or MaUI:GetPanelPreset(State.panels.bar).name
		Set("panels", L["Data panels"], panels)
		Set("scale", L["UI scale"], State.modules.uiscale and format("%.4f", MaUI:GetTargetScale(State.choices.uiscale)) or L["Unchanged"])
	end,
	NextLabel = function()
		return (Installer.installing and L["Installing..."]) or (not Installer.installed and L["Install"]) or nil
	end,
	CanNext = function()
		return not Installer.installing
	end,
	Done = function()
		return Installer.installed
	end,
	Action = function(_, frame)
		local rows = {}
		for _, row in ipairs(frame.rows) do
			if row.module then rows[row.module] = row end
		end

		local started = MaUI:Install(function(module, status, err)
			local row = rows[module]
			if not row then return end
			row.status:SetStatus(status)
			if status == "failed" then
				row.detail:SetText(err and tostring(err):gsub("^.-:%d+: ", "") or L["Failed"])
				row.detail:SetTextColor(unpack(C.danger))
			end
		end, function(failed)
			Installer.installing = nil
			Installer.installed = true
			Installer.failed = failed
			Installer:Refresh()
			Installer:UpdateSidebar()
		end)

		if started then
			Installer.installing = true
			Installer:Refresh()
		end
	end,
})

-- update (only when the installer was opened for an outdated profile) ---------------------

local UPDATE_ROWS = 12

-- "player, target, party +3" from the subjects an area changes most
local function SubjectsText(subjects)
	local shown = {}
	for i = 1, math.min(#subjects, 3) do
		shown[i] = subjects[i]
	end
	local text = table.concat(shown, ", ")
	if #subjects > 3 then text = text .. format(" +%d", #subjects - 3) end
	return text
end

AddPage({
	nav = L["Update"],
	update = "only",
	title = L["Profile update"],
	subtitle = function()
		return format(L["MaUI has new settings for your profile \"%s\". See what changes before you apply them, your own changes stay."], State.updating or "")
	end,
	Build = function(_, frame)
		local list = W.Panel(frame, C.surface, C.border, 0.85)
		list:SetPoint("TOPLEFT")
		list:SetSize(400, 390)

		local listTitle = SectionTitle(list, L["CHANGES"])
		listTitle:SetPoint("TOPLEFT", 18, -18)

		frame.empty = W.Text(list, 13, C.muted)
		frame.empty:SetPoint("TOPLEFT", 18, -46)
		frame.empty:SetWidth(364)
		frame.empty:SetText(L["Nothing changes in this profile, the update only marks it as current."])

		-- one row per ElvUI area: name, what it is about, the count and a bar against the biggest area
		frame.rows = {}
		for i = 1, UPDATE_ROWS do
			local row = W.Box(list)
			row:SetSize(364, 24)
			row:SetPoint("TOPLEFT", 18, -42 - (i - 1) * 28)
			row.name = W.Text(row, 12, C.text, true)
			row.name:SetPoint("TOPLEFT")
			row.count = W.Text(row, 12, C.accent, true)
			row.count:SetPoint("TOPRIGHT")
			row.subjects = W.Text(row, 10, C.muted)
			row.subjects:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
			row.subjects:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
			row.subjects:SetWordWrap(false)
			row.track = W.Texture(row, nil, "BORDER", C.track)
			row.track:SetPoint("BOTTOMLEFT")
			row.track:SetPoint("BOTTOMRIGHT")
			row.track:SetHeight(3)
			row.bar = W.Texture(row, nil, "ARTWORK")
			W.Gradient(row.bar, "HORIZONTAL", C.accentA, 1, C.accentB, 1)
			row.bar:SetPoint("BOTTOMLEFT")
			row.bar:SetHeight(3)
			frame.rows[i] = row
		end

		local summary = W.Panel(frame, C.surface, C.border, 0.85)
		summary:SetPoint("TOPRIGHT")
		summary:SetSize(PAGE_WIDTH - 416, 390)

		local summaryTitle = SectionTitle(summary, L["SUMMARY"])
		summaryTitle:SetPoint("TOPLEFT", 18, -18)

		frame.summary = {}
		for i, key in ipairs({ "profile", "layout", "installed", "total" }) do
			local caption = W.Text(summary, 11, C.muted)
			caption:SetPoint("TOPLEFT", 18, -46 - (i - 1) * 54)
			local value = W.Text(summary, 15, C.text, true)
			value:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -5)
			value:SetWidth(PAGE_WIDTH - 452)
			value:SetWordWrap(false)
			frame.summary[key] = { caption = caption, value = value }
		end

		local note = W.Text(summary, 11, C.muted)
		note:SetPoint("BOTTOMLEFT", 18, 18)
		note:SetWidth(PAGE_WIDTH - 452)
		note:SetSpacing(2)
		note:SetText(L["Only the settings MaUI changed are carried over, your own changes stay."])
	end,
	Refresh = function(_, frame)
		local name = State.updating
		if not name or Installer.installed then return end

		-- the dry run is worked out once per profile, Refresh runs on every click
		if frame.previewFor ~= name then
			frame.previewFor = name
			frame.preview, frame.total = MaUI:PreviewUpdate(name)
		end

		local list, total = frame.preview, frame.total
		local biggest = list[1] and list[1].count or 1
		for i, row in ipairs(frame.rows) do
			local area = list[i]
			row:SetShown(area ~= nil)
			if area then
				-- the last row sums up what does not fit
				if i == UPDATE_ROWS and #list > UPDATE_ROWS then
					local rest = 0
					for j = i, #list do
						rest = rest + list[j].count
					end
					row.name:SetText(format(L["and %d more areas"], #list - i + 1))
					row.subjects:SetText("")
					row.count:SetText(tostring(rest))
				else
					row.name:SetText(area.name)
					row.subjects:SetText(SubjectsText(area.subjects))
					row.count:SetText(tostring(area.count))
				end
				row.bar:SetWidth(math.max(1, 364 * math.min(1, area.count / biggest)))
			end
		end
		frame.empty:SetShown(#list == 0)

		local info = MaUI:GetProfileInfo(name)
		local source = info or MaUI:ParseProfileName(name)
		local layout = source and MaUI:GetLayout(source.layout)
		local function Set(key, caption, value)
			frame.summary[key].caption:SetText(caption)
			frame.summary[key].value:SetText(value)
		end
		Set("profile", L["ElvUI profile"], name)
		Set("layout", L["Layout"], layout and (layout.name .. (source.cdm and " + CDM" or "")) or L["Unknown"])
		Set("installed", L["Installed on"], info and date("%d.%m.%Y", info.time or 0) or L["Imported by hand"])
		Set("total", L["Changed settings"], tostring(total))
	end,
	NextLabel = function()
		return not Installer.installed and L["Update"] or nil
	end,
	Done = function()
		return Installer.installed
	end,
	Action = function()
		if InCombatLockdown() then
			MaUI:Print(L["The installation cannot run in combat."])
			return
		end

		local ok, result = pcall(MaUI.UpdateProfile, MaUI, State.updating)
		if not ok then MaUI:Print(tostring(result)) end
		Installer.installed = true
		Installer.failed = ok and 0 or 1
		Installer.updated = ok and result or 0
		-- straight on to the done page, there is nothing more to show here
		Installer:Next()
	end,
})

-- 10. done --------------------------------------------------------------------

AddPage({
	nav = L["Done"],
	update = true,
	title = L["All set!"],
	Build = function(_, frame)
		local glow = W.Texture(frame, Media.glow, "BACKGROUND", C.success, 0.25)
		glow:SetBlendMode("ADD")
		glow:SetSize(260, 260)
		glow:SetPoint("TOP", 0, 20)

		frame.icon = W.StatusIcon(frame, 96)
		frame.icon:SetPoint("TOP", 0, -60)

		frame.headline = W.Text(frame, 20, C.text, true)
		-- the status icon is a box, regions outside of it anchor to its region
		frame.headline:SetPoint("TOP", W.Anchor(frame.icon), "BOTTOM", 0, -26)
		frame.headline:SetJustifyH("CENTER")

		frame.text = W.Text(frame, 13, C.muted)
		frame.text:SetPoint("TOP", frame.headline, "BOTTOM", 0, -12)
		frame.text:SetWidth(PAGE_WIDTH - 120)
		frame.text:SetJustifyH("CENTER")
		frame.text:SetSpacing(4)
		frame.glow = glow

		-- plays each time the page comes up; the frame starts hidden so the first Show counts too
		-- the burst stays inside the installer window
		frame.celebration = W.Celebration(frame, frame.icon, 96, Installer.frame)
		frame:SetScript("OnShow", function()
			local failed = (Installer.failed or 0) > 0
			frame.celebration:Play(not failed, C.warning)
		end)
		frame:Hide()
	end,
	Refresh = function(_, frame)
		local failed = Installer.failed or 0
		local color = failed > 0 and C.warning or C.success
		frame.icon:SetStatus(failed > 0 and "failed" or "done")
		frame.icon.icon:SetVertexColor(unpack(color))
		frame.glow:SetVertexColor(color[1], color[2], color[3], 0.25)

		if State.updating then
			if failed > 0 then
				frame.headline:SetText(L["Update failed"])
				frame.text:SetText(L["The details are in your chat. Feel free to ask on Discord."])
			else
				frame.headline:SetText(L["Profile updated"])
				frame.text:SetText(format(L["%d settings were updated. Reload your interface to load them."], Installer.updated or 0))
			end
		elseif failed > 0 then
			frame.headline:SetText(format(L["Installed with %d problem(s)"], failed))
			frame.text:SetText(L["The steps marked red could not be applied, the details are in your chat. Everything else is ready. Reload your interface to finish, and feel free to ask on Discord."])
		else
			frame.headline:SetText(L["MaUI is installed"])
			frame.text:SetText(L["Reload your interface to load the new profiles. You can run the installer again at any time with /maui."])
		end
	end,
})
