import SwiftUI

@main
struct TouchDeckApp: App {
    var body: some Scene {
        WindowGroup {
            TouchDeckView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
