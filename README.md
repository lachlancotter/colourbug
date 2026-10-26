# Colourbug

## Project Aims

Colourbug is a cosy, tactile paint-by-numbers game for iPad, designed to make colouring a relaxing and delightful experience.

Unlike traditional colouring games, Colourbug invites players to choose colours and fill each area of a template by hand with Apple Pencil, using natural pencil strokes rather than simply tapping to apply colour.

Our goal is to create **a little happy place** — somewhere to slow down, unwind, and enjoy the simple pleasure of bringing beautiful illustrations to life.

**Guiding principles:**

- **Joy in every stroke.** Make the act of colouring deeply satisfying.
- **Relaxation over achievement.** No pressure, penalties, or unnecessary interruptions.
- **Gentle guidance, creative freedom.** Make colouring intuitive, forgiving, and expressive.
- **Delight in the details.** Create a warm, whimsical world full of little surprises.
- **The journey is the reward.** Celebrate the process of creating, not just completing pictures.

**Our North Star:** *Not a game to beat. A place to be.*

## Current state

The app currently opens to **one flower on a full-screen textured sheet**. Its transparent pen-and-ink overlay was isolated from the left side of the awakening linework study. The Water button replays the chosen reveal: a faint damp front moves through the flower before its ink emerges. The Pressed paper and Gathering ink reveal studies remain in the source as drafts, but are hidden from the current canvas. Four large, individually shadowed pigment shapes hover above the paper at the bottom, suggesting colours for the bell, leaf, stem, and bud. The selected pigment can flow and blend across region edges. Paint with a finger or Apple Pencil using the fluid watercolour candidate. Pigment stays mobile, forms eddies, and curls beyond the end of a stroke. Wet paint is visible on the whole paper, but paint beyond the flower silhouette fades clear as it dries. Once pigment covers about 82% of the flower silhouette, with at least 75% coverage of each of its four parts, deeper violet shadows gather under overlapping petals, saturated blue and gold light blooms across raised surfaces, and a soft cast shadow appears on the paper behind the whole flower. These passes sit beneath the ink and preserve the painted colour. Double-tap with two fingers to clear the paint and replay the water reveal. Painting is reset when the canvas size changes or the app relaunches. The tie-dye algorithm remains in the source as a saved candidate, but is no longer shown.

The earlier puppy god canvas and its region-based painting implementation remain in the source for comparison, but are not shown in the current app.

The bundled texture is `Colourbug/Resources/WatercolourWhisper.png`; the flower ink and its clipping silhouette are `Colourbug/Resources/StoryFlowerInk.png` and `Colourbug/Resources/StoryFlowerMask.png`.

## Run the app

From this directory, run:

```sh
./run.sh
```

This builds the app, installs it on the first connected iPad, and opens it. In Conductor, use the **iPad** run script for the same action. The iPad must be connected, unlocked, and have Developer Mode enabled. To use an iPad simulator instead, run `./run.sh --simulator` (or `./run-simulator.sh`). Set `COLOURBUG_DEVICE_ID` to select a specific paired iPad. Xcode is required; the simulator option also needs an iOS Simulator runtime. If Xcode's license has not been accepted on this Mac, an administrator must first run:

```sh
sudo xcodebuild -license
```

The app entry point is `Colourbug/ColourbugApp.swift`. `Colourbug/FlowerPaintingCanvas.swift` displays the sheet, flower and palette, and forwards touches; `Colourbug/FlowerRegions.swift` defines the four parts and suggested colours; `Colourbug/FlowerDepthArtwork.swift` defines the flower's light and shadow passes; `Colourbug/PaintView.swift` owns painting input and curling flow; `Colourbug/WatercolourRenderer.swift` simulates and draws paint and measures coverage; `Colourbug/PaintingTemplate.swift` defines the continuous surface and loads the earlier region map; and `Colourbug/ImagePaperStrategy.swift` displays the texture. The previous region-based canvas remains in `Colourbug/PaperCanvas.swift`.
