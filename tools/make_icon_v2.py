#!/usr/bin/env python3
"""第二组 App 图标方案：三棱镜 / 胶片卷 / 极简快门 / 双格胶片 / 彩虹镜头 / 散景。"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
OUT = os.path.join("build", "icons", "v2")


# ---------- 基础 ----------

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


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def paste_rounded(base, layer, box, radius):
    w = int(box[2] - box[0])
    h = int(box[3] - box[1])
    scaled = layer.resize((w, h), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    base.paste(scaled, (int(box[0]), int(box[1])), mask)


def mini_landscape(w, h, sky, sun, hills):
    img = diag_grad(max(w, h), [sky[0], sky[1]], 90).resize((w, h))
    d = ImageDraw.Draw(img)
    sr = w * 0.11
    d.ellipse([w * 0.66 - sr, h * 0.28 - sr, w * 0.66 + sr, h * 0.28 + sr], fill=sun + (255,))
    for i, color in enumerate(hills):
        base_y = h * (0.62 + i * 0.13)
        d.polygon(
            [(0, h), (0, base_y), (w * 0.30, base_y - h * 0.12), (w * 0.58, base_y + h * 0.05),
             (w * 0.80, base_y - h * 0.07), (w, base_y), (w, h)],
            fill=color + (255,),
        )
    return img


# ---------- 方案 ----------

def opt_prism():
    img = diag_grad(S, [(10, 14, 34), (26, 18, 52), (8, 10, 26)], 120)
    img = radial_glow(img, (90, 70, 190), (0.24, 0.20), 0.9, 0.35)
    d = ImageDraw.Draw(img)
    cx, cy = S * 0.44, S * 0.52

    d.polygon([(0, cy - 24), (cx - 130, cy - 44), (cx - 130, cy + 44), (0, cy + 24)],
              fill=(255, 255, 255, 230))

    colors = [(255, 74, 96), (255, 148, 62), (255, 214, 84), (96, 214, 132), (72, 166, 255), (152, 108, 255)]
    for i, c in enumerate(colors):
        y0 = cy - 96 + i * 34
        d.polygon([(cx + 96, cy - 26 + i * 10), (S, y0 - 22), (S, y0 + 22)], fill=c + (215,))

    tri = [(cx, cy - 176), (cx + 156, cy + 132), (cx - 156, cy + 132)]
    d.polygon(tri, fill=(238, 244, 255, 255))
    d.line(tri + [tri[0]], fill=(255, 255, 255, 255), width=7, joint="curve")
    return grain(img, 4)


def opt_film_roll():
    img = diag_grad(S, [(255, 216, 176), (250, 142, 122), (206, 86, 118)], 70)
    img = radial_glow(img, (255, 246, 226), (0.26, 0.20), 0.7, 0.3)
    d = ImageDraw.Draw(img)

    cx = cy = S / 2
    R = 336
    thick = 152
    d.arc([cx - R, cy - R, cx + R, cy + R], 0, 360, fill=(30, 25, 32, 255), width=thick)

    count = 26
    for i in range(count):
        angle = 360.0 * i / count
        for rr in (R - thick * 0.26, R - thick * 0.74):
            rad = math.radians(angle)
            px = cx + rr * math.cos(rad)
            py = cy + rr * math.sin(rad)
            patch = Image.new("RGBA", (30, 42), (0, 0, 0, 0))
            pd = ImageDraw.Draw(patch)
            pd.rounded_rectangle([0, 0, 29, 41], radius=7, fill=(255, 224, 196, 240))
            patch = patch.rotate(-angle, expand=True, resample=Image.BICUBIC)
            img.alpha_composite(patch, (int(px - patch.width / 2), int(py - patch.height / 2)))

    d = ImageDraw.Draw(img)
    d.ellipse([cx - 158, cy - 158, cx + 158, cy + 158], fill=(255, 244, 228, 255))
    d.ellipse([cx - 84, cy - 84, cx + 84, cy + 84], fill=(248, 112, 104, 255))
    d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=(255, 244, 228, 255))
    return grain(img)


def opt_minimal_shutter():
    img = diag_grad(S, [(248, 244, 236), (235, 228, 217)], 90)
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    blades = 6
    for i in range(blades):
        a0 = i * 60 - 90
        a1 = a0 + 52
        pts = [
            (cx + 76 * math.cos(math.radians(a0)), cy + 76 * math.sin(math.radians(a0))),
            (cx + 344 * math.cos(math.radians(a0)), cy + 344 * math.sin(math.radians(a0))),
            (cx + 344 * math.cos(math.radians(a1)), cy + 344 * math.sin(math.radians(a1))),
            (cx + 76 * math.cos(math.radians(a1)), cy + 76 * math.sin(math.radians(a1))),
        ]
        d.polygon(pts, fill=(26, 24, 22, 255))
    d.ellipse([cx - 344, cy - 344, cx + 344, cy + 344], outline=(26, 24, 22, 255), width=12)
    d.ellipse([cx - 74, cy - 74, cx + 74, cy + 74], fill=(248, 244, 236, 255))
    d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=(255, 108, 78, 255))
    return grain(img, 4)


def opt_double_frame():
    img = diag_grad(S, [(20, 20, 26), (34, 28, 40)], 90)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([58, 214, 966, 810], radius=34, fill=(12, 11, 15, 255))
    for x in range(96, 936, 62):
        d.rounded_rectangle([x, 232, x + 28, 266], radius=7, fill=(238, 232, 222, 190))
        d.rounded_rectangle([x, 758, x + 28, 792], radius=7, fill=(238, 232, 222, 190))

    scenes = [
        ((255, 208, 158), (255, 132, 122), (255, 246, 214), [(120, 96, 150), (54, 44, 86)]),
        ((168, 208, 240), (110, 140, 210), (255, 250, 228), [(86, 104, 156), (40, 52, 96)]),
    ]
    boxes = [(100, 292, 492, 732), (532, 292, 924, 732)]
    for (sky0, sky1, sun, hills), box in zip(scenes, boxes):
        w = box[2] - box[0]
        h = box[3] - box[1]
        photo = mini_landscape(w, h, (sky0, sky1), sun, hills)
        paste_rounded(img, photo, box, 10)

    return grain(img, 4)


def opt_rainbow_lens():
    img = diag_grad(S, [(14, 10, 28), (38, 16, 54), (10, 20, 40)], 130)
    img = radial_glow(img, (120, 60, 210), (0.30, 0.24), 0.95, 0.40)
    d = ImageDraw.Draw(img)
    cx = cy = S / 2
    R = 336

    d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(16, 12, 26, 255))

    colors = [(255, 84, 110), (255, 150, 70), (255, 214, 90), (110, 214, 140), (80, 176, 255), (160, 116, 255)]
    for i, c in enumerate(colors):
        r = R - 44 - i * 36
        d.arc([cx - r, cy - r, cx + r, cy + r], 196, 322, fill=c + (235,), width=32)

    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(240, 240, 255, 210), width=11)
    d.ellipse([cx - R + 26, cy - R + 26, cx + R - 26, cy + R - 26], outline=(255, 255, 255, 40), width=5)
    d.ellipse([cx - 46, cy - 46, cx + 46, cy + 46], fill=(255, 255, 255, 235))
    return grain(img, 4)


def opt_bokeh():
    img = diag_grad(S, [(12, 10, 24), (28, 14, 46), (10, 16, 34)], 120)
    rng = np.random.default_rng(7)
    palette = [(255, 92, 152), (92, 200, 255), (255, 192, 96), (180, 124, 255), (120, 255, 206)]

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(16):
        r = rng.uniform(48, 148)
        x = rng.uniform(90, S - 90)
        y = rng.uniform(90, S - 90)
        c = palette[int(rng.integers(0, len(palette)))]
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (int(rng.uniform(40, 90)),))
    layer = layer.filter(ImageFilter.GaussianBlur(7))
    img.alpha_composite(layer)

    d = ImageDraw.Draw(img)
    d.ellipse([S * 0.63 - 48, S * 0.29 - 48, S * 0.63 + 48, S * 0.29 + 48], fill=(255, 255, 255, 240))
    d.ellipse([S * 0.63 - 74, S * 0.29 - 74, S * 0.63 + 74, S * 0.29 + 74], outline=(255, 255, 255, 90), width=4)
    return grain(img, 4)


OPTIONS = [
    ("三棱镜", opt_prism),
    ("胶片卷", opt_film_roll),
    ("极简快门", opt_minimal_shutter),
    ("双格胶片", opt_double_frame),
    ("彩虹镜头", opt_rainbow_lens),
    ("散景光斑", opt_bokeh),
]


# ---------- 出图 ----------

def contact_sheet(items, path):
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
    sheet.save(path, "PNG")
    return sheet


def small_row(items, path):
    size = 96
    gap = 34
    font = None
    for c in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf", "arial.ttf"):
        try:
            font = ImageFont.truetype(c, 20)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    w = gap + len(items) * (size + gap)
    h = gap + size + 34
    sheet = Image.new("RGB", (w, h), (26, 26, 30))
    d = ImageDraw.Draw(sheet)
    mask = rounded_mask(size, int(size * 0.2237))
    for idx, (_, image) in enumerate(items):
        x = gap + idx * (size + gap)
        sheet.paste(image.resize((size, size), Image.LANCZOS).convert("RGB"), (x, gap), mask)
        d.text((x + 2, gap + size + 8), str(idx + 1), fill=(220, 220, 226), font=font)
    sheet.save(path, "PNG")
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    items = []
    for idx, (name, maker) in enumerate(OPTIONS, start=1):
        icon = maker().convert("RGB")
        path = os.path.join(OUT, f"v{idx}.png")
        icon.save(path, "PNG")
        items.append((name, icon))
        print(f"wrote {path}  ({name})")

    contact_sheet(items, os.path.join(OUT, "sheet.png"))
    small_row(items, os.path.join(OUT, "small-row.png"))
    print("done")


if __name__ == "__main__":
    main()
