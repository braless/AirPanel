#!/usr/bin/env python3
"""AirPanel 图标生成器。

只依赖 Pillow。所有尺寸按 1024 基准归一化，内部 3 倍超采样再降采样，
避免圆角、圆弧出现锯齿。

    python3 tools/make_icon.py            # 生成 variants/ 里的候选图
    python3 tools/make_icon.py --final    # 生成最终的 AppIcon 1024 PNG
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 1024          # 设计基准
SS = 3            # 超采样倍数
W = S * SS

ACCENT = (10, 132, 255)
ACCENT_LIGHT = (86, 180, 255)
WHITE = (255, 255, 255)


# ---------------------------------------------------------------- 基础工具

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical_gradient(size, stops):
    """stops: [(位置0..1, rgb), ...]"""
    w, h = size
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            p0, c0 = stops[i]
            p1, c1 = stops[i + 1]
            if p0 <= t <= p1:
                px[0, y] = lerp(c0, c1, (t - p0) / max(1e-6, p1 - p0))
                break
        else:
            px[0, y] = stops[-1][1]
    return strip.resize((w, h), Image.BICUBIC)


def radial_glow(size, color, center, radius, strength=1.0):
    """中心亮、边缘透明的径向光斑（返回 RGBA）。"""
    small = 256
    img = Image.new("RGBA", (small, small), (0, 0, 0, 0))
    px = img.load()
    cx, cy = center[0] * small, center[1] * small
    r = radius * small
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - cx, y - cy) / max(1e-6, r)
            if d >= 1:
                continue
            a = (1 - d) ** 2.2 * strength
            px[x, y] = (color[0], color[1], color[2], round(a * 255))
    return img.resize(size, Image.BICUBIC)


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(box, radius=radius, fill=255)
    return m


def arc_with_caps(draw, center, radius, start, end, width, fill):
    """PIL 的 arc 没有圆头，自己在两端补圆。角度：0=3 点方向，顺时针。"""
    cx, cy = center
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    # PIL 不支持 end > 360，拆成两段
    segs = []
    a = start
    while a < end:
        b = min(a + 360, end)
        segs.append((a % 360, b % 360 if b % 360 != 0 else 360))
        a = b
    for a, b in segs:
        draw.arc(box, a, b, fill=fill, width=width)

    rr = radius - width / 2
    for ang in (start, end):
        t = math.radians(ang)
        px, py = cx + rr * math.cos(t), cy + rr * math.sin(t)
        draw.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=fill)


def gradient_arc(draw, center, radius, start, end, width, c0, c1):
    """沿弧线做颜色渐变：PIL 的 arc 只能单色，这里按 1° 分段画线。"""
    cx, cy = center
    rr = radius - width / 2
    n = max(2, int(abs(end - start)))
    for i in range(n):
        a0 = math.radians(start + i)
        a1 = math.radians(start + i + 1)
        t = i / (n - 1)
        draw.line([(cx + rr * math.cos(a0), cy + rr * math.sin(a0)),
                   (cx + rr * math.cos(a1), cy + rr * math.sin(a1))],
                  fill=lerp(c0, c1, t) + (255,), width=width)
    for ang, col in ((start, c0), (end, c1)):
        t = math.radians(ang)
        px, py = cx + rr * math.cos(t), cy + rr * math.sin(t)
        draw.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2],
                     fill=col + (255,))


# 闪电：0..1 归一化坐标（y 向下）
BOLT = [(0.575, 0.020), (0.185, 0.560), (0.450, 0.560),
        (0.385, 0.980), (0.815, 0.420), (0.520, 0.420)]


def bolt_points(cx, cy, height, width_scale=1.0):
    """把归一化闪电按高度缩放到画布坐标。"""
    xs = [p[0] for p in BOLT]
    ys = [p[1] for p in BOLT]
    w0, h0 = max(xs) - min(xs), max(ys) - min(ys)
    k = height / h0
    wpx = w0 * k * width_scale
    left = cx - wpx / 2 - min(xs) * k
    top = cy - height / 2
    return [(left + x * k, top + y * k) for x, y in BOLT]


def base_canvas():
    """深蓝黑渐变 + 左上蓝光，作为所有候选的共同底。"""
    img = vertical_gradient(
        (W, W),
        [(0.0, (16, 32, 58)), (0.45, (9, 17, 32)), (1.0, (4, 6, 12))],
    ).convert("RGBA")
    img.alpha_composite(radial_glow((W, W), ACCENT, (0.30, 0.18), 0.75, 0.55))
    img.alpha_composite(radial_glow((W, W), (40, 90, 200), (0.86, 0.92), 0.60, 0.35))
    return img


def vignette(size, start=0.62, strength=0.42):
    """只在最外圈压暗。

    不能用 radial_glow 反相：它的衰减是二次的，反相后在 20% 半径处
    就已经压掉 40%，白色字形会被压成灰色（实测 255 → 206）。
    """
    small = 256
    img = Image.new("L", (small, small), 0)
    px = img.load()
    cx = cy = small / 2
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - cx, y - cy) / (small / 2 * 1.35)
            if d <= start:
                continue
            t = min(1.0, (d - start) / (1 - start))
            px[x, y] = round((t ** 1.6) * strength * 255)
    return img.resize(size, Image.BICUBIC)


def finish(img):
    dark = Image.new("RGBA", (W, W), (0, 0, 0, 255))
    dark.putalpha(vignette((W, W)))
    img.alpha_composite(dark)
    return img.resize((S, S), Image.LANCZOS)


# ---------------------------------------------------------------- 候选方案

def variant_ring():
    """圆环仪表 + 闪电：呼应概览页的电量环，环＝监控，闪电＝下发。

    环用「掩码画弧 + 渐变着色」而不是逐度画线——后者在 3 倍超采样下
    仍会留下肉眼可见的梳齿。
    """
    img = base_canvas()
    c = (W / 2, W / 2)
    R = W * 0.360
    wid = round(W * 0.100)
    start, end = 135, 405

    mask = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(mask)
    d.arc([c[0] - R, c[1] - R, c[0] + R, c[1] + R], 135, 360, fill=255, width=wid)
    d.arc([c[0] - R, c[1] - R, c[0] + R, c[1] + R], 0, 45, fill=255, width=wid)
    rr = R - wid / 2
    for ang in (start, end):
        t = math.radians(ang)
        px, py = c[0] + rr * math.cos(t), c[1] + rr * math.sin(t)
        d.ellipse([px - wid / 2, py - wid / 2, px + wid / 2, py + wid / 2], fill=255)

    # 沿 135°→405° 的走向做蓝→浅蓝渐变（用斜向线性渐变近似）
    grad = vertical_gradient((W, W), [(0.0, (0, 92, 220)), (0.55, ACCENT), (1.0, ACCENT_LIGHT)]).convert("RGBA")
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ring.paste(grad, (0, 0), mask)

    # 环内侧一点辉光，让它像发光而不是贴纸
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    glow.paste(Image.new("RGBA", (W, W), ACCENT + (255,)), (0, 0), mask)
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.035))
    glow.putalpha(glow.getchannel("A").point(lambda a: round(a * 0.55)))
    img.alpha_composite(glow)
    img.alpha_composite(ring)

    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(bolt_points(W / 2, W / 2 + W * 0.012, W * 0.345), fill=WHITE + (255,))
    img.alpha_composite(layer)
    return finish(img)


def variant_broadcast():
    """信号弧 + 原点：Air 的「无线」意象。"""
    img = base_canvas()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    origin = (W * 0.30, W * 0.72)
    for i, r in enumerate((0.165, 0.255, 0.345)):
        arc_with_caps(d, origin, W * r, -90, 0, round(W * 0.062),
                      (255, 255, 255, 255 if i < 2 else 150))
    d.ellipse([origin[0] - W * 0.055, origin[1] - W * 0.055,
               origin[0] + W * 0.055, origin[1] + W * 0.055], fill=WHITE + (255,))
    img.alpha_composite(layer)
    return finish(img)


def variant_panel():
    """面板 + 信号弧：一台在发信号的设备。"""
    img = base_canvas()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # 面板
    bw, bh = W * 0.42, W * 0.30
    box = [W / 2 - bw / 2, W * 0.50, W / 2 + bw / 2, W * 0.50 + bh]
    d.rounded_rectangle(box, radius=W * 0.075, fill=(255, 255, 255, 235))

    # 面板里的三条信号柱
    bar_w = W * 0.045
    base_y = box[3] - W * 0.055
    for i, h in enumerate((0.085, 0.135, 0.19)):
        x = W / 2 - W * 0.105 + i * W * 0.075
        d.rounded_rectangle([x, base_y - W * h, x + bar_w, base_y],
                            radius=bar_w / 2, fill=ACCENT + (255,))

    # 面板上方的两段弧
    for r in (0.20, 0.30):
        arc_with_caps(d, (W / 2, W * 0.52), W * r, 200, 340, round(W * 0.05),
                      (255, 255, 255, 210))
    img.alpha_composite(layer)
    return finish(img)


def variant_tile():
    """圆角方块 + 挖空闪电：和 TabBar 的 bolt.circle 同一套几何语言。"""
    img = base_canvas()
    size = W * 0.575
    box = [W / 2 - size / 2, W / 2 - size / 2, W / 2 + size / 2, W / 2 + size / 2]

    mask = rounded_mask((W, W), box, size * 0.285)
    cut = Image.new("L", (W, W), 0)
    ImageDraw.Draw(cut).polygon(bolt_points(W / 2, W / 2, size * 0.56), fill=255)
    mask = Image.composite(Image.new("L", (W, W), 0), mask, cut)

    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    tile.paste(Image.new("RGBA", (W, W), WHITE + (255,)), (0, 0), mask)
    img.alpha_composite(tile)
    return finish(img)


def variant_tile_blue():
    """蓝色渐变瓷片 + 白色闪电：小尺寸下最抗糊。"""
    img = base_canvas()
    size = W * 0.60
    box = [W / 2 - size / 2, W / 2 - size / 2, W / 2 + size / 2, W / 2 + size / 2]

    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    d.rounded_rectangle(box, radius=size * 0.27, fill=(0, 0, 0, 0))
    grad = vertical_gradient((W, W), [(0.0, (94, 186, 255)), (0.55, (10, 132, 255)), (1.0, (0, 88, 214))]).convert("RGBA")
    tile.paste(grad, (0, 0), rounded_mask((W, W), box, size * 0.27))
    # 上沿一道高光，模拟玻璃
    hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(
        [box[0] + W * 0.02, box[1] + W * 0.015, box[2] - W * 0.02, box[1] + size * 0.30],
        radius=size * 0.24, fill=(255, 255, 255, 46))
    hl.putalpha(Image.composite(hl.getchannel("A"),
                                Image.new("L", (W, W), 0),
                                rounded_mask((W, W), box, size * 0.27)))
    tile.alpha_composite(hl)
    d.polygon(bolt_points(W / 2, W / 2, size * 0.56), fill=WHITE + (255,))
    img.alpha_composite(tile)
    return finish(img)


def variant_bars():
    """三条信号柱：直接画，不加外框——小尺寸下最不容易糊成一团。"""
    img = base_canvas()
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    bw = W * 0.105
    gap = W * 0.055
    total = bw * 3 + gap * 2
    left = W / 2 - total / 2
    base = W * 0.755
    heights = (0.20, 0.32, 0.45)
    for i, h in enumerate(heights):
        x = left + i * (bw + gap)
        col = ACCENT if i == 2 else (255, 255, 255, 235)
        d.rounded_rectangle([x, base - W * h, x + bw, base], radius=bw / 2, fill=col)
    img.alpha_composite(layer)
    return finish(img)


def variant_tile_bars():
    """蓝色瓷片 + 三条信号柱：瓷片给品牌色，柱子说「在监控信号」。

    瓷片占画布 0.68：iOS 图标的视觉主体通常在 0.7 上下，
    再小就会在桌面上显得「缩在中间」。
    """
    img = base_canvas()
    size = W * 0.68
    box = [W / 2 - size / 2, W / 2 - size / 2, W / 2 + size / 2, W / 2 + size / 2]
    radius = size * 0.265
    mask = rounded_mask((W, W), box, radius)

    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    grad = vertical_gradient(
        (W, W),
        [(0.0, (92, 182, 255)), (0.45, (16, 136, 255)), (1.0, (0, 82, 204))],
    ).convert("RGBA")
    tile.paste(grad, (0, 0), mask)

    # 上沿一点柔光，代替原来那道横贯整块的硬高光
    sheen = radial_glow((W, W), (255, 255, 255), (0.5, 0.06), 0.55, 0.30)
    sheen.putalpha(Image.composite(sheen.getchannel("A"), Image.new("L", (W, W), 0), mask))
    tile.alpha_composite(sheen)

    # 柱子：纯白不透明，单独一层再合成（直接画 alpha 会被背景吃掉）
    bars = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(bars)
    bw = size * 0.150
    gap = size * 0.082
    left = W / 2 - (bw * 3 + gap * 2) / 2
    base = W / 2 + size * 0.250
    for i, h in enumerate((0.235, 0.375, 0.515)):
        x = left + i * (bw + gap)
        d.rounded_rectangle([x, base - size * h, x + bw, base], radius=bw / 2,
                            fill=(255, 255, 255, 255))
    tile.alpha_composite(bars)

    img.alpha_composite(tile)
    return finish(img)


def variant_tile_glass():
    """深色玻璃瓷片 + 信号柱：和 App 内的 Liquid Glass 卡片同一套语言。"""
    img = base_canvas()
    size = W * 0.63
    box = [W / 2 - size / 2, W / 2 - size / 2, W / 2 + size / 2, W / 2 + size / 2]
    radius = size * 0.265
    mask = rounded_mask((W, W), box, radius)

    tile = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    tile.paste(Image.new("RGBA", (W, W), (255, 255, 255, 20)), (0, 0), mask)
    d = ImageDraw.Draw(tile)
    # 上沿高光 + 边缘描边
    hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(
        [box[0] + W * 0.016, box[1] + W * 0.012, box[2] - W * 0.016, box[1] + size * 0.34],
        radius=radius * 0.92, fill=(255, 255, 255, 34))
    hl.putalpha(Image.composite(hl.getchannel("A"), Image.new("L", (W, W), 0), mask))
    tile.alpha_composite(hl)
    d.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 62), width=round(W * 0.006))

    bw = size * 0.16
    gap = size * 0.085
    left = W / 2 - (bw * 3 + gap * 2) / 2
    base = W / 2 + size * 0.255
    for i, h in enumerate((0.24, 0.38, 0.52)):
        x = left + i * (bw + gap)
        col = ACCENT_LIGHT if i == 2 else (255, 255, 255, 240)
        d.rounded_rectangle([x, base - size * h, x + bw, base], radius=bw / 2, fill=col)
    img.alpha_composite(tile)
    return finish(img)


def variant_bleed_bars():
    """满幅蓝底 + 白柱：交给系统圆角遮罩，最接近原生 iOS 图标。

    自带圆角的瓷片放在深色底上，会被系统再套一层圆角，
    桌面上看起来像「方框里还有一块方框」，所以另出一版满幅的。
    """
    img = vertical_gradient(
        (W, W),
        [(0.0, (104, 190, 255)), (0.42, (16, 138, 255)), (1.0, (0, 74, 196))],
    ).convert("RGBA")
    img.alpha_composite(radial_glow((W, W), (255, 255, 255), (0.5, 0.02), 0.85, 0.22))

    bars = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(bars)
    bw = W * 0.108
    gap = W * 0.058
    left = W / 2 - (bw * 3 + gap * 2) / 2
    base = W / 2 + W * 0.185
    for i, h in enumerate((0.175, 0.275, 0.375)):
        x = left + i * (bw + gap)
        d.rounded_rectangle([x, base - W * h, x + bw, base], radius=bw / 2,
                            fill=(255, 255, 255, 255))
    img.alpha_composite(bars)
    return finish(img)


VARIANTS = {
    "A-ring": variant_ring,
    "K-bleed": variant_bleed_bars,
    "H-tile-glass": variant_tile_glass,
    "G-tile-bars": variant_tile_bars,
    "F-bars": variant_bars,
    "E-tile-blue": variant_tile_blue,
    "B-broadcast": variant_broadcast,
    "C-panel": variant_panel,
    "D-tile": variant_tile,
}


def contact_sheet(paths, out):
    """一张对比图：大图 + 60/40/29 三个真实尺寸。"""
    pad = 40
    big = 420
    small_sizes = (180, 120, 87)
    cols = len(paths)
    width = pad + cols * (big + pad)
    height = pad * 2 + big + 60 + max(small_sizes) + 24

    sheet = Image.new("RGBA", (width, height), (245, 245, 247, 255))
    dark = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dark.paste(Image.new("RGBA", (width, height // 2), (12, 12, 14, 255)), (0, 0))

    for i, p in enumerate(paths):
        icon = Image.open(p).convert("RGBA")
        x = pad + i * (big + pad)
        sheet.alpha_composite(icon.resize((big, big), Image.LANCZOS), (x, pad))
        sx = x
        for s in small_sizes:
            sheet.alpha_composite(icon.resize((s, s), Image.LANCZOS), (sx, pad + big + 60))
            sx += s + 24

    sheet.convert("RGB").save(out, quality=92)


def write_appicon(out_png):
    """生成 App Store 要求的 1024×1024、无 alpha 的 PNG。"""
    icon = variant_tile_bars().convert("RGB")
    os.makedirs(os.path.dirname(out_png), exist_ok=True)
    icon.save(out_png, optimize=True)
    print("wrote", out_png)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    if "--final" in sys.argv:
        write_appicon(os.path.join(
            root, "AirPanelV2", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"))
        return

    if "--bleed" in sys.argv:
        icon = variant_bleed_bars().convert("RGB")
        icon.save(os.path.join(root, "tools", "icon-variants", "K-bleed-final.png"))
        print("wrote K-bleed-final.png")
        return

    out_dir = os.path.join(root, "tools", "icon-variants")
    os.makedirs(out_dir, exist_ok=True)

    paths = []
    for name, fn in VARIANTS.items():
        p = os.path.join(out_dir, f"{name}.png")
        fn().save(p)
        paths.append(p)
        print("wrote", p)

    contact_sheet(paths, os.path.join(out_dir, "compare.png"))
    print("wrote", os.path.join(out_dir, "compare.png"))


if __name__ == "__main__":
    main()
