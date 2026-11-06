local MaUI, L, E = unpack(ElvUI_MaUI)

local _G = _G
local format, ipairs, next, tinsert, type, unpack = format, ipairs, next, tinsert, type, unpack
local abs, cos, sin, max, min, pi, random = math.abs, math.cos, math.sin, math.max, math.min, math.pi, math.random
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local GetLocale = GetLocale

local C = MaUI.Colors
local Media = MaUI.Media

local W = {}
MaUI.Widgets = W

-- tweens ---------------------------------------------------------------------

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()

local function OutCubic(t)
	t = t - 1
	return t * t * t + 1
end

driver:SetScript("OnUpdate", function(self, elapsed)
	for key, tween in next, tweens do
		tween.time = tween.time + elapsed
		local progress = min(1, tween.time / tween.duration)
		tween.apply(tween.from + (tween.to - tween.from) * OutCubic(progress))
		if progress >= 1 then
			tweens[key] = nil
			if tween.done then tween.done() end
		end
	end
	if not next(tweens) then self:Hide() end
end)

-- animates a number from `from` to `to`; a new tween with the same key replaces the running one
function W.Tween(key, from, to, duration, apply, done)
	if duration <= 0 then
		tweens[key] = nil
		apply(to)
		if done then done() end
		return
	end
	tweens[key] = { time = 0, duration = duration, from = from, to = to, apply = apply, done = done }
	driver:Show()
end

local function Mix(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end
W.Mix = Mix

-- theme ----------------------------------------------------------------------

-- colors are changed in place, widgets and pages keep references to these tables
local function SetColor(color, r, g, b)
	color[1], color[2], color[3] = r, g, b
end

local WHITE = { 1, 1, 1 }

-- the installer wears the ElvUI colors of the MaUI profile and the player's class color
function MaUI:ApplyTheme()
	-- from data\index.lua, a window does not need the data addon just for its colors
	local general = self.ThemeColors or {}

	for key, setting in next, { background = "backdropcolor", sidebar = "backdropfadecolor", border = "bordercolor" } do
		local value = general[setting]
		if value then SetColor(C[key], value.r or C[key][1], value.g or C[key][2], value.b or C[key][3]) end
	end

	SetColor(C.surface, Mix(C.sidebar, C.background, 0.45))
	SetColor(C.surfaceHover, Mix(C.sidebar, C.background, 0.9))
	SetColor(C.track, Mix(C.background, WHITE, 0.16))
	SetColor(C.muted, Mix(C.text, C.background, 0.38))

	-- light class colors (priest, rogue, monk) need dark text, and their gradient may only darken a little
	-- so that text stays readable across the whole button
	local class = E:ClassColor(E.myclass, true)
	local light = 0.299 * class.r + 0.587 * class.g + 0.114 * class.b > 0.65
	local shade = light and 0.8 or 0.55
	SetColor(C.accent, class.r, class.g, class.b)
	SetColor(C.accentA, class.r, class.g, class.b)
	SetColor(C.accentB, class.r * shade, class.g * shade, class.b * shade)
	SetColor(C.onAccent, unpack(light and { 0.1, 0.1, 0.1 } or C.text))
	MaUI.LightAccent = light
end

-- colors text that sits on an accent fill; dark text gets no shadow, it would only blur it
function W.SetAccentText(text, onAccent)
	text:SetTextColor(unpack(onAccent and C.onAccent or C.muted))
	text:SetShadowColor(0, 0, 0, (onAccent and MaUI.LightAccent) and 0 or 0.8)
end

-- basics ---------------------------------------------------------------------

-- Expressway and ElvUI's default font only cover Latin letters, these clients use their own font
local CLIENT_FONT_LOCALES = { ruRU = true, koKR = true, zhCN = true, zhTW = true }

function W.Fonts()
	if CLIENT_FONT_LOCALES[GetLocale()] then return _G.STANDARD_TEXT_FONT, _G.STANDARD_TEXT_FONT end

	local LSM = E.Libs.LSM
	return LSM:Fetch("font", "Expressway") or E.media.normFont, E.media.normFont
end

function W.Text(parent, size, color, heading, layer)
	local headingFont, bodyFont = W.Fonts()
	local text = parent:CreateFontString(nil, layer or "OVERLAY") -- boxes forward this to their frame
	text:SetFont(heading and headingFont or bodyFont, size, "")
	text:SetShadowOffset(1, -1)
	text:SetShadowColor(0, 0, 0, 0.8)
	text:SetTextColor(unpack(color or C.text))
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)
	return text
end

-- trilinear filtering uses the mipmaps, so the large shape textures stay smooth when drawn small
function W.SetShape(tex, file)
	tex:SetTexture(file, nil, nil, "TRILINEAR")
end

function W.Texture(parent, file, layer, color, alpha)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	W.SetShape(tex, file or Media.white)
	if color then tex:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
	return tex
end

-- role icons ---------------------------------------------------------------------

-- the profile's mMediaTag settings and Blizzard's role icons in case mMT does not know the icon
local ROLE_SETTINGS = { TANK = "tank", HEALER = "heal", DAMAGER = "dd" }
local BLIZZARD_ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local BLIZZARD_ROLE_COORDS = {
	TANK = { 0, 0.2617, 0.2617, 0.5234 },
	HEALER = { 0.2617, 0.5234, 0, 0.2617 },
	DAMAGER = { 0.2617, 0.5234, 0.2617, 0.5234 },
}

-- the mMediaTag role icon the MaUI profile uses: its own choice from the index, otherwise mMT's default
-- returns the file and, for Blizzard's fallback, the texture coordinates
function W.RoleIcon(role)
	local mmt = _G.ElvUI_mMediaTag
	local defaults, media = mmt and mmt[5], mmt and mmt[7]
	local setting = ROLE_SETTINGS[role]
	local name = MaUI.RoleIcons[setting] or (defaults and defaults.role_icons and defaults.role_icons[setting])
	local file = name and media and media.icons and media.icons.role and media.icons.role[name]

	if file then return file end
	return BLIZZARD_ROLE_FILE, BLIZZARD_ROLE_COORDS[role]
end

-- the same icon as a texture escape for texts
function W.RoleIconString(role, size)
	local file, coords = W.RoleIcon(role)
	if not coords then return format("|T%s:%d:%d|t", file, size, size) end
	return format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", file, size, size, coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

function W.Gradient(tex, orientation, colorA, alphaA, colorB, alphaB)
	tex:SetTexture(Media.white)
	tex:SetGradient(orientation, CreateColor(colorA[1], colorA[2], colorA[3], alphaA), CreateColor(colorB[1], colorB[2], colorB[3], alphaB))
end

-- boxes ------------------------------------------------------------------------------
--[[ A box looks and behaves like a panel frame but is only textures on the frame it belongs to: an
	anchor, the fill and four one pixel edges like ElvUI's backdrop, so a see-through fill stays
	see-through. Regions and frames created "in" a box live on
	that frame; the box shows, hides and fades them with itself, and points given relative to a box (or
	without a relative region) are taken relative to the box. Only things that take clicks are frames.
]]

-- a box sits above a backdrop of the frame it is on, a box in a box above that
local LAYERS = { "BORDER", "ARTWORK", "ARTWORK" }

local Box = {}
local BoxMeta = { __index = Box }

-- the real frame behind a parent, which may be a box
local function Host(parent)
	return parent.isBox and parent.host or parent
end
W.Host = Host

local function Resolve(relative)
	return type(relative) == "table" and relative.isBox and relative.outer or relative
end
-- the region to anchor to, for frames and regions that are not part of the box
W.Anchor = Resolve

-- SetPoint / SetAllPoints of a box child: missing or box relatives point at the box itself
local function ChildSetPoint(self, point, relative, relativePoint, x, y)
	if relative == nil or type(relative) == "number" then
		return self.__SetPoint(self, point, self.__box.outer, point, relative or 0, relativePoint or 0)
	end
	return self.__SetPoint(self, point, Resolve(relative), relativePoint or point, x or 0, y or 0)
end

local function ChildSetAllPoints(self, relative)
	return self.__SetAllPoints(self, Resolve(relative) or self.__box.outer)
end

-- registers a region, frame or box with the box it was made in
local function Adopt(parent, child)
	if not parent.isBox then return child end

	if not child.isBox then
		child.__box = parent
		child.__SetPoint, child.SetPoint = child.SetPoint, ChildSetPoint
		child.__SetAllPoints, child.SetAllPoints = child.SetAllPoints, ChildSetAllPoints
	end
	parent.children[#parent.children + 1] = child
	if not parent.shown then child:Hide() end
	return child
end
W.Adopt = Adopt

function W.Box(parent, color, borderColor, alpha)
	local host = Host(parent)
	local depth = parent.isBox and parent.depth + 1 or 1
	local layer = LAYERS[depth] or "ARTWORK"

	local box = setmetatable({ isBox = true, host = host, depth = depth, children = {}, shown = true, parent = parent }, BoxMeta)

	-- the outer texture only gives the box its place and size, everyone anchors to it
	box.outer = host:CreateTexture(nil, layer, nil, -8)
	box.outer:SetColorTexture(0, 0, 0, 0)
	box.textures = { box.outer }

	-- an invisible box (no color) only groups and places what is in it
	if color then
		local mult = E.mult
		box.inner = host:CreateTexture(nil, layer, nil, -8)
		box.inner:SetPoint("TOPLEFT", box.outer, "TOPLEFT", mult, -mult)
		box.inner:SetPoint("BOTTOMRIGHT", box.outer, "BOTTOMRIGHT", -mult, mult)

		-- top, bottom, left, right: each pinned to two corners and one pixel thick
		box.edges = {}
		for i, corners in next, { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } } do
			local edge = host:CreateTexture(nil, layer, nil, -7)
			edge:SetPoint(corners[1], box.outer, corners[1])
			edge:SetPoint(corners[2], box.outer, corners[2])
			if i <= 2 then edge:SetHeight(mult) else edge:SetWidth(mult) end
			box.edges[i] = edge
		end

		box.textures[2] = box.inner
		for _, edge in next, box.edges do
			box.textures[#box.textures + 1] = edge
		end

		box:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
		box:SetBackdropBorderColor(unpack(borderColor or C.border))
	end

	return Adopt(parent, box)
end

W.Panel = W.Box

function Box:SetBackdropColor(r, g, b, a)
	if self.inner then self.inner:SetColorTexture(r, g, b, a or 1) end
end

function Box:SetBackdropBorderColor(r, g, b, a)
	for _, edge in next, self.edges or {} do
		edge:SetColorTexture(r, g, b, a or 1)
	end
end

function Box:SetPoint(point, relative, relativePoint, x, y)
	local default = self.parent.isBox and self.parent.outer or self.host
	if relative == nil or type(relative) == "number" then
		return self.outer:SetPoint(point, default, point, relative or 0, relativePoint or 0)
	end
	return self.outer:SetPoint(point, Resolve(relative), relativePoint or point, x or 0, y or 0)
end

function Box:ClearAllPoints()
	self.outer:ClearAllPoints()
end

function Box:SetSize(width, height)
	self.outer:SetSize(width, height)
end

function Box:SetWidth(width)
	self.outer:SetWidth(width)
end

function Box:SetHeight(height)
	self.outer:SetHeight(height)
end

function Box:GetWidth()
	return self.outer:GetWidth()
end

function Box:IsShown()
	return self.shown
end

function Box:SetShown(shown)
	self.shown = shown and true or false
	for _, texture in next, self.textures do
		texture:SetShown(shown)
	end
	for _, child in next, self.children do
		-- a child keeps its own visibility for when the box shows again
		if shown then
			if child.isBox then child:SetShown(child.wanted ~= false) elseif child.wanted ~= false then child:Show() end
		else
			if child.isBox then
				child.wanted = child.shown
				child:SetShown(false)
			else
				child.wanted = child:IsShown()
				child:Hide()
			end
		end
	end
end

function Box:Show()
	self:SetShown(true)
end

function Box:Hide()
	self:SetShown(false)
end

function Box:SetAlpha(alpha)
	for _, texture in next, self.textures do
		texture:SetAlpha(alpha)
	end
	for _, child in next, self.children do
		child:SetAlpha(alpha)
	end
end

-- regions made in a box are made on its frame
function Box:CreateTexture(name, layer, template, sublevel)
	return Adopt(self, self.host:CreateTexture(name, layer or LAYERS[self.depth + 1] or "ARTWORK", template, sublevel))
end

function Box:CreateFontString(name, layer, template)
	return Adopt(self, self.host:CreateFontString(name, layer or "OVERLAY", template))
end

-- works for frames with a backdrop and for boxes
function W.SetPanelColors(panel, color, borderColor, alpha)
	panel:SetBackdropColor(color[1], color[2], color[3], alpha or 1)
	panel:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
end

-- fades a frame in while it slides a few pixels into place
function W.Reveal(frame, delay, offset)
	frame.revealGroup = frame.revealGroup or frame:CreateAnimationGroup()
	local group = frame.revealGroup
	group:Stop()

	if not group.alpha then
		group.alpha = group:CreateAnimation("Alpha")
		group.alpha:SetFromAlpha(0)
		group.alpha:SetToAlpha(1)
		group.alpha:SetDuration(0.3)
		group.alpha:SetSmoothing("OUT")
		group.move = group:CreateAnimation("Translation")
		group.move:SetDuration(0.3)
		group.move:SetSmoothing("OUT")
		-- the frame stays invisible during the start delay and keeps full alpha afterwards
		group:SetToFinalAlpha(true)
	end

	group.alpha:SetStartDelay(delay or 0)
	group.move:SetStartDelay(delay or 0)
	group.move:SetOffset(0, 0)
	frame:SetAlpha(0)

	-- Translation moves from the current spot, so the frame starts offset and the animation brings it back
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if point and offset then
		frame.revealPoint = frame.revealPoint or { point, relativeTo, relativePoint, x, y }
		local p = frame.revealPoint
		frame:SetPoint(p[1], p[2], p[3], p[4], p[5] - offset)
		group.move:SetOffset(0, offset)
		group:SetScript("OnFinished", function()
			frame:SetPoint(p[1], p[2], p[3], p[4], p[5])
		end)
	end

	group:Play()
end

-- buttons --------------------------------------------------------------------

local function ButtonColors(button)
	if button.kind == "primary" then return C.accentA, C.accentB end
	if button.kind == "danger" then return C.danger, C.danger end
	return C.surface, C.surface
end

local function ButtonUpdate(button, hover)
	local from = button.hoverValue or 0
	W.Tween(button, from, hover and 1 or 0, 0.18, function(value)
		button.hoverValue = value
		button.highlight:SetAlpha(value * (button.kind == "secondary" and 0.08 or 0.18))
		local r, g, b = Mix(C.border, C.accent, value)
		button:SetBackdropBorderColor(r, g, b, 1)
		if button.icon then button.icon:SetVertexColor(Mix(button.label.textColor, C.accent, value)) end
	end)
end

local BUTTON_ICON, BUTTON_ICON_GAP = 16, 6

-- icon is optional, it sits left of the text and both are centered together
function W.Button(parent, text, kind, width, height, icon)
	local button = Adopt(parent, CreateFrame("Button", nil, Host(parent), "BackdropTemplate"))
	button.kind = kind or "secondary"
	button:SetSize(width or 130, height or 34)
	button:SetTemplate("Default", nil, true)
	button:SetBackdropColor(0, 0, 0, 0)
	button:SetBackdropBorderColor(unpack(C.border))

	button.fill = W.Texture(button, nil, "BACKGROUND")
	button.fill:SetInside(button)
	local a, b = ButtonColors(button)
	W.Gradient(button.fill, "HORIZONTAL", a, 1, b, 1)

	button.highlight = W.Texture(button, nil, "BORDER", { 1, 1, 1 }, 1)
	button.highlight:SetInside(button)
	button.highlight:SetAlpha(0)

	button.label = W.Text(button, 13, C.text, true)
	button.label.textColor = button.kind == "primary" and C.onAccent or C.text
	if button.kind == "primary" then W.SetAccentText(button.label, true) end
	button.labelX = icon and (BUTTON_ICON + BUTTON_ICON_GAP) / 2 or 0
	button.label:SetPoint("CENTER", button.labelX, 0)
	button.label:SetJustifyH("CENTER")
	button.label:SetText(text)

	if icon then
		button.icon = W.Texture(button, icon, "OVERLAY", button.label.textColor)
		button.icon:SetSize(BUTTON_ICON, BUTTON_ICON)
		button.icon:SetPoint("RIGHT", button.label, "LEFT", -BUTTON_ICON_GAP, 0)
	end

	button:SetScript("OnEnter", function(self)
		if self:IsEnabled() then ButtonUpdate(self, true) end
	end)
	button:SetScript("OnLeave", function(self)
		ButtonUpdate(self, false)
	end)
	button:SetScript("OnMouseDown", function(self)
		if self:IsEnabled() then self.label:SetPoint("CENTER", self.labelX, -1) end
	end)
	button:SetScript("OnMouseUp", function(self)
		self.label:SetPoint("CENTER", self.labelX, 0)
	end)
	button:SetScript("OnDisable", function(self)
		self:SetAlpha(0.35)
		ButtonUpdate(self, false)
	end)
	button:SetScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)

	function button:SetLabel(value)
		self.label:SetText(value)
	end

	return button
end

-- a round icon button without a frame, e.g. the close cross
function W.IconButton(parent, icon, size, color)
	local button = Adopt(parent, CreateFrame("Button", nil, Host(parent)))
	button:SetSize(size, size)
	button.icon = W.Texture(button, icon, "ARTWORK", color or C.muted)
	button.icon:SetAllPoints()
	button:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(unpack(C.text))
	end)
	button:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(unpack(color or C.muted))
	end)
	return button
end

-- toggle ---------------------------------------------------------------------

local TOGGLE_W, TOGGLE_H, KNOB = 40, 20, 14

local function ToggleApply(toggle, value)
	toggle.value = value
	-- a locked toggle (always installed) keeps its state but reads as not clickable
	local r, g, b = Mix(C.track, C.accent, toggle.locked and value * 0.4 or value)
	toggle.track:SetVertexColor(r, g, b, 1)
	if toggle.locked then
		toggle.knob:SetVertexColor(unpack(C.muted))
	else
		toggle.knob:SetVertexColor(Mix(C.text, C.onAccent, value))
	end
	toggle.knob:SetPoint("CENTER", toggle, "LEFT", TOGGLE_H / 2 + (TOGGLE_W - TOGGLE_H) * value, 0)
end

function W.Toggle(parent, onChange)
	local toggle = Adopt(parent, CreateFrame("Button", nil, Host(parent)))
	toggle:SetSize(TOGGLE_W, TOGGLE_H)

	toggle.track = W.Texture(toggle, Media.pill, "BACKGROUND")
	toggle.track:SetAllPoints()

	toggle.knob = W.Texture(toggle, Media.circle, "ARTWORK", C.text)
	toggle.knob:SetSize(KNOB, KNOB)

	function toggle:SetLocked(locked)
		self.locked = locked
		self:EnableMouse(not locked)
		ToggleApply(self, self.value or 0)
	end

	function toggle:SetChecked(checked, instant)
		self.checked = checked and true or false
		W.Tween(self, self.value or 0, self.checked and 1 or 0, instant and 0 or 0.2, function(value)
			ToggleApply(self, value)
		end)
	end

	function toggle:GetChecked()
		return self.checked
	end

	toggle:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if onChange then onChange(self.checked) end
	end)
	toggle:SetScript("OnDisable", function(self)
		self:SetAlpha(0.35)
	end)
	toggle:SetScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)

	toggle:SetChecked(false, true)
	return toggle
end

-- segmented switch -----------------------------------------------------------

-- options: list of { value, label }
function W.Segmented(parent, options, width, onChange)
	local control = W.Panel(parent, C.sidebar, C.border)
	local segment = (width - 4) / #options
	control:SetSize(width, 26)

	control.slider = W.Texture(control)
	control.slider:SetSize(segment, 22)
	W.Gradient(control.slider, "HORIZONTAL", C.accentA, 0.9, C.accentB, 0.9)

	control.buttons = {}
	for i, option in next, options do
		local button = Adopt(control, CreateFrame("Button", nil, control.host))
		button:SetSize(segment, 22)
		button:SetPoint("LEFT", 2 + (i - 1) * segment, 0)
		button.value = option[1]
		button.label = W.Text(button, 11, C.muted, true)
		button.label:SetPoint("CENTER")
		button.label:SetText(option[2])
		button:SetScript("OnClick", function()
			control:SetValue(option[1])
			if onChange then onChange(option[1]) end
		end)
		control.buttons[i] = button
	end

	function control:SetValue(value, instant)
		for i, button in next, self.buttons do
			local selected = button.value == value
			W.SetAccentText(button.label, selected)
			if selected then
				local target = 2 + (i - 1) * segment
				W.Tween(self, self.position or target, target, instant and 0 or 0.22, function(x)
					self.position = x
					self.slider:SetPoint("LEFT", x, 0)
				end)
			end
		end
	end

	control:SetValue(options[1][1], true)
	return control
end

-- pill / status --------------------------------------------------------------

function W.Pill(parent)
	local pill = W.Panel(parent, C.sidebar, C.border)
	pill:SetHeight(18)
	pill.text = W.Text(pill, 10, C.muted, true)
	pill.text:SetPoint("CENTER")

	function pill:SetStatus(text, color)
		self.text:SetText(text)
		self.text:SetTextColor(unpack(color))
		self:SetBackdropColor(color[1], color[2], color[3], 0.12)
		self:SetBackdropBorderColor(color[1], color[2], color[3], 0.6)
		self:SetWidth(self.text:GetStringWidth() + 16)
	end

	return pill
end

local STATUS_ICONS = {
	pending = { Media.ring, C.track },
	running = { Media.arc, C.accent },
	done = { Media.check, C.success },
	failed = { Media.cross, C.danger },
	skipped = { Media.ring, C.muted },
}

-- an invisible box holding two textures; the spinner rotates the icon texture itself
function W.StatusIcon(parent, size)
	local frame = W.Box(parent)
	frame:SetSize(size, size)
	frame.bg = W.Texture(frame, Media.circle, "ARTWORK")
	frame.bg:SetAllPoints()
	frame.icon = W.Texture(frame, Media.ring, "OVERLAY")
	frame.icon:SetAllPoints()

	frame.spin = frame.icon:CreateAnimationGroup()
	frame.spin:SetLooping("REPEAT")
	local rotation = frame.spin:CreateAnimation("Rotation")
	rotation:SetDegrees(-360)
	rotation:SetDuration(0.9)

	function frame:SetStatus(status)
		local info = STATUS_ICONS[status]
		W.SetShape(self.icon, info[1])
		self.icon:SetVertexColor(unpack(info[2]))
		local filled = status == "done" or status == "failed"
		self.bg:SetVertexColor(info[2][1], info[2][2], info[2][3], filled and 0.15 or 0)
		if status == "running" then
			self.spin:Play()
		else
			self.spin:Stop()
		end
	end

	frame:SetStatus("pending")
	return frame
end

-- celebration ----------------------------------------------------------------

local CONFETTI = 28

local RING_SCALE = 2.4
local BOUNDS_MARGIN = 12

-- free space from the center of a region to each edge of the bounds frame, nil before the layout is done
local function Space(center, bounds)
	local x, y = center:GetCenter()
	local left, right, top, bottom = bounds:GetLeft(), bounds:GetRight(), bounds:GetTop(), bounds:GetBottom()
	if not (x and left and right and top and bottom) then return end
	return x - left - BOUNDS_MARGIN, right - x - BOUNDS_MARGIN, top - y - BOUNDS_MARGIN, y - bottom - BOUNDS_MARGIN
end

-- one burst around a region: the region pops in, two rings ripple out and confetti flies off and falls.
-- Nothing leaves the bounds frame: the flight is shortened to fit and the client clips what is left.
-- Everything runs on animation groups, the client animates it without any Lua per frame.
function W.Celebration(parent, region, size, bounds)
	local celebration = { pop = {}, rings = {}, confetti = {} }
	local center = W.Anchor(region)
	bounds = bounds or parent

	-- the one frame of the burst, it only exists to clip rings and confetti to the bounds
	local host = CreateFrame("Frame", nil, Host(parent))
	host:SetPoint("TOPLEFT", bounds, "TOPLEFT", 1, -1)
	host:SetPoint("BOTTOMRIGHT", bounds, "BOTTOMRIGHT", -1, 1)
	host:SetClipsChildren(true)

	-- the region's own textures grow from small with a slight overshoot
	for _, tex in ipairs({ region.bg, region.icon }) do
		local group = tex:CreateAnimationGroup()
		local grow = group:CreateAnimation("Scale")
		grow:SetScaleFrom(0.3, 0.3)
		grow:SetScaleTo(1.12, 1.12)
		grow:SetDuration(0.6)
		grow:SetSmoothing("OUT")
		local settle = group:CreateAnimation("Scale")
		settle:SetScaleFrom(1.12, 1.12)
		settle:SetScaleTo(1, 1)
		settle:SetDuration(0.4)
		settle:SetSmoothing("IN_OUT")
		settle:SetOrder(2)
		tinsert(celebration.pop, group)
	end

	for i = 1, 2 do
		local ring = W.Texture(host, Media.ring, "ARTWORK", i == 1 and C.accentA or C.accentB, 0)
		ring:SetSize(size, size)
		ring:SetPoint("CENTER", center)
		ring:SetBlendMode("ADD")

		local group = ring:CreateAnimationGroup()
		group.ring, group.tint = ring, i == 1 and C.accentA or C.accentB
		group:SetToFinalAlpha(true)
		group.scale = group:CreateAnimation("Scale")
		group.scale:SetScaleFrom(0.9, 0.9)
		group.scale:SetScaleTo(RING_SCALE, RING_SCALE)
		group.scale:SetDuration(2.2)
		group.scale:SetSmoothing("OUT")
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.7)
		fade:SetToAlpha(0)
		fade:SetDuration(2.2)
		fade:SetSmoothing("IN")
		group.scale:SetStartDelay((i - 1) * 0.45)
		fade:SetStartDelay((i - 1) * 0.45)
		tinsert(celebration.rings, group)
	end

	for i = 1, CONFETTI do
		local round = i % 3 == 0
		local piece = W.Texture(host, round and Media.circle or Media.pill, "OVERLAY")
		piece:SetPoint("CENTER", center)
		piece:SetAlpha(0)

		local group = piece:CreateAnimationGroup()
		group:SetToFinalAlpha(true)
		group.fly = group:CreateAnimation("Translation")
		group.fly:SetSmoothing("OUT")
		group.fall = group:CreateAnimation("Translation")
		group.fall:SetSmoothing("IN")
		group.spin = group:CreateAnimation("Rotation")
		group.fade = group:CreateAnimation("Alpha")
		group.fade:SetFromAlpha(1)
		group.fade:SetToAlpha(0)
		group.fade:SetSmoothing("IN")
		group.piece, group.round = piece, round
		tinsert(celebration.confetti, group)
	end

	-- confetti is left out when something failed, the rings then take the warning color
	function celebration:Play(success, color)
		local left, right, up, down = Space(center, bounds)

		for _, group in ipairs(self.pop) do
			group:Stop()
			group:Play()
		end

		-- the rings grow at most until they touch the nearest edge
		local ringScale = RING_SCALE
		if left then ringScale = max(1, min(RING_SCALE, 2 * min(left, right, up, down) / size)) end
		for _, group in ipairs(self.rings) do
			local tint = success and group.tint or color
			group.ring:SetVertexColor(tint[1], tint[2], tint[3])
			group.scale:SetScaleTo(ringScale, ringScale)
			group:Stop()
			group:Play()
		end

		for i, group in ipairs(self.confetti) do
			group:Stop()
			group.piece:SetAlpha(success and 1 or 0)
			if success then
				-- an even spread with some jitter, pieces in the lower half fly less far
				local angle = (i / CONFETTI) * 2 * pi + (random() - 0.5) * 0.4
				local distance = 70 + random() * 90
				local x, y = cos(angle) * distance, sin(angle) * distance
				if y < 0 then y = y * 0.5 end
				local drop = -50 - random() * 40
				local duration = 2.4 + random() * 1.0

				-- shorten the flight along its direction so the piece stays inside, the drop ends at the bottom edge
				if left then
					local limit = 1
					if x ~= 0 then limit = min(limit, (x > 0 and right or left) / abs(x * 1.15)) end
					if y > 0 then limit = min(limit, up / y) elseif y < 0 then limit = min(limit, down / -y) end
					limit = max(limit, 0)
					x, y = x * limit, y * limit
					drop = max(drop, -down - y)
				end

				local piece = group.piece
				local width = 4 + random() * 3
				piece:SetSize(width, group.round and width or width * 2.2)
				piece:SetVertexColor(Mix(C.accentA, C.accentB, random()))

				group.fly:SetOffset(x, y)
				group.fly:SetDuration(duration * 0.55)
				group.fall:SetOffset(x * 0.15, min(drop, 0))
				group.fall:SetDuration(duration * 0.6)
				group.fall:SetStartDelay(duration * 0.4)
				group.spin:SetDegrees((random() - 0.5) * 720)
				group.spin:SetDuration(duration)
				group.fade:SetDuration(duration * 0.45)
				group.fade:SetStartDelay(duration * 0.55)
				group:Play()
			end
		end
	end

	return celebration
end

-- addon / module icon with a rounded backdrop
function W.Icon(parent, size, texture)
	local frame = W.Panel(parent, C.sidebar, C.border)
	frame:SetSize(size, size)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
	frame.icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

	function frame:SetIcon(value)
		self.icon:SetTexture(value or MaUI.Media.icon)
		-- game icons carry a dark frame that is cut away
		if type(value) == "number" or (type(value) == "string" and value:find("\\Icons\\")) then
			self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			self.icon:SetTexCoord(0, 1, 0, 1)
		end
	end

	frame:SetIcon(texture)
	return frame
end

-- selectable card ------------------------------------------------------------

function W.Card(parent, width, height, onClick)
	local card = Adopt(parent, CreateFrame("Button", nil, Host(parent), "BackdropTemplate"))
	card:SetSize(width, height)
	card:SetTemplate("Default", nil, true)
	W.SetPanelColors(card, C.surface, C.border)

	card.glow = W.Texture(card, Media.glow, "BACKGROUND", C.accent, 0)
	card.glow:SetPoint("CENTER", card, "TOP", 0, -10)
	card.glow:SetSize(width * 1.4, height)
	card.glow:SetBlendMode("ADD")

	card.badge = W.Texture(card, Media.circle, "OVERLAY", C.accent)
	card.badge:SetSize(22, 22)
	card.badge:SetPoint("TOPRIGHT", -10, -10)
	card.badgeIcon = W.Texture(card, Media.check, "OVERLAY", C.onAccent)
	card.badgeIcon:SetSize(16, 16)
	card.badgeIcon:SetPoint("CENTER", card.badge)
	card.badgeIcon:SetDrawLayer("OVERLAY", 2)

	local function Update(self)
		local target = (self.selected and 1) or (self.hovered and 0.35) or 0
		W.Tween(self, self.value or 0, target, 0.2, function(value)
			self.value = value
			local r, g, b = Mix(C.border, C.accent, value)
			self:SetBackdropBorderColor(r, g, b, 1)
			r, g, b = Mix(C.surface, C.surfaceHover, min(1, value * 2))
			self:SetBackdropColor(r, g, b, 1)
			self.glow:SetAlpha(value * 0.35)
			self.badge:SetAlpha(self.selected and value or 0)
			self.badgeIcon:SetAlpha(self.selected and value or 0)
		end)
	end

	function card:SetSelected(selected)
		self.selected = selected
		Update(self)
	end

	card:SetScript("OnEnter", function(self)
		self.hovered = true
		Update(self)
	end)
	card:SetScript("OnLeave", function(self)
		self.hovered = false
		Update(self)
	end)
	card:SetScript("OnClick", onClick)

	card:SetSelected(false)
	return card
end
