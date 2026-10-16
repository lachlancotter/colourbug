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

The app currently opens on a textured paper canvas. Drag to pan and pinch to zoom; the paper grain stays fixed to the sheet as it moves. The bundled paper image moves with a view transform, keeping pan and zoom smooth. The template, palette, and painting interaction described above are project goals, not implemented features yet.

The bundled texture is `Colourbug/Resources/WatercolourWhisper.png`.

## Run the app

From this directory, run:

```sh
./run-simulator.sh
```

This builds the app, installs it on the first available iPad simulator, and opens it. Xcode and an iOS Simulator runtime are required. If Xcode's license has not been accepted on this Mac, an administrator must first run:

```sh
sudo xcodebuild -license
```

The app entry point is `Colourbug/ColourbugApp.swift`. `Colourbug/PaperCanvas.swift` owns gestures, and `Colourbug/ImagePaperStrategy.swift` displays the textured sheet.
