#!/usr/bin/env python3
"""生成 32³ LUT。输出为 1024x32 的 PNG，像素顺序为 r 最慢、b 最快。"""

import os

import numpy as np
from PIL import Image

SIZE = 32
OUT_DIR = os.path.join("FilterCam", "Resources", "LUTs")

LUMA = np.array([0.2126, 0.7152, 0.0722])

FILTERS = {
    # 胶片模拟
    "sim_standard": dict(exposure=0.05, contrast=1.02, saturation=1.04, temperature=0.02, gamma=1.0),
    "sim_vivid": dict(exposure=0.10, contrast=1.12, saturation=1.25, temperature=0.05),
    "sim_soft": dict(exposure=0.08, contrast=0.92, saturation=0.92, lift=0.03, gamma=1.05),
    "sim_chrome": dict(contrast=1.08, saturation=0.72, temperature=-0.05, shadow_tint=[-0.04, 0.02, 0.05], highlight_tint=[0.02, 0.01, -0.02]),
    "sim_negative": dict(contrast=1.18, saturation=1.05, temperature=0.08, tint=0.05, shadow_tint=[0.05, -0.02, 0.02]),
    "sim_nostalgic": dict(contrast=1.05, saturation=0.95, temperature=0.16, lift=0.02, highlight_tint=[0.06, 0.04, -0.03]),
    "sim_cinema": dict(contrast=1.02, saturation=0.82, temperature=-0.02, lift=0.03, shadow_tint=[-0.02, 0.03, 0.02]),
    "sim_bleach": dict(contrast=1.35, saturation=0.45, gamma=0.95),
    "sim_mono": dict(mono=True, contrast=1.08, gamma=1.02),
    "sim_mono_red": dict(mono=True, mono_weights=[0.35, 0.55, 0.10], contrast=1.12),

    # 经典胶片
    "warm_portrait": dict(exposure=0.06, contrast=0.98, saturation=1.02, temperature=0.10, highlight_tint=[0.04, 0.03, 0.0]),
    "cool_portrait": dict(exposure=0.04, contrast=1.0, saturation=0.98, temperature=-0.08, shadow_tint=[0.0, 0.02, 0.04]),
    "golden_day": dict(exposure=0.08, contrast=1.06, saturation=1.05, temperature=0.18, highlight_tint=[0.05, 0.03, -0.02]),
    "vivid_landscape": dict(contrast=1.14, saturation=1.22, temperature=-0.03, gamma=0.98),
    "daily_street": dict(contrast=1.04, saturation=0.90, temperature=-0.04, shadow_tint=[-0.02, 0.01, 0.03]),
    "coarse_mono": dict(mono=True, contrast=1.18, lift=0.02),
    "high_contrast_mono": dict(mono=True, contrast=1.45, gamma=0.92),
    "tungsten_night": dict(contrast=1.10, saturation=0.95, temperature=0.22, shadow_tint=[0.0, -0.02, 0.08]),
    "instant": dict(contrast=0.88, saturation=0.80, temperature=-0.06, lift=0.06, gamma=1.08),
    "retro_red": dict(contrast=1.05, saturation=0.78, temperature=0.12, tint=0.08),

    # 电影感
    "teal_orange": dict(contrast=1.10, saturation=1.02, shadow_tint=[-0.06, 0.02, 0.07], highlight_tint=[0.07, 0.02, -0.05]),
    "bleach_bypass": dict(contrast=1.30, saturation=0.55, gamma=0.98),
    "cross_process": dict(contrast=1.16, saturation=1.10, shadow_tint=[-0.05, 0.05, 0.03], highlight_tint=[0.08, 0.03, -0.06]),
    "faded_matte": dict(contrast=0.85, saturation=0.85, lift=0.08, gamma=1.06),
    "warm_cinema": dict(contrast=1.04, saturation=0.95, temperature=0.14, lift=0.02),
    "cool_noir": dict(contrast=1.22, saturation=0.72, temperature=-0.14, shadow_tint=[-0.03, 0.0, 0.06]),
    "neon_night": dict(contrast=1.18, saturation=1.35, tint=0.06, shadow_tint=[0.06, -0.04, 0.10]),
    "desert": dict(contrast=1.06, saturation=0.80, temperature=0.20, lift=0.03),

    # 季节情绪
    "spring": dict(exposure=0.10, contrast=0.94, saturation=1.06, temperature=0.04, tint=0.05, lift=0.03),
    "summer": dict(exposure=0.06, contrast=1.10, saturation=1.20, temperature=0.10),
    "autumn": dict(contrast=1.08, saturation=1.10, temperature=0.20, tint=0.04),
    "winter": dict(contrast=1.02, saturation=0.82, temperature=-0.18, shadow_tint=[0.0, 0.02, 0.06]),
    "rainy": dict(contrast=0.92, saturation=0.72, temperature=-0.10, lift=0.04, gamma=1.04),
    "sunset": dict(contrast=1.06, saturation=1.12, temperature=0.24, highlight_tint=[0.08, 0.02, -0.04]),
    "dawn": dict(exposure=0.06, contrast=0.90, saturation=0.88, temperature=-0.06, lift=0.05, gamma=1.06),
    "forest": dict(contrast=1.04, saturation=0.95, temperature=-0.08, tint=0.06, shadow_tint=[-0.03, 0.05, 0.0]),

    # 复古实验
    "sepia": dict(mono=True, mono_tint=[0.12, 0.06, -0.04], contrast=1.06, gamma=1.04),
    "cyanotype": dict(mono=True, mono_tint=[-0.08, 0.0, 0.16], contrast=1.10),
    "infrared": dict(contrast=1.16, saturation=0.90, shadow_tint=[0.02, 0.06, -0.02], highlight_tint=[0.10, -0.02, 0.04]),
    "lomo": dict(contrast=1.28, saturation=1.35, temperature=0.05, tint=0.04),
    "duotone_purple": dict(mono=True, mono_tint=[0.08, -0.04, 0.14], contrast=1.08),
    "negative": dict(invert=True, contrast=1.04),
}


def apply_params(rgb: np.ndarray, p: dict) -> np.ndarray:
    x = rgb.astype(np.float64).copy()

    if p.get("invert"):
        x = 1.0 - x

    x *= 2.0 ** p.get("exposure", 0.0)
    x = (x - 0.5) * p.get("contrast", 1.0) + 0.5

    sat = p.get("saturation", 1.0)
    luma = x @ LUMA
    x = luma[:, None] + (x - luma[:, None]) * sat

    temp = p.get("temperature", 0.0)
    if temp:
        x[:, 0] *= 1.0 + 0.25 * temp
        x[:, 2] *= 1.0 - 0.25 * temp

    tint = p.get("tint", 0.0)
    if tint:
        x[:, 1] *= 1.0 + 0.20 * tint

    luma2 = np.clip(x @ LUMA, 0.0, 1.0)[:, None]
    shadow_w = np.clip(1.0 - luma2 * 2.0, 0.0, 1.0)
    highlight_w = np.clip(luma2 * 2.0 - 1.0, 0.0, 1.0)
    x += np.array(p.get("shadow_tint", [0, 0, 0])) * shadow_w * 0.15
    x += np.array(p.get("highlight_tint", [0, 0, 0])) * highlight_w * 0.15

    x = np.clip(x, 0.0, 1.0)
    x = x * p.get("gain", 1.0) + p.get("lift", 0.0)
    x = np.clip(x, 0.0, 1.0) ** (1.0 / p.get("gamma", 1.0))

    if p.get("mono"):
        weights = np.array(p.get("mono_weights", [0.2126, 0.7152, 0.0722]))
        luma3 = x @ weights
        x = luma3[:, None] + np.array(p.get("mono_tint", [0, 0, 0]))

    return np.clip(x, 0.0, 1.0)


def build_cube(params: dict) -> np.ndarray:
    steps = np.linspace(0.0, 1.0, SIZE)
    r = np.repeat(steps, SIZE * SIZE)
    g = np.tile(np.repeat(steps, SIZE), SIZE)
    b = np.tile(steps, SIZE * SIZE)
    rgb = np.stack([r, g, b], axis=1)
    return apply_params(rgb, params)


def save_cube(values: np.ndarray, path: str) -> None:
    rgba = np.ones((SIZE * SIZE * SIZE, 4), dtype=np.uint8) * 255
    rgba[:, :3] = np.round(values * 255.0).astype(np.uint8)
    image = Image.fromarray(rgba.reshape(SIZE, SIZE * SIZE, 4))
    image.save(path)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    save_cube(build_cube({}), os.path.join(OUT_DIR, "identity.png"))
    for name, params in FILTERS.items():
        save_cube(build_cube(params), os.path.join(OUT_DIR, f"{name}.png"))
    print(f"generated {len(FILTERS) + 1} LUTs in {OUT_DIR}")


if __name__ == "__main__":
    main()
