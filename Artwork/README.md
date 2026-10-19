# Puppy god colour map

`puppy-god-linework.png` is the original generated ink illustration. `puppy-god-regions.json` defines 102 named SVG paths in the source image's 1448 × 1086 pixel coordinate system. Each region has a suggested palette colour, source component where applicable, pixel area, and a boundary type:

- `ink`: the boundary follows a visible contour in the drawing.
- `soft`: a hand-defined division within a subject, such as fur or muzzle, to be blended across `featherPixels`.
- `hidden`: an unlined sky zone, also blended across `featherPixels`.

The three sky paths overlap deliberately so blue, lilac, and peach can blend without a visible ink divider. The face and body are base regions beneath soft ear, muzzle, and paw overlays. Regions are listed in paint order, and `compositing` specifies how an overlay should meet the base. Tiny stars, flower stamens, eye highlights, and open fur marks remain ink details rather than separate paint targets. Palette colours are suggestions for preview and can be changed without altering geometry.

`puppy-god-region-map.svg` contains the vector paths. `puppy-god-region-preview.png` shows a proposed coloured result with the source ink overlaid. `puppy-god-ink.png` is the transparent ink layer used by the app, and `puppy-god-owners.bin` stores one byte per source pixel: zero for unpaintable paper, otherwise the one-based index of a region in the JSON. Regenerate these files and the JSON with `Artwork/tools/build_puppy_region_map.py` using Pillow, NumPy, and OpenCV. The app loads the JSON palette and paths, uses the owner data for fast paint clipping, and displays the ink above the paint.
