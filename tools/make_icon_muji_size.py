#!/usr/bin/env python3
"""按 MUJI 图标的字标比例生成 Sx Cam 图标。

MUJI 官方图标实测：白色字标宽占 70%，字高占 28.5%，居中。
Sx Cam 有 6 个字符，一行做不到这个字高，所以提供两行方案对比。
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

S = 1024
OUT = os.path.join("build", "icons", "muji-size")

RED = (140, 16, 36)
WHITE = (255, 255, 255, 255)

FONT_NARROW_BOLD = "C:/Windows/Fonts/ARIALNB.TTF"
FONT_BOLD = "C:/Windows/Fonts/arialbd.ttf"


def base():
    img = Image.new("RGBA", (S, S), RED + (255,))
    arr = np.array(img, dtype=np.int16)
    noise = np.random.default_rng(5).normal(0, 2.2, (S, S, 1))
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def text_width(draw, text, font):
    return draw.textlength(text, font=font)


def fit_font(draw, text, font_path, max_width, target_cap):
    """返回 (font, 实际字高)。字高受 target_cap 和 max_width 双重约束。"""
    size = int(target_cap / 0.716)
    font = ImageFont.truetype(font_path, size)
    width = text_width(draw, text, font)
    if width > max_width:
        size = int(size * max_width / width)
        font = ImageFont.truetype(font_path, size)
    bbox = draw.textbbox((0, 0), text, font=font, anchor="ls")
    cap = bbox[3] - bbox[1]
    return font, cap


def two_lines(top, bottom, font_path, target_cap, max_width, gap_ratio, y_center=S / 2):
    img = base()
    d = ImageDraw.Draw(img)
    # 两行共用字号：以更宽的一行为准
    size = int(target_cap / 0.716)
    font = ImageFont.truetype(font_path, size)
    widest = max(text_width(d, top, font), text_width(d, bottom, font))
    if widest > max_width:
        size = int(size * max_width / widest)
        font = ImageFont.truetype(font_path, size)

    bbox = d.textbbox((0, 0), "H", font=font)
    cap = bbox[3] - bbox[1]
    gap = cap * gap_ratio
    block = cap * 2 + gap
    y_top = y_center - block / 2
    d.text((S / 2, y_top), top, font=font, anchor="ma", fill=WHITE)
    d.text((S / 2, y_top + cap + gap), bottom, font=font, anchor="ma", fill=WHITE)
    return img, cap


def one_line(text, font_path, target_cap, max_width):
    img = base()
    d = ImageDraw.Draw(img)
    font, cap = fit_font(d, text, font_path, max_width, target_cap)
    d.text((S / 2, S / 2), text, font=font, anchor="mm", fill=WHITE)
    return img, cap


def contact_sheet(items, path):
    thumb = 420
    gap = 28
    label_h = 76
    cols = 3
    rows = (len(items) + cols - 1) // cols
    w = gap + cols * (thumb + gap)
    h = gap + rows * (thumb + label_h + gap)
    sheet = Image.new("RGB", (w, h), (16, 16, 19))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 26)
    for idx, (name, image, note) in enumerate(items):
        row, col = divmod(idx, cols)
        x = gap + col * (thumb + gap)
        y = gap + row * (thumb + label_h + gap)
        sheet.paste(image.resize((thumb, thumb), Image.LANCZOS).convert("RGB"), (x, y))
        d.text((x + 6, y + thumb + 10), name, fill=(235, 235, 240), font=font)
        d.text((x + 6, y + thumb + 42), note, fill=(150, 150, 160), font=font)
    sheet.save(path, "PNG")


def main():
    os.makedirs(OUT, exist_ok=True)

    variants = [
        ("A 两行 28.5%", *two_lines("Sx", "Cam", FONT_NARROW_BOLD, S * 0.285, S * 0.70, 0.22)),
        ("B 两行 25%", *two_lines("Sx", "Cam", FONT_NARROW_BOLD, S * 0.25, S * 0.66, 0.22)),
        ("C 两行 22%", *two_lines("Sx", "Cam", FONT_NARROW_BOLD, S * 0.22, S * 0.60, 0.24)),
        ("D 两行 28.5% 常规体", *two_lines("Sx", "Cam", FONT_BOLD, S * 0.285, S * 0.70, 0.22)),
        ("E 一行 70% 窄体", *one_line("Sx Cam", FONT_NARROW_BOLD, S * 0.285, S * 0.70)),
        ("F 一行 70% 常规", *one_line("Sx Cam", FONT_BOLD, S * 0.285, S * 0.70)),
    ]

    items = []
    for idx, (name, img, cap) in enumerate(variants, start=1):
        path = os.path.join(OUT, f"v{idx}.png")
        img.convert("RGB").save(path, "PNG")
        items.append((name, img, f"字高 {cap / S * 100:.1f}%"))
        print(f"wrote {path}  {name}  cap {cap / S * 100:.1f}%")

    contact_sheet(items, os.path.join(OUT, "sheet.png"))
    print("done")


if __name__ == "__main__":
    main()
