import SwiftUI

@main
struct ColourbugApp: App {
    var body: some Scene {
        WindowGroup {
            FlowerPaintingCanvas()
                .preferredColorScheme(.light)
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
