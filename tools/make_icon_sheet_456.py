#!/usr/bin/env python3
"""把 4/5/6 三款图标做成对比图：大图 + 桌面实际大小预览。"""

import os

from PIL import Image, ImageDraw, ImageFont

SRC = os.path.join("build", "icons")
OUT = os.path.join(SRC, "sheet-456.png")

BIG = 400
SMALL = 118
PAD = 40
LABEL_H = 56


def load(index):
    return Image.open(os.path.join(SRC, f"option-{index}.png")).convert("RGB")


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    font = None
    small_font = None
    for candidate in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf", "arial.ttf"):
        try:
            font = ImageFont.truetype(candidate, 32)
            small_font = ImageFont.truetype(candidate, 26)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
        small_font = font

    width = PAD + 3 * BIG + 2 * PAD + 3 * SMALL + 3 * PAD
    height = PAD + BIG + LABEL_H + PAD

    sheet = Image.new("RGB", (width, height), (18, 18, 20))
    draw = ImageDraw.Draw(sheet)

    x = PAD
    for index in (4, 5, 6):
        img = load(index)
        big = rounded(img.resize((BIG, BIG), Image.LANCZOS), 88)
        sheet.paste(big, (x, PAD), big)
        draw.text((x + 4, PAD + BIG + 12), f"{index}", fill=(235, 235, 235), font=font)

        small = rounded(img.resize((SMALL, SMALL), Image.LANCZOS), 26)
        sx = x + BIG + PAD // 2
        sy = PAD + (BIG - SMALL) // 2
        sheet.paste(small, (sx, sy), small)
        draw.text((sx + 2, sy + SMALL + 8), "实际大小", fill=(150, 150, 155), font=small_font)

        x += BIG + SMALL + PAD

    sheet.save(OUT, "PNG")
    print(f"wrote {OUT} {sheet.size}")


if __name__ == "__main__":
    main()
