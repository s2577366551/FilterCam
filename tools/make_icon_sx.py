#!/usr/bin/env python3
"""Sx + cam 命名方案，直接渲染成无印风图标。"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

S = 1024
OUT = os.path.join("build", "icons", "sx")

RED = (140, 16, 36)
WHITE = (255, 255, 255, 255)

FONT_CJK = "C:/Windows/Fonts/msyhbd.ttc"
FONT_LATIN = "C:/Windows/Fonts/arialbd.ttf"


def base():
    img = Image.new("RGBA", (S, S), RED + (255,))
    arr = np.array(img, dtype=np.int16)
    noise = np.random.default_rng(5).normal(0, 2.2, (S, S, 1))
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def draw_spaced(draw, text, font, center_y, spacing):
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    x = S / 2 - total / 2
    for ch, w in zip(text, widths):
        if ch != " ":
            draw.text((x, center_y), ch, font=font, anchor="lm", fill=WHITE)
        x += w + spacing


def one_line(text, size, spacing, font_path=FONT_LATIN, y=S / 2):
    img = base()
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(font_path, size)
    draw_spaced(d, text, font, y, spacing)
    return img


def two_lines(top, bottom, size_top, size_bottom, spacing):
    img = base()
    d = ImageDraw.Draw(img)
    draw_spaced(d, top, ImageFont.truetype(FONT_LATIN, size_top), S * 0.41, spacing)
    draw_spaced(d, bottom, ImageFont.truetype(FONT_CJK, size_bottom), S * 0.615, spacing)
    return img


OPTIONS = [
    ("SxCAM", lambda: one_line("SxCAM", 210, 8)),
    ("Sx Cam", lambda: one_line("Sx Cam", 200, 6)),
    ("Sxcam", lambda: one_line("Sxcam", 230, 4)),
    ("Sx CAM", lambda: one_line("Sx CAM", 200, 18)),
    ("SxCam / 胶片", lambda: two_lines("SxCam", "胶片", 200, 150, 10)),
    ("Sx 相机", lambda: one_line("Sx 相机", 210, 16, FONT_CJK)),
]


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
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 28)
    for idx, (name, image) in enumerate(items):
        row, col = divmod(idx, cols)
        x = gap + col * (thumb + gap)
        y = gap + row * (thumb + label_h + gap)
        sheet.paste(image.resize((thumb, thumb), Image.LANCZOS).convert("RGB"), (x, y))
        d.text((x + 6, y + thumb + 14), f"{idx + 1}  {name}", fill=(232, 232, 238), font=font)
    sheet.save(path, "PNG")


def small_row(items, path):
    size = 96
    gap = 34
    w = gap + len(items) * (size + gap)
    h = gap + size + 34
    sheet = Image.new("RGB", (w, h), (26, 26, 30))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.2237), fill=255)
    for idx, (_, image) in enumerate(items):
        x = gap + idx * (size + gap)
        sheet.paste(image.resize((size, size), Image.LANCZOS).convert("RGB"), (x, gap), mask)
        d.text((x + 2, gap + size + 8), str(idx + 1), fill=(220, 220, 226), font=font)
    sheet.save(path, "PNG")


def main():
    os.makedirs(OUT, exist_ok=True)
    items = []
    for idx, (name, maker) in enumerate(OPTIONS, start=1):
        icon = maker().convert("RGB")
        path = os.path.join(OUT, f"s{idx}.png")
        icon.save(path, "PNG")
        items.append((name, icon))
        print(f"wrote {path}  ({name})")
    contact_sheet(items, os.path.join(OUT, "sheet.png"))
    small_row(items, os.path.join(OUT, "small-row.png"))
    print("done")


if __name__ == "__main__":
    main()
