import SwiftUI

@main
struct MorningBriefApp: App {
    @StateObject private var store = BriefStore()

    var body: some Scene {
        // Title + systemImage is more reliable/visible than a custom Image-only label,
        // especially when the menu bar is crowded / notch overflow.
        MenuBarExtra {
            MenuBarPanelView()
                .environmentObject(store)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: store.statusIcon)
                Text("晨报")
                    .font(.system(size: 12, weight: .medium))
            }
            .accessibilityLabel("Morning Brief")
        }
        .menuBarExtraStyle(.window)
    }
}
