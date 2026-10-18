import SwiftUI

@main
struct ColourbugApp: App {
    var body: some Scene {
        WindowGroup {
            PaintingScreen()
                .preferredColorScheme(.light)
        }
    }
}
