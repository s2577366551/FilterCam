#!/usr/bin/env python3
"""同一套拍立得风格，换不同的相框内照片。输出 6 个方案 + 对比图。"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
OUT_DIR = os.path.join("build", "icons", "variants")


# ---------- 基础工具 ----------

def vgrad(w, h, stops):
    """竖向渐变。stops: [(t, (r,g,b)), ...]，t 从 0(顶) 到 1(底)。"""
    ys = np.linspace(0, 1, h)
    ts = [s[0] for s in stops]
    arr = np.zeros((h, w, 3), dtype=np.float64)
    for c in range(3):
        vals = [s[1][c] for s in stops]
        line = np.interp(ys, ts, vals)
        arr[:, :, c] = line[:, None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def diag_grad(size, colors, angle=60):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    rad = math.radians(angle)
    proj = xx * math.cos(rad) + yy * math.sin(rad)
    proj -= proj.min()
    proj /= max(proj.max(), 1)
    stops = np.linspace(0, 1, len(colors))
    arr = np.zeros((size, size, 3), dtype=np.float64)
    for c in range(3):
        arr[..., c] = np.interp(proj, stops, [col[c] for col in colors])
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def radial_glow(img, color, center, radius, strength):
    w, h = img.size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    cx, cy = center[0] * w, center[1] * h
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (max(w, h) * radius)
    mask = np.clip(1 - dist, 0, 1) ** 2 * strength
    arr = np.array(img, dtype=np.float64)
    for c in range(3):
        arr[..., c] = arr[..., c] * (1 - mask) + color[c] * mask
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def grain(img, strength=5):
    w, h = img.size
    arr = np.array(img, dtype=np.int16)
    noise = np.random.default_rng(11).normal(0, strength, (h, w, 1))
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def star(draw, center, radius, color):
    pts = []
    for i in range(8):
        a = math.radians(i * 45 - 90)
        length = radius if i % 2 == 0 else radius * 0.30
        pts.append((center[0] + length * math.cos(a), center[1] + length * math.sin(a)))
    draw.polygon(pts, fill=color)


def shadow(base, layer, offset=(0, 26), blur=34, opacity=100):
    alpha = layer.split()[3].point(lambda v: int(v * opacity / 255))
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    sh.paste(alpha, offset, alpha)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(sh)
    base.alpha_composite(layer)


def bezier_point(p0, p1, p2, t):
    x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
    y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
    dx = 2 * (1 - t) * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0])
    dy = 2 * (1 - t) * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1])
    return x, y, dx, dy


def leaf(draw, base, ctrl, tip, width, color, serration=0.16, taper=0.85):
    """画一片叶子：沿二次贝塞尔曲线两侧生成轮廓。"""
    up, dn = [], []
    n = 40
    for i in range(n + 1):
        t = i / n
        x, y, dx, dy = bezier_point(base, ctrl, tip, t)
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        hw = width * (1 - t) ** taper
        hw *= 1 + serration * math.sin(t * 34)
        hw = max(hw, 0.0)
        up.append((x + nx * hw, y + ny * hw))
        dn.append((x - nx * hw, y - ny * hw))
    draw.polygon(up + dn[::-1], fill=color)


# ---------- 相框内画面 ----------

def scene_beach(w, h):
    img = vgrad(w, h, [(0.0, (255, 198, 128)), (0.34, (255, 146, 128)), (0.58, (196, 116, 158)), (1.0, (120, 88, 152))])
    d = ImageDraw.Draw(img)
    sun_r = w * 0.150
    sun_cx, sun_cy = w * 0.60, h * 0.34
    d.ellipse([sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r], fill=(255, 242, 206, 255))

    sea_top = int(h * 0.60)
    sea = vgrad(w, h - sea_top, [(0.0, (168, 128, 176)), (0.45, (108, 84, 140)), (1.0, (54, 44, 100))])
    img.paste(sea.convert("RGB"), (0, sea_top))

    d = ImageDraw.Draw(img)
    # 海面反光：平滑的高斯光柱 + 少量波光，避免生硬条纹
    sea_h = h - sea_top
    yy, xx = np.mgrid[0:sea_h, 0:w].astype(np.float64)
    t = yy / max(sea_h - 1, 1)
    spread = w * 0.085 * (0.55 + 1.35 * t)
    dx = xx - sun_cx
    alpha = 118 * np.clip(1 - t, 0, 1) ** 1.7 * np.exp(-(dx / spread) ** 2)
    alpha *= 0.80 + 0.20 * np.sin(yy * 0.55)
    overlay = np.zeros((sea_h, w, 4), dtype=np.float64)
    overlay[..., 0] = 255
    overlay[..., 1] = 224
    overlay[..., 2] = 188
    overlay[..., 3] = np.clip(alpha, 0, 255)
    img.alpha_composite(Image.fromarray(overlay.astype(np.uint8), "RGBA"), (0, sea_top))

    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(9)
    for _ in range(26):
        y = rng.uniform(sea_top + 6, sea_top + sea_h * 0.75)
        t = (y - sea_top) / sea_h
        half = w * (0.012 + 0.030 * t) * rng.uniform(0.6, 1.4)
        cx = sun_cx + rng.normal(0, w * 0.055 * (0.5 + t))
        d.line([(cx - half, y), (cx + half, y)], fill=(255, 236, 206, int(150 * (1 - t))), width=3)
    # 远处细浪
    for i in range(3):
        y = sea_top + 10 + i * 12
        d.line([(0, y), (w, y)], fill=(255, 226, 210, 55 - i * 14), width=2)
    return img


def scene_city(w, h):
    img = vgrad(w, h, [(0.0, (68, 60, 138)), (0.40, (198, 106, 152)), (0.68, (255, 156, 122)), (1.0, (255, 204, 156))])
    d = ImageDraw.Draw(img)
    sun_r = w * 0.105
    d.ellipse([w * 0.28 - sun_r, h * 0.50 - sun_r, w * 0.28 + sun_r, h * 0.50 + sun_r], fill=(255, 234, 182, 255))

    rng = np.random.default_rng(5)

    def building_row(base_y, color, count, min_w, max_w, max_h, window_color=None):
        rects = []
        x = -w * 0.05
        while x < w:
            bw = rng.uniform(min_w, max_w)
            bh = rng.uniform(max_h * 0.45, max_h)
            top = base_y - bh
            d.rectangle([x, top, x + bw, h], fill=color)
            rects.append((x, x + bw, top))
            x += bw + rng.uniform(2, 10)
        if window_color:
            for (x0, x1, top) in rects:
                cols = max(1, int((x1 - x0) // 26))
                rows = max(1, int((h - top) // 30))
                for c in range(cols):
                    for r in range(rows):
                        if rng.random() < 0.45:
                            continue
                        wx = x0 + 8 + c * 26
                        wy = top + 14 + r * 30
                        if wx + 7 > x1 - 4:
                            continue
                        d.rectangle([wx, wy, wx + 7, wy + 10],
                                    fill=(255, 214, 150, int(rng.uniform(120, 220))))
        return rects

    building_row(h * 0.70, (92, 68, 118, 255), 22, w * 0.06, w * 0.13, h * 0.30)
    building_row(h * 0.80, (62, 44, 84, 255), 20, w * 0.07, w * 0.15, h * 0.26, window_color=True)
    building_row(h * 0.90, (32, 22, 48, 255), 18, w * 0.08, w * 0.17, h * 0.22, window_color=True)
    return img


def scene_boat(w, h):
    img = vgrad(w, h, [(0.0, (255, 218, 164)), (0.28, (255, 176, 138)), (0.50, (196, 140, 168)), (0.68, (110, 120, 168)), (1.0, (48, 84, 140))])
    d = ImageDraw.Draw(img)
    sun_r = w * 0.105
    sun_cx, sun_cy = w * 0.30, h * 0.34
    d.ellipse([sun_cx - sun_r, sun_cy - sun_r, sun_cx + sun_r, sun_cy + sun_r], fill=(255, 248, 218, 255))

    sea_top = int(h * 0.62)
    sea = vgrad(w, h - sea_top, [(0.0, (120, 132, 176)), (0.5, (74, 96, 148)), (1.0, (34, 54, 104))])
    img.paste(sea.convert("RGB"), (0, sea_top))

    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(4)
    for y in range(sea_top + 6, h, 7):
        t = (y - sea_top) / max(h - sea_top, 1)
        alpha = int(110 * (1 - t) ** 1.1)
        if alpha <= 4:
            continue
        for _ in range(2):
            cx = rng.uniform(0, w)
            half = rng.uniform(w * 0.02, w * 0.09)
            d.line([(cx - half, y), (cx + half, y)], fill=(210, 226, 246, alpha), width=2)

    hull = (40, 30, 56, 255)
    sail = (255, 252, 244, 255)
    bx, by = w * 0.63, h * 0.76
    d.polygon([(bx - w * 0.155, by), (bx + w * 0.155, by), (bx + w * 0.105, by + h * 0.085), (bx - w * 0.115, by + h * 0.085)], fill=hull)
    d.line([(bx, by), (bx, by - h * 0.42)], fill=hull, width=max(2, int(w * 0.010)))
    d.polygon([(bx - w * 0.008, by - h * 0.40), (bx - w * 0.008, by - h * 0.04), (bx - w * 0.20, by - h * 0.04)], fill=sail)
    d.polygon([(bx + w * 0.012, by - h * 0.36), (bx + w * 0.012, by - h * 0.04), (bx + w * 0.175, by - h * 0.04)], fill=(238, 228, 214, 255))
    d.ellipse([bx - w * 0.005, by - h * 0.425, bx + w * 0.013, by - h * 0.405], fill=hull)

    for gx, gy, gs in ((w * 0.20, h * 0.20, 1.0), (w * 0.27, h * 0.25, 0.7), (w * 0.14, h * 0.27, 0.55)):
        d.arc([gx - w * 0.035 * gs, gy - h * 0.022 * gs, gx, gy + h * 0.012 * gs], start=200, end=340,
              fill=(72, 56, 82, 220), width=max(2, int(w * 0.008 * gs)))
        d.arc([gx, gy - h * 0.022 * gs, gx + w * 0.035 * gs, gy + h * 0.012 * gs], start=200, end=340,
              fill=(72, 56, 82, 220), width=max(2, int(w * 0.008 * gs)))
    return img


def scene_snow(w, h):
    img = vgrad(w, h, [(0.0, (66, 92, 160)), (0.38, (140, 150, 200)), (0.62, (240, 190, 190)), (1.0, (255, 214, 190))])
    d = ImageDraw.Draw(img)
    sun_r = w * 0.085
    d.ellipse([w * 0.70 - sun_r, h * 0.34 - sun_r, w * 0.70 + sun_r, h * 0.34 + sun_r], fill=(255, 240, 210, 255))
    d.polygon([(0, h), (0, h * 0.62), (w * 0.24, h * 0.34), (w * 0.46, h * 0.60), (w * 0.62, h * 0.44), (w * 0.86, h * 0.66), (w, h * 0.58), (w, h)],
              fill=(226, 232, 248, 255))
    d.polygon([(0, h), (0, h * 0.78), (w * 0.30, h * 0.56), (w * 0.56, h * 0.80), (w * 0.78, h * 0.64), (w, h * 0.82), (w, h)],
              fill=(120, 132, 180, 255))
    d.polygon([(0, h), (0, h * 0.90), (w * 0.40, h * 0.80), (w * 0.72, h * 0.92), (w, h * 0.86), (w, h)],
              fill=(52, 54, 92, 255))
    d.polygon([(w * 0.24, h * 0.34), (w * 0.31, h * 0.45), (w * 0.24, h * 0.42), (w * 0.17, h * 0.46)], fill=(255, 255, 255, 235))
    d.polygon([(w * 0.62, h * 0.44), (w * 0.67, h * 0.53), (w * 0.62, h * 0.51), (w * 0.57, h * 0.54)], fill=(255, 255, 255, 225))
    return img


def scene_moon(w, h):
    img = vgrad(w, h, [(0.0, (18, 20, 54)), (0.42, (40, 34, 86)), (0.72, (70, 44, 104)), (1.0, (30, 22, 52))])
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(21)
    for _ in range(70):
        x, y = rng.uniform(0, w), rng.uniform(0, h * 0.7)
        r = rng.uniform(0.6, 2.4)
        a = int(rng.uniform(80, 230))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 235, a))
    moon_r = w * 0.16
    d.ellipse([w * 0.66 - moon_r, h * 0.26 - moon_r, w * 0.66 + moon_r, h * 0.26 + moon_r], fill=(255, 246, 214, 255))
    d.ellipse([w * 0.66 - moon_r * 0.30, h * 0.26 - moon_r * 0.42, w * 0.66 - moon_r * 0.02, h * 0.26 - moon_r * 0.14],
              fill=(236, 224, 190, 255))
    d.polygon([(0, h), (0, h * 0.74), (w * 0.22, h * 0.60), (w * 0.48, h * 0.76), (w * 0.70, h * 0.64), (w, h * 0.80), (w, h)],
              fill=(24, 20, 44, 255))
    d.polygon([(0, h), (0, h * 0.88), (w * 0.34, h * 0.80), (w * 0.66, h * 0.92), (w, h * 0.86), (w, h)],
              fill=(14, 12, 30, 255))
    return img


def scene_balloon(w, h):
    img = vgrad(w, h, [(0.0, (255, 226, 190)), (0.30, (255, 186, 168)), (0.58, (226, 158, 190)), (1.0, (150, 132, 196))])
    d = ImageDraw.Draw(img)

    sun_r = w * 0.085
    d.ellipse([w * 0.20 - sun_r, h * 0.24 - sun_r, w * 0.20 + sun_r, h * 0.24 + sun_r], fill=(255, 246, 214, 255))

    # 云
    rng = np.random.default_rng(12)
    for cx, cy, scale in ((0.72, 0.20, 1.0), (0.84, 0.30, 0.65), (0.12, 0.44, 0.55)):
        for _ in range(5):
            ox = rng.uniform(-1, 1) * w * 0.055 * scale
            oy = rng.uniform(-0.5, 0.5) * h * 0.020 * scale
            rr = rng.uniform(0.6, 1.0) * w * 0.042 * scale
            px = w * cx + ox
            py = h * cy + oy
            d.ellipse([px - rr, py - rr * 0.72, px + rr, py + rr * 0.72], fill=(255, 248, 240, 150))

    # 远山
    d.polygon([(0, h), (0, h * 0.80), (w * 0.22, h * 0.68), (w * 0.46, h * 0.79), (w * 0.68, h * 0.70), (w, h * 0.80), (w, h)],
              fill=(146, 126, 180, 255))
    d.polygon([(0, h), (0, h * 0.90), (w * 0.28, h * 0.82), (w * 0.56, h * 0.92), (w * 0.80, h * 0.85), (w, h * 0.91), (w, h)],
              fill=(96, 84, 146, 255))

    # 热气球
    bx, by = w * 0.58, h * 0.40
    rw, rh = w * 0.150, h * 0.175
    shell = (250, 92, 96, 255)
    stripe = (255, 206, 96, 255)
    stripe2 = (86, 170, 196, 255)

    def envelope(color):
        d.ellipse([bx - rw, by - rh, bx + rw, by + rh * 0.52], fill=color)
        d.polygon([(bx - rw * 0.96, by + rh * 0.26), (bx + rw * 0.96, by + rh * 0.26),
                   (bx + rw * 0.20, by + rh * 0.98), (bx - rw * 0.20, by + rh * 0.98)], fill=color)

    envelope(shell)
    d.ellipse([bx - rw * 0.58, by - rh * 0.92, bx + rw * 0.58, by + rh * 0.44], fill=stripe)
    d.ellipse([bx - rw * 0.20, by - rh * 0.90, bx + rw * 0.20, by + rh * 0.46], fill=stripe2)
    d.polygon([(bx - rw * 0.58, by + rh * 0.22), (bx + rw * 0.58, by + rh * 0.22),
               (bx + rw * 0.13, by + rh * 0.92), (bx - rw * 0.13, by + rh * 0.92)], fill=stripe2)

    # 吊篮
    basket_y = by + rh * 1.20
    d.line([(bx - rw * 0.34, by + rh * 0.86), (bx - rw * 0.16, basket_y)], fill=(96, 64, 88, 255), width=4)
    d.line([(bx + rw * 0.34, by + rh * 0.86), (bx + rw * 0.16, basket_y)], fill=(96, 64, 88, 255), width=4)
    d.rounded_rectangle([bx - rw * 0.20, basket_y, bx + rw * 0.20, basket_y + rh * 0.20], radius=5, fill=(120, 78, 76, 255))

    # 飞鸟
    for gx, gy, gs in ((w * 0.30, h * 0.28, 0.9), (w * 0.38, h * 0.34, 0.6)):
        d.arc([gx - w * 0.030 * gs, gy - h * 0.020 * gs, gx, gy + h * 0.010 * gs], start=200, end=340,
              fill=(120, 88, 120, 210), width=2)
        d.arc([gx, gy - h * 0.020 * gs, gx + w * 0.030 * gs, gy + h * 0.010 * gs], start=200, end=340,
              fill=(120, 88, 120, 210), width=2)
    return img


SCENES = [
    ("海边日落", scene_beach, [(255, 206, 170), (252, 108, 132)], (255, 200, 60)),
    ("城市黄昏", scene_city, [(255, 196, 190), (186, 122, 190)], (255, 206, 90)),
    ("帆船日落", scene_boat, [(186, 220, 236), (255, 180, 152)], (255, 210, 96)),
    ("雪山", scene_snow, [(206, 226, 246), (252, 176, 176)], (255, 208, 84)),
    ("月夜", scene_moon, [(78, 76, 140), (232, 140, 168)], (255, 220, 110)),
    ("热气球", scene_balloon, [(255, 214, 186), (226, 156, 178)], (255, 206, 80)),
]


# ---------- 组合成图标 ----------

def polaroid(scene_fn, bg_colors, star_color):
    canvas = diag_grad(S, bg_colors, 60)
    canvas = radial_glow(canvas, (255, 245, 225), (0.24, 0.18), 0.62, 0.30)

    cw, ch = 636, 736
    card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle([0, 0, cw, ch], radius=24, fill=(255, 255, 255, 255))

    pw, ph = cw - 68, 540
    photo = scene_fn(pw, ph)
    photo = grain(photo, 5)
    card.paste(photo.convert("RGB"), (34, 34))

    d = ImageDraw.Draw(card)
    star(d, (cw - 112, ch - 96), 40, star_color + (255,))

    card = card.rotate(-8, expand=True, resample=Image.BICUBIC)
    shadow(canvas, card, (0, 26), 34, 100)
    return grain(canvas)


def contact_sheet(items):
    thumb = 380
    gap = 26
    label_h = 62
    cols = 3
    rows = (len(items) + cols - 1) // cols
    w = gap + cols * (thumb + gap)
    h = gap + rows * (thumb + label_h + gap)
    sheet = Image.new("RGB", (w, h), (16, 16, 19))
    d = ImageDraw.Draw(sheet)
    font = None
    for c in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf", "arial.ttf"):
        try:
            font = ImageFont.truetype(c, 28)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    for idx, (name, image) in enumerate(items):
        row, col = divmod(idx, cols)
        x = gap + col * (thumb + gap)
        y = gap + row * (thumb + label_h + gap)
        sheet.paste(image.resize((thumb, thumb), Image.LANCZOS).convert("RGB"), (x, y))
        d.text((x + 6, y + thumb + 14), f"{idx + 1}  {name}", fill=(232, 232, 238), font=font)
    return sheet


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    items = []
    for idx, (name, fn, bg, star_color) in enumerate(SCENES, start=1):
        icon = polaroid(fn, bg, star_color).convert("RGB")
        path = os.path.join(OUT_DIR, f"v{idx}.png")
        icon.save(path, "PNG")
        items.append((name, icon))
        print(f"wrote {path}  ({name})")
    sheet = contact_sheet(items)
    sheet_path = os.path.join(OUT_DIR, "variants-sheet.png")
    sheet.save(sheet_path, "PNG")
    print(f"wrote {sheet_path} {sheet.size}")


if __name__ == "__main__":
    main()
