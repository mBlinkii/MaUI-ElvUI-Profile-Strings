# ElvUI_MaUI – Installer (Development)

Standalone addon that sets up MaUI v8.5 through its own installation window: ElvUI profile (Tank/DPS or Heal, optionally with Cooldown Manager), mMediaTag, UI scale, Blizzard Edit Mode, Details!, Baganator and MaUI M+ Timer. Addon profiles are only offered when the addon is installed and enabled.

Opening in game: automatically on first login, otherwise via `/maui`, the addon compartment, or under ElvUI → MaUI.

## Structure

```
ElvUI_MaUI/
  init.lua            namespace, colors, media
  core/               helpers, module registry + install flow, startup
  modules/            one module per addon (elvui, mmt, uiscale, blizzard, details, baganator, mplustimer)
  data/index.lua      data revision, old versions, window colors (generated, always loaded)
  ui/                 widgets, main window, pages
  locales/            deDE, esES/esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW (English is the default in code)
  media/              logo, icons, generated textures
ElvUI_MaUI_Data/      LoadOnDemand addon holding the profiles as Lua tables (generated, see below)
  data/               elvui, mmt, details, baganator, mplustimer, blizzard, legacy
tools/
  convert.py          generates ElvUI_MaUI_Data and data/index.lua from Profile/*.txt or ElvUI's SavedVariables
  savedvars.py        reader for WoW SavedVariables
  media.py            draws the UI textures (circle, check mark, spinner, ...)
  logo.py             builds logo.tga and icon.tga from Media/logo.png
  check.lua           loads the addon against a mocked WoW API and runs through the installation
  locales.py          checks the locale files for missing/extra strings and placeholders
  package.py          builds the zip for CurseForge (both addons)
```

The four ElvUI layouts are split into `ElvUI_MaUI_Data/data/elvui/base.lua` (everything shared) and small `layout_*.lua` overrides. During installation, base + layout are merged. With CDM enabled, the mMT CDM settings are added on top (`modules/mmt.lua`).

A new addon profile only needs one file in `modules/` (`MaUI:RegisterModule{...}`) and its data in `ElvUI_MaUI_Data/data/`; `convert.py` writes the data addon's TOC.

### Memory

- The profile data lives in the LoadOnDemand addon `ElvUI_MaUI_Data`. `MaUI:GetData` loads it on first access, i.e. only when the installer is opened or a profile is updated. Login, update check and window colors only need `data/index.lua`.
- The copies of installed profiles in `MaUIInstallerDB` are stored compressed (`Utils.Pack`) and only unpacked for an update.
- Only clickable elements are frames. Panels, status pills, icons and list rows are `W.Box`: textures on the frame above them. Pages are only built the first time they are shown.

## Updating profiles

1. Adjust the profiles in game and `/reload` (so the SavedVariables get written).
2. Update the strings in `Profile/` (Details, Baganator, M+ Timer, mMT, Edit Mode). The Edit Mode layout exists per client: `blizzard.txt` from Retail, `blizzard_forever.txt` from Forever.
3. Regenerate the data. The ElvUI profiles come straight from the SavedVariables; the profile names are set in `SV_LAYOUTS` / `SV_PRIVATE` in `convert.py`:

```bash
python -I Installer/tools/convert.py --savedvars "C:/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/ElvUI.lua"
```

`convert.py` also writes `data/revision.lua`, a hash over `data/elvui` and `data/mmt`. When it changes, installed MaUI profiles are considered outdated: players get an update notice on login, and the update only applies what changed between the old and the new MaUI version (`core/profiles.lua`). For this, the installer remembers in `MaUIInstallerDB` (account-wide) what it wrote into each profile.

Profiles that players previously imported by hand from the strings (e.g. "MaUI v8.5 Heal CDM") are recognized by name and can be updated as well. For this, `convert.py` generates the state of that time from the archived strings under `data/legacy/`, stored only as a diff against the current layout. Which versions these are is defined in `LEGACY` in `convert.py`. Profiles older than v8 are shown but not updated.

Before a new release: copy the ElvUI strings of the previous version to `Archive/v<version>/` and add them to `LEGACY`, so players with those strings can update later.

Without `--savedvars`, the ElvUI data is also read from the strings in `Profile/`. Personal settings (Grid, premade filters, old installer flags, Details character assignment, ElvUI's own export blacklist) are removed automatically.

## Checking and publishing

```bash
lua5.1 Installer/tools/check.lua
```

```bash
python -I Installer/tools/locales.py
```

Write new strings in code in English as `L["..."]`. `locales.py` then shows which translations are missing in which locale file.

```bash
python -I Installer/tools/package.py 1.0.0
```

The zip ends up in `Installer/dist/` and can be uploaded to CurseForge directly. Once the CurseForge project has been created, its project ID goes into the TOC as `## X-Curse-Project-ID:`.
