# -*- coding: utf-8 -*-
"""生成 AirPanel PWA 图标：蓝靛渐变圆角方块 + 白色信号塔图形"""
from PIL import Image, ImageDraw

def make_icon(size, path):
    S = size
    # 圆角半径（现代 app 图标风格，约 22%）
    radius = int(S * 0.22)
    # 对角渐变：蓝 #3B82F6 -> 靛 #4F46E5
    base = Image.new("RGB", (S, S), "#3B82F6")
    draw = ImageDraw.Draw(base)
    for y in range(S):
        t = y / (S - 1)
        r = int(59 + (79 - 59) * t)
        g = int(130 + (70 - 130) * t)
        b = int(246 + (229 - 246) * t)
        draw.line([(0, y), (S, y)], fill=(r, g, b))
    # 圆角遮罩
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)

    d = ImageDraw.Draw(icon)
    # 白色信号塔图形：竖杆 + 三条递增横线（象征设备信号/通信）
    white = (255, 255, 255, 255)
    cx = S * 0.5
    # 竖杆
    pole_w = max(2, int(S * 0.045))
    d.rounded_rectangle([cx - pole_w / 2, S * 0.30, cx + pole_w / 2, S * 0.72], radius=pole_w / 2, fill=white)
    # 三条横线（自下而上递增，圆头）
    bars = [(0.20, 0.62), (0.32, 0.48), (0.44, 0.34)]
    bar_h = max(2, int(S * 0.035))
    for wfrac, yfrac in bars:
        half = S * wfrac / 2
        y0 = S * yfrac
        d.rounded_rectangle([cx - half, y0, cx + half, y0 + bar_h], radius=bar_h / 2, fill=white)
    # 底部小圆点（锚点）
    dot_r = max(2, int(S * 0.05))
    d.ellipse([cx - dot_r, S * 0.76 - dot_r, cx + dot_r, S * 0.76 + dot_r], fill=white)

    icon.save(path, "PNG")
    print("saved", path, size)

import os
os.makedirs(os.path.join(os.path.dirname(__file__), "icons"), exist_ok=True)
base = os.path.join(os.path.dirname(__file__), "icons")
make_icon(192, os.path.join(base, "icon-192.png"))
make_icon(512, os.path.join(base, "icon-512.png"))
make_icon(180, os.path.join(base, "apple-touch-icon.png"))
make_icon(32, os.path.join(base, "favicon.png"))
print("done")
