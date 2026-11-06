"""
Draws the small UI textures of the installer (white, tinted in game) as TGA files.

    python -I Installer/tools/media.py
"""

import math
import os
import re

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ElvUI_MaUI", "media"))
SS = 4  # supersampling per axis for anti-aliasing


def save_tga(name, grid):
    """grid: rows (top first) of 0..1 alpha values; writes a white 32 bit TGA with that alpha."""
    h, w = len(grid), len(grid[0])
    data = bytearray()
    for row in reversed(grid):  # TGA rows are stored bottom-up
        for a in row:
            data += bytes((255, 255, 255, round(255 * min(1, max(0, a)))))
    header = bytes((0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0)) + w.to_bytes(2, "little") + h.to_bytes(2, "little") + bytes((32, 8))
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(header + data)
    print("wrote", name)


def write_tga(name, size, alpha):
    """alpha(x, y) -> 0..1 in pixel space, supersampled."""
    w, h = size
    grid = []
    for y in range(h):
        row = []
        for x in range(w):
            a = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    a += alpha(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
            row.append(a / (SS * SS))
        grid.append(row)
    save_tga(name, grid)


# SVG path filling --------------------------------------------------------------

PATH_NUMBER = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
PATH_SEPARATOR = re.compile(r"[\s,]*")


class PathReader:
    """Reads SVG path data, including the compact forms like ".4.07" or arc flags written as "00"."""

    def __init__(self, d):
        self.d, self.pos = d, 0

    def skip(self):
        self.pos = PATH_SEPARATOR.match(self.d, self.pos).end()

    def done(self):
        self.skip()
        return self.pos >= len(self.d)

    def command(self):
        self.skip()
        if self.d[self.pos].isalpha():
            self.pos += 1
            return self.d[self.pos - 1]

    def num(self):
        self.skip()
        m = PATH_NUMBER.match(self.d, self.pos)
        self.pos = m.end()
        return float(m.group())

    def flag(self):
        self.skip()
        self.pos += 1
        return int(self.d[self.pos - 1])


def arc_points(x1, y1, rx, ry, phi, large, sweep, x2, y2, steps=48):
    """SVG elliptical arc (endpoint form) as a list of points, the start point excluded."""
    phi = math.radians(phi)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cos_p * dx + sin_p * dy, -sin_p * dx + cos_p * dy
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cos_p * cxp - sin_p * cyp + (x1 + x2) / 2
    cy = sin_p * cxp + cos_p * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi

    points = []
    for i in range(1, steps + 1):
        t = t1 + dt * i / steps
        x, y = rx * math.cos(t), ry * math.sin(t)
        points.append((cos_p * x - sin_p * y + cx, sin_p * x + cos_p * y + cy))
    return points


def path_polygons(d, steps=24):
    """Flattens an SVG path (M L H V C S A Z, absolute and relative) into polygons."""
    reader = PathReader(d)
    num = reader.num
    polygons, poly = [], []
    x = y = sx = sy = 0.0
    last_ctrl = None
    cmd = None

    def cubic(p0, p1, p2, p3):
        for k in range(1, steps + 1):
            t = k / steps
            mt = 1 - t
            poly.append((mt ** 3 * p0[0] + 3 * mt * mt * t * p1[0] + 3 * mt * t * t * p2[0] + t ** 3 * p3[0],
                         mt ** 3 * p0[1] + 3 * mt * mt * t * p1[1] + 3 * mt * t * t * p2[1] + t ** 3 * p3[1]))

    while not reader.done():
        cmd = reader.command() or cmd
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if c == "M":
            if poly:
                polygons.append(poly)
            x, y = num() + ox, num() + oy
            sx, sy = x, y
            poly = [(x, y)]
            cmd = "l" if rel else "L"  # further pairs are line segments
            last_ctrl = None
        elif c == "L":
            x, y = num() + ox, num() + oy
            poly.append((x, y))
            last_ctrl = None
        elif c == "H":
            x = num() + ox
            poly.append((x, y))
            last_ctrl = None
        elif c == "V":
            y = num() + oy
            poly.append((x, y))
            last_ctrl = None
        elif c in "CS":
            if c == "C":
                p1 = (num() + ox, num() + oy)
            else:
                p1 = (2 * x - last_ctrl[0], 2 * y - last_ctrl[1]) if last_ctrl else (x, y)
            p2 = (num() + ox, num() + oy)
            p3 = (num() + ox, num() + oy)
            cubic((x, y), p1, p2, p3)
            last_ctrl = p2
            x, y = p3
        elif c == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = reader.flag(), reader.flag()
            nx, ny = num() + ox, num() + oy
            poly.extend(arc_points(x, y, rx, ry, phi, int(large), int(sweep), nx, ny))
            x, y = nx, ny
            last_ctrl = None
        elif c == "Z":
            x, y = sx, sy
            polygons.append(poly)
            poly = []
            last_ctrl = None
        else:
            raise ValueError("unsupported path command " + cmd)
    if poly:
        polygons.append(poly)
    return polygons


def write_path_tga(name, d, view, size):
    """Fills an SVG path (even-odd) from the viewBox `view` = (x, y, w, h) into a size x size texture."""
    vx, vy, vw, vh = view
    scale = size / max(vw, vh)
    edges = []
    for poly in path_polygons(d):
        for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
            ax, ay, bx, by = (ax - vx) * scale, (ay - vy) * scale, (bx - vx) * scale, (by - vy) * scale
            if ay != by:
                edges.append((ax, ay, bx, by))

    grid = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for sub in range(SS):
            sy = row + (sub + 0.5) / SS
            xs = sorted(ax + (sy - ay) * (bx - ax) / (by - ay)
                        for ax, ay, bx, by in edges if (ay <= sy < by) or (by <= sy < ay))
            for left, right in zip(xs[0::2], xs[1::2]):
                # horizontal coverage of the span, also with sub pixel precision at both ends
                for px in range(max(0, int(left)), min(size, int(math.ceil(right)))):
                    cover = min(px + 1, right) - max(px, left)
                    if cover > 0:
                        grid[row][px] += cover / SS
    save_tga(name, grid)


# Discord logo mark from Simple Icons (CC0), 24 x 24 viewBox
DISCORD_MARK = (
    "M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495"
    "-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037"
    " 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578"
    "a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276"
    "c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923"
    "a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105"
    "c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924"
    "a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067"
    "c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294"
    "a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286z"
    "M8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952"
    " 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419"
    " 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"
)

# GitHub mark from GitHub's Octicons (MIT license), 16 x 16 viewBox
GITHUB_MARK = (
    "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49"
    "-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82"
    ".72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15"
    "-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82"
    ".44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2"
    " 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"
)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy)


def main():
    os.makedirs(OUT, exist_ok=True)
    c = 32

    # shapes are drawn in a 64 unit design space and rendered at 2x, the game scales them down with mipmaps
    def shape(name, size, alpha, scale=2):
        write_tga(name, (size[0] * scale, size[1] * scale), lambda x, y: alpha(x / scale, y / scale))

    shape("circle.tga", (64, 64), lambda x, y: 1 if math.hypot(x - c, y - c) <= 31 else 0)
    shape("ring.tga", (64, 64), lambda x, y: 1 if 26 <= math.hypot(x - c, y - c) <= 31 else 0)
    # capsule for the toggle track, one texture so a transparent toggle shows no seams
    shape("pill.tga", (64, 32), lambda x, y: 1 if seg_dist(x, y, 16, 16, 48, 16) <= 15.5 else 0)

    def arc(x, y):  # a quarter-open ring, rotated in game as loading spinner
        r = math.hypot(x - c, y - c)
        ang = math.degrees(math.atan2(y - c, x - c)) % 360
        return (1 if 25 <= r <= 31 else 0) * (ang / 270 if ang <= 270 else 0)
    shape("arc.tga", (64, 64), arc)

    shape("check.tga", (64, 64), lambda x, y: 1 if min(
        seg_dist(x, y, 14, 33, 27, 46), seg_dist(x, y, 27, 46, 51, 19)) <= 4.5 else 0)
    shape("cross.tga", (64, 64), lambda x, y: 1 if min(
        seg_dist(x, y, 18, 18, 46, 46), seg_dist(x, y, 46, 18, 18, 46)) <= 4.5 else 0)
    shape("arrow.tga", (64, 64), lambda x, y: 1 if min(
        seg_dist(x, y, 24, 14, 42, 32), seg_dist(x, y, 42, 32, 24, 50)) <= 4.5 else 0)
    # arrow pointing up, the "update available" sign
    shape("update.tga", (64, 64), lambda x, y: 1 if min(
        seg_dist(x, y, 32, 50, 32, 16), seg_dist(x, y, 17, 30, 32, 15), seg_dist(x, y, 47, 30, 32, 15)) <= 4.5 else 0)

    write_path_tga("github.tga", GITHUB_MARK, (0, 0, 16, 16), 128)
    write_path_tga("discord.tga", DISCORD_MARK, (0, 0, 24, 24), 128)

    write_tga("glow.tga", (128, 128), lambda x, y: max(0, 1 - math.hypot(x - 64, y - 64) / 64) ** 2)
    # horizontal fade 1 -> 0, used for highlights and separators
    write_tga("fade.tga", (128, 8), lambda x, y: 1 - x / 128)


if __name__ == "__main__":
    main()
