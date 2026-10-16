import SwiftUI

@main
struct ColourbugApp: App {
    var body: some Scene {
        WindowGroup {
            PaperCanvas()
                .ignoresSafeArea()
                .preferredColorScheme(.light)
        }
    }
}
