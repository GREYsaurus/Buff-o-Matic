"""Generate the Buff-o-Matic logo, in-game icon and CurseForge banner.

Original artwork drawn procedurally (no game assets): a holy-light shield inside a
golden cog (the "o-Matic" machine), on a royal-blue sunburst.

Usage:  python tools/make_logo.py            (requires Pillow)
Outputs:
  BuffOMatic/Media/icon.tga         64x64   in-game icon (TOC IconTexture, window, button)
  BuffOMatic/Media/logo256.tga      256x256 in-game large logo
  art/logo_1024.png                 master
  art/logo_400.png                  CurseForge project avatar
  art/banner_1280x400.png           CurseForge / GitHub banner
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 2048  # supersampled master
C = S / 2

GOLD = (242, 192, 55)
GOLD_LIGHT = (255, 232, 140)
GOLD_DARK = (122, 78, 8)
NAVY_IN = (46, 72, 160)
NAVY_OUT = (10, 16, 48)


def radial(size, inner, outer, center=None, radius=None):
    w, h = size
    cx, cy = center or (w / 2, h / 2)
    radius = radius or math.hypot(w, h) / 2
    grad = Image.new("RGB", (256, 1))
    for i in range(256):
        t = i / 255
        grad.putpixel((i, 0), tuple(int(inner[k] + (outer[k] - inner[k]) * t) for k in range(3)))
    # distance field
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            d = math.hypot((x + 0.5) / small * w - cx, (y + 0.5) / small * h - cy) / radius
            px[x, y] = grad.getpixel((min(255, int(d * 255)), 0))
    return img.resize(size, Image.BICUBIC)


def vertical(size, top, bottom):
    w, h = size
    img = Image.new("RGB", (1, 256))
    for i in range(256):
        t = i / 255
        img.putpixel((0, i), tuple(int(top[k] + (bottom[k] - top[k]) * t) for k in range(3)))
    return img.resize(size, Image.BICUBIC)


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=r, fill=255)
    return m


def gear_polygon(cx, cy, r_out, r_root, teeth, tooth_frac=0.46, steps=6):
    pts = []
    for t in range(teeth):
        base = 2 * math.pi * t / teeth
        span = 2 * math.pi / teeth
        a0 = base
        a1 = base + span * (1 - tooth_frac) / 2
        a2 = a1 + span * tooth_frac
        a3 = base + span
        # root arc
        for s in range(steps):
            a = a0 + (a1 - a0) * s / steps
            pts.append((cx + r_root * math.cos(a), cy + r_root * math.sin(a)))
        # flank up, tooth top (slightly narrower = trapezoid tooth)
        inset = span * tooth_frac * 0.12
        for s in range(steps + 1):
            a = (a1 + inset) + ((a2 - inset) - (a1 + inset)) * s / steps
            pts.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
        for s in range(steps):
            a = a2 + (a3 - a2) * s / steps
            pts.append((cx + r_root * math.cos(a), cy + r_root * math.sin(a)))
    return pts


def shield_polygon(cx, top, w, h, steps=60):
    """Heater shield: gently arched top, straight upper sides, curved taper to a point."""
    pts = []
    half = w / 2
    # arched top (left -> right)
    for i in range(steps + 1):
        x = -half + w * i / steps
        y = top + h * 0.035 * (1 - (x / half) ** 2) * -1 + h * 0.035
        pts.append((cx + x, y))
    # right side down to point
    for i in range(1, steps + 1):
        t = i / steps
        y = top + h * 0.035 + (h - h * 0.035) * t
        # straight-ish for first 35%, then curve to center
        if t < 0.35:
            x = half
        else:
            u = (t - 0.35) / 0.65
            x = half * math.cos(u * math.pi / 2) ** 0.85
        pts.append((cx + x, y))
    # left side back up
    for i in range(steps - 1, 0, -1):
        t = i / steps
        y = top + h * 0.035 + (h - h * 0.035) * t
        if t < 0.35:
            x = half
        else:
            u = (t - 0.35) / 0.65
            x = half * math.cos(u * math.pi / 2) ** 0.85
        pts.append((cx - x, y))
    return pts


def star_polygon(cx, cy, r_long, r_short, points=4, rot=-math.pi / 2, r_diag=None):
    pts = []
    n = points * 2
    for i in range(n):
        a = rot + math.pi * i / points
        if i % 2 == 0:
            r = r_long
        else:
            r = r_short
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def paste_shape(base, fill_img, polygon, blur=0):
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).polygon(polygon, fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(blur))
    base.paste(fill_img, (0, 0), mask)


def glow(base, polygon, color, radius, strength=1.0):
    layer = Image.new("RGBA", base.size, color + (0,))
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).polygon(polygon, fill=int(255 * strength))
    mask = mask.filter(ImageFilter.GaussianBlur(radius))
    layer.putalpha(mask)
    base.alpha_composite(layer)


def make_master():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    corner = int(S * 0.18)
    tile_mask = rounded_mask((S, S), corner)

    # background
    bg = radial((S, S), NAVY_IN, NAVY_OUT, radius=S * 0.72).convert("RGBA")
    # sunburst rays
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    n = 18
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + math.pi / n
        rd.polygon([(C, C), (C + S * math.cos(a0), C + S * math.sin(a0)), (C + S * math.cos(a1), C + S * math.sin(a1))],
                   fill=(255, 214, 110, 34))
    bg.alpha_composite(rays)
    img.paste(bg, (0, 0), tile_mask)

    # outer halo behind cog
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([C - S * 0.43, C - S * 0.43, C + S * 0.43, C + S * 0.43], fill=(255, 205, 90, 120))
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.04))
    img.alpha_composite(halo)

    # cog
    r_out, r_root, r_hole = S * 0.43, S * 0.365, S * 0.30
    gear = gear_polygon(C, C, r_out, r_root, teeth=12)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + S * 0.012, y + S * 0.018) for x, y in gear], fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.01))
    img.alpha_composite(shadow)
    paste_shape(img, vertical((S, S), GOLD_LIGHT, GOLD_DARK).convert("RGBA"), gear)
    # cog rim bevel lines
    d = ImageDraw.Draw(img)
    d.polygon(gear, outline=(90, 55, 5, 255), width=int(S * 0.008))
    # inner well
    well = radial((S, S), (28, 44, 110), (8, 12, 36), radius=r_hole).convert("RGBA")
    ring_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring_mask).ellipse([C - r_hole, C - r_hole, C + r_hole, C + r_hole], fill=255)
    img.paste(well, (0, 0), ring_mask)
    d.ellipse([C - r_hole, C - r_hole, C + r_hole, C + r_hole], outline=(255, 226, 130, 255), width=int(S * 0.014))
    d.ellipse([C - r_hole - S * 0.022, C - r_hole - S * 0.022, C + r_hole + S * 0.022, C + r_hole + S * 0.022],
              outline=(110, 70, 8, 255), width=int(S * 0.006))
    # rivets on the cog face
    for i in range(12):
        a = 2 * math.pi * (i + 0.5) / 12
        rx, ry = C + (r_root - S * 0.03) * math.cos(a), C + (r_root - S * 0.03) * math.sin(a)
        rr = S * 0.011
        d.ellipse([rx - rr, ry - rr, rx + rr, ry + rr], fill=(255, 240, 180, 255), outline=(110, 70, 8, 255), width=4)

    # shield
    sw, sh = S * 0.40, S * 0.47
    top = C - sh * 0.50
    shield = shield_polygon(C, top, sw, sh)
    glow(img, shield, (255, 220, 120), S * 0.03, 0.9)
    # gold border = bigger shield
    border = shield_polygon(C, top - S * 0.022, sw + S * 0.05, sh + S * 0.05)
    paste_shape(img, vertical((S, S), GOLD_LIGHT, GOLD_DARK).convert("RGBA"), border)
    paste_shape(img, vertical((S, S), (250, 251, 255), (150, 162, 190)).convert("RGBA"), shield)
    # shield center line highlight (left half lighter)
    left_half = [p for p in shield if p[0] <= C] + [(C, top + sh)]
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).polygon(left_half, fill=(255, 255, 255, 50))
    img.alpha_composite(hl)
    d = ImageDraw.Draw(img)
    d.line(border + [border[0]], fill=(90, 55, 5, 255), width=int(S * 0.006))

    # holy light emblem: radiant 4-point star with diagonal minor star
    ecx, ecy = C, top + sh * 0.43
    big = star_polygon(ecx, ecy, S * 0.165, S * 0.035)
    small = star_polygon(ecx, ecy, S * 0.085, S * 0.022, rot=-math.pi / 4)
    glow(img, big, (255, 200, 60), S * 0.035, 1.0)
    paste_shape(img, vertical((S, S), (255, 248, 200), (238, 160, 20)).convert("RGBA"), small)
    paste_shape(img, vertical((S, S), (255, 250, 215), (232, 150, 10)).convert("RGBA"), big)
    d = ImageDraw.Draw(img)
    d.polygon(big, outline=(140, 85, 5, 255), width=int(S * 0.005))
    core = S * 0.03
    d.ellipse([ecx - core, ecy - core, ecx + core, ecy + core], fill=(255, 255, 240, 255))

    # sparkles
    for (sx, sy, sr) in [(0.80, 0.20, 0.055), (0.20, 0.80, 0.04), (0.86, 0.74, 0.03), (0.15, 0.24, 0.028)]:
        sp = star_polygon(S * sx, S * sy, S * sr, S * sr * 0.22)
        glow(img, sp, (255, 240, 170), S * 0.012, 1.0)
        ImageDraw.Draw(img).polygon(sp, fill=(255, 250, 225, 255))

    # crisp tile edge
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([S * 0.006, S * 0.006, S * 0.994, S * 0.994], radius=corner,
                                           outline=(255, 210, 90, 255), width=int(S * 0.014))
    img.alpha_composite(edge)
    # final alpha = tile
    a = img.getchannel("A")
    img.putalpha(Image.composite(a, Image.new("L", (S, S), 0), tile_mask))
    return img


def save_tga(img, path, size):
    out = img.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path, format="TGA")  # 32-bit, uncompressed, bottom-left origin (WoW-safe)


def make_banner(master):
    W, H = 1280, 400
    banner = radial((W, H), (36, 58, 140), (8, 12, 36), center=(W * 0.3, H / 2), radius=W * 0.75).convert("RGBA")
    rays = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    cx, cy = 200, H / 2
    for i in range(24):
        a0 = 2 * math.pi * i / 24
        a1 = a0 + math.pi / 24
        rd.polygon([(cx, cy), (cx + 2000 * math.cos(a0), cy + 2000 * math.sin(a0)),
                    (cx + 2000 * math.cos(a1), cy + 2000 * math.sin(a1))], fill=(255, 214, 110, 18))
    banner.alpha_composite(rays)
    logo = master.resize((330, 330), Image.LANCZOS)
    banner.alpha_composite(logo, (35, 35))

    font_path = "C:/Windows/Fonts/georgiab.ttf"
    title = "BUFF-O-MATIC"
    tx, ty = 400, 92
    size = 118
    title_font = ImageFont.truetype(font_path, size)
    while title_font.getlength(title) > W - tx - 50 and size > 40:
        size -= 2
        title_font = ImageFont.truetype(font_path, size)
    ty = 92 + (118 - size) // 2
    sub_font = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 34)
    # gold gradient text with dark outline and soft glow
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).text((tx, ty), title, font=title_font, fill=255)
    glow_l = Image.new("RGBA", (W, H), (255, 200, 80, 0))
    glow_l.putalpha(mask.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.7)))
    banner.alpha_composite(glow_l)
    outline = Image.new("RGBA", (W, H), (60, 35, 0, 0))
    outline.putalpha(mask.filter(ImageFilter.MaxFilter(9)))
    banner.alpha_composite(outline)
    grad = vertical((W, H), (255, 246, 190), (214, 140, 10)).convert("RGBA")
    banner.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(banner)
    ty = 92
    d.text((tx + 6, ty + 150), "Smart paladin blessings for WoW Forever", font=sub_font, fill=(225, 230, 250, 255))
    d.text((tx + 6, ty + 198), "One click. Next player. Best blessing nobody else gave.", font=ImageFont.truetype(
        "C:/Windows/Fonts/georgia.ttf" if os.path.exists("C:/Windows/Fonts/georgia.ttf") else font_path, 26),
        fill=(170, 182, 220, 255))
    d.rectangle([0, 0, W - 1, H - 1], outline=(255, 210, 90, 255), width=4)
    return banner


def main():
    master = make_master()
    art = os.path.join(ROOT, "art")
    os.makedirs(art, exist_ok=True)
    master.resize((1024, 1024), Image.LANCZOS).save(os.path.join(art, "logo_1024.png"))
    master.resize((400, 400), Image.LANCZOS).save(os.path.join(art, "logo_400.png"))
    make_banner(master).convert("RGB").save(os.path.join(art, "banner_1280x400.png"))
    media = os.path.join(ROOT, "BuffOMatic", "Media")
    save_tga(master, os.path.join(media, "icon.tga"), 64)
    save_tga(master, os.path.join(media, "logo256.tga"), 256)
    # preview of the small icon for review
    master.resize((64, 64), Image.LANCZOS).resize((256, 256), Image.NEAREST).save(os.path.join(art, "icon64_preview.png"))
    print("ok")


if __name__ == "__main__":
    main()
