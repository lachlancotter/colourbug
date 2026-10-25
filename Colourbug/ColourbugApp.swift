import SwiftUI

@main
struct ColourbugApp: App {
    var body: some Scene {
        WindowGroup {
            BlankPaintingCanvas()
                .preferredColorScheme(.light)
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
