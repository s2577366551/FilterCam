#!/usr/bin/env python3
"""把富士官方 LUT 与我们的预设套在同一张测试图上，生成对比图。

用法：
    python tools/compare_luts.py <官方LUT目录> [输出目录]

官方 LUT 目录需包含 33Grid/F-Log2 下的 .cube 文件。
输出：build/compare/<预设>.png（原图 | 富士 | 我们的）。
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

SIZE = 32
OUR_LUT_DIR = os.path.join("FilterCam", "Resources", "LUTs")

MAPPING = {
    "PROVIA": "sim_standard",
    "Velvia": "sim_vivid",
    "ASTIA": "sim_soft",
    "CLASSIC-CHROME": "sim_chrome",
    "CLASSIC-Neg.": "sim_negative",
    "PRO-Neg.Std": "sim_nostalgic",
    "ETERNA": "sim_cinema",
    "ETERNA-BB": "sim_bleach",
    "ACROS": "sim_mono",
}

FLOG2_A = 5.555556
FLOG2_B = 0.064829
FLOG2_C = 0.245281
FLOG2_D = 0.384316
FLOG2_E = 8.799461
FLOG2_F = 0.092864
FLOG2_CUT1 = 0.000889

BT709_TO_BT2020 = np.array([
    [0.6274040, 0.3292820, 0.0433136],
    [0.0690970, 0.9195400, 0.0113612],
    [0.0163916, 0.0880132, 0.8955950],
])


def parse_cube(path):
    size = None
    values = []
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("TITLE"):
                continue
            if line.startswith("LUT_3D_SIZE"):
                size = int(line.split()[1])
                continue
            if line.startswith("DOMAIN_MIN") or line.startswith("DOMAIN_MAX"):
                continue
            parts = line.split()
            if len(parts) >= 3:
                values.append([float(parts[0]), float(parts[1]), float(parts[2])])
    if size is None:
        raise ValueError("missing LUT_3D_SIZE")
    data = np.array(values, dtype=np.float64)
    expected = size ** 3
    if data.shape[0] != expected:
        raise ValueError(f"expected {expected} rows, got {data.shape[0]}")
    return size, np.clip(data, 0.0, 1.0)


def sample_lut(size, data, rgb):
    points = np.clip(rgb, 0.0, 1.0) * (size - 1)
    base = np.floor(points).astype(np.int64)
    frac = points - base
    upper = np.minimum(base + 1, size - 1)

    def value(r, g, b):
        index = r + g * size + b * size * size
        return data[index]

    c000 = value(base[:, 0], base[:, 1], base[:, 2])
    c100 = value(upper[:, 0], base[:, 1], base[:, 2])
    c010 = value(base[:, 0], upper[:, 1], base[:, 2])
    c110 = value(upper[:, 0], upper[:, 1], base[:, 2])
    c001 = value(base[:, 0], base[:, 1], upper[:, 2])
    c101 = value(upper[:, 0], base[:, 1], upper[:, 2])
    c011 = value(base[:, 0], upper[:, 1], upper[:, 2])
    c111 = value(upper[:, 0], upper[:, 1], upper[:, 2])

    fx = frac[:, 0:1]
    fy = frac[:, 1:2]
    fz = frac[:, 2:3]
    c00 = c000 + (c100 - c000) * fx
    c10 = c010 + (c110 - c010) * fx
    c01 = c001 + (c101 - c001) * fx
    c11 = c011 + (c111 - c011) * fx
    c0 = c00 + (c10 - c00) * fy
    c1 = c01 + (c11 - c01) * fy
    return c0 + (c1 - c0) * fz


def srgb_to_linear(value):
    value = np.clip(value, 0.0, 1.0)
    return np.where(value <= 0.04045, value / 12.92, ((value + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(value):
    value = np.clip(value, 0.0, 1.0)
    return np.where(value <= 0.0031308, value * 12.92, 1.055 * value ** (1 / 2.4) - 0.055)


def encode_flog2(value):
    value = np.maximum(value, 0.0)
    return np.where(
        value >= FLOG2_CUT1,
        FLOG2_C * np.log10(FLOG2_A * value + FLOG2_B) + FLOG2_D,
        FLOG2_E * value + FLOG2_F,
    )


def bt709_to_linear(value):
    value = np.clip(value, 0.0, 1.0)
    return np.where(value < 0.081, value / 4.5, ((value + 0.099) / 1.099) ** (1 / 0.45))


def adapt_flog2(size, data):
    steps = np.linspace(0.0, 1.0, size)
    b, g, r = np.meshgrid(steps, steps, steps, indexing="ij")
    srgb = np.stack([r.ravel(), g.ravel(), b.ravel()], axis=1)
    linear = srgb_to_linear(srgb)
    linear_2020 = linear @ BT709_TO_BT2020.T
    log = encode_flog2(linear_2020)
    mapped = sample_lut(size, data, log)
    out_linear = bt709_to_linear(mapped)
    return size, np.clip(linear_to_srgb(out_linear), 0.0, 1.0)


def load_our_lut(name):
    path = os.path.join(OUR_LUT_DIR, f"{name}.png")
    image = np.array(Image.open(path).convert("RGB")).reshape(-1, 3) / 255.0
    return SIZE, image


def make_chart(size=480):
    image = Image.new("RGB", (size, size), (24, 24, 24))
    draw = ImageDraw.Draw(image)

    steps = 12
    cell_w = size // steps
    for index in range(steps):
        value = int(index / (steps - 1) * 255)
        draw.rectangle(
            [index * cell_w, 0, (index + 1) * cell_w, cell_w],
            fill=(value, value, value),
        )

    patches = [
        (232, 190, 172), (198, 134, 66), (110, 60, 40), (240, 210, 190),
        (90, 140, 200), (60, 90, 140), (120, 170, 90), (40, 90, 50),
        (200, 60, 50), (230, 160, 40), (120, 80, 160), (200, 200, 200),
    ]
    for index, color in enumerate(patches):
        row, column = divmod(index, 4)
        x = column * (size // 4) + 8
        y = cell_w + 12 + row * (size // 4)
        draw.rectangle([x, y, x + size // 4 - 16, y + size // 4 - 24], fill=color)

    for y in range(cell_w, size):
        ratio = (y - cell_w) / max(size - cell_w, 1)
        for x in range(size):
            base = image.getpixel((x, y))
            blend = tuple(int(channel * (0.85 + 0.3 * ratio)) for channel in base)
            image.putpixel((x, y), tuple(min(255, channel) for channel in blend))
    return image


def apply_to_image(size, data, image):
    array = np.array(image).reshape(-1, 3) / 255.0
    result = sample_lut(size, data, array)
    return Image.fromarray(
        np.round(np.clip(result, 0, 1).reshape(image.height, image.width, 3) * 255).astype(np.uint8)
    )


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    lut_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join("build", "compare")
    os.makedirs(out_dir, exist_ok=True)

    chart = make_chart()
    chart.save(os.path.join(out_dir, "chart.png"))

    for fuji_name, our_name in MAPPING.items():
        fuji_path = os.path.join(lut_dir, f"FLog2_to_{fuji_name}_33grid_V.1.00.cube")
        if not os.path.exists(fuji_path):
            print(f"skip {fuji_name}: file not found")
            continue

        fuji_size, fuji_raw = parse_cube(fuji_path)
        fuji_size, fuji_data = adapt_flog2(fuji_size, fuji_raw)
        fuji_image = apply_to_image(fuji_size, fuji_data, chart)

        our_size, our_data = load_our_lut(our_name)
        our_image = apply_to_image(our_size, our_data, chart)

        canvas = Image.new("RGB", (chart.width * 3, chart.height))
        canvas.paste(chart, (0, 0))
        canvas.paste(fuji_image, (chart.width, 0))
        canvas.paste(our_image, (chart.width * 2, 0))
        canvas.save(os.path.join(out_dir, f"{our_name}.png"))

        fuji_array = np.array(fuji_image, dtype=np.float64) / 255.0
        our_array = np.array(our_image, dtype=np.float64) / 255.0
        mae = np.abs(fuji_array - our_array).mean()
        print(f"{our_name:16s} vs {fuji_name:14s} MAE={mae:.4f}")

    print(f"written to {out_dir}")


if __name__ == "__main__":
    main()
