local MaUI, L, E = unpack(ElvUI_MaUI)

local _G = _G
local ipairs, type = ipairs, type

-- hands the installer's functions to FunctionProfiler (/fp) when that addon is installed; without it nothing happens.
-- Loaded last so every file has put its functions in place. Functions kept in locals at load time are not covered.
local Profiler = _G.NumyFunctionProfiler
if not Profiler then return end

local OWNER = MaUI.AddonName

Profiler:WrapModules(OWNER, "MaUI", MaUI)
Profiler:WrapModules(OWNER, "Installer", MaUI.Installer)
Profiler:WrapModules(OWNER, "Widgets", MaUI.Widgets)
Profiler:WrapModules(OWNER, "Utils", MaUI.Utils)

for _, module in ipairs(MaUI.Modules) do
	Profiler:WrapModules(OWNER, "Module:" .. module.key, module)
end

for index, page in ipairs(MaUI.Pages) do
	Profiler:WrapModules(OWNER, "Page:" .. (page.key or index), page)
end

-- only the handlers of the ElvUI module, its embedded Ace methods are not ours
local module = E:GetModule(OWNER)
for _, name in ipairs({ "Initialize", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
	if type(module[name]) == "function" then Profiler:WrapInPlace(OWNER, "Boot", module, name) end
end
