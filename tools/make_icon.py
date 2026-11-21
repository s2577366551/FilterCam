#!/usr/bin/env python3
"""生成 1024x1024 的 App 图标：胶片齿孔环 + 光圈叶片。"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048
OUT = os.path.join("FilterCam", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")


def radial_background():
    yy, xx = np.mgrid[0:S, 0:S]
    cx = cy = S / 2
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S * 0.62)
    glow = np.clip(1 - dist, 0, 1) ** 2.2
    base = np.zeros((S, S, 4), dtype=np.float64)
    base[..., 0] = 14 + 74 * glow
    base[..., 1] = 13 + 42 * glow
    base[..., 2] = 12 + 22 * glow
    base[..., 3] = 255
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGBA")


def film_ring(img):
    count = 28
    radius = 800
    for index in range(count):
        angle = index * (360 / count)
        patch = Image.new("RGBA", (168, 104), (0, 0, 0, 0))
        draw = ImageDraw.Draw(patch)
        draw.rounded_rectangle([4, 4, 164, 100], radius=26, fill=(242, 232, 213, 235))
        patch = patch.rotate(-angle, expand=True, resample=Image.BICUBIC)
        rad = math.radians(angle)
        cx = S / 2 + radius * math.cos(rad)
        cy = S / 2 + radius * math.sin(rad)
        img.alpha_composite(patch, (int(cx - patch.width / 2), int(cy - patch.height / 2)))


def amber_disc(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center = S / 2
    max_radius = 530
    steps = 160
    for step in range(steps, 0, -1):
        ratio = step / steps
        radius = max_radius * ratio
        mix = ratio
        red = int(255 - 30 * mix)
        green = int(190 - 85 * mix)
        blue = int(105 - 70 * mix)
        draw.ellipse(
            [center - radius, center - radius, center + radius, center + radius],
            fill=(red, green, blue, 255),
        )
    img.alpha_composite(layer)


def aperture_blades(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center = S / 2
    inner = 86
    outer = 505
    spread = 54
    for index in range(6):
        start = index * 60 + 12
        end = start + spread
        points = [
            (
                center + inner * math.cos(math.radians(start)),
                center + inner * math.sin(math.radians(start)),
            ),
            (
                center + outer * math.cos(math.radians(start)),
                center + outer * math.sin(math.radians(start)),
            ),
            (
                center + outer * math.cos(math.radians(end)),
                center + outer * math.sin(math.radians(end)),
            ),
            (
                center + inner * math.cos(math.radians(end)),
                center + inner * math.sin(math.radians(end)),
            ),
        ]
        draw.polygon(points, fill=(18, 17, 16, 238))
        draw.line(points + [points[0]], fill=(255, 179, 71, 210), width=5, joint="curve")
    img.alpha_composite(layer)


def accents(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center = S / 2
    radius = 585
    draw.ellipse(
        [center - radius, center - radius, center + radius, center + radius],
        outline=(47, 179, 166, 190),
        width=8,
    )
    dot = 34
    draw.ellipse(
        [center - dot, center - dot, center + dot, center + dot],
        fill=(47, 179, 166, 235),
    )
    img.alpha_composite(layer)


def grain(img, strength=7):
    array = np.array(img, dtype=np.int16)
    noise = np.random.default_rng(7).normal(0, strength, (S, S, 1))
    array[..., :3] = np.clip(array[..., :3] + noise, 0, 255)
    return Image.fromarray(array.astype(np.uint8), "RGBA")


def vignette(img):
    yy, xx = np.mgrid[0:S, 0:S]
    cx = cy = S / 2
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (S * 0.72)
    factor = np.clip(1 - 0.45 * np.clip(dist, 0, 1) ** 2, 0, 1)
    array = np.array(img, dtype=np.float64)
    array[..., :3] *= factor[..., None]
    return Image.fromarray(np.clip(array, 0, 255).astype(np.uint8), "RGBA")


def main():
    img = radial_background()
    amber_disc(img)
    aperture_blades(img)
    film_ring(img)
    accents(img)
    img = vignette(img)
    img = grain(img)

    img = img.resize((1024, 1024), Image.LANCZOS)
    img = img.convert("RGB")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT, "PNG")
    print(f"icon written to {OUT}")


if __name__ == "__main__":
    main()
