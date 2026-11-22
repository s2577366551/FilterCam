#!/usr/bin/env python3
"""把富士官方 33-grid LUT 转成 App 用的紧凑二进制（已适配 sRGB 照片）。

原始 LUT 是为 F-Log / F-Log2 / F-Log2C 视频设计的，直接套在普通照片上会发灰发暗。
这里在构建期做一次反向适配：
  sRGB -> 线性 BT.709 -> 线性 BT.2020 -> Log 编码 -> 采样官方 LUT
  -> BT.709 解码 -> sRGB
输出 33^3 RGBA8，顺序 r 最快、b 最慢，和 CIColorCube 一致。
"""

import hashlib
import io
import json
import os
import re
import struct
import sys

import numpy as np

SRC = r"D:\Cache\Temp\opencode\fuji-lut\extracted"
OUT = r"C:\Users\25773\FilterCam\FilterCam\Resources\OfficialLUTs"

N = 33
BT709_TO_BT2020 = np.array([
    [0.6274040, 0.3292820, 0.0433136],
    [0.0690970, 0.9195400, 0.0113612],
    [0.0163916, 0.0880132, 0.8955950],
], dtype=np.float64)


def parse_cube(path):
    size = None
    rows = []
    with io.open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("LUT_3D_SIZE"):
                size = int(line.split()[1])
                continue
            if line.startswith(("TITLE", "DOMAIN_MIN", "DOMAIN_MAX", "LUT_1D_SIZE")):
                continue
            parts = line.split()
            if len(parts) >= 3:
                rows.append((float(parts[0]), float(parts[1]), float(parts[2])))
    if size is None:
        raise ValueError("missing LUT_3D_SIZE: " + path)
    if len(rows) != size ** 3:
        raise ValueError(f"row count {len(rows)} != {size**3}: {path}")
    arr = np.array(rows, dtype=np.float64).reshape(size, size, size, 3)  # [b][g][r]
    return arr


def srgb_to_linear(v):
    v = np.clip(v, 0.0, 1.0)
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(v):
    v = np.clip(v, 0.0, 1.0)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(v, 1 / 2.4) - 0.055)


def encode_flog2(v):
    v = np.maximum(v, 0.0)
    cut1, a, b, c, d, e, f = 0.000889, 5.555556, 0.064829, 0.245281, 0.384316, 8.799461, 0.092864
    return np.where(v >= cut1, c * np.log10(a * v + b) + d, e * v + f)


def encode_flog(v):
    v = np.maximum(v, 0.0)
    cut1, a, b, c, d, e, f = 0.00089, 0.555556, 0.009468, 0.244161, 0.344676, 8.735631, 0.092864
    return np.where(v >= cut1, c * np.log10(a * v + b) + d, e * v + f)


def bt709_to_linear(v):
    v = np.clip(v, 0.0, 1.0)
    return np.where(v < 0.081, v / 4.5, ((v + 0.099) / 1.099) ** (1 / 0.45))


def trilinear(cube, log):
    n = cube.shape[0]
    max_i = n - 1
    x = np.clip(log[..., 0], 0, 1) * max_i
    y = np.clip(log[..., 1], 0, 1) * max_i
    z = np.clip(log[..., 2], 0, 1) * max_i
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int); z0 = np.floor(z).astype(int)
    x1 = np.minimum(x0 + 1, max_i); y1 = np.minimum(y0 + 1, max_i); z1 = np.minimum(z0 + 1, max_i)
    fx = (x - x0)[..., None]; fy = (y - y0)[..., None]; fz = (z - z0)[..., None]
    c000 = cube[z0, y0, x0]; c100 = cube[z0, y0, x1]
    c010 = cube[z0, y1, x0]; c110 = cube[z0, y1, x1]
    c001 = cube[z1, y0, x0]; c101 = cube[z1, y0, x1]
    c011 = cube[z1, y1, x0]; c111 = cube[z1, y1, x1]
    c00 = c000 + (c100 - c000) * fx
    c10 = c010 + (c110 - c010) * fx
    c01 = c001 + (c101 - c001) * fx
    c11 = c011 + (c111 - c011) * fx
    c0 = c00 + (c10 - c00) * fy
    c1 = c01 + (c11 - c01) * fy
    return c0 + (c1 - c0) * fz


def adapt(cube, log_type):
    n = cube.shape[0]
    axis = np.linspace(0, 1, n)
    bb, gg, rr = np.meshgrid(axis, axis, axis, indexing="ij")  # [b][g][r]
    srgb = np.stack([rr, gg, bb], axis=-1)
    linear709 = srgb_to_linear(srgb)
    linear2020 = linear709 @ BT709_TO_BT2020.T
    if log_type == "flog":
        log = encode_flog(linear2020)
    else:
        log = encode_flog2(linear2020)
    mapped = trilinear(cube, log)
    out_linear = bt709_to_linear(mapped)
    out_srgb = linear_to_srgb(out_linear)
    return np.clip(out_srgb, 0, 1)


CAMERA_NAMES = {
    "XH1": "X-H1", "XH2": "X-H2", "XH2S": "X-H2S", "XE4": "X-E4", "XE5": "X-E5",
    "XT2": "X-T2", "XT3": "X-T3", "XT4": "X-T4", "XT5": "X-T5",
    "XS10": "X-S10", "XS20": "X-S20", "XPRO3": "X-Pro3", "X100V": "X100V",
    "X100VI": "X100VI", "XT30": "X-T30", "XT30II": "X-T30 II", "XT30III": "X-T30 III",
    "XT50": "X-T50", "XM5": "X-M5", "GFX100": "GFX100", "GFX100S": "GFX100S",
    "GFX100II": "GFX100 II", "GFX100SII": "GFX100S II", "GFX100RF": "GFX100RF",
    "GFXETERNA55": "GFX ETERNA 55",
}

SIM_NAMES = {
    "ACROS": "ACROS",
    "ASTIA": "ASTIA",
    "CLASSIC-CHROME": "CLASSIC CHROME",
    "CLASSIC-Neg.": "CLASSIC Neg",
    "ETERNA": "ETERNA",
    "ETERNA-BB": "ETERNA BB",
    "PRO-Neg.Std": "PRO Neg Std",
    "PROVIA": "PROVIA",
    "REALA-ACE": "REALA ACE",
    "Velvia": "Velvia",
    "FLog2-709": "F-Log2 709",
    "FLog2C-709": "F-Log2C 709",
    "FLog-709": "F-Log 709",
    "FLog": "F-Log 709",
    "WDR": "WDR 709",
    "WDR-709": "WDR 709",
}


def classify(filename):
    base = filename[:-5]  # strip .cube
    log_type = "flog2"
    if base.startswith("FLog2C_") or "FLog2C" in base.split("_")[:2]:
        log_type = "flog2c"
    elif base.startswith("FLog2_") or "FLog2" in base.split("_")[:2]:
        log_type = "flog2"
    elif base.startswith("FLog_") or "FLog" in base.split("_")[:2]:
        log_type = "flog"

    camera = None
    m = re.match(r"^(X[A-Z0-9]+|GFX[0-9A-Z]+)_", base)
    if m:
        camera = CAMERA_NAMES.get(m.group(1), m.group(1))

    sim = None
    m = re.search(r"_to_(.+?)(?:_BT\.709|_33grid|$)", base)
    if m:
        sim = m.group(1)
    if sim is None:
        m = re.search(r"_to_(.+)$", base)
        sim = m.group(1) if m else base
    sim = SIM_NAMES.get(sim, sim.replace("_", " ").replace("-", " "))

    group = {"flog2": "F-Log2", "flog2c": "F-Log2C", "flog": "F-Log"}[log_type]
    name = sim
    if log_type == "flog2c":
        name += " (F-Log2C)"
    elif log_type == "flog":
        name += " (F-Log)"
    if camera:
        name += f" · {camera}"
    return name, group, log_type, camera, sim


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        os.remove(os.path.join(OUT, old))

    seen_src = {}
    for root, _, files in os.walk(SRC):
        for f in files:
            if not f.endswith(".cube") or "65grid" in f:
                continue
            path = os.path.join(root, f)
            digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
            # 优先保留通用命名（FLog2_to_...），避免留下相机专属重复项。
            if digest in seen_src:
                if f.startswith("FLog") and not os.path.basename(seen_src[digest]).startswith("FLog"):
                    seen_src[digest] = path
                continue
            seen_src[digest] = path

    adapted_seen = {}
    entries = []
    for path in seen_src.values():
        fname = os.path.basename(path)
        name, group, log_type, camera, sim = classify(fname)
        cube = parse_cube(path)
        adapted = adapt(cube, log_type)
        payload = (adapted * 255.0 + 0.5).astype(np.uint8)
        # 扁平化成 r 最快、b 最慢
        flat = payload.reshape(-1, 3)
        alpha = np.full((flat.shape[0], 1), 255, dtype=np.uint8)
        rgba = np.concatenate([flat, alpha], axis=1).tobytes()

        digest = hashlib.sha256(rgba).hexdigest()
        if digest in adapted_seen:
            existing = adapted_seen[digest]
            # 通用命名优先于相机专属
            if existing["camera"] and not camera:
                old_file = existing["file"]
                existing.update(name=name, group=group, camera=camera, sim=sim)
                new_file = "official_" + re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") + ".rgba"
                os.replace(os.path.join(OUT, old_file), os.path.join(OUT, new_file))
                existing["file"] = new_file
            continue

        slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        file_name = f"official_{slug}.rgba"
        with open(os.path.join(OUT, file_name), "wb") as fh:
            fh.write(rgba)
        entry = {
            "id": slug,
            "name": name,
            "group": group,
            "camera": camera or "",
            "sim": sim,
            "file": file_name,
        }
        adapted_seen[digest] = entry
        entries.append(entry)

    order = {"F-Log2": 0, "F-Log2C": 1, "F-Log": 2}
    entries.sort(key=lambda e: (order.get(e["group"], 9), e["name"]))
    with io.open(os.path.join(OUT, "official_luts.json"), "w", encoding="utf-8") as fh:
        json.dump(entries, fh, ensure_ascii=False, indent=2)

    total = sum(os.path.getsize(os.path.join(OUT, e["file"])) for e in entries)
    print(f"entries: {len(entries)}")
    print(f"total: {total/1024/1024:.1f} MB")
    for e in entries:
        print(f"  {e['group']:8} {e['name']}")


if __name__ == "__main__":
    main()
