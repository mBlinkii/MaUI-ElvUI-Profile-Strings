local MaUI, L, E = unpack(ElvUI_MaUI)
local Utils = MaUI.Utils
local W = MaUI.Widgets

local date, format, ipairs, tconcat, tinsert, floor = date, format, ipairs, table.concat, tinsert, math.floor

local C = MaUI.Colors
local Media = MaUI.Media

-- the MaUI entry in ElvUI's options: logo, version, the character's profile and its update.
-- Everything here comes from the index and the SavedVariables, opening it never loads the data addon.
-- Icons are texture escapes, so the white MaUI shapes can be tinted right inside the texts.

-- icons ------------------------------------------------------------------------

-- one of the white MaUI shapes (128 x 128), tinted
local function Shape(file, color, size)
	return format("|T%s:%d:%d:0:0:128:128:0:128:0:128:%d:%d:%d|t", file, size or 14, size or 14, floor(color[1] * 255), floor(color[2] * 255), floor(color[3] * 255))
end

-- the small accent dot in front of an information line
local function Dot()
	return Shape(Media.circle, C.accent, 8)
end

local STATUS = {
	current = { L["Up to date"], C.success, Media.check },
	outdated = { L["Update available"], C.warning, Media.update },
	old = { L["Too old for updates"], C.danger, Media.cross },
	unknown = { L["Unknown"], C.muted, Media.ring },
	none = { L["Not a MaUI profile"], C.muted, Media.ring },
}

local function StatusIcon(status, size)
	return Shape(STATUS[status][3], STATUS[status][2], size)
end

local function StatusText(status)
	return StatusIcon(status) .. " " .. Utils.Colorize(STATUS[status][1], STATUS[status][2])
end

-- "[tank][dps] Tank / DPS + CDM"
local function LayoutText(name)
	local key, cdm = MaUI:ProfileLayout(name)
	local layout = key and MaUI:GetLayout(key)
	if not layout then return Shape(Media.ring, C.muted) .. " " .. L["Unknown"] end

	local icons = ""
	for _, role in ipairs(layout.roles) do
		icons = icons .. W.RoleIconString(role, 16)
	end
	return icons .. "  " .. layout.name .. (cdm and Utils.Colorize("  + CDM", C.accent) or "")
end

local function Muted(text)
	return Utils.Colorize(text, C.muted)
end

-- a line with an icon, a label in the muted color and a value
local function Line(icon, label, value)
	return format("%s  %s  %s", icon, Muted(label), value)
end

-- the profile ---------------------------------------------------------------------

local function CurrentStatus()
	local name = E.data:GetCurrentProfile()
	for _, profile in ipairs(MaUI:FindProfiles()) do
		if profile.name == name then return profile.status end
	end
	return "none"
end

local function ProfileTitle()
	local name, status = E.data:GetCurrentProfile(), CurrentStatus()
	return format("%s  %s\n", StatusIcon(status, 18), Utils.Colorize(name, status == "none" and C.text or C.accent))
end

local function ProfileInfo()
	local name, status = E.data:GetCurrentProfile(), CurrentStatus()
	local lines = { Line(Dot(), L["Status"], StatusText(status)) }

	if status ~= "none" then
		tinsert(lines, Line(Dot(), L["Layout"], LayoutText(name)))

		local info, source = MaUI:GetProfileInfo(name), nil
		if info then
			source = format(L["v%s on %s"], info.version or "?", date("%d.%m.%Y", info.time or 0))
		else
			local legacy = MaUI:ParseProfileName(name)
			source = legacy and format(L["v%s, imported by hand"], legacy.version) or L["Unknown"]
		end
		tinsert(lines, Line(Dot(), L["Installed"], source))
	end

	local db = MaUIInstallerCharDB or {}
	local character = (db.installed and format(L["Installed on %s"], date("%d.%m.%Y", db.time or 0)))
		or (db.skipped and L["Installation skipped"])
		or L["Not set up yet"]
	tinsert(lines, Line(Dot(), L["This character"], character))

	return tconcat(lines, "\n\n") .. "\n"
end

-- ElvUI asks for the texts on every refresh, the preview is worked out once per profile until it is updated
local previews = {}

local function UpdateHint()
	local name = MaUI:CurrentProfileUpdate()
	if not name then return "" end

	if not previews[name] then
		local lines, total = MaUI:UpdateSummary(name)
		local bullet = Utils.Colorize("•", C.accent) .. "  "
		previews[name] = format("%s\n\n%s\n%s%s\n",
			Utils.Colorize(L["Only the settings MaUI changed are carried over, your own changes stay."], C.warning),
			format(L["What changes (%d settings):"], total),
			bullet, table.concat(lines, "\n" .. bullet))
	end
	return previews[name]
end

-- the account ---------------------------------------------------------------------

local function AccountProfiles()
	local found = MaUI:FindProfiles()
	if #found == 0 then return Muted(L["None"]) .. "\n" end

	local current = E.data:GetCurrentProfile()
	local lines = {}
	for _, profile in ipairs(found) do
		local name = profile.name == current and (Utils.Colorize(profile.name, C.accent) .. "  " .. Muted(L["(in use)"])) or profile.name
		tinsert(lines, format("%s  %s\n      %s     %s", StatusIcon(profile.status, 16), name, LayoutText(profile.name), StatusText(profile.status)))
	end
	return tconcat(lines, "\n\n") .. "\n"
end

-- options -------------------------------------------------------------------------

local function Execute(order, name, func, disabled, width)
	return { order = order, type = "execute", name = name, func = func, disabled = disabled, width = width }
end

-- a framed section with its title on the border
local function Group(order, name, args)
	return { order = order, type = "group", inline = true, name = name, args = args }
end

function MaUI:LoadOptions()
	MaUI:ApplyTheme()

	E.Options.args.MaUIInstaller = {
		order = 100,
		type = "group",
		name = MaUI.Title,
		args = {
			-- logo with the title and versions next to it
			hero = {
				order = 1,
				type = "description",
				fontSize = "large",
				image = Media.logo,
				imageWidth = 192,
				imageHeight = 96,
				width = "full",
				name = function()
					return format("%s %s\n\n%s\n%s\n\n%s",
						MaUI.Title, Muted(L["Installer"]),
						Line(Shape(Media.icon, C.text), L["Installer version"], MaUI.Version),
						Line(Shape(Media.check, C.success), L["MaUI profile"], "v" .. MaUI.ProfileVersion),
						Muted(L["Installs the MaUI layout and the matching addon profiles."]))
				end,
			},
			open = Execute(2, Shape(Media.arrow, C.text, 12) .. "  " .. L["Open installer"], function()
				E:ToggleOptions()
				MaUI:ShowInstaller()
			end, nil, 1.1),
			discord = Execute(3, Shape(Media.discord, C.text) .. "  " .. L["Discord"], function()
				MaUI:ShowURL(MaUI.Discord)
			end, nil, 0.8),
			github = Execute(4, Shape(Media.github, C.text) .. "  GitHub", function()
				MaUI:ShowURL(MaUI.GitHub)
			end, nil, 0.8),

			profile = Group(10, L["Your profile"], {
				title = { order = 1, type = "description", fontSize = "large", width = "full", name = ProfileTitle },
				info = { order = 2, type = "description", fontSize = "medium", width = "full", name = ProfileInfo },
				hint = { order = 3, type = "description", fontSize = "medium", width = "full", name = UpdateHint },
				-- the installer shows every change before it runs the update
				update = Execute(4, Shape(Media.update, C.text, 12) .. "  " .. L["Update profile"], function()
					local name = E.data:GetCurrentProfile()
					previews[name] = nil
					E:ToggleOptions()
					MaUI:ShowInstaller(name)
				end, function()
					return not MaUI:CurrentProfileUpdate()
				end, 1.1),
			}),

			account = Group(20, L["MaUI profiles on this account"], {
				list = { order = 1, type = "description", fontSize = "medium", width = "full", name = AccountProfiles },
			}),
		},
	}
end
