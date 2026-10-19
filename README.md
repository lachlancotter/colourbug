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

The app opens on a textured paper canvas with the puppy god illustration. Its ink floats above the paint, while 102 mapped colour regions guide painting beneath it. The palette comes from the artwork data; scroll through its swatches and tap one to select a colour. Visible ink regions highlight when their colour is selected. The unlined sky zones share a paint group, allowing three sky colours to blend without a drawn divider; the puppy's fur colours also share a group for softer transitions. Drag one finger or an Apple Pencil to paint. Paint that wanders into another paint group or off the mapped artwork appears briefly, then fades away without changing paint already underneath. Fresh paint spreads subtly and stays workable for several seconds, while dry marks remain underneath new paint. A long stroke gradually uses up water and pigment, paper grain becomes clearer as pigment settles, and Pencil force and tilt make small changes to the brush. Use two fingers to pan or pinch to zoom; incidental finger contact does not interrupt a Pencil stroke. Paint and paper move together as one sheet. Persistence remains a project goal.

The bundled texture is `Colourbug/Resources/WatercolourWhisper.png`.

## Run the app

From this directory, run:

```sh
./run.sh
```

This builds the app, installs it on the first connected iPad, and opens it. In Conductor, use the **iPad** run script for the same action. The iPad must be connected, unlocked, and have Developer Mode enabled. To use an iPad simulator instead, run `./run.sh --simulator` (or `./run-simulator.sh`). Set `COLOURBUG_DEVICE_ID` to select a specific paired iPad. Xcode is required; the simulator option also needs an iOS Simulator runtime. If Xcode's license has not been accepted on this Mac, an administrator must first run:

```sh
sudo xcodebuild -license
```

The app entry point is `Colourbug/ColourbugApp.swift`. `Colourbug/PaperCanvas.swift` owns the palette, ink overlay, pan, and zoom; `Colourbug/PaintView.swift` owns painting input; `Colourbug/WatercolourRenderer.swift` simulates and draws paint; `Colourbug/PaintingTemplate.swift` loads the region map and palette from `Artwork/puppy-god-regions.json`; and `Colourbug/ImagePaperStrategy.swift` displays the textured sheet. See `Artwork/README.md` for the source illustration, region paths, and asset generator.
