import SwiftUI

@main
struct VoltApp: App {
    @State private var usageStore = UsageStore()
    @StateObject private var updateController = UpdateController()

    init() {
        VoltAssets.registerStatusBarIcon()
    }

    var body: some Scene {
        MenuBarExtra("Volt", image: VoltAssets.statusBarIconName.rawValue) {
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
