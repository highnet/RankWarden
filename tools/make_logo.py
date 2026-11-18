"""Draws media/logo.png (400x400): a shield with three rank chevrons, the lowest
greyed out as the outdated rank. Pure Python (zlib PNG writer), no dependencies.

Usage (from the addon root):  python tools/make_logo.py
"""

import math
import os
import struct
import zlib

SIZE = 400
SS = 3  # supersampling per axis

BG = (20, 24, 33)
BG_GLOW = (38, 48, 72)
SHIELD = (30, 42, 68)
SHIELD_HI = (44, 60, 96)
GOLD = (236, 186, 74)
GOLD_DIM = (176, 132, 48)
GREY = (96, 102, 116)


def shield_points():
    pts = [(108, 72), (292, 72), (292, 220)]
    # curve down to the point at the bottom and back up
    for i in range(1, 20):
        t = i / 20
        x = 292 + (200 - 292) * t
        y = 220 + 124 * math.sin(t * math.pi / 2)
        pts.append((x, y))
    pts.append((200, 344))
    for i in range(19, 0, -1):
        t = i / 20
        x = 108 + (200 - 108) * t
        y = 220 + 124 * math.sin(t * math.pi / 2)
        pts.append((x, y))
    pts.append((108, 220))
    return pts


SHIELD_PTS = shield_points()
EDGES = list(zip(SHIELD_PTS, SHIELD_PTS[1:] + SHIELD_PTS[:1]))


def inside(px, py):
    hit = False
    for (x1, y1), (x2, y2) in EDGES:
        if (y1 > py) != (y2 > py):
            if px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
                hit = not hit
    return hit


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


def edge_dist(px, py):
    return min(seg_dist(px, py, x1, y1, x2, y2) for (x1, y1), (x2, y2) in EDGES)


def rounded_rect(px, py, r=64):
    # inside a rounded square covering the whole canvas
    qx = max(abs(px - SIZE / 2) - (SIZE / 2 - r), 0)
    qy = max(abs(py - SIZE / 2) - (SIZE / 2 - r), 0)
    return math.hypot(qx, qy) <= r


def chevron_dist(px, py, top):
    return min(seg_dist(px, py, 150, top + 40, 200, top), seg_dist(px, py, 200, top, 250, top + 40))


CHEVRONS = [(104, GOLD), (152, GOLD_DIM), (200, GREY)]


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def sample(px, py):
    if not rounded_rect(px, py):
        return None  # transparent corner
    d = math.hypot(px - 200, py - 150) / 300
    color = mix(BG_GLOW, BG, min(1.0, d))

    if inside(px, py):
        color = mix(SHIELD_HI, SHIELD, min(1.0, max(0.0, (py - 72) / 270)))
        for top, c in CHEVRONS:
            if chevron_dist(px, py, top) <= 11:
                color = c
    if edge_dist(px, py) <= 7:
        color = GOLD
    return color


def render():
    rows = []
    for y in range(SIZE):
        row = bytearray([0])  # filter: none
        for x in range(SIZE):
            acc = [0.0, 0.0, 0.0]
            alpha = 0
            for sy in range(SS):
                for sx in range(SS):
                    c = sample(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS)
                    if c is not None:
                        alpha += 1
                        for i in range(3):
                            acc[i] += c[i]
            if alpha:
                rgb = [int(round(v / alpha)) for v in acc]
            else:
                rgb = [0, 0, 0]
            row += bytes(rgb + [int(round(255 * alpha / (SS * SS)))])
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, raw):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    os.makedirs("media", exist_ok=True)
    write_png("media/logo.png", render())
    print("wrote media/logo.png")
