import SwiftUI

@main
struct Baumio_App: App {
    init() {
        BaumioMetricSubscriber.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
