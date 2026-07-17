import AppKit
import SwiftUI

@main
struct VoltApp: App {
    @State private var usageStore = UsageStore()
    @StateObject private var updateController = UpdateController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(usageStore)
                .environmentObject(updateController)
        } label: {
            VoltLogoView(size: 18, template: true)
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
