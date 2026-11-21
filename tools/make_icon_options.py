#!/usr/bin/env python3
"""生成 6 款 App 图标方案，并输出一张对比图。"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
OUT_DIR = os.path.join("build", "icons")


def linear_gradient(colors, angle=45):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    rad = math.radians(angle)
    projection = xx * math.cos(rad) + yy * math.sin(rad)
    projection -= projection.min()
    projection /= max(projection.max(), 1)
    stops = np.linspace(0, 1, len(colors))
    result = np.zeros((S, S, 3), dtype=np.float64)
    for channel in range(3):
        values = [color[channel] for color in colors]
        result[..., channel] = np.interp(projection, stops, values)
    return Image.fromarray(np.clip(result, 0, 255).astype(np.uint8), "RGB").convert("RGBA")


def radial_glow(img, color, center=(0.3, 0.25), radius=0.8, strength=1.0):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    cx, cy = center[0] * S, center[1] * S
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S * radius)
    mask = np.clip(1 - dist, 0, 1) ** 2 * strength
    array = np.array(img, dtype=np.float64)
    for channel in range(3):
        array[..., channel] = array[..., channel] * (1 - mask) + color[channel] * mask
    return Image.fromarray(np.clip(array, 0, 255).astype(np.uint8), "RGBA")


def shadow(base, layer, offset=(0, 26), blur=30, opacity=110):
    alpha = layer.split()[3].point(lambda value: int(value * opacity / 255))
    shadow_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_layer.paste(alpha, offset, alpha)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow_layer)
    base.alpha_composite(layer)


def aperture_layer(center, radius, inner, blades, color, rotation=0, width=0):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    spread = 360 / blades - 8
    for index in range(blades):
        start = rotation + index * (360 / blades)
        end = start + spread
        points = [
            (center[0] + inner * math.cos(math.radians(start)), center[1] + inner * math.sin(math.radians(start))),
            (center[0] + radius * math.cos(math.radians(start)), center[1] + radius * math.sin(math.radians(start))),
            (center[0] + radius * math.cos(math.radians(end)), center[1] + radius * math.sin(math.radians(end))),
            (center[0] + inner * math.cos(math.radians(end)), center[1] + inner * math.sin(math.radians(end))),
        ]
        draw.polygon(points, fill=color, outline=color, width=width)
    return layer


def star(draw, center, radius, color):
    points = []
    for index in range(8):
        angle = math.radians(index * 45 - 90)
        length = radius if index % 2 == 0 else radius * 0.32
        points.append((center[0] + length * math.cos(angle), center[1] + length * math.sin(angle)))
    draw.polygon(points, fill=color)


def grain(img, strength=6):
    width, height = img.size
    array = np.array(img, dtype=np.int16)
    noise = np.random.default_rng(11).normal(0, strength, (height, width, 1))
    array[..., :3] = np.clip(array[..., :3] + noise, 0, 255)
    return Image.fromarray(array.astype(np.uint8), "RGBA")


def option1():
    img = linear_gradient([(255, 46, 147), (122, 43, 255), (0, 229, 255)], 40)
    img = radial_glow(img, (255, 255, 255), (0.32, 0.2), 0.55, 0.35)
    layer = aperture_layer((S / 2, S / 2), 400, 70, 6, (255, 255, 255, 235), rotation=15)
    draw = ImageDraw.Draw(layer)
    draw.ellipse([S / 2 - 408, S / 2 - 408, S / 2 + 408, S / 2 + 408], outline=(255, 255, 255, 235), width=12)
    shadow(img, layer, (0, 24), 26, 90)
    return grain(img)


def option2():
    img = linear_gradient([(255, 245, 235), (255, 228, 214)], 90)
    img = radial_glow(img, (255, 214, 190), (0.7, 0.2), 0.7, 0.35)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    size = 620
    x0 = (S - size) / 2
    y0 = (S - size) / 2
    draw.rounded_rectangle([x0, y0, x0 + size, y0 + size], radius=170, fill=(255, 255, 255, 255))
    draw.ellipse([S / 2 - 210, S / 2 - 210, S / 2 + 210, S / 2 + 210], fill=(255, 90, 95, 255))
    draw.ellipse([S / 2 - 100, S / 2 - 90, S / 2 - 40, S / 2 - 30], fill=(255, 255, 255, 255))
    draw.ellipse([S / 2 + 40, S / 2 - 90, S / 2 + 100, S / 2 - 30], fill=(255, 255, 255, 255))
    draw.arc([S / 2 - 95, S / 2 - 20, S / 2 + 95, S / 2 + 120], start=20, end=160, fill=(255, 255, 255, 255), width=22)
    star(draw, (S * 0.78, S * 0.24), 58, (255, 200, 60, 255))
    shadow(img, layer, (0, 30), 40, 70)
    return grain(img)


def option3():
    img = linear_gradient([(12, 12, 22), (30, 18, 52), (10, 24, 46)], 120)
    img = radial_glow(img, (120, 80, 255), (0.28, 0.25), 0.8, 0.5)
    img = radial_glow(img, (0, 200, 255), (0.75, 0.78), 0.7, 0.4)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for step in range(26):
        ratio = step / 25
        radius = 430 - 330 * ratio
        shade = int(180 + 70 * ratio)
        draw.ellipse(
            [S / 2 - radius, S / 2 - radius, S / 2 + radius, S / 2 + radius],
            outline=(shade, shade, min(255, shade + 20), 210),
            width=8,
        )
    for index in range(6):
        angle = math.radians(index * 60 + 15)
        draw.line(
            [S / 2 + 80 * math.cos(angle), S / 2 + 80 * math.sin(angle),
             S / 2 + 330 * math.cos(angle), S / 2 + 330 * math.sin(angle)],
            fill=(240, 240, 255, 220),
            width=6,
        )
    star(draw, (S * 0.76, S * 0.24), 46, (255, 255, 255, 235))
    star(draw, (S * 0.24, S * 0.74), 30, (255, 255, 255, 200))
    shadow(img, layer, (0, 18), 24, 90)
    return grain(img, 4)


def option4():
    img = linear_gradient([(245, 241, 233), (236, 230, 219)], 90)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = 320
    draw.ellipse(
        [S / 2 - radius, S / 2 - radius, S / 2 + radius, S / 2 + radius],
        outline=(28, 26, 24, 255),
        width=14,
    )
    for index in range(6):
        angle = math.radians(index * 60 + 15)
        draw.line(
            [S / 2 + 90 * math.cos(angle), S / 2 + 90 * math.sin(angle),
             S / 2 + 250 * math.cos(angle), S / 2 + 250 * math.sin(angle)],
            fill=(28, 26, 24, 255),
            width=10,
        )
    draw.ellipse([S / 2 - 34, S / 2 - 34, S / 2 + 34, S / 2 + 34], fill=(255, 90, 70, 255))
    img.alpha_composite(layer)
    return grain(img, 4)


def option5():
    img = linear_gradient([(255, 211, 165), (253, 101, 133)], 60)
    img = radial_glow(img, (255, 240, 200), (0.25, 0.2), 0.6, 0.35)

    cw, ch = 636, 736
    card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle([0, 0, cw, ch], radius=24, fill=(255, 255, 255, 255))

    pw, ph = cw - 68, 540
    photo = linear_gradient([(255, 196, 120), (255, 120, 120), (90, 70, 150)], 90).resize((pw, ph))
    photo_draw = ImageDraw.Draw(photo)
    photo_draw.ellipse([pw - 250, 60, pw - 110, 200], fill=(255, 240, 205, 255))
    photo_draw.polygon(
        [(0, ph), (0, ph - 170), (150, ph - 260), (280, ph - 150), (400, ph - 230), (pw, ph - 120), (pw, ph)],
        fill=(62, 42, 82, 255),
    )
    photo_draw.polygon(
        [(0, ph), (0, ph - 80), (190, ph - 120), (360, ph - 60), (pw, ph - 100), (pw, ph)],
        fill=(28, 20, 44, 255),
    )
    photo = grain(photo, 5)
    card.paste(photo, (34, 34))

    draw = ImageDraw.Draw(card)
    star(draw, (cw - 112, ch - 96), 40, (255, 200, 60, 255))

    card = card.rotate(-8, expand=True, resample=Image.BICUBIC)
    shadow(img, card, (0, 26), 34, 100)
    return grain(img)


def option6():
    img = linear_gradient([(8, 8, 20), (26, 10, 48), (6, 20, 38)], 130)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse([S / 2 - 360, S / 2 - 360, S / 2 + 360, S / 2 + 360], outline=(255, 46, 180, 200), width=60)
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    img.alpha_composite(glow)

    glass = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glass_draw = ImageDraw.Draw(glass)
    for step in range(90, 0, -1):
        radius = 330 * step / 90
        alpha = int(110 * (1 - step / 90))
        glass_draw.ellipse(
            [S / 2 - radius, S / 2 - radius, S / 2 + radius, S / 2 + radius],
            fill=(8, 54, 72, alpha),
        )
    img.alpha_composite(glass)

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.ellipse([S / 2 - 330, S / 2 - 330, S / 2 + 330, S / 2 + 330], outline=(0, 229, 255, 235), width=14)
    draw.arc(
        [S / 2 - 300, S / 2 - 300, S / 2 + 300, S / 2 + 300],
        start=200,
        end=258,
        fill=(255, 255, 255, 140),
        width=14,
    )
    for index in range(6):
        angle = math.radians(index * 60 + 15)
        draw.line(
            [S / 2 + 70 * math.cos(angle), S / 2 + 70 * math.sin(angle),
             S / 2 + 320 * math.cos(angle), S / 2 + 320 * math.sin(angle)],
            fill=(255, 46, 180, 225),
            width=10,
        )
    draw.ellipse([S / 2 - 30, S / 2 - 30, S / 2 + 30, S / 2 + 30], fill=(0, 229, 255, 255))
    star(draw, (S * 0.78, S * 0.22), 40, (255, 255, 255, 220))
    img.alpha_composite(layer)
    return grain(img, 5)


def contact_sheet(images):
    thumb = 420
    gap = 28
    sheet = Image.new("RGB", (thumb * 3 + gap * 4, (thumb + 70) * 2 + gap * 3), (16, 16, 18))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 34)
    except OSError:
        font = ImageFont.load_default()
    for index, image in enumerate(images):
        row, column = divmod(index, 3)
        x = gap + column * (thumb + gap)
        y = gap + row * (thumb + 70 + gap)
        sheet.paste(image.resize((thumb, thumb), Image.LANCZOS).convert("RGB"), (x, y))
        draw.text((x + 6, y + thumb + 10), str(index + 1), fill=(240, 240, 240), font=font)
    return sheet


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    makers = [option1, option2, option3, option4, option5, option6]
    images = []
    for index, maker in enumerate(makers, start=1):
        image = maker().convert("RGB")
        path = os.path.join(OUT_DIR, f"option-{index}.png")
        image.save(path, "PNG")
        images.append(image)
        print(f"wrote {path}")
    sheet = contact_sheet(images)
    sheet_path = os.path.join(OUT_DIR, "options-sheet.png")
    sheet.save(sheet_path, "PNG")
    print(f"wrote {sheet_path}")


if __name__ == "__main__":
    main()
