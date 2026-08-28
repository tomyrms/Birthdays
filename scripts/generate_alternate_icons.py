#!/usr/bin/env python3
"""Décline l’icône source avec les couleurs de marque codées dans l’app."""

from pathlib import Path
import colorsys

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ios/Birthdays/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
DESTINATIONS = {
    "AppIconBlue": "1677D2",
    "AppIconMint": "168276",
    "AppIconRose": "C84778",
    "AppIconAmber": "C66A28",
    "AppIconGraphite": "586273",
}
SOURCE_HUE = 0.718


def rgb(hex_value: str) -> tuple[float, float, float]:
    return tuple(int(hex_value[index:index + 2], 16) / 255 for index in (0, 2, 4))


def recolor(source: Image.Image, hex_value: str) -> Image.Image:
    target_hue, target_saturation, _ = colorsys.rgb_to_hsv(*rgb(hex_value))
    pixels = []
    for red, green, blue in source.convert("RGB").getdata():
        hue, saturation, value = colorsys.rgb_to_hsv(red / 255, green / 255, blue / 255)
        is_brand_pixel = 0.60 <= hue <= 0.86 and saturation >= 0.075 and value >= 0.055
        if is_brand_pixel:
            hue_delta = (hue - SOURCE_HUE) * 0.10
            hue = (target_hue + hue_delta) % 1
            if target_saturation < 0.25:
                saturation = min(0.22, saturation * 0.28)
            else:
                saturation = min(1, saturation * (0.62 + target_saturation * 0.58))
            red_value, green_value, blue_value = colorsys.hsv_to_rgb(hue, saturation, value)
            pixels.append((round(red_value * 255), round(green_value * 255), round(blue_value * 255)))
        else:
            pixels.append((red, green, blue))
    result = Image.new("RGB", source.size)
    result.putdata(pixels)
    return result


def main() -> None:
    source = Image.open(SOURCE)
    for asset_name, hex_value in DESTINATIONS.items():
        destination = SOURCE.parent.parent / f"{asset_name}.appiconset" / f"{asset_name}-1024.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        recolor(source, hex_value).save(destination, compress_level=6)
        print(destination)


if __name__ == "__main__":
    main()
