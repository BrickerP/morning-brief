import SwiftUI

@main
struct MorningBriefApp: App {
    @StateObject private var appStore: Store<AppFeature.State, AppFeature.Action>

    init() {
        Self.sanitizeWorkingDirectory()
        let saved = UserDefaults.standard.string(forKey: PanelLens.storageKey)
        let lens = PanelLens(rawValue: saved ?? "") ?? .work
        let store = AppFeature.store()
        store.send(.setLens(lens))
        store.send(.work(.onAppear))
        _appStore = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup("Morning Brief") {
            RootWindowView(appStore: appStore)
                .tint(AppChrome.accent)
        }
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandMenu("视图") {
                Button("工作台账") { appStore.send(.setLens(.work)) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Agent") { appStore.send(.setLens(.agent)) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("晨报") { appStore.send(.setLens(.brief)) }
                    .keyboardShortcut("3", modifiers: .command)
            }
        }
    }

    private static func sanitizeWorkingDirectory() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MorningBrief", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let path = support.path
        _ = FileManager.default.changeCurrentDirectoryPath(path)
        setenv("PWD", path, 1)
        setenv("OLDPWD", path, 1)
        setenv("MORNINGBRIEF_SUPPORT", path, 1)
    }
}
