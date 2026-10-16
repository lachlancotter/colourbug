# colourbug
A cosy paint-by-numbers game where every colour comes to life, one pencil stroke at a time.

## Run the hello world app

From this directory, run:

```sh
./run-simulator.sh
```

This builds the SwiftUI app, installs it on the first available iPad simulator, and opens it. Xcode and an iOS Simulator runtime are required. On this Mac, Xcode's license must first be accepted by an administrator:

```sh
sudo xcodebuild -license
```

All app code is in `Colourbug/ColourbugApp.swift`. The Xcode project contains only build settings; the workflow does not require the Xcode editor.
