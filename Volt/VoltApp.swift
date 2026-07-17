import SwiftUI

@main
struct VoltApp: App {
    @State private var usageStore = UsageStore()
    @StateObject private var updateController = UpdateController()

    var body: some Scene {
        MenuBarExtra("Volt", systemImage: "bolt.square.fill") {
            ContentView()
                .environment(usageStore)
                .environmentObject(updateController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(usageStore)
                .environmentObject(updateController)
        }
        .windowResizability(.contentSize)
    }
}
