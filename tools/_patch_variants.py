import io

path = "tools/make_icon_variants.py"
with io.open(path, encoding="utf-8") as f:
    lines = f.readlines()

start = next(i for i, l in enumerate(lines) if l.startswith("def scene_desert("))
end = next(i for i, l in enumerate(lines) if l.startswith("SCENES = ["))

new = '''def scene_balloon(w, h):
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


'''

lines[start:end] = [new]
text = "".join(lines)
text = text.replace(
    '("沙漠公路", scene_desert, [(255, 198, 140), (246, 128, 138)], (255, 200, 60)),',
    '("热气球", scene_balloon, [(255, 214, 186), (226, 156, 178)], (255, 206, 80)),',
)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(text)
print("patched")
