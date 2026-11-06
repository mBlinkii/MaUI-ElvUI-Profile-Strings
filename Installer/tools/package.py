"""
Builds the CurseForge upload zip for ElvUI_MaUI and its LoadOnDemand data addon ElvUI_MaUI_Data.

    python -I Installer/tools/package.py 1.0.0

Writes Installer/dist/ElvUI_MaUI-<version>.zip with both addon folders at the zip root
and the version filled into the tocs, the same layout the CurseForge packager produces.
"""

import os
import sys
import zipfile

ADDON = "ElvUI_MaUI"
FOLDERS = (ADDON, ADDON + "_Data")
HERE = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(HERE, "..", "dist")


def toc_version():
    with open(os.path.join(HERE, "..", "ElvUI_MaUI", "ElvUI_MaUI.toc"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("## Version:"):
                return line.split(":", 1)[1].strip()
    sys.exit("ElvUI_MaUI.toc has no version")


def main():
    if len(sys.argv) > 2:
        sys.exit("usage: package.py [version]")
    # without an argument the version in ElvUI_MaUI.toc is used
    version = sys.argv[1] if len(sys.argv) == 2 else toc_version()

    os.makedirs(DIST, exist_ok=True)
    target = os.path.join(DIST, "%s-%s.zip" % (ADDON, version))
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as zf:
        for addon in FOLDERS:
            src = os.path.join(HERE, "..", addon)
            for folder, _, files in os.walk(src):
                for name in sorted(files):
                    path = os.path.join(folder, name)
                    arcname = os.path.join(addon, os.path.relpath(path, src)).replace(os.sep, "/")
                    if name.endswith(".toc"):
                        with open(path, encoding="utf-8") as f:
                            zf.writestr(arcname, f.read().replace("@project-version@", version))
                    else:
                        zf.write(path, arcname)
    print("wrote", os.path.relpath(target, os.getcwd()))


if __name__ == "__main__":
    main()
