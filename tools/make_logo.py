"""Draws RankWarden's dragon-eye art:
  media/logo.png            400x400 CurseForge logo
  Textures/icon.tga         64x64 in-game icon (addon list, minimap button, HUD)

An amber-to-ember dragon iris with radial streaks and a razor slit pupil, set in
a dark scaled hide. Pure Python (zlib PNG + raw TGA writers), no dependencies.

Usage (from the addon root):  python tools/make_logo.py
"""

import math
import os
import struct
import zlib

C = 200  # the art is designed on a 400x400 canvas; other sizes are sampled from it

HIDE_DARK = (14, 10, 12)
HIDE = (52, 20, 18)
HIDE_EDGE = (96, 38, 26)
LID = (24, 14, 12)
LID_GOLD = (232, 162, 54)
IRIS_CORE = (255, 236, 120)
IRIS_MID = (246, 140, 26)
IRIS_EDGE = (150, 24, 10)
PUPIL = (6, 4, 4)
PUPIL_GLOW = (255, 92, 20)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def rounded_rect(px, py, r=72):
    qx = max(abs(px - C) - (C - r), 0)
    qy = max(abs(py - C) - (C - r), 0)
    return math.hypot(qx, qy) <= r


def scales(px, py):
    """Overlapping scale rows: 0 at a scale's edge, 1 at its centre."""
    row = math.floor(py / 26)
    ox = 15 if row % 2 else 0
    cx = math.floor((px - ox) / 30) * 30 + 15 + ox
    cy = row * 26 + 8
    d = math.hypot(px - cx, (py - cy) * 1.15)
    return max(0.0, 1 - d / 20)


# Eye: a sharp horizontal lens (two circles offset vertically).
LENS_R, LENS_OFF = 190, 122


def lens_sdf(px, py):
    d1 = math.hypot(px - C, py - (C - LENS_OFF)) - LENS_R
    d2 = math.hypot(px - C, py - (C + LENS_OFF)) - LENS_R
    return max(d1, d2)


def slit_sdf(px, py):
    """Razor-thin vertical slit pupil (a narrow tall lens)."""
    d1 = math.hypot(px - (C - 60), py - C) - 70
    d2 = math.hypot(px - (C + 60), py - C) - 70
    return max(d1, d2)


IRIS_R = 82


def sample(px, py):
    if not rounded_rect(px, py):
        return None
    r = math.hypot(px - C, py - C)

    # Scaled hide, darker towards the corners, warmer near the eye.
    s = scales(px, py)
    color = mix(HIDE_DARK, HIDE, s * (1 - min(1.0, r / 300)) + 0.15)
    if s < 0.08:
        color = mix(color, HIDE_EDGE, 0.5 * (1 - min(1.0, r / 260)))

    d = lens_sdf(px, py)
    if d < 0:
        # Iris fills the lens (dragon eyes are nearly all iris), clipped by the lids.
        t = r / IRIS_R
        color = mix(IRIS_CORE, IRIS_MID, t * 1.4) if t < 0.7 else mix(IRIS_MID, IRIS_EDGE, (t - 0.7) / 0.6)
        ang = math.atan2(py - C, px - C)
        streak = 0.5 + 0.5 * math.sin(ang * 46 + math.sin(ang * 7) * 2)
        color = mix(color, IRIS_EDGE, streak * 0.28 * min(1.0, t))
        sd = slit_sdf(px, py)
        if sd < 0:
            color = PUPIL
        elif sd < 7:
            color = mix(PUPIL_GLOW, color, sd / 7)
        if math.hypot(px - (C + 34), py - (C - 40)) <= 10:  # glint
            color = (255, 248, 220)
        # Lids shade the top and bottom of the iris.
        shade = max(0.0, 1 - (-d) / 28)
        color = mix(color, LID, shade * 0.75)
    if abs(d) <= 4:
        color = LID_GOLD
    elif 4 < d <= 15:
        color = LID
    return color


def render(size, ss):
    """Rows of RGBA pixels at `size`, sampled from the 400x400 design."""
    k = 400 / size
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            acc = [0.0, 0.0, 0.0]
            alpha = 0
            for sy in range(ss):
                for sx in range(ss):
                    c = sample((x + (sx + 0.5) / ss) * k, (y + (sy + 0.5) / ss) * k)
                    if c is not None:
                        alpha += 1
                        for i in range(3):
                            acc[i] += c[i]
            rgb = [int(round(v / alpha)) for v in acc] if alpha else [0, 0, 0]
            row.append((*rgb, int(round(255 * alpha / (ss * ss)))))
        rows.append(row)
    return rows


def write_png(path, rows):
    size = len(rows)
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def write_tga(path, rows):
    """Uncompressed 32-bit TGA, top-left origin (what WoW loads)."""
    size = len(rows)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = b"".join(bytes((b, g, r, a)) for row in rows for (r, g, b, a) in row)
    with open(path, "wb") as f:
        f.write(header + pixels)


if __name__ == "__main__":
    os.makedirs("media", exist_ok=True)
    os.makedirs("Textures", exist_ok=True)
    write_png("media/logo.png", render(400, 3))
    print("wrote media/logo.png")
    write_tga("Textures/icon.tga", render(64, 6))
    print("wrote Textures/icon.tga")
