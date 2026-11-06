"""
Builds the installer's logo and addon icon from the MaUI logo, with the standard library only.

    python -I Installer/tools/logo.py

Reads Media/logo.png (RGBA) and writes Installer/ElvUI_MaUI/media/logo.tga (512 x 256, the wordmark
trimmed and centered) and icon.tga (128 x 128, "Ma" over "UI" on a dark rounded tile, so it stays
readable at the 16 px of the addon list), plus PNG previews of both into Installer/dist.
"""

import os
import struct
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCE = os.path.join(ROOT, "Media", "logo.png")
MEDIA = os.path.join(ROOT, "Installer", "ElvUI_MaUI", "media")
PREVIEW = os.path.join(ROOT, "Installer", "dist")


# png ---------------------------------------------------------------------------------

def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos, idat = 8, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and color == 6 and interlace == 0, "only 8 bit RGBA without interlace"
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length

    raw, stride = zlib.decompress(idat), width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    # premultiplied floats make the downscale free of dark or light fringes
    pixels = []
    for line in rows:
        row = []
        for x in range(width):
            r, g, b, a = line[x * 4:x * 4 + 4]
            f = a / 255
            row.append((r * f, g * f, b * f, a))
        pixels.append(row)
    return width, height, pixels


def write_png(path, width, height, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes(Unpremultiply(r, g, b, a))
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


# image helpers -------------------------------------------------------------------------

def Unpremultiply(r, g, b, a):
    if a <= 0:
        return 0, 0, 0, 0
    f = 255 / a
    return (min(255, round(r * f)), min(255, round(g * f)), min(255, round(b * f)), min(255, round(a)))


def bbox(width, height, pixels, threshold=8):
    xs = [x for y in range(height) for x in range(width) if pixels[y][x][3] > threshold]
    ys = [y for y in range(height) for x in range(width) if pixels[y][x][3] > threshold]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def resize(pixels, box, out_w, out_h):
    """area average of the box into out_w x out_h"""
    x0, y0, x1, y1 = box
    sx, sy = (x1 - x0) / out_w, (y1 - y0) / out_h
    out = []
    for oy in range(out_h):
        fy0, fy1 = y0 + oy * sy, y0 + (oy + 1) * sy
        row = []
        for ox in range(out_w):
            fx0, fx1 = x0 + ox * sx, x0 + (ox + 1) * sx
            acc, total = [0.0, 0.0, 0.0, 0.0], 0.0
            y = int(fy0)
            while y < fy1:
                wy = min(fy1, y + 1) - max(fy0, y)
                x = int(fx0)
                while x < fx1:
                    w = (min(fx1, x + 1) - max(fx0, x)) * wy
                    p = pixels[y][x]
                    for i in range(4):
                        acc[i] += p[i] * w
                    total += w
                    x += 1
                y += 1
            row.append(tuple(v / total for v in acc))
        out.append(row)
    return out


def canvas(width, height, color=(0, 0, 0, 0)):
    return [[color] * width for _ in range(height)]


def paste(target, image, left, top):
    """source over, both premultiplied"""
    for y, row in enumerate(image):
        for x, (r, g, b, a) in enumerate(row):
            tr, tg, tb, ta = target[top + y][left + x]
            k = 1 - a / 255
            target[top + y][left + x] = (r + tr * k, g + tg * k, b + tb * k, a + ta * k)


def fit(pixels, box, max_w, max_h):
    x0, y0, x1, y1 = box
    scale = min(max_w / (x1 - x0), max_h / (y1 - y0))
    w, h = max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))
    return resize(pixels, box, w, h), w, h


# the italic letters part along a slanted line: x = SPLIT_X + SPLIT_SLOPE * (SPLIT_Y - y), found by
# searching the line that crosses no letter pixel; the letters end above the underline at LETTERS_BOTTOM
SPLIT_X, SPLIT_Y, SPLIT_SLOPE = 734, 350, 0.12
LETTERS_BOTTOM = 492


def split_letters(width, pixels, box):
    """the wordmark without its underline as two images: "Ma" and "UI", each with its bounding box"""
    x0, y0, x1, _ = box
    left, right = [], []
    for y in range(y0, LETTERS_BOTTOM):
        cut = SPLIT_X + SPLIT_SLOPE * (SPLIT_Y - y)
        left.append([p if x < cut else (0, 0, 0, 0) for x, p in enumerate(pixels[y])])
        right.append([p if x >= cut else (0, 0, 0, 0) for x, p in enumerate(pixels[y])])
    height = LETTERS_BOTTOM - y0
    return [(part, bbox(width, height, part)) for part in (left, right)]


def rounded_tile(size, radius, color, inset=0):
    """a premultiplied rounded square with an anti aliased edge"""
    r, g, b, a = color
    tile = canvas(size, size)
    lo, hi = inset, size - inset
    for y in range(size):
        for x in range(size):
            cx = min(max(x + 0.5, lo + radius), hi - radius)
            cy = min(max(y + 0.5, lo + radius), hi - radius)
            dist = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
            cover = max(0.0, min(1.0, radius - dist + 0.5))
            if lo <= x < hi and lo <= y < hi and cover > 0:
                f = a / 255 * cover
                tile[y][x] = (r * f, g * f, b * f, 255 * f)
    return tile


# tga -----------------------------------------------------------------------------------

def write_tga(path, width, height, pixels):
    """32 bit, run length encoded, top left origin"""
    body = bytearray()
    for row in pixels:
        line = [bytes((b, g, r, a)) for r, g, b, a in (Unpremultiply(*p) for p in row)]
        x = 0
        while x < width:
            run = 1
            while x + run < width and run < 128 and line[x + run] == line[x]:
                run += 1
            if run > 1:
                body.append(0x80 | (run - 1))
                body += line[x]
                x += run
                continue
            start = x
            while x < width and x - start < 128 and (x + 1 >= width or line[x + 1] != line[x]):
                x += 1
            body.append(x - start - 1)
            for p in line[start:x]:
                body += p
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 10, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header + body)


def main():
    width, height, pixels = read_png(SOURCE)
    box = bbox(width, height, pixels)
    print("source %dx%d, logo bbox %s" % (width, height, box))

    # logo: the wordmark centered on 512 x 256 with a little room around it
    logo = canvas(512, 256)
    image, w, h = fit(pixels, box, 496, 240)
    paste(logo, image, (512 - w) // 2, (256 - h) // 2)
    write_tga(os.path.join(MEDIA, "logo.tga"), 512, 256, logo)

    # icon: "Ma" over "UI" on a dark rounded tile, both lines in the same scale
    icon = rounded_tile(128, 22, (18, 20, 26, 255), inset=2)
    parts = split_letters(width, pixels, box)
    gap = 6
    widest = max(b[2] - b[0] for _, b in parts)
    tallest = sum(b[3] - b[1] for _, b in parts)
    scale = min(100 / widest, (100 - gap) / tallest)
    sizes = [(max(1, round((b[2] - b[0]) * scale)), max(1, round((b[3] - b[1]) * scale))) for _, b in parts]
    top = (128 - (sizes[0][1] + gap + sizes[1][1])) // 2
    for (part, b), (w, h) in zip(parts, sizes):
        paste(icon, resize(part, b, w, h), (128 - w) // 2, top)
        top += h + gap
    write_tga(os.path.join(MEDIA, "icon.tga"), 128, 128, icon)

    os.makedirs(PREVIEW, exist_ok=True)
    write_png(os.path.join(PREVIEW, "logo_preview.png"), 512, 256, logo)
    write_png(os.path.join(PREVIEW, "icon_preview.png"), 128, 128, icon)
    print("wrote logo.tga, icon.tga and previews in Installer/dist")


if __name__ == "__main__":
    main()
