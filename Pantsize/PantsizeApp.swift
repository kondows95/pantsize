import SwiftUI

@main
struct PantsizeApp: App {
    @State private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(projectStore)
        }
    }
}
