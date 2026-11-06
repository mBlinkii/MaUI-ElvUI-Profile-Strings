local MaUI, L, E = unpack(ElvUI_MaUI)
local W = MaUI.Widgets

local _G = _G
local format, ipairs, tinsert, type, unpack = format, ipairs, tinsert, type, unpack
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local ReloadUI = ReloadUI

local C = MaUI.Colors
local Media = MaUI.Media

local WIDTH, HEIGHT, SIDEBAR = 980, 620, 250
local PADDING = 40
local STEP_HEIGHT, STEPS_TOP = 40, -162 -- up to nine steps fit above the Discord and GitHub buttons

local Installer = {}
MaUI.Installer = Installer

-- pages are added by ui\pages.lua:
-- { nav, title, subtitle, Build(frame), Refresh(frame), NextLabel(), CanNext(), Action(frame), Done() }
-- update = true: part of the update (State.updating), "only" when it shows in no installation
MaUI.Pages = {}

E.PopupDialogs.MAUI_INSTALLER_URL = {
	text = MaUI.Title,
	button1 = _G.OKAY,
	hasEditBox = 1,
	OnShow = function(self, url)
		local editBox = self.editBox or self.EditBox
		editBox:SetAutoFocus(false)
		editBox:SetText(url)
		editBox:HighlightText()
		editBox:SetFocus()
		editBox.url = url
	end,
	EditBoxOnTextChanged = function(self)
		if self.url and self:GetText() ~= self.url then self:SetText(self.url) end
		self:HighlightText()
	end,
	EditBoxOnEnterPressed = function(self)
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	whileDead = 1,
	hideOnEscape = 1,
	preferredIndex = 3,
}

function MaUI:ShowURL(url)
	E:StaticPopup_Show("MAUI_INSTALLER_URL", nil, nil, url)
end

-- decoration -----------------------------------------------------------------

local function CreateDecoration(frame)
	local pattern = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	pattern:SetTexture(Media.pattern, "REPEAT", "REPEAT")
	pattern:SetHorizTile(true)
	pattern:SetVertTile(true)
	pattern:SetInside(frame)
	pattern:SetAlpha(0.035)

	local glowA = W.Texture(frame, Media.glow, "BACKGROUND", C.accentA, 0.16)
	glowA:SetDrawLayer("BACKGROUND", 2)
	glowA:SetBlendMode("ADD")
	glowA:SetSize(700, 520)
	glowA:SetPoint("CENTER", frame, "TOPRIGHT", -120, -40)

	local glowB = W.Texture(frame, Media.glow, "BACKGROUND", C.accentB, 0.12)
	glowB:SetDrawLayer("BACKGROUND", 2)
	glowB:SetBlendMode("ADD")
	glowB:SetSize(700, 520)
	glowB:SetPoint("CENTER", frame, "BOTTOMLEFT", SIDEBAR + 140, 40)

	local line = frame:CreateTexture(nil, "OVERLAY")
	W.Gradient(line, "HORIZONTAL", C.accentA, 1, C.accentB, 1)
	line:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	line:SetHeight(2)
end

-- sidebar --------------------------------------------------------------------

-- the steps are placed by Installer:UpdateSidebar, which leaves out hidden pages
local function CreateStep(sidebar, index, page)
	local step = CreateFrame("Button", nil, sidebar)
	step:SetSize(SIDEBAR, STEP_HEIGHT)

	step.circle = W.Texture(step, Media.circle, "ARTWORK", C.surface)
	step.circle:SetSize(26, 26)
	step.circle:SetPoint("LEFT", 28, 0)

	step.ring = W.Texture(step, Media.ring, "ARTWORK", C.track)
	step.ring:SetDrawLayer("ARTWORK", 1)
	step.ring:SetAllPoints(step.circle)

	step.number = W.Text(step, 12, C.muted, true)
	step.number:SetPoint("CENTER", step.circle, 0, 0)
	step.number:SetJustifyH("CENTER")

	-- the line up to the previous step
	step.connector = W.Texture(step, nil, "BORDER", C.track)
	step.connector:SetSize(2, STEP_HEIGHT - 26 - 8)
	step.connector:SetPoint("BOTTOM", step.circle, "TOP", 0, 4)

	step.check = W.Texture(step, Media.check, "OVERLAY", C.onAccent)
	step.check:SetSize(18, 18)
	step.check:SetPoint("CENTER", step.circle)

	step.label = W.Text(step, 14, C.muted, true)
	step.label:SetPoint("LEFT", step.circle, "RIGHT", 14, 0)
	step.label:SetText(page.nav)

	step:SetScript("OnClick", function()
		if Installer:CanJumpTo(index) then Installer:SetPage(index) end
	end)

	return step
end

local function CreateSidebar(frame)
	local sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPLEFT", 1, -1)
	sidebar:SetPoint("BOTTOMLEFT", 1, 1)
	sidebar:SetWidth(SIDEBAR)

	local bg = W.Texture(sidebar, nil, "BACKGROUND", C.sidebar, 0.75)
	bg:SetAllPoints()

	local edge = W.Texture(sidebar, nil, "BORDER", C.border)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetWidth(1)

	local logo = W.Texture(sidebar, Media.logo, "ARTWORK")
	logo:SetSize(200, 100)
	logo:SetPoint("TOP", 0, -26)

	local subtitle = W.Text(sidebar, 11, C.muted, true)
	subtitle:SetPoint("TOP", logo, "BOTTOM", 0, 0)
	subtitle:SetJustifyH("CENTER")
	subtitle:SetText(format(L["PROFILE %s  ·  ELVUI"], MaUI.ProfileVersion))

	-- the highlight slides to the active step: a fade and an accent bar on the sidebar itself
	sidebar.selectorFade = W.Texture(sidebar, Media.fade, "BORDER", C.accent, 0.16)
	sidebar.selectorFade:SetSize(SIDEBAR - 1, STEP_HEIGHT - 6)
	sidebar.selectorBar = W.Texture(sidebar, nil, "BORDER", C.accent)
	sidebar.selectorBar:SetSize(3, STEP_HEIGHT - 6)

	sidebar.steps = {}
	for index, page in ipairs(MaUI.Pages) do
		sidebar.steps[index] = CreateStep(sidebar, index, page)
	end

	local discord = W.Button(sidebar, L["Discord"], "secondary", (SIDEBAR - 62) / 2, 32, Media.discord)
	discord:SetPoint("BOTTOMLEFT", 28, 50)
	discord:SetScript("OnClick", function()
		MaUI:ShowURL(MaUI.Discord)
	end)

	local github = W.Button(sidebar, "GitHub", "secondary", (SIDEBAR - 62) / 2, 32, Media.github)
	github:SetPoint("LEFT", discord, "RIGHT", 6, 0)
	github:SetScript("OnClick", function()
		MaUI:ShowURL(MaUI.GitHub)
	end)

	local version = W.Text(sidebar, 10, C.muted)
	version:SetPoint("BOTTOM", 0, 22)
	version:SetJustifyH("CENTER")
	version:SetText(format(L["Installer %s"], MaUI.Version))

	return sidebar
end

-- content --------------------------------------------------------------------

local function CreateContent(frame)
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", SIDEBAR + PADDING, -PADDING + 6)
	content:SetPoint("BOTTOMRIGHT", -PADDING, 0)

	content.stepLabel = W.Text(content, 11, C.accent, true)
	content.stepLabel:SetPoint("TOPLEFT")

	content.title = W.Text(content, 28, C.text, true)
	content.title:SetPoint("TOPLEFT", content.stepLabel, "BOTTOMLEFT", 0, -8)

	content.subtitle = W.Text(content, 13, C.muted)
	content.subtitle:SetPoint("TOPLEFT", content.title, "BOTTOMLEFT", 0, -8)
	content.subtitle:SetWidth(WIDTH - SIDEBAR - PADDING * 2 - 40)
	content.subtitle:SetSpacing(3)

	local separator = W.Texture(content, nil, "BORDER", C.border)
	separator:SetPoint("BOTTOMLEFT", 0, 68)
	separator:SetPoint("BOTTOMRIGHT", 0, 68)
	separator:SetHeight(1)

	-- the progress bar sits on the separator and grows with every step
	content.progress = content:CreateTexture(nil, "ARTWORK")
	W.Gradient(content.progress, "HORIZONTAL", C.accentA, 1, C.accentB, 1)
	content.progress:SetPoint("BOTTOMLEFT", separator, "BOTTOMLEFT")
	content.progress:SetHeight(2)
	content.progress:SetWidth(1)

	content.next = W.Button(content, L["Next"], "primary", 150, 36)
	content.next:SetPoint("BOTTOMRIGHT", 0, 18)
	content.next:SetScript("OnClick", function()
		Installer:Next()
	end)

	content.back = W.Button(content, L["Back"], "secondary", 110, 36)
	content.back:SetPoint("RIGHT", content.next, "LEFT", -10, 0)
	content.back:SetScript("OnClick", function()
		Installer:Back()
	end)

	content.skip = W.Button(content, L["Skip installation"], "secondary", 160, 36)
	content.skip:SetPoint("BOTTOMLEFT", 0, 18)
	content.skip:SetScript("OnClick", function()
		MaUI:SkipInstall()
		Installer.frame:Hide()
		MaUI:Print(L["Installation skipped. Type /maui to open the installer again."])
	end)

	return content
end

function Installer:Create()
	MaUI:ApplyTheme()

	local frame = CreateFrame("Frame", "MaUIInstallerFrame", E.UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetTemplate("Default", nil, true)
	W.SetPanelColors(frame, C.background, C.border, 0.82)
	frame:CreateShadow(14)
	frame.shadow:SetBackdropBorderColor(0, 0, 0, 0.75)
	tinsert(_G.UISpecialFrames, frame:GetName())

	CreateDecoration(frame)
	self.sidebar = CreateSidebar(frame)
	self.content = CreateContent(frame)

	local close = W.IconButton(frame, Media.cross, 22)
	close:SetPoint("TOPRIGHT", -14, -14)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	self.frame = frame
end

-- a page is built the first time it is shown, pages nobody opens cost nothing
function Installer:BuildPage(page)
	if page.frame then return end

	page.frame = CreateFrame("Frame", nil, self.content)
	page.frame:SetPoint("TOPLEFT", 0, -112)
	page.frame:SetSize(WIDTH - SIDEBAR - PADDING * 2, HEIGHT - 112 - 84 - PADDING + 6)
	page:Build(page.frame)
end

-- navigation -----------------------------------------------------------------

local function IsPageShown(index)
	local page = MaUI.Pages[index]
	if not page then return false end
	-- an update has its own short way: the changes, then done
	if MaUI.State.updating then return page.update ~= nil end
	return page.update ~= "only" and (not page.IsShown or page.IsShown())
end

local function FirstPage()
	local index = 1
	while index < #MaUI.Pages and not IsPageShown(index) do
		index = index + 1
	end
	return index
end

-- position of a page among the visible ones and their count, for the step counter and progress
function Installer:Position(index)
	local position, count = 0, 0
	for i = 1, #MaUI.Pages do
		if IsPageShown(i) then
			count = count + 1
			if i <= index then position = count end
		end
	end
	return position, count
end

function Installer:CanJumpTo(index)
	return not self.installing and not self.installed and index < self.index and IsPageShown(index)
end

function Installer:UpdateSidebar()
	local sidebar = self.sidebar
	local position, activePosition = 0, 0
	for index, step in ipairs(sidebar.steps) do
		local shown = IsPageShown(index)
		step:SetShown(shown)
		if shown then
			position = position + 1
			step:SetPoint("TOPLEFT", 0, STEPS_TOP - (position - 1) * STEP_HEIGHT)
			step.connector:SetShown(position > 1)
			step.number:SetText(position)
			if index == self.index then activePosition = position end
		end

		local active, completed = index == self.index, index < self.index
		step.circle:SetVertexColor(unpack((active or completed) and C.accent or C.surface))
		step.ring:SetVertexColor(unpack(active and C.accentA or C.track))
		step.number:SetShown(not completed)
		W.SetAccentText(step.number, active)
		step.check:SetShown(completed)
		step.label:SetTextColor(unpack((active and C.text) or (completed and { 0.8, 0.82, 0.88 }) or C.muted))
	end

	local target = STEPS_TOP - (activePosition - 1) * STEP_HEIGHT - 3
	W.Tween(sidebar.selectorFade, self.selectorY or target, target, 0.25, function(y)
		self.selectorY = y
		sidebar.selectorFade:SetPoint("TOPLEFT", 0, y)
		sidebar.selectorBar:SetPoint("TOPLEFT", 0, y)
	end)
end

function Installer:UpdateFooter()
	local content, page = self.content, MaUI.Pages[self.index]
	local last = self.index == #MaUI.Pages

	content.next:SetLabel((page.NextLabel and page.NextLabel()) or (last and L["Reload UI"]) or L["Next"])
	content.next:SetEnabled(not page.CanNext or page.CanNext())
	content.back:SetShown(self.index > FirstPage() and not self.installed)
	content.back:SetEnabled(not self.installing)
	content.skip:SetShown(self.index == 1)

	local position, count = self:Position(self.index)
	local width = content:GetWidth() * (position - 1) / (count - 1)
	W.Tween(content.progress, self.progressWidth or 1, width, 0.4, function(value)
		self.progressWidth = value
		content.progress:SetWidth(value > 1 and value or 1)
	end)
end

function Installer:Refresh()
	local page = MaUI.Pages[self.index]
	if page.Refresh then page:Refresh(page.frame) end
	self:UpdateFooter()
	-- options on a page can show or hide later pages
	self:UpdateSidebar()
end

function Installer:SetPage(index, instant)
	local pages = MaUI.Pages
	if index < 1 or index > #pages then return end

	local old = pages[self.index or index]
	if old and old.frame then old.frame:Hide() end

	self.index = index
	local page, content = pages[index], self.content

	content.stepLabel:SetText(format(L["STEP %d OF %d"], self:Position(index)))
	content.title:SetText(page.title)
	content.subtitle:SetText((type(page.subtitle) == "function" and page.subtitle()) or page.subtitle or "")

	self:BuildPage(page)
	page.frame:Show()
	self:Refresh()

	if not instant then
		W.Reveal(content.title, 0, 6)
		W.Reveal(content.subtitle, 0.05, 6)
	end
	W.Reveal(page.frame, instant and 0 or 0.08, 12)
end

function Installer:Next()
	if self.index == #MaUI.Pages then
		ReloadUI()
		return
	end

	-- a page with an Action (the install page) runs it instead of moving on until it is done
	local page = MaUI.Pages[self.index]
	if page.Action and not page.Done() then
		page:Action(page.frame)
		return
	end

	local index = self.index + 1
	while not IsPageShown(index) do
		index = index + 1
	end
	self:SetPage(index)
end

function Installer:Back()
	local index = self.index - 1
	while index > 1 and not IsPageShown(index) do
		index = index - 1
	end
	self:SetPage(index)
end

-- public ---------------------------------------------------------------------

-- `update`: the name of an outdated MaUI profile, the installer then only shows and runs its update
function MaUI:ShowInstaller(update)
	if InCombatLockdown() then
		MaUI:Print(L["The installer opens after combat."])
		Installer.pending = update or true
		return
	end

	if not Installer.frame then Installer:Create() end

	if not Installer.installing then
		Installer.installed, Installer.failed, Installer.updated = nil, nil, nil
		MaUI:ResetState()
		MaUI.State.updating = update
		Installer:SetPage(FirstPage(), true)
	end

	Installer.frame:Show()
	W.Reveal(Installer.frame, 0)
end

-- the installer steps aside while the player fights and comes back on the same page afterwards
function MaUI:HideInstallerForCombat()
	if Installer.frame and Installer.frame:IsShown() then
		Installer.hiddenByCombat = true
		Installer.frame:Hide()
	end
end

function MaUI:RestoreInstallerAfterCombat()
	if not Installer.hiddenByCombat then return end
	Installer.hiddenByCombat = nil

	Installer.frame:Show()
	W.Reveal(Installer.frame, 0)
end

function MaUI:ToggleInstaller()
	if Installer.frame and Installer.frame:IsShown() then
		Installer.frame:Hide()
	else
		MaUI:ShowInstaller()
	end
end
