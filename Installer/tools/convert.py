"""
Converts the MaUI export strings in Profile/ into Lua data tables for the installer.

    python -I Installer/tools/convert.py [--savedvars <WTF/Account/<id>/SavedVariables/ElvUI.lua>]

Reads every known string from Profile/, decodes it the same way the addon that
exported it would, and writes Lua files to Installer/ElvUI_MaUI_Data/data/ (a LoadOnDemand addon) plus a small
index for the installer in Installer/ElvUI_MaUI/data/index.lua. With
--savedvars the ElvUI profile, private and global data come straight from
ElvUI's SavedVariables instead (profile names in SV_LAYOUTS / SV_PRIVATE).

The four ElvUI layouts are split into a shared base plus small per-layout
overrides, so a change to the common setup only has to be made once.
"""

import base64
import hashlib
import os
import re
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "Profile")
# the profile data lives in a LoadOnDemand addon, the installer only keeps a small index loaded
DATA_ADDON = os.path.join(ROOT, "Installer", "ElvUI_MaUI_Data")
OUT = os.path.join(DATA_ADDON, "data")
INDEX = os.path.join(ROOT, "Installer", "ElvUI_MaUI", "data", "index.lua")
MAIN_TOC = os.path.join(ROOT, "Installer", "ElvUI_MaUI", "ElvUI_MaUI.toc")


# ---------------------------------------------------------------------------
# decoders
# ---------------------------------------------------------------------------

def b64(text):
    text = re.sub(r"\s+", "", text)
    return base64.b64decode(text + "=" * (-len(text) % 4))


def inflate(data):
    for wbits in (-15, 15, 31):
        try:
            return zlib.decompress(data, wbits)
        except zlib.error:
            pass
    raise ValueError("cannot decompress")


PRINT_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
PRINT_MAP = {c: i for i, c in enumerate(PRINT_ALPHABET)}


def decode_for_print(text):
    """LibDeflate:DecodeForPrint"""
    text = re.sub(r"\s+", "", text)
    out = bytearray()
    cache, bits = 0, 0
    for ch in text:
        cache |= PRINT_MAP[ch] << bits
        bits += 6
        while bits >= 8:
            out.append(cache & 0xFF)
            cache >>= 8
            bits -= 8
    return bytes(out)


class CBOR:
    """Minimal CBOR reader for C_EncodingUtil.SerializeCBOR output."""

    def __init__(self, data):
        self.data, self.pos = data, 0

    def byte(self):
        b = self.data[self.pos]
        self.pos += 1
        return b

    def take(self, n):
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def arg(self, info):
        if info < 24:
            return info
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        return int.from_bytes(self.take(size), "big")

    def read(self):
        head = self.byte()
        major, info = head >> 5, head & 31
        if major == 0:
            return self.arg(info)
        if major == 1:
            return -1 - self.arg(info)
        if major in (2, 3):
            if info == 31:
                parts = []
                while self.data[self.pos] != 0xFF:
                    parts.append(self.read())
                self.pos += 1
                raw = b"".join(p if isinstance(p, bytes) else p.encode("utf-8", "surrogateescape") for p in parts)
            else:
                raw = self.take(self.arg(info))
            # Lua strings that are not valid UTF-8 arrive as byte strings; both are plain strings in Lua
            return raw.decode("utf-8", "surrogateescape")
        if major == 4:
            if info == 31:
                items = []
                while self.data[self.pos] != 0xFF:
                    items.append(self.read())
                self.pos += 1
            else:
                items = [self.read() for _ in range(self.arg(info))]
            return {i + 1: v for i, v in enumerate(items) if v is not None}
        if major == 5:
            result = {}
            count = None if info == 31 else self.arg(info)
            while (count is None and self.data[self.pos] != 0xFF) or (count is not None and len(result) < count):
                key = self.read()
                result[key] = self.read()
            if count is None:
                self.pos += 1
            return result
        if major == 6:
            self.arg(info)
            return self.read()
        if info == 20:
            return False
        if info == 21:
            return True
        if info in (22, 23):
            return None
        if info == 25:
            return struct.unpack(">e", self.take(2))[0]
        if info == 26:
            return struct.unpack(">f", self.take(4))[0]
        if info == 27:
            return struct.unpack(">d", self.take(8))[0]
        raise ValueError("unsupported CBOR item %d/%d" % (major, info))


def cbor(data):
    return CBOR(data).read()


class LibSerialize:
    """Reader for LibSerialize v1 (used by MaUI M+ Timer exports)."""

    def __init__(self, data):
        self.data, self.pos = data, 0
        self.strings, self.tables = [], []

    def take(self, n):
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def uint(self, n):
        return int.from_bytes(self.take(n), "big")

    def string(self, n):
        s = self.take(n).decode("utf-8", "surrogateescape")
        if n > 2:
            self.strings.append(s)
        return s

    def table(self, map_count, array_count):
        t = {}
        for i in range(array_count):
            t[i + 1] = self.read()
        for _ in range(map_count):
            k = self.read()
            t[k] = self.read()
        if len(t) > 2 or map_count + array_count > 2:
            self.tables.append(t)
        return t

    def read(self):
        b = self.uint(1)
        if b & 1:  # 7-bit number
            return b >> 1
        if b & 2:  # 4-bit typed item
            kind, count = (b & 0x0F) >> 2, b >> 4
            if kind == 0:
                return self.string(count)
            if kind == 1:
                return self.table(count, 0)
            if kind == 2:
                return self.table(0, count)
            return self.table(count, count) if False else self.mixed(count)
        if b & 4:  # 12-bit number
            n = ((b & 0xF0) << 4) + self.uint(1)
            return -n if b & 8 else n
        return self.typed(b >> 3)

    def mixed(self, packed):
        map_count, array_count = (packed >> 2) + 1, (packed & 3) + 1
        t = {}
        for i in range(array_count):
            t[i + 1] = self.read()
        for _ in range(map_count):
            k = self.read()
            t[k] = self.read()
        self.tables.append(t)
        return t

    def typed(self, kind):
        u = self.uint
        if kind == 0: return None
        if kind in (1, 2, 3, 4, 5, 6, 7, 8):  # ints 16/24/32/64, pos then neg
            sizes = {1: 2, 2: 2, 3: 3, 4: 3, 5: 4, 6: 4, 7: 7, 8: 7}
            n = u(sizes[kind])
            return -n if kind % 2 == 0 else n
        if kind == 9: return struct.unpack(">d", self.take(8))[0]
        if kind in (10, 11): return float(self.string(self.uint(1))) * (-1 if kind == 11 else 1)
        if kind == 12: return True
        if kind == 13: return False
        if kind in (14, 15, 16):
            return self.string(u({14: 1, 15: 2, 16: 3}[kind]))
        if kind in (17, 18, 19):
            return self.table(u({17: 1, 18: 2, 19: 3}[kind]), 0)
        if kind in (20, 21, 22):
            return self.table(0, u({20: 1, 21: 2, 22: 3}[kind]))
        if kind in (23, 24, 25):
            size = {23: 1, 24: 2, 25: 3}[kind]
            m, a = u(size), u(size)
            return self.table(m, a)
        if kind in (26, 27, 28):
            return self.strings[u({26: 1, 27: 2, 28: 3}[kind]) - 1]
        if kind in (29, 30, 31):
            return self.tables[u({29: 1, 30: 2, 31: 3}[kind]) - 1]
        raise ValueError("unsupported LibSerialize type %d" % kind)


def libserialize(data):
    reader = LibSerialize(data)
    if reader.uint(1) != 1:
        raise ValueError("unsupported LibSerialize version")
    return reader.read()


def split_export(raw):
    """Strips the trailing '::type[::key]' info ElvUI and mMT append to the CBOR payload."""
    m = re.match(rb"^(.*)::([^:]*)::([^:]*)$", raw, re.S)
    if m and m.group(2) == b"profile":
        return m.group(1), m.group(2).decode(), m.group(3).decode()
    m = re.match(rb"^(.*)::([^:]*)$", raw, re.S)
    return m.group(1), m.group(2).decode(), None


def decode(text):
    text = text.strip()
    if text.startswith("!E2!") or text.startswith("!mMT2!"):
        body, kind, key = split_export(inflate(b64(text.split("!", 2)[2])))
        return cbor(body), kind, key
    if text.startswith("BGR!1!"):
        return cbor(inflate(b64(text[6:]))), "baganator", None
    if text.startswith("D!ProfileV2-"):
        return cbor(inflate(b64(text[12:]))), "details", None
    m = re.match(r"^!MAUI:(\w+):(\d+)!(.+)$", text, re.S)
    if m:
        envelope = libserialize(inflate(decode_for_print(m.group(3))))
        return envelope["payload"], m.group(1), None
    raise ValueError("unknown export format")


# ---------------------------------------------------------------------------
# table helpers
# ---------------------------------------------------------------------------

def deep_equal(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(deep_equal(a[k], b[k]) for k in a)
    return type(a) == type(b) and a == b


def common(tables):
    """Keys whose value is identical in every table."""
    first, rest = tables[0], tables[1:]
    result = {}
    for k, v in first.items():
        if all(k in t for t in rest):
            if isinstance(v, dict) and all(isinstance(t[k], dict) for t in rest):
                sub = common([v] + [t[k] for t in rest])
                if sub:
                    result[k] = sub
            elif all(deep_equal(v, t[k]) for t in rest):
                result[k] = v
    return result


def subtract(table, base):
    """What `table` adds or changes on top of `base`."""
    result = {}
    for k, v in table.items():
        if k not in base:
            result[k] = v
        elif isinstance(v, dict) and isinstance(base[k], dict):
            sub = subtract(v, base[k])
            if sub:
                result[k] = sub
        elif not deep_equal(v, base[k]):
            result[k] = v
    return result


def missing(table, base):
    """Paths present in base but absent from table (a merge cannot express those)."""
    out = []
    for k, v in base.items():
        if k not in table:
            out.append([k])
        elif isinstance(v, dict) and isinstance(table[k], dict):
            out += [[k] + p for p in missing(table[k], v)]
    return out


# ---------------------------------------------------------------------------
# Lua writer
# ---------------------------------------------------------------------------

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
KEYWORDS = set("and break do else elseif end false for function goto if in local nil not or repeat return then true until while".split())


def lua_string(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\\": out.append("\\\\")
        elif ch == '"': out.append('\\"')
        elif ch == "\n": out.append("\\n")
        elif ch == "\r": out.append("\\r")
        elif ch == "\t": out.append("\\t")
        elif 0xDC80 <= o <= 0xDCFF: out.append("\\%d" % (o - 0xDC00))
        elif o < 32 or o == 127: out.append("\\%d" % o)
        else: out.append(ch)
    return '"' + "".join(out) + '"'


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v) and abs(v) < 2 ** 53:
            return str(int(v))
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    raise TypeError(type(v))


def lua_key(k):
    if isinstance(k, str) and IDENT.match(k) and k not in KEYWORDS:
        return k
    return "[" + lua_value(k) + "]"


def sort_key(k):
    return (0, k, "") if isinstance(k, (int, float)) and not isinstance(k, bool) else (1, 0, str(k))


def lua_table(t, indent=1):
    if not t:
        return "{}"
    pad = "\t" * indent
    keys = sorted(t.keys(), key=sort_key)
    is_list = keys == list(range(1, len(keys) + 1))
    lines = []
    for k in keys:
        v = t[k]
        text = lua_table(v, indent + 1) if isinstance(v, dict) else lua_value(v)
        lines.append(pad + (text if is_list else lua_key(k) + " = " + text) + ",")
    return "{\n" + "\n".join(lines) + "\n" + "\t" * (indent - 1) + "}"


HEADER = "-- Generated by Installer/tools/convert.py from %s - rerun the tool instead of editing by hand.\n"


def write(name, source, body):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER % source)
        f.write("local MaUI = unpack(ElvUI_MaUI)\n\n")
        f.write(body)
        f.write("\n")
    print("wrote", os.path.relpath(path, ROOT))


def register(module, key, table):
    return 'MaUI:RegisterData("%s", "%s", %s)' % (module, key, lua_table(table))


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def read(name):
    with open(os.path.join(SRC, name), encoding="utf-8") as f:
        return decode(f.read())[0]


LAYOUTS = {
    "tankdd": "elvui_profile_tank-dd.txt",
    "tankdd_cdm": "elvui_profile_tank-dd-cdm.txt",
    "heal": "elvui_profile_heal.txt",
    "heal_cdm": "elvui_profile_heal-cdm.txt",
}

# simple one-file modules: output file, module, key, source
SINGLES = [
    ("elvui/private.lua", "elvui", "private", "elvui_private.txt"),
    ("elvui/global.lua", "elvui", "global", "elvui_globale.txt"),
    ("mmt/datapanels.lua", "mmt", "datapanels", "mmt_datapanels.txt"),
    ("mmt/cdm.lua", "mmt", "cdm", "mmt_cdm.txt"),
    ("baganator/profile.lua", "baganator", "profile", "baganator_profile.txt"),
    ("baganator/categories.lua", "baganator", "categories", "baganator_category.txt"),
    ("details/profile.lua", "details", "profile", "details.txt"),
    ("mplustimer/profile.lua", "mplustimer", "profile", "maui_mplus_timer.txt"),
]

# Edit Mode layout per client: data key, source
EDIT_MODE = {
    "editmode": "blizzard.txt",
    "editmode_forever": "blizzard_forever.txt",
}


# profile names in ElvUI's SavedVariables, used with --savedvars
SV_LAYOUTS = {
    "tankdd": "MaUI v8.5 Tank/DD",
    "tankdd_cdm": "MaUI v8.5 Tank/DD CDM",
    "heal": "MaUI v8.5 Heal",
    "heal_cdm": "MaUI v8.5 Heal CDM",
}
SV_PRIVATE = "MaUI v8.5"

# ElvUI's D.blacklistedKeys plus keys that only describe the author's own character or setup
SV_STRIP = {
    "profile": {
        "gridSize": True, "gridLineWidth": True, "dbConverted": True, "layoutSetting": True,
        "general": {"cropIcon": True, "numberPrefixStyle": True},
        "chat": {"hideVoiceButtons": True},
        "bags": {"shownBags": True},
        "mMediaTag": {"premade_filter": True},
    },
    "private": {"install_complete": True, "MaUI": True, "UII": True},
    "global": {
        "profileCopy": True, "fontSlug": True,
        "general": {"AceGUI": True, "UIScale": True, "locale": True, "version": True, "eyefinity": True,
                    "ultrawide": True, "disableTutorialButtons": True, "allowDistributor": True},
        "chat": {"classColorMentionExcludedNames": True},
        "datatexts": {"newPanelInfo": True, "settings": {"Currencies": {"tooltipData": True}}},
    },
}


def strip(table, keys):
    for k, rule in keys.items():
        if k not in table:
            continue
        if rule is True:
            del table[k]
        elif isinstance(table[k], dict):
            strip(table[k], rule)
    return table


def from_savedvars(path):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # python -I leaves the script folder out
    import savedvars
    data = savedvars.load(path)
    profiles = data["ElvDB"]["profiles"]
    layouts = {k: strip(profiles[name], SV_STRIP["profile"]) for k, name in SV_LAYOUTS.items()}
    private = strip(data["ElvPrivateDB"]["profiles"][SV_PRIVATE], SV_STRIP["private"])
    glob = strip(data["ElvDB"]["global"], SV_STRIP["global"])
    return layouts, private, glob


# switched off data panels keep old datatext names (e.g. "mGameMenu" from earlier mMT versions);
# the panels stay off, only their slot assignments go
def clear_disabled_panels(profile):
    panels = profile.get("datatexts", {}).get("panels", {})
    for panel in panels.values():
        if isinstance(panel, dict) and panel.get("enable") is False:
            for slot in [k for k in panel if isinstance(k, int)]:
                del panel[slot]
    return profile


# per-module cleanup of decoded strings: drop what only belongs to the author
CLEANUP = {
    # Details maps every character of the exporting account to a profile
    "details": lambda t: strip(t, {"globaData": {"__char_profiles": True}}),
    # the M+ Timer envelope carries name and export meta next to the profile
    "mplustimer": lambda t: t["profile"],
}


def main():
    sv_path = sys.argv[sys.argv.index("--savedvars") + 1] if "--savedvars" in sys.argv else None
    if sv_path:
        layouts, private, glob = from_savedvars(sv_path)
        sources = {k: "SavedVariables " + v for k, v in SV_LAYOUTS.items()}
        write("elvui/private.lua", "SavedVariables " + SV_PRIVATE, register("elvui", "private", private))
        write("elvui/global.lua", "SavedVariables global", register("elvui", "global", glob))
    else:
        layouts = {k: read(v) for k, v in LAYOUTS.items()}
        sources = LAYOUTS

    for table in layouts.values():
        clear_disabled_panels(table)
    base = common(list(layouts.values()))
    write("elvui/base.lua", ", ".join(sources.values()), register("elvui", "base", base))
    for key, table in layouts.items():
        gaps = missing(table, base)
        if gaps:
            sys.exit("layout %s lacks base keys %s - cannot be expressed as an override" % (key, gaps[:5]))
        write("elvui/layout_%s.lua" % key, sources[key], register("elvui", key, subtract(table, base)))

    for out, module, key, source in SINGLES:
        if sv_path and module == "elvui":
            continue
        if os.path.exists(os.path.join(SRC, source)):
            table = read(source)
            write(out, source, register(module, key, CLEANUP.get(module, lambda t: t)(table)))

    # every client with Edit Mode has its own systems, so each one gets a layout exported there
    for key, source in EDIT_MODE.items():
        edit_mode = os.path.join(SRC, source)
        if os.path.exists(edit_mode):
            with open(edit_mode, encoding="utf-8") as f:
                write("blizzard/%s.lua" % key, source,
                      "-- Edit Mode layouts only exist as Blizzard's own string format.\n"
                      'MaUI:RegisterData("blizzard", "%s", %s)' % (key, lua_string(f.read().strip())))

    legacy_keys = write_legacy(layouts)
    write_index(base, legacy_keys)
    write_data_toc()


# ElvUI profiles of older MaUI releases, imported by hand from their strings. The installer updates them
# like its own installations, it only needs to know what they looked like: stored as the difference to
# the current layout, `set` holds the old values and `removed` the keys the old version did not have.
LEGACY = {
    "8": {"tankdd": "Archive/v8/elvui_profile.txt"},
    "8.5": {
        "tankdd": "Archive/v8.5/elvui_profile_tank-dd.txt",
        "tankdd_cdm": "Archive/v8.5/elvui_profile_tank-dd-cdm.txt",
        "heal": "Archive/v8.5/elvui_profile_heal.txt",
        "heal_cdm": "Archive/v8.5/elvui_profile_heal-cdm.txt",
    },
}


def nested(paths):
    result = {}
    for path in paths:
        node = result
        for key in path[:-1]:
            node = node.setdefault(key, {})
        node[path[-1]] = True
    return result


def write_legacy(layouts):
    keys = []
    for version, sources in LEGACY.items():
        blocks = []
        for layout, source in sources.items():
            with open(os.path.join(ROOT, source), encoding="utf-8") as f:
                old = decode(f.read())[0]
            current = layouts[layout]
            delta = {"set": subtract(old, current), "removed": nested(missing(old, current))}
            keys.append("%s/%s" % (version, layout))
            blocks.append(register("legacy", keys[-1], delta))
        write("legacy/v%s.lua" % version, ", ".join(sources.values()), "\n\n".join(blocks))
    return keys


# everything that ends up in the ElvUI profile and its global settings; a change here makes
# installed MaUI profiles outdated, so the installer offers an update
REVISION_FOLDERS = ("elvui", "mmt")


def revision():
    digest = hashlib.sha1()
    for folder in REVISION_FOLDERS:
        path = os.path.join(OUT, folder)
        for name in sorted(os.listdir(path)):
            with open(os.path.join(path, name), encoding="utf-8") as f:
                f.readline()  # the header only names the source
                digest.update(name.encode("utf-8"))
                digest.update(f.read().encode("utf-8"))
    return digest.hexdigest()[:12]


# what the installer needs without loading the data addon: the data revision for update checks,
# the old releases it can update and the profile colors its windows use
THEME_COLORS = ("backdropcolor", "backdropfadecolor", "bordercolor")


def write_index(base, legacy_keys):
    general = base.get("general", {})
    theme = {key: general[key] for key in THEME_COLORS if key in general}
    # the mMediaTag role icons the profile picked; the installer falls back to mMT's defaults for the rest
    role_settings = base.get("mMediaTag", {}).get("role_icons", {})
    roles = {key: role_settings[key] for key in ("tank", "heal", "dd") if key in role_settings}
    lines = [
        HEADER % "Installer/ElvUI_MaUI_Data/data",
        "local MaUI = unpack(ElvUI_MaUI)\n\n",
        'MaUI.DataRevision = "%s"\n' % revision(),
        "MaUI.LegacyKeys = %s\n" % lua_table({key: True for key in legacy_keys}),
        "MaUI.ThemeColors = %s\n" % lua_table(theme),
        "MaUI.RoleIcons = %s\n" % lua_table(roles),
    ]
    with open(INDEX, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(lines))
    print("wrote", os.path.relpath(INDEX, ROOT))


# the data addon's toc lists every generated file and shares the game versions of the installer
def write_data_toc():
    with open(MAIN_TOC, encoding="utf-8") as f:
        lines = [line.strip() for line in f]
    interface = next(line for line in lines if line.startswith("## Interface:"))
    # both addons ship together, the data addon carries the installer's version
    version = next(line for line in lines if line.startswith("## Version:"))
    category = [line for line in lines if line.startswith("## Category")]
    files = []
    for folder, _, names in os.walk(OUT):
        for name in sorted(names):
            files.append(os.path.relpath(os.path.join(folder, name), DATA_ADDON).replace("/", "\\"))
    lines = [
        interface,
        "## Title: |CFF29C0E3M|r|CFF5493FFa|r|CFF854FE3U|r|CFFA632E3I|r |CFFB8B8B8Installer Data|r",
        "## Notes: Profile data of the MaUI installer, only loaded while installing or updating.",
        "## Notes-deDE: Profildaten des MaUI-Installers, werden nur beim Installieren oder Aktualisieren geladen.",
        "## Author: Blinkii",
        version,
        "## IconTexture: Interface\\AddOns\\ElvUI_MaUI\\media\\icon",
        "## LoadOnDemand: 1",
        "## Dependencies: ElvUI_MaUI",
        # the addon list nests only one level, so it joins the installer in ElvUI's group, listed right below it
        "## Group: ElvUI",
    ] + category + [""] + sorted(files)
    path = os.path.join(DATA_ADDON, "ElvUI_MaUI_Data.toc")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
