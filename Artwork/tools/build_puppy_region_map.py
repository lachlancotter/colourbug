"""Build an editable colour-region map from the puppy god ink illustration.

Run from the repository root with Pillow, NumPy, and OpenCV installed:
    python Artwork/tools/build_puppy_region_map.py
The component choices and palette below are authored; contour extraction is mechanical.
"""
from __future__ import annotations

import json
import hashlib
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ARTWORK = Path("Artwork")
SOURCE = ARTWORK / "puppy-god-linework.png"
MAP = ARTWORK / "puppy-god-regions.json"
SVG = ARTWORK / "puppy-god-region-map.svg"
PREVIEW = ARTWORK / "puppy-god-region-preview.png"
INK = ARTWORK / "puppy-god-ink.png"
OWNERS = ARTWORK / "puppy-god-owners.bin"
SOURCE_SHA256 = "c841181912cf03b130704b7e1ac7d3b00b4283db7cbf6372ccee19081e067493"

PALETTE = {
    "sky_blue": "#DDEBF3",
    "sky_lilac": "#EDE7F5",
    "sky_peach": "#F8E9DC",
    "halo_gold": "#EAC56C",
    "halo_glow": "#FBF0CB",
    "star_gold": "#F2CD70",
    "cloud": "#F7F4ED",
    "cloud_shadow": "#DFE9ED",
    "fur": "#D9B487",
    "fur_light": "#F1D9B7",
    "fur_shadow": "#B98F6F",
    "tongue": "#EA999C",
    "collar": "#83A7B4",
    "collar_dark": "#628697",
    "medallion": "#F0C65F",
    "flower_coral": "#E7A2A7",
    "flower_peach": "#F3C2A8",
    "flower_rose": "#CF829D",
    "flower_gold": "#E9C66E",
    "leaf": "#9BBD91",
    "leaf_dark": "#6F9C79",
    "ground": "#B9CCA3",
}

# Source components were inspected against the ink image at its native resolution.
# Open fine ink details deliberately remain unpainted.
GROUPS = [
    ("halo-rim", "halo_gold", [2]),
    ("halo-inner-glow", "halo_glow", [3]),
    ("halo-star", "star_gold", [4]),
    ("star", "star_gold", [5, 7, 12]),
    ("cloud-left-upper", "cloud", [11]),
    ("cloud-left-middle", "cloud_shadow", [21]),
    ("cloud-right-upper", "cloud", [13]),
    ("cloud-right-middle", "cloud_shadow", [29]),
    ("garden-left", "leaf", [27]),
    ("garden-right", "leaf", [50]),
    ("garden-right-inner", "leaf_dark", [64, 114, 118]),
    ("puppy-body", "fur", [38]),
    ("puppy-left-haunch", "fur_light", [104]),
    ("puppy-right-haunch", "fur_light", [93]),
    ("puppy-left-tail", "fur_light", [147]),
    ("puppy-right-tail", "fur_light", [148]),
    ("puppy-under-chin", "fur_light", [31, 32]),
    ("puppy-tongue", "tongue", [25]),
    ("collar-band", "collar_dark", [33, 34]),
    ("collar-stud", "medallion", [43, 44]),
    ("sun-medallion-ring", "medallion", [65]),
    ("sun-medallion-centre", "halo_glow", [66]),
    ("left-flower-bud", "flower_peach", [40, 88]),
    ("right-flower-bud", "flower_peach", [71]),
    ("left-flower-coral-petal", "flower_coral", [96, 127, 134, 157]),
    ("left-flower-peach-petal", "flower_peach", [86, 116, 154, 151]),
    ("left-flower-lower-leaves", "leaf", [199, 200]),
    ("right-flower-coral-petal", "flower_coral", [149, 137, 180]),
    ("right-flower-rose-petal", "flower_rose", [170]),
    ("right-flower-lower-leaves", "leaf", [202, 212]),
    ("left-foliage", "leaf", [54, 55, 57, 61, 76, 100, 110, 111, 113, 173, 174, 179, 182, 185, 192, 195, 218]),
    ("left-foliage-dark", "leaf_dark", [163, 167, 186, 193, 194, 203, 206, 209]),
    ("right-foliage", "leaf", [79, 82, 98, 99, 101, 105, 108, 124, 125, 140, 172, 183, 197, 214]),
    ("right-foliage-dark", "leaf_dark", [145, 175, 181, 196, 207, 222]),
    ("ground-clouds", "ground", [191]),
]

def rgb(hex_colour: str) -> np.ndarray:
    return np.array([int(hex_colour[i:i+2], 16) for i in (1, 3, 5)], dtype=np.uint8)

def contour_path(mask: np.ndarray) -> str:
    contours, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    pieces = []
    for contour in contours:
        if cv2.contourArea(contour) < 8:
            continue
        simplified = cv2.approxPolyDP(contour, 1.5, True).reshape(-1, 2)
        if len(simplified) < 3:
            continue
        points = " L ".join(f"{x} {y}" for x, y in simplified)
        pieces.append(f"M {points} Z")
    return " ".join(pieces)

def polygon_mask(shape: tuple[int, int], points: list[tuple[int, int]]) -> np.ndarray:
    mask = np.zeros(shape, dtype=np.uint8)
    cv2.fillPoly(mask, [np.array(points, dtype=np.int32)], 1)
    return mask.astype(bool)

def main() -> None:
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == SOURCE_SHA256, \
        "The source image changed; inspect components before rebuilding the map."
    source = np.array(Image.open(SOURCE).convert("RGB"))
    height, width = source.shape[:2]
    grey = cv2.cvtColor(source, cv2.COLOR_RGB2GRAY)
    ink = (grey < 160).astype(np.uint8)
    ink = cv2.morphologyEx(
        ink, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    )
    _, labels, stats, _ = cv2.connectedComponentsWithStats(1 - ink, 8)
    preview = np.full_like(source, 255)
    owners = np.zeros((height, width), dtype=np.uint8)
    regions = []
    claimed = set()

    def add(region_id: str, label: str, colour: str, mask: np.ndarray,
            boundary: str = "ink", feather: int = 0, component: int | None = None,
            soft_inside: np.ndarray | None = None) -> None:
        path = contour_path(mask)
        if not path:
            return
        regions.append({
            "id": region_id,
            "label": label,
            "colourID": colour,
            "boundary": boundary,
            "compositing": "soft-overlay" if boundary == "soft" else
                           "blend-zone" if boundary == "hidden" else "normal",
            "featherPixels": feather,
            "order": len(regions),
            "paintGroup": "sky" if region_id.startswith("sky-") else
                          "puppy-coat" if colour in ("fur", "fur_light", "fur_shadow") else
                          region_id,
            "sourceComponent": component,
            "areaPixels": int(mask.sum()),
            "path": path,
        })
        owners[mask] = len(regions)
        if feather and soft_inside is not None:
            blend = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), feather / 2)
            blend *= soft_inside
            active = blend > 0.01
            strength = blend[active, None]
            preview[active] = np.round(
                preview[active] * (1 - strength) + rgb(PALETTE[colour]) * strength
            ).astype(np.uint8)
        else:
            preview[mask] = rgb(PALETTE[colour])

    # Three broad, unlined sky zones intentionally overlap. A painter can blend
    # them; a renderer should feather each zone instead of drawing a seam.
    sky = labels == 1
    ys = np.arange(height)[:, None]
    for name, colour, low, high in [
        ("sky-upper", "sky_blue", 0, 280),
        ("sky-middle", "sky_lilac", 220, 500),
        ("sky-lower", "sky_peach", 440, 665),
    ]:
        add(name, name.replace("-", " ").title(), colour,
            sky & (ys >= low) & (ys < high), "hidden", 80)
    stops = [(0, rgb(PALETTE["sky_blue"])),
             (320, rgb(PALETTE["sky_lilac"])),
             (660, rgb(PALETTE["sky_peach"]))]
    for y in range(min(height, 665)):
        first, second = (stops[0], stops[1]) if y <= 320 else (stops[1], stops[2])
        t = max(0, min(1, (y - first[0]) / (second[0] - first[0])))
        preview[y, sky[y]] = np.round(first[1] * (1 - t) + second[1] * t).astype(np.uint8)

    # The face/ears/muzzle are one connected white component. Split them into
    # broad art-directed shapes while keeping each mask inside the drawn head.
    head = labels == 9
    left_ear = head & polygon_mask((height, width), [
        (474, 345), (506, 277), (562, 222), (618, 220), (635, 294),
        (623, 384), (602, 480), (535, 489), (470, 417)
    ])
    right_ear = head & polygon_mask((height, width), [
        (812, 221), (861, 182), (927, 226), (968, 292),
        (970, 391), (924, 467), (850, 444), (821, 349)
    ])
    muzzle = head & polygon_mask((height, width), [
        (624, 320), (679, 298), (759, 298), (817, 330),
        (851, 388), (812, 430), (733, 449), (658, 428), (618, 378)
    ])
    raised_paw = (labels == 38) & polygon_mask((height, width), [
        (510, 480), (595, 470), (635, 516), (644, 599),
        (626, 700), (575, 729), (508, 688), (493, 571)
    ])
    # Keep the base coat beneath soft overlays so a renderer can feather their
    # edges without exposing unpainted paper.
    face_base = head
    body_base = labels == 38

    # A soft preview needs the underlying coat colour beneath feathered edges.
    preview[head | (labels == 38)] = rgb(PALETTE["fur"])
    add("puppy-face", "Puppy face and crown", "fur", face_base)
    add("puppy-left-ear", "Left ear", "fur_shadow", left_ear, "soft", 12, soft_inside=head)
    add("puppy-right-ear", "Right ear", "fur_shadow", right_ear, "soft", 12, soft_inside=head)
    add("puppy-muzzle", "Muzzle", "fur_light", muzzle, "soft", 14, soft_inside=head)
    add("puppy-body", "Puppy body", "fur", body_base)
    add("puppy-raised-paw", "Raised paw", "fur_light", raised_paw, "soft", 8,
        soft_inside=labels == 38)
    claimed.update((9, 38))

    for group_name, colour, component_ids in GROUPS:
        for number, component_id in enumerate(component_ids, start=1):
            if component_id in claimed:
                continue
            if component_id >= len(stats) or stats[component_id, cv2.CC_STAT_AREA] < 65:
                continue
            claimed.add(component_id)
            region_id = group_name if len(component_ids) == 1 else f"{group_name}-{number:02d}"
            add(region_id, group_name.replace("-", " ").title(), colour,
                labels == component_id, component=component_id)

    # Put the original anti-aliased ink over the colour preview.
    alpha = np.clip((255 - grey).astype(np.float32) / 220, 0, 1)[:, :, None]
    preview = np.round(preview.astype(np.float32) * (1 - alpha)).astype(np.uint8)
    Image.fromarray(preview).save(PREVIEW)
    ink_alpha = np.maximum(0, 255 - grey)
    ink_alpha[ink_alpha < 8] = 0
    ink_rgba = np.zeros((height, width, 4), dtype=np.uint8)
    ink_rgba[:, :, 3] = ink_alpha
    Image.fromarray(ink_rgba, "RGBA").save(INK)
    OWNERS.write_bytes(owners.tobytes())

    result = {
        "version": 1,
        "sourceImage": SOURCE.name,
        "sourceSHA256": SOURCE_SHA256,
        "size": {"width": width, "height": height},
        "coordinateSpace": "source image pixels, origin top-left",
        "pathFormat": "SVG path data; fill-rule evenodd",
        "palette": PALETTE,
        "paletteOrder": list(PALETTE),
        "regions": regions,
    }
    MAP.write_text(json.dumps(result, indent=2) + "\n")
    svg_regions = "\n".join(
        f'<path id="{r["id"]}" d="{r["path"]}" '
        f'fill="{"url(#sky-gradient)" if r["id"].startswith("sky-") else PALETTE[r["colourID"]]}" '
        f'fill-rule="evenodd"/>'
        for r in regions
    )
    SVG.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">\n'
        f'<defs><linearGradient id="sky-gradient" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0%" stop-color="{PALETTE["sky_blue"]}"/>'
        f'<stop offset="48%" stop-color="{PALETTE["sky_lilac"]}"/>'
        f'<stop offset="100%" stop-color="{PALETTE["sky_peach"]}"/>'
        f'</linearGradient></defs>\n'
        f'{svg_regions}\n</svg>\n'
    )
    print(f"{len(regions)} regions; {len(claimed)} source components mapped")
    print(MAP, SVG, PREVIEW, INK, OWNERS)

if __name__ == "__main__":
    main()
