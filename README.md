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

The app currently opens to **only a full-screen textured sheet**. Paint on it with a finger or Apple Pencil using a single indigo pigment. It starts with the **paper bloom** candidate: a connected capillary front grows from the whole stroke, travels unevenly through the paper, and leaves pale violet washes and darker tide lines as it settles. Painting over an existing wash rewets a limited amount of pigment once per stroke; an overlapping bloom travels through denser colour without laying another tide line on top. Double-tap with two fingers to clear the sheet and switch to the saved **fluid** candidate, whose pigment stays mobile longer, forms stronger eddies, and curls beyond the end of a stroke. Double-tap with two fingers again to return to paper bloom. This isolated study is for comparing the feel of the paint before adding scene objects, colour selection, or progression back into the experience. Painting is reset when the canvas size changes or the app relaunches.

The earlier puppy god canvas and its region-based painting implementation remain in the source for comparison, but are not shown in the current app.

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

The app entry point is `Colourbug/ColourbugApp.swift`. `Colourbug/BlankPaintingCanvas.swift` displays the sheet and forwards touches; `Colourbug/PaintView.swift` owns painting input and curling flow; `Colourbug/WatercolourRenderer.swift` simulates and draws paint; `Colourbug/PaintingTemplate.swift` defines the continuous surface and loads the earlier region map; and `Colourbug/ImagePaperStrategy.swift` displays the texture. The previous region-based canvas remains in `Colourbug/PaperCanvas.swift`.
