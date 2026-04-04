#!/usr/bin/env python3

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PACKAGING_DIR = PROJECT_ROOT / "Packaging"
MASTER_PATH = PACKAGING_DIR / "AppIcon-master.png"
ICONSET_DIR = PACKAGING_DIR / "AppIcon.iconset"
ICNS_PATH = PACKAGING_DIR / "AppIcon.icns"

CANVAS = 1024
CORNER_RADIUS = 232


def main() -> None:
    PACKAGING_DIR.mkdir(parents=True, exist_ok=True)
    image = build_icon(CANVAS)
    image.save(MASTER_PATH)
    export_iconset(image)

    if ICNS_PATH.exists():
        ICNS_PATH.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)],
        check=True,
    )
    print(ICNS_PATH)


def build_icon(size: int) -> Image.Image:
    scale = 4
    render_size = size * scale
    base = make_background(render_size)
    draw_ambient_light(base)
    draw_card(base, scale=scale)
    mask = rounded_mask(render_size, CORNER_RADIUS * scale)
    base.putalpha(mask)
    return base.resize((size, size), Image.Resampling.LANCZOS)


def make_background(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pixels = image.load()

    # Deeper, richer dark background: near-black with teal hint bottom-right
    tl = (10, 14, 20)
    tr = (12, 20, 26)
    bl = (16, 22, 32)
    br = (18, 52, 56)

    for y in range(size):
        ny = y / (size - 1)
        for x in range(size):
            nx = x / (size - 1)
            upper = lerp_color(tl, tr, nx)
            lower = lerp_color(bl, br, nx)
            pixels[x, y] = (*lerp_color(upper, lower, ny), 255)

    # Subtle vignette
    vig = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(vig).ellipse((-80, -60, size + 120, size + 180), fill=(0, 0, 0, 100))
    vig = vig.filter(ImageFilter.GaussianBlur(100))
    image.alpha_composite(vig)
    return image


def draw_ambient_light(image: Image.Image) -> None:
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)

    # Top-left cool blue-white glow
    draw.ellipse((-60, -80, 480, 460), fill=(140, 200, 255, 28))
    # Bottom-right teal glow
    draw.ellipse((580, 560, 1100, 1100), fill=(40, 200, 160, 36))
    # Center subtle warm highlight
    draw.ellipse((300, 200, 780, 680), fill=(255, 255, 255, 10))

    glow = glow.filter(ImageFilter.GaussianBlur(90))
    image.alpha_composite(glow)


def draw_card(image: Image.Image, scale: int = 1) -> None:
    size = image.size[0]
    s = scale

    # Card bounds — centered, slightly lower for visual balance
    cx, cy = size // 2, size // 2 + 30 * s
    half_w, half_h = 268 * s, 268 * s
    card_rect = (cx - half_w, cy - half_h, cx + half_w, cy + half_h)
    radius = 96 * s

    # Drop shadow
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (card_rect[0] + 12*s, card_rect[1] + 18*s, card_rect[2] + 12*s, card_rect[3] + 18*s),
        radius=radius, fill=(0, 0, 0, 160)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(40 * s))
    image.alpha_composite(shadow)

    card = Image.new("RGBA", image.size, (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card)
    card_draw.rounded_rectangle(card_rect, radius=radius, fill=(235, 245, 248, 245))
    sheen = make_card_sheen(card_rect, image.size, radius)
    card.alpha_composite(sheen)
    card_draw.rounded_rectangle(card_rect, radius=radius, outline=(255, 255, 255, 140), width=3*s)
    image.alpha_composite(card)

    draw_capture_marks(image, card_rect, s)
    draw_pin(image, card_rect, s)


def make_card_sheen(rect, canvas_size, radius) -> Image.Image:
    layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0

    grad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = grad.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        # Top: bright white sheen, fades to very light teal-white
        alpha = int(lerp(100, 0, t))
        color = lerp_color((255, 255, 255), (220, 238, 240), t)
        for x in range(w):
            px[x, y] = (*color, alpha)

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), radius=radius, fill=255)
    grad.putalpha(mask)
    layer.alpha_composite(grad, dest=(x0, y0))
    return layer


def draw_capture_marks(image: Image.Image, card_rect, s: int = 1) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    x0, y0, x1, y1 = card_rect
    inset = 88 * s
    arm = 80 * s
    stroke = 28 * s
    color = (22, 196, 148, 255)

    left = x0 + inset
    top = y0 + inset
    right = x1 - inset
    bottom = y1 - inset

    corners = [
        ((left, top + arm), (left, top), (left + arm, top)),
        ((right - arm, top), (right, top), (right, top + arm)),
        ((left, bottom - arm), (left, bottom), (left + arm, bottom)),
        ((right - arm, bottom), (right, bottom), (right, bottom - arm)),
    ]

    for start, pivot, end in corners:
        draw.line([start, pivot, end], fill=color, width=stroke, joint="curve")

    layer = layer.filter(ImageFilter.GaussianBlur(0.8))
    image.alpha_composite(layer)


def draw_pin(image: Image.Image, card_rect, s: int = 1) -> None:
    import math
    x0, y0, x1, y1 = card_rect

    head_r = 56 * s
    bronze = (218, 162, 96, 255)
    bronze_rim = (248, 210, 160, 180)
    shaft_color = (28, 34, 44, 255)

    cx = x1 + 10 * s
    cy = y0 - 10 * s
    entry_x = x1 - 30 * s
    entry_y = y0 + 30 * s

    # Direction unit vector
    dx = entry_x - cx
    dy = entry_y - cy
    dist = math.hypot(dx, dy)
    nx, ny = dx / dist, dy / dist

    # Shaft start: just outside head
    sx = int(cx + nx * (head_r - 8 * s))
    sy = int(cy + ny * (head_r - 8 * s))

    ex = int(entry_x + nx * 50 * s)
    ey = int(entry_y + ny * 50 * s)

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        (cx - head_r + 8*s, cy - head_r + 10*s, cx + head_r + 8*s, cy + head_r + 10*s),
        fill=(0, 0, 0, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(16 * s))
    image.alpha_composite(shadow)

    shaft_layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shaft_draw = ImageDraw.Draw(shaft_layer)
    shaft_draw.line([(sx, sy), (ex, ey)], fill=shaft_color, width=18 * s)
    shaft_draw.ellipse((ex - 6*s, ey - 6*s, ex + 6*s, ey + 6*s), fill=shaft_color)
    shaft_layer = shaft_layer.filter(ImageFilter.GaussianBlur(1.5 * s))
    image.alpha_composite(shaft_layer)

    head_layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    head_draw = ImageDraw.Draw(head_layer)
    head_draw.ellipse((cx - head_r, cy - head_r, cx + head_r, cy + head_r),
                      fill=bronze, outline=bronze_rim, width=5 * s)
    image.alpha_composite(head_layer)


def export_iconset(master: Image.Image) -> None:
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, target_size in sizes.items():
        resized = master.resize((target_size, target_size), Image.Resampling.LANCZOS)
        resized.save(ICONSET_DIR / filename)


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def lerp(a: float, b: float, t: float) -> float:
    return a * (1 - t) + b * t


def lerp_color(a, b, t: float):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


if __name__ == "__main__":
    main()
