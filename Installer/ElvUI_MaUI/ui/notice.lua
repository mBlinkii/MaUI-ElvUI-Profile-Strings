local MaUI, L, E = unpack(ElvUI_MaUI)
local W = MaUI.Widgets
local Utils = MaUI.Utils

local _G = _G
local format, max = format, math.max
local CreateFrame = CreateFrame

local C = MaUI.Colors
local Media = MaUI.Media

-- a small window that tells about an update for the character's MaUI profile, the update itself runs in the installer

local notice

local function Create()
	MaUI:ApplyTheme()

	notice = CreateFrame("Frame", "MaUIUpdateNotice", E.UIParent, "BackdropTemplate")
	notice:SetSize(400, 132)
	notice:SetPoint("TOP", 0, -140)
	notice:SetFrameStrata("DIALOG")
	notice:SetTemplate("Default", nil, true)
	W.SetPanelColors(notice, C.background, C.border, 0.92)
	notice:CreateShadow(10)
	notice.shadow:SetBackdropBorderColor(0, 0, 0, 0.7)

	local line = notice:CreateTexture(nil, "OVERLAY")
	W.Gradient(line, "HORIZONTAL", C.accentA, 1, C.accentB, 1)
	line:SetPoint("TOPLEFT", 1, -1)
	line:SetPoint("TOPRIGHT", -1, -1)
	line:SetHeight(2)

	local icon = W.Texture(notice, Media.icon, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 16, -16)

	notice.title = W.Text(notice, 15, C.text, true)
	notice.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -1)

	notice.text = W.Text(notice, 12, C.muted)
	notice.text:SetPoint("TOPLEFT", notice.title, "BOTTOMLEFT", 0, -6)
	notice.text:SetWidth(320)
	notice.text:SetSpacing(2)

	notice.primary = W.Button(notice, "", "primary", 150, 30)
	notice.primary:SetPoint("BOTTOMRIGHT", -14, 14)

	notice.later = W.Button(notice, L["Later"], "secondary", 100, 30)
	notice.later:SetPoint("RIGHT", notice.primary, "LEFT", -8, 0)
	notice.later:SetScript("OnClick", function()
		notice:Hide()
	end)
end

-- the window grows with its text, the buttons stay at the bottom
local function Fit()
	notice:SetHeight(max(132, notice.text:GetStringHeight() + 96))
end

function MaUI:ShowUpdateNotice(name)
	if not notice then Create() end

	-- tell what is going to change, per ElvUI area
	local lines, total = MaUI:UpdateSummary(name, 6)
	local text = format(L["MaUI has new settings for your profile \"%s\". Only what MaUI changed is carried over, your own changes stay."], name)
	if total > 0 then
		local bullet = Utils.Colorize("•", C.accent) .. "  "
		text = text .. "\n\n" .. Utils.Colorize(format(L["What changes (%d settings):"], total), C.text) .. "\n" .. bullet .. table.concat(lines, "\n" .. bullet)
	end

	notice.title:SetText(L["Profile update available"])
	notice.text:SetText(text)
	Fit()
	notice.primary:SetLabel(L["Show update"])
	notice.primary:SetScript("OnClick", function()
		notice:Hide()
		MaUI:ShowInstaller(name)
	end)

	notice:Show()
	W.Reveal(notice, 0, 10)
end
