#!/usr/bin/env python3
"""Generate HomeWallet raster and native icon assets from the brand mark.

Dependencies: Python 3.10+, PyMuPDF, Pillow.
Install with: python -m pip install pymupdf pillow
"""

from __future__ import annotations

from collections import deque
from pathlib import Path

try:
    import fitz
    from PIL import Image, ImageDraw, ImageFont, ImageOps
except ImportError as exc:
    raise SystemExit(
        "Missing generator dependency. Run: python -m pip install pymupdf pillow"
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "branding"
GENERATED = BRAND / "generated"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_APPICON = (
    ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
)
WEB_ICONS = ROOT / "web" / "icons"
MARK = BRAND / "homewallet_mark.png"
SUPPLIED_LOGO = BRAND / "homewallet_logo_supplied.png"
REGULAR_FONT = ROOT / "assets" / "fonts" / "Roboto-Regular.ttf"
BOLD_FONT = ROOT / "assets" / "fonts" / "Roboto-Bold.ttf"

OFF_WHITE = "#FAFAF8"
INK = "#292B2E"
PALE_MINT = "#DDEFEA"
MINT = "#8FC9C2"


def _serif_font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/georgia.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"),
        Path("/System/Library/Fonts/NewYork.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.truetype(str(REGULAR_FONT), size)


def render(svg_name: str, destination: Path, width: int, height: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    source = BRAND / svg_name
    document = fitz.open(stream=source.read_bytes(), filetype="svg")
    try:
        page = document[0]
        matrix = fitz.Matrix(width / page.rect.width, height / page.rect.height)
        pixmap = page.get_pixmap(matrix=matrix, alpha=True)
        pixmap.save(destination)
    finally:
        document.close()


def resize(source: Path, destination: Path, size: int, *, opaque: bool = False) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        if opaque:
            background = Image.new("RGBA", image.size, OFF_WHITE)
            background.alpha_composite(image)
            image = background.convert("RGB")
        image.save(destination, optimize=True)


def resize_round(source: Path, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        image.putalpha(mask)
        image.save(destination, optimize=True)


def _trim_transparency(source: Image.Image) -> Image.Image:
    """Normalize transparency without changing the supplied artwork."""
    converted = source.convert("RGBA")
    pixels = converted.load()
    width, height = converted.size
    neutral = bytearray(width * height)
    for y in range(height):
        row = y * width
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and min(red, green, blue) >= 235 and (
                max(red, green, blue) - min(red, green, blue) <= 7
            ):
                neutral[row + x] = 1

    # PhotoRoom-style exports can contain a baked neutral grid. Removing all
    # neutral pixels also damages the wallet snap and pale leaf highlights, so
    # remove only connected canvas regions. Tiny isolated highlights stay.
    visited = bytearray(width * height)
    snap_x, snap_y = int(width * 0.543), int(height * 0.527)
    snap_index = snap_y * width + snap_x
    for start in range(width * height):
        if not neutral[start] or visited[start]:
            continue
        queue: deque[int] = deque([start])
        visited[start] = 1
        component: list[int] = []
        touches_edge = False
        contains_snap = False
        while queue:
            index = queue.popleft()
            component.append(index)
            contains_snap = contains_snap or index == snap_index
            x = index % width
            y = index // width
            touches_edge = touches_edge or x == 0 or y == 0 or x == width - 1 or y == height - 1
            if x > 0:
                neighbor = index - 1
                if neutral[neighbor] and not visited[neighbor]:
                    visited[neighbor] = 1
                    queue.append(neighbor)
            if x + 1 < width:
                neighbor = index + 1
                if neutral[neighbor] and not visited[neighbor]:
                    visited[neighbor] = 1
                    queue.append(neighbor)
            if y > 0:
                neighbor = index - width
                if neutral[neighbor] and not visited[neighbor]:
                    visited[neighbor] = 1
                    queue.append(neighbor)
            if y + 1 < height:
                neighbor = index + width
                if neutral[neighbor] and not visited[neighbor]:
                    visited[neighbor] = 1
                    queue.append(neighbor)
        if not contains_snap and (touches_edge or len(component) >= 150):
            for index in component:
                pixels[index % width, index // width] = (0, 0, 0, 0)
    alpha = converted.getchannel("A").point(lambda value: 0 if value <= 8 else value)
    converted.putalpha(alpha)
    bounds = alpha.getbbox()
    if bounds is None:
        raise SystemExit("The supplied logo does not contain visible artwork")
    return converted.crop(bounds)


def _supplied_logo(*, dark: bool = False) -> Image.Image:
    with Image.open(SUPPLIED_LOGO) as source:
        converted = _trim_transparency(source)
    if not dark:
        return converted

    # Keep the supplied symbol pixel-for-pixel. Only make its charcoal wordmark
    # readable against the app's dark background.
    pixels = converted.load()
    wordmark_top = int(converted.height * 0.72)
    for y in range(wordmark_top, converted.height):
        for x in range(converted.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and max(red, green, blue) < 170:
                luminance = (red * 299 + green * 587 + blue * 114) // 1000
                light = min(250, 224 + luminance // 6)
                pixels[x, y] = (light, min(250, light + 1), light - 4, alpha)
    return converted


def _supplied_mark() -> Image.Image:
    logo = _supplied_logo()
    mark_region = logo.crop((0, 0, logo.width, int(logo.height * 0.73)))
    alpha_bounds = mark_region.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise SystemExit("The supplied logo mark is empty")
    return mark_region.crop(alpha_bounds)


def _contain_mark(
    size: tuple[int, int], inset: int = 0, *, dark: bool = False
) -> Image.Image:
    with Image.open(MARK) as source:
        source = source.convert("RGBA")
        available = (size[0] - inset * 2, size[1] - inset * 2)
        fitted = ImageOps.contain(source, available, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    position = ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2)
    canvas.alpha_composite(fitted, position)
    return canvas


def _save_horizontal_logo(destination: Path, *, dark: bool) -> None:
    canvas = Image.new("RGBA", (1600, 900), (0, 0, 0, 0))
    logo = ImageOps.contain(
        _supplied_logo(dark=dark), (1450, 820), Image.Resampling.LANCZOS
    )
    canvas.alpha_composite(
        logo, ((canvas.width - logo.width) // 2, (canvas.height - logo.height) // 2)
    )
    canvas.save(destination, optimize=True)


def _centered_text(
    draw: ImageDraw.ImageDraw,
    canvas_width: int,
    y: int,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: str,
) -> None:
    bounds = draw.textbbox((0, 0), text, font=font)
    width = bounds[2] - bounds[0]
    draw.text(((canvas_width - width) // 2, y), text, font=font, fill=fill)


def _save_stacked_logo(destination: Path, *, dark: bool) -> None:
    _supplied_logo(dark=dark).save(destination, optimize=True)


def generate_brand_pngs() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
    _supplied_mark().save(MARK, optimize=True)
    foreground = _contain_mark((1024, 1024), inset=48)
    # Android 12 masks the native splash artwork. Keep the complete mark inside
    # its circular safe zone so the house, wallet, leaves and sparkles are never
    # cropped by different manufacturers' launch animations.
    splash_foreground = _contain_mark((1024, 1024), inset=196)
    foreground.save(GENERATED / "app_icon_foreground.png", optimize=True)
    splash_foreground.save(GENERATED / "splash_logo.png", optimize=True)
    splash_foreground.save(GENERATED / "splash_logo_dark.png", optimize=True)
    foreground.save(GENERATED / "homewallet_mark_dark.png", optimize=True)

    app_icon = Image.new("RGBA", (1024, 1024), OFF_WHITE)
    app_icon.alpha_composite(_contain_mark((1024, 1024), inset=52))
    app_icon.convert("RGB").save(GENERATED / "app_icon_1024.png", optimize=True)

    monochrome = Image.new("RGBA", foreground.size, INK)
    monochrome.putalpha(foreground.getchannel("A"))
    monochrome.save(GENERATED / "app_icon_monochrome.png", optimize=True)

    _save_horizontal_logo(GENERATED / "logo_horizontal.png", dark=False)
    _save_horizontal_logo(GENERATED / "logo_white.png", dark=True)
    _save_stacked_logo(GENERATED / "logo_stacked_light.png", dark=False)
    _save_stacked_logo(GENERATED / "logo_stacked_dark.png", dark=True)


def generate_android_legacy_icons() -> None:
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    source = GENERATED / "app_icon_1024.png"
    for density, size in sizes.items():
        folder = ANDROID_RES / f"mipmap-{density}"
        resize(source, folder / "ic_launcher.png", size, opaque=True)
        resize_round(source, folder / "ic_launcher_round.png", size)

    adaptive = ANDROID_RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / "ic_launcher_round.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground>
    <inset android:drawable="@drawable/ic_launcher_foreground" android:inset="18%" />
  </foreground>
</adaptive-icon>
""",
        encoding="utf-8",
    )


def generate_ios_icons() -> None:
    entries = [
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    ]
    source = GENERATED / "app_icon_1024.png"
    for filename, size in entries:
        resize(source, IOS_APPICON / filename, size, opaque=True)


def generate_web_icons() -> None:
    source = GENERATED / "app_icon_1024.png"
    for filename, size in [
        ("Icon-192.png", 192),
        ("Icon-512.png", 512),
        ("Icon-maskable-192.png", 192),
        ("Icon-maskable-512.png", 512),
    ]:
        resize(source, WEB_ICONS / filename, size, opaque=True)
    resize(source, ROOT / "web" / "favicon.png", 48, opaque=True)


def verify_outputs() -> None:
    expected = [
        GENERATED / "app_icon_1024.png",
        MARK,
        GENERATED / "app_icon_foreground.png",
        GENERATED / "app_icon_monochrome.png",
        GENERATED / "logo_horizontal.png",
        GENERATED / "logo_white.png",
        GENERATED / "logo_stacked_light.png",
        GENERATED / "logo_stacked_dark.png",
        GENERATED / "splash_logo_dark.png",
        GENERATED / "splash_logo.png",
        IOS_APPICON / "Icon-App-1024x1024@1x.png",
        ANDROID_RES / "mipmap-xxxhdpi" / "ic_launcher.png",
        ANDROID_RES / "mipmap-anydpi-v26" / "ic_launcher_round.xml",
    ]
    missing = [str(path.relative_to(ROOT)) for path in expected if not path.exists()]
    if missing:
        raise SystemExit("Missing generated assets: " + ", ".join(missing))
    with Image.open(GENERATED / "app_icon_1024.png") as image:
        if image.size != (1024, 1024):
            raise SystemExit("Master PNG must be exactly 1024 x 1024")
    for transparent_asset in [
        MARK,
        GENERATED / "logo_stacked_light.png",
        GENERATED / "logo_stacked_dark.png",
        GENERATED / "splash_logo.png",
        GENERATED / "splash_logo_dark.png",
    ]:
        with Image.open(transparent_asset) as image:
            if image.convert("RGBA").getpixel((0, 0))[3] != 0:
                raise SystemExit(
                    f"{transparent_asset.name} must preserve transparent corners"
                )


def main() -> None:
    generate_brand_pngs()
    generate_android_legacy_icons()
    generate_ios_icons()
    generate_web_icons()
    verify_outputs()
    print("HomeWallet assets generated from the official brand mark.")


if __name__ == "__main__":
    main()
