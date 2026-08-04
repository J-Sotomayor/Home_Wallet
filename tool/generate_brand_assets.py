#!/usr/bin/env python3
"""Generate HomeWallet raster and native icon assets from editable SVG masters.

Dependencies: Python 3.10+, PyMuPDF, Pillow.
Install with: python -m pip install pymupdf pillow
"""

from __future__ import annotations

from pathlib import Path

try:
    import fitz
    from PIL import Image
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
            background = Image.new("RGBA", image.size, "#2563EB")
            background.alpha_composite(image)
            image = background.convert("RGB")
        image.save(destination, optimize=True)


def resize_round(source: Path, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        from PIL import ImageDraw

        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        image.putalpha(mask)
        image.save(destination, optimize=True)


def generate_brand_pngs() -> None:
    GENERATED.mkdir(parents=True, exist_ok=True)
    render("homewallet_app_icon.svg", GENERATED / "app_icon_1024.png", 1024, 1024)
    render(
        "homewallet_icon_foreground.svg",
        GENERATED / "app_icon_foreground.png",
        1024,
        1024,
    )
    render(
        "homewallet_logo_monochrome.svg",
        GENERATED / "app_icon_monochrome.png",
        1024,
        1024,
    )
    render("homewallet_logo_horizontal.svg", GENERATED / "logo_horizontal.png", 1600, 400)
    render("homewallet_logo_white.svg", GENERATED / "logo_white.png", 1600, 400)
    render("homewallet_icon_foreground.svg", GENERATED / "splash_logo.png", 1024, 1024)


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
    <inset android:drawable="@drawable/ic_launcher_foreground" android:inset="0%" />
  </foreground>
  <monochrome>
    <inset android:drawable="@drawable/ic_launcher_monochrome" android:inset="0%" />
  </monochrome>
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
        GENERATED / "app_icon_foreground.png",
        GENERATED / "app_icon_monochrome.png",
        GENERATED / "logo_horizontal.png",
        GENERATED / "logo_white.png",
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


def main() -> None:
    generate_brand_pngs()
    generate_android_legacy_icons()
    generate_ios_icons()
    generate_web_icons()
    verify_outputs()
    print("HomeWallet assets generated from SVG masters.")


if __name__ == "__main__":
    main()
