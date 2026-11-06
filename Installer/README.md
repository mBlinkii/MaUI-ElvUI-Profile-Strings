# ElvUI_MaUI – Installer

Eigenständiges Addon, das MaUI v8.5 mit einem eigenen Installationsfenster einrichtet: ElvUI-Profil (Tank/DD oder Heal, optional mit Cooldown Manager), mMediaTag, UI-Skalierung, Blizzard Edit Mode, Details!, Baganator und MaUI M+ Timer. Addon-Profile werden nur angeboten, wenn das Addon installiert und aktiv ist.

Öffnen im Spiel: automatisch beim ersten Login, sonst `/maui`, über das Addon-Kompartiment oder unter ElvUI → MaUI.

## Aufbau

```
ElvUI_MaUI/
  init.lua            Namespace, Farben, Media
  core/               Hilfsfunktionen, Modul-Registry + Install-Ablauf, Start
  modules/            ein Modul je Addon (elvui, mmt, uiscale, blizzard, details, baganator, mplustimer)
  data/index.lua      Daten-Revision, alte Versionen, Fensterfarben (generiert, immer geladen)
  ui/                 Widgets, Hauptfenster, Seiten
  locales/            deDE, esES/esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW (Englisch ist der Standard im Code)
  media/              Logo, Icons, generierte Texturen
ElvUI_MaUI_Data/      LoadOnDemand-Addon mit den Profilen als Lua-Tabellen (generiert, siehe unten)
  data/               elvui, mmt, details, baganator, mplustimer, blizzard, legacy
tools/
  convert.py          erzeugt ElvUI_MaUI_Data und data/index.lua aus Profile/*.txt oder ElvUIs SavedVariables
  savedvars.py        Leser für WoW-SavedVariables
  media.py            zeichnet die UI-Texturen (Kreis, Haken, Spinner, ...)
  logo.py             baut logo.tga und icon.tga aus Media/logo.png
  check.lua           lädt das Addon mit nachgebauter WoW-API und spielt die Installation durch
  locales.py          prüft die Sprachdateien auf fehlende/überflüssige Texte und Platzhalter
  package.py          baut das Zip für CurseForge (beide Addons)
```

Die vier ElvUI-Layouts sind in `ElvUI_MaUI_Data/data/elvui/base.lua` (alles Gemeinsame) und kleine Overrides `layout_*.lua` aufgeteilt. Bei der Installation wird Basis + Layout zusammengeführt. Bei aktivem CDM kommen die mMT-CDM-Einstellungen dazu (`modules/mmt.lua`).

Ein neues Addon-Profil braucht nur eine Datei in `modules/` (`MaUI:RegisterModule{...}`) und seine Daten in `ElvUI_MaUI_Data/data/`; die TOC des Daten-Addons schreibt `convert.py`.

### Speicher

- Die Profildaten stecken im LoadOnDemand-Addon `ElvUI_MaUI_Data`. `MaUI:GetData` lädt es beim ersten Zugriff, also erst wenn der Installer geöffnet oder ein Profil aktualisiert wird. Login, Update-Prüfung und Fensterfarben kommen mit `data/index.lua` aus.
- Die Kopien der installierten Profile in `MaUIInstallerDB` werden komprimiert gespeichert (`Utils.Pack`) und nur für ein Update entpackt.
- Nur klickbare Elemente sind Frames. Panels, Status-Pillen, Icons und Listenzeilen sind `W.Box`: Texturen auf dem Frame darüber. Seiten werden erst gebaut, wenn sie zum ersten Mal erscheinen.

## Profile aktualisieren

1. Profile im Spiel anpassen und `/reload` machen (damit die SavedVariables geschrieben werden).
2. Die Strings in `Profile/` aktualisieren (Details, Baganator, M+ Timer, mMT, Edit Mode). Den Edit-Mode-Layout gibt es pro Client: `blizzard.txt` aus Retail, `blizzard_forever.txt` aus Forever.
3. Daten neu erzeugen. Die ElvUI-Profile kommen direkt aus den SavedVariables, die Profilnamen stehen in `SV_LAYOUTS` / `SV_PRIVATE` in `convert.py`:

```bash
python -I Installer/tools/convert.py --savedvars "C:/Program Files (x86)/World of Warcraft/_retail_/WTF/Account/<ACCOUNT>/SavedVariables/ElvUI.lua"
```

`convert.py` schreibt dabei `data/revision.lua`, einen Hash über `data/elvui` und `data/mmt`. Ändert er sich, gelten installierte MaUI-Profile als veraltet: Spieler bekommen beim Login einen Update-Hinweis, und das Update übernimmt nur, was sich zwischen der alten und der neuen MaUI-Version geändert hat (`core/profiles.lua`). Dafür merkt sich der Installer in `MaUIInstallerDB` (account-weit), was er in jedes Profil geschrieben hat.

Profile, die Spieler früher von Hand aus den Strings importiert haben (z. B. „MaUI v8.5 Heal CDM“), erkennt der Installer am Namen und kann sie ebenfalls aktualisieren. Dafür erzeugt `convert.py` aus den archivierten Strings unter `data/legacy/` den damaligen Stand, gespeichert nur als Unterschied zum aktuellen Layout. Welche Versionen das sind, steht in `LEGACY` in `convert.py`. Profile vor v8 werden angezeigt, aber nicht aktualisiert.

Vor einem neuen Release: die ElvUI-Strings der bisherigen Version nach `Archive/v<Version>/` kopieren und in `LEGACY` eintragen, damit Spieler mit diesen Strings später aktualisieren können.

Ohne `--savedvars` werden auch die ElvUI-Daten aus den Strings in `Profile/` gelesen. Persönliche Einstellungen (Grid, Premade-Filter, alte Installer-Flags, Details-Charakterzuordnung, ElvUIs eigene Export-Blacklist) werden automatisch entfernt.

## Prüfen und veröffentlichen

```bash
lua5.1 Installer/tools/check.lua
```

```bash
python -I Installer/tools/locales.py
```

Neue Texte im Code schreibst du auf Englisch als `L["..."]`. `locales.py` zeigt danach an, welche Übersetzungen in welcher Sprachdatei fehlen.

```bash
python -I Installer/tools/package.py 1.0.0
```

Das Zip landet in `Installer/dist/` und kann direkt auf CurseForge hochgeladen werden. Nach dem Anlegen des CurseForge-Projekts kommt die Projekt-ID als `## X-Curse-Project-ID:` in die TOC.
