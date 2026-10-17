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

The app currently opens on a textured paper canvas. Drag one finger or an Apple Pencil on the paper to paint with a blue watercolour brush. Fresh paint spreads subtly and dries in about 1–2 seconds; crossing wet marks shares pigment, while dry marks remain underneath new paint. A long stroke gradually uses up water and pigment, paper grain becomes clearer as pigment settles, and Pencil force and tilt make small changes to the brush. Use two fingers to pan or pinch to zoom; incidental finger contact does not interrupt a Pencil stroke. Paint and paper move together as one sheet. The template, palette, and persistence described above are project goals, not implemented features yet.

The bundled texture is `Colourbug/Resources/WatercolourWhisper.png`.

## Run the app

From this directory, run:

```sh
./run.sh
```

This builds the app, installs it on the first available paired iPad, and opens it. The iPad must be connected, unlocked, and have Developer Mode enabled. To use an iPad simulator instead, run `./run.sh --simulator` (or `./run-simulator.sh`). Set `COLOURBUG_DEVICE_ID` to select a specific paired iPad. Xcode is required; the simulator option also needs an iOS Simulator runtime. If Xcode's license has not been accepted on this Mac, an administrator must first run:

```sh
sudo xcodebuild -license
```

The app entry point is `Colourbug/ColourbugApp.swift`. `Colourbug/PaperCanvas.swift` owns pan and zoom, `Colourbug/PaintView.swift` owns painting input, `Colourbug/WatercolourRenderer.swift` simulates and draws paint, and `Colourbug/ImagePaperStrategy.swift` displays the textured sheet.
