#!/usr/bin/env python3
"""Recadre les icônes de l'app et régénère leurs aperçus SwiftUI.

Les icônes générées sont posées sur un canevas blanc avec une marge uniforme.
Le script mesure cette marge, la retire, puis rééchantillonne l'illustration à
1024x1024 pour qu'elle remplisse à nouveau la vignette iOS.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image, PngImagePlugin


SOURCE_SIZE = 1024
PREVIEW_SIZE = 256

# Une marge est du blanc bruité (compression) : on tolère un écart de 60 par
# canal avant de considérer un pixel comme faisant partie de l'illustration.
WHITE_TOLERANCE = 60
# Une ligne isolée de pixels sombres est du bruit ; l'illustration en couvre
# une part franche.
CONTENT_RATIO = 0.05
# Au-delà, la détection a mordu dans une illustration claire plutôt que sur la
# marge : mieux vaut ne rien toucher que de mutiler l'icône.
MAX_BORDER_RATIO = 0.18
PROCESSED_KEY = "birthdays.app-icon-border-crop"

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSET_CATALOG = PROJECT_ROOT / "Birthdays" / "Resources" / "Assets.xcassets"


def png_info(value: str) -> PngImagePlugin.PngInfo:
    info = PngImagePlugin.PngInfo()
    info.add_text(PROCESSED_KEY, value)
    return info


def write_png(image: Image.Image, destination: Path, marker: str) -> None:
    # Le nom du fichier temporaire porte le PID : deux exécutions simultanées
    # se disputaient sinon le même `.tmp`, et celle qui perdait la course
    # échouait au `replace` sur un fichier déjà consommé.
    temporary = destination.with_name(f".{destination.name}.{os.getpid()}.tmp")
    try:
        image.save(temporary, format="PNG", optimize=True, pnginfo=png_info(marker))
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def measure_border(image: Image.Image) -> int:
    """Épaisseur de la marge blanche, mesurée sur les quatre côtés."""
    width, height = image.size
    pixels = image.convert("RGB").load()

    def is_content(x: int, y: int) -> bool:
        return 255 - min(pixels[x, y]) > WHITE_TOLERANCE

    def scan(is_blank) -> int:
        inset = 0
        while inset < min(width, height) and is_blank(inset):
            inset += 1
        return inset

    row_limit = width * CONTENT_RATIO
    column_limit = height * CONTENT_RATIO

    top = scan(lambda i: sum(is_content(x, i) for x in range(width)) <= row_limit)
    bottom = scan(
        lambda i: sum(is_content(x, height - 1 - i) for x in range(width)) <= row_limit
    )
    left = scan(lambda i: sum(is_content(i, y) for y in range(height)) <= column_limit)
    right = scan(
        lambda i: sum(is_content(width - 1 - i, y) for y in range(height)) <= column_limit
    )

    # L'ombre portée déborde sous l'illustration et raccourcit la mesure du bas.
    # Le côté le plus généreux est donc le seul à voir la marge entière ; s'en
    # tenir au minimum laisserait un liseré blanc.
    return max(top, bottom, left, right)


def crop_icon(source: Path) -> tuple[Image.Image, str]:
    with Image.open(source) as opened_image:
        # App Store Connect refuse une icône porteuse d'un canal alpha ; ces
        # PNG sont entièrement opaques, l'aplatir ne perd donc rien.
        image = opened_image.convert("RGB")
        marker = opened_image.info.get(PROCESSED_KEY)
        needs_flattening = opened_image.mode != "RGB"

    if marker is not None:
        if needs_flattening:
            write_png(image, source, marker)
            return image, "déjà recadrée, canal alpha retiré"
        return image, "déjà recadrée"

    if image.size != (SOURCE_SIZE, SOURCE_SIZE):
        raise ValueError(
            f"{source} mesure {image.width}x{image.height}; "
            f"la taille attendue est {SOURCE_SIZE}x{SOURCE_SIZE}."
        )

    border = measure_border(image)
    if border == 0:
        return image, "aucune marge détectée"
    if border > SOURCE_SIZE * MAX_BORDER_RATIO:
        return image, f"marge suspecte de {border}px ignorée"

    cropped = image.crop(
        (border, border, SOURCE_SIZE - border, SOURCE_SIZE - border)
    ).resize((SOURCE_SIZE, SOURCE_SIZE), Image.Resampling.LANCZOS)
    write_png(cropped, source, f"{border}px-from-{SOURCE_SIZE}px")
    return cropped, f"recadrée de {border}px"


def write_swiftui_preview(icon_set: Path, icon: Image.Image) -> None:
    """Les catalogues `.appiconset` ne sont pas lisibles via `Image(_:)` :
    on en maintient une copie légère dans une `.imageset` jumelle."""
    preview_set = icon_set.with_name(f"{icon_set.stem}-Preview.imageset")
    preview_set.mkdir(exist_ok=True)

    preview_filename = "icon_preview.png"
    preview = icon.resize((PREVIEW_SIZE, PREVIEW_SIZE), Image.Resampling.LANCZOS)
    write_png(preview, preview_set / preview_filename, "preview")

    contents = {
        "images": [
            {
                "filename": preview_filename,
                "idiom": "universal",
                "scale": "1x",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (preview_set / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    icon_sources = sorted(ASSET_CATALOG.glob("AppIcon*.appiconset/icon_1024.png"))
    if not icon_sources:
        raise SystemExit(f"Aucune icône icon_1024.png trouvée dans {ASSET_CATALOG}")

    for source in icon_sources:
        icon, status = crop_icon(source)
        write_swiftui_preview(source.parent, icon)
        print(f"{source.parent.name}/icon_1024.png : {status}")

    print(f"Terminé : {len(icon_sources)} aperçu(s) SwiftUI synchronisé(s).")


if __name__ == "__main__":
    main()
